@tool
extends RefCounted
## Evidence is issued by the executor, not supplied as a model-written success claim.
static var Common: GDScript
static var Experiments: GDScript
var revision = 0
var criteria: Array = []
var evidence = {}
var passed = {}
## Criteria are stable for the lifetime of a user task. New requirements may be
## appended, but the model cannot replace, weaken or remove an existing one.
var declaration = 0
var _declared_at = {}

static func criteria_schema() -> Dictionary:
	return {"type": "array", "maxItems": 24, "items": Common.schema({"id": {"type": "string", "minLength": 1, "maxLength": 48}, "description": {"type": "string", "minLength": 1, "maxLength": 600}, "kind": {"type": "string", "enum": ["inspection", "syntax", "runtime", "interaction", "visual"]}, "paths": {"type": "array", "maxItems": 20, "items": Common.string_field()}, "check": Common.schema({"pointer": {"type": "string", "maxLength": 300, "description": "JSON pointer inside a tool's result, e.g. /properties/score."}, "op": {"type": "string", "enum": ["eq", "ne", "gt", "gte", "lt", "lte", "contains", "nonempty"]}, "expected": {}}, ["pointer", "op"])}, ["id", "description", "kind"])}

static func definition() -> Dictionary:
	return Common.tool("task_check", "Verify one declared task_update criterion against real verification_evidence IDs returned by tools. Checks kind, current project revision, file hashes and the declared JSON-pointer assertion. Never invent an evidence ID. Re-run affected checks after changes. Runtime/interaction criteria require a measured check, not a written success claim.", {"criterion": Common.string_field(), "evidence": {"type": "array", "minItems": 1, "maxItems": 20, "items": Common.string_field()}}, ["criterion", "evidence"])

func reset() -> void:
	revision = 0
	criteria.clear()
	evidence.clear()
	passed.clear()
	declaration = 0
	_declared_at.clear()

## Check a criteria update against the protected set without changing any state.
## The panel uses this before planner.update so a rejected update cannot be
## partially applied.
func prevalidate(items: Array) -> Dictionary:
	var plan = _plan(items)
	if not plan.get("ok", false): return plan
	return Common.success({"criteria": plan["criteria"].size(), "added": plan["added"].duplicate()})

func declare(items: Array) -> Dictionary:
	var plan = _plan(items)
	if not plan.get("ok", false): return plan
	var additions: Array = plan["added"]
	if additions.is_empty(): return Common.success({"criteria": criteria.size()})
	declaration += 1
	for id in additions: _declared_at[str(id)] = declaration
	criteria = plan["criteria"]
	return Common.success({"criteria": criteria.size(), "added": additions.duplicate()})

