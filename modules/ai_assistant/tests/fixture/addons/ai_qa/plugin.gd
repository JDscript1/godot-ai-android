@tool
extends EditorPlugin

var embedded: Dictionary = {}
var panel: Control
var failures: Array = []
var checks = 0
var native = false
var placement = 0
var fixture_dock: EditorDock

func _has_main_screen() -> bool: return not ClassDB.class_exists("AIAssistantEditorPlugin")
func _get_plugin_name() -> String: return "AI Assistant QA"
func _make_visible(value: bool) -> void:
	if is_instance_valid(panel) and not native:
		if fixture_dock != null:
			if value: fixture_dock.make_visible()
		else: panel.visible = value

func set_chat_placement(index: int) -> void:
	if index == placement: return
	if fixture_dock != null:
		fixture_dock.remove_child(panel)
		remove_dock(fixture_dock)
		fixture_dock.queue_free()
		fixture_dock = null
	else: panel.get_parent().remove_child(panel)
	placement = index
	if index == 0:
		EditorInterface.get_editor_main_screen().add_child(panel)
		panel.custom_minimum_size = Vector2(0, 200) * EditorInterface.get_editor_scale()
		EditorInterface.set_main_screen_editor("AI Assistant QA")
	else:
		fixture_dock = EditorDock.new()
		fixture_dock.title = "AI Assistant QA"
		fixture_dock.default_slot = EditorDock.DOCK_SLOT_LEFT_UL if index == 1 else EditorDock.DOCK_SLOT_RIGHT_UL
		panel.custom_minimum_size = Vector2(200, 200) * EditorInterface.get_editor_scale()
		fixture_dock.add_child(panel)
		add_dock(fixture_dock)
		fixture_dock.make_visible()
		EditorInterface.set_main_screen_editor("3D")
	panel.show()

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

class FixtureLocalCatalog:
	extends RefCounted
	var requests = 0
	func list_models(_profile: Dictionary, _cancel: Dictionary = {}) -> Dictionary:
		requests += 1
		return {"ok": true, "result": [{"id": "unloaded-code", "loaded": false, "capabilities": {}}, {"id": "loaded-code", "loaded": true, "context": 4096, "capabilities": {}}]}

class FixtureResumeProvider:
	extends RefCounted
	var requests = 0
	var contexts: Array = []
	func complete(_profile: Dictionary, messages: Array, _tools: Array, _model: String, _effort: String, _cancel: Dictionary, delta: Callable) -> Dictionary:
		requests += 1
		contexts.append(messages.duplicate(true))
		if requests == 1:
			delta.call("Am început verificarea.")
			return {"ok": false, "code": "incomplete_stream", "error": "Fixture interrupted stream"}
		var text = "Verificare reluată fără operații duplicate."
		return {"ok": true, "message": {"role": "assistant", "content": text, "tool_calls": []}, "calls": [], "finish": "stop"}

class FixtureBlockedProvider:
	extends RefCounted
	var requests = 0
	func complete(_profile: Dictionary, _messages: Array, _tools: Array, _model: String, _effort: String, _cancel: Dictionary, _delta: Callable) -> Dictionary:
		requests += 1
		var calls = [{"id": "fixture-blocked-plan", "name": "task_update", "arguments": {"phase": "blocked", "tasks": [{"step": "Verifică diagnosticele native", "status": "pending"}], "explanation": "Bridge indisponibil."}}] if requests == 1 else []
		return {"ok": true, "message": {"role": "assistant", "content": "" if requests == 1 else "Verificarea este blocată.", "tool_calls": calls}, "calls": calls, "finish": "stop"}

class FixtureRedirectProvider:
	extends RefCounted
	var host: Control
	var requests = 0
	func complete(_profile: Dictionary, _messages: Array, _tools: Array, _model: String, _effort: String, _cancel: Dictionary, _delta: Callable) -> Dictionary:
		requests += 1
		if requests == 1:
			host._send_or_queue("Acum doar inspectează proiectul, fără generare.")
			var calls = [{"id": "superseded-generate", "name": "asset_generate", "arguments": {"profile": "missing", "prompt": "Superseded box"}}]
			return {"ok": true, "message": {"role": "assistant", "content": "", "tool_calls": calls}, "calls": calls}
		return {"ok": true, "message": {"role": "assistant", "content": "Am păstrat proiectul nemodificat.", "tool_calls": []}, "calls": [], "finish": "stop"}

class FixturePlanningProvider:
	extends RefCounted
	var requests = 0
	func complete(_profile: Dictionary, _messages: Array, _tools: Array, _model: String, _effort: String, _cancel: Dictionary, delta: Callable) -> Dictionary:
		requests += 1
		var name = ""
		var args = {}
		var phase = {1: "planning", 5: "executing", 7: "verifying", 9: "completed"}.get(requests, "")
		if not phase.is_empty():
			name = "task_update"
			args = {"phase": phase, "tasks": [{"step": "Pregătește nodul scenei", "status": "completed" if requests >= 7 else ("in_progress" if requests == 5 else "pending")}, {"step": "Verifică structura scenei", "status": "completed" if requests == 9 else ("in_progress" if requests == 7 else "pending")}], "explanation": "Două etape dependente; verific scena înainte de finalizare."}
		if requests == 3:
			name = "tool_describe"
			args = {"name": "godot_create_node"}
		if requests in [4, 6]:
			name = "godot_create_node"
			args = {"type": "Node3D", "name": "PlannedProbe"}
		if requests == 8: name = "godot_scene_tree"
		var calls = [] if name.is_empty() else [{"id": "planning-" + str(requests), "name": name, "arguments": args}]
		var text = ("Plan pregătit." if requests == 2 else "Implementat și verificat.") if name.is_empty() else ""
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
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame
	await get_tree().process_frame
	var directory = OS.get_environment("GODOT_AI_QA_SOURCE")
	var bindings = {"common": "Common", "diff": "Diff", "transport": "Transport", "tool_registry": "ToolRegistry", "providers": "Providers", "editor_tools": "Tools", "mcp": "MCP", "asset_exports": "AssetExports", "assets": "Assets", "accounts": "Accounts", "conversations": "Conversations", "icons": "Icons", "planner": "Planner", "markdown": "Markdown", "file_registry": "FileRegistry", "model_preview": "ModelPreview", "media_view": "MediaView", "chat_view": "ChatView", "harness": "Harness", "agent_jobs": "AgentJobs", "speech": "Speech", "workspace": "Workspace", "termux_blender": "TermuxBlender", "integrations": "Integrations", "store": "Store", "editor_control": "EditorControl"}
	for name in ["common", "diff", "transport", "tool_registry", "providers", "editor_tools", "mcp", "asset_exports", "assets", "accounts", "conversations", "icons", "planner", "markdown", "file_registry", "model_preview", "media_view", "chat_view", "harness", "agent_jobs", "speech", "workspace", "termux_blender", "integrations", "store", "editor_control", "panel"]:
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
	_check(panel.profile_picker != null and panel.settings_tabs.get_tab_count() == 12, "Build all settings forms")
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "blender":
		await _termux_blender_card_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "preview":
		await _model_and_control_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "activity":
		await _activity_drawer_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "files":
		await _file_chat_tests()
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "dock":
		await _configuration_screenshots(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	if OS.get_environment("GODOT_AI_QA_SCENARIO") == "terrain":
		var archive = OS.get_environment("GODOT_AI_TERRAIN3D_ZIP")
		var result = await panel.store.install_zip(archive, {"id": "tokisangames/terrain3d", "name": "Terrain3D"}, "1.0.2", {})
		_check(result.get("ok", false) and result.get("result", {}).get("files", 0) > 0, "Actual Terrain3D release installs its addon files into an isolated editor project")
		_check(FileAccess.file_exists("res://addons/terrain_3d/plugin.cfg") and FileAccess.file_exists("res://addons/terrain_3d/bin/libterrain.android.debug.arm64.so"), "Installed Terrain3D includes plugin manifest and Android ARM64 binary")
		_finish_report(OS.get_environment("GODOT_AI_QA_OUTPUT"))
		return
	await _chat_workflow_tests()
	await _history_button_tests()
	await _settings_action_tests()
	await _layout_tests()
	await _activity_drawer_tests()
	await _control_settings_tests()
	_vision_settings_tests()
	await _file_chat_tests()
	await _model_and_control_tests()
	await _store_install_tests()
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
	_reflection_tool_tests(scene)
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
		for provider_index in [2, 3, 4]:
			panel.forms["generation"]["kind"].select(provider_index)
			panel._generation_fields(provider_index, panel.forms["generation"]["workflow_fields"], true)
			await get_tree().create_timer(0.2).timeout
			image = panel.settings_window.get_texture().get_image()
			if image != null and not image.is_empty(): image.save_png(output.path_join("generation-" + panel.Assets.KINDS[provider_index] + ".png"))
		panel.settings_window.hide()
		panel.chat._open_options()
		await get_tree().create_timer(0.2).timeout
		image = panel.chat.runtime_options.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("chat-options.png"))
		panel.chat.runtime_options.hide()
		await _drawer_screenshots(output)
		await _plan_and_markdown_screenshots(output)
		await _configuration_screenshots(output)
	_finish_report(output)

func _finish_report(output: String) -> void:
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

func _reflection_tool_tests(scene: Node) -> void:
	var toolset = panel.tools
	var created = toolset.execute("godot_create_node", {"type": "MeshInstance3D", "name": "TypedReflectionProbe"}, 2, true)
	var node = scene.get_node_or_null("TypedReflectionProbe") as MeshInstance3D
	_check(created.get("ok", false) and node != null, "Create reflection regression fixture")
	if node == null: return
	var handle = str(created.result.handle)
	var mesh = toolset.execute("godot_create_resource", {"class": "BoxMesh"}, 2, true)
	var reference = {"$handle": mesh.get("result", {}).get("handle", "")}
	_check(mesh.get("result", {}).get("reference") == reference, "Object results expose a ready-to-use resource reference")
	var invalid = toolset.execute("godot_set", {"handle": handle, "property": "mesh", "value": {"handle": reference["$handle"]}}, 2, true)
	_check(invalid.get("code") == "invalid_arguments" and node.mesh == null, "A plain handle descriptor cannot silently clear a mesh while claiming success")
	invalid = toolset.execute("godot_call", {"handle": handle, "method": "set_mesh", "arguments": [{"handle": reference["$handle"]}]}, 2, true)
	_check(invalid.get("code") == "invalid_arguments" and node.mesh == null, "Generic calls reject incompatible object arguments before invoking Godot")
	var assigned = toolset.execute("godot_set", {"handle": handle, "property": "mesh", "value": reference}, 2, true)
	_check(assigned.get("ok", false) and node.mesh is BoxMesh, "Canonical object reference assigns and verifies a real BoxMesh")
	var typed = toolset.execute("godot_call", {"handle": handle, "method": "set_mesh", "arguments": [{"$type": "Object", "handle": reference["$handle"]}]}, 2, true)
	_check(typed.get("ok", false) and node.mesh is BoxMesh, "Explicit typed object references resolve inside method arguments")
	var original = node.mesh
	var stale = toolset.execute("godot_set", {"handle": handle, "property": "mesh", "value": {"$handle": "obj_missing"}}, 2, true)
	_check(stale.get("code") == "stale_handle" and node.mesh == original, "Stale resource references preserve the previous property")
	var material = toolset.execute("godot_create_resource", {"class": "StandardMaterial3D"}, 2, true)
	var wrong_class = toolset.execute("godot_set", {"handle": handle, "property": "mesh", "value": material.result.reference}, 2, true)
	_check(wrong_class.get("code") == "invalid_arguments" and node.mesh == original, "Native Resource class constraints reject a material where a mesh is required")
	var description = toolset.execute("godot_describe", {"handle": handle, "filter": "set_mesh"}, 0, false)
	var wire: Dictionary = embedded.common.json_safe(description)
	var arguments: Array = wire.get("result", {}).get("methods", [{}])[0].get("args", [])
	_check(not arguments.is_empty() and arguments[0].get("type") == TYPE_OBJECT and arguments[0].get("class_name") == "Mesh", "Reflected method argument metadata survives JSON serialization without depth truncation")
	scene.remove_child(node)
	node.queue_free()

