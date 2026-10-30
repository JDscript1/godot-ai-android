@tool
extends RefCounted
## Native orchestration for verified game development. Models propose; tools measure.
static var Common: GDScript
static var EngineeringStore: GDScript
static var QAScenarios: GDScript
static var AssetAudit: GDScript
static var Experiments: GDScript
var owner: Node
var store: RefCounted
var scenarios: RefCounted
var experiments: RefCounted
var directory = ""
var qa_session = -1
var qa_generation = -1
var qa_project = ""
var qa_experiment = ""
var qa_scene = ""
var qa_turn = ""
var profile_active = false
var owned_started = false

func shutdown() -> void:
	# Tree teardown cannot await a reply. The game bridge releases input on
	# debugger disconnect; stop only a process this coordinator started.
	if owned_started and qa_session >= 0 and owner.plugin.has_method("runtime_request"): owner.plugin.runtime_request("release", {"__session": qa_session, "__generation": qa_generation})
	if owned_started and not qa_experiment.is_empty() and owner.plugin.has_method("experiment_stop"): owner.plugin.experiment_stop()
	elif owned_started: owner.tools.finish_playtest(qa_turn, true)
	owned_started = false

func fingerprint() -> Dictionary:
	var root = qa_project if not qa_project.is_empty() else ProjectSettings.globalize_path("res://").trim_suffix("/")
	var captured = Experiments.snapshot(root)
	if not captured.get("ok", false): return {"complete": false, "error": captured.get("error", "Snapshot unavailable")}
	return {"complete": true, "root": root, "digest": captured["result"]["digest"], "files": captured["result"]["files"].size(), "excluded": captured["result"]["excluded"]}

func _target(experiment: String) -> Dictionary:
	if scenarios.active or profile_active or owned_started or owner.agent_jobs.playtest_busy: return Common.failure("O verificare de joc este deja activă.", "qa_busy")
	qa_experiment = experiment
	qa_project = ProjectSettings.globalize_path("res://").trim_suffix("/")
	if not experiment.is_empty():
		var saved = experiments.read(experiment)
		if not saved.get("ok", false): return saved
		qa_project = str(saved["result"]["project"])
	qa_session = -1
	qa_generation = -1
	qa_turn = str(owner.current_turn)
	return Common.success()

func _launch(scene: String, cancel: Dictionary) -> Dictionary:
	if not owner.plugin.has_method("runtime_request"): return Common.failure("Puntea runtime nativă necesită editorul recompilat.", "bridge_unavailable")
	if EditorInterface.is_playing_scene(): return Common.failure("Există deja un joc pornit; testul nu preia sesiunea utilizatorului.", "game_already_running")
	var old_generations = {}
	if not owner.plugin.has_method("debugger_snapshot"): return Common.failure("Lipsește identificarea sesiunilor native.", "bridge_unavailable")
	var baseline: Dictionary = owner.plugin.debugger_snapshot()
	# Event truncation concerns old error rows; this native endpoint lists all
	# session identities independently of that event budget.
	if not baseline.get("ok", false) or not baseline.get("result", {}).get("sessions") is Array: return Common.failure("Lipsește lista sesiunilor debugger.", "coverage_incomplete")
	for session in baseline["result"].get("sessions", []): old_generations[int(session["session"])] = int(session["generation"])
	qa_scene = scene
	var launch: Dictionary
	if not qa_experiment.is_empty():
		if not owner.plugin.has_method("experiment_launch"): return Common.failure("Lipsește lansatorul nativ pentru copii de proiect.", "bridge_unavailable")
		launch = owner.plugin.experiment_launch(qa_project, scene)
	else:
		launch = owner.tools.execute("godot_run", {"scene": scene, "keep_open": false}, 2, true)
	if not launch.get("ok", false): return launch
	owned_started = true
	var deadline = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and not cancel.get("cancelled", false):
		var status = await owner.agent_jobs.runtime("status", {}, cancel, 400)
		if status.get("ok", false) and status.get("result", {}).get("scene") == scene:
			var session = int(status.get("runtime_session", -1))
			var generation = int(status.get("runtime_generation", -1))
			if old_generations.get(session, -2) == generation:
				await owner.get_tree().process_frame
				continue # A dying previous run of the same scene is not a new test.
			var observed_root = str(status["result"].get("project_root", "")).simplify_path().trim_suffix("/")
			if observed_root != qa_project.simplify_path().trim_suffix("/"):
				await finish()
				return Common.failure("Sesiunea runtime nu confirmă directorul proiectului cerut.", "runtime_project_mismatch")
			qa_session = int(status.get("runtime_session", -1))
			qa_generation = int(status.get("runtime_generation", -1))
			if qa_session < 0 or qa_generation < 0:
				await finish()
				return Common.failure("Puntea runtime nu poate fixa sesiunea și generația debuggerului; recompilarea este necesară.", "bridge_unavailable")
			return Common.success({"scene": scene, "project": qa_project, "runtime_session": qa_session, "runtime_generation": qa_generation, "experiment": qa_experiment})
		await owner.get_tree().process_frame
	await finish()
	return Common.failure("Pornirea jocului nu a fost confirmată.", "cancelled" if cancel.get("cancelled", false) else "runtime_timeout")

