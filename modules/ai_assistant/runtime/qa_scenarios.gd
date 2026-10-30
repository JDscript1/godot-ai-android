@tool
extends RefCounted
## Versioned, replayable gameplay checks. Only executor observations can pass.
static var Common: GDScript
static var EngineeringStore: GDScript
var directory = ""
var active = false

func configure(path: String) -> void: directory = path.path_join("engineering/scenarios")

static func validate(args: Dictionary) -> Dictionary:
	if not EngineeringStore.valid_id(str(args.get("id", ""))) or Common.project_path(str(args.get("scene", ""))).is_empty(): return Common.failure("ID sau scenă invalidă.", "invalid_scenario")
	if str(args.get("scene", "")).get_extension() not in ["tscn", "scn"]: return Common.failure("Scenariul necesită o scenă Godot salvată.", "invalid_scenario")
	var steps = args.get("steps", [])
	if not steps is Array or steps.is_empty() or steps.size() > 64 or JSON.stringify(steps).length() > 64000: return Common.failure("Scenariul necesită între 1 și 64 de pași.", "invalid_scenario")
	var assertions = 0
	for step in steps:
		if not step is Dictionary or step.get("kind") not in ["act", "assert", "watch"]: return Common.failure("Tip de pas nesuportat.", "invalid_scenario")
		if step["kind"] == "assert":
			assertions += 1
			if not step.get("expression") is String or step["expression"].is_empty() or step["expression"].length() > 400 or step.get("op") not in ["eq", "ne", "gt", "gte", "lt", "lte", "contains", "nonempty"] or (step.get("op") != "nonempty" and not step.has("expected")): return Common.failure("Condiție de verificare invalidă.", "invalid_scenario")
		elif step["kind"] == "act":
			if not step.get("inputs", []) is Array or step.get("inputs", []).size() > 8 or not _integer(step.get("advance_frames", 1), 1, 1200): return Common.failure("Acțiune prea mare sau invalidă.", "invalid_scenario")
			for input in step.get("inputs", []):
				if not _input(input): return Common.failure("Input invalid.", "invalid_scenario")
			if step.has("until") and (not step["until"] is Dictionary or not step["until"].get("expression") is String or step["until"]["expression"].is_empty() or step["until"]["expression"].length() > 400 or not _integer(step["until"].get("timeout_frames", 600), 1, 1800)): return Common.failure("Condiție de așteptare invalidă.", "invalid_scenario")
			if not _expressions(step.get("probes", []), 12) or step.has("servo"): return Common.failure("Probe invalide; scenariile salvate folosesc inputs/until, fără servo implicit.", "invalid_scenario")
		else:
			if not _expressions(step.get("expressions", []), 4) or not step.get("signals", []) is Array or step.get("signals", []).size() > 8: return Common.failure("Prea multe probe urmărite.", "invalid_scenario")
			for item in step.get("signals", []):
				if not item is Dictionary or not item.get("path") is String or not item.get("name") is String or item["name"].is_empty(): return Common.failure("Semnal urmărit invalid.", "invalid_scenario")
	if assertions == 0: return Common.failure("Un test trebuie să aibă cel puțin o verificare măsurată.", "assertion_required")
	return Common.success({"assertions": assertions})

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

static func _expressions(value: Variant, maximum: int) -> bool:
	return value is Array and value.size() <= maximum and value.all(func(item: Variant) -> bool: return item is String and not item.is_empty() and item.length() <= 400)

static func _input(value: Variant) -> bool:
	if not value is Dictionary or value.get("kind") not in ["action", "key", "mouse", "touch"]: return false
	if value["kind"] == "action" and (not value.get("action") is String or value["action"].is_empty()): return false
	if value["kind"] == "key" and not _integer(value.get("key"), 1, 0x7fffffff): return false
	if value.has("button") and not _integer(value["button"], 1, 9): return false
	for key in ["x", "y"]:
		if value.has(key) and (not (value[key] is int or value[key] is float) or not is_finite(float(value[key])) or value[key] < 0 or value[key] > 1): return false
	for key in ["sustain", "release"]:
		if value.has(key) and not value[key] is bool: return false
	return true

