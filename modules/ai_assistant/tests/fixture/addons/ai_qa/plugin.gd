@tool
extends EditorPlugin

var embedded: Dictionary = {}
var panel: Control
var failures: Array = []
var checks = 0
var native = false

func _has_main_screen() -> bool: return not ClassDB.class_exists("AIAssistantEditorPlugin")
func _get_plugin_name() -> String: return "AI Assistant QA"
func _make_visible(value: bool) -> void:
	if is_instance_valid(panel) and not native: panel.visible = value

class FixtureVault:
	extends RefCounted
	var values = {}
	func read(name: String) -> String: return str(values.get(name, ""))
	func store(name: String, value: String) -> bool:
		values[name] = value
		return true
	func erase(name: String) -> bool: return values.erase(name)

class FixtureProvider:
	extends RefCounted
	var requests = 0
	var call_id = "fixture-native-write"
	func complete(_profile: Dictionary, _messages: Array, _tools: Array, _model: String, _effort: String, _cancel: Dictionary, delta: Callable) -> Dictionary:
		requests += 1
		var calls = []
		if requests == 1: calls = [{"id": call_id + "-describe", "name": "tool_describe", "arguments": {"name": "godot_create_node"}}]
		if requests == 2: calls = [{"id": call_id, "name": "godot_create_node", "arguments": {"type": "Node3D", "name": "HarnessProbe"}}]
		var text = "" if requests <= 2 else "Verificat în editor."
		if not text.is_empty(): delta.call(text)
		return {"ok": true, "message": {"role": "assistant", "content": text, "tool_calls": calls}, "calls": calls, "finish": "stop"}