func runtime(command: String, args: Dictionary, cancel: Dictionary) -> Dictionary:
	if qa_session < 0: return Common.failure("Nu există o sesiune de test fixată.", "runtime_session_missing")
	var parameters = args.merged({"__session": qa_session, "__generation": qa_generation}, true)
	var result = await owner.agent_jobs.runtime(command, parameters, cancel, 90000 if command == "act" else (1500 if command in ["release", "performance"] else 10000))
	if result.get("ok", false) and (int(result.get("runtime_session", -1)) != qa_session or int(result.get("runtime_generation", -1)) != qa_generation): return Common.failure("Sesiunea jocului s-a schimbat în timpul verificării.", "runtime_session_changed")
	return result

func finish() -> void:
	if owned_started:
		if qa_session >= 0:
			await runtime("performance", {"action": "stop"}, {})
			await runtime("release", {}, {})
		if not qa_experiment.is_empty() and owner.plugin.has_method("experiment_stop"): owner.plugin.experiment_stop()
		else: owner.tools.finish_playtest(qa_turn, true)
	owned_started = false
	qa_session = -1
	qa_generation = -1

func run_scenario(id: String, experiment: String, cancel: Dictionary) -> Dictionary:
	var selected = _target(experiment)
	if not selected.get("ok", false): return selected
	var result = await scenarios.run(id, {"launch": _launch, "runtime": runtime, "finish": finish, "fingerprint": fingerprint, "redact": owner._redact}, cancel)
	if result.get("ok", false): result["project_mutated"] = result["result"]["fingerprint"] != result["result"].get("fingerprint_after")
	return result

func _stage(args: Dictionary, cancel: Dictionary) -> Dictionary:
	var report = scenarios.report(str(args["report"]))
	var changes = experiments.differences(str(args["id"]))
	var item = experiments.read(str(args["id"]))
	if not report.get("ok", false): return report
	if not changes.get("ok", false): return changes
	if not item.get("ok", false): return item
	var measured: Dictionary = report["result"]
	if measured.get("status") != "pass" or measured.get("session", {}).get("experiment") != args["id"] or measured.get("fingerprint_after", {}).get("digest") != changes["result"]["digest"]: return Common.failure("Integrarea necesită un test trecut pe versiunea actuală a acestei copii.", "evidence_required")
	var scenario = scenarios.read(str(measured.get("scenario", "")))
	if not scenario.get("ok", false) or scenario["result"]["sha256"] != measured.get("scenario_sha256"): return Common.failure("Testul s-a schimbat după verificare; rulează-l din nou.", "stale_evidence")
	if not args.get("paths", []).is_empty() and changes["result"]["changes"].any(func(change: Dictionary) -> bool: return change["path"] not in args["paths"]): return Common.failure("Proba verifică întreaga copie, nu o selecție incompletă. Construiește și testează separat alternativa cu subsetul dorit.", "partial_experiment")
	var proposed = experiments.proposals(str(args["id"]), args.get("paths", []))
	if not proposed.get("ok", false): return proposed
	return await owner.tools.execute_changes("godot_changes_prepare", {"changes": proposed["result"]["changes"]}, cancel)

func _reconcile(args: Dictionary, cancel: Dictionary) -> Dictionary:
	var previous: Dictionary = store.data["effects"].get(str(args["effect"]), {})
	if previous.get("tool") not in ["asset_generate", "asset_remove_background"]: return Common.failure("Acest efect cere inspecția proiectului sau a lotului original; nu poate fi confirmat printr-un job de generare.", "recovery_required")
	var job = owner.assets.find_job(str(args["job"]))
	if job.is_empty(): return Common.failure("Job salvat inexistent.", "job_missing")
	var known = previous.get("recovery", {})
	if not known.is_empty() and known.get("id", known.get("job", "")) != args["job"]: return Common.failure("Jobul nu corespunde efectului original.", "recovery_mismatch")
	# Unknown pre-submission crashes have no provider ID; never guess a match.
	if known.is_empty(): return Common.failure("Jurnalul nu conține ID-ul jobului original. Este necesară identificarea lui în jurnalul furnizorului.", "recovery_required")
	var result = await owner.assets.refresh(str(args["job"]), owner._generation_profile(str(job.get("profile_id", ""))), cancel)
	if not result.get("ok", false) or result.get("result", {}).get("status") != "completed": return Common.failure("Jobul existent nu este confirmat ca finalizat.", "recovery_pending")
	return store.reconcile(str(args["effect"]), result)

