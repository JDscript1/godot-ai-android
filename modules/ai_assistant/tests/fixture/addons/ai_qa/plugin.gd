@tool
extends EditorPlugin

var embedded: Dictionary = {}
var panel: Control
var failures: Array = []
var checks = 0

class FixtureVault:
	extends RefCounted
	var values = {}
	func read(name: String) -> String: return str(values.get(name, ""))
	func store(name: String, value: String) -> bool:
		values[name] = value
		return true
	func erase(name: String) -> bool: return values.erase(name)

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
	var bindings = {"common": "Common", "transport": "Transport", "providers": "Providers", "editor_tools": "Tools", "mcp": "MCP", "assets": "Assets", "accounts": "Accounts"}
	for name in ["common", "transport", "providers", "editor_tools", "mcp", "assets", "accounts", "panel"]:
		var script = GDScript.new()
		script.source_code = FileAccess.get_file_as_string(directory.path_join("runtime/" + name + ".gd"))
		var error = script.reload()
		_check(error == OK, "Compile " + name)
		if error != OK:
			get_tree().quit(1)
			return
		for dependency in embedded: script.set(bindings[dependency], embedded[dependency])
		embedded[name] = script
	panel = embedded["panel"].new()
	panel.configure(self, FixtureVault.new())
	add_control_to_bottom_panel(panel, "AI Assistant QA")
	make_bottom_panel_item_visible(panel)
	await get_tree().process_frame
	_check(panel.profile_picker != null and panel.settings_tabs.get_tab_count() == 6, "Build all settings forms")
	var scene = EditorInterface.get_edited_scene_root()
	if scene == null:
		scene = Node3D.new()
		scene.name = "AITestRoot"
		EditorInterface.add_root_node(scene)
	await get_tree().process_frame
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
		var written = toolset.execute("godot_write_file", {"path": "res://ai_test_probe.gd", "text": "@tool\nextends Node3D\nfunc fixture_method():\n\treturn 42\n"}, 2, true)
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
	panel._display("assistant", "Asistentul AI este integrat în editor. Configurează un serviciu cloud sau local din Setări pentru a începe.")
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		await get_tree().create_timer(0.5).timeout
		var image = EditorInterface.get_base_control().get_viewport().get_texture().get_image()
		_check(image != null and not image.is_empty(), "Render editor panel")
		if image != null and not image.is_empty(): image.save_png(output.path_join("editor-panel.png"))
		panel.open_settings("providers")
		await get_tree().create_timer(0.5).timeout
		image = panel.settings_window.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("settings.png"))
		panel.open_settings("generation")
		await get_tree().create_timer(0.3).timeout
		image = panel.settings_window.get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(output.path_join("generation.png"))
		panel.settings_window.hide()
	print("Godot AI editor: %s checks, %s failures" % [checks, failures.size()])
	if not output.is_empty():
		var file = FileAccess.open(output.path_join("editor-report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	get_tree().quit(0 if failures.is_empty() else 1)

func _exit_tree() -> void:
	if is_instance_valid(panel):
		remove_control_from_bottom_panel(panel)
		panel.queue_free()