func save(args: Dictionary) -> Dictionary:
	var validation = validate(args)
	if not validation.get("ok", false): return validation
	var path = directory.path_join(str(args["id"]) + ".json")
	if FileAccess.file_exists(path) and FileAccess.get_sha256(path) != args.get("expected_sha256", ""): return Common.failure("Test modificat între timp; recitește-l înainte de salvare.", "scenario_conflict")
	var item = {"version": 1, "id": args["id"], "title": str(args.get("title", args["id"])).left(200), "scene": args["scene"], "steps": args["steps"].duplicate(true)}
	if Common.atomic_json(path, item) != OK: return Common.failure("Testul nu a putut fi salvat.", "checkpoint_failed")
	return read(str(args["id"]))

func read(id: String) -> Dictionary:
	if not EngineeringStore.valid_id(id): return Common.failure("ID invalid.", "invalid_scenario")
	var path = directory.path_join(id + ".json")
	var item: Variant = Common.read_json(path, {})
	if not item is Dictionary or not validate(item).get("ok", false): return Common.failure("Test inexistent sau deteriorat.", "scenario_missing")
	return Common.success(item.merged({"sha256": FileAccess.get_sha256(path)}))

func list_saved() -> Array:
	var rows = []
	var dir = DirAccess.open(directory)
	if dir == null: return rows
	for filename in dir.get_files():
		if rows.size() >= 100: break
		if not filename.ends_with(".json"): continue
		var item = read(filename.trim_suffix(".json"))
		if item.get("ok", false): rows.append(item["result"])
	return rows

static func compare(actual: Variant, op: String, expected: Variant = null) -> bool:
	if actual is Dictionary and actual.has("error"): return false
	if op == "nonempty": return actual != null and not str(actual).is_empty() and (not (actual is Array or actual is Dictionary) or not actual.is_empty())
	if op in ["eq", "ne"]:
		var same_type = typeof(actual) == typeof(expected) or ((actual is int or actual is float) and (expected is int or expected is float))
		if not same_type: return false
		return actual == expected if op == "eq" else actual != expected
	if op == "contains":
		if actual is String and expected is String: return expected in actual
		if actual is Array: return expected in actual
		return false
	if not (actual is int or actual is float) or not (expected is int or expected is float) or not is_finite(float(actual)) or not is_finite(float(expected)): return false
	match op:
		"gt": return actual > expected
		"gte": return actual >= expected
		"lt": return actual < expected
		"lte": return actual <= expected
	return false

func run(id: String, hooks: Dictionary, cancel: Dictionary = {}) -> Dictionary:
	if active: return Common.failure("Un scenariu de test rulează deja.", "qa_busy")
	if cancel.get("cancelled", false): return Common.failure("Testul nu a pornit: oprire solicitată.", "cancelled")
	var saved = read(id)
	if not saved.get("ok", false): return saved
	for required in ["launch", "runtime", "finish", "fingerprint"]:
		if not hooks.get(required, Callable()).is_valid(): return Common.failure("Lipsește conexiunea nativă de testare.", "qa_unavailable")
	active = true
	var run = {"version": 1, "id": Common.uid(), "scenario": id, "scenario_sha256": saved["result"]["sha256"], "scene": saved["result"]["scene"], "status": "running", "steps": [], "started": Time.get_unix_time_from_system(), "fingerprint": hooks["fingerprint"].call()}
	if not run["fingerprint"].get("complete", false):
		active = false
		return Common.failure("Testul necesită un snapshot complet al surselor salvate.", "coverage_incomplete")
	var report_path = directory.path_join("runs").path_join(str(run["id"]) + ".json")
	if Common.atomic_json(report_path, run) != OK:
		active = false
		return Common.failure("Testul nu a pornit: raportul nu poate fi salvat.", "checkpoint_failed")
	var launched: Dictionary = await hooks["launch"].call(str(saved["result"]["scene"]), cancel)
	if not launched.get("ok", false):
		run["status"] = "blocked"
		run["error"] = launched.get("error", "Jocul nu a pornit.")
	else:
		run["session"] = launched.get("result", {})
		await _steps(saved["result"], run, hooks, cancel)
		# Every success/failure/cancellation path releases held input and closes
		# only the game session launched by this runner.
	await hooks["finish"].call()
	if cancel.get("cancelled", false): run["status"] = "cancelled"
	run["finished"] = Time.get_unix_time_from_system()
	run["fingerprint_after"] = hooks["fingerprint"].call()
	if run["fingerprint"] != run["fingerprint_after"]:
		run["status"] = "blocked"
		run["error"] = "Proiectul s-a schimbat în timpul testului; rezultatul necesită reluare."
	active = false
	if hooks.get("redact", Callable()).is_valid(): run = Common.parse_json(hooks["redact"].call(JSON.stringify(Common.json_safe(run))))
	if Common.atomic_json(report_path, run) != OK: return Common.failure("Testul s-a încheiat, dar raportul nu a putut fi salvat.", "checkpoint_failed")
	return Common.success(run)