func _save_record(kind: String, record: Dictionary) -> Dictionary:
	var safe: Dictionary = Common.parse_json(owner._redact(JSON.stringify(Common.json_safe(record))))
	if Common.atomic_json(directory.path_join(kind).path_join(str(record["id"]) + ".json"), safe) != OK: return Common.failure("Raportul nu a putut fi salvat.", "checkpoint_failed")
	return Common.success(safe)

func _record(kind: String, id: String) -> Dictionary:
	if not EngineeringStore.valid_id(id): return Common.failure("ID de raport invalid.", "invalid_report")
	var item: Variant = Common.read_json(directory.path_join(kind).path_join(id + ".json"), {})
	if not item is Dictionary or item.get("id") != id: return Common.failure("Raport inexistent.", "report_missing")
	return Common.success(item)

func recent_records() -> Dictionary:
	var output = {}
	for kind in ["profiles", "repairs", "scenarios/runs"]:
		var folder = directory.path_join(kind)
		var files = DirAccess.get_files_at(folder) if DirAccess.dir_exists_absolute(folder) else PackedStringArray()
		var rows = []
		# Bounded listing: includes timestamps so a truncated catalog is explicit.
		var ordered: Array = Array(files).filter(func(file: String) -> bool: return file.ends_with(".json"))
		ordered.sort_custom(func(a: String, b: String) -> bool: return FileAccess.get_modified_time(folder.path_join(a)) > FileAccess.get_modified_time(folder.path_join(b)))
		for file in ordered.slice(0, 20):
			var item: Variant = Common.read_json(folder.path_join(file), {})
			if not item is Dictionary or not item.has("id"): continue
			rows.append({"id": item["id"], "status": "interrupted" if item.get("status") == "running" else item.get("status", ""), "scene": item.get("scene", ""), "goal": str(item.get("goal", "")).left(200), "started": item.get("started", 0)})
		output[kind] = {"items": rows, "truncated": ordered.size() > 20}
	return output

func profile(args: Dictionary, cancel: Dictionary) -> Dictionary:
	var selected = _target(str(args.get("experiment", "")))
	if not selected.get("ok", false): return selected
	var scene = Common.project_path(str(args.get("scene", "")))
	if scene.is_empty() or scene.get_extension() not in ["tscn", "scn"]: return Common.failure("Scenă invalidă.", "invalid_path")
	var frames = clampi(int(args.get("frames", 240)), 30, 1200)
	var warmup = clampi(int(args.get("warmup_frames", 60)), 1, 600)
	var source = fingerprint()
	if not source.get("complete", false): return Common.failure("Snapshot incomplet.", "coverage_incomplete")
	profile_active = true
	var report = {"version": 1, "id": Common.uid(), "status": "running", "scene": scene, "frames": frames, "warmup_frames": warmup, "fingerprint": source, "environment": {"os": OS.get_name(), "model": OS.get_model_name(), "architecture": Engine.get_architecture_name(), "engine": Engine.get_version_info().get("string", ""), "renderer": RenderingServer.get_current_rendering_method()}, "started": Time.get_unix_time_from_system()}
	var persisted = _save_record("profiles", report)
	if not persisted.get("ok", false):
		profile_active = false
		return persisted
	var result = await _launch(scene, cancel)
	if result.get("ok", false):
		report["session"] = result["result"]
		result = await runtime("act", {"advance_frames": warmup}, cancel)
	if result.get("ok", false): result = await runtime("performance", {"action": "reset"}, cancel)
	if result.get("ok", false): result = await runtime("act", {"advance_frames": frames}, cancel)
	if result.get("ok", false): result = await runtime("performance", {"action": "stop"}, cancel)
	if result.get("ok", false) and result.get("result", {}).get("source") == "running_game_native" and int(result["result"].get("samples", 0)) >= frames - 2:
		report["measurements"] = result["result"]
		report["status"] = "measured"
		report["environment"]["viewport"] = result["result"].get("viewport", [])
		var health = await runtime("status", {}, cancel)
		if not health.get("ok", false) or health.get("result", {}).get("diagnostics_truncated", true) or not health.get("result", {}).get("diagnostics", []).filter(func(item: Dictionary) -> bool: return item.get("severity") != "warning").is_empty():
			report["status"] = "blocked"
			report["error"] = "Jocul are erori sau diagnosticul runtime este incomplet."
	else:
		report["status"] = "blocked"
		report["error"] = result.get("error", "Lipsesc măsurători native complete ale jocului.")
	await finish()
	report["fingerprint_after"] = fingerprint()
	if report["fingerprint_after"] != source:
		report["status"] = "blocked"
		report["error"] = "Sursele s-au schimbat în timpul măsurării."
	if cancel.get("cancelled", false): report["status"] = "cancelled"
	report["finished"] = Time.get_unix_time_from_system()
	profile_active = false
	return _save_record("profiles", report)

