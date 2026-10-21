@tool
extends RefCounted

static var Common: GDScript
var plugin: EditorPlugin
var panel: Node
var handles: Dictionary = {}
var retained: Array = []
var file_changes: Array = []
var backup_directory = ""

func _init(editor_plugin: EditorPlugin = null, owner_panel: Node = null) -> void:
	plugin = editor_plugin
	panel = owner_panel

func definitions() -> Array:
	var string = Common.string_field()
	var integer = {"type": "integer"}
	var object = {"type": "object"}
	var array = {"type": "array", "items": {}}
	return [
		Common.tool("godot_project", "Inspect project, edited scene and selected nodes. Returns object handles for further discovery.", {}, []),
		Common.tool("godot_files", "List project files; optional name/content search. Paths are relative to res://.", {"path": string, "query": string, "content": {"type": "boolean"}}, []),
		Common.tool("godot_read_file", "Read a project text file.", {"path": string}, ["path"]),
		Common.tool("godot_write_file", "Write a project text file with a recoverable previous version.", {"path": string, "text": string}, ["path", "text"], "write"),
		Common.tool("godot_delete_file", "Remove a project file, retaining a recovery copy.", {"path": string}, ["path"], "write"),
		Common.tool("godot_restore_file", "Restore a prior file change using its journal index.", {"index": integer}, ["index"], "write"),
		Common.tool("godot_scene_tree", "Inspect the open scene's nodes, types and object handles.", {}, []),
		Common.tool("godot_create_scene", "Create an unsaved scene with the given Node class as root.", {"type": string, "name": string}, ["type", "name"], "write"),
		Common.tool("godot_create_node", "Create a node with Undo. Parent is a path relative to the scene root.", {"parent": string, "type": string, "name": string}, ["type", "name"], "write"),
		Common.tool("godot_remove_node", "Remove a scene node with Undo.", {"path": string}, ["path"], "write"),
		Common.tool("godot_save_scene", "Save the current scene to a project path.", {"path": string}, ["path"], "write"),
		Common.tool("godot_open_scene", "Open a project scene.", {"path": string}, ["path"], "write"),
		Common.tool("godot_describe", "Discover methods, properties and signals of a class or object handle. Script-defined methods are included for objects.", {"class": string, "handle": string, "filter": string}, []),
		Common.tool("godot_get", "Read an object's property by handle.", {"handle": string, "property": string}, ["handle", "property"]),
		Common.tool("godot_set", "Set an object property with Undo. Typed values use {$type:Vector3,value:[x,y,z]} and analogous Vector2, Color, Quaternion forms.", {"handle": string, "property": string, "value": {}}, ["handle", "property", "value"], "write"),
		Common.tool("godot_call", "Call a discovered Godot method. All generic calls require modification permission; resolve objects using handles, never raw instance IDs.", {"handle": string, "method": string, "arguments": array}, ["handle", "method", "arguments"], "write"),
		Common.tool("godot_load_resource", "Load and inspect a project resource, including materials, animation libraries and scripts.", {"path": string}, ["path"]),
		Common.tool("godot_create_resource", "Create an instantiable Resource class and return its handle.", {"class": string}, ["class"], "write"),
		Common.tool("godot_save_resource", "Save a Resource handle to the project, with a recovery copy of any previous file.", {"handle": string, "path": string}, ["handle", "path"], "write"),
		Common.tool("godot_run", "Run the project or a chosen scene.", {"scene": string}, [], "write"),
		Common.tool("godot_stop", "Stop the running project.", {}, [], "write"),
		Common.tool("godot_undo", "Undo the latest scene operation.", {}, [], "write"),
		Common.tool("godot_redo", "Redo the latest scene operation.", {}, [], "write"),
		Common.tool("godot_settings", "Read matching project or editor settings; secret values are excluded.", {"scope": string, "filter": string}, []),
		Common.tool("godot_set_setting", "Change and save a project or editor setting.", {"scope": string, "key": string, "value": {}}, ["scope", "key", "value"], "write"),
		Common.tool("godot_ui_tree", "Inspect visible Godot editor controls by semantic handle, including menus, debugger and output.", {"filter": string}, []),
		Common.tool("godot_ui_action", "Operate a discovered UI control. Actions: press, text, select, popup, menu, focus. value supplies text or item index.", {"handle": string, "action": string, "value": {}}, ["handle", "action"], "write"),
		Common.tool("godot_output", "Read visible editor Output and Debugger text with secret fields excluded.", {}, []),
		Common.tool("godot_animation", "Inspect animation libraries or play, stop, seek an AnimationPlayer preview.", {"path": string, "action": string, "animation": string, "position": {"type": "number"}}, ["path"], "write"),
	]