func _harness_editor_tests(scene: Node) -> void:
	var original_service = panel.providers
	var original_profiles: Array = panel.config["providers"]
	panel.config["providers"] = [{"id": "native-harness", "name": "Fixture native", "issuer": "custom", "kind": "chat", "models": [{"id": "fixture"}]}]
	panel._refresh_profiles()
	panel._choose({"profile": "native-harness", "model": "fixture"})
	panel._new_conversation()
	var service = FixtureProvider.new()
	panel.providers = service
	panel.mode_picker.select(1)
	panel.full_control.button_pressed = true
	await panel._start_chat("Create the fixture node and verify the tool result")
	_check(not panel.busy and panel.harness.state == "completed" and service.requests == 3 and scene.get_node_or_null("HarnessProbe") != null, "Native harness discovers a tool, connects chat/model and edits the scene")
	_check(panel.history.size() == 6 and panel.history[2].get("role") == "tool" and panel.history[-1].get("content") == "Verificat în editor.", "Harness preserves discovery, tool turn and streamed assistant message")
	var snapshot: Dictionary = embedded["common"].read_json(panel.project_directory.path_join("runs").path_join(panel.current_turn + ".json"), {})
	_check(snapshot.get("status") == "completed" and snapshot.get("tool_calls") == 1, "Harness saves its settled run in private project storage")
	var journal_results = panel.journal.filter(func(item: Dictionary) -> bool: return item.get("turn_id") == panel.current_turn and item.get("tool") == "agent_tool_result")
	_check(journal_results.size() == 2 and journal_results[-1].get("arguments", {}).get("call_id") == service.call_id and journal_results[-1].get("arguments", {}).get("executed", false) and journal_results[-1].get("arguments", {}).get("duration_ms", -1) >= 0, "Activity journal correlates discovery and execution by call ID and records timing")
	panel.tools.execute("godot_undo", {}, 2, true)
	_check(scene.get_node_or_null("HarnessProbe") == null, "Harness scene mutation remains compatible with native Undo")
	panel._new_conversation()
	service.requests = 0
	service.call_id = "fixture-analysis-write"
	panel.mode_picker.select(2)
	panel.full_control.button_pressed = false
	await panel._start_chat("Inspect without modifying")
	_check(not panel.busy and scene.get_node_or_null("HarnessProbe") == null and "tool_unavailable" in str(panel.history[2].get("content", "")), "Analysis mode excludes mutation tools even when the model requests one")
	panel._new_conversation()
	panel.mode_picker.select(0)
	panel.full_control.button_pressed = true
	var planning_service = FixturePlanningProvider.new()
	panel.providers = planning_service
	await panel._start_chat("Pregătește un plan, creează nodul și verifică rezultatul")
	_check(panel.mode_picker.item_count == 3 and panel.mode_picker.get_item_text(0) == "Auto" and panel.mode_picker.get_item_text(1) == "Default" and panel.mode_picker.get_item_text(2) == "Plan", "Auto, Default and Plan are exposed as work modes")
	_check(planning_service.requests == 10 and panel.harness.state == "completed" and scene.get_node_or_null("PlannedProbe") != null, "Auto continues a proposed execution plan and completes real scene edits")
	_check(panel.history.any(func(item: Dictionary) -> bool: return item.get("tool_name") == "godot_create_node" and "plan_read_only" in str(item.get("content", ""))), "Planning blocks project writes before the explicit execution phase")
	_check(panel.history.any(func(item: Dictionary) -> bool: return item.get("tool_name") == "godot_scene_tree" and "PlannedProbe" in str(item.get("content", ""))), "The verification phase inspects the actual modified scene")
	_check(panel.planner.phase == "completed" and panel.history[-1].get("plan_snapshot", {}).get("phase") == "completed", "Completed plan state is saved with the conversation")
	panel._render_history()
	_check(panel.chat.plan_cards.size() == 1 and panel.chat.plan_cards[panel.current_turn]["toggle"].text.contains("2/2"), "Conversation restore shows one updated plan card with completed steps")
	_check(panel.chat.work_turn == panel.current_turn and panel.chat.activity_counter.text == "2/2" and panel.chat.work_plan.get("phase") == "completed", "Restoring chat also restores the latest task progress above the input")
	panel.mode_picker.select(2)
	_check(not await panel._authorize({"name": "godot_create_node", "risk": "write"}, {}), "Manual Plan refuses writes even when session writes are enabled")
	panel.tools.execute("godot_undo", {}, 2, true)
	panel._new_conversation()
	panel.providers = FixtureBlockedProvider.new()
	await panel._start_chat("Verifică și raportează blocajul real")
	var blocked_snapshot: Dictionary = embedded.common.read_json(panel.project_directory.path_join("runs").path_join(panel.current_turn + ".json"), {})
	_check(panel.harness.state == "blocked" and blocked_snapshot.get("status") == "blocked" and panel.history[-1].get("run_status") == "blocked", "A blocked plan remains blocked in harness, checkpoints and chat instead of hiding Resume as completed")
	panel._new_conversation()
	panel.mode_picker.select(1)
	var resume_service = FixtureResumeProvider.new()
	panel.providers = resume_service
	await panel._start_chat("Verifică proiectul și raportează rezultatul.")
	var interrupted_turn = panel.current_turn
	var interrupted_message = str(panel.history[-1].get("id", ""))
	panel.composer.text = "Ciornă păstrată în timpul reluării"
	await panel._resume_chat({"message": interrupted_message})
	_check(resume_service.requests == 2 and panel.current_turn == interrupted_turn and panel.history.filter(func(item: Dictionary) -> bool: return item.get("role") == "user").size() == 1, "Resume keeps the same task and does not fabricate another user message")
	_check(panel.composer.text == "Ciornă păstrată în timpul reluării" and str(resume_service.contexts[-1][0]["content"]).contains("SAME user task"), "Resume preserves the user's draft and explicitly reuses the original request context")
	await panel._resume_chat({"message": panel.history[-1]["id"]})
	_check(resume_service.requests == 2 and panel.chat.status.text.contains("deja încheiată"), "Completed tasks cannot be replayed by the resume action")
	panel.composer.clear()
	panel._new_conversation()
	var redirect_service = FixtureRedirectProvider.new()
	redirect_service.host = panel
	panel.providers = redirect_service
	await panel._start_chat("Generează o cutie 3D.")
	for frame in range(60):
		if not panel.busy and panel.queued.is_empty(): break
		await get_tree().process_frame
	_check(redirect_service.requests == 2 and panel.history[-1].get("content") == "Am păstrat proiectul nemodificat.", "A new user message interrupts the previous model turn and runs after it settles")
	_check(not panel.history.any(func(item: Dictionary) -> bool: return item.get("tool_name") == "asset_generate") and panel.history.filter(func(item: Dictionary) -> bool: return item.get("role") == "user").size() == 2, "A superseded generation cannot execute after the user's replacement request")
	var local_catalog = FixtureLocalCatalog.new()
	panel.providers = local_catalog
	panel._new_provider()
	panel._select_issuer("lmstudio")
	var local_form: Dictionary = panel.forms["provider"]
	local_form["issuer"].item_selected.emit(local_form["issuer"].selected)
	local_form["url"].text = "192.168.1.50"
	await panel._provider_save_action()
	_check(local_catalog.requests == 1 and panel._current_profile().get("url") == "http://192.168.1.50:1234/v1" and panel._selection().get("model") == "loaded-code", "Connect accepts a bare local IP, verifies its catalog and selects the loaded model in one action")
	_check(local_form["save"].text == "Conectează" and local_form["key_label"].text == "Token (opțional)" and not panel.provider_advanced.visible and local_form["groups"]["url"].visible, "Local connection exposes the address and optional token without requiring advanced settings")
	panel.open_settings("providers")
	await get_tree().create_timer(0.2).timeout
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty(): panel.settings_window.get_texture().get_image().save_png(output.path_join("settings-local-connection.png"))
	panel.settings_window.hide()
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
	_check(preview.get("result", {}).get("change_preview", [{}])[0].get("state") == "Propus", "Dry-run diff is explicitly proposed rather than applied")
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
	EditorInterface.edit_script.call_deferred(load(path))
	await get_tree().process_frame
	await get_tree().process_frame
	var script_editor = EditorInterface.get_script_editor()
	var code = script_editor.get_current_editor().get_base_editor()
	var original_text = str(code.text)
	code.text = original_text + "\n# unsaved manual change\n"
	var dirty = panel.tools.execute("godot_apply_patch", args, 2, true)
	_check(dirty.get("code") == "unsaved_changes" and FileAccess.get_file_as_string(path) == source, "Patch refuses an open script with unsaved user edits")
	code.text = source
	script_editor.save_all_scripts.call_deferred()
	await get_tree().create_timer(0.15).timeout
	while panel.tools.scan_pending or EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame
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
	_check(panel.cancel.get("reason") == "new_request" and not panel.queue_paused, "A queued steering message stops outdated work and remains scheduled after settlement")
	panel.busy = false
	panel.cancel = {}
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
	_check(not panel.chat.picker.visible and panel._selection() == original_selection.merged({"profile": "qa-cloud", "model": "qa-code", "effort": "high"}, true) and panel.chat.reasoning_button.text == "Ridicat", "Reasoning choice applies provider, model and effort together and updates composer chips")
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
	panel.mode_picker.select(0)
	panel.full_control.button_pressed = false
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
	panel.mode_picker.select(2)
	panel.full_control.button_pressed = false
	panel.config["providers"] = []
	panel._status("Configurează un furnizor din Setări pentru a începe.")
	panel._refresh_profiles()
	panel._render_history()