func compare_profiles(before: String, after: String) -> Dictionary:
	var first = _record("profiles", before)
	var second = _record("profiles", after)
	if not first.get("ok", false): return first
	if not second.get("ok", false): return second
	return compare_measurements(first["result"], second["result"])

static func compare_measurements(first: Dictionary, second: Dictionary) -> Dictionary:
	for key in ["scene", "frames", "warmup_frames", "environment"]:
		if first.get(key) != second.get(key) or not first.has(key): return Common.failure("Profilurile au condiții de măsurare diferite.", "profile_incomparable")
	if first.get("status") != "measured" or second.get("status") != "measured": return Common.failure("Sunt necesare două măsurători finalizate.", "evidence_required")
	var deltas = {}
	for key in ["average_frame_ms", "p95_frame_ms", "max_frame_ms", "process_ms", "physics_ms", "engine_static_memory_bytes", "draw_calls", "primitives", "nodes"]:
		if not first.get("measurements", {}).has(key) or not second.get("measurements", {}).has(key): continue
		var a = float(first["measurements"][key])
		var b = float(second["measurements"][key])
		deltas[key] = {"before": a, "after": b, "delta": b - a, "percent": (b - a) * 100.0 / a if a != 0 else null}
	if deltas.is_empty(): return Common.failure("Nu există metrici comune.", "evidence_required")
	return Common.success({"before": first.get("id"), "after": second.get("id"), "metrics": deltas, "scope": "One measured game window per revision; repeat on the same device to assess noise. Not GPU timing, OS-wide RAM or proof of better gameplay."})

static func current_errors(data: Dictionary) -> Array:
	return data.get("issues", []).filter(func(issue: Dictionary) -> bool:
		return not issue.get("stale", true) and issue.get("severity") == "error" and (str(issue.get("source", "")).begins_with("script:") or str(issue.get("source", "")).begins_with("references:") or issue.get("source") == "runtime" or (issue.get("source") == "debugger" and issue.get("active", false))))

static func diagnostics_complete(data: Dictionary) -> bool:
	var collection: Dictionary = data.get("collection", {})
	if data.get("truncated", true) or not collection.get("parser_available", false) or collection.get("parser_partial", true) or collection.get("map", {}).get("partial", true) or collection.get("map", {}).get("stale", true): return false
	if not collection.get("debugger_available", false) or data.get("sources", {}).get("debugger", {}).get("partial", true): return false
	if collection.get("running", false) and (not collection.get("runtime_available", false) or data.get("sources", {}).get("runtime", {}).get("partial", true)): return false
	for key in data.get("sources", {}):
		if (str(key).begins_with("script:") or str(key).begins_with("references:")) and data["sources"][key].get("partial", false): return false
	return true

func _regressions(ids: Array, source: Dictionary, status: String) -> Dictionary:
	var tests = {}
	for id in ids:
		var saved = scenarios.report(str(id))
		if not saved.get("ok", false): return saved
		var report: Dictionary = saved["result"]
		var captured: Dictionary = report.get("fingerprint_after", {})
		if report.get("status") != status or not captured.get("complete", false) or captured.get("digest") != source.get("digest") or captured.get("root") != source.get("root") or not report.get("session", {}).get("experiment", "").is_empty(): return Common.failure("Raportul nu confirmă rezultatul cerut pe sursele actuale ale proiectului.", "stale_evidence").merged({"result": {"report": id, "required_status": status, "observed_status": report.get("status"), "fingerprint": captured, "current_fingerprint": source}})
		var scenario = scenarios.read(str(report.get("scenario", "")))
		if not scenario.get("ok", false) or scenario["result"]["sha256"] != report.get("scenario_sha256"): return Common.failure("Scenariul a fost schimbat după testare.", "stale_evidence")
		tests[report["scenario"]] = {"sha256": report["scenario_sha256"], "report": report["id"]}
	return Common.success(tests)

