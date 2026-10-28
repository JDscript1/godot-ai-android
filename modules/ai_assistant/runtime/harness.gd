@tool
extends RefCounted
## The editor's own agent runtime. Uses Godot callbacks; never launches a process.

signal event(value: Dictionary)

static var Common: GDScript
static var ToolRegistry: GDScript

const TOOL_RESULT_LIMIT = 24000
const TOOL_BATCH_LIMIT = 48000
# Reserve a compact JSON contract for every remaining call (at most 64 per batch).
const TOOL_RESULT_RESERVE = 512

var owner: Node
var state = "idle"
var stats = {}
var _tool_budget = TOOL_BATCH_LIMIT
var _active = false
var _cancel: Dictionary = {}
var _hooks: Dictionary = {}
var _messages: Array = []
var _ledger: Dictionary = {}
var _effects: Dictionary = {}
var _deduplicate_tools: Array = []
var _turn = ""
var _checkpoint_failed = false
var _started_msec = 0
var _continuations = 0
var _continuation_hint = ""
var _repair_hint = ""
var _inspection_repeats = {}

func _init(node: Node = null) -> void:
	owner = node

func stop() -> void:
	_cancel["cancelled"] = true

func run(options: Dictionary, hooks: Dictionary) -> Dictionary:
	if _active: return Common.failure("Agentul are deja o sarcină activă.", "busy")
	if not hooks.get("complete", Callable()).is_valid(): return Common.failure("Lipsește conexiunea modelului.", "invalid_harness")
	_active = true
	_started_msec = Time.get_ticks_msec()
	_cancel = options.get("cancel", {})
	_hooks = hooks
	_checkpoint_failed = false
	_messages = options.get("messages", [])
	_ledger = _restore_ledger(_messages)
	_turn = str(options.get("metadata", {}).get("turn_id", options.get("id", "")))
	_deduplicate_tools = options.get("deduplicate_tools", [])
	_effects = _restore_effects(_messages)
	stats = {"version": 1, "id": str(options.get("id", Common.uid())), "steps": 0, "requests": 0, "retries": 0, "tool_calls": 0, "reused_calls": 0, "continuations": 0}
	_continuations = 0
	_continuation_hint = ""
	_repair_hint = ""
	_inspection_repeats.clear()
	var definitions: Array = options.get("tools", [])
	var registry = ToolRegistry.new(definitions, bool(options.get("deferred_tools", false)))
	if not registry.error.is_empty(): return _finish("failed", registry.error, "invalid_tools")
	registry.restore(_messages)
	# Normal editor runs have no step ceiling. Only isolated evaluations opt in.
	var maximum = maxi(0, int(options.get("max_steps", 0)))
	var retries = clampi(int(options.get("max_retries", 2)), 0, 3)
	var auto_continue = clampi(int(options.get("auto_continue", 0)), 0, 5)
	var metadata: Dictionary = options.get("metadata", {})
	var last_text = ""
	var empty_rounds = 0
	var repeated_result = ""
	var repeated_count = 0
	_transition("running")
	var step = 0
	while maximum == 0 or step < maximum:
		if _checkpoint_failed: return _finish("failed", "Progresul agentului nu a putut fi salvat.", "checkpoint_failed", last_text)
		if _stopped(): return _finish("cancelled", "Oprit.", "cancelled", last_text)
		# Cached/local callbacks can finish synchronously; keep Stop and the UI responsive.
		if step > 0 and is_instance_valid(owner):
			await owner.get_tree().process_frame
			if _stopped(): return _finish("cancelled", "Oprit.", "cancelled", last_text)
		step += 1
		stats["steps"] = step
		_tool_budget = TOOL_BATCH_LIMIT
		var continuation_hint = _continuation_hint
		_continuation_hint = ""
		definitions = registry.active_definitions()
		var declared = {}
		for definition in definitions: declared[definition["name"]] = true
		var context: Array = _hooks["context"].call() if _hooks.get("context", Callable()).is_valid() else _messages.duplicate(true)
		if not continuation_hint.is_empty(): context.append({"role": "user", "content": continuation_hint})
		if not _repair_hint.is_empty():
			context.append({"role": "system", "content": _repair_hint})
			_repair_hint = ""
		var response: Dictionary = {}
		var response_msec = 0
		for attempt in range(retries + 1):
			if _stopped(): return _finish("cancelled", "Oprit.", "cancelled", last_text)
			_transition("running")
			if _checkpoint_failed: return _finish("failed", "Progresul agentului nu a putut fi salvat.", "checkpoint_failed", last_text)
			event.emit({"kind": "request_started", "step": step, "maximum": maximum, "attempt": attempt + 1, "continuation": not continuation_hint.is_empty(), "continuation_attempt": _continuations, "continuation_max": auto_continue})
			if _stopped(): return _finish("cancelled", "Oprit.", "cancelled", last_text)
			stats["requests"] += 1
			var streamed = {"text": false}
			var delta = func(piece: String) -> void:
				if _stopped() or piece.is_empty(): return
				streamed["text"] = true
				event.emit({"kind": "text_delta", "text": _redact(piece)})
			var request_started_msec = Time.get_ticks_msec()
			response = await _hooks["complete"].call(context, definitions, _cancel, delta)
			response_msec = Time.get_ticks_msec() - request_started_msec
			if _stopped(): return _finish("cancelled", "Oprit.", "cancelled", last_text)
			if response.get("ok", false): break
			# Retry only model requests, before visible text. Tools are never retried.
			if streamed["text"] or attempt >= retries or not _transient(response):
				return _finish("failed", str(response.get("error", "Cererea a eșuat.")), str(response.get("code", "provider_error")), last_text)
			stats["retries"] += 1
			_transition("retrying")
			event.emit({"kind": "retry", "attempt": attempt + 1})
			if not await _backoff(_retry_delay(response, attempt, int(options.get("retry_delay_ms", 400)))):
				return _finish("cancelled", "Oprit.", "cancelled", last_text)
		var validation = _validate_response(response)
		if not validation.is_empty(): return _finish("failed", validation, "invalid_response", last_text)
		var calls: Array = response.get("calls", [])
		var message: Dictionary = _safe(response["message"])
		message.merge(metadata, true)
		message["role"] = "assistant"
		message["id"] = Common.uid()
		var continuation_round = not continuation_hint.is_empty()
		var merged = false
		var previous: Dictionary = _messages[-1] if not _messages.is_empty() else {}
		if continuation_round and previous.get("role") == "assistant" and previous.get("tool_calls", []).is_empty():
			previous["content"] = str(previous.get("content", "")) + str(message.get("content", ""))
			if not str(message.get("reasoning_content", "")).is_empty(): previous["reasoning_content"] = str(previous.get("reasoning_content", "")) + str(message["reasoning_content"])
			for key in ["provider_items", "provider_blocks"]:
				var addition: Variant = message.get(key)
				if not addition is Array or addition.is_empty(): continue
				var combined: Array = previous.get(key, []) if previous.get(key, []) is Array else []
				combined.append_array(addition)
				previous[key] = combined
			if not calls.is_empty(): previous["tool_calls"] = calls
			# A truncated answer keeps one assistant record and one chat bubble.
			message = previous
			merged = true
		else:
			_messages.append(message)
		last_text = str(message.get("content", ""))
		event.emit({"kind": "message", "message": message, "usage": response.get("usage", {}), "finish": response.get("finish", ""), "duration_ms": response_msec, "continuation": continuation_round, "merged": merged})
		_checkpoint()
		if calls.is_empty():
			var finish = str(response.get("finish", ""))
			if finish in ["length", "MAX_TOKENS", "max_tokens"]:
				if _continuations < auto_continue:
					_continuations += 1
					stats["continuations"] = _continuations
					_continuation_hint = "The previous answer stopped at the output token limit. Continue exactly where it stopped, without repeating anything already written and without a preamble. Complete any unfinished sentence, code block, list or tool call."
					event.emit({"kind": "auto_continue", "attempt": _continuations, "maximum": auto_continue})
					continue
				var limit_message = "Răspuns oprit la limita modelului." if _continuations == 0 else "Răspuns oprit la limita modelului după %d continuări." % _continuations
				return _finish("limited", limit_message, "output_limit", last_text)
			if _hooks.get("needs_continuation", Callable()).is_valid() and _hooks["needs_continuation"].call():
				empty_rounds += 1
				if empty_rounds >= 3: return _finish("limited", "Agentul nu a făcut progrese în ultimele trei încercări. Verifică pașii rămași înainte de reluare.", "no_progress", last_text)
				event.emit({"kind": "plan_continuation", "step": step})
				continue
			if _hooks.get("blocked_reason", Callable()).is_valid():
				var reason = str(_hooks["blocked_reason"].call())
				if not reason.is_empty(): return _finish("blocked", "Sarcină blocată. " + reason, "task_blocked", last_text)
			if _hooks.get("completion_problem", Callable()).is_valid():
				var problem = str(_hooks["completion_problem"].call())
				if not problem.is_empty():
					empty_rounds += 1
					if empty_rounds >= 3: return _finish("blocked", problem, "verification_required", last_text)
					_repair_hint = "Completion has not been verified. " + problem + " Continue with the required checks or report the concrete blocker; do not repeat a success claim."
					event.emit({"kind": "verification_required", "message": problem})
					continue
			return _finish("completed", "Finalizat.", "", last_text)
		empty_rounds = 0
		var stalled = false
		var remaining_calls = calls.size()
		for call in calls:
			var call_started_msec = Time.get_ticks_msec()
			var result: Dictionary
			var executed = false
			var replayed = false
			var id = str(call["id"])
			var name = str(call["name"])
			if _stopped():
				result = Common.failure("Operație întreruptă înainte de execuție.", "cancelled")
			elif stalled:
				result = Common.failure("Operație amânată deoarece agentul repetă aceeași încercare fără progres.", "no_progress")
			elif _checkpoint_failed:
				result = Common.failure("Operația a fost oprită deoarece progresul nu poate fi salvat.", "checkpoint_failed")
			elif not registry.catalog.has(name):
				result = Common.failure("Instrument indisponibil în această sesiune.", "tool_unavailable")
			elif not declared.has(name):
				result = Common.failure("Folosește tool_search sau tool_describe pentru a încărca instrumentul înainte de apel.", "tool_not_loaded")
			elif not ToolRegistry.validate(registry.catalog[name], call["arguments"]).get("ok", false):
				result = ToolRegistry.validate(registry.catalog[name], call["arguments"])
			elif _ledger.has(id) and str(_ledger[id]["result"].get("code", "")) not in ["plan_required", "plan_read_only", "tool_not_loaded"]:
				# Replayed provider IDs receive their recorded result without repeating a write.
				result = _ledger[id]["result"]
				replayed = true
			elif _effects.has(_signature(call)):
				# Provider call IDs are not idempotency keys for paid/external operations.
				result = _effects[_signature(call)].duplicate(true)
				replayed = true
			elif name in ["tool_search", "tool_describe"]:
				event.emit({"kind": "tool_started", "id": id, "name": name, "arguments": _safe(call["arguments"])})
				result = registry.discover(name, call["arguments"])
			elif not _hooks.get("execute", Callable()).is_valid():
				result = Common.failure("Execuția instrumentelor nu este disponibilă.", "tool_unavailable")
			else:
				_transition("waiting_tool")
				event.emit({"kind": "tool_started", "id": id, "name": name, "arguments": _safe(call["arguments"])})
				if _stopped():
					result = Common.failure("Operație întreruptă înainte de execuție.", "cancelled")
				elif _checkpoint_failed:
					result = Common.failure("Operația a fost oprită deoarece progresul nu poate fi salvat.", "checkpoint_failed")
				else:
					executed = true
					stats["tool_calls"] += 1
					# Review may narrow a write, but must never change the provider call's identity.
					result = await _hooks["execute"].call(name, call["arguments"].duplicate(true))
			var recovery = _recovery_guidance(name, result)
			if not recovery.is_empty(): result = result.merged({"recovery": recovery}, true)
			if executed and registry.catalog.get(name, {}).get("risk") != "read" and result.get("ok", false) and name not in ["task_update", "plan_ask"]:
				_inspection_repeats.clear()
			if executed and name in ["godot_files", "godot_read_file", "godot_read_range", "godot_describe", "godot_project_map", "godot_symbols", "godot_search_code"] and result.get("ok", false):
				var fingerprint = _signature(call) + JSON.stringify(result.get("result")).sha256_text()
				if _inspection_repeats.size() >= 100 and not _inspection_repeats.has(fingerprint): _inspection_repeats.erase(_inspection_repeats.keys()[0])
				_inspection_repeats[fingerprint] = int(_inspection_repeats.get(fingerprint, 0)) + 1
				if _inspection_repeats[fingerprint] >= 3:
					_repair_hint = "The same inspection returned the same facts at least three times without a project change. Change the query or tool, use godot_diagnostics/project_map, test a concrete hypothesis, revise the plan or report a blocker. Further identical reads do not establish progress."
					event.emit({"kind": "recovery", "tool": name, "reason": "unchanged_inspection", "count": _inspection_repeats[fingerprint]})
					if _inspection_repeats[fingerprint] >= 6: stalled = true
			var tool_message = _tool_message(call, result, metadata, remaining_calls)
			remaining_calls -= 1
			tool_message["execution_started"] = executed
			_messages.append(tool_message)
			_ledger[id] = {"signature": _signature(call), "result": _result_from_message(tool_message)}
			if replayed: stats["reused_calls"] += 1
			if executed and (_deduplicate_tools.has(name) or result.get("code") == "permission_denied") and _remember_effect(result): _effects[_signature(call)] = _ledger[id]["result"]
			if not result.get("ok", false) or replayed or name == "task_update":
				var fingerprint = _signature(call) + ":" + str(result.get("code", "ok"))
				repeated_count = repeated_count + 1 if fingerprint == repeated_result else 1
				repeated_result = fingerprint
				stalled = stalled or repeated_count >= 3
			else:
				repeated_count = 0
				repeated_result = ""
			event.emit({"kind": "tool_result", "id": id, "name": name, "arguments": _safe(call["arguments"]), "result": _ledger[id]["result"], "executed": executed, "replayed": replayed, "duration_ms": Time.get_ticks_msec() - call_started_msec})
			_checkpoint()
		if _checkpoint_failed: return _finish("failed", "Progresul agentului nu a putut fi salvat.", "checkpoint_failed", last_text)
		if _stopped(): return _finish("cancelled", "Oprit.", "cancelled", last_text)
		if stalled: return _finish("limited", "Aceeași operație se repetă fără progres. Rezultatele au fost păstrate; verifică eroarea înainte de reluare.", "no_progress", last_text)
	return _finish("limited", "Limita explicită a probei a fost atinsă.", "step_limit", last_text)