func _history_button_tests() -> void:
	panel._new_conversation()
	panel.history = [{"id": "audit-user", "role": "user", "content": "Transcript export fixture"}, {"id": "audit-answer", "role": "assistant", "content": "Answer fixture"}]
	panel._persist_history()
	panel._render_history()
	var id = str(panel.conversations.index["active"])
	var path = panel.conversations._path(id)
	panel.composer.text = "Draft stays with its own conversation"
	panel.chat.navigation_buttons["new"].pressed.emit()
	_check(panel.composer.text.is_empty() and panel.history.is_empty(), "New-chat button starts with an empty draft and transcript")
	panel.chat.action.emit("open", {"id": id})
	_check(panel.composer.text == "Draft stays with its own conversation" and panel.history.size() == 2, "Opening a conversation restores its own draft without mixing messages")
	var answer = panel.chat.message_records[-1]
	_check(answer["actions"][2].disabled, "Changes button is disabled for responses without any changes")
	answer["actions"][0].pressed.emit()
	_check(DisplayServer.clipboard_get() == "Answer fixture", "Message Copy button copies the selected response")
	panel.composer.clear()
	panel.chat.history_buttons["favorite"].pressed.emit()
	_check(panel.conversations.item(id)["favorite"] and "Elimină" in panel.chat.history_buttons["favorite"].tooltip_text, "Favorite button changes the active conversation and describes the reverse action")
	panel.chat.history_buttons["favorite"].pressed.emit()
	_check(not panel.conversations.item(id)["favorite"], "Favorite button can remove the same favorite")
	panel.chat.history_buttons["rename"].pressed.emit()
	var rename = panel.get_node("RenameConversation") as ConfirmationDialog
	var input = rename.find_children("*", "LineEdit", false, false)[0]
	input.text = "   "
	input.text_changed.emit(input.text)
	_check(rename.get_ok_button().disabled, "Rename rejects an empty conversation name")
	rename.get_cancel_button().pressed.emit()
	await get_tree().process_frame
	_check(panel.conversations.item(id)["title"] != "   ", "Cancel rename keeps the original title")
	panel.chat.history_buttons["rename"].pressed.emit()
	rename = panel.get_node("RenameConversation") as ConfirmationDialog
	input = rename.find_children("*", "LineEdit", false, false)[0]
	input.text = "  Audit renamed  "
	input.text_changed.emit(input.text)
	input.text_submitted.emit(input.text)
	await get_tree().process_frame
	_check(panel.chat.title.text == "Audit renamed" and panel.conversations.item(id)["title"] == "Audit renamed", "Rename submits the trimmed name and refreshes the actual chat title")
	panel.chat.history_buttons["export"].pressed.emit()
	var export_dialog = panel.get_node("ExportConversation") as FileDialog
	var export_path = panel.project_directory.path_join("audit-export.md")
	export_dialog.file_selected.emit(export_path)
	await get_tree().process_frame
	var exported = FileAccess.get_file_as_string(export_path)
	_check(exported.begins_with("# Audit renamed") and "Transcript export fixture" in exported and "Answer fixture" in exported, "Export button writes a Markdown file containing the active conversation")
	panel.chat.history_buttons["archive"].pressed.emit()
	_check(panel.conversations.item(id)["archived"] and panel.chat.archived.button_pressed and panel.chat.history_active and "Dezarhivează" in panel.chat.history_buttons["archive"].tooltip_text, "Archive keeps its conversation selected in the archive list and offers unarchive")
	panel.chat.history_buttons["archive"].pressed.emit()
	_check(not panel.conversations.item(id)["archived"] and not panel.chat.archived.button_pressed and panel.chat.history_active, "Unarchive returns the conversation to the normal history")
	panel.chat.search.text = "no matching conversation"
	panel.chat.search.text_changed.emit(panel.chat.search.text)
	_check(panel.chat.chats.item_count == 0 and panel.chat.history_buttons["delete"].disabled, "Filtered-out conversations cannot be deleted through an unrelated empty list")
	panel.chat.search.clear()
	panel.chat.search.text_changed.emit("")
	panel.busy = true
	panel.chat.set_working(true)
	_check(panel.chat.history_buttons.values().all(func(control: Button) -> bool: return control.disabled) and panel.chat.navigation_buttons["new"].disabled, "History mutations and new chat are visibly disabled while the agent works")
	panel.busy = false
	panel.chat.set_working(false)
	panel.chat.history_buttons["delete"].pressed.emit()
	var deletion = panel.get_node("DeleteConversation") as ConfirmationDialog
	_check("Audit renamed" in deletion.dialog_text and FileAccess.file_exists(path), "Delete opens a confirmation naming the unarchived conversation without deleting early")
	deletion.get_cancel_button().pressed.emit()
	await get_tree().process_frame
	_check(FileAccess.file_exists(path) and not panel.conversations.item(id).is_empty() and panel.history.size() == 2, "Cancel deletion preserves transcript, index and displayed messages")
	panel.chat.history_buttons["delete"].pressed.emit()
	deletion = panel.get_node("DeleteConversation") as ConfirmationDialog
	deletion.get_ok_button().pressed.emit()
	await get_tree().process_frame
	_check(not FileAccess.file_exists(path) and panel.conversations.item(id).is_empty() and str(panel.conversations.index["active"]) != id and panel.history == panel.conversations.load_active(), "Confirm Delete removes an unarchived transcript and displays the surviving active chat")
	var reloaded = embedded["conversations"].new()
	reloaded.configure(panel.project_directory)
	_check(reloaded.item(id).is_empty(), "Deleted conversations stay deleted after reopening their index")
	panel._new_conversation()
	panel.history = [{"id": "branch-first", "role": "user", "content": "Start"}, {"id": "branch-here", "role": "assistant", "content": "Fork here"}, {"id": "branch-later", "role": "user", "content": "Keep only in original"}]
	panel._persist_history()
	panel._render_history()
	var branch_original = str(panel.conversations.index["active"])
	var record = panel.chat.message_records[1]
	record["actions"][-1].get_popup().id_pressed.emit(0)
	_check(str(panel.conversations.index["active"]) != branch_original and panel.history.size() == 2 and panel.history[-1]["id"] == "branch-here", "Message menu forks at the selected response and excludes subsequent messages")
	var source_data: Dictionary = embedded["common"].read_json(panel.conversations._path(branch_original), {})
	_check(source_data.get("messages", []).size() == 3, "Forking through the message menu preserves the original transcript on disk")
	panel.chat.navigation_buttons["settings"].pressed.emit()
	_check(panel.settings_window.visible, "Header Settings button opens the actual settings window")
	panel.settings_window.get_ok_button().pressed.emit()
	_check(not panel.settings_window.visible, "Settings Close button closes its window")
	panel._new_conversation()
	panel.chat.search.clear()
	panel.chat.archived.set_pressed_no_signal(false)
	panel._refresh_conversations()
	DirAccess.remove_absolute(export_path)

