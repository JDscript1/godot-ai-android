@tool
extends EditorPlugin
## Opt-in test driver. Calls the installed native panel, never substitutes its runtime.
var panel: Control
var control_dir = ""
var elapsed = 0.0
var command_busy = false
var handled = ""
var request_id = ""
var last_outcome = {}
var started_at = 0
var requests = 0
var finished_at = 0

func _enter_tree() -> void:
	control_dir = str(ProjectSettings.get_setting("ai_workflow_test/control_directory", ""))
	if control_dir.is_empty(): return
	if FileAccess.file_exists(control_dir.path_join("handled.txt")): handled = FileAccess.get_file_as_string(control_dir.path_join("handled.txt"))
	set_process(true)

func _process(delta: float) -> void:
	if control_dir.is_empty(): return
	elapsed += delta
	if elapsed < 1.0: return
	elapsed = 0
	if not is_instance_valid(panel):
		panel = EditorInterface.get_base_control().find_child("AIAssistantPanel", true, false)
		if panel == null or panel.get("harness") == null: return
		panel.harness.event.connect(_event)
		_write("identity.json", {"native_panel": true, "project": ProjectSettings.globalize_path("res://"), "version": Engine.get_version_info(), "panel_sha256": panel.get_script().source_code.sha256_text(), "generation_profiles": panel.config.get("generation", []).map(func(p: Dictionary) -> Dictionary: return {"id": p.get("id"), "kind": p.get("asset_kind"), "provider": p.get("kind"), "model": p.get("model")})})
		_snapshot()
	if panel.busy or command_busy: _snapshot()
	var command: Variant = JSON.parse_string(FileAccess.get_file_as_string(control_dir.path_join("command.json"))) if FileAccess.file_exists(control_dir.path_join("command.json")) else null
	if not command is Dictionary or str(command.get("id", "")).is_empty() or str(command["id"]) == handled: return
	if command_busy and command.get("operation") != "stop": return
	handled = str(command["id"])
	var marker = FileAccess.open(control_dir.path_join("handled.txt"), FileAccess.WRITE)
	if marker != null: marker.store_string(handled); marker.close()
	match str(command.get("operation", "status")):
		"send": _send.call_deferred(command)
		"stop": panel._stop("user")
		"capture": _capture.call_deferred()
		"status": _snapshot()
		"decide":
			if panel.approval_pending: panel._decide(bool(command.get("accepted", false)))

func _send(command: Dictionary) -> void:
	if panel.busy: _write("command-error.json", {"id": handled, "error": "Agent already busy"}); return
	command_busy = true
	request_id = handled
	requests = 0
	last_outcome = {}
	started_at = Time.get_ticks_msec()
	finished_at = 0
	var original = panel._selection()
	if command.get("fresh", true): panel._new_conversation()
	var selection: Dictionary = original.duplicate(true)
	selection["work_mode"] = str(command.get("work_mode", "auto"))
	selection["effort"] = str(command.get("effort", original.get("effort", "")))
	panel._choose(selection)
	EditorInterface.set_main_screen_editor("AI Assistant")
	await panel._start_chat(str(command.get("prompt", "")), selection)
	finished_at = Time.get_ticks_msec()
	panel._choose(original)
	_write("selection-restoration.json", {"ok": panel._persist_history(), "request": request_id})
	_snapshot()
	_capture.call_deferred()
	command_busy = false

func _event(value: Dictionary) -> void:
	var kind = str(value.get("kind", ""))
	var event = {"request": request_id, "kind": kind, "time_ms": Time.get_ticks_msec()}
	match kind:
		"request_started": requests += 1; event["request_number"] = requests
		"tool_started": event.merge({"id": value.get("id"), "name": value.get("name")})
		"tool_result": event.merge({"id": value.get("id"), "name": value.get("name"), "arguments": value.get("arguments", {}), "result": value.get("result", {}), "executed": value.get("executed", false)})
		"settled":
			var result: Dictionary = value.get("result", {})
			last_outcome = {"ok": result.get("ok"), "status": result.get("status"), "code": result.get("code"), "message": result.get("message", result.get("error", "")), "requests": result.get("requests", requests)}
			finished_at = Time.get_ticks_msec()
			_snapshot.call_deferred()
			event["outcome"] = last_outcome
		"message": event["usage"] = value.get("usage", {})
		_: return
	var line = JSON.stringify(panel._journal_value(event))
	var path = control_dir.path_join("events.jsonl")
	var file = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null: file.seek_end(); file.store_line(line); file.close()

func _snapshot() -> void:
	if not is_instance_valid(panel): return
	var messages = []
	for item in panel.history:
		if item.get("role") in ["user", "assistant"] and not str(item.get("content", "")).is_empty(): messages.append({"role": item["role"], "content": panel._redact(str(item["content"]))})
	var root = EditorInterface.get_edited_scene_root()
	_write("status.json", {"request": request_id, "busy": panel.busy, "time_ms": Time.get_ticks_msec(), "duration_ms": (finished_at if finished_at > 0 else Time.get_ticks_msec()) - started_at if started_at > 0 else 0, "requests": requests, "outcome": last_outcome, "status": panel.status_label.text, "plan": panel.planner.snapshot(), "messages": messages, "scene": root.scene_file_path if root != null else "", "journal_path": panel.project_directory.path_join("journal.json"), "permission_yolo": panel.full_control.button_pressed, "approval_pending": panel.approval_pending, "approval": {"heading": panel.approval_heading.text, "target": panel.approval_target.text, "details": panel._redact(panel.approval_details.text)} if panel.approval_pending else {}, "turn_id": panel.current_turn, "conversation_id": panel.conversations.index.get("active", ""), "selection": {"profile": panel._selection().get("profile"), "model": panel._selection().get("model"), "work_mode": panel._selection().get("work_mode")}, "generation_jobs": panel.assets.jobs.map(func(j: Dictionary) -> Dictionary: return {"id": j.get("id"), "kind": j.get("kind"), "status": j.get("status"), "cost_usd": j.get("cost_usd"), "imported_path": j.get("imported_path")})})

func _write(filename: String, value: Dictionary) -> void:
	var file = FileAccess.open(control_dir.path_join(filename + ".tmp"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(value, "\t")); file.close()
	DirAccess.rename_absolute(control_dir.path_join(filename + ".tmp"), control_dir.path_join(filename))

func _capture() -> void:
	await get_tree().process_frame
	var image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	if image != null: image.save_png(control_dir.path_join("editor.png"))
