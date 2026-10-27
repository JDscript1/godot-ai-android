@tool
extends RefCounted
## Exercises real tool effects, persistence and touch gestures in an isolated editor.

func run(host: Node, panel: Control) -> void:
	var tools = panel.tools
	host._check(tools._values_equal(Vector3(-49.999996, -34.999996, 0), Vector3(-50, -35, 0)), "Float rotation roundoff is accepted")
	host._check(not tools._values_equal(Vector3(-49.99, -35, 0), Vector3(-50, -35, 0)) and not tools._values_equal(2, 3), "Different rotations and discrete values remain rejected")
	var key = "ai_qa/typed_setting"
	var result = tools.execute("godot_set_setting", {"scope": "project", "key": key, "value": {"$type": "PackedStringArray", "value": ["one", "two"]}}, 2, true)
	host._check(result.get("ok", false) and ProjectSettings.get_setting(key) is PackedStringArray, "Typed setting decodes PackedStringArray instead of storing a Dictionary")
	var invalid = tools.execute("godot_set_setting", {"scope": "project", "key": key, "value": {"$type": "PackedStringArray", "value": [7]}}, 2, true)
	host._check(not invalid.get("ok", true) and ProjectSettings.get_setting(key) == PackedStringArray(["one", "two"]), "Invalid typed setting is rejected without changing the previous value")
	var plugins: Variant = ProjectSettings.get_setting("editor_plugins/enabled")
	var guarded = tools.execute("godot_set_setting", {"scope": "project", "key": "editor_plugins/enabled", "value": []}, 2, true)
	host._check(guarded.get("code") == "dedicated_tool_required" and ProjectSettings.get_setting("editor_plugins/enabled") == plugins, "Plugin activation uses its dedicated live tool and preserves the existing list")
	ProjectSettings.set_setting(key, null)
	ProjectSettings.save()
	var previous = EditorInterface.get_edited_scene_root()
	var previous_path = previous.scene_file_path if previous != null else ""
	var created = tools.execute("godot_create_scene", {"type": "Control", "name": "NewSceneProbe"}, 2, true)
	if panel.plugin.has_method("create_scene_root"):
		host._check(created.get("ok", false) and EditorInterface.get_edited_scene_root().name == "NewSceneProbe", "Native scene creation switches to the actual new root")
		host._check(previous == null or is_instance_valid(previous), "New native scene preserves the previous scene root")
		var child = tools.execute("godot_create_node", {"type": "Label", "name": "OnlyInNewScene"}, 2, true)
		host._check(child.get("ok", false) and (previous == null or not previous.has_node("OnlyInNewScene")), "Subsequent nodes belong to the newly created scene")
		tools.execute("godot_save_scene", {"path": "res://qa_new_scene/new_scene.tscn"}, 2, true)
		if not previous_path.is_empty(): EditorInterface.open_scene_from_path(previous_path)
	else:
		host._check(previous == null or (created.get("code") == "scene_create_failed" and EditorInterface.get_edited_scene_root() == previous), "Upstream editor reports an unavailable native new-tab bridge without a false success")
	host._check(panel._requests_preview("Deschide modelul în preview") and not panel._requests_preview("Generează un copac") and not panel._requests_preview("Nu deschide preview-ul"), "Viewer request distinguishes explicit opening from automatic generation")
	var definitions = panel.active_definitions
	panel.active_definitions = [panel._preview_definition()]
	panel.preview_requested = false
	var preview = await panel._execute_call("file_preview", {"id": "unused"})
	host._check(preview.get("code") == "preview_not_requested", "Agent cannot open the viewer without an explicit user request")
	panel.active_definitions = definitions
	panel.verification_tools.clear()
	host._check(not panel._verification_problem({"verification": "done"}).is_empty(), "A completion claim without real post-change checks is rejected")
	panel._track_verification("playtest_input")
	host._check(not panel._verification_problem({"verification": "pressed", "verification_kind": "interaction"}).is_empty(), "Input alone does not verify the resulting state")
	panel._track_verification("playtest_state")
	host._check(panel._verification_problem({"verification": "pressed +1, state count=1", "verification_kind": "interaction"}).is_empty(), "Interaction completion accepts actual input plus runtime inspection")
	panel._track_verification("godot_write_file")
	host._check(panel.verification_tools.is_empty(), "New mutations invalidate previous verification evidence")
	var before = tools.external_snapshot()
	var external_path = "res://qa_external_probe.txt"
	var file = FileAccess.open(external_path, FileAccess.WRITE)
	file.store_string("external change")
	file.close()
	var changes = tools.record_external(before, tools.external_snapshot())
	host._check(changes["changes"].any(func(item: Dictionary) -> bool: return item["path"] == external_path and item["kind"] == "external"), "External filesystem changes are tracked separately from native recovery")
	host._check(not tools.restore_turn(tools.turn_id).get("ok", true), "External changes never report a guaranteed native restoration")
	var old_main: Variant = ProjectSettings.get_setting("application/run/main_scene", "")
	ProjectSettings.set_setting("application/run/main_scene", "uid://bnonexistentqa")
	var run_state = tools.execute("godot_run_state", {}, 0, false)
	host._check(run_state.get("result", {}).get("unresolved_main_uid", false) and ProjectSettings.get_setting("application/run/main_scene") == "uid://bnonexistentqa", "Unresolved main-scene UID is diagnosed without rewriting project settings")
	ProjectSettings.set_setting("application/run/main_scene", old_main)
	var registry = host.embedded["tool_registry"].new(tools.definitions(), true)
	registry.restore([{"role": "assistant", "tool_calls": [{"name": "godot_apply_patch", "arguments": {}}]}])
	host._check(registry.loaded.has("godot_apply_patch") and registry.loaded.has("godot_script_diagnostics"), "Conversation history restores allowed schemas and their useful tool family")
	var read_registry = host.embedded["tool_registry"].new(tools.definitions().filter(func(tool: Dictionary) -> bool: return tool["risk"] == "read"), true)
	read_registry.restore([{"tool_calls": [{"name": "godot_apply_patch", "arguments": {}}]}])
	host._check(not read_registry.catalog.has("godot_apply_patch"), "Schema restoration cannot expose tools excluded by Plan mode")
	var spec = host.embedded["planner"].definition()
	var long_plan = host.embedded["tool_registry"].validate(spec, {"tasks": ["x".repeat(601)]})
	host._check(not long_plan.get("ok", true), "Plan schema declares its real step-text limit")
	var planner = host.embedded["planner"].new()
	host._check(planner.update({"tasks": ["x".repeat(601)]}).get("error", "").contains("601"), "Plan length error identifies the actual length and field")
	var assets = panel.assets
	var task = {"taskType": "getResponse", "taskUUID": "same-job"}
	var payload = {"status": 500, "json": {"data": [{"taskUUID": "same-job", "taskType": "imageInference", "status": "success", "imageURL": "https://im.runware.ai/result.png"}]}}
	host._check(assets._recover_runware_result(payload, [task]), "HTTP 500 can recover the completed result of the exact existing Runware job")
	payload["json"]["data"][0]["taskUUID"] = "different-job"
	host._check(not assets._recover_runware_result(payload, [task]), "A different Runware task cannot masquerade as recovery")
	payload["json"]["data"][0] = {"taskUUID": "same-job", "taskType": "imageInference"}
	host._check(not assets._recover_runware_result(payload, [task]), "An uncertain acknowledgement remains uncertain without an artifact")
	var old_export = panel.config["preferences"].get("journal_export_directory", "")
	var exported = panel.project_directory.path_join("qa-export")
	panel.config["preferences"]["journal_export_directory"] = exported
	panel.secrets.append("fixture-full-log-secret")
	var long_text = "full result ".repeat(1500)
	panel._record_event("qa_full_result", {"authorization": "fixture-full-log-secret"}, {"ok": true, "text": long_text, "bytes": PackedByteArray([1, 2, 3]), "images": [{"data": "private-image-pixels"}]})
	for i in 1005: panel._append_detailed_log({"test_index": i, "result": {"ok": true}})
	var log_path = panel.project_directory.path_join("logs").path_join("activity-%s-%04d.jsonl" % [panel.journal_session, panel.journal_part])
	var log_text = FileAccess.get_file_as_string(log_path)
	var matched = []
	for line in log_text.split("\n", false):
		var entry: Variant = JSON.parse_string(line)
		if entry is Dictionary and entry.get("tool") == "qa_full_result": matched.append(entry)
	host._check(matched.size() == 1 and matched[0]["result"]["text"] == long_text and log_text.split("\n", false).size() > 1000, "Detailed JSONL preserves complete text and more than 1000 events")
	host._check(not "fixture-full-log-secret" in log_text and not "private-image-pixels" in log_text and matched[0]["result"]["bytes"].get("binary_omitted", false), "Detailed logs mask secrets and omit binary/image payloads")
	var mirror = exported.path_join("godot-ai-" + panel.project_directory.get_file()).path_join(log_path.get_file())
	host._check(FileAccess.file_exists(mirror) and FileAccess.get_file_as_string(mirror).contains(long_text), "Selected export directory receives full logs without reading the API vault")
	panel.config["preferences"]["journal_export_directory"] = old_export
	panel._append_detailed_log({"padding": "x".repeat(8 * 1024 * 1024)})
	var previous_part = panel.journal_part
	panel._append_detailed_log({"after_rotation": true})
	host._check(panel.journal_part == previous_part + 1 and FileAccess.file_exists(log_path), "Full logs rotate into successive files while preserving older events")
	panel.chat.show_running_tool("godot_save_scene")
	host._check(panel.chat.running_tools is Label and panel.chat.running_tools.text == "Running Tools · godot_save_scene" and panel.chat.running_tools.get_child_count() == 0, "Running Tools is a live non-dropdown row")
	panel.chat.show_running_tool()
	host._check(panel.chat.running_tools.text == "Running Tools · —", "Running Tools clears when the operation ends")
	panel.chat.clear_messages()
	panel.chat.append_message("assistant", "Scroll probe\n".repeat(120), {"id": "qa-scroll"})
	panel.chat.show_plan({"turn": "qa-todo-plan", "phase": "executing", "steps": [{"step": "Verifică o scenă fără să lărgești conversația", "status": "in_progress"}]})
	await host.get_tree().create_timer(0.2).timeout
	panel.chat._size_messages()
	await host.get_tree().process_frame
	var plan = panel.chat.plan_cards["qa-todo-plan"]["node"]
	host._check(plan.size.x <= minf(440 * EditorInterface.get_editor_scale(), panel.chat.scroll.size.x) + 1, "Plan card stays compact inside the available dock width")
	panel.chat.follow_bottom = false
	panel.chat.scroll.scroll_vertical = 180
	await host.get_tree().process_frame
	var initial = panel.chat.scroll.scroll_vertical
	var point = panel.chat.scroll.get_global_rect().get_center()
	var press = InputEventScreenTouch.new()
	press.pressed = true
	press.position = point
	var accepted: bool = panel.chat._chat_touch(press)
	var drag = InputEventScreenDrag.new()
	drag.position = point + Vector2(0, 70)
	panel.chat._chat_touch(drag)
	host._check(accepted and panel.chat.scroll.scroll_vertical < initial, "Vertical touch over message text scrolls the conversation instead of selecting it")
	press.pressed = false
	panel.chat._chat_touch(press)
	var anchor = panel.chat.message_records[0]["blocks"][0]["node"]
	host._check(anchor.get_selected_text().is_empty(), "Scrolling touch does not create an accidental text selection")
	panel.chat.scroll.scroll_vertical = 0
	await host.get_tree().process_frame
	press.position = anchor.get_global_rect().intersection(panel.chat.scroll.get_global_rect()).get_center()
	press.pressed = true
	panel.chat._chat_touch(press)
	await host.get_tree().create_timer(0.6).timeout
	host._check(not anchor.get_selected_text().is_empty(), "Intentional long press enables text selection for copying")
	press.pressed = false
	panel.chat._chat_touch(press)
	for child in panel.chat.get_children():
		if child is PopupMenu: child.hide()
	anchor.deselect()
	panel.chat.clear_messages()
	panel.chat.append_message("user", "Verifică scena și lasă rezultatul aici.", {"id": "qa-demo-user"})
	panel.chat.show_plan({"turn": "qa-demo", "phase": "executing", "steps": [{"step": "Salvează scena", "status": "completed"}, {"step": "Verifică interacțiunea", "status": "in_progress"}, {"step": "Raportează rezultatul", "status": "pending"}]})
	panel.chat.plan_cards["qa-demo"]["toggle"].pressed.emit()
	var image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color("353952"))
	image.fill_rect(Rect2i(36, 22, 56, 88), Color("92c7a8"))
	var sample = panel.project_directory.path_join("qa-card.png")
	image.save_png(sample)
	panel.file_registry.permit(sample)
	var registered = panel.file_registry.register_file(sample, str(panel.conversations.index["active"]))
	panel.chat.file_scope = str(panel.conversations.index["active"])
	panel.chat.append_message("assistant", "Scena este salvată; verific interacțiunea.", {"id": "qa-demo-card", "files": [registered["result"]["id"]]})
	panel.chat.show_running_tool("playtest_state")
	panel.chat.follow_bottom = true
	panel.chat._follow()
	await host.get_tree().create_timer(0.15).timeout
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty():
		host._workspace_capture(output, "todo-chat")
		for placement in [1, 2]:
			panel.plugin.set_chat_placement(placement)
			await host.get_tree().create_timer(0.2).timeout
			panel.chat._size_messages()
			await host.get_tree().process_frame
			var card = panel.chat.plan_cards["qa-demo"]["node"]
			host._check(card.size.x <= panel.chat.scroll.size.x + 1, "Plan stays within dock placement " + str(placement))
			host._workspace_capture(output, "todo-dock-" + str(placement))
		panel.plugin.set_chat_placement(0)