func validate(name: String, args: Dictionary) -> Dictionary:
	for definition in definitions():
		if definition["name"] != name: continue
		var specification: Dictionary = definition["parameters"]
		for required in specification["required"]:
			if not args.has(required): return Common.failure("Argument obligatoriu: " + str(required), "invalid_arguments")
		for key in args:
			if not specification["properties"].has(key): return Common.failure("Argument necunoscut: " + str(key), "invalid_arguments")
			var type = str(specification["properties"][key].get("type", ""))
			var value: Variant = args[key]
			if (type == "string" and not value is String) or (type == "array" and not value is Array) or (type == "boolean" and not value is bool) or (type in ["number", "integer"] and not (value is int or value is float)):
				return Common.failure("Tip invalid pentru " + str(key), "invalid_arguments")
		return Common.success(definition["risk"])
	return Common.failure("Instrument necunoscut: " + name, "unknown_tool")

func execute(name: String, args: Dictionary, mode: int = 0, full_control: bool = false) -> Dictionary:
	var validation = validate(name, args)
	if not validation.get("ok", false): return validation
	if validation["result"] != "read" and (mode == 0 or not full_control): return Common.failure("Operația necesită control complet activat și un mod care permite modificări.", "permission_denied")
	if not Engine.is_editor_hint(): return Common.failure("Aceste instrumente rulează numai în editor.")
	var root = EditorInterface.get_edited_scene_root()
	match name:
		"godot_project":
			var selected = []
			for node in EditorInterface.get_selection().get_selected_nodes(): selected.append(_encode(node))
			return Common.success({"name": ProjectSettings.get_setting("application/config/name", ""), "version": Engine.get_version_info(), "root": _encode(root), "editor": _encode(EditorInterface), "filesystem": _encode(EditorInterface.get_resource_filesystem()), "selection": selected, "running": EditorInterface.is_playing_scene()})
		"godot_files": return _files(args)
		"godot_read_file":
			var path = Common.project_path(str(args["path"]))
			if path.is_empty() or not FileAccess.file_exists(path): return Common.failure("Fișier de proiect inexistent sau cale nepermisă.")
			var file = FileAccess.open(path, FileAccess.READ)
			if file == null or file.get_length() > 1024 * 1024: return Common.failure("Fișierul nu poate fi citit sau depășește 1 MB.")
			return Common.success(file.get_as_text())
		"godot_write_file", "godot_delete_file": return _file_change(name, args)
		"godot_restore_file": return _restore(int(args["index"]))
		"godot_scene_tree": return Common.success(_scene_tree(root, root, 0))
		"godot_create_scene":
			var node = _instantiate_node(str(args["type"]))
			if node == null: return Common.failure("Clasa nu este un Node instanțiabil.")
			node.name = str(args["name"])
			EditorInterface.add_root_node(node)
			return Common.success(_encode(node))
		"godot_create_node":
			if root == null: return Common.failure("Deschide sau creează mai întâi o scenă.")
			var parent = root.get_node_or_null(NodePath(str(args.get("parent", "."))))
			if parent == null or not _inside_scene(parent, root): return Common.failure("Părinte inexistent în scena curentă.")
			var node = _instantiate_node(str(args["type"]))
			if node == null: return Common.failure("Clasa nu este un Node instanțiabil.")
			node.name = str(args["name"])
			var undo = plugin.get_undo_redo()
			undo.create_action("AI: create " + str(node.name))
			undo.add_do_method(parent, "add_child", node, true)
			undo.add_do_property(node, "owner", root)
			undo.add_do_reference(node)
			undo.add_undo_method(parent, "remove_child", node)
			undo.commit_action()
			return Common.success(_encode(node))
		"godot_remove_node":
			if root == null: return Common.failure("Nu există scenă activă.")
			var node = root.get_node_or_null(NodePath(str(args["path"])))
			if node == null or node == root or not _inside_scene(node, root): return Common.failure("Nod invalid.")
			var parent = node.get_parent()
			var index = node.get_index()
			var undo = plugin.get_undo_redo()
			undo.create_action("AI: remove " + str(node.name))
			undo.add_do_method(parent, "remove_child", node)
			undo.add_undo_method(parent, "add_child", node)
			undo.add_undo_method(parent, "move_child", node, index)
			undo.add_undo_property(node, "owner", root)
			undo.add_undo_reference(node)
			undo.commit_action()
			return Common.success("Nod eliminat; disponibil în Undo.")
		"godot_save_scene":
			var path = Common.project_path(str(args["path"]))
			if path.is_empty() or path.get_extension() not in ["tscn", "scn"]: return Common.failure("Destinație de scenă invalidă.")
			if root == null: return Common.failure("Nu există scenă activă.")
			if _snapshot(path) < 0: return Common.failure("Copia de recuperare nu a putut fi creată.")
			EditorInterface.save_scene_as(path)
			return Common.success({"path": path, "saved": FileAccess.file_exists(path) and root.scene_file_path == path})
		"godot_open_scene":
			var path = Common.project_path(str(args["path"]))
			if path.is_empty() or not FileAccess.file_exists(path) or path.get_extension() not in ["tscn", "scn"]: return Common.failure("Scenă inexistentă.")
			EditorInterface.open_scene_from_path(path)
			return Common.success(path)
		"godot_describe": return _describe(args)
		"godot_get", "godot_set", "godot_call", "godot_save_resource": return _object_operation(name, args)
		"godot_load_resource":
			var path = Common.project_path(str(args["path"]))
			if path.is_empty() or not ResourceLoader.exists(path): return Common.failure("Resursă inexistentă.")
			var resource = ResourceLoader.load(path)
			if resource == null: return Common.failure("Importul resursei nu a reușit.")
			retained.append(resource)
			return Common.success(_encode(resource))
		"godot_create_resource":
			var type = str(args["class"])
			if not ClassDB.can_instantiate(type) or not ClassDB.is_parent_class(type, "Resource"): return Common.failure("Clasa nu este Resource instanțiabil.")
			var resource = ClassDB.instantiate(type)
			retained.append(resource)
			return Common.success(_encode(resource))
		"godot_run":
			var scene = str(args.get("scene", ""))
			if scene.is_empty(): EditorInterface.play_main_scene()
			elif not Common.project_path(scene).is_empty() and FileAccess.file_exists(scene): EditorInterface.play_custom_scene(scene)
			else: return Common.failure("Scenă invalidă.")
			return Common.success("Cerere de rulare transmisă; verifică starea și Output.")
		"godot_stop":
			EditorInterface.stop_playing_scene()
			return Common.success("Oprire transmisă.")
		"godot_undo", "godot_redo":
			if root == null: return Common.failure("Nu există scenă activă.")
			var manager = plugin.get_undo_redo()
			var history = manager.get_history_undo_redo(manager.get_object_history_id(root))
			if name == "godot_undo" and history.has_undo(): history.undo()
			elif name == "godot_redo" and history.has_redo(): history.redo()
			else: return Common.failure("Nu există operație disponibilă.")
			return Common.success(true)
		"godot_settings", "godot_set_setting": return _settings(name, args)
		"godot_ui_tree":
			var output = []
			_ui_tree(EditorInterface.get_base_control(), str(args.get("filter", "")).to_lower(), output, 0)
			return Common.success(output)
		"godot_ui_action": return _ui_action(args)
		"godot_output":
			var output = []
			_collect_output(EditorInterface.get_base_control(), output)
			return Common.success(output)
		"godot_animation":
			if root == null: return Common.failure("Nu există scenă activă.")
			var player = root.get_node_or_null(NodePath(str(args["path"]))) as AnimationPlayer
			if player == null or not _inside_scene(player, root): return Common.failure("AnimationPlayer inexistent.")
			match str(args.get("action", "list")):
				"play": player.play(str(args.get("animation", "")))
				"stop": player.stop()
				"seek": player.seek(float(args.get("position", 0)), true)
			return Common.success({"animations": Array(player.get_animation_list()), "player": _encode(player)})
	return Common.failure("Operație neimplementată.")