func _plan(items: Array) -> Dictionary:
	if items.size() > 24: return Common.failure("Cel mult 24 de criterii.", "invalid_criteria")
	var identifiers = {}
	var incoming = []
	for item in items:
		if not item is Dictionary or str(item.get("id", "")).is_empty() or identifiers.has(str(item["id"])): return Common.failure("Criteriile necesită identificatori unici.", "invalid_criteria")
		if item.get("kind") not in ["inspection", "syntax", "runtime", "interaction", "visual"] or not item.get("description") is String or item["description"].strip_edges().is_empty() or not item.get("paths", []) is Array: return Common.failure("Format de criteriu invalid.", "invalid_criteria")
		identifiers[str(item["id"])] = true
		if item.get("kind") in ["runtime", "interaction"] and not item.get("check") is Dictionary: return Common.failure("Criteriul comportamental necesită check cu valoare măsurată.", "invalid_criteria")
		var criterion = {"id": str(item["id"]), "description": item["description"], "kind": str(item["kind"]), "paths": []}
		if item.has("check"):
			if not item["check"] is Dictionary: return Common.failure("Condiție de verificare invalidă.", "invalid_criteria")
			var check: Dictionary = item["check"]
			var operation = str(check.get("op", ""))
			if not (check.get("pointer") is String) or operation not in ["eq", "ne", "gt", "gte", "lt", "lte", "contains", "nonempty"] or (operation != "nonempty" and not check.has("expected")): return Common.failure("Condiție de verificare invalidă.", "invalid_criteria")
			criterion["check"] = check.duplicate(true)
		for path in item.get("paths", []):
			var normalized = Common.project_path(str(path))
			if normalized.is_empty(): return Common.failure("Cale de criteriu invalidă.", "invalid_criteria")
			criterion["paths"].append(normalized)
		incoming.append(criterion)
	var existing = {}
	for criterion in criteria: existing[str(criterion["id"])] = true
	var supplied = {}
	for criterion in incoming: supplied[str(criterion["id"])] = criterion
	var ordered = []
	var additions = []
	for criterion in criteria:
		var id = str(criterion["id"])
		if not supplied.has(id): return Common.failure("Criteriul deja declarat nu poate fi eliminat: " + id, "criteria_protected")
		if not _same_criterion(supplied[id], criterion): return Common.failure("Criteriul deja declarat nu poate fi reformulat sau slăbit: " + id, "criteria_protected")
		ordered.append(criterion.duplicate(true))
	for criterion in incoming:
		var id = str(criterion["id"])
		if existing.has(id): continue
		ordered.append(criterion.duplicate(true))
		additions.append(id)
	return {"ok": true, "criteria": ordered, "added": additions}

static func _same_criterion(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("id", "")) == str(right.get("id", "")) and str(left.get("description", "")) == str(right.get("description", "")) and str(left.get("kind", "")) == str(right.get("kind", "")) and left.get("paths", []) == right.get("paths", []) and left.get("check", null) == right.get("check", null)

func changed() -> void:
	revision += 1
	passed.clear()
	evidence.clear()