func _validate_response(response: Dictionary) -> String:
	if not response.get("message") is Dictionary or response["message"].get("role") != "assistant": return "Răspuns de model invalid."
	if not response.get("calls", []) is Array: return "Lista apelurilor nu este validă."
	var calls: Array = response.get("calls", [])
	if calls.size() > 64: return "Modelul a solicitat prea multe operații într-un singur pas."
	if response["message"].get("tool_calls", []) != calls: return "Apelurile nu corespund mesajului modelului."
	var ids = {}
	for call in calls:
		if not call is Dictionary or not call.get("arguments") is Dictionary: return "Argumente de instrument invalide."
		var id = str(call.get("id", ""))
		if id.is_empty() or str(call.get("name", "")).is_empty() or ids.has(id): return "Identificator de apel lipsă sau duplicat."
		ids[id] = true
		if _ledger.has(id) and _ledger[id]["signature"] != _signature(call): return "Un identificator de apel a fost reutilizat pentru altă operație."
	return ""

static func _recovery_guidance(name: String, result: Dictionary) -> Dictionary:
	var code = str(result.get("code", ""))
	if result.get("result") is Dictionary and result["result"].get("syntax") is Dictionary and not result["result"]["syntax"].get("valid", true):
		return {"category": "syntax", "next": ["godot_script_diagnostics", "godot_read_range"], "action": "Inspect the reported source and apply a minimal repair, then validate again. The file write alone did not verify syntax."}
	if result.get("ok", false): return {}
	var recovery = {"category": "inspect_failure", "retry_tool_automatically": false, "action": "Inspect the concrete error and choose a different hypothesis before repeating the operation."}
	match code:
		"tool_not_loaded", "tool_unavailable", "unknown_tool": recovery.merge({"category": "capability", "next": ["tool_describe", "tool_search"], "action": "Discover the actual permitted tool/schema; do not invent an unavailable capability."}, true)
		"stale_handle": recovery.merge({"category": "stale_reference", "next": ["godot_project", "godot_scene_tree"], "action": "Obtain fresh handles; never reuse the stale object reference."}, true)
		"patch_conflict", "unsaved_changes": recovery.merge({"category": "version_conflict", "next": ["godot_read_range"], "action": "Re-read the current source and hash. Preserve user edits; do not overwrite or force an old patch."}, true)
		"restore_conflict", "recovery_required", "recovery_failed", "journal_failed": recovery.merge({"category": "recovery", "next": ["godot_changes_status"], "action": "Inspect actual file hashes and the existing recovery journal. Preserve later edits. Recover the existing set, never blindly reapply it or claim rollback succeeded without checking the result."}, true)
		"invalid_path", "invalid_file", "scene_not_found", "directory_create_failed": recovery.merge({"category": "project_structure", "next": ["godot_project_map", "godot_files"], "action": "Inspect existing paths and dependencies; reuse the actual scene/file path instead of creating another project tree."}, true)
		"permission_denied", "cancelled": recovery.merge({"category": "user_boundary", "action": "Respect the refusal or Stop. Do not bypass it through another tool or repeat the same approval."}, true)
		"submission_unknown", "conversion_unknown": recovery.merge({"category": "uncertain_side_effect", "next": ["asset_status", "asset_wait"], "action": "Recover the existing job and provider ID. Do not submit or charge again."}, true)
		"invalid_arguments", "invalid_method", "invalid_property": recovery.merge({"category": "schema", "next": ["tool_describe", "godot_describe"], "action": "Inspect the real schema/member type before correcting the arguments."}, true)
		"criterion_failed", "evidence_stale", "evidence_scope", "verification_required": recovery.merge({"category": "verification", "action": "Keep the original criterion; gather fresh scoped evidence, repair a failed check and verify again."}, true)
	return recovery.merged({"tool": name})