func _instantiate_node(type: String) -> Node:
	if not ClassDB.can_instantiate(type) or not ClassDB.is_parent_class(type, "Node"): return null
	return ClassDB.instantiate(type) as Node

func _inside_scene(node: Node, root: Node) -> bool:
	return node == root or root.is_ancestor_of(node)

func _encode(value: Variant, depth: int = 0) -> Variant:
	if depth > 5: return "[depth limit]"
	if value is Object:
		if not is_instance_valid(value): return null
		if value is Node and panel != null and (value == panel or panel.is_ancestor_of(value)): return {"unavailable": "AI assistant UI"}
		if value == panel or value == plugin: return {"unavailable": "AI assistant internals"}
		var handle = "obj_" + str(value.get_instance_id())
		handles[handle] = weakref(value)
		return {"handle": handle, "class": value.get_class(), "name": str(value.name) if value is Node else ""}
	if value is Array:
		var output = []
		for item in value.slice(0, 1000): output.append(_encode(item, depth + 1))
		return output
	if value is Dictionary:
		var output = {}
		for key in value: output[str(key)] = _encode(value[key], depth + 1)
		return output
	return Common.json_safe(value)

func _resolve(handle: String) -> Object:
	var reference: WeakRef = handles.get(handle)
	if reference == null: return null
	var object = reference.get_ref()
	if object is Node and panel != null and (object == panel or panel.is_ancestor_of(object)): return null
	return object