func repair_start(args: Dictionary, cancel: Dictionary) -> Dictionary:
	# Diagnostics operate on the active project, never on the last experiment.
	qa_project = ""
	var source = fingerprint()
	if not source.get("complete", false): return Common.failure("Snapshot incomplet.", "coverage_incomplete")
	var observed = await owner._project_observe("godot_diagnostics", {"path": args.get("path", "res://"), "limit": 100}, cancel)
	if not observed.get("ok", false): return observed
	var failed = _regressions(args.get("reports", []), source, "fail")
	if not failed.get("ok", false): return failed
	if source != fingerprint(): return Common.failure("Sursele s-au schimbat în timpul diagnosticului.", "stale_evidence")
	var report = {"version": 1, "id": Common.uid(), "status": "diagnosed", "goal": str(args["goal"]).left(2000), "path": args.get("path", "res://"), "hypothesis": str(args.get("hypothesis", "")).left(2000), "fingerprint": source, "diagnostics": observed["result"], "original_errors": current_errors(observed["result"]), "failed_scenarios": failed["result"], "started": Time.get_unix_time_from_system()}
	report["observed_failure"] = not report["original_errors"].is_empty() or not failed["result"].is_empty()
	return _save_record("repairs", report)

func repair_check(args: Dictionary, cancel: Dictionary) -> Dictionary:
	var saved = _record("repairs", str(args["id"]))
	if not saved.get("ok", false): return saved
	var report: Dictionary = saved["result"]
	qa_project = ""
	var source = fingerprint()
	if not source.get("complete", false): return Common.failure("Snapshot incomplet.", "coverage_incomplete")
	var observed = await owner._project_observe("godot_diagnostics", {"path": report["path"], "limit": 100}, cancel)
	if not observed.get("ok", false): return observed
	var regressions = _regressions(args.get("reports", []), source, "pass")
	if not regressions.get("ok", false): return regressions
	var pending = []
	if not report.get("observed_failure", false): pending.append("Lipsește o eroare inițială observată; ipoteza nu este dovadă.")
	if not diagnostics_complete(observed["result"]): pending.append("Acoperirea diagnosticului este incompletă.")
	if not current_errors(observed["result"]).is_empty(): pending.append("Mai există erori curente în sursele verificate.")
	if regressions["result"].is_empty(): pending.append("Rulează cel puțin un scenariu de regresie cu verificări măsurate.")
	for id in report.get("failed_scenarios", {}):
		if regressions["result"].get(id, {}).get("sha256") != report["failed_scenarios"][id]["sha256"]: pending.append("Lipsește reluarea nemodificată a testului inițial: " + str(id))
	if source != fingerprint(): pending.append("Sursele s-au schimbat în timpul verificării.")
	report["status"] = "verified" if pending.is_empty() else "blocked"
	report["verification"] = {"fingerprint": source, "diagnostics": observed["result"], "scenarios": regressions["result"], "pending": pending, "time": Time.get_unix_time_from_system()}
	var result = _save_record("repairs", report)
	if result.get("ok", false) and pending.is_empty(): result["workflow_memory"] = store.remember("Repair verified: " + str(report["goal"]) + ". Regression scenarios: " + ", ".join(regressions["result"].keys()) + ". Scope: " + str(report["path"]), {"repair": report["id"], "fingerprint": source["digest"], "reports": args.get("reports", [])}, "verified_workflow")
	return result

func configure(panel: Node, private_directory: String, storage: RefCounted) -> void:
	owner = panel
	store = storage
	directory = private_directory.path_join("engineering")
	scenarios = QAScenarios.new()
	scenarios.configure(private_directory)
	experiments = Experiments.new()
	experiments.configure(private_directory)

