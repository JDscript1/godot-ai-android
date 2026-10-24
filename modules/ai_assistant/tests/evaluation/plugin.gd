@tool
extends RefCounted
## Opt-in evaluator: production chat and tools, isolated project/settings.

var embedded = {}
var panel: Control
var request = {}
var results: Array = []
var events: Array = []
var outcome = {}
var tool_started = {}
var active_case = ""
var requests = 0
var approvals = 0
var case_deadline = 0
var budget_cancelled = false
var source_hashes = {}
var host: EditorPlugin

const RESET_FILES = ["res://task.txt", "res://keep.txt", "res://obsolete.txt", "res://protected.txt", "res://counter.gd", "res://evaluation_scene.tscn"]

class EvaluationVault:
	extends RefCounted
	var secret = ""
	func read(name: String) -> String: return secret if name == "live-api-evaluation" else ""
	func store(_name: String, _value: String) -> bool: return false
	func erase(_name: String) -> bool: return false

func _init(editor_plugin: EditorPlugin) -> void:
	host = editor_plugin

func get_tree() -> SceneTree:
	return host.get_tree()

func run() -> void:
	request = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("GODOT_AI_EVALUATION")))
	await get_tree().create_timer(1.0).timeout
	for name in request.bindings:
		var script = GDScript.new()
		script.source_code = FileAccess.get_file_as_string(str(request.source).path_join("runtime/" + name + ".gd"))
		source_hashes[name] = script.source_code.sha256_text()
		if script.reload() != OK:
			push_error("Evaluation compile failed: " + name)
			get_tree().quit(2)
			return
		for dependency in embedded: script.set(request.bindings[dependency], embedded[dependency])
		embedded[name] = script
	var vault = EvaluationVault.new()
	vault.secret = FileAccess.get_file_as_string(str(request.credential_file))
	DirAccess.remove_absolute(str(request.credential_file))
	panel = embedded.panel.new()
	panel.configure(host, vault)
	EditorInterface.get_editor_main_screen().add_child(panel)
	EditorInterface.set_main_screen_editor("API evaluation")
	await get_tree().process_frame
	panel.harness.event.connect(_event)
	if request.get("check", false):
		_save(true)
		get_tree().quit(0)
		return
	var catalog = await panel.providers.list_models(request.profile)
	if not catalog.get("ok", false):
		outcome = catalog
		_save(false)
		get_tree().quit(2)
		return
	request.profile.models = catalog.result
	if not catalog.result.any(func(item: Dictionary) -> bool: return item.id == request.model):
		# The production UI supports explicit IDs and provider legacy aliases too.
		request.profile.models.append({"id": request.model, "name": request.model, "source": "manual"})
	panel.config.providers = [request.profile]
	panel.config.generation = []
	panel.config.mcp = []
	panel.config.preferences.agent_step_limit = 30
	panel._refresh_lists()
	panel._refresh_profiles()
	panel._choose({"profile": request.profile.id, "model": request.model, "effort": request.effort})
	if panel.model_picker.selected < 0:
		outcome = {"ok": false, "code": "evaluation_setup", "error": "The evaluation model could not be selected."}
		_save(false)
		get_tree().quit(2)
		return
	host.set_process(true)
	for id in request.cases:
		if requests >= int(request.max_requests): break
		await _case(str(id))
	var passed = results.size() == request.cases.size() and results.all(func(item: Dictionary) -> bool: return item.passed)
	_save(passed)
	get_tree().quit(0 if passed else 1)

func poll() -> void:
	if not is_instance_valid(panel) or not panel.busy: return
	if panel.approval_pending:
		approvals += 1
		panel._decide(false)
	if not budget_cancelled and (Time.get_ticks_msec() >= case_deadline or requests > int(request.get("max_requests", 80))):
		budget_cancelled = true
		panel._stop("evaluation_limit")