func _decode(value: Variant) -> Variant:
	if value is Dictionary and value.has("$handle"): return _resolve(str(value["$handle"]))
	if value is Array:
		var result = []
		for item in value: result.append(_decode(item))
		return result
	return Common.decode_variant(value)

func _describe(args: Dictionary) -> Dictionary:
	var object = _resolve(str(args.get("handle", "")))
	var type = str(args.get("class", ""))
	var filter = str(args.get("filter", "")).to_lower()
	var methods: Array = []
	var properties: Array = []
	var signals: Array = []
	if object != null:
		methods = object.get_method_list()
		properties = object.get_property_list()
		signals = object.get_signal_list()
	elif ClassDB.class_exists(type):
		methods = ClassDB.class_get_method_list(type)
		properties = ClassDB.class_get_property_list(type)
		signals = ClassDB.class_get_signal_list(type)
	else:
		return Common.failure("Clasă sau handle inexistent.")
	var output = {"methods": [], "properties": [], "signals": []}
	for category in ["methods", "properties", "signals"]:
		var source: Array = methods if category == "methods" else (properties if category == "properties" else signals)
		for item in source:
			if filter.is_empty() or filter in str(item.get("name", "")).to_lower(): output[category].append(Common.json_safe(item))
	return Common.success(output)

func _object_operation(name: String, args: Dictionary) -> Dictionary:
	var object = _resolve(str(args["handle"]))
	if object == null: return Common.failure("Obiectul nu mai există. Inspectează din nou scena/editorul.", "stale_handle")
	if name == "godot_call":
		var method = str(args["method"])
		if method.begins_with("_") or method in ["free", "set_script", "set_meta", "set", "set_indexed", "call", "callv", "call_deferred", "call_thread_safe", "emit_signal"]:
			return Common.failure("Folosește operațiile dedicate pentru această modificare; metodele interne nu sunt expuse.")
		if not object.has_method(method): return Common.failure("Metoda nu există.")
		var arguments: Array = _decode(args["arguments"])
		for specification in object.get_method_list():
			if specification["name"] == method:
				var count = specification.get("args", []).size()
				var defaults = specification.get("default_args", []).size()
				if arguments.size() < count - defaults or (arguments.size() > count and not (int(specification.get("flags", 0)) & METHOD_FLAG_VARARG)):
					return Common.failure("Număr invalid de argumente. Consultă godot_describe.")
				break
		return Common.success(_encode(object.callv(method, arguments)))
	if name == "godot_save_resource":
		if not object is Resource: return Common.failure("Obiectul nu este Resource.")
		var path = Common.project_path(str(args["path"]))
		if path.is_empty(): return Common.failure("Destinație invalidă.")
		_snapshot(path)
		var error = ResourceSaver.save(object, path)
		return Common.success(path) if error == OK else Common.failure(error_string(error))
	var property = str(args["property"])
	var found = false
	for specification in object.get_property_list():
		if specification["name"] == property: found = true
	if not found: return Common.failure("Proprietate inexistentă.")
	if name == "godot_get": return Common.success(_encode(object.get(property)))
	if property in ["script", "owner", "scene_file_path"] or property.begins_with("_"): return Common.failure("Proprietatea necesită o operație dedicată.")
	var value: Variant = _decode(args.get("value"))
	var undo = plugin.get_undo_redo()
	undo.create_action("AI: set " + property)
	undo.add_do_property(object, property, value)
	undo.add_undo_property(object, property, object.get(property))
	undo.commit_action()
	return Common.success(_encode(object.get(property)))