func _settings_action_tests() -> void:
	panel._update_settings_controls()
	_check(panel.settings_actions["provider_delete"].disabled and panel.settings_actions["generation_delete"].disabled and panel.settings_actions["mcp_delete"].disabled, "Delete-profile buttons are disabled when no saved profile is being edited")
	_check(panel.settings_actions["job_preview"].disabled and panel.settings_actions["job_import"].disabled and panel.settings_actions["job_refresh"].disabled, "Generation result actions are disabled when there is no selection")
	var previous_profiles = panel.config["generation"].duplicate(true)
	var previous_jobs = panel.assets.jobs.duplicate(true)
	var previous_editing = panel.forms["generation"]["editing"]
	var path = panel.project_directory.path_join("button-preview.png")
	var image = Image.create(4, 3, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	image.save_png(path)
	panel.config["generation"] = [{"id": "button-profile", "name": "Button fixture", "kind": "openai_image", "asset_kind": "image"}]
	panel.forms["generation"]["editing"] = "button-profile"
	panel.assets.jobs = [{"id": "button-first", "profile_id": "button-profile", "kind": "image", "status": "running"}, {"id": "button-ready", "profile_id": "button-profile", "kind": "image", "status": "completed", "file": path}]
	panel._refresh_lists()
	panel.lists["jobs"].select(1)
	panel.assets.jobs.reverse()
	panel._refresh_lists()
	_check(panel._selected_job().get("id") == "button-ready" and not panel.settings_actions["job_preview"].disabled and not panel.settings_actions["job_import"].disabled, "Updating and reordering generation results preserves their stable selection and enables ready actions")
	panel.settings_actions["job_preview"].pressed.emit()
	var previews = panel.generation_preview.get_children()
	_check(previews.size() == 1 and previews[0].texture != null and previews[0].texture.get_image().get_pixel(0, 0).r > 0.9, "Generation Preview button decodes the selected result into an actual image")
	panel.assets.jobs[0]["status"] = "running"
	panel._refresh_lists()
	_check(panel.settings_actions["job_preview"].disabled and panel.settings_actions["job_import"].disabled and not panel.settings_actions["job_refresh"].disabled, "Pending generation results allow refresh while preview and import remain unavailable")
	panel.busy = true
	panel._update_settings_controls()
	_check(panel.settings_actions.values().all(func(control: Button) -> bool: return control.disabled), "Settings actions that depend on mutable selection are disabled while another operation runs")
	panel.busy = false
	panel._update_settings_controls()
	panel.settings_actions["generation_delete"].pressed.emit()
	_check(panel.config["generation"].is_empty() and panel.settings_actions["generation_delete"].disabled and panel.settings_actions["job_refresh"].disabled and FileAccess.file_exists(path), "Delete-generation-profile button removes its profile, preserves generated files and disables stale actions")
	panel.config["generation"] = previous_profiles
	panel.assets.jobs = previous_jobs
	panel.forms["generation"]["editing"] = previous_editing
	for child in panel.generation_preview.get_children():
		panel.generation_preview.remove_child(child)
		child.queue_free()
	panel._refresh_lists()
	DirAccess.remove_absolute(path)
	await get_tree().process_frame

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
	_check(panel.chat.model_button.size.x <= 150 * scale + 1 and panel.chat.reasoning_button.size.x <= 112 * scale + 1, "Composer selection chips keep compact bounded widths")
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
		_check(panel.settings_category.visible and panel.settings_category.item_count == 12, "Compact settings expose every main category through a full-width selector")
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

func _activity_capture(name: String) -> void:
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if output.is_empty(): return
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
	var geometry = {"activity": str(panel.chat.activity_panel.get_global_rect()), "composer": str(panel.chat.compose_panel.get_global_rect()), "details": str(panel.chat.activity_details.get_global_rect()), "rows": []}
	for row in panel.chat.activity_rows.get_children():
		if row.has_meta("state"): geometry.rows.append({"state": row.get_meta("state"), "size": str(row.size)})
	embedded.common.atomic_json(output.path_join(name + "-geometry.json"), geometry)

func _activity_drawer_tests() -> void:
	panel.settings_window.hide()
	var chat = panel.chat
	var saved_turn = panel.current_turn
	var saved_jobs = panel.agent_jobs.jobs
	var saved_busy = panel.busy
	chat.clear_messages()
	chat.thread.alignment = BoxContainer.ALIGNMENT_BEGIN
	chat.append_message("user", "Pregătește animațiile personajului și verifică scena.", {"id": "activity-visual-user"})
	chat.append_message("assistant", "Am verificat proiectul și scriptul. Continui cu animațiile, apoi testez scena.", {"id": "activity-visual-answer"})
	var snapshot = {"turn": "activity-visual", "phase": "executing", "intent": "execute", "steps": [{"step": "Inspectează proiectul și scena", "status": "completed"}, {"step": "Actualizează scriptul personajului", "status": "completed"}, {"step": "Pregătește animațiile personajului", "status": "in_progress"}, {"step": "Verifică tranzițiile și comenzile", "status": "pending"}, {"step": "Testează scena în editor", "status": "pending"}]}
	chat.begin_work("activity-visual", snapshot)
	panel.busy = true
	chat.show_status("Pregătesc animațiile personajului…", true)
	chat.start_operation("activity-read", "Citesc fișierul…", "res://player.gd")
	chat.finish_operation("activity-read", "Citesc fișierul…", "res://player.gd", {"ok": true})
	chat.start_operation("activity-write", "Aplic modificările…", "res://player.gd")
	chat.finish_operation("activity-write", "Aplic modificările…", "res://player.gd", {"ok": true})
	chat.start_operation("activity-animation", "Pregătesc animația…", "Player / AnimationPlayer")
	chat.set_working(true)
	await get_tree().create_timer(0.2).timeout
	_check(chat.activity_panel.get_parent() == chat.compose_panel.get_parent() and chat.activity_panel.get_index() + 1 == chat.compose_panel.get_index() and chat.activity_panel.get_global_rect().end.y <= chat.compose_panel.get_global_rect().position.y + 1, "Activity status stays immediately above the composer, outside the conversation scroll")
	_check(chat.activity_counter.text == "2/5" and not chat.activity_details.visible and chat.activity_toggle.focus_mode == Control.FOCUS_ALL, "Running activity is compact, counts real completed steps and supports keyboard focus")
	_activity_capture("activity-collapsed")
	chat.activity_toggle.pressed.emit()
	await get_tree().create_timer(0.2).timeout
	var rows = chat.activity_rows.get_children().filter(func(item: Node) -> bool: return item.has_meta("state"))
	_check(chat.activity_details.visible and rows.size() == 8 and rows[0].get_meta("state") == "completed" and rows[2].get_meta("state") == "in_progress" and rows[4].get_meta("state") == "pending", "Expanding activity reveals completed, running and pending plan steps plus actual operations")
	_check(rows.slice(0, 5).all(func(row: Node) -> bool: return row.get_child(2).is_visible_in_tree() and row.get_child(2).size.x >= row.get_child(2).get_minimum_size().x and row.get_child(2).size.x > 20 * EditorInterface.get_editor_scale() and row.get_global_rect().grow(1).encloses(row.get_child(2).get_global_rect())), "Plan state captions reserve readable width inside each activity row")
	panel.current_turn = "activity-visual"
	panel.agent_jobs.jobs = {"child-done": {"id": "child-done", "parent": "activity-visual", "task": "Verifică structura proiectului", "kind": "Explore", "status": "completed"}, "child-running": {"id": "child-running", "parent": "activity-visual", "task": "Verifică animațiile și tranzițiile", "kind": "General", "status": "running"}}
	panel.agent_jobs.changed.emit("activity-visual")
	await get_tree().create_timer(0.2).timeout
	_check(chat.work_jobs.size() == 2 and chat.work_jobs[0].status == "completed" and chat.work_jobs[1].status == "running", "Background task events populate separate completed and running tasks in the drawer")
	_check(chat.activity_details.size.y <= maxf(48 * EditorInterface.get_editor_scale(), minf(200 * EditorInterface.get_editor_scale(), chat.root_column.size.y * 0.30)) + 1 and chat.get_global_rect().grow(1).encloses(chat.compose_panel.get_global_rect()), "Expanded activity has bounded height and keeps the composer visible")
	_check(chat.activity_rows.size.x <= chat.activity_details.size.x + 1, "Activity details wrap inside the available width without horizontal overflow")
	_activity_capture("activity-expanded")
	snapshot.steps[2].status = "completed"
	snapshot.steps[3].status = "in_progress"
	chat.show_work_plan(snapshot)
	_check(chat.activity_counter.text == "3/5" and chat.activity_details.visible, "Live plan updates preserve the drawer expansion and advance only confirmed completed steps")
	chat.finish_operation("activity-animation", "Pregătește animația", "Player", {"ok": false, "code": "permission_denied", "error": "Operația nu a fost autorizată."})
	_check(chat.work_operations["activity-animation"].state == "blocked", "Denied operations remain visibly blocked rather than completed")
	snapshot.phase = "paused"
	chat.show_work_plan(snapshot)
	chat.finish_work("activity-visual", "cancelled")
	panel.busy = false
	chat.set_working(false)
	_check(chat.activity_counter.text == "3/5" and chat.status.text.contains("întreruptă") and chat.work_plan.steps[4].status == "pending", "Stopping keeps unfinished tasks visible without claiming full completion")
	await get_tree().create_timer(0.2).timeout
	_activity_capture("activity-interrupted")
	chat.show_work_jobs([])
	for item in snapshot.steps: item.status = "completed"
	snapshot.phase = "completed"
	chat.show_work_plan(snapshot)
	chat.finish_work("activity-visual", "completed")
	chat.activity_toggle.pressed.emit()
	_check(chat.activity_counter.text == "5/5" and chat.activity_panel.visible and not chat.activity_details.visible, "Completed progress remains available for later inspection in one compact row")
	chat.activity_toggle.pressed.emit()
	_check(chat.activity_details.visible, "Completed task details can be reopened")
	chat.begin_work("activity-new", {})
	panel.current_turn = "activity-new"
	panel.agent_jobs.changed.emit("activity-visual")
	_check(chat.work_plan.is_empty() and chat.work_operations.is_empty() and chat.work_jobs.is_empty() and not chat.activity_details.visible, "A new request clears previous progress and ignores events from an older task")
	panel.agent_jobs.jobs = saved_jobs
	panel.current_turn = saved_turn
	panel.busy = saved_busy
	chat.set_working(false)
	chat.reset_work()
	panel._render_history()

func _plan_and_markdown_screenshots(output: String) -> void:
	panel.mode_picker.select(0)
	panel.chat.show_plan({"turn": "visual-plan", "phase": "verifying", "intent": "execute", "steps": [{"step": "Inspectează scena și scripturile", "status": "completed"}, {"step": "Aplică modificările în proiect", "status": "completed"}, {"step": "Verifică rezultatul și importurile", "status": "in_progress"}], "explanation": "Sarcină cu mai multe etape; verific rezultatul înainte de finalizare."})
	panel.chat.append_message("assistant", "## Modificările sunt pregătite\n\nAm organizat scena și am păstrat setările existente.\n\n- Nodul **Player** folosește `CharacterBody3D`.\n- Mișcarea rămâne configurabilă din Inspector.\n\n> Urmează verificarea rezultatului în editor.\n\n| Element | Stare |\n| --- | --- |\n| Scenă | Pregătită |\n| Script | Verificat |\n\n[Documentația proiectului](https://docs.godotengine.org/)", {"id": "visual-formatted", "origin_label": "Godot AI · Auto", "profile_id": "visual-provider"})
	panel.chat.follow_bottom = true
	await get_tree().create_timer(0.2).timeout
	panel.chat._follow()
	await get_tree().create_timer(0.25).timeout
	_check(panel.chat.size.x <= panel.size.x + 2, "Formatted tables and plan steps stay inside the chat width")
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("formatted-chat.png"))
	panel.chat.plan_cards["visual-plan"]["node"].get_parent().move_child(panel.chat.plan_cards["visual-plan"]["node"], panel.chat.thread.get_child_count() - 1)
	panel.chat._follow()
	await get_tree().create_timer(0.2).timeout
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("structured-plan.png"))