func _tool_message(call: Dictionary, result: Dictionary, metadata: Dictionary, remaining_calls: int = 1) -> Dictionary:
	var body = result.duplicate()
	body.erase("images")
	var serialized = _redact(JSON.stringify(Common.json_safe(body)))
	var limit = mini(TOOL_RESULT_LIMIT, _tool_budget - TOOL_RESULT_RESERVE * maxi(0, remaining_calls - 1))
	if serialized.length() > limit: serialized = _bounded_result(serialized, limit)
	_tool_budget = maxi(0, _tool_budget - serialized.length())
	return {"id": Common.uid(), "role": "tool", "tool_call_id": call["id"], "tool_name": call["name"], "content": serialized, "attachments": _safe(result.get("images", [])), "turn_id": metadata.get("turn_id", stats["id"])}

static func _bounded_result(serialized: String, limit: int = TOOL_RESULT_LIMIT) -> String:
	# Keep the executor contract when only the model's text view needs shortening.
	# The panel's detailed journal retains the complete, separately sanitized result.
	var details_limit = mini(8000, maxi(mini(limit - 32, 1024), limit / 3))
	var body: Dictionary = Common.parse_json(serialized)
	var summary = {"truncated": true, "original_characters": serialized.length()}
	for key in ["ok", "code", "error", "files"]:
		if not body.has(key): continue
		var value: Variant = body[key]
		if value is String:
			value = value.left(mini(1200, limit / 4))
			while not value.is_empty() and JSON.stringify(summary.merged({key: value})).length() > details_limit: value = value.left(value.length() / 2)
		elif value is Array: value = value.filter(func(item: Variant) -> bool: return item is String and item.length() <= 256).slice(0, 6)
		var candidate = summary.merged({key: value})
		if JSON.stringify(candidate).length() <= details_limit: summary = candidate
	if body.get("approval") is Dictionary:
		var candidate = summary.merged({"approval": body["approval"]})
		# Leave room for the tool's status, artifact identity and syntax verdict too.
		if JSON.stringify(candidate).length() > details_limit / 2:
			var compact = {"partial": body["approval"].get("partial", false), "truncated": true}
			for key in ["selected_hunks", "rejected_hunks"]:
				if body["approval"].get(key) is Array: compact[key + "_count"] = body["approval"][key].size()
			candidate = summary.merged({"approval": compact})
		if JSON.stringify(candidate).length() <= details_limit: summary = candidate
	if body.get("result") is Dictionary:
		var details = {}
		var syntax: Variant = body["result"].get("syntax")
		if syntax is Dictionary:
			var compact = {"valid": syntax.get("valid"), "truncated": true}
			for key in ["errors", "warnings"]:
				if syntax.get(key) is Array: compact[key + "_count"] = syntax[key].size()
			if JSON.stringify(summary.merged({"result": {"syntax": compact}})).length() <= details_limit: details["syntax"] = compact
		for key in ["id", "job", "task_id", "external_id", "status", "exit_code", "file", "imported_path", "path", "name", "class", "handle", "reference", "quality", "progress", "cost_usd", "format", "directory", "scene", "saved", "offset", "next_offset", "total", "truncated", "total_lines", "next_line", "syntax"]:
			if not body["result"].has(key): continue
			var value: Variant = body["result"][key]
			if JSON.stringify(value).length() > 2048: continue
			var candidate = details.merged({key: value}, true)
			if JSON.stringify(summary.merged({"result": candidate})).length() <= details_limit: details = candidate
		for key in ["matches", "symbols", "diagnostics"]:
			var items: Variant = body["result"].get(key)
			if not items is Array: continue
			var kept = []
			for item in items:
				if JSON.stringify(item).length() > 512: continue
				kept.append(item)
				if kept.size() >= 3: break
			var candidate = details.merged({key + "_count": items.size()})
			if not kept.is_empty(): candidate[key] = kept
			if JSON.stringify(summary.merged({"result": candidate})).length() <= details_limit: details = candidate
		if not details.is_empty(): summary["result"] = details
	for key in ["verification_evidence", "recovery"]:
		if not body.get(key) is Dictionary: continue
		var candidate = summary.merged({key: body[key]})
		if JSON.stringify(candidate).length() <= details_limit: summary = candidate
	for key in ["tail", "next"]:
		var value = serialized.right(mini(2000, limit / 6)) if key == "tail" else "Request a narrower inspection, a reflection page or a file range; omitted fields do not prove absence."
		var candidate = summary.merged({key: value})
		if JSON.stringify(candidate).length() <= details_limit: summary = candidate
	var preview_length = mini(serialized.length(), mini(12000, maxi(0, limit - 4000)))
	while true:
		summary["preview"] = serialized.left(preview_length)
		var encoded = JSON.stringify(summary)
		if encoded.length() <= limit: return encoded
		if preview_length == 0: return JSON.stringify(summary) # Summary itself already fits details_limit.
		preview_length /= 2
	return ""