func _scene_tree(node: Node, root: Node, depth: int) -> Variant:
	if node == null: return null
	if depth > 20: return "[depth limit]"
	var output: Dictionary = _encode(node)
	output["path"] = str(root.get_path_to(node))
	output["children"] = []
	for child in node.get_children(): output["children"].append(_scene_tree(child, root, depth + 1))
	return output

func _files(args: Dictionary) -> Dictionary:
	var start = Common.project_path(str(args.get("path", "res://")))
	if start.is_empty(): return Common.failure("Cale invalidă.")
	var queue = [start]
	var output = []
	var query = str(args.get("query", "")).to_lower()
	while not queue.is_empty() and output.size() < 400:
		var path: String = queue.pop_front()
		var directory = DirAccess.open(path)
		if directory == null: continue
		for folder in directory.get_directories():
			if not folder.begins_with(".") and not directory.is_link(folder): queue.append(path.path_join(folder))
		for filename in directory.get_files():
			if filename.begins_with(".") or filename.ends_with(".import") or directory.is_link(filename): continue
			var file_path = path.path_join(filename)
			var matches = query.is_empty() or query in filename.to_lower()
			if not matches and args.get("content", false) and filename.get_extension() in ["gd", "tscn", "tres", "gdshader", "json", "cfg", "godot", "txt", "md"]:
				var file = FileAccess.open(file_path, FileAccess.READ)
				if file != null and file.get_length() < 256 * 1024: matches = query in file.get_as_text().to_lower()
			if matches: output.append(file_path)
			if output.size() >= 400: break
	return Common.success(output)

func _snapshot(path: String) -> int:
	var entry = {"path": path, "existed": FileAccess.file_exists(path), "backup": "", "time": Time.get_datetime_string_from_system(true)}
	if entry["existed"]:
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > Common.MAX_ASSET_BYTES: return -1
		DirAccess.make_dir_recursive_absolute(backup_directory)
		entry["backup"] = backup_directory.path_join(Common.uid() + ".bak")
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), str(entry["backup"])) != OK: return -1
	file_changes.append(entry)
	Common.atomic_json(backup_directory.path_join("journal.json"), file_changes)
	return file_changes.size() - 1

func _file_change(operation: String, args: Dictionary) -> Dictionary:
	var path = Common.project_path(str(args["path"]))
	if path.is_empty() or path == "res://" or path == "res://project.godot": return Common.failure("Cale nepermisă; pentru setări folosește godot_set_setting.")
	var index = _snapshot(path)
	if index < 0: return Common.failure("Copia de recuperare nu a putut fi creată.")
	if operation == "godot_delete_file":
		var error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if error != OK: return Common.failure(error_string(error))
	else:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file == null: return Common.failure("Nu pot scrie fișierul.")
		file.store_string(str(args["text"]))
		file.close()
	EditorInterface.get_resource_filesystem().scan()
	return Common.success({"path": path, "recovery_index": index})