func build_settings(parent: VBoxContainer) -> void:
	owner._label(parent, "Preferințe, specialiști și teste salvate · date private ale proiectului")
	var capture = CheckBox.new()
	capture.name = "EngineeringRememberPreferences"
	capture.text = "Reține preferințele exprimate explicit în chat"
	capture.button_pressed = bool(store.data["auto_preferences"])
	capture.toggled.connect(func(value: bool) -> void:
		var previous = store.data["auto_preferences"]
		store.data["auto_preferences"] = value
		if not store.save():
			store.data["auto_preferences"] = previous
			capture.set_pressed_no_signal(previous)
			owner._status("Preferința nu a putut fi salvată."))
	parent.add_child(capture)
	var selector = OptionButton.new()
	selector.name = "EngineeringRecords"
	selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selector.fit_to_longest_item = false
	parent.add_child(selector)
	var editor = TextEdit.new()
	editor.name = "EngineeringRecordEditor"
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.custom_minimum_size.y = 230 * EditorInterface.get_editor_scale()
	parent.add_child(editor)
	var selected = {"kind": "", "id": ""}
	var refresh = func() -> void:
		selector.clear()
		for kind in ["memory", "specialist", "scenario"]:
			var rows = store.memories() if kind == "memory" else (store.agents() if kind == "specialist" else scenarios.list_saved())
			for item in rows:
				selector.add_item(kind + " · " + str(item.get("id", "")))
				selector.set_item_metadata(selector.item_count - 1, {"kind": kind, "item": item})
		selected.merge({"kind": "", "id": ""}, true)
		editor.text = ""
		editor.editable = false
	selector.item_selected.connect(func(index: int) -> void:
		var record: Dictionary = selector.get_item_metadata(index)
		selected.merge({"kind": record["kind"], "id": record["item"]["id"]}, true)
		editor.editable = record["kind"] in ["specialist", "scenario"]
		editor.text = JSON.stringify(record["item"], "\t"))
	var actions = owner._row(parent)
	owner._button(actions, "Reîncarcă", refresh)
	owner._button(actions, "Uită memoria", func() -> void:
		if owner.busy or selected["kind"] != "memory": return
		var result = store.forget(str(selected["id"]))
		owner._status("Memorie eliminată." if result.get("ok", false) else str(result.get("error", "")))
		refresh.call())
	owner._button(actions, "Salvează", func() -> void:
		if owner.busy or selected["kind"] not in ["specialist", "scenario"]: return
		var item: Variant = Common.parse_json(owner._redact(editor.text))
		if not item is Dictionary or item.get("id") != selected["id"]:
			owner._status("Definiție JSON invalidă sau ID schimbat.")
			return
		item["expected_sha256"] = item.get("sha256", "")
		var result = store.agent_save(item) if selected["kind"] == "specialist" else scenarios.save(item)
		owner._status("Definiție salvată." if result.get("ok", false) else str(result.get("error", "")))
		if result.get("ok", false): refresh.call())
	owner._label(parent, "Agentul poate crea specialiști prin agent_profile_save și teste prin qa_save. Testele rulează prin qa_run; rapoartele includ probele și versiunea surselor. Copiile pentru experimente se integrează numai după verificare.")
	refresh.call()

