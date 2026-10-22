@tool
extends RefCounted
## The editor's own agent runtime. Uses Godot callbacks; never launches a process.

signal event(value: Dictionary)

static var Common: GDScript
static var ToolRegistry: GDScript

var owner: Node
var state = "idle"
var stats = {}
var _active = false
var _cancel: Dictionary = {}
var _hooks: Dictionary = {}
var _messages: Array = []
var _ledger: Dictionary = {}
var _checkpoint_failed = false

func _init(node: Node = null) -> void:
	owner = node

func stop() -> void:
	_cancel["cancelled"] = true

func run(options: Dictionary, hooks: Dictionary) -> Dictionary:
	if _active: return Common.failure("Agentul are deja o sarcină activă.", "busy")
	if not hooks.get("complete", Callable()).is_valid(): return Common.failure("Lipsește conexiunea modelului.", "invalid_harness")
	_active = true
	_cancel = options.get("cancel", {})
	_hooks = hooks
	_checkpoint_failed = false
	_messages = options.get("messages", [])
	_ledger = _restore_ledger(_messages)
	stats = {"version": 1, "id": str(options.get("id", Common.uid())), "steps": 0, "requests": 0, "retries": 0, "tool_calls": 0}
	var definitions: Array = options.get("tools", [])
	var registry = ToolRegistry.new(definitions, bool(options.get("deferred_tools", false)))
	if not registry.error.is_empty(): return _finish("failed", registry.error, "invalid_tools")
	var maximum = clampi(int(options.get("max_steps", 30)), 1, 100)
	var retries = clampi(int(options.get("max_retries", 2)), 0, 3)
	var metadata: Dictionary = options.get("metadata", {})
	var last_text = ""
	_transition("running")
	for step in range(maximum):
		if _checkpoint_failed: return _finish("failed", "Progresul agentului nu a putut fi salvat.", "checkpoint_failed", last_text)
		if _stopped(): return _finish("cancelled", "Oprit.", "cancelled", last_text)
		stats["steps"] = step + 1
		definitions = registry.active_definitions()
		var declared = {}
		for definition in definitions: declared[definition["name"]] = true
		var context: Array = _hooks["context"].call() if _hooks.get("context", Callable()).is_valid() else _messages.duplicate(true)
		var response: Dictionary = {}
		for attempt in range(retries + 1):
			if _stopped(): return _finish("cancelled", "Oprit.", "cancelled", last_text)
			_transition("running")
			if _checkpoint_failed: return _finish("failed", "Progresul agentului nu a putut fi salvat.", "checkpoint_failed", last_text)
			event.emit({"kind": "request_started", "step": step + 1, "maximum": maximum, "attempt": attempt + 1})
			if _stopped(): return _finish("cancelled", "Oprit.", "cancelled", last_text)
			stats["requests"] += 1
			var streamed = {"text": false}
			var delta = func(piece: String) -> void:
				if _stopped() or piece.is_empty(): return
				streamed["text"] = true
				event.emit({"kind": "text_delta", "text": _redact(piece)})
			response = await _hooks["complete"].call(context, definitions, _cancel, delta)
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
		_messages.append(message)
		last_text = str(message.get("content", ""))
		event.emit({"kind": "message", "message": message, "usage": response.get("usage", {}), "finish": response.get("finish", "")})
		_checkpoint()
		if calls.is_empty():
			var finish = str(response.get("finish", ""))
			if finish in ["length", "MAX_TOKENS", "max_tokens"]:
				return _finish("limited", "Răspuns oprit la limita modelului.", "output_limit", last_text)
			return _finish("completed", "Finalizat.", "", last_text)
		for call in calls:
			var result: Dictionary
			var executed = false
			var replayed = false
			var id = str(call["id"])
			var name = str(call["name"])
			if _stopped():
				result = Common.failure("Operație întreruptă înainte de execuție.", "cancelled")
			elif _checkpoint_failed:
				result = Common.failure("Operația a fost oprită deoarece progresul nu poate fi salvat.", "checkpoint_failed")
			elif not registry.catalog.has(name):
				result = Common.failure("Instrument indisponibil în această sesiune.", "tool_unavailable")
			elif not declared.has(name):
				result = Common.failure("Folosește tool_search sau tool_describe pentru a încărca instrumentul înainte de apel.", "tool_not_loaded")
			elif not ToolRegistry.validate(registry.catalog[name], call["arguments"]).get("ok", false):
				result = ToolRegistry.validate(registry.catalog[name], call["arguments"])
			elif _ledger.has(id):
				# Replayed provider IDs receive their recorded result without repeating a write.
				result = _ledger[id]["result"]
				replayed = true
			elif name in ["tool_search", "tool_describe"]:
				result = registry.discover(name, call["arguments"])
			elif not _hooks.get("execute", Callable()).is_valid():
				result = Common.failure("Execuția instrumentelor nu este disponibilă.", "tool_unavailable")
			else:
				_transition("waiting_tool")
				event.emit({"kind": "tool_started", "id": id, "name": name})
				if _stopped():
					result = Common.failure("Operație întreruptă înainte de execuție.", "cancelled")
				elif _checkpoint_failed:
					result = Common.failure("Operația a fost oprită deoarece progresul nu poate fi salvat.", "checkpoint_failed")
				else:
					executed = true
					stats["tool_calls"] += 1
					result = await _hooks["execute"].call(name, call["arguments"])
			var tool_message = _tool_message(call, result, metadata)
			_messages.append(tool_message)
			_ledger[id] = {"signature": _signature(call), "result": _result_from_message(tool_message)}
			event.emit({"kind": "tool_result", "id": id, "name": name, "arguments": _safe(call["arguments"]), "result": _ledger[id]["result"], "executed": executed, "replayed": replayed})
			_checkpoint()
		if _checkpoint_failed: return _finish("failed", "Progresul agentului nu a putut fi salvat.", "checkpoint_failed", last_text)
		if _stopped(): return _finish("cancelled", "Oprit.", "cancelled", last_text)
	return _finish("limited", "Limita de pași a fost atinsă. Verifică rezultatele înainte de continuare.", "step_limit", last_text)

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

func _tool_message(call: Dictionary, result: Dictionary, metadata: Dictionary) -> Dictionary:
	var body = result.duplicate()
	body.erase("images")
	var serialized = _redact(JSON.stringify(Common.json_safe(body)))
	if serialized.length() > 24000: serialized = JSON.stringify({"truncated": true, "preview": serialized.left(22000), "next": "Request a narrower inspection or file range."})
	return {"id": Common.uid(), "role": "tool", "tool_call_id": call["id"], "tool_name": call["name"], "content": serialized, "attachments": _safe(result.get("images", [])), "turn_id": metadata.get("turn_id", stats["id"])}

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
	return {"id": Common.uid(), "role": "tool", "tool_call_id": id, "tool_name": name, "content": JSON.stringify(Common.failure("Operație întreruptă înainte de confirmarea rezultatului. Verifică starea proiectului înainte de continuare.", "cancelled"))}

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
	_active = false
	event.emit({"kind": "settled", "result": result})
	return result