func _steps(scenario: Dictionary, run: Dictionary, hooks: Dictionary, cancel: Dictionary) -> void:
	var initial: Dictionary = await hooks["runtime"].call("status", {}, cancel)
	if not initial.get("ok", false) or initial.get("result", {}).get("scene") != scenario["scene"]:
		run["status"] = "blocked"
		run["error"] = "Starea jocului nu confirmă scena cerută."
		return
	if initial["result"].get("diagnostics_truncated", true):
		run["status"] = "blocked"
		run["error"] = "Observația runtime inițială este incompletă."
		return
	var startup_errors: Array = initial["result"].get("diagnostics", []).filter(func(item: Dictionary) -> bool: return item.get("severity") != "warning")
	if not startup_errors.is_empty():
		run["status"] = "fail"
		run["startup_errors"] = startup_errors
		return
	var assertions = 0
	for step in scenario["steps"]:
		if cancel.get("cancelled", false):
			run["status"] = "cancelled"
			return
		var result: Dictionary
		if step["kind"] == "assert":
			result = await hooks["runtime"].call("eval", {"expressions": [step["expression"]]}, cancel)
			var values: Dictionary = result.get("result", {}).get("values", {})
			var present = values.has(step["expression"])
			var actual: Variant = values.get(step["expression"])
			var passed = result.get("ok", false) and present and compare(actual, str(step["op"]), step.get("expected"))
			result = {"ok": result.get("ok", false), "passed": passed, "actual": actual, "expected": step.get("expected"), "expression": step["expression"], "op": step["op"]}
			assertions += 1
		else:
			var parameters: Dictionary = step.duplicate(true)
			parameters.erase("kind")
			result = await hooks["runtime"].call("act" if step["kind"] == "act" else "watch", parameters, cancel)
			var state: Dictionary = result.get("result", {})
			result["passed"] = result.get("ok", false) and not state.get("timed_out", false) and not state.get("cancelled", false) and not state.get("expired", false)
		run["steps"].append({"kind": step["kind"], "result": result})
		if not result.get("passed", false):
			run["status"] = "fail" if result.get("ok", false) else "blocked"
			return
	var final: Dictionary = await hooks["runtime"].call("status", {}, cancel)
	if not final.get("ok", false) or final.get("result", {}).get("scene") != scenario["scene"] or final.get("result", {}).get("diagnostics_truncated", true):
		run["status"] = "blocked"
		run["error"] = "Lipsește o observație runtime finală completă."
		return
	var new_errors = final["result"].get("diagnostics", []).filter(func(item: Dictionary) -> bool: return item.get("severity") != "warning")
	run["new_errors"] = new_errors
	run["assertions"] = assertions
	run["status"] = "pass" if assertions > 0 and new_errors.is_empty() else "fail"

func report(id: String) -> Dictionary:
	if not EngineeringStore.valid_id(id): return Common.failure("ID invalid.", "invalid_report")
	var item: Variant = Common.read_json(directory.path_join("runs").path_join(id + ".json"), {})
	if not item is Dictionary or item.get("id") != id: return Common.failure("Raport inexistent.", "report_missing")
	if item.get("status") == "running": item = item.merged({"status": "interrupted", "error": "Execuția anterioară nu are o încheiere confirmată."}, true)
	return Common.success(item)