func _control_settings_tests() -> void:
	_check(panel.Common.work_mode_index({"ui_mode": 1}) == 2 and panel.Common.work_mode_index({"work_mode": "default", "ui_mode": 1}) == 1, "Legacy Plan conversations restore read-only while new Default remains distinct")
	panel.mode_picker.select(1)
	_check(panel._mode() == 4 and "DEFAULT MODE" in panel._context_messages()[0]["content"] and "one or two short sentences" in panel._context_messages()[0]["content"], "Default is balanced and simple identity replies are instructed to stay compact")
	var form = panel.forms["generation"]
	form["kind"].select(2)
	panel._generation_fields(2, form["workflow_fields"], true)
	_check(form["asset_kind"].selected == 1 and form["asset_kind"].disabled and not form["allow_http"].visible and not form["groups"]["url"].visible, "Meshy form enforces GLB and fixed secure endpoint")
	form["kind"].select(4)
	panel._generation_fields(4, form["workflow_fields"], true)
	_check(form["asset_kind"].selected == 0 and form["asset_kind"].disabled and not form["workflow_import"].visible, "OpenAI Images form exposes PNG without unrelated workflow actions")
	form["kind"].select(3)
	panel._generation_fields(3, form["workflow_fields"], true)
	_check(not form["asset_kind"].disabled and form["kind"].item_count == 5, "Tripo supports both image and GLB profiles alongside existing generators")
	form["kind"].select(0)
	panel._generation_fields(0, form["workflow_fields"], true)
	_check(panel.section_tabs.has("integrations") and panel.section_tabs.has("skills") and panel.section_tabs.has("automations") and panel.section_tabs["skills"] == panel.section_tabs["integrations"] + 1 and panel.section_tabs["automations"] == panel.section_tabs["skills"] + 1 and panel.settings_tabs.get_tab_title(panel.section_tabs["agent"]) == "AGENT.MD", "Skills and tasks have main sections after Integrations")
	_check(panel.forms["general"].has("yolo") and panel.forms["general"].has("dock") and panel.forms["general"].has("sounds") and not panel.forms["general"].has("max_steps") and not panel.forms["general"].has("enabled"), "General exposes control preferences without technical runtime settings")
	_check(not "Permisiuni" in panel._settings_labels(panel.chat.runtime_options) and not "Extinde" in panel._settings_labels(panel.chat.runtime_options), "Work mode menu contains no permissions or duplicate expand action")
	panel.mode_picker.select(0)
	panel.full_control.button_pressed = false
	_check(panel._permission_mode() == 1, "YOLO off requires individual operation approval")
	panel.full_control.button_pressed = true
	_check(panel._permission_mode() == 2 and panel.config["preferences"]["yolo"], "YOLO preference is saved immediately and enables automatic operations")
	panel.mode_picker.select(2)
	_check(panel._permission_mode() == 3, "Plan stays read-only even with YOLO enabled")
	panel.mode_picker.select(0)
	panel._set_usage({"usedTokens": 500, "contextWindowTokens": 1000}, {"models": [{"id": "fixture", "context": 0}]}, "fixture")
	_check(panel.chat.context_label.text == "50%" and panel.chat.context_indicator.get_parent() == panel.chat.composer_controls, "Context filling is independently visible in the bottom toolbar and retains provider limits")
	panel._set_usage({"input_tokens": 500}, {}, "unknown")
	_check(panel.chat.context_label.text == "—" and "500" in panel.chat.context_label.tooltip_text, "Unknown context capacity never displays a fabricated percentage")
	var wave = panel._completion_stream()
	_check(wave.data.size() > 10000 and wave.mix_rate == 22050 and wave.format == AudioStreamWAV.FORMAT_16_BITS, "Completion sound is a playable native PCM asset without downloaded audio")
	panel.forms["github"]["repository"].text = "fixture/project"
	panel.forms["github"]["key"].text = "fixture-integration-key"
	panel.forms["github"]["enabled"].button_pressed = true
	var connected = panel._save_connections()
	var connection_file = FileAccess.get_file_as_string(panel.project_directory.path_join("integrations.json"))
	_check(connected and "fixture/project" in connection_file and not "fixture-integration-key" in connection_file and panel.forms["github"]["key"].text.is_empty(), "Integration configuration is project-scoped and credentials stay out of its JSON")
	panel.forms["github"]["enabled"].button_pressed = false
	panel._save_connections()
	var definitions = panel.active_definitions
	panel.active_definitions = panel.Workspace.definitions()
	panel.planner.reset("skills-fixture")
	var needs_plan = await panel._execute_call("skill_save", {"id": "unplanned-auto", "description": "Must plan", "instructions": "Do not write yet"})
	_check(needs_plan.get("code") == "plan_required" and not FileAccess.file_exists("res://.godot_ai/skills/unplanned-auto/SKILL.md"), "Auto enforces a plan before project changes even with YOLO")
	panel.mode_picker.select(1)
	var saved = await panel._execute_call("skill_save", {"id": "scene-check", "description": "Verifică o scenă", "instructions": "Inspectează nodurile, rulează verificările și raportează rezultatul."})
	_check(saved.get("ok", false) and FileAccess.file_exists("res://.godot_ai/skills/scene-check/SKILL.md") and panel.lists["skills"].item_count == 1, "Agent skill creation writes a portable SKILL.md and updates the manager")
	var read = panel.workspace.read("scene-check")
	_check(read.get("ok", false) and "scene-check" in panel.workspace.context(), "Enabled skills are discoverable and readable as project context")
	var stale = panel.workspace.save({"id": "scene-check", "description": "Changed", "instructions": "Should not overwrite", "expected_sha256": "stale"})
	_check(stale.get("code") == "skill_conflict", "A stale skill revision cannot overwrite newer instructions")
	panel.workspace.set_enabled("scene-check", false)
	_check(panel.workspace.read("scene-check").get("code") == "skill_disabled" and not "scene-check" in panel.workspace.context(), "Disabled skills are excluded from automatic context and agent reads")
	panel.workspace.set_enabled("scene-check", true)
	panel._edit_skill(0)
	_check(panel.forms["skill"]["instructions"].text.begins_with("Inspectează"), "Skill manager edits instructions without duplicating front matter")
	panel.mode_picker.select(2)
	var denied = await panel._execute_call("skill_save", {"id": "forbidden-plan", "description": "Denied", "instructions": "Must not write"})
	_check(not denied.get("ok", true) and not FileAccess.file_exists("res://.godot_ai/skills/forbidden-plan/SKILL.md"), "Plan cannot create skills through the editor dispatcher")
	panel.mode_picker.select(1)
	var deleted = panel.workspace.remove("scene-check", read["result"]["sha256"])
	var recovery = panel.tools.execute("godot_restore_file", {"index": deleted.get("result", {}).get("recovery", {}).get("recovery_index", -1)}, 2, true)
	_check(deleted.get("ok", false) and recovery.get("ok", false) and panel.workspace.read("scene-check").get("ok", false), "Skill deletion retains a working native recovery copy")
	panel._refresh_skills()
	panel.active_definitions = definitions
	panel.memory_editor.text = "# Memorie proiect\n\nPreferă scene mici și nume clare.\n"
	var memory = panel._save_memories()
	_check(memory.get("ok", false) and "Preferă scene mici" in FileAccess.get_file_as_string("res://AGENT.md") and "Preferă scene mici" in panel._reference_context(), "AGENT.MD edits a real project file included in subsequent context")
	panel.tools.execute("godot_write_file", {"path": "res://AGENT.md", "text": "# Schimbare manuală\n"}, 2, true)
	_check(panel._save_memories().get("code") == "memory_conflict" and FileAccess.get_file_as_string("res://AGENT.md").contains("manuală"), "Memory editor refuses to overwrite an external AGENT.md change")
	panel._load_memories()
	panel._record_event("fixture_log", {"step": 1}, {"ok": true, "result": "Verificare încheiată"})
	_check(panel.journal_console.text.contains("fixture_log") and panel.journal_console.text.contains("Verificare încheiată"), "Live journal shows chronological operation and result data in a console")
	panel.journal_filter.text = "fixture_log"
	panel.journal_filter.text_changed.emit(panel.journal_filter.text)
	_check(panel.journal_console.text.contains("fixture_log") and not panel.journal_console.text.contains("skill_save"), "Journal search filters activity without deleting stored entries")
	panel.journal_filter.clear()
	panel.journal_filter.text_changed.emit("")
	panel.full_control.button_pressed = false
	panel.planner.reset()

func _termux_blender_card_tests() -> void:
	var old_card = panel.forms["blender"]["container"].get_parent().get_parent()
	var page = old_card.get_parent()
	page.remove_child(old_card)
	old_card.queue_free()
	var backend = embedded["termux_blender"].new(panel)
	backend.configure(panel.data_directory, panel.project_directory)
	var device = {"ok": true, "installed": false, "permission": false, "supported": true}
	backend.native_override = func(action: String, _args: Dictionary) -> Dictionary: return device if action == "status" else {"ok": false}
	panel.integrations.termux = backend
	backend.changed.connect(panel._refresh_blender_card)
	panel._build_termux_blender(page)
	panel.open_settings("integrations")
	await get_tree().create_timer(.2).timeout
	var form: Dictionary = panel.forms["blender"]
	_check(form["primary"].text == "Instalează Termux" and not form["guide"].visible, "Missing Termux offers installation without a broken setup form")
	device["installed"] = true
	await backend.refresh()
	_check(form["primary"].text == "Acordă permisiunea" and form["guide"].visible, "First setup exposes Android permission and activation guidance")
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	panel.settings_tabs.get_tab_control(panel.section_tabs["integrations"]).scroll_vertical = 10000
	await get_tree().create_timer(.2).timeout
	panel.settings_tabs.get_tab_control(panel.section_tabs["integrations"]).scroll_vertical = 10000
	await get_tree().create_timer(.1).timeout
	panel.settings_window.get_texture().get_image().save_png(output.path_join("blender-setup.png"))
	device["permission"] = true
	backend.state = device.duplicate()
	backend.connected = true
	panel._refresh_blender_card()
	_check(form["primary"].text == "Instalează Blender", "Connected Termux without Blender offers installation")
	backend.state["error_code"] = "incomplete_image"
	panel._refresh_blender_card()
	_check(form["primary"].text == "Repară instalarea", "A partial owned image exposes explicit repair")
	backend.state.erase("error_code")
	backend.working = true
	backend.state["stage"] = "Instalare Blender"
	backend.log_text = "Pregătire Debian 13\nDescărcare pachete…\n"
	panel._refresh_blender_card()
	_check(form["primary"].disabled and form["cancel"].visible and not form["guide"].visible, "Install in progress prevents duplicate starts and exposes Stop")
	backend.working = false
	backend.pending = {"id": "fixture-interrupted", "kind": "run"}
	panel._refresh_blender_card()
	_check(form["primary"].text == "Recuperează", "Interrupted jobs expose explicit recovery")
	backend.pending = {}
	backend.runtime = {"kind": "proot", "container": "debian", "executable": "/usr/bin/blender", "version": "Blender 4.3.2", "capabilities": {"formats": ["glb", "fbx"], "render_cpu": true}}
	backend.verified = {"fingerprint": backend.fingerprint(backend.runtime), "protocol": 1}
	panel._refresh_blender_card()
	_check(form["status"].text.begins_with("Disponibil") and not form["guide"].visible and not form["cancel"].visible, "Only a verified runtime is shown as available")
	form["enabled"].button_pressed = true
	_check(panel.integration_settings.get("blender_enabled", false), "Agent activation is saved independently of GitHub settings")
	_check(not panel.Integrations.definitions(false, true, false).any(func(item: Dictionary) -> bool: return item.name == "blender_run" and "inputs" in item.parameters.properties), "An unready Android backend is not advertised")
	_check(panel.Integrations.definitions(false, true, true).any(func(item: Dictionary) -> bool: return item.name == "blender_run" and "inputs" in item.parameters.properties), "A ready backend exposes the portable Blender input/output contract")
	await get_tree().create_timer(.2).timeout
	panel.settings_window.get_texture().get_image().save_png(output.path_join("blender-ready.png"))
	form["logs"].show()
	await get_tree().create_timer(.2).timeout
	panel.settings_window.get_texture().get_image().save_png(output.path_join("blender-logs.png"))
	for node in [form["primary"], form["status"], form["logs"]]:
		_check(node.size.x <= panel.settings_window.size.x, "Blender card content stays inside the settings window")
	panel.settings_window.hide()
	panel.integrations.termux = null

func _configuration_screenshots(output: String) -> void:
	panel.chat.set_context(8192, 32768, 430)
	await get_tree().create_timer(0.15).timeout
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("context-filling.png"))
	for section in ["general", "providers", "generation", "integrations", "journal", "agent"]:
		if section == "generation":
			panel._clear_form("generation")
			panel.forms["generation"]["destination"].text = "res://ai_assets"
			panel.forms["generation"]["kind"].select(0)
			panel.forms["generation"]["asset_kind"].select(1)
			panel._generation_fields(0, panel.forms["generation"]["workflow_fields"])
		panel.open_settings(section)
		await get_tree().create_timer(0.2).timeout
		var page: ScrollContainer = panel.settings_tabs.get_tab_control(panel.section_tabs[section])
		page.scroll_vertical = 0
		await get_tree().process_frame
		panel.settings_window.get_texture().get_image().save_png(output.path_join("settings-" + section + ".png"))
		if section == "providers":
			var service: OptionButton = panel.forms["provider"]["issuer"]
			service.show_popup()
			await get_tree().create_timer(0.15).timeout
			service.get_popup().get_texture().get_image().save_png(output.path_join("provider-groups.png"))
			service.get_popup().hide()
	panel.open_settings("skills")
	await get_tree().create_timer(0.2).timeout
	panel.settings_window.get_texture().get_image().save_png(output.path_join("settings-skills.png"))
	panel.open_settings("automations")
	await get_tree().create_timer(0.2).timeout
	panel.settings_window.get_texture().get_image().save_png(output.path_join("settings-tasks.png"))
	panel.settings_window.hide()
	var base = EditorInterface.get_base_control()
	var groups = {}
	var center_columns = []
	for child in base.find_child("DockHSplitMain", true, false).get_children():
		if child is Control and not str(child.name).begins_with("DockVSplit"): center_columns.append({"node": child, "maximum": child.custom_maximum_size})
	for name in ["DockVSplitLeftL", "DockVSplitLeftR", "DockVSplitRightL", "DockVSplitRightR"]:
		var group = base.find_child(name, true, false)
		if group != null: groups[name] = group.visible
	for index in [1, 2, 0]:
		panel._set_placement(index)
		await get_tree().create_timer(0.3).timeout
		while panel.dock_layout_busy: await get_tree().process_frame
		await get_tree().process_frame
		var docked = panel.get_parent() is EditorDock
		_check(panel.chat.get_global_rect().end.x <= panel.get_viewport().get_visible_rect().end.x + 1 and panel.chat.send_button.get_global_rect().end.x <= panel.get_viewport().get_visible_rect().end.x + 1, "Dock and Send stay inside the usable editor width: " + str(index))
		_check(docked == (index != 0) and panel.is_visible_in_tree(), "Chat placement is active and visible: " + str(index))
		if index != 0: _assert_workspace_bounds(index, output, "normal")
		RenderingServer.force_draw(false)
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join(["dock-center.png", "dock-left.png", "dock-right.png"][index]))
		if index != 0:
			var slot = panel.get_parent().get_parent() as TabContainer
			var expected = panel._dock_content_rect(slot)
			_check(panel.get_parent().get_rect().is_equal_approx(expected) and panel.size.y >= expected.size.y - 1, "Dock fills its actual tab content height and width: " + str(index))
			await _narrow_dock_controls(slot, index, output)
			panel.chat.expand_button.pressed.emit()
			await get_tree().create_timer(0.2).timeout
			_check(not panel.get_parent() is EditorDock and EditorInterface.is_distraction_free_mode_enabled() and panel.is_visible_in_tree(), "Top expand opens docked chat in the central workspace")
			panel.chat.expand_button.pressed.emit()
			await get_tree().create_timer(0.2).timeout
			_check(panel.get_parent() is EditorDock and not EditorInterface.is_distraction_free_mode_enabled() and panel.config["preferences"]["dock"] == index, "Top collapse restores the original dock and preserves its saved preference")

	await get_tree().process_frame
	for name in groups:
		_check(base.find_child(name, true, false).visible == groups[name], "Returning to central chat restores secondary dock visibility: " + name)
	for column in center_columns: _check(column["node"].custom_maximum_size == column["maximum"], "Returning to central chat restores the workspace size constraint")