func observe(name: String, args: Dictionary, result: Dictionary) -> Dictionary:
	if not result.get("ok", false) or criteria.is_empty(): return {}
	var data: Variant = result.get("result", {})
	var source_path = str(args.get("path", ""))
	if source_path.begins_with("res://"):
		var current_hash = _file_hash(source_path)
		if name == "godot_read_file" and data is String and data.sha256_text() != current_hash: return {}
		if name in ["godot_read_range", "godot_script_diagnostics"] and data is Dictionary and data.has("sha256") and data["sha256"] != current_hash: return {}
		if name == "godot_write_file" and str(args.get("text", "")).sha256_text() != current_hash: return {}
		if name == "godot_apply_patch" and data is Dictionary and data.has("after_sha256") and data["after_sha256"] != current_hash: return {}
	if name == "godot_project_map" and data is Dictionary and (data.get("partial", true) or data.get("stale", true)): return {}
	if name == "godot_diagnostics" and data is Dictionary:
		var collection: Dictionary = data.get("collection", {})
		if data.get("sources", {}).get("debugger", {}).get("partial", true): return {}
		if not collection.get("debugger_available", false) or not collection.get("parser_available", false) or collection.get("parser_partial", true) or collection.get("map", {}).get("partial", true) or (collection.get("running", false) and not collection.get("runtime_available", false)): return {}
	if name == "godot_debugger" and (not data is Dictionary or not data.get("available", false) or data.get("truncated", true)): return {}
	if name in ["godot_panels", "godot_panel_read"] and (not data is Dictionary or data.get("partial", true) or not str(args.get("snapshot", "")).is_empty()): return {}
	if name == "godot_panel_read" and not data.get("coverage", {}).get("contents_readable", false): return {}
	if name == "godot_panel_data" and (not data is Dictionary or not data.get("collected", false) or data.get("partial", false) or data.get("stale_session", false)): return {}
	var kinds = []
	if name == "qa_run" and data is Dictionary and data.get("status") == "pass" and data.get("fingerprint", {}).get("complete", false) and data.get("fingerprint") == data.get("fingerprint_after") and data.get("session", {}).get("experiment", "").is_empty():
		var captured = Experiments.snapshot(ProjectSettings.globalize_path("res://").trim_suffix("/"))
		if captured.get("ok", false) and captured["result"]["digest"] == data["fingerprint_after"].get("digest"):
			kinds.append_array(["inspection", "runtime", "interaction"])
	if name == "profile_run" and data is Dictionary and data.get("status") == "measured" and data.get("session", {}).get("experiment", "").is_empty(): kinds.append_array(["inspection", "runtime"])
	if name == "repair_check" and data is Dictionary and data.get("status") == "verified": kinds.append_array(["inspection", "runtime"])
	if name in ["asset_audit", "godot_impact"]: kinds.append("inspection")
	if name in ["godot_read_file", "godot_read_range", "godot_get", "godot_describe", "godot_settings", "godot_scene_tree", "godot_project_map", "godot_diagnostics", "godot_debugger", "godot_panels", "godot_panel_read", "godot_panel_data", "godot_files", "asset_status", "asset_wait", "asset_import", "asset_export", "github_read", "github_create_issue"]: kinds.append("inspection")
	if name == "godot_script_diagnostics" and data is Dictionary and data.get("valid", false) and (not args.has("text") or str(args["text"]).sha256_text() == _file_hash(str(args.get("path", "")))): kinds.append("syntax")
	if data is Dictionary and data.get("syntax", {}).get("valid", false) and not (name == "godot_apply_patch" and args.get("dry_run", true)): kinds.append("syntax")
	if name == "playtest_state" and data is Dictionary and not data.is_empty(): kinds.append("runtime")
	if name == "godot_run_state" and data is Dictionary and data.get("running", false): kinds.append("runtime")
	if name == "playtest_act" and data is Dictionary and data.get("until_met", false) and not data.get("after", {}).is_empty(): kinds.append("interaction"); kinds.append("runtime")
	if name in ["playtest_observe", "editor_capture", "file_observe"] and not result.get("images", []).is_empty(): kinds.append("visual")
	if kinds.is_empty(): return {}
	var paths = []
	var path = str(args.get("path", ""))
	if path.begins_with("res://") and FileAccess.file_exists(path): paths.append(path)
	if data is Dictionary and str(data.get("path", "")).begins_with("res://") and FileAccess.file_exists(data["path"]) and data["path"] not in paths: paths.append(data["path"])
	var values = {}
	var hashes = {}
	for criterion in criteria:
		for target in criterion.get("paths", []):
			var normalized = Common.project_path(str(target))
			if not hashes.has(normalized): hashes[normalized] = _file_hash(normalized)
		if criterion.get("check") is Dictionary: values[criterion["id"]] = _pointer(data, str(criterion["check"].get("pointer", "")))
	var id = Common.uid()
	if evidence.size() >= 100: evidence.erase(evidence.keys()[0])
	evidence[id] = {"id": id, "tool": name, "kinds": kinds, "paths": paths, "revision": revision, "declaration": declaration, "hashes": hashes, "values": values}
	return {"id": id, "kinds": kinds, "revision": revision}