func _restore_ledger(messages: Array) -> Dictionary:
	var pending = {}
	var ledger = {}
	for message in messages:
		for call in message.get("tool_calls", []):
			if call is Dictionary and call.get("arguments") is Dictionary: pending[str(call.get("id", ""))] = _signature(call)
		if message.get("role") == "tool":
			var id = str(message.get("tool_call_id", ""))
			if pending.has(id): ledger[id] = {"signature": pending[id], "result": _result_from_message(message)}
	return ledger

func _restore_effects(messages: Array) -> Dictionary:
	var calls = {}
	var effects = {}
	if _turn.is_empty(): return effects
	for message in messages:
		if message.get("role") == "assistant" and message.get("turn_id", "") == _turn:
			for call in message.get("tool_calls", []):
				if call is Dictionary: calls[str(call.get("id", ""))] = call
		if message.get("role") != "tool" or not calls.has(str(message.get("tool_call_id", ""))): continue
		var result = _result_from_message(message)
		var call: Dictionary = calls[str(message["tool_call_id"])]
		if (_deduplicate_tools.has(str(call.get("name", ""))) or result.get("code") == "permission_denied") and (message.get("execution_started", result.get("ok", false)) or message.get("execution_unknown", false)) and _remember_effect(result):
			effects[_signature(calls[str(message["tool_call_id"])])] = result
	return effects