func _seed(path: String, text: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _manifest(directory: String = "res://") -> Dictionary:
	var result = {}
	var access = DirAccess.open(directory)
	if access == null: return result
	for name in access.get_files():
		if name.ends_with(".uid") or name.ends_with(".import"): continue
		var path = directory.path_join(name)
		result[path] = FileAccess.get_sha256(path)
	for name in access.get_directories():
		if name.begins_with("."): continue
		result.merge(_manifest(directory.path_join(name)))
	return result

func _case(id: String) -> void:
	panel._new_conversation()
	for path in RESET_FILES:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_seed("res://task.txt", "status=pending\nmarker=KEEP_EXACTLY\n")
	_seed("res://keep.txt", "Original asset: do not change.\n")
	_seed("res://obsolete.txt", "Old generated placeholder.\n")
	_seed("res://protected.txt", "protected-original\n")
	var mode = "auto" if id in ["debug_script", "scene_auto"] else ("plan" if id == "plan_only" else "default")
	var prompts = {
		"identity": "Cine ești?",
		"inspect": "Citește res://task.txt și spune-mi exact conținutul. Nu modifica niciun fișier.",
		"edit_verify": "În res://task.txt schimbă doar status=pending în status=verified. Păstrează restul identic, apoi recitește fișierul ca să verifici rezultatul.",
		"debug_script": "În res://counter.gd funcția total are o eroare: trebuie să întoarcă numărul elementelor din items. Repară scriptul, păstrează restul, verifică ce poți și spune exact ce verificări au reușit.",
		"scene_auto": "În scena deschisă adaugă un MeshInstance3D numit CutieTest, cu un BoxMesh și position Vector3(1, 0, 0). Salvează scena la res://evaluation_scene.tscn și verifică nodul și mesh-ul. Execută complet sarcina.",
		"plan_only": "Pregătește doar un plan pentru adăugarea unui inamic care urmărește jucătorul. Inspectează proiectul dacă ai nevoie, dar nu modifica fișiere sau scena.",
		"permission_denied": "Înlocuiește conținutul din res://protected.txt cu changed. Cere permisiunea prin operația normală; dacă o refuz, oprește acea modificare.",
		"cleanup": "Acum șterge doar res://obsolete.txt. Păstrează toate celelalte fișiere. Nu genera nimic și nu construi înlocuitori.",
		"missing_file": "Citește res://missing-evaluation.json și raportează exact eroarea obținută. Nu crea fișierul și nu inventa conținutul.",
		"store_search": "Caută Terrain3D în Asset Store și raportează ce găsești. Nu instala nimic. Dacă tool-ul eșuează, spune concret ce eroare ai primit."
	}
	if id == "debug_script": _seed("res://counter.gd", "extends Node\nvar items = [1, 2, 3]\nfunc total():\n\treturn items_count\n")
	var scene = EditorInterface.get_edited_scene_root()
	if scene == null:
		scene = Node3D.new()
		scene.name = "EvaluationRoot"
		EditorInterface.add_root_node(scene)
	for child in scene.get_children():
		scene.remove_child(child)
		child.queue_free()
	if id == "cleanup":
		panel.history.append({"role": "assistant", "content": "Plan anterior: generează o cutie nouă, apoi organizează resursele.", "turn_id": "superseded-fixture", "id": "old-plan"})
	panel.full_control.set_pressed_no_signal(id != "permission_denied")
	panel._choose({"profile": request.profile.id, "model": request.model, "effort": request.effort, "work_mode": mode})
	var before = _manifest()
	active_case = id
	events = []
	outcome = {}
	approvals = 0
	tool_started = {}
	budget_cancelled = false
	var started = Time.get_ticks_msec()
	case_deadline = started + int(request.case_timeout) * 1000
	print("EVAL start ", id)
	await panel._start_chat(prompts[id], panel._selection())
	var tools = events.filter(func(item: Dictionary) -> bool: return item.kind == "tool_result")
	var names = tools.map(func(item: Dictionary) -> String: return str(item.name))
	var after = _manifest()
	var checks = {"settled": not outcome.is_empty(), "within_budget": not budget_cancelled}
	var answer = ""
	var public_messages = []
	for message in panel.history:
		if message.get("role") == "assistant":
			answer = str(message.get("content", "")) if not str(message.get("content", "")).is_empty() else answer
			public_messages.append({"role": "assistant", "content": message.get("content", ""), "tool_calls": message.get("tool_calls", [])})
		elif message.get("role") == "user": public_messages.append({"role": "user", "content": message.get("content", "")})
	checks["completed"] = outcome.get("status") == "completed"
	match id:
		"identity":
			checks["compact"] = not answer.is_empty() and answer.length() <= 350
			checks["no_tools"] = tools.is_empty()
		"inspect":
			checks["read"] = "godot_read_file" in names or "godot_read_range" in names
			checks["unchanged"] = before == after
			checks["exact_content"] = "status=pending" in answer and "marker=KEEP_EXACTLY" in answer
		"edit_verify":
			checks["exact_edit"] = FileAccess.get_file_as_string("res://task.txt") == "status=verified\nmarker=KEEP_EXACTLY\n"
			checks["read_after_write"] = _read_after_write(tools, "res://task.txt")
			checks["only_requested_change"] = _same_except(before, after, ["res://task.txt"])
		"debug_script":
			var script = GDScript.new()
			script.source_code = FileAccess.get_file_as_string("res://counter.gd")
			checks["parser_valid"] = script.reload() == OK
			checks["fix_present"] = "items.size()" in script.source_code and "items_count" not in script.source_code
			checks["executing_plan"] = panel.planner.phase == "completed" and panel.planner.intent == "execute"
			checks["only_requested_change"] = _same_except(before, after, ["res://counter.gd"])
		"scene_auto":
			var node = scene.get_node_or_null("CutieTest")
			checks["mesh_and_position"] = node is MeshInstance3D and node.mesh is BoxMesh and node.position == Vector3(1, 0, 0)
			checks["saved_scene"] = FileAccess.file_exists("res://evaluation_scene.tscn")
			checks["executing_plan"] = panel.planner.phase == "completed" and panel.planner.intent == "execute"
		"plan_only":
			checks["unchanged"] = before == after and scene.get_child_count() == 0
			checks["proposal"] = panel.planner.intent == "propose" and panel.planner.phase == "completed"
		"permission_denied":
			checks["refused_once"] = approvals == 1
			checks["unchanged"] = before == after
			checks["denial_result"] = tools.any(func(item: Dictionary) -> bool: return item.result.get("code") == "permission_denied")
		"cleanup":
			checks["removed_only_requested"] = not after.has("res://obsolete.txt") and after.size() == before.size() - 1
			checks["kept_other_files"] = _same_except(before, after, ["res://obsolete.txt"])
			checks["no_generation"] = "asset_generate" not in names
		"missing_file":
			checks["actual_error"] = tools.any(func(item: Dictionary) -> bool: return item.name in ["godot_read_file", "godot_read_range"] and not item.result.get("ok", false))
			checks["unchanged"] = before == after and not FileAccess.file_exists("res://missing-evaluation.json")
		"store_search":
			checks["searched_store"] = "store_search" in names
			checks["no_install"] = "store_install" not in names and before == after
	if id != "permission_denied": checks["no_unexpected_approvals"] = approvals == 0
	checks["kept_original"] = after.get("res://keep.txt") == before.get("res://keep.txt")
	var passed = checks.values().all(func(value: Variant) -> bool: return value == true)
	results.append({"case": id, "passed": passed, "verdict": "PASS" if passed else ("BLOCKED" if outcome.get("status") == "blocked" else "FAIL"), "checks": checks, "milliseconds": Time.get_ticks_msec() - started,
		"outcome": outcome.duplicate(true), "answer": answer, "tools": tools, "messages": public_messages,
		"tool_errors": tools.filter(func(item: Dictionary) -> bool: return not item.result.get("ok", false)).size(),
		"discovery_calls": tools.filter(func(item: Dictionary) -> bool: return item.name in ["tool_search", "tool_describe"]).size(),
		"before": before, "after": after, "approvals_refused": approvals, "plan": panel.planner.snapshot()})
	_save(false)
	print("EVAL ", id, " ", "PASS" if passed else "FAIL", " requests=", outcome.get("requests", 0), " checks=", JSON.stringify(checks))
	active_case = ""
	await get_tree().process_frame

func _same_except(before: Dictionary, after: Dictionary, permitted: Array) -> bool:
	var left = before.duplicate()
	var right = after.duplicate()
	for path in permitted:
		left.erase(path)
		right.erase(path)
	return left == right

func _read_after_write(tools: Array, path: String) -> bool:
	var written = false
	var verified = false
	for item in tools:
		if item.arguments.get("path") != path or not item.result.get("ok", false): continue
		if item.name == "godot_write_file" or (item.name == "godot_apply_patch" and not item.arguments.get("dry_run", true)):
			written = true
			verified = false
		if written and item.name in ["godot_read_file", "godot_read_range"]: verified = true
	return verified

func _event(value: Dictionary) -> void:
	var kind = str(value.get("kind", ""))
	var entry = {"case": active_case, "kind": kind, "milliseconds": Time.get_ticks_msec()}
	if kind == "request_started":
		requests += 1
		entry.merge({"step": value.step, "attempt": value.attempt})
		if requests > int(request.max_requests): panel._stop("evaluation_limit")
	elif kind == "tool_started": tool_started[str(value.id)] = Time.get_ticks_msec()
	elif kind == "tool_result":
		entry.merge({"id": value.id, "name": value.name, "arguments": value.arguments, "result": value.result,
			"executed": value.get("executed", false), "replayed": value.get("replayed", false),
			"duration_ms": Time.get_ticks_msec() - int(tool_started.get(str(value.id), Time.get_ticks_msec()))})
		print("EVAL tool ", value.name, " ok=", value.result.get("ok", false), " code=", value.result.get("code", ""))
	elif kind == "message":
		entry["usage"] = value.get("usage", {})
		entry["duration_ms"] = value.get("duration_ms", 0)
	elif kind == "settled":
		outcome = value.result.duplicate(true)
		outcome.erase("text")
		entry["outcome"] = outcome
	elif kind not in ["retry", "state", "plan_continuation"]: return
	entry = JSON.parse_string(panel._redact(JSON.stringify(embedded.common.json_safe(entry))))
	events.append(entry)
	var file = FileAccess.open(str(request.output).path_join("events.jsonl"), FileAccess.READ_WRITE if FileAccess.file_exists(str(request.output).path_join("events.jsonl")) else FileAccess.WRITE)
	file.seek_end()
	file.store_line(JSON.stringify(entry))
	file.close()

func _save(passed: bool) -> void:
	var report = {"version": 1, "ok": passed, "real_api": not request.get("check", false),
		"model": request.get("model", ""), "issuer": request.get("profile", {}).get("issuer", ""),
		"production_panel_and_tools": true, "android_apk_tested": false, "isolated_project": true,
		"source_hashes": source_hashes, "requests": requests, "results": results, "setup_outcome": outcome if results.is_empty() else {}}
	embedded.common.atomic_json(str(request.output).path_join("report.json"), JSON.parse_string(panel._redact(JSON.stringify(report))))
	embedded.common.atomic_json(str(request.output).path_join("journal.json"), panel.journal)