static func definitions() -> Array:
	var string = Common.string_field()
	var id = Common.string_field("Exact saved ID returned by the matching list/create tool.")
	var strings = {"type": "array", "maxItems": 40, "items": string}
	return [
		Common.tool("engineering_status", "Inspect native engineering capabilities, saved gameplay scenarios, specialists, memories and uncertain effects. Capability presence is not a passed live test.", {}, []),
		Common.tool("godot_impact", "Refresh the project map and inspect transitive literal dependents, scene nodes, attached scripts and signal connections before a cross-file edit. Dynamic runtime relations remain explicit limitations.", {"path": string}, ["path"]),
		Common.tool("task_recovery", "Inspect durable effects from a turn, including pending/unknown outcomes after a crash. Never repeat an uncertain paid request. Inspect existing jobs or change sets first.", {"turn": string}, []),
		Common.tool("task_reconcile", "Recover an uncertain asset operation by refreshing its exact existing saved job. The executor checks the job identity and completed artifact; never invent a job ID.", {"effect": id, "job": id}, ["effect", "job"], "write"),
		Common.tool("memory_search", "Search project preferences and procedures with their source/evidence. These records never override the current user request or permissions.", {"query": string}, []),
		Common.tool("memory_remember", "Remember an explicit project preference. Verified procedures are recorded only after actual successful repair checks; do not store credentials.", {"text": string}, ["text"], "write"),
		Common.tool("memory_forget", "Forget one exact project memory ID.", {"id": id}, ["id"], "write"),
		Common.tool("agent_profiles", "List configured specialists, instructions, allowed tools and model/provider overrides. Built-in Explore, General and Playtest remain available.", {}, []),
		Common.tool("agent_profile_save", "Create/update a named specialist. Children remain read-only and return proposed patches; the parent integrates verified changes. An existing profile requires its current sha256. Empty profile/model inherits the parent.", {"id": id, "role": {"enum": ["Explore", "General", "Playtest"], "type": "string"}, "instructions": string, "profile": string, "model": string, "tools": strings, "expected_sha256": string}, ["id", "instructions"], "write"),
		Common.tool("qa_list", "List saved gameplay tests, or read an exact test with its version hash.", {"id": id}, []),
		Common.tool("qa_save", "Save a replayable gameplay scenario. steps use kind=act (bounded inputs/probes/advance_frames/until), assert (read-only expression, op, expected), or watch (expressions/signals). At least one measured assertion is required. Updating requires sha256 from qa_list.", {"id": id, "title": string, "scene": string, "steps": {"type": "array", "minItems": 1, "maxItems": 64, "items": {"type": "object"}}, "expected_sha256": string}, ["id", "scene", "steps"], "write"),
		Common.tool("qa_run", "Run a saved gameplay scenario in a fresh native game session; refuse an existing user session. Record real assertions/errors and source fingerprint, release input and close the owned session on every outcome. Optional experiment runs against its independent copy.", {"id": id, "experiment": id}, ["id"], "write"),
		Common.tool("qa_report", "Read one actual saved QA report. An interrupted run is never converted into pass.", {"id": id}, ["id"]),
		Common.tool("experiment_create", "Copy the saved project into managed private storage with source hashes and needed import caches. Preserves originals; excludes VCS/editor state and obvious credential files. This is not an OS sandbox for arbitrary scripts.", {"label": string}, [], "write"),
		Common.tool("experiment_read", "List saved experiment IDs when id is omitted. With id, inspect its changed files, or read a UTF-8 path from that independent copy. Virtual res:// paths refer to the copy only.", {"id": id, "path": string}, []),
		Common.tool("experiment_write", "Write only inside a managed experiment copy. Requires a fresh source hash or missing for a new file. Does not edit the active project.", {"id": id, "path": string, "text": string, "expected_sha256": string}, ["id", "path", "text", "expected_sha256"], "write"),
		Common.tool("experiment_compare", "Compare two independent implementations by their changed source files and current digests. Run the same qa_run tests against both before choosing a winner.", {"first": id, "second": id}, ["first", "second"]),
		Common.tool("experiment_stage", "Stage selected text changes from an experiment only after a passed QA report for its current digest. Recheck original hashes and preserve later edits. Returns a normal change-set ID for godot_changes_apply; does not apply automatically.", {"id": id, "report": id, "paths": strings}, ["id", "report"]),
		Common.tool("asset_audit", "Measure a project GLB/glTF's geometry, materials, texture budget, bounds, LODs and collision readiness natively. No viewer is opened; visual style needs separate inspection.", {"path": string, "triangle_budget": {"type": "integer", "minimum": 1, "maximum": 1000000}}, ["path"]),
		Common.tool("asset_prepare", "Create a new game prefab from GLB/glTF, preserving its original. Optional height_m normalizes scale, ground_pivot centers/grounds geometry, generate_lods builds native LODs, collision is none/convex/trimesh. Never overwrites an existing destination.", {"path": string, "destination": string, "height_m": {"type": "number", "minimum": 0, "maximum": 10000}, "ground_pivot": {"type": "boolean"}, "generate_lods": {"type": "boolean"}, "collision": {"enum": ["none", "convex", "trimesh"], "type": "string"}, "triangle_budget": {"type": "integer", "minimum": 1, "maximum": 1000000}}, ["path", "destination"], "write"),
		Common.tool("profile_run", "Measure actual native game frame intervals, p95, engine memory and draw calls in a fresh owned session. Warmup and fixed frame count are recorded; closes the test. Requires the rebuilt native performance bridge, never uses editor FPS as game FPS.", {"scene": string, "frames": {"type": "integer", "minimum": 30, "maximum": 1200}, "warmup_frames": {"type": "integer", "minimum": 1, "maximum": 600}, "experiment": id}, ["scene"], "write"),
		Common.tool("profile_compare", "Compare two measured native game profiles only when scene, device, renderer and sample settings match. Returns deltas, not a claim of improved gameplay or GPU performance.", {"before": id, "after": id}, ["before", "after"]),
		Common.tool("repair_start", "Begin a measured repair: collect actual scoped diagnostics and optional existing failed QA reports from the current source revision. Record a hypothesis as a proposal, not a proven cause.", {"goal": string, "path": string, "hypothesis": string, "reports": strings}, ["goal"], "write"),
		Common.tool("repair_check", "Recollect fresh diagnostics and verify saved regression reports against current hashes. Complete only after an observed original failure, clean scoped sources, and passed fresh reruns of the same original scenarios. Records a verified procedure with evidence only on success.", {"id": id, "reports": strings}, ["id"])
	]