func _assert_workspace_bounds(index: int, output: String, variant: String) -> void:
	var rect = panel.chat.get_global_rect()
	_check(panel.get_viewport().get_visible_rect().grow(1).encloses(rect), "The complete dock stays inside the viewport: " + str(index) + " / " + variant)
	var viewport_3d = EditorInterface.get_editor_viewport_3d(0).get_parent() as Control
	if viewport_3d.is_visible_in_tree():
		_check(not viewport_3d.get_global_rect().intersection(rect.grow(-1)).has_area(), "The actual 3D viewport does not cover the chat: " + str(index) + " / " + variant)
	var main = EditorInterface.get_base_control().find_child("DockHSplitMain", true, false) as Control
	var columns = []
	for child in main.get_children():
		if not child is Control or not child.is_visible_in_tree(): continue
		columns.append({"name": child.name, "rect": str(child.get_global_rect()), "minimum": str(child.get_combined_minimum_size()), "maximum": str(child.get_combined_maximum_size())})
		if not child.is_ancestor_of(panel): _check(not child.get_global_rect().intersection(rect.grow(-1)).has_area(), "Editor column does not cover the chat: " + str(child.name) + " / " + str(index) + " / " + variant)
	embedded["common"].atomic_json(output.path_join("dock-geometry-" + str(index) + "-" + variant + ".json"), {"chat": str(rect), "viewport_3d": str(viewport_3d.get_global_rect()), "columns": columns})

func _narrow_dock_controls(slot: TabContainer, placement_index: int, output: String) -> void:
	var previous = slot.custom_maximum_size
	slot.custom_maximum_size.x = 224 * EditorInterface.get_editor_scale()
	await get_tree().create_timer(0.2).timeout
	while panel.dock_layout_busy: await get_tree().process_frame
	for _frame in range(5): await get_tree().process_frame
	_assert_workspace_bounds(placement_index, output, "narrow")
	var scope = panel.chat.get_global_rect().grow(1)
	for control in [panel.chat.model_button, panel.chat.reasoning_button, panel.chat.options_button, panel.chat.context_indicator, panel.chat.voice_button, panel.chat.send_button, panel.chat.expand_button, panel.chat.navigation_buttons["settings"]]:
		var fits = scope.encloses(control.get_global_rect()) and panel.get_parent().get_global_rect().grow(1).encloses(control.get_global_rect())
		if not fits:
			print("Control bounds: chat=", scope, " host=", panel.get_parent().get_global_rect(), " control=", control.get_global_rect(), " composer=", panel.chat.compose_panel.get_global_rect(), " toolbar=", panel.chat.composer_controls.get_global_rect())
			EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("dock-clipped-" + str(placement_index) + ".png"))
		_check(fits, "Narrow dock keeps the complete control visible: " + control.tooltip_text + " / " + str(placement_index))
	_check(panel.chat.composer.placeholder_text == "Mesaj…" and panel.chat.send_button.size.y <= 34 * EditorInterface.get_editor_scale(), "Narrow dock keeps the input hint on one line and Send at compact height")
	panel.chat.navigation_buttons["history"].pressed.emit()
	for _frame in range(4): await get_tree().process_frame
	_check(panel.chat.sidebar.visible and not panel.chat.root_column.visible and panel.chat.get_global_rect().grow(1).encloses(panel.chat.sidebar.get_global_rect()), "History replaces chat inside a narrow dock without expanding outside it")
	panel.chat.show_history(false)
	panel.chat.set_context(32768, 32768)
	panel.speech.transcribing = true
	for _frame in range(4): await get_tree().process_frame
	_check(panel.chat.root_column.visible and panel.chat.stop_button.visible and panel.chat.compose_panel.get_global_rect().grow(1).encloses(panel.chat.stop_button.get_global_rect()) and panel.chat.compose_panel.get_global_rect().grow(1).encloses(panel.chat.send_button.get_global_rect()), "Narrow dock keeps Stop and Send accessible with full context and voice transcription")
	panel.chat.stop_button.pressed.emit()
	for _frame in range(3): await get_tree().process_frame
	_check(not panel.speech.transcribing, "The visible Stop button actually cancels voice transcription")
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("dock-narrow-" + str(placement_index) + ".png"))
	slot.custom_maximum_size = previous
	await get_tree().create_timer(0.15).timeout
	while panel.dock_layout_busy: await get_tree().process_frame

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
		if diff.get_line(index) == "+speed = 12": additions = diff.get_line_background_color(index).g > diff.get_line_background_color(index).r
		if diff.get_line(index) == "-speed = 5": deletions = diff.get_line_background_color(index).r > diff.get_line_background_color(index).g
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
	var copy: Button = assistant["blocks"][1]["copy"]
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
	_check(panel.provider_selector.item_count == 3 and panel.provider_selector.get_item_metadata(2) == "visual-provider" and not panel.lists["providers"].visible and not panel.provider_advanced.visible, "Saved profiles use a compact selector with advanced fields collapsed")
	_check(not panel.provider_mark.visible and panel.forms["provider"]["issuer"].get_parent() == panel.forms["provider"]["key"].get_parent().get_parent(), "Saved provider keeps the service catalog visible above the API key")
	panel._new_provider()
	_check(panel.forms["provider"]["issuer"].get_parent() == panel.forms["provider"]["key"].get_parent().get_parent(), "New provider exposes service selection before the API key")
	panel._edit_provider(0)
	var previous_profiles = panel.config["providers"].duplicate(true)
	panel.config["providers"].append({"id": "lan-fixture", "name": "LAN fixture", "issuer": "custom", "kind": "chat", "url": "http://192.168.1.20:1234/v1", "models": []})
	panel._refresh_lists()
	var local_index = panel.provider_selector.item_count - 1
	panel.provider_selector.item_selected.emit(local_index)
	_check(panel.forms["provider"]["editing"] == "lan-fixture" and panel.forms["provider"]["url"].text.contains("192.168.1.20"), "Cloud/local separators retain stable profile selection instead of offset indexes")
	panel._select_issuer("ollama")
	_check(panel._provider_issuer()["id"] == "ollama", "Separated service picker resolves the correct catalog entry by ID")
	panel.config["providers"] = previous_profiles
	panel._edit_provider(0)
	_check(panel.forms["github"]["key"].secret and not panel.forms["github"].has("client_id"), "GitHub settings offer a masked personal-token field only")
	panel.forms["github"]["key"].text = "fixture-personal-token"
	_check(panel._save_connections() and panel.vault.read("integration_github") == "fixture-personal-token" and panel.integration_settings["github_enabled"], "Saving a personal token enables GitHub and stores the secret in the vault")
	panel.settings_actions["github_disconnect"].pressed.emit()
	_check(panel.vault.read("integration_github").is_empty() and not panel.integration_settings["github_enabled"], "Disconnect removes the personal token and disables GitHub")
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

func _file_chat_tests() -> void:
	var scope = str(panel.conversations.index["active"])
	var image = Image.create(80, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var path = panel.file_registry.directory.path_join("qa-image.png")
	panel.file_registry.permit(path)
	image.save_png(path)
	var registered = panel.file_registry.register_file(path, scope)
	_check(registered.get("ok", false), "File registration succeeds in the real editor")
	if not registered.get("ok", false): return
	var id = str(registered["result"]["id"])
	panel.chat.append_message("assistant", "Captura găsită", {"id": "qa-file", "files": [id]})
	var card = panel.chat.thread.find_child("File_" + id, true, false)
	_check(card != null and card.mouse_filter == Control.MOUSE_FILTER_PASS, "File cards preserve vertical chat scrolling until a horizontal gesture is accepted")
	_check(card != null and card.find_children("*", "TextureRect", true, false).size() == 1, "Assistant file cards show actual image thumbnails")
	panel.chat.append_message("assistant", "Aceeași referință", {"id": "qa-file-second", "files": [id]})
	panel._chat_action("file_pin", {"id": id})
	var pins = panel.chat.thread.find_children("*", "Button", true, false).filter(func(button: Button) -> bool: return button.get_meta("file_pin_id", "") == id)
	_check(pins.size() == 2 and pins.all(func(button: Button) -> bool: return button.button_pressed), "Pinning one card synchronizes every visible copy of that file")
	panel._chat_action("file_pin", {"id": id})
	_check(pins.all(func(button: Button) -> bool: return not button.button_pressed) and not panel.file_registry.describe(id, scope).get("pinned", true), "Unpinning clears card indicators and conversation context together")
	panel.composer.text = "Verifică aici"
	panel._chat_action("file_mention", {"id": id})
	var chips = panel.chat.attachment_chips.get_child_count()
	panel._composer_hints()
	_check(panel.pending_files == [id] and panel.composer.text == "Verifică aici" and panel.chat.attachment_chips.get_child_count() == chips, "Mentioning a file preserves the draft and repeated hints do not duplicate chips")
	var touch = InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(10, 10)
	card.gui_input.emit(touch)
	panel.pending_files.clear()
	var drag = InputEventScreenDrag.new()
	drag.position = Vector2(160, 14)
	drag.relative = Vector2(150, 4)
	card.gui_input.emit(drag)
	_check(panel.pending_files == [id], "Swiping a discovered card right references the exact file")
	panel._open_file(id)
	await get_tree().process_frame
	_check(panel.media_view.visible and panel.media_view.canvases.size() == 1 and panel.media_view.canvases[0].image.get_width() == 80, "Opening a card displays its real captured image in the viewer")
	panel.media_view.canvases[0].selection = Rect2(2, 2, 10, 6)
	var crop = panel.media_view.canvases[0].exported(true)
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty():
		panel.media_view.get_texture().get_image().save_png(output.path_join("viewer-image.png"))
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("file-mentions.png"))
	_check(crop.get_width() == 10 and crop.get_height() == 6 and crop.get_pixel(0, 0) == Color.RED, "Crop exports the selected original pixels without modifying the source")
	panel.media_view.hide()
	panel._open_file(id, id)
	_check(panel.media_view.canvases.size() == 2, "Comparison opens both exact image revisions")
	panel.media_view.canvases[0].pose_changed.emit({"zoom": 2.0, "offset": Vector2(0.1, 0.2)})
	_check(panel.media_view.canvases[1].zoom == 2.0, "Image comparison shares zoom and normalized pan")
	panel.media_view.hide()
	_check(panel.composer.text == "Verifică aici" and panel.pending_files == [id], "Closing the viewer preserves conversation draft and references")
	panel.busy = true
	panel._chat_action("file_send", {"id": id})
	_check(panel.queued.size() == 1 and panel.queued[0]["selection"]["files"] == [id], "Direct reference sending retains stable file IDs in queued messages")
	panel.busy = false
	panel.queued.clear()
	panel.pending_files.clear()
	var cutout = Image.create(80, 80, false, Image.FORMAT_RGBA8)
	cutout.fill(Color.TRANSPARENT)
	cutout.fill_rect(Rect2i(20, 20, 40, 40), Color.CORNFLOWER_BLUE)
	var cutout_path = panel.file_registry.directory.path_join("qa-cutout.png")
	panel.file_registry.permit(cutout_path)
	cutout.save_png(cutout_path)
	var cutout_file = panel.file_registry.register_file(cutout_path, scope)
	panel._open_file(str(cutout_file["result"]["id"]))
	await get_tree().create_timer(0.2).timeout
	_check(panel.media_view.canvases[0].checker != null and panel.media_view.canvases[0].exported(false).get_pixel(0, 0).a == 0, "Transparent images show a viewer checkerboard while original and exported pixels keep their real alpha")
	if not output.is_empty(): panel.media_view.get_texture().get_image().save_png(output.path_join("viewer-transparent.png"))
	panel.media_view.hide()
	panel.composer.clear()
	panel._composer_hints()
	panel.chat.clear_messages()
	panel.media_view.queue_free()
	panel.media_view = null
	await get_tree().process_frame
	while EditorInterface.get_resource_filesystem().is_scanning(): await get_tree().process_frame