static func _remember_effect(result: Dictionary) -> bool:
	# A plan or missing credential can be fixed before submission; a user refusal persists for this turn.
	return str(result.get("code", "")) not in ["plan_required", "plan_read_only", "invalid_arguments", "missing_credentials", "tool_unavailable", "tool_not_loaded"]

static func repair_messages(messages: Array) -> Array:
	var repaired = []
	var pending = {}
	for message in messages:
		if message.get("role") != "tool":
			for id in pending: repaired.append(_interrupted_result(id, pending[id]))
			pending.clear()
		repaired.append(message)
		for call in message.get("tool_calls", []): pending[call["id"]] = call["name"]
		if message.get("role") == "tool": pending.erase(message.get("tool_call_id", ""))
	for id in pending: repaired.append(_interrupted_result(id, pending[id]))
	return repaired

static func _interrupted_result(id: String, name: String) -> Dictionary:
	return {"id": Common.uid(), "role": "tool", "tool_call_id": id, "tool_name": name, "execution_unknown": true, "content": JSON.stringify(Common.failure("Operație întreruptă înainte de confirmarea rezultatului. Verifică starea proiectului înainte de continuare.", "cancelled"))}

static func _result_from_message(message: Dictionary) -> Dictionary:
	var result: Variant = Common.parse_json(str(message.get("content", "")))
	if not result is Dictionary: result = Common.success(str(message.get("content", "")))
	if not message.get("attachments", []).is_empty(): result["images"] = message["attachments"]
	return result