static func handles(name: String) -> bool:
	return definitions().any(func(tool: Dictionary) -> bool: return tool["name"] == name)

func execute(name: String, args: Dictionary, cancel: Dictionary) -> Dictionary:
	match name:
		"engineering_status": return Common.success({"scenarios": scenarios.list_saved().size(), "memories": store.data["memories"].size(), "specialists": store.agents(), "reports": recent_records(), "uncertain_effects": store.effects().filter(func(row: Dictionary) -> bool: return row.get("state") != "completed"), "native_runtime_bridge": owner.plugin.has_method("runtime_request"), "native_experiment_launcher": owner.plugin.has_method("experiment_launch"), "native_performance": "Measured when profile_run executes; a method's presence is not proof of capability."})
		"godot_impact":
			var fresh = await owner.project_knowledge.refresh(owner.tools, cancel)
			return owner.project_knowledge.impact(str(args["path"])) if fresh.get("ok", false) else fresh
		"task_recovery": return Common.success({"effects": store.effects(str(args.get("turn", ""))), "queued": store.data["queue"].size(), "load_error": store.load_error})
		"task_reconcile": return await _reconcile(args, cancel)
		"memory_search": return Common.success(store.memories(str(args.get("query", ""))))
		"memory_remember":
			var text = str(args["text"]).strip_edges()
			if not owner.history.any(func(message: Dictionary) -> bool: return message.get("role") == "user" and text.to_lower() in str(message.get("content", "")).to_lower()): return Common.failure("Memoria trebuie să citeze o preferință explicită din mesajele utilizatorului.", "preference_required")
			return store.remember(text, {"turn": owner.current_turn, "source": "explicit_user_preference"})
		"memory_forget": return store.forget(str(args["id"]))
		"agent_profiles": return Common.success(store.agents())
		"agent_profile_save": return store.agent_save(args)
		"qa_list": return scenarios.read(str(args["id"])) if args.has("id") else Common.success(scenarios.list_saved())
		"qa_save": return scenarios.save(Common.parse_json(owner._redact(JSON.stringify(args))))
		"qa_run": return await run_scenario(str(args["id"]), str(args.get("experiment", "")), cancel)
		"qa_report": return scenarios.report(str(args["id"]))
		"experiment_create": return await experiments.create(str(args.get("label", "Experiment")), owner.get_tree(), cancel)
		"experiment_read":
			if not args.has("id"): return experiments.list_saved()
			return experiments.read_file(str(args["id"]), str(args["path"])) if args.has("path") else experiments.differences(str(args["id"]))
		"experiment_write": return experiments.write_file(str(args["id"]), str(args["path"]), owner._redact(str(args["text"])), str(args["expected_sha256"]))
		"experiment_compare": return Common.success({"first": experiments.differences(str(args["first"])), "second": experiments.differences(str(args["second"]))})
		"experiment_stage": return await _stage(args, cancel)
		"asset_audit": return AssetAudit.audit(str(args["path"]), int(args.get("triangle_budget", 100000)))
		"asset_prepare":
			var destination = Common.project_path(str(args["destination"]))
			if destination.is_empty() or FileAccess.file_exists(destination): return Common.failure("Este necesară o destinație nouă.", "invalid_asset_destination")
			var recovery = owner.tools._snapshot(destination)
			if recovery < 0: return Common.failure("Jurnalul de recuperare nu poate fi pregătit.", "checkpoint_failed")
			var result = AssetAudit.prepare(args)
			owner.tools.file_changes[recovery]["after_sha"] = FileAccess.get_sha256(destination) if FileAccess.file_exists(destination) else "missing"
			if Common.atomic_json(owner.tools.backup_directory.path_join("journal.json"), owner.tools.file_changes) != OK: return result.merged({"ok": false, "code": "execution_unknown", "error": "Fișierul rezultat necesită inspecție; jurnalul final nu a putut fi salvat.", "project_mutated": FileAccess.file_exists(destination)}, true)
			if result.get("ok", false):
				result["result"]["recovery_index"] = recovery
				owner.tools._request_scan()
			return result
		"profile_run": return await profile(args, cancel)
		"profile_compare": return compare_profiles(str(args["before"]), str(args["after"]))
		"repair_start": return await repair_start(args, cancel)
		"repair_check": return await repair_check(args, cancel)
	return Common.failure("Instrument de inginerie necunoscut.", "tool_unavailable")