func _enter_tree() -> void:
	if OS.get_environment("GODOT_AI_QA_SOURCE").is_empty(): return
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("AI editor verification: " + label)

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	while EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
	await get_tree().process_frame
	var directory = OS.get_environment("GODOT_AI_QA_SOURCE")
	var bindings = {"common": "Common", "transport": "Transport", "tool_registry": "ToolRegistry", "providers": "Providers", "editor_tools": "Tools", "mcp": "MCP", "assets": "Assets", "accounts": "Accounts", "conversations": "Conversations", "icons": "Icons", "chat_view": "ChatView", "harness": "Harness", "agent_jobs": "AgentJobs", "speech": "Speech"}
	for name in ["common", "transport", "tool_registry", "providers", "editor_tools", "mcp", "assets", "accounts", "conversations", "icons", "chat_view", "harness", "agent_jobs", "speech", "panel"]:
		var script = GDScript.new()
		script.source_code = FileAccess.get_file_as_string(directory.path_join("runtime/" + name + ".gd"))
		var error = script.reload()
		_check(error == OK, "Compile " + name)
		if error != OK:
			get_tree().quit(1)
			return
		for dependency in embedded: script.set(bindings[dependency], embedded[dependency])
		embedded[name] = script
	panel = EditorInterface.get_base_control().find_child("AIAssistantPanel", true, false)
	native = panel != null
	if not native:
		panel = embedded["panel"].new()
		panel.configure(self, FixtureVault.new())
		EditorInterface.get_editor_main_screen().add_child(panel)
	EditorInterface.set_main_screen_editor("AI Assistant" if native else "AI Assistant QA")
	await get_tree().process_frame
	_check(panel.profile_picker != null and panel.settings_tabs.get_tab_count() == 10, "Build all settings forms")
	await _chat_workflow_tests()
	await _layout_tests()
	await get_tree().process_frame
	_check(panel.chat.thread.size.x >= minf(740 * EditorInterface.get_editor_scale(), panel.chat.scroll.size.x - 40 * EditorInterface.get_editor_scale()), "Chat column uses the available readable width")
	_check(panel.chat.thread.size.x <= 760 * EditorInterface.get_editor_scale() + 1, "Chat column stays within 760 logical pixels")
	_check(panel.chat.sidebar.visible == (panel.chat.size.x / EditorInterface.get_editor_scale() >= 900), "History sidebar responds to available workspace width")
	var scene = EditorInterface.get_edited_scene_root()
	if scene == null:
		scene = Node3D.new()
		scene.name = "AITestRoot"
		EditorInterface.add_root_node(scene)
	await get_tree().process_frame
	await _harness_editor_tests(scene)
	await _code_tool_tests()
	var toolset = panel.tools
	var created = toolset.execute("godot_create_node", {"type": "Node3D", "name": "AIProbe"}, 2, true)
	_check(created.get("ok", false), "Create scene node")
	var probe = scene.get_node_or_null("AIProbe")
	_check(probe != null, "Created node exists in live scene")
	if probe != null:
		var handle = str(created["result"]["handle"])
		var set_result = toolset.execute("godot_set", {"handle": handle, "property": "position", "value": {"$type": "Vector3", "value": [1, 2, 3]}}, 2, true)
		_check(set_result.get("ok", false) and probe.position == Vector3(1, 2, 3), "Set typed scene property")
		toolset.execute("godot_undo", {}, 2, true)
		_check(probe.position == Vector3.ZERO, "Undo scene property")
		toolset.execute("godot_redo", {}, 2, true)
		_check(probe.position == Vector3(1, 2, 3), "Redo scene property")
		var written = toolset.execute("godot_write_file", {"path": "res://ai_test_probe.gd", "text": "@tool\nextends Node3D\nvar counter = 0\nvar held: bool:\n\tget: return Input.is_action_pressed(\"ui_accept\")\nfunc _ready():\n\tRenderingServer.set_default_clear_color(Color(0.2, 0.1, 0.4))\nfunc _input(event):\n\tif event.is_action_pressed(\"ui_accept\"): counter += 1\nfunc fixture_method():\n\treturn 42\n"}, 2, true)
		_check(written.get("ok", false), "Write project script with recovery journal")
		await get_tree().process_frame
		while EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
		var attached = toolset.execute("godot_attach_script", {"path": "AIProbe", "script": "res://ai_test_probe.gd"}, 2, true)
		_check(attached.get("ok", false) and probe.has_method("fixture_method"), "Attach project script")
		var called = toolset.execute("godot_call", {"handle": handle, "method": "fixture_method", "arguments": []}, 2, true)
		_check(called.get("ok", false) and called.get("result") == 42, "Call a script-defined method")
		var scene_result = toolset.execute("godot_save_scene", {"path": "res://ai_test_scene.tscn"}, 2, true)
		_check(scene_result.get("ok", false) and scene_result.get("result", {}).get("saved", false), "Save live scene")
		var before = FileAccess.get_file_as_string("res://ai_test_probe.gd")
		var changed = toolset.execute("godot_write_file", {"path": "res://ai_test_probe.gd", "text": before + "\n# temporary fixture edit\n"}, 2, true)
		var restored = toolset.execute("godot_restore_file", {"index": changed.get("result", {}).get("recovery_index", -1)}, 2, true)
		_check(restored.get("ok", false) and FileAccess.get_file_as_string("res://ai_test_probe.gd") == before, "Restore previous file bytes")
	# Check grouped rollback and conflicts against real editor state, not just a mock.
	if probe != null:
		toolset.turn_id = "fixture-restore"
		toolset.execute("godot_set", {"handle": str(created["result"]["handle"]), "property": "position", "value": {"$type": "Vector3", "value": [9, 8, 7]}}, 2, true)
		toolset.execute("godot_write_file", {"path": "res://ai_restore_probe.txt", "text": "AI content"}, 2, true)
		var manual = FileAccess.open("res://ai_restore_probe.txt", FileAccess.WRITE)
		manual.store_string("Manual content")
		manual.close()
		var conflict = toolset.restore_turn("fixture-restore")
		_check(conflict.get("code") == "restore_conflict" and probe.position == Vector3(9, 8, 7), "Rollback conflict preserves manual bytes and scene")
		manual = FileAccess.open("res://ai_restore_probe.txt", FileAccess.WRITE)
		manual.store_string("AI content")
		manual.close()
		var rollback = toolset.restore_turn("fixture-restore")
		_check(rollback.get("ok", false) and not FileAccess.file_exists("res://ai_restore_probe.txt") and probe.position == Vector3(1, 2, 3), "Grouped rollback restores file and native scene Undo")
		toolset.turn_id = ""
	if native:
		await _native_runtime_tests()
		hide_bottom_panel()
	await _populated_chat_tests()
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		await get_tree().create_timer(0.5).timeout
		var image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		_check(image != null and not image.is_empty(), "Render editor panel")
		if image != null and not image.is_empty(): image.save_png(output.path_join("editor-panel.png"))
		panel.chat.follow_bottom = true
		panel.chat._follow()
		await get_tree().create_timer(0.2).timeout
		image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("conversation-bottom.png"))
		panel.open_settings("providers")
		await get_tree().create_timer(0.5).timeout
		print("AI settings dimensions: ", panel.settings_window.size)
		_check(panel.settings_window.size.y <= DisplayServer.screen_get_size().y, "Settings dialog fits the display height")
		_check(panel.settings_window.size.x <= DisplayServer.screen_get_size().x, "Settings dialog fits the display width")
		image = panel.settings_window.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("settings.png"))
		panel.open_settings("accounts")
		await get_tree().create_timer(0.2).timeout
		image = panel.settings_window.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("accounts-chatgpt.png"))
		panel.account_service.select(1)
		panel._select_account_service()
		await get_tree().create_timer(0.2).timeout
		image = panel.settings_window.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("accounts-claude.png"))
		panel.account_service.select(0)
		panel._select_account_service()
		panel.open_settings("generation")
		await get_tree().create_timer(0.3).timeout
		image = panel.settings_window.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("generation.png"))
		panel.settings_window.hide()
		panel.chat._open_options()
		await get_tree().create_timer(0.2).timeout
		image = panel.chat.runtime_options.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("chat-options.png"))
		panel.chat.runtime_options.hide()
		await _drawer_screenshots(output)
	print("Godot AI editor: %s checks, %s failures" % [checks, failures.size()])
	if not output.is_empty():
		var file = FileAccess.open(output.path_join("editor-report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	get_tree().quit(0 if failures.is_empty() else 1)

func _exit_tree() -> void:
	if is_instance_valid(panel) and not native: panel.queue_free()

func _rpc(command: String, args: Dictionary = {}) -> Dictionary:
	var id = panel.plugin.runtime_request(command, args)
	if id < 0: return {"ok": false, "error": "No debugger session"}
	var deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var result = panel.plugin.runtime_poll(id)
		if not result.is_empty(): return result
		await get_tree().process_frame
	return {"ok": false, "error": "RPC timeout"}

func _native_runtime_tests() -> void:
	_check(panel.get_script().is_built_in() and panel.get_script().resource_path.begins_with("local://"), "Embedded scripts remain internal when saving a scene")
	var ai_button: Button
	var asset_button: Button
	for node in EditorInterface.get_base_control().find_children("*", "Button", true, false):
		if node.text == "AI Assistant": ai_button = node
		if node.text == "Asset Store": asset_button = node
	_check(ai_button != null and asset_button != null and ai_button.get_parent() == asset_button.get_parent() and ai_button.get_index() == asset_button.get_index() + 1, "Native AI tab is immediately after Asset Store")
	_check(panel.vault.store("qa-secret", "fixture-vault-test") and panel.vault.read("qa-secret") == "fixture-vault-test", "Native encrypted desktop credential store round trip")
	_check(panel.vault.erase("qa-secret") and panel.vault.read("qa-secret").is_empty(), "Native credential store erases test secret")
	EditorInterface.play_current_scene()
	var state = {}
	for attempt in range(40):
		await get_tree().create_timer(0.25).timeout
		state = await _rpc("status")
		if state.get("ok", false): break
	_check(state.get("ok", false), "Native debugger connects to running game")
	if state.get("ok", false):
		var frame = await _rpc("screenshot")
		var image = Image.new()
		var bytes = Marshalls.base64_to_raw(str(frame.get("result", {}).get("data", "")))
		_check(frame.get("ok", false) and image.load_png_from_buffer(bytes) == OK, "Capture actual game viewport through native debugger")
		if not image.is_empty(): image.save_png(OS.get_environment("GODOT_AI_QA_OUTPUT").path_join("game-viewport.png"))
		var before = await _rpc("inspect", {"path": "AIProbe", "properties": ["counter", "held"]})
		var sent = await _rpc("input", {"kind": "action", "action": "ui_accept"})
		await get_tree().create_timer(0.2).timeout
		var after = await _rpc("inspect", {"path": "AIProbe", "properties": ["counter", "held"]})
		_check(sent.get("ok", false) and after.get("result", {}).get("properties", {}).get("counter", 0) > before.get("result", {}).get("properties", {}).get("counter", 0), "Playtest input reaches the running game's script")
		await get_tree().create_timer(2.5).timeout
		var released = await _rpc("inspect", {"path": "AIProbe", "properties": ["held"]})
		_check(released.get("ok", false) and released.get("result", {}).get("properties", {}).get("held") == false, "Native watchdog releases held game input")
	EditorInterface.stop_playing_scene()
	await get_tree().create_timer(0.4).timeout

func _fixture_approval(name: String, results: Dictionary, operation_cancel: Dictionary = {}) -> void:
	results[name] = await panel._authorize({"name": name, "risk": "write"}, {}, operation_cancel)

func _harness_editor_tests(scene: Node) -> void:
	var original_service = panel.providers
	var original_profiles: Array = panel.config["providers"]
	panel.config["providers"] = [{"id": "native-harness", "name": "Fixture native", "issuer": "custom", "kind": "chat", "models": [{"id": "fixture"}]}]
	panel._refresh_profiles()
	panel._choose({"profile": "native-harness", "model": "fixture"})
	panel._new_conversation()
	var service = FixtureProvider.new()
	panel.providers = service
	panel.mode_picker.select(2)
	panel.full_control.button_pressed = true
	await panel._start_chat("Create the fixture node and verify the tool result")
	_check(not panel.busy and panel.harness.state == "completed" and service.requests == 3 and scene.get_node_or_null("HarnessProbe") != null, "Native harness discovers a tool, connects chat/model and edits the scene")
	_check(panel.history.size() == 6 and panel.history[2].get("role") == "tool" and panel.history[-1].get("content") == "Verificat în editor.", "Harness preserves discovery, tool turn and streamed assistant message")
	var snapshot: Dictionary = embedded["common"].read_json(panel.project_directory.path_join("runs").path_join(panel.current_turn + ".json"), {})
	_check(snapshot.get("status") == "completed" and snapshot.get("tool_calls") == 1, "Harness saves its settled run in private project storage")
	panel.tools.execute("godot_undo", {}, 2, true)
	_check(scene.get_node_or_null("HarnessProbe") == null, "Harness scene mutation remains compatible with native Undo")
	panel._new_conversation()
	service.requests = 0
	service.call_id = "fixture-analysis-write"
	panel.mode_picker.select(0)
	panel.full_control.button_pressed = false
	await panel._start_chat("Inspect without modifying")
	_check(not panel.busy and scene.get_node_or_null("HarnessProbe") == null and "tool_unavailable" in str(panel.history[2].get("content", "")), "Analysis mode excludes mutation tools even when the model requests one")
	panel._new_conversation()
	panel.providers = original_service
	panel.config["providers"] = original_profiles
	panel._refresh_profiles()

func _code_tool_tests() -> void:
	print("AI code tools: patch, recovery and diagnostics")
	var path = "res://ai_patch_probe.gd"
	var source = "extends Node\nvar patch_value = 1 # română 🐦\n"
	var created = panel.tools.execute("godot_write_file", {"path": path, "text": source}, 2, true)
	_check(created.get("ok", false), "Create an isolated patch fixture with normal file recovery")
	var read = panel.tools.execute("godot_read_range", {"path": path, "start_line": 2, "end_line": 2}, 0, false)
	_check(read.get("ok", false) and read["result"]["lines"][0]["line"] == 2 and read["result"]["sha256"] == source.sha256_text(), "Read ranges return exact source hashes and line numbers")
	var edits = [{"old_text": "patch_value = 1", "new_text": "patch_value = 2"}]
	var args = {"path": path, "expected_sha256": source.sha256_text(), "edits": edits}
	var before_count = panel.tools.file_changes.size()
	var preview = panel.tools.execute("godot_apply_patch", args, 2, true)
	_check(preview.get("ok", false) and preview["result"]["dry_run"] and FileAccess.get_file_as_string(path) == source and panel.tools.file_changes.size() == before_count, "Patch preview changes neither file bytes nor recovery history")
	args["dry_run"] = false
	var applied = panel.tools.execute("godot_apply_patch", args, 2, true)
	_check(applied.get("ok", false) and FileAccess.get_file_as_string(path) == source.replace("value = 1", "value = 2"), "Apply a version-checked exact patch in the real editor")
	var stale = panel.tools.execute("godot_apply_patch", args, 2, true)
	_check(stale.get("code") == "patch_conflict" and FileAccess.get_file_as_string(path) == source.replace("value = 1", "value = 2"), "A stale patch cannot overwrite a newer file")
	var restored = panel.tools.execute("godot_restore_file", {"index": applied.get("result", {}).get("recovery_index", -1)}, 2, true)
	_check(restored.get("ok", false) and FileAccess.get_file_as_string(path) == source, "Patch recovery restores the exact original file")
	var matches = panel.tools.execute("godot_search_code", {"path": path, "query": "patch_value", "limit": 1}, 0, false)
	_check(matches.get("ok", false) and matches["result"]["matches"].size() == 1 and matches["result"]["matches"][0]["line"] == 2 and matches["result"]["matches"][0]["column"] == 5, "Code search reports the real matching file, line and column")
	_check(panel.tools.execute("godot_apply_patch", args, 0, true).get("code") == "permission_denied", "Analysis mode cannot apply patches")
	while panel.tools.scan_pending or EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	EditorInterface.edit_script(load(path))
	await get_tree().process_frame
	await get_tree().process_frame
	var script_editor = EditorInterface.get_script_editor()
	var code = script_editor.get_current_editor().get_base_editor()
	var original_text = str(code.text)
	code.text = original_text + "\n# unsaved manual change\n"
	var dirty = panel.tools.execute("godot_apply_patch", args, 2, true)
	_check(dirty.get("code") == "unsaved_changes" and FileAccess.get_file_as_string(path) == source, "Patch refuses an open script with unsaved user edits")
	code.text = source
	script_editor.save_all_scripts()
	var diagnostics = panel.tools.execute("godot_script_diagnostics", {"path": path}, 0, false)
	if panel.plugin.has_method("script_diagnostics"):
		_check(diagnostics.get("ok", false) and diagnostics["result"]["valid"] and diagnostics["result"]["sha256"] == source.sha256_text(), "Native parser validates the saved GDScript and reports its hash")
		var invalid = panel.tools.execute("godot_script_diagnostics", {"path": path, "text": "extends Node\nfunc broken(:\n"}, 0, false)
		_check(invalid.get("ok", false) and not invalid["result"]["valid"] and invalid["result"]["diagnostics"].any(func(item: Dictionary) -> bool: return item.get("severity") == "error" and item.get("line", 0) >= 2), "Native parser returns structured diagnostics for an invalid draft")
		_check(FileAccess.get_file_as_string(path) == source, "Diagnosing a draft does not save it over the project script")
	else:
		_check(diagnostics.get("code") == "native_bridge_unavailable", "Upstream editor explicitly reports the missing native diagnostics bridge")
	EditorInterface.set_main_screen_editor("AI Assistant" if native else "AI Assistant QA")

func _chat_workflow_tests() -> void:
	panel.config["providers"] = [
		{"id": "qa-cloud", "name": "Fixture cloud", "issuer": "deepseek", "kind": "chat", "models": [{"id": "qa-code", "efforts": ["high"]}]},
		{"id": "qa-local", "name": "Fixture local", "issuer": "ollama", "kind": "chat", "models": [{"id": "qa-local-code"}]},
	]
	panel._refresh_profiles()
	panel._choose({"profile": "qa-cloud", "model": "qa-code", "effort": "high"})
	panel.busy = true
	panel._send_or_queue("Queued fixture instruction")
	panel._choose({"profile": "qa-local", "model": "qa-local-code"})
	_check(panel.queued.size() == 1 and panel.queued[0]["selection"]["profile"] == "qa-cloud" and panel.queued[0]["selection"]["effort"] == "high", "Queued messages retain provider, model and reasoning selection")
	panel.busy = false
	panel.queued.clear()
	panel.history = [{"role": "user", "id": "fixture-history", "content": "Preserved fixture history"}]
	panel._persist_history()
	var original = str(panel.conversations.index["active"])
	panel._choose({"profile": "qa-cloud", "model": "qa-code"})
	_check(panel.history.size() == 1 and panel.history[0]["content"] == "Preserved fixture history", "Switch providers without clearing chat")
	panel._new_conversation()
	_check(panel.history.is_empty() and panel.conversations.select(original) and panel.conversations.load_active().size() == 1, "New conversation keeps the previous transcript")
	panel.history = panel.conversations.load_active()
	panel._new_conversation()
	var original_selection = panel._selection().duplicate()
	panel.chat.model_button.pressed.emit()
	panel.chat.picker_search.text = "Fixture local"
	panel.chat.picker_search.text_changed.emit(panel.chat.picker_search.text)
	_check(panel.chat.picker.visible and panel.chat.drawer_stage == "providers" and panel.chat.picker_list.item_count == 2 and panel.chat.picker_list.get_item_text(0).contains("locale"), "Composer opens searchable provider groups in a bottom drawer")
	_tap_drawer("profile", "qa-local")
	_check(panel.chat.drawer_stage == "models" and panel.chat.picker_search.text.is_empty() and panel.chat.picker_list.item_count == 1, "Selecting a provider shows only its own models and clears the provider search")
	_tap_drawer("model", "qa-local-code")
	_check(panel.chat.drawer_stage == "reasoning" and panel.chat.picker_list.item_count == 1 and panel.chat.drawer_hint.text.contains("Nu sunt disponibile"), "Model without declared reasoning levels offers only automatic reasoning")
	_check(panel._selection() == original_selection, "Provider and model changes remain pending until reasoning is chosen")
	panel.chat._close_drawer()
	_check(panel._selection() == original_selection, "Closing the drawer discards a pending model change")
	panel.chat.model_button.pressed.emit()
	_tap_drawer("profile", "qa-cloud")
	panel.chat.picker_search.text = "qa-local-code"
	panel.chat.picker_search.text_changed.emit(panel.chat.picker_search.text)
	_check(panel.chat.picker_list.get_item_metadata(0) == null, "Model search cannot leak results from a different provider")
	panel.chat.picker_search.text = "qa-code"
	panel.chat.picker_search.text_changed.emit(panel.chat.picker_search.text)
	_tap_drawer("model", "qa-code")
	_check(panel.chat.picker_list.item_count == 2 and panel.chat.picker_list.get_item_metadata(1).get("effort") == "high", "Reasoning drawer uses the selected model's provider-declared levels")
	panel.chat.drawer_back.pressed.emit()
	_check(panel.chat.drawer_stage == "models", "Reasoning drawer can return to model selection")
	_tap_drawer("model", "qa-code")
	_tap_drawer("effort", "high")
	_check(not panel.chat.picker.visible and panel._selection() == {"profile": "qa-cloud", "model": "qa-code", "effort": "high"} and panel.chat.reasoning_button.text == "Ridicat", "Reasoning choice applies provider, model and effort together and updates composer chips")
	panel.chat.reasoning_button.pressed.emit()
	_check(panel.chat.drawer_stage == "reasoning", "Reasoning chip reopens the current model's reasoning drawer directly")
	var escape = InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	panel.chat._input(escape)
	_check(not panel.chat.picker.visible and panel._selection()["effort"] == "high", "Escape closes reasoning without changing the selection")
	var fingerprints = {}
	for entry in embedded["providers"].CATALOG:
		var texture = panel.chat.provider_icon({"issuer": entry["id"]})
		_check(texture != null and not texture.get_image().is_empty(), "Provider icon renders: " + str(entry["id"]))
		if entry["id"] != "qwen-cn": fingerprints[texture.get_image().get_data().hex_encode().sha256_text()] = true
	_check(fingerprints.size() == embedded["providers"].CATALOG.size() - 1, "Each provider identity has a distinct vector emblem; Qwen regions share the same identity")
	for service in ["Claude", "Kimi", "GitHub Copilot"]:
		_check(panel.chat.provider_icon({"kind": "companion", "name": service}) != panel.chat._icon("Accounts"), "Subscription retains its provider emblem: " + service)
	panel.mode_picker.select(1)
	panel.full_control.button_pressed = true
	panel.cancel = {"cancelled": false}
	var decisions = {}
	_fixture_approval.call_deferred("first", decisions)
	_fixture_approval.call_deferred("second", decisions)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.approval_pending and panel.approval_dialog.dialog_text.begins_with("first"), "Concurrent agent approvals have separate prompts")
	panel._decide(true)
	await get_tree().process_frame
	_check(decisions.get("first") == true and not decisions.has("second") and panel.approval_dialog.dialog_text.begins_with("second"), "One approval authorizes exactly one queued operation")
	panel._decide(false)
	await get_tree().process_frame
	_check(decisions.get("second") == false, "Second concurrent operation can be independently denied")
	panel.mode_picker.select(0)
	panel.full_control.button_pressed = false
	panel.config["providers"] = []
	panel._status("Configurează un furnizor din Setări pentru a începe.")
	panel._refresh_profiles()
	panel._render_history()

func _layout_tests() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.chat.compose_panel.get_global_rect().encloses(panel.chat.model_button.get_global_rect()) and panel.chat.model_button.get_global_rect().position.y >= panel.composer.get_global_rect().end.y, "Compact model selector stays below the input inside the composer")
	_check(not panel.chat.model_button.get_global_rect().intersects(panel.chat.reasoning_button.get_global_rect()), "Model and reasoning chips do not overlap")
	_check(not panel.effort_picker.is_visible_in_tree() and not panel.full_control.is_visible_in_tree(), "Advanced agent controls stay out of the composer")
	var mode_button = panel.chat.options_button
	var mode_text_width = mode_button.get_theme_font("font").get_string_size(mode_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, mode_button.get_theme_font_size("font_size")).x
	_check(mode_button.size.x >= mode_text_width + mode_button.get_theme_stylebox("normal").get_minimum_size().x + mode_button.get_theme_constant("icon_max_width") - 2, "Current mode icon and label fit without clipping")
	var scale = EditorInterface.get_editor_scale()
	_check(panel.chat.model_button.size.x <= 220 * scale + 1 and panel.chat.reasoning_button.size.x <= 112 * scale + 1, "Composer selection chips keep compact bounded widths")
	_check(panel.chat.model_button.size.y <= 32 * scale + 2 and panel.chat.send_button.size.y <= 32 * scale + 2 and panel.chat.options_button.size.y <= 32 * scale + 2, "Composer controls use the compact 32 pixel height")
	panel.chat._open_picker()
	await get_tree().process_frame
	await get_tree().process_frame
	print("AI drawer bounds: workspace=", panel.chat.root_column.get_global_rect(), " sheet=", panel.chat.drawer.get_global_rect(), " minimum=", panel.chat.drawer.get_combined_minimum_size())
	_check(panel.chat.root_column.get_global_rect().encloses(panel.chat.drawer.get_global_rect()), "Bottom drawer stays entirely inside the chat workspace")
	_check(panel.chat.drawer.get_global_rect().encloses(panel.chat.picker_list.get_global_rect()), "Drawer list fits inside the sheet and scrolls independently")
	panel.chat._close_drawer()
	_check(not panel.chat.stop_button.is_visible_in_tree(), "Idle chat hides Stop")
	panel.chat.set_working(true)
	_check(panel.chat.stop_button.is_visible_in_tree(), "Running chat shows Stop")
	await get_tree().process_frame
	_check(panel.chat.compose_panel.get_global_rect().encloses(panel.chat.stop_button.get_global_rect()) and panel.chat.compose_panel.get_global_rect().encloses(panel.chat.send_button.get_global_rect()), "Stop and send remain inside the composer while work is running")
	panel.chat.set_working(false)
	panel.speech.transcribing = true
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.chat.stop_button.is_visible_in_tree(), "Voice transcription keeps Stop available")
	panel.speech.transcribing = false
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not panel.chat.stop_button.is_visible_in_tree(), "Completed voice work returns to the clean composer")
	panel.open_settings("accounts")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(panel.chatgpt_section.visible and not panel.companion_section.visible, "ChatGPT login is separate from companion configuration")
	panel.account_service.select(1)
	panel._select_account_service()
	_check(not panel.chatgpt_section.visible and panel.companion_section.visible and not panel.companion_connection.visible, "Claude has its own login view and collapsed connection details")
	_check(panel.forms["companion"]["account"].text == "claude" and not panel.forms["companion"]["account"].is_visible_in_tree(), "Account selection replaces manual service name entry")
	panel.account_service.select(0)
	panel._select_account_service()
	if panel.settings_navigation.visible:
		var font = panel.settings_navigation.get_theme_font("font")
		var font_size = panel.settings_navigation.get_theme_font_size("font_size")
		var longest = 0.0
		for index in range(panel.settings_navigation.item_count): longest = maxf(longest, font.get_string_size(panel.settings_navigation.get_item_text(index), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		_check(panel.settings_navigation.size.x >= longest + 12, "Settings categories fit the actual font metrics")
	else:
		_check(panel.settings_category.visible and panel.settings_category.item_count == 10, "Compact settings use a full-width category selector")
	_check(not panel.lists["accounts"].visible and not panel.lists["general"].visible, "Empty saved lists do not create blank sections")
	var initial_size = panel.settings_window.size
	panel.settings_window.size = Vector2i(420 * EditorInterface.get_editor_scale(), initial_size.y)
	await get_tree().process_frame
	panel._layout_settings()
	_check(panel.settings_category.visible and not panel.settings_navigation.visible, "Narrow settings switch to category dropdown without clipped names")
	panel.settings_window.size = initial_size
	panel._layout_settings()
	print("AI editor UI scale: ", EditorInterface.get_editor_scale())
	panel.settings_window.hide()

func _tap_drawer(key: String, value: String) -> void:
	for index in range(panel.chat.picker_list.item_count):
		var metadata: Variant = panel.chat.picker_list.get_item_metadata(index)
		if metadata is Dictionary and metadata.get(key) == value:
			panel.chat.picker_list.item_selected.emit(index)
			return
	_check(false, "Drawer item is available: " + key + "=" + value)

func _drawer_screenshots(output: String) -> void:
	panel.config["providers"][0]["models"] = [
		{"id": "fixture-code", "name": "Coding · model de probă", "efforts": ["low", "medium", "high", "max"]},
		{"id": "fixture-fast", "name": "Chat rapid · model de probă"}]
	panel.config["providers"].append({"id": "visual-openai", "name": "OpenAI · API", "issuer": "openai", "kind": "responses", "models": [{"id": "fixture-openai"}]})
	panel.config["providers"].append({"id": "visual-ollama", "name": "Ollama · local", "issuer": "ollama", "kind": "chat", "models": [{"id": "fixture-local"}]})
	panel.config["providers"].append({"id": "visual-lmstudio", "name": "LM Studio · local", "issuer": "lmstudio", "kind": "chat", "models": [{"id": "fixture-studio"}]})
	panel.account_profiles = [{"id": "visual-subscription", "name": "ChatGPT · abonament", "kind": "siwc", "models": [{"id": "fixture-account"}]}]
	panel._refresh_profiles()
	panel._choose({"profile": "visual-provider", "model": "fixture-code", "effort": "high"})
	await get_tree().process_frame
	panel.chat._open_picker()
	await get_tree().create_timer(0.2).timeout
	var image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	image.save_png(output.path_join("drawer-providers.png"))
	_tap_drawer("profile", "visual-provider")
	await get_tree().create_timer(0.2).timeout
	print("AI model rows: list=", panel.chat.picker_list.size, " scroll max/page=", panel.chat.picker_list.get_v_scroll_bar().max_value, "/", panel.chat.picker_list.get_v_scroll_bar().page)
	_check(not panel.chat.picker_list.get_v_scroll_bar().visible, "Short model lists include row padding and need no unnecessary scrollbar")
	image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	image.save_png(output.path_join("drawer-models.png"))
	_tap_drawer("model", "fixture-code")
	await get_tree().create_timer(0.2).timeout
	image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	image.save_png(output.path_join("drawer-reasoning.png"))
	_tap_drawer("effort", "high")
	await get_tree().create_timer(0.2).timeout
	image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	image.save_png(output.path_join("composer-selector.png"))

func _populated_chat_tests() -> void:
	var scale = EditorInterface.get_editor_scale()
	panel.tools.execute("godot_write_file", {"path": "res://ai_visual_diff.txt", "text": "speed = 5\n"}, 2, true)
	panel.tools.turn_id = "visual-diff"
	panel.tools.execute("godot_write_file", {"path": "res://ai_visual_diff.txt", "text": "speed = 12\n"}, 2, true)
	panel.tools.turn_id = ""
	panel._show_changes("visual-diff")
	await get_tree().create_timer(0.2).timeout
	var changes: AcceptDialog
	for child in panel.get_children():
		if child is AcceptDialog and child.title == "Modificările execuției": changes = child
	var diff: CodeEdit = changes.find_children("*", "CodeEdit", true, false)[0]
	var additions = false
	var deletions = false
	for index in range(diff.get_line_count()):
		if diff.get_line(index) == "+ speed = 12": additions = diff.get_line_background_color(index).g > diff.get_line_background_color(index).r
		if diff.get_line(index) == "- speed = 5": deletions = diff.get_line_background_color(index).r > diff.get_line_background_color(index).g
	_check(additions and deletions, "Changes show actual before and after content with distinct colors")
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty(): changes.get_texture().get_image().save_png(output.path_join("changes.png"))
	changes.hide()
	changes.queue_free()
	_check(panel.tools.restore_turn("visual-diff").get("ok", false), "Visual diff keeps recovery operational")
	panel.chat.motion_enabled = false
	panel._status("")
	panel.history = [{"id": "visual-user", "role": "user", "content": "hei"}]
	panel._render_history()
	await get_tree().create_timer(0.2).timeout
	var user: Dictionary = panel.chat.message_records[0]
	_check(user["card"].size.x <= panel.chat.thread.size.x * 0.75 and user["card"].size.y < 90 * scale, "Short user messages have compact bubbles")
	_check(absf(user["card"].get_global_rect().end.x - user["row"].get_global_rect().end.x) < 2, "User bubbles align to the right")
	_check(not panel.chat.tasks_label.visible and not panel.chat.reference_label.visible, "Empty task and reference rows reserve no chat space")
	_check(panel.chat.scroll.size.y >= panel.chat.size.y * 0.5, "Conversation receives at least half the available workspace")
	_check(panel.chat.size.x <= panel.size.x + 2, "Message width does not force the chat outside its workspace")
	var compact_height = panel.composer.size.y
	panel.composer.text = "Linie\n".repeat(12)
	await get_tree().create_timer(0.2).timeout
	_check(panel.composer.size.y > compact_height and panel.composer.size.y <= 112 * scale + 1, "Composer grows with text up to its height limit")
	panel.composer.clear()
	panel.pending_references = ["res://example.gd"]
	panel._composer_hints()
	_check(panel.chat.attachment_chips.visible and panel.chat.attachment_chips.get_child_count() == 1, "References appear as removable chips")
	panel._chat_action("remove_attachment", {"kind": "reference", "index": 0})
	_check(panel.pending_references.is_empty() and not panel.chat.attachment_chips.visible, "Removing a reference updates the actual pending context")
	var source = "extends Node3D\n\nfunc _ready():\n\tprint(\"Salut din Godot\")"
	var answer = "Putem construi scena împreună.\n\n**Pașii propuși**\n- Verific structura proiectului.\n- Pregătesc scriptul și verific rezultatul.\n\n```gdscript\n" + source + "\n```\n\nModificările rămân disponibile pentru revizuire."
	panel.current_origin = {"origin_label": "DeepSeek · Model de probă", "turn_id": "visual-turn"}
	panel._display("assistant", "")
	var anchor = panel.transcript
	panel.chat.stream_text(anchor, answer.left(answer.length() / 2))
	await get_tree().create_timer(0.15).timeout
	panel.chat.stream_text(anchor, answer.substr(answer.length() / 2))
	await get_tree().create_timer(0.2).timeout
	var assistant: Dictionary = anchor.get_meta("message")
	var body_id = assistant["body"].get_instance_id()
	var before = assistant["card"].size.y
	_check(assistant["blocks"].size() == 3 and assistant["blocks"][1]["editor"].text == source, "Streaming renders highlighted fenced code before completion")
	var copy: Button = assistant["blocks"][1]["node"].get_child(0).get_child(1)
	copy.pressed.emit()
	_check(DisplayServer.clipboard_get() == source, "Code copy preserves source without Markdown fences")
	var completed = {"id": "visual-answer", "role": "assistant", "content": answer, "origin_label": "DeepSeek · Model de probă", "turn_id": "visual-turn"}
	panel.history.append(completed)
	panel.chat.finish_stream(anchor, completed)
	panel._finish_chat("Finalizat.")
	await get_tree().create_timer(0.2).timeout
	_check(is_instance_valid(anchor) and assistant["body"].get_instance_id() == body_id and absf(assistant["card"].size.y - before) < 2, "Completion keeps the same message widgets and layout")
	_check(not assistant["actions"][0].disabled and assistant["metadata"]["id"] == "visual-answer", "Completed message actions bind to the stored conversation message")
	panel.chat.activity("Inspectează scena · finalizat", "Fixture result")
	panel.chat.activity("Verifică scriptul · finalizat", "Fixture result")
	var group = panel.chat.activity_group
	var entries = group.get_meta("entries")
	_check(entries.get_child_count() == 2 and not entries.visible, "Operations form one collapsed activity group")
	group.get_meta("toggle").pressed.emit()
	_check(entries.visible, "Activity details expand on request")
	group.get_meta("toggle").pressed.emit()
	panel.config["providers"] = [{"id": "visual-provider", "name": "DeepSeek", "issuer": "deepseek", "kind": "chat", "url": "https://api.deepseek.com", "models": [{"id": "visual-code", "name": "Model de probă"}]}]
	panel._refresh_lists()
	panel._refresh_profiles()
	panel._edit_provider(0)
	_check(panel.provider_selector.item_count == 2 and not panel.lists["providers"].visible and not panel.provider_advanced.visible, "Saved profiles use a compact selector with advanced fields collapsed")
	_check(panel.provider_badge.text.contains("neverificată"), "Saved model metadata does not imply a verified connection")
	panel.config["providers"][0]["verified_at"] = 1
	panel._refresh_lists()
	_check(panel.provider_badge.text.contains("Conexiune verificată"), "Verified profiles show their distinct connection state")
	panel.open_settings("providers")
	await get_tree().create_timer(0.2).timeout
	var key = panel.forms["provider"]["key"]
	_check(key.is_visible_in_tree() and key.get_global_rect().end.y < panel.settings_window.size.y - 60 * scale, "API key remains visible with a saved provider")
	panel._status("Profil verificat pentru captura de test.")
	_check(panel.settings_status.visible and not panel.chat.status.visible, "Settings feedback is separate from chat status")
	_check(panel.settings_navigation.get_theme_stylebox("panel").bg_color == Color("0d1320"), "Saved lists and settings navigation use the graphite theme")
	panel.settings_window.hide()
	var was_expanded = EditorInterface.is_distraction_free_mode_enabled()
	panel.chat.expand_button.pressed.emit()
	_check(EditorInterface.is_distraction_free_mode_enabled() != was_expanded, "Header expand button controls the native editor workspace")
	panel.chat.expand_button.pressed.emit()
	panel.chat.follow_bottom = false
	panel.chat.scroll.scroll_vertical = 0
	await get_tree().create_timer(0.2).timeout