func _restore(index: int) -> Dictionary:
	if index < 0 or index >= file_changes.size(): return Common.failure("Index de recuperare invalid.")
	var change: Dictionary = file_changes[index]
	var path = Common.project_path(str(change["path"]))
	if path.is_empty(): return Common.failure("Calea nu mai este validă.")
	var error = OK
	if change["existed"]: error = DirAccess.copy_absolute(str(change["backup"]), ProjectSettings.globalize_path(path))
	elif FileAccess.file_exists(path): error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	EditorInterface.get_resource_filesystem().scan()
	return Common.success(path) if error == OK else Common.failure(error_string(error))

func _settings(name: String, args: Dictionary) -> Dictionary:
	var settings: Object = EditorInterface.get_editor_settings() if args.get("scope", "project") == "editor" else ProjectSettings
	if name == "godot_set_setting":
		var key = str(args["key"])
		if key.is_empty() or key.begins_with("ai_assistant/") or _sensitive(key): return Common.failure("Setare rezervată sau secretă.")
		settings.set_setting(key, Common.decode_variant(args["value"]))
		var error = settings.save()
		return Common.success(key) if error == OK else Common.failure(error_string(error))
	var output = {}
	var filter = str(args.get("filter", "")).to_lower()
	for entry in settings.get_property_list():
		var key = str(entry["name"])
		if key.begins_with("_") or _sensitive(key) or (not filter.is_empty() and not filter in key.to_lower()): continue
		if output.size() >= 200: break
		output[key] = _encode(settings.get(key))
	return Common.success(output)

func _sensitive(value: String) -> bool:
	var lower = value.to_lower()
	return "token" in lower or "secret" in lower or "password" in lower or "api_key" in lower or "encryption_key" in lower

func _ui_tree(node: Node, filter: String, output: Array, depth: int) -> void:
	if output.size() >= 500 or depth > 30 or node == panel: return
	if node is Control and node.is_visible_in_tree():
		var text = ""
		if node is Button or node is Label: text = str(node.text)
		elif node is LineEdit and not node.secret: text = str(node.text)
		if filter.is_empty() or filter in (str(node.name) + " " + text).to_lower():
			var item: Dictionary = _encode(node)
			item["text"] = text.left(500)
			output.append(item)
	for child in node.get_children(): _ui_tree(child, filter, output, depth + 1)

func _ui_action(args: Dictionary) -> Dictionary:
	var node = _resolve(str(args["handle"]))
	if node == null: return Common.failure("Controlul nu mai există.")
	var action = str(args["action"])
	var value: Variant = args.get("value")
	if action == "press" and node is BaseButton:
		if node.disabled: return Common.failure("Buton dezactivat.")
		if node.toggle_mode: node.set_pressed(not node.button_pressed)
		node.emit_signal("pressed")
	elif action == "text" and (node is LineEdit or node is TextEdit):
		if node is LineEdit and node.secret: return Common.failure("Câmpurile secrete se configurează manual.")
		node.text = str(value)
		if node is LineEdit: node.emit_signal("text_changed", str(value))
	elif action == "select" and node is OptionButton:
		var index = int(value)
		if index < 0 or index >= node.item_count: return Common.failure("Index invalid.")
		node.select(index)
		node.emit_signal("item_selected", index)
	elif action == "select" and node is TabContainer:
		if int(value) < 0 or int(value) >= node.get_tab_count(): return Common.failure("Index invalid.")
		node.current_tab = int(value)
	elif action == "popup" and node is Popup: node.popup()
	elif action == "menu" and node is PopupMenu:
		var index = int(value)
		if index < 0 or index >= node.item_count or node.is_item_disabled(index): return Common.failure("Element de meniu invalid.")
		node.emit_signal("id_pressed", node.get_item_id(index))
	elif action == "focus" and node is Control: node.grab_focus()
	else: return Common.failure("Acțiunea nu este disponibilă pentru acest control.")
	return Common.success(true)

func _collect_output(node: Node, output: Array) -> void:
	if node == panel or output.size() >= 12: return
	if node is RichTextLabel and node.is_visible_in_tree():
		var path = str(node.get_path()).to_lower()
		if "output" in path or "debug" in path or "log" in path: output.append(node.get_parsed_text().right(16000))
	for child in node.get_children(): _collect_output(child, output)