static func _signature(call: Dictionary) -> String:
	# JSON's sorted dictionary keys make argument key order irrelevant.
	return str(call.get("name", "")) + ":" + JSON.stringify(call.get("arguments", {}), "", true).sha256_text()

static func _transient(response: Dictionary) -> bool:
	return int(response.get("status", 0)) in [408, 429, 500, 502, 503, 504] or response.get("code") in ["connection_failed", "timeout", "interrupted", "incomplete_stream"]

static func _retry_delay(response: Dictionary, attempt: int, base: int) -> int:
	var delay = clampi(base, 0, 5000) * (1 << attempt)
	for key in response.get("headers", {}):
		if str(key).to_lower() == "retry-after": delay = maxi(delay, int(float(response["headers"][key]) * 1000.0))
	return clampi(delay, 0, 30000)

func _backoff(milliseconds: int) -> bool:
	var deadline = Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		if _stopped(): return false
		if not is_instance_valid(owner) or not owner.is_inside_tree(): return false
		await owner.get_tree().process_frame
	return not _stopped()

func _stopped() -> bool:
	return _cancel.get("cancelled", false) or (owner != null and (not is_instance_valid(owner) or not owner.is_inside_tree()))

func _redact(value: String) -> String:
	return str(_hooks["redact"].call(value)) if _hooks.get("redact", Callable()).is_valid() else value