func _export_button_tests(path: String) -> void:
	var previous_profiles = panel.config["generation"].duplicate(true)
	var previous_jobs = panel.assets.jobs.duplicate(true)
	panel.config["generation"] = [{"id": "export-profile", "kind": "meshy", "asset_kind": "mesh", "name": "Meshy fixture"}]
	panel.assets.jobs = [{"id": "export-cube", "profile_id": "export-profile", "kind": "mesh", "provider": "meshy", "status": "completed", "file": path, "external_id": "fixture-remote"}]
	panel._refresh_lists()
	_check(panel.lists["jobs"].get_item_text(0).begins_with("Model 3D · Finalizat"), "Generation result list uses a readable type and status")
	panel.lists["jobs"].select(0)
	panel.lists["jobs"].item_selected.emit(0)
	var picker: OptionButton = panel.forms["generation"]["export_format"]
	_check(not panel.settings_actions["job_export"].disabled and picker.item_count == 9, "Completed Meshy model enables nine actual export formats")
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == "stl": picker.select(index); picker.item_selected.emit(index)
	panel.open_settings("generation")
	await get_tree().process_frame
	panel.settings_actions["job_export"].pressed.emit()
	while panel.busy: await get_tree().process_frame
	await get_tree().process_frame
	var destination = str(panel.assets.jobs[0].get("exports", {}).get("stl", {}).get("project_path", ""))
	_check(destination.begins_with("res://ai_assets/") and destination.ends_with("_stl.stl") and panel.settings_status.text.contains("Export salvat"), "Export button saves the selected format in the named object folder")
	var file = FileAccess.open(destination, FileAccess.READ)
	if file != null: file.seek(80)
	_check(file != null and file.get_length() == 684 and file.get_32() == 12, "Object folder receives twelve actual cube triangles in binary STL")
	file = null
	var original = FileAccess.get_file_as_bytes(destination)
	panel._perform_export("export-cube", "stl")
	while panel.busy: await get_tree().process_frame
	_check(FileAccess.get_file_as_bytes(destination) == original and str(panel.assets.jobs[0]["exports"]["stl"].get("project_path", "")) == destination, "Repeated export reuses the existing object file without overwriting it")
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == "fbx": picker.select(index); picker.item_selected.emit(index)
	panel.settings_actions["job_export"].pressed.emit()
	var confirmations = panel.find_children("*", "ConfirmationDialog", true, false).filter(func(item: ConfirmationDialog) -> bool: return item.title == "Conversie FBX")
	_check(confirmations.size() == 1 and panel.assets.jobs[0].get("exports", {}).has("stl") and not panel.assets.jobs[0].get("exports", {}).has("fbx"), "FBX requires explicit conversion confirmation before any paid submission")
	if not confirmations.is_empty(): confirmations[0].canceled.emit()
	await get_tree().process_frame
	panel.open_settings("generation")
	var group: Control = panel.forms["generation"]["export_group"]
	var scroll = group.get_parent()
	while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
	if scroll != null: scroll.ensure_control_visible(group)
	await get_tree().create_timer(0.2).timeout
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty(): panel.settings_window.get_texture().get_image().save_png(output.path_join("export-formats.png"))
	panel.generation_preview.get_parent().show()
	panel.settings_actions["job_preview"].pressed.emit()
	await get_tree().create_timer(0.2).timeout
	var previews = panel.generation_preview.get_children()
	_check(previews.size() == 1 and previews[0].has_method("pose") and previews[0].information.get("triangles") == 12, "Generation settings use the shared interactive model viewer instead of a static 3D viewport")
	if previews.size() == 1:
		var preview = previews[0]
		if scroll != null: scroll.ensure_control_visible(preview)
		await get_tree().create_timer(0.2).timeout
		var old = Vector2(preview.yaw, preview.pitch)
		var point = preview.get_global_rect().get_center()
		var touch = InputEventScreenTouch.new()
		touch.position = point
		touch.pressed = true
		panel.settings_window.push_input(touch, true)
		var drag = InputEventScreenDrag.new()
		drag.position = point + Vector2(24, -18)
		drag.relative = Vector2(24, -18)
		panel.settings_window.push_input(drag, true)
		touch.pressed = false
		panel.settings_window.push_input(touch, true)
		_check(preview.yaw != old.x and preview.pitch != old.y, "A generated mesh rotates horizontally and vertically through the actual settings window")
		await get_tree().create_timer(0.2).timeout
		RenderingServer.force_draw(false)
		if not output.is_empty(): panel.settings_window.get_texture().get_image().save_png(output.path_join("generation-preview-3d.png"))
	panel.settings_window.hide()
	for preview in panel.generation_preview.get_children():
		panel.generation_preview.remove_child(preview)
		preview.queue_free()
	panel.config["generation"] = previous_profiles
	panel.assets.jobs = previous_jobs
	panel._refresh_lists()
	panel.chat.show_status("", false)
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame

func _model_and_control_tests() -> void:
	var scene = Node3D.new()
	var mesh = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	scene.add_child(mesh)
	mesh.owner = scene
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	var path = panel.file_registry.directory.path_join("qa-cube.glb")
	panel.file_registry.permit(path)
	var exported = document.append_from_scene(scene, state) == OK and document.write_to_filesystem(state, path) == OK
	scene.free()
	_check(exported, "Build an actual GLB fixture for the shared native renderer")
	if exported: await _export_button_tests(path)
	var registered = panel.file_registry.register_file(path, str(panel.conversations.index["active"]))
	_check(registered.get("ok", false), "Register a GLB snapshot for the current conversation")
	if registered.get("ok", false):
		var id = str(registered["result"]["id"])
		panel._open_file(id)
		await get_tree().process_frame
		_check(panel.media_view.model_views.size() == 1, "Opening a 3D card launches the shared interactive GLB viewer")
		if not panel.media_view.model_views.is_empty():
			var model = panel.media_view.model_views[0]
			_check(model.information.get("triangles", 0) == 12 and model.information.get("meshes", 0) == 1, "3D metadata counts actual rendered cube geometry")
			var pixels = await model.capture()
			_check(pixels != null and pixels.get_width() >= 128 and pixels.get_pixel(pixels.get_width() / 2, pixels.get_height() / 2).is_equal_approx(pixels.get_pixel(0, 0)) == false, "Interactive 3D preview renders actual geometry rather than a flat placeholder")
			var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
			if not output.is_empty(): panel.media_view.get_texture().get_image().save_png(output.path_join("viewer-3d.png"))
			var original_yaw = model.yaw
			var original_pitch = model.pitch
			var point = model.get_global_rect().get_center()
			var touch = InputEventScreenTouch.new()
			touch.pressed = true
			touch.position = point
			panel.media_view.push_input(touch, true)
			var drag = InputEventScreenDrag.new()
			drag.position = point + Vector2(60, 35)
			drag.relative = Vector2(60, 35)
			panel.media_view.push_input(drag, true)
			touch.pressed = false
			touch.position = drag.position
			panel.media_view.push_input(touch, true)
			_check(model.yaw != original_yaw and model.pitch != original_pitch, "Touch events routed through the real viewer window rotate the model on both axes")
			var turned = model.camera.transform
			touch.pressed = true
			touch.position = point
			panel.media_view.push_input(touch, true)
			drag.position = point - Vector2(60, 35)
			drag.relative = Vector2(-60, -35)
			panel.media_view.push_input(drag, true)
			touch.pressed = false
			panel.media_view.push_input(touch, true)
			_check(is_equal_approx(model.yaw, original_yaw) and is_equal_approx(model.pitch, original_pitch) and model.camera.transform != turned, "Opposite touch movement restores both camera axes through the navigation surface")
			var mouse = InputEventMouseButton.new()
			mouse.button_index = MOUSE_BUTTON_LEFT
			mouse.position = point
			mouse.pressed = true
			panel.media_view.push_input(mouse, true)
			var motion = InputEventMouseMotion.new()
			motion.position = point + Vector2(-25, 20)
			motion.relative = Vector2(-25, 20)
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			panel.media_view.push_input(motion, true)
			mouse.position = motion.position
			mouse.pressed = false
			panel.media_view.push_input(mouse, true)
			_check(model.yaw > original_yaw and model.pitch > original_pitch and not model.dragging, "Mouse drag rotates the preview and releases its gesture state")
			var old_distance = model.distance
			touch.position = point - Vector2(40, 0)
			touch.pressed = true
			panel.media_view.push_input(touch, true)
			var second_touch = InputEventScreenTouch.new()
			second_touch.index = 1
			second_touch.position = point + Vector2(40, 0)
			second_touch.pressed = true
			panel.media_view.push_input(second_touch, true)
			drag.index = 1
			drag.position = point + Vector2(70, 0)
			drag.relative = Vector2(30, 0)
			panel.media_view.push_input(drag, true)
			_check(model.distance < old_distance and model.target != Vector3.ZERO, "Two-finger input zooms and pans the actual preview camera")
			touch.pressed = false
			second_touch.pressed = false
			panel.media_view.push_input(touch, true)
			panel.media_view.push_input(second_touch, true)
			var key = InputEventKey.new()
			key.keycode = KEY_HOME
			key.pressed = true
			panel.media_view.push_input(key, true)
			_check(model.touches.is_empty() and model.target == Vector3.ZERO and is_equal_approx(model.distance, model.radius * 3), "Releasing fingers clears navigation and Home resets camera framing")
			touch.pressed = true
			panel.media_view.push_input(touch, true)
			panel.media_view.focus_exited.emit()
			_check(model.touches.is_empty() and not model.dragging, "Losing viewer focus releases all navigation inputs")
			touch.pressed = false
			panel.media_view.push_input(touch, true)
			await get_tree().create_timer(0.2).timeout
			var rotations = []
			var direction_buttons = model.input_surface.find_children("Orbit_*", "Button", true, false)
			for direction_button in direction_buttons:
				var before = Vector2(model.yaw, model.pitch)
				touch.position = direction_button.get_global_rect().get_center()
				touch.pressed = true
				panel.media_view.push_input(touch, true)
				touch.pressed = false
				panel.media_view.push_input(touch, true)
				rotations.append(Vector2(model.yaw, model.pitch) - before)
			_check(rotations.size() == 4 and rotations[0].x > 0 and rotations[1].x < 0 and rotations[2].y < 0 and rotations[3].y > 0 and direction_buttons.all(func(control: Button) -> bool: return model.get_global_rect().grow(1).encloses(control.get_global_rect())), "Four visible navigation buttons rotate left, right, up and down through real window taps")
			await get_tree().create_timer(0.2).timeout
			if not output.is_empty(): panel.media_view.get_texture().get_image().save_png(output.path_join("viewer-3d-navigated.png"))
		panel.media_view.hide()
		await get_tree().process_frame
		_check(panel.media_view.model_views.is_empty(), "Closing the viewer releases its active 3D scenes")
		var observed = await panel._observe_file(id)
		_check(observed.get("ok", false) and observed.get("result", {}).get("metadata", {}).get("triangles", 0) == 12 and not panel.media_view.visible, "Agent 3D inspection runs offscreen without opening the user viewer")
		var thumbnail = panel.file_registry.entries[id].get("preview", "")
		_check(FileAccess.file_exists(thumbnail) and Image.load_from_file(thumbnail).get_width() == 512, "Offscreen 3D inspection caches a real 512px preview")
		if not thumbnail.is_empty():
			var pixels = Image.load_from_file(thumbnail)
			_check(pixels.get_pixel(256, 256).is_equal_approx(pixels.get_pixel(0, 0)) == false, "Background 3D capture contains the rendered model")
		panel.media_view.queue_free()
		panel.media_view = null
	# A separate real editor window supplies a target outside the assistant UI.
	var window = Window.new()
	window.title = "AI input fixture"
	window.size = Vector2i(320, 180)
	EditorInterface.get_base_control().add_child(window)
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(box)
	var clicked = {"value": false}
	var button = Button.new()
	button.text = "Editor fixture button"
	button.pressed.connect(func() -> void: clicked["value"] = true)
	box.add_child(button)
	var edit = LineEdit.new()
	box.add_child(edit)
	var secret = LineEdit.new()
	secret.secret = true
	secret.text = "fixture-secret"
	box.add_child(secret)
	window.popup_centered()
	await get_tree().process_frame
	await get_tree().process_frame
	var handle = panel.tools._encode(button)["handle"]
	var capture = await panel.editor_control.capture({"target": "control", "handle": handle}, {})
	_check(capture.get("ok", false) and not capture.get("images", []).is_empty(), "Editor capture returns actual control pixels and a fresh frame ID")
	if capture.get("ok", false):
		var args = {"frame": capture["result"]["frame"], "action": "click", "x": 0.5, "y": 0.5}
		var result = await panel.editor_control.input(args, {})
		_check(result.get("ok", false) and clicked["value"] and panel.editor_control.held.is_empty(), "Coordinate input clicks the actual editor button and releases it")
		_check((await panel.editor_control.input(args, {})).get("code") == "stale_frame", "A consumed frame cannot operate the editor twice without re-observation")
	capture = await panel.editor_control.capture({"target": "control", "handle": handle}, {})
	window.size += Vector2i(20, 0)
	await get_tree().process_frame
	_check((await panel.editor_control.input({"frame": capture["result"]["frame"], "action": "click"}, {})).get("code") == "stale_frame", "Window layout changes invalidate previously captured coordinates")
	edit.grab_focus()
	capture = await panel.editor_control.capture({"target": "control", "handle": panel.tools._encode(edit)["handle"]}, {})
	var typed = await panel.editor_control.input({"frame": capture["result"]["frame"], "action": "text", "text": "test română"}, {})
	_check(typed.get("ok", false) and edit.text == "test română", "Editor text input inserts at the focused field caret")
	secret.grab_focus()
	capture = await panel.editor_control.capture({"target": "control", "handle": panel.tools._encode(secret)["handle"]}, {})
	var bytes = Marshalls.base64_to_raw(capture.get("images", [{}])[0].get("data", ""))
	var masked = Image.new()
	masked.load_png_from_buffer(bytes)
	_check(masked.get_pixel(masked.get_width() / 2, masked.get_height() / 2).is_equal_approx(Color("141a29")), "Secret fields are masked in editor captures")
	_check(not (await panel.editor_control.input({"frame": capture["result"]["frame"], "action": "text", "text": "forbidden"}, {})).get("ok", false) and secret.text == "fixture-secret", "Agent text input cannot modify a secret field")
	capture = await panel.editor_control.capture({"target": "control", "handle": handle}, {})
	var touch = InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = button.get_global_rect().get_center()
	panel.editor_control._hold(window, touch)
	panel.editor_control.user_input(InputEventKey.new())
	_check(panel.editor_control.held.is_empty() and panel.editor_control.frames.is_empty(), "Manual takeover releases held inputs and invalidates coordinates")
	panel.editor_control._hold(window, touch)
	panel.editor_control.release()
	_check(panel.editor_control.held.is_empty(), "Stop releases all synthetic touch/key states")
	window.hide()
	window.queue_free()
	panel.editor_control.release()
	await get_tree().process_frame
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame

func _store_install_tests() -> void:
	var archive_path = panel.store.directory.path_join("qa-addon.zip")
	var pack = ZIPPacker.new()
	pack.open(archive_path)
	var contents = {"fixture-root/addons/ai_test_store/plugin.cfg": "[plugin]\nname=\"AI QA addon\"\ndescription=\"Isolated installation fixture\"\nauthor=\"QA\"\nversion=\"1.0\"\nscript=\"plugin.gd\"\n", "fixture-root/addons/ai_test_store/plugin.gd": "@tool\nextends EditorPlugin\n", "fixture-root/addons/ai_test_store/empty.txt": ""}
	for name in contents:
		pack.start_file(name)
		pack.write_file(str(contents[name]).to_utf8_buffer())
		pack.close_file()
	pack.close()
	var result = await panel.store.install_zip(archive_path, {"id": "qa-addon", "name": "QA addon"}, "1.0", {})
	_check(result.get("ok", false) and FileAccess.get_file_as_string("res://addons/ai_test_store/plugin.gd") == contents["fixture-root/addons/ai_test_store/plugin.gd"], "Store installation extracts actual approved addon files" + (" through the native Godot installer" if native else " in the upstream fixture"))
	if not result.get("ok", false): return
	var installation = str(result["result"]["installation"])
	while panel.tools.scan_pending or EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame
	_check(panel.store.enable_plugin("ai_test_store", true).get("ok", false) and EditorInterface.is_plugin_enabled("ai_test_store"), "Installed addon enables through the real EditorInterface")
	_check(not panel.store.remove(installation).get("ok", false), "Store removal requires disabling the active addon first")
	panel.store.enable_plugin("ai_test_store", false)
	await get_tree().process_frame
	await get_tree().process_frame
	while EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame
	var duplicate = await panel.store.install_zip(archive_path, {"id": "qa-addon"}, "1.0", {})
	_check(duplicate.get("code") == "install_conflict", "Store installation refuses to overwrite existing addon files")
	var source = "res://addons/ai_test_store/plugin.gd"
	var output = FileAccess.open(source, FileAccess.WRITE)
	output.store_string("# manual change\n" + contents["fixture-root/addons/ai_test_store/plugin.gd"])
	output.close()
	_check(panel.store.remove(installation).get("code") == "install_conflict" and FileAccess.file_exists(source), "Uninstallation preserves manually changed addon files")
	output = FileAccess.open(source, FileAccess.WRITE)
	output.store_string(contents["fixture-root/addons/ai_test_store/plugin.gd"])
	output.close()
	await get_tree().process_frame
	var removed = panel.store.remove(installation)
	if native: _check(removed.get("ok", false) and not FileAccess.file_exists(source), "Unmodified tracked addon uninstalls after being disabled")
	else: _check(removed.get("code") == "native_bridge_unavailable" and FileAccess.file_exists(source), "Upstream editor reports the native cache-removal bridge requirement without deleting live scripts")
	while panel.tools.scan_pending or EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing(): await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

func _vision_settings_tests() -> void:
	var original = panel.config["providers"].duplicate(true)
	var selection = panel._selection()
	panel.config["providers"].append({"id": "qa-vision-settings", "name": "Vision QA", "issuer": "custom", "kind": "chat", "url": "https://vision.example/v1", "models": [{"id": "qa-image", "name": "QA images", "capabilities": {}}, {"id": "qa-text", "name": "QA text", "capabilities": {}}]})
	panel._refresh_profiles()
	panel._choose({"profile": "qa-vision-settings", "model": "qa-image"})
	panel._edit_provider(panel.config["providers"].size() - 1)
	var form: Dictionary = panel.forms["provider"]
	form["vision_model"].select(0)
	form["vision_model"].item_selected.emit(0)
	form["vision_policy"].select(1)
	form["vision_policy"].item_selected.emit(1)
	panel._save_provider()
	_check(panel._vision_enabled() and not embedded["providers"].vision_allowed(panel._current_profile(), "qa-text"), "Provider settings permit images only for the explicitly selected model")
	form["vision_model"].select(1)
	form["vision_model"].item_selected.emit(1)
	_check(form["vision_policy"].selected == 0 and form["vision_pending"].get("qa-image") == 1, "Selecting another model preserves its separate image policy")
	form["vision_policy"].select(2)
	form["vision_policy"].item_selected.emit(2)
	panel._save_provider()
	var saved: Dictionary = panel.Common.read_json(panel.data_directory.path_join("config.json"), {})
	var profile: Dictionary = saved["providers"][-1]
	_check(profile.get("vision_overrides", {}).get("qa-image") == 1 and profile["vision_overrides"].get("qa-text") == 2, "Per-model image preferences persist with the provider profile")
	panel.config["providers"] = original
	panel._save_config()
	panel._choose(selection)
	if not original.is_empty(): panel._edit_provider(0)