func check(id: String, ids: Array) -> Dictionary:
	var matches = criteria.filter(func(item: Dictionary) -> bool: return item["id"] == id)
	if matches.is_empty(): return Common.failure("Criteriu necunoscut.", "criterion_unknown")
	var criterion: Dictionary = matches[0]
	var covered = []
	var accepted = false
	var stale = false
	var declared_at = int(_declared_at.get(id, 0))
	for key in ids:
		if not evidence.has(key): return Common.failure("Dovadă necunoscută sau invalidată. Rulează verificarea din nou.", "evidence_stale")
		var proof: Dictionary = evidence[key]
		if proof["revision"] != revision: return Common.failure("Proiectul s-a modificat după verificare.", "evidence_stale")
		for path in proof["hashes"]:
			if proof["hashes"][path] == "unverified_large" or _file_hash(path) != proof["hashes"][path]: return Common.failure("Fișier modificat sau prea mare pentru această probă: " + path, "evidence_stale")
		# Evidence collected before this criterion existed must not accidentally
		# satisfy it, even when kind and paths would otherwise match.
		if int(proof.get("declaration", 0)) < declared_at:
			stale = true
			continue
		if criterion["kind"] not in proof["kinds"]: continue
		covered.append_array(proof["paths"])
		if criterion.has("check"):
			var value: Dictionary = proof["values"].get(id, {})
			accepted = accepted or (value.get("found", false) and _compare(value.get("value"), criterion["check"]))
		else: accepted = true
	if stale and not accepted: return Common.failure("Dovada a fost colectată înainte de declararea acestui criteriu. Rulează verificarea din nou.", "evidence_stale")
	for target in criterion.get("paths", []):
		if criterion["kind"] in ["inspection", "syntax"] and Common.project_path(str(target)) not in covered: return Common.failure("Dovada nu acoperă fișierul cerut: " + str(target), "evidence_scope")
	if not accepted: return Common.failure("Dovezile nu satisfac tipul sau condiția criteriului.", "criterion_failed")
	passed[id] = {"revision": revision, "evidence": ids.duplicate()}
	return Common.success({"criterion": id, "verified": true, "revision": revision})

func problem() -> String:
	if criteria.is_empty(): return "Declară criterii concrete în task_update.criteria și verifică-le prin task_check înainte de finalizare."
	for criterion in criteria:
		if not passed.has(criterion["id"]): return "Criteriu încă neverificat: " + str(criterion["description"])
		var checked = check(str(criterion["id"]), passed[criterion["id"]]["evidence"])
		if not checked.get("ok", false): return str(checked.get("error", "Verificare invalidată."))
	return ""

func snapshot() -> Dictionary:
	return {"revision": revision, "criteria": criteria.duplicate(true), "verified": passed.keys(), "pending": criteria.filter(func(item: Dictionary) -> bool: return not passed.has(item["id"])).map(func(item: Dictionary) -> String: return item["id"])}

func restore(saved: Dictionary) -> void:
	reset()
	if saved.get("criteria", []) is Array: declare(saved.get("criteria", []))
	revision = int(saved.get("revision", 0)) + 1
	# A process restart cannot preserve an observation of a previous running game.

static func _file_hash(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return "missing"
	if file.get_length() > 4 * 1024 * 1024: return "unverified_large"
	return FileAccess.get_sha256(path)

static func _pointer(data: Variant, pointer: String) -> Dictionary:
	var value: Variant = data
	if not pointer.is_empty():
		if not pointer.begins_with("/"): return {"found": false}
		for part in pointer.substr(1).split("/"):
			var key = part.replace("~1", "/").replace("~0", "~")
			if value is Dictionary and value.has(key): value = value[key]
			elif value is Array and key.is_valid_int() and int(key) >= 0 and int(key) < value.size(): value = value[int(key)]
			else: return {"found": false}
	if JSON.stringify(value).length() > 4000: return {"found": false, "reason": "Request a narrower measurement."}
	return {"found": true, "value": value}

static func _compare(value: Variant, assertion: Dictionary) -> bool:
	var expected: Variant = assertion.get("expected")
	match str(assertion.get("op", "")):
		"eq": return value == expected
		"ne": return value != expected
		"contains":
			if value is String: return expected is String and expected in value
			return (value is Array or value is Dictionary) and expected in value
		"nonempty": return (value is Array or value is String or value is Dictionary) and not value.is_empty()
		"gt", "gte", "lt", "lte":
			if not (value is float or value is int) or not (expected is float or expected is int): return false
			match assertion["op"]:
				"gt": return value > expected
				"gte": return value >= expected
				"lt": return value < expected
				"lte": return value <= expected
	return false