func _safe(value: Variant) -> Variant:
	return Common.parse_json(_redact(JSON.stringify(value)))

func _checkpoint() -> void:
	if _hooks.get("checkpoint", Callable()).is_valid():
		var saved: Variant = _hooks["checkpoint"].call(stats.merged({"status": state}))
		if saved is bool and not saved: _checkpoint_failed = true

func _transition(next: String) -> void:
	state = next
	event.emit({"kind": "state", "state": state})
	_checkpoint()

func _finish(status: String, message: String, code: String, text: String = "") -> Dictionary:
	stats["duration_ms"] = Time.get_ticks_msec() - _started_msec
	if status == "cancelled":
		message = {"new_request": "Trec la cererea nouă.", "user": "Oprit la cererea ta."}.get(str(_cancel.get("reason", "")), "Execuția s-a întrerupt.")
		code = "redirected" if _cancel.get("reason") == "new_request" else code
	if _checkpoint_failed: status = "failed"
	state = status
	_checkpoint()
	if _checkpoint_failed:
		state = "failed"
		status = "failed"
		message = "Progresul agentului nu a putut fi salvat. Verifică rezultatele înainte de continuare."
		code = "checkpoint_failed"
	var result = stats.merged({"ok": status == "completed", "status": status, "message": _redact(message), "code": code, "text": _redact(text)})
	# Drop host callables and images after settling; avoid a panel -> harness -> panel cycle.
	_hooks = {}
	_messages = []
	_ledger = {}
	_effects = {}
	_deduplicate_tools = []
	_active = false
	event.emit({"kind": "settled", "result": result})
	return result
