@tool
extends RefCounted

static var Common: GDScript
static var ToolRegistry: GDScript
static var Diff: GDScript
static var ChangeSet: GDScript
static var PanelReader: GDScript
var panel_reader: RefCounted
var change_set: RefCounted
var plugin: Node
var panel: Node
var handles: Dictionary = {}
var retained: Array = []
var file_changes: Array = []
var backup_directory = ""
var turn_id = ""
var scene_changes = {}
var scan_pending = false
var last_run: Dictionary = {}
var run_output_before = ""
var play_owner = ""
var owned_scene = ""
var keep_playtest_open = false
var launching_playtest = false
var playback_bar: Node
var external_changes: Array = []
var symbol_cache: Dictionary = {}

func _init(editor_plugin: Node = null, owner_panel: Node = null) -> void:
	plugin = editor_plugin
	panel = owner_panel

func _panels() -> RefCounted:
	if panel_reader == null: panel_reader = PanelReader.new(self)
	return panel_reader

func _run_scene(args: Dictionary) -> Dictionary:
	var scene = str(args.get("scene", ""))
	if not scene.is_empty() and (Common.project_path(scene).is_empty() or scene.get_extension() not in ["tscn", "scn"] or not FileAccess.file_exists(scene)): return Common.failure("Scenă invalidă.")
	var target = scene if not scene.is_empty() else str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if target.begins_with("uid://") and ResourceUID.has_id(ResourceUID.text_to_id(target)): target = ResourceUID.get_id_path(ResourceUID.text_to_id(target))
	var playing = EditorInterface.is_playing_scene()
	if playing and not args.get("restart", false):
		if EditorInterface.get_playing_scene() != target: return Common.failure("Altă scenă rulează deja. Verifică starea; folosește restart=true doar dacă schimbarea scenei este necesară.", "game_already_running")
		if play_owner == turn_id and args.has("keep_open"): keep_playtest_open = args["keep_open"]
		return Common.success({"running": true, "playing_scene": target, "reused": true, "requested": false, "agent_owned": not play_owner.is_empty(), "keep_open": keep_playtest_open, "verified": false})
	var output: Array = _console_snapshot()["lines"]
	run_output_before = "\n".join(output)
	last_run = {"requested_scene": scene, "requested_at": Time.get_datetime_string_from_system(true), "baseline_available": not output.is_empty()}
	_watch_playback()
	launching_playtest = true
	if scene.is_empty(): EditorInterface.play_main_scene()
	else: EditorInterface.play_custom_scene(scene)
	launching_playtest = false
	if EditorInterface.is_playing_scene() and is_instance_valid(playback_bar) and not turn_id.is_empty():
		play_owner = turn_id
		owned_scene = EditorInterface.get_playing_scene()
		keep_playtest_open = bool(args.get("keep_open", false))
	else: _release_playback()
	return Common.success(last_run.merged({"requested": true, "reused": false, "agent_owned": not play_owner.is_empty(), "keep_open": keep_playtest_open, "verified": false, "next": "Reuse this session for state, input and the necessary frames. Inspect godot_debugger and godot_run_state before reporting success. Stop when verification ends."}))

func _watch_playback() -> void:
	if is_instance_valid(playback_bar): return
	var bars = EditorInterface.get_base_control().get_tree().root.find_children("*", "EditorRunBar", true, false)
	if bars.is_empty(): return
	playback_bar = bars[0]
	playback_bar.connect("play_pressed", _playback_started)
	playback_bar.connect("stop_pressed", _playback_stopped)

func _playback_started() -> void:
	# A user restarting even the same scene takes ownership of the new session.
	if not launching_playtest: _release_playback()

func _playback_stopped() -> void:
	play_owner = ""
	owned_scene = ""
	if not launching_playtest: _release_playback()

func _release_playback() -> void:
	if is_instance_valid(playback_bar):
		if playback_bar.is_connected("play_pressed", _playback_started): playback_bar.disconnect("play_pressed", _playback_started)
		if playback_bar.is_connected("stop_pressed", _playback_stopped): playback_bar.disconnect("stop_pressed", _playback_stopped)
	playback_bar = null
	play_owner = ""
	owned_scene = ""
	keep_playtest_open = false

func finish_playtest(turn: String, force_close: bool = false) -> Dictionary:
	if play_owner.is_empty() or play_owner != turn: return {"stopped": false, "reason": "not_owned"}
	var stop = (force_close or not keep_playtest_open) and EditorInterface.is_playing_scene() and EditorInterface.get_playing_scene() == owned_scene
	var result = {"stopped": stop, "scene": owned_scene, "reason": "temporary_test_finished" if stop else ("left_open_by_request" if keep_playtest_open else "session_changed")}
	_release_playback()
	if stop: EditorInterface.stop_playing_scene()
	return result

func _changes() -> RefCounted:
	if change_set == null:
		change_set = ChangeSet.new()
		change_set.configure(backup_directory.path_join("sets"))
	return change_set

func _change_guard(path: String, source: String) -> bool:
	return Engine.is_editor_hint() and (_dirty_script(path, source) or _dirty_scene(path))

func _dirty_scene(path: String) -> bool:
	# Text writes must never clobber an unsaved edited scene.
	if path.get_extension() not in ["tscn", "scn"]: return false
	if path not in EditorInterface.get_open_scenes(): return false
	if plugin != null and plugin.has_method("scene_is_unsaved"): return plugin.scene_is_unsaved(path)
	# The stock public API cannot inspect dirty tabs reliably. Fail closed.
	return true

func execute_changes(name: String, args: Dictionary, cancel: Dictionary = {}) -> Dictionary:
	if name not in ["godot_changes_prepare", "godot_changes_status", "godot_changes_apply", "godot_changes_rollback"]: return Common.failure("Instrument de lot necunoscut.", "unknown_tool")
	var validation = validate(name, args)
	if not validation.get("ok", false): return validation
	var worker = _changes()
	var result: Dictionary
	if name == "godot_changes_prepare": result = worker.prepare(args["changes"], turn_id, _change_guard, _syntax_check)
	elif name == "godot_changes_status": result = worker.status(str(args.get("id", "")))
	elif name == "godot_changes_rollback": result = worker.rollback(str(args["id"]), _change_guard)
	else: result = await worker.apply(str(args["id"]), cancel, panel.get_tree() if is_instance_valid(panel) and panel.is_inside_tree() else null, _change_guard)
	var id = str(result.get("result", {}).get("id", ""))
	if not id.is_empty() and _sync_change_journal(id) != OK:
		result["ok"] = false
		result["code"] = "journal_failed"
		result["error"] = "Jurnalul lotului există, dar istoricul pe turn nu a putut fi actualizat. Verifică godot_changes_status."
	if name in ["godot_changes_apply", "godot_changes_rollback"] and result.get("project_mutated", false): _request_scan()
	return result

func _sync_change_journal(id: String) -> Error:
	var data = _changes()._load(id)
	if data.is_empty(): return ERR_INVALID_DATA
	var touched = false
	for index in data["entries"].size():
		var entry = data["entries"][index]
		if not entry.get("touched", false): continue
		touched = true
		var found = -1
		for cursor in file_changes.size():
			if file_changes[cursor].get("set_id") == id and file_changes[cursor].get("set_index") == index: found = cursor; break
		var record = {"turn_id": data.get("turn", ""), "set_id": id, "set_index": index, "path": entry["path"], "existed": entry["before"] != "missing", "backup": _changes()._blob(id, index, "before"), "before_sha": entry["before"], "after_sha": entry["after"], "time": data.get("created", ""), "restored": data["state"] == "rolled_back" or _changes()._hash(entry["path"]) == entry["before"]}
		if found < 0: file_changes.append(record)
		else:
			record["restored"] = record["restored"] or file_changes[found].get("restored", false)
			file_changes[found] = record
	return Common.atomic_json(backup_directory.path_join("journal.json"), file_changes) if touched else OK

func change_preview(id: String, restoring: bool = false) -> String:
	var status = _changes().status(id)
	if not status.get("ok", false): return str(status.get("error", "Lot indisponibil."))
	var value = "Lot %s · %s\n" % [id, status["result"]["state"]]
	if restoring:
		var budget = 24000
		for item in status["result"]["files"]:
			if not item.get("touched", false): continue
			var path = str(item["path"])
			if item["position"] == "conflict": value += "\nCONFLICT · " + path + " · Editarea ulterioară va fi păstrată.\n"; continue
			if item["position"] == "before": value += "\n" + path + " · Deja restaurat.\n"; continue
			var before = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
			var restored = _changes()._blob_text(id, int(item["member_index"]), "before")
			var diff = Diff.unified(path, Diff.compare(before, restored))
			var bound = mini(4000, budget)
			value += "\n" + diff.left(bound) + ("\n[diff trunchiat]" if diff.length() > bound else "")
			budget -= mini(bound, diff.length())
		return value
	for item in status["result"]["change_preview"]:
		value += "\n" + str(item["diff"]) + ("\n[diff trunchiat]" if item.get("truncated", false) else "")
	return value

func definitions() -> Array:
	if panel != null and bool(panel.get("project_manager_mode")): return []
	var string = Common.string_field()
	var integer = {"type": "integer"}
	var object = {"type": "object"}
	var array = {"type": "array", "items": {}}
	return ChangeSet.definitions() + [
		Common.tool("godot_project", "Inspect project, edited scene and selected nodes. Returns object handles for further discovery.", {}, []),
		Common.tool("godot_files", "List project files; optional name/content search. Paths are relative to res://.", {"path": string, "query": string, "content": {"type": "boolean"}}, []),
		Common.tool("godot_read_file", "Read a project text file.", {"path": string}, ["path"]),
		Common.tool("godot_read_range", "Read a bounded range of a UTF-8 project file with one-based line numbers and its SHA-256 for a later patch.", {"path": string, "start_line": {"type": "integer", "minimum": 1}, "end_line": {"type": "integer", "minimum": 1}}, ["path"]),
		Common.tool("godot_search_code", "Search literal text in project text files. Returns paths, one-based lines and bounded excerpts; optional context lines (0-4) show the surrounding source. No shell or regex needed.", {"path": string, "query": {"type": "string", "minLength": 1}, "case_sensitive": {"type": "boolean"}, "context": {"type": "integer", "minimum": 0, "maximum": 4}, "limit": {"type": "integer", "minimum": 1, "maximum": 100}}, ["query"]),
		Common.tool("godot_symbols", "Map top-level GDScript symbols: classes, functions, signals, constants, enums, exports and variables, with paths and one-based lines. Filter by name, kind or a res:// directory. Cached by content hash and bounded.", {"path": string, "query": string, "kind": {"type": "string", "enum": ["class", "function", "signal", "constant", "enum", "export", "var"]}, "limit": {"type": "integer", "minimum": 1, "maximum": 200}}, []),
		Common.tool("godot_apply_patch", "Preview or apply sequential exact replacements in a UTF-8 file. Supply the expected_sha256 from godot_read_range. Every old_text must match exactly once. dry_run defaults to true; applying saves a recovery copy. Save any open script edits first. GDScript results carry an automatic syntax verdict.", {"path": string, "expected_sha256": {"type": "string", "pattern": "^[a-fA-F0-9]{64}$"}, "edits": {"type": "array", "minItems": 1, "maxItems": 20, "items": {"type": "object", "properties": {"old_text": {"type": "string", "minLength": 1}, "new_text": string}, "required": ["old_text", "new_text"], "additionalProperties": false}}, "dry_run": {"type": "boolean"}}, ["path", "expected_sha256", "edits"], "write"),
		Common.tool("godot_script_diagnostics", "Validate GDScript through the native Godot parser/analyzer without instantiating the script. Returns valid, errors, warnings and source hash. Optional text validates a draft instead of the saved file. Requires the rebuilt native editor bridge.", {"path": string, "text": string}, ["path"]),
		Common.tool("godot_write_file", "Write a project text file with a recoverable previous version. GDScript files are parsed afterwards and return a syntax verdict when the native bridge is available.", {"path": string, "text": string}, ["path", "text"], "write"),
		Common.tool("godot_delete_file", "Remove a project file, retaining a recovery copy.", {"path": string}, ["path"], "write"),
		Common.tool("godot_restore_file", "Restore a prior file change using its journal index.", {"index": integer}, ["index"], "write"),
		Common.tool("godot_scene_tree", "Inspect the open scene's nodes, types and object handles.", {}, []),
		Common.tool("godot_create_scene", "Create an unsaved scene with the given Node class as root.", {"type": string, "name": string}, ["type", "name"], "write"),
		Common.tool("godot_create_node", "Create a node with Undo. Parent is a path relative to the scene root.", {"parent": string, "type": string, "name": string}, ["type", "name"], "write"),
		Common.tool("godot_remove_node", "Remove a scene node with Undo.", {"path": string}, ["path"], "write"),
		Common.tool("godot_attach_script", "Attach a project GDScript to a scene node, with Undo.", {"path": string, "script": string}, ["path", "script"], "write"),
		Common.tool("godot_connect_signal", "Connect a signal between scene nodes, persistently and with Undo.", {"source": string, "signal": string, "target": string, "method": string}, ["source", "signal", "target", "method"], "write"),
		Common.tool("godot_save_scene", "Save the current scene to the exact project path, creating missing parent directories. Reuse the returned path for opening and running; an unsuccessful save returns an error.", {"path": string}, ["path"], "write"),
		Common.tool("godot_open_scene", "Open an existing project scene using its exact path from godot_files or a successful save. Does not create or relocate files.", {"path": string}, ["path"], "write"),
		Common.tool("godot_describe", "Discover a bounded page of methods, properties and signals of a class or object handle, including script methods. filter matches name substrings, with | for alternatives (shader|color). offset and limit apply to each list; follow next_offset until -1 when more results are needed. Without class/handle, pages class names.", {"class": string, "handle": string, "filter": string, "offset": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 50}}, []),
		Common.tool("godot_get", "Read an object's property by handle.", {"handle": string, "property": string}, ["handle", "property"]),
		Common.tool("godot_set", "Set an object property with Undo and verify its resulting value. Object/resource values use {\"$handle\":\"obj_...\"}, available as reference in object results. Typed values use {$type:Vector3,value:[x,y,z]} and analogous Vector2, Color, Quaternion forms. Do not pass the handle string or a plain descriptor as the value.", {"handle": string, "property": string, "value": {}}, ["handle", "property", "value"], "write"),
		Common.tool("godot_call", "Call a discovered Godot method. All generic calls require modification permission. Pass object/resource arguments as {\"$handle\":\"obj_...\"} using the reference from object results; never raw instance IDs. Reflected argument types are checked before calling. Inspect the result and editor output for effects or errors inside the method.", {"handle": string, "method": string, "arguments": array}, ["handle", "method", "arguments"], "write"),
		Common.tool("godot_load_resource", "Load and inspect a project resource, including materials, animation libraries and scripts.", {"path": string}, ["path"]),
		Common.tool("godot_create_resource", "Create an instantiable Resource class and return its handle.", {"class": string}, ["class"], "write"),
		Common.tool("godot_save_resource", "Save a Resource handle to the project, with a recovery copy of any previous file.", {"handle": string, "path": string}, ["handle", "path"], "write"),
		Common.tool("godot_run", "Run a scene for verification. Reuses the same running scene; restart=true explicitly restarts after relevant changes. Temporary agent-started tests close at turn end. Set keep_open=true only when the user requests leaving the game open. A user-started game is never adopted for automatic cleanup.", {"scene": string, "restart": {"type": "boolean"}, "keep_open": {"type": "boolean"}}, [], "write"),
		Common.tool("godot_run_state", "Inspect the last requested scene, actual playing scene, unresolved main-scene UID and Output since the request. A run request alone does not prove startup or gameplay.", {}, []),
		Common.tool("godot_stop", "Stop the running project.", {}, [], "write"),
		Common.tool("godot_undo", "Undo the latest scene operation.", {}, [], "write"),
		Common.tool("godot_redo", "Redo the latest scene operation.", {}, [], "write"),
		Common.tool("godot_settings", "Read matching project or editor settings; secret values are excluded.", {"scope": string, "filter": string}, []),
		Common.tool("godot_set_setting", "Change and save a project or editor setting.", {"scope": string, "key": string, "value": {}}, ["scope", "key", "value"], "write"),
		Common.tool("godot_ui_tree", "Inspect visible Godot editor controls by semantic handle, including menus, debugger and output.", {"filter": string}, []),
		Common.tool("godot_panels", "Inventory instantiated Godot panels and controls, including hidden docks, tabs and plugin UI. handle narrows the inventory to one panel subtree. Returns handles and reader capabilities. Page using snapshot and next_offset; snapshots expire after five minutes without access. Not-instantiated or custom-drawn data is not guaranteed readable. Excludes assistant UI and secret contents.", {"handle": string, "filter": string, "include_hidden": {"type": "boolean"}, "snapshot": string, "offset": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 100}}, []),
		Common.tool("godot_panel_read", "Read a panel/control by handle without opening or changing it. Supports collapsed Tree rows, lists, menus, tabs, text/code, numeric values and toggles. Children have their own handles. Page items via snapshot/offset; read long text or field=tooltip via text_offset, and long cells via item/column. No graph/custom-draw interpretation. Never treats missing or partial content as complete.", {"handle": string, "snapshot": string, "offset": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 100}, "field": {"type": "string", "enum": ["text", "tooltip"]}, "text_offset": {"type": "integer", "minimum": 0}, "text_limit": {"type": "integer", "minimum": 1, "maximum": 16000}, "item": {"type": "integer", "minimum": 0}, "column": {"type": "integer", "minimum": 0}}, []),
		Common.tool("godot_panel_data", "Read native cached panel data: output, profiler, visual_profiler, monitors, vram, stack, variables, threads, breakpoints, inspector, selection, audio_buses or animation. Animation accepts a player handle, animation name and optional track to page its keys. Works while hidden and reports session/collection state. Does not start profiling, refresh VRAM, pause a game or request variables. No samples means uncollected, not zero usage. offset/limit page rows; frame selects a profiler frame, -1 means latest. For monitors supply monitor=name to page its retained sample history.", {"section": {"type": "string", "enum": ["output", "profiler", "visual_profiler", "monitors", "vram", "stack", "variables", "threads", "breakpoints", "inspector", "selection", "audio_buses", "animation"]}, "handle": string, "animation": string, "monitor": string, "track": {"type": "integer", "minimum": 0}, "session": {"type": "integer", "minimum": -1}, "frame": {"type": "integer", "minimum": -1}, "offset": {"type": "integer", "minimum": 0}, "limit": {"type": "integer", "minimum": 1, "maximum": 100}}, ["section"]),
		Common.tool("godot_ui_action", "Operate a discovered UI control. Actions: press, text, select, popup, menu, focus. value supplies text or item index.", {"handle": string, "action": string, "value": {}}, ["handle", "action"], "write"),
		Common.tool("godot_output", "Read recent retained native Output plus Debugger errors, including hidden panels and stopped sessions. Without the native Output bridge, console text is a visible-only fallback. For older Output messages use godot_panel_data section=output. debugger contains structured counts, sources and stacks. Check coverage: empty visible console text alone never proves no errors.", {}, []),
		Common.tool("godot_debugger", "Read the native Debugger error list without opening UI or starting a game. Includes errors/warnings, file, line, stack, session generation and active/stopped state. Retained errors are historical observations; check session and truncation before claiming a fresh clean run.", {}, []),
		Common.tool("godot_animation", "Inspect animation libraries or play, stop, seek an AnimationPlayer preview.", {"path": string, "action": string, "animation": string, "position": {"type": "number"}}, ["path"], "write"),
	]

func validate(name: String, args: Dictionary) -> Dictionary:
	for definition in definitions():
		if definition["name"] != name: continue
		var validation = ToolRegistry.validate(definition, args)
		if not validation.get("ok", false): return validation
		return Common.success(definition["risk"])
	return Common.failure("Instrument necunoscut: " + name, "unknown_tool")

func execute(name: String, args: Dictionary, mode: int = 0, full_control: bool = false) -> Dictionary:
	if panel != null and bool(panel.get("project_manager_mode")): return Common.failure("Deschide un proiect pentru instrumentele editorului.", "project_required")
	var validation = validate(name, args)
	if not validation.get("ok", false): return validation
	if validation["result"] != "read" and (mode in [0, 3] or not full_control): return Common.failure("Operația necesită control complet activat și un mod care permite modificări.", "permission_denied")
	if not Engine.is_editor_hint(): return Common.failure("Aceste instrumente rulează numai în editor.")
	var root = EditorInterface.get_edited_scene_root()
	match name:
		"godot_project":
			var selected = []
			for node in EditorInterface.get_selection().get_selected_nodes(): selected.append(_encode(node))
			return Common.success({"name": ProjectSettings.get_setting("application/config/name", ""), "version": Engine.get_version_info(), "project_path": ProjectSettings.globalize_path("res://"), "scene_path": root.scene_file_path if root != null else "", "recent_paths": _recent_project_paths(), "root": _encode(root), "editor": _encode(EditorInterface), "filesystem": _encode(EditorInterface.get_resource_filesystem()), "selection": selected, "running": EditorInterface.is_playing_scene()})
		"godot_files": return _files(args)
		"godot_read_range": return _read_range(args)
		"godot_search_code": return _search_code(args)
		"godot_symbols": return _symbols(args)
		"godot_apply_patch": return _apply_patch(args)
		"godot_script_diagnostics": return _script_diagnostics(args)
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
			if plugin != null and plugin.has_method("create_scene_root"):
				plugin.create_scene_root(node)
			elif root == null: EditorInterface.add_root_node(node)
			if EditorInterface.get_edited_scene_root() != node:
				node.free()
				return Common.failure("Scena nouă nu a putut deveni activă. Scena existentă este păstrată; este necesar editorul nativ actualizat.", "scene_create_failed")
			return Common.success(_encode(node))
		"godot_create_node":
			if root == null: return Common.failure("Deschide sau creează mai întâi o scenă.")
			var parent = root.get_node_or_null(NodePath(str(args.get("parent", "."))))
			if parent == null or not _inside_scene(parent, root): return Common.failure("Părinte inexistent în scena curentă.")
			var node = _instantiate_node(str(args["type"]))
			if node == null: return Common.failure("Clasa nu este un Node instanțiabil.")
			node.name = str(args["name"])
			var undo = plugin.get_undo_redo()
			_begin_scene_change("Creează nod: " + str(node.name))
			undo.create_action("AI: create " + str(node.name))
			undo.add_do_method(parent, "add_child", node, true)
			undo.add_do_property(node, "owner", root)
			undo.add_do_reference(node)
			undo.add_undo_method(parent, "remove_child", node)
			undo.commit_action()
			_end_scene_change()
			return Common.success(_encode(node))
		"godot_remove_node":
			if root == null: return Common.failure("Nu există scenă activă.")
			var node = root.get_node_or_null(NodePath(str(args["path"])))
			if node == null or node == root or not _inside_scene(node, root): return Common.failure("Nod invalid.")
			var parent = node.get_parent()
			var index = node.get_index()
			var undo = plugin.get_undo_redo()
			_begin_scene_change("Șterge nod: " + str(node.name))
			undo.create_action("AI: remove " + str(node.name))
			undo.add_do_method(parent, "remove_child", node)
			undo.add_undo_method(parent, "add_child", node)
			undo.add_undo_method(parent, "move_child", node, index)
			undo.add_undo_property(node, "owner", root)
			undo.add_undo_reference(node)
			undo.commit_action()
			_end_scene_change()
			return Common.success("Nod eliminat; disponibil în Undo.")
		"godot_attach_script":
			if root == null: return Common.failure("Nu există scenă activă.")
			var node = root.get_node_or_null(NodePath(str(args["path"])))
			var path = Common.project_path(str(args["script"]))
			if node == null or not _inside_scene(node, root) or path.is_empty() or path.get_extension() != "gd" or not FileAccess.file_exists(path): return Common.failure("Nod sau script de proiect invalid.")
			var script = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as Script
			if script == null or str(script.get_instance_base_type()).is_empty() or not node.is_class(script.get_instance_base_type()): return Common.failure("Scriptul nu poate fi atașat acestui tip de nod. Verifică baza scriptului și erorile de parsare.")
			if script.reload(true) != OK: return Common.failure("Scriptul conține erori de parsare.")
			var undo = plugin.get_undo_redo()
			_begin_scene_change("Atașează script")
			undo.create_action("AI: attach script")
			undo.add_do_property(node, "script", script)
			undo.add_undo_property(node, "script", node.get_script())
			undo.commit_action()
			_end_scene_change()
			return Common.success(_encode(node))
		"godot_connect_signal":
			if root == null: return Common.failure("Nu există scenă activă.")
			var source = root.get_node_or_null(NodePath(str(args["source"])))
			var target = root.get_node_or_null(NodePath(str(args["target"])))
			var signal_name = str(args["signal"])
			var method = str(args["method"])
			if source == null or target == null or not _inside_scene(source, root) or not _inside_scene(target, root) or not source.has_signal(signal_name) or not target.has_method(method): return Common.failure("Semnal, metodă sau nod invalid.")
			var callable = Callable(target, method)
			if source.is_connected(signal_name, callable): return Common.success("Conexiunea există deja.")
			var undo = plugin.get_undo_redo()
			_begin_scene_change("Conectează semnal")
			undo.create_action("AI: connect signal")
			undo.add_do_method(source, "connect", signal_name, callable, CONNECT_PERSIST)
			undo.add_undo_method(source, "disconnect", signal_name, callable)
			undo.commit_action()
			_end_scene_change()
			return Common.success(true)
		"godot_save_scene":
			var path = Common.project_path(str(args["path"]))
			if path.is_empty() or path.get_extension() not in ["tscn", "scn"] or DirAccess.dir_exists_absolute(path): return Common.failure("Destinație de scenă invalidă.", "invalid_path")
			if root == null: return Common.failure("Nu există scenă activă.")
			var directory_error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			if directory_error != OK or not DirAccess.dir_exists_absolute(path.get_base_dir()):
				if directory_error == OK: directory_error = ERR_CANT_CREATE
				var failed = Common.failure("Nu pot crea folderul scenei %s: %s" % [path, error_string(directory_error)], "directory_create_failed")
				failed["result"] = {"path": path, "saved": false}
				return failed
			var recovery = _snapshot(path)
			if recovery < 0: return Common.failure("Copia de recuperare nu a putut fi creată.")
			EditorInterface.save_scene_as(path)
			_finalize_snapshot(recovery)
			var saved_file = FileAccess.open(path, FileAccess.READ) if FileAccess.file_exists(path) else null
			var saved = saved_file != null and saved_file.get_length() > 0 and root.scene_file_path == path
			if saved_file != null: saved_file.close()
			var result = {"path": path, "saved": saved, "recovery_index": recovery}
			if not saved:
				var failed = Common.failure("Scena nu a fost salvată la " + path + ". Verifică destinația și Output; păstrează aceeași cale la reluare.", "scene_save_failed")
				failed["result"] = result
				return failed
			_request_scan()
			return Common.success(result)
		"godot_open_scene":
			var path = Common.project_path(str(args["path"]))
			if path.is_empty() or path.get_extension() not in ["tscn", "scn"]: return Common.failure("Cale de scenă invalidă.", "invalid_path")
			if not FileAccess.file_exists(path): return Common.failure("Scena nu există la " + path + ". Caută fișierul prin godot_files și reutilizează calea existentă.", "scene_not_found")
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
			return _run_scene(args)
		"godot_run_state":
			var console = _console_snapshot()
			var output: Array = console["lines"]
			var current_output = "\n".join(output)
			var main = str(ProjectSettings.get_setting("application/run/main_scene", ""))
			var unresolved = main.begins_with("uid://") and not ResourceUID.has_id(ResourceUID.text_to_id(main))
			var debugger = _debugger_snapshot()
			return Common.success(last_run.merged({"agent_owned": not play_owner.is_empty(), "keep_open": keep_playtest_open, "running": EditorInterface.is_playing_scene(), "playing_scene": EditorInterface.get_playing_scene(), "main_scene": main, "unresolved_main_uid": unresolved, "output_after_request": current_output.substr(run_output_before.length()) if current_output.begins_with(run_output_before) else current_output, "output_baseline_reset": not current_output.begins_with(run_output_before), "debugger": debugger.get("result", {}), "debugger_available": debugger.get("ok", false), "note": "An unresolved main UID is independent of an explicitly requested scene. Do not rewrite the main scene to hide it. Check native Debugger session generation and coverage; empty visible console text is not proof of no errors."}))
		"godot_stop":
			EditorInterface.stop_playing_scene()
			_release_playback()
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
		"godot_panels":
			var scope = EditorInterface.get_base_control().get_window() if str(args.get("handle", "")).is_empty() else _resolve(str(args["handle"]))
			if not (scope is Control or scope is Window): return Common.failure("Panoul nu mai există.", "stale_handle")
			return _panels().catalog(scope, args)
		"godot_panel_read": return _panels().read(_resolve(str(args.get("handle", ""))), args)
		"godot_panel_data": return _panel_data(args)
		"godot_ui_action": return _ui_action(args)
		"godot_output":
			var console = _console_snapshot()
			var output: Array = console["lines"]
			var snapshot = _debugger_snapshot()
			var data: Dictionary = snapshot.get("result", {}) if snapshot.get("ok", false) else {}
			for event in data.get("events", []):
				output.append(_debugger_text(event))
			return Common.success(output).merged({"debugger": data, "console": console.get("data", {}), "coverage": {"visible_console_only": not console["native"], "output_native_available": console["native"], "output_partial": console["partial"], "debugger_available": snapshot.get("ok", false), "debugger_truncated": data.get("truncated", true), "empty_console_proves_clean": false}, "debugger_error": snapshot.get("error", "")})
		"godot_debugger": return _debugger_snapshot()
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
	if not ClassDB.class_exists(type) or not ClassDB.can_instantiate(type) or not ClassDB.is_parent_class(type, "Node"): return null
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
		return {"handle": handle, "reference": {"$handle": handle}, "class": value.get_class(), "name": str(value.name) if value is Node else ""}
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
	if value is Dictionary and value.get("$type") == "Object": return _resolve(str(value.get("handle", "")))
	if value is Array:
		var result = []
		for item in value: result.append(_decode(item))
		return result
	var decoded: Variant = Common.decode_variant(value)
	if decoded is Dictionary:
		var result = {}
		for key in decoded: result[key] = _decode(decoded[key])
		return result
	return decoded

func _reference_error(value: Variant) -> String:
	if value is Dictionary:
		if value.has("$handle") or value.get("$type") == "Object":
			var handle = str(value.get("$handle", value.get("handle", "")))
			if _resolve(handle) == null: return "Referința obiectului nu mai este validă. Inspectează din nou obiectul și folosește reference: {\"$handle\":\"obj_...\"}."
		for child in value.values():
			var problem = _reference_error(child)
			if not problem.is_empty(): return problem
	elif value is Array:
		for child in value:
			var problem = _reference_error(child)
			if not problem.is_empty(): return problem
	return ""

func _type_error(value: Variant, specification: Dictionary) -> String:
	var expected = int(specification.get("type", TYPE_NIL))
	if expected == TYPE_NIL: return "" # Unspecified/Variant script argument.
	var actual = typeof(value)
	if expected == TYPE_OBJECT:
		if value == null: return ""
		if not value is Object: return "Este necesar un obiect/resursă. Folosește reference: {\"$handle\":\"obj_...\"}."
		var type = str(specification.get("class_name", ""))
		if not type.is_empty() and ClassDB.class_exists(type) and not value.is_class(type): return "Obiectul trebuie să fie de tip " + type + "."
		return ""
	if expected == actual: return ""
	if expected == TYPE_FLOAT and actual == TYPE_INT: return ""
	if expected == TYPE_INT and actual == TYPE_FLOAT and is_finite(value) and value == floor(value): return ""
	if expected in [TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH] and actual in [TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH]: return ""
	var element_types = {TYPE_PACKED_BYTE_ARRAY: TYPE_INT, TYPE_PACKED_INT32_ARRAY: TYPE_INT, TYPE_PACKED_INT64_ARRAY: TYPE_INT, TYPE_PACKED_FLOAT32_ARRAY: TYPE_FLOAT, TYPE_PACKED_FLOAT64_ARRAY: TYPE_FLOAT, TYPE_PACKED_STRING_ARRAY: TYPE_STRING, TYPE_PACKED_VECTOR2_ARRAY: TYPE_VECTOR2, TYPE_PACKED_VECTOR3_ARRAY: TYPE_VECTOR3, TYPE_PACKED_COLOR_ARRAY: TYPE_COLOR, TYPE_PACKED_VECTOR4_ARRAY: TYPE_VECTOR4}
	if actual == TYPE_ARRAY and element_types.has(expected):
		for item in value:
			var problem = _type_error(item, {"type": element_types[expected]})
			if not problem.is_empty(): return problem
		return ""
	return "Tip incompatibil: este necesar %s, primit %s. Consultă godot_describe." % [type_string(expected), type_string(actual)]

func _convert_argument(value: Variant, specification: Dictionary) -> Variant:
	var expected = int(specification.get("type", TYPE_NIL))
	if value is Array and expected in [TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY]: return type_convert(value, expected)
	return type_convert(value, expected) if expected in [TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH] and typeof(value) != expected else value

func _describe(args: Dictionary) -> Dictionary:
	var object = _resolve(str(args.get("handle", "")))
	var type = str(args.get("class", ""))
	var filter = str(args.get("filter", "")).to_lower()
	var offset = maxi(0, int(args.get("offset", 0)))
	var limit = clampi(int(args.get("limit", 16)), 1, 50)
	if object == null and type.is_empty():
		var classes = []
		for class_name_value in ClassDB.get_class_list():
			if _description_matches(str(class_name_value), filter): classes.append(str(class_name_value))
		classes.sort()
		return Common.success({"classes": classes.slice(offset, offset + limit), "total": classes.size(), "offset": offset, "next_offset": offset + limit if offset + limit < classes.size() else -1})
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
	var totals = {}
	var largest = 0
	for category in ["methods", "properties", "signals"]:
		var source: Array = methods if category == "methods" else (properties if category == "properties" else signals)
		var matches = []
		for item in source:
			if _description_matches(str(item.get("name", "")), filter): matches.append(item)
		matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
		totals[category] = matches.size()
		largest = maxi(largest, matches.size())
		for item in matches.slice(offset, offset + limit): output[category].append(Common.json_safe(item))
	output.merge({"total": totals, "offset": offset, "next_offset": offset + limit if offset + limit < largest else -1})
	return Common.success(output)

static func _description_matches(name: String, filter: String) -> bool:
	if filter.strip_edges().is_empty(): return true
	for term in filter.split("|", false):
		if not term.strip_edges().is_empty() and term.strip_edges() in name.to_lower(): return true
	return false

func _object_operation(name: String, args: Dictionary) -> Dictionary:
	var object = _resolve(str(args["handle"]))
	if object == null: return Common.failure("Obiectul nu mai există. Inspectează din nou scena/editorul.", "stale_handle")
	if name == "godot_call":
		var method = str(args["method"])
		if method.begins_with("_") or method in ["free", "set_script", "set_meta", "set", "set_indexed", "call", "callv", "call_deferred", "call_thread_safe", "emit_signal"]:
			return Common.failure("Folosește operațiile dedicate pentru această modificare; metodele interne nu sunt expuse.")
		if not object.has_method(method): return Common.failure("Metoda nu există.")
		var reference_error = _reference_error(args["arguments"])
		if not reference_error.is_empty(): return Common.failure(reference_error, "stale_handle")
		var arguments: Array = _decode(args["arguments"])
		for specification in object.get_method_list():
			if specification["name"] == method:
				var count = specification.get("args", []).size()
				var defaults = specification.get("default_args", []).size()
				if arguments.size() < count - defaults or (arguments.size() > count and not (int(specification.get("flags", 0)) & METHOD_FLAG_VARARG)):
					return Common.failure("Număr invalid de argumente. Consultă godot_describe.")
				for index in range(mini(count, arguments.size())):
					var argument_spec: Dictionary = specification["args"][index]
					var problem = _type_error(arguments[index], argument_spec)
					if not problem.is_empty(): return Common.failure("Argument %s (%s): %s" % [index + 1, argument_spec.get("name", ""), problem], "invalid_arguments")
					arguments[index] = _convert_argument(arguments[index], argument_spec)
				break
		return Common.success(_encode(object.callv(method, arguments)))
	if name == "godot_save_resource":
		if not object is Resource: return Common.failure("Obiectul nu este Resource.")
		var path = Common.project_path(str(args["path"]))
		if path.is_empty(): return Common.failure("Destinație invalidă.")
		var recovery = _snapshot(path)
		if recovery < 0: return Common.failure("Copia de recuperare nu a putut fi creată.")
		var error = ResourceSaver.save(object, path)
		_finalize_snapshot(recovery)
		return Common.success(path) if error == OK else Common.failure(error_string(error))
	var property = str(args["property"])
	var property_spec = {}
	for specification in object.get_property_list():
		if specification["name"] == property: property_spec = specification
	if property_spec.is_empty(): return Common.failure("Proprietate inexistentă.")
	if name == "godot_get": return Common.success(_encode(object.get(property)))
	if property in ["script", "owner", "scene_file_path"] or property.begins_with("_"): return Common.failure("Proprietatea necesită o operație dedicată.")
	var reference_error = _reference_error(args.get("value"))
	if not reference_error.is_empty(): return Common.failure(reference_error, "stale_handle")
	var value: Variant = _decode(args.get("value"))
	var problem = _type_error(value, property_spec)
	if not problem.is_empty(): return Common.failure(problem, "invalid_arguments")
	value = _convert_argument(value, property_spec)
	var undo = plugin.get_undo_redo()
	_begin_scene_change("Proprietate: " + property)
	undo.create_action("AI: set " + property)
	undo.add_do_property(object, property, value)
	undo.add_undo_property(object, property, object.get(property))
	undo.commit_action()
	_end_scene_change()
	var actual: Variant = object.get(property)
	if not _values_equal(actual, value): return Common.failure("Proprietatea nu are valoarea cerută după modificare. Verifică rezultatul înainte de continuare.", "property_not_applied").merged({"result": _encode(actual)})
	return Common.success(_encode(actual))

func _values_equal(actual: Variant, expected: Variant) -> bool:
	if typeof(actual) in [TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR, TYPE_QUATERNION, TYPE_BASIS, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_PLANE]:
		if actual is float and expected is float: return is_finite(actual) and is_finite(expected) and absf(actual - expected) <= 0.00001 + 0.000001 * maxf(absf(actual), absf(expected))
		return typeof(actual) == typeof(expected) and actual.is_equal_approx(expected)
	return actual == expected

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

func _read_text(path: String) -> Dictionary:
	if Common.project_path(path).is_empty(): return Common.failure("Cale de proiect nepermisă.", "invalid_path")
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 1024 * 1024: return Common.failure("Fișier inexistent sau mai mare de 1 MB.", "invalid_file")
	var bytes = file.get_buffer(file.get_length())
	if bytes.has(0): return Common.failure("Fișierul trebuie să fie text UTF-8 fără caractere NUL.", "invalid_file")
	var text = bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes: return Common.failure("Fișierul trebuie să fie text UTF-8.", "invalid_file")
	return Common.success({"text": text, "sha256": text.sha256_text()})

func _read_range(args: Dictionary) -> Dictionary:
	var path = Common.project_path(str(args["path"]))
	var read = _read_text(path)
	if not read.get("ok", false): return read
	var lines = str(read["result"]["text"]).split("\n")
	var start = int(args.get("start_line", 1))
	var end = int(args.get("end_line", start + 119))
	if end < start or start > lines.size(): return Common.failure("Interval de linii invalid.", "invalid_arguments")
	end = mini(end, mini(lines.size(), start + 199))
	var output = []
	var count = 0
	for index in range(start - 1, end):
		var text = str(lines[index]).trim_suffix("\r").left(2000)
		if count + text.length() > 20000: break
		output.append({"line": index + 1, "text": text, "truncated": lines[index].length() > 2000})
		count += text.length()
	return Common.success({"path": path, "sha256": read["result"]["sha256"], "lines": output, "total_lines": lines.size(), "next_line": start + output.size() if start + output.size() <= lines.size() else -1})

func _search_code(args: Dictionary) -> Dictionary:
	var start = Common.project_path(str(args.get("path", "res://")))
	if start.is_empty(): return Common.failure("Cale invalidă.", "invalid_path")
	var query = str(args["query"])
	var sensitive = bool(args.get("case_sensitive", false))
	if not sensitive: query = query.to_lower()
	var limit = clampi(int(args.get("limit", 40)), 1, 100)
	var context = clampi(int(args.get("context", 0)), 0, 4)
	var queue = [start]
	var output = []
	var visited = 0
	var scanned_bytes = 0
	var emitted = 0
	var covered = {}
	var budget_hit = false
	while not queue.is_empty() and visited < 2000 and scanned_bytes < 4 * 1024 * 1024 and output.size() < limit:
		var path: String = queue.pop_front()
		visited += 1
		if FileAccess.file_exists(path):
			if path.get_extension() not in ["gd", "tscn", "tres", "gdshader", "json", "cfg", "godot", "txt", "md"]: continue
			var read = _read_text(path)
			if not read.get("ok", false): continue
			var lines = str(read["result"]["text"]).split("\n")
			scanned_bytes += str(read["result"]["text"]).to_utf8_buffer().size()
			for index in range(lines.size()):
				var line = str(lines[index]).trim_suffix("\r")
				var found = (line if sensitive else line.to_lower()).find(query)
				if found < 0: continue
				var excerpt_start = maxi(0, found - 120)
				var entry = {"path": path, "line": index + 1, "column": found + 1, "text": line.substr(excerpt_start, 400), "excerpt_column": excerpt_start + 1}
				emitted += entry["text"].length()
				if context > 0:
					var before = []
					for offset in range(maxi(0, index - context), index):
						if int(covered.get(path, 0)) >= offset + 1: continue
						var nearby = str(lines[offset]).trim_suffix("\r").left(400)
						before.append({"line": offset + 1, "text": nearby})
						emitted += nearby.length()
					var after = []
					for offset in range(index + 1, mini(lines.size(), index + 1 + context)):
						var nearby = str(lines[offset]).trim_suffix("\r").left(400)
						after.append({"line": offset + 1, "text": nearby})
						emitted += nearby.length()
					if not before.is_empty(): entry["before"] = before
					if not after.is_empty(): entry["after"] = after
					covered[path] = mini(lines.size(), index + 1 + context)
				output.append(entry)
				if emitted >= 24000:
					budget_hit = true
					break
				if output.size() >= limit: break
			if budget_hit: break
			continue
		var directory = DirAccess.open(path)
		if directory == null: continue
		for folder in directory.get_directories():
			if not folder.begins_with(".") and not directory.is_link(folder): queue.append(path.path_join(folder))
		for filename in directory.get_files():
			if not filename.begins_with(".") and not directory.is_link(filename): queue.append(path.path_join(filename))
	return Common.success({"matches": output, "truncated": budget_hit or not queue.is_empty() or output.size() >= limit, "visited": visited, "scanned_bytes": scanned_bytes})

func _symbols(args: Dictionary) -> Dictionary:
	var start = Common.project_path(str(args.get("path", "res://")))
	if start.is_empty(): return Common.failure("Cale invalidă.", "invalid_path")
	var query = str(args.get("query", "")).to_lower()
	var kind = str(args.get("kind", ""))
	var limit = clampi(int(args.get("limit", 80)), 1, 200)
	var queue = [start]
	var output = []
	var files = 0
	var visited = 0
	var scanned_bytes = 0
	var truncated = false
	while not queue.is_empty() and visited < 2000 and scanned_bytes < 4 * 1024 * 1024 and output.size() < limit:
		var path: String = queue.pop_front()
		visited += 1
		if FileAccess.file_exists(path):
			if path.get_extension() != "gd": continue
			var read = _read_text(path)
			if not read.get("ok", false): continue
			var text = str(read["result"]["text"])
			var sha = str(read["result"]["sha256"])
			scanned_bytes += text.to_utf8_buffer().size()
			files += 1
			var cached: Dictionary = symbol_cache.get(path, {})
			var symbols: Array
			if str(cached.get("sha256", "")) == sha: symbols = cached.get("symbols", [])
			else:
				symbols = _scan_symbols(path, text)
				symbol_cache[path] = {"sha256": sha, "symbols": symbols}
			for symbol in symbols:
				if not kind.is_empty() and symbol["kind"] != kind: continue
				if not query.is_empty() and not query in str(symbol["name"]).to_lower(): continue
				output.append(symbol)
				if output.size() >= limit: break
			continue
		var directory = DirAccess.open(path)
		if directory == null: continue
		for folder in directory.get_directories():
			if not folder.begins_with(".") and not directory.is_link(folder): queue.append(path.path_join(folder))
		for filename in directory.get_files():
			if not filename.begins_with(".") and not directory.is_link(filename): queue.append(path.path_join(filename))
	truncated = not queue.is_empty() or output.size() >= limit
	output.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["path"] < b["path"] or (a["path"] == b["path"] and int(a["line"]) < int(b["line"])))
	if symbol_cache.size() > 600: symbol_cache.clear()
	return Common.success({"symbols": output, "files_scanned": files, "scanned_bytes": scanned_bytes, "truncated": truncated, "limit": limit})

func _scan_symbols(path: String, text: String) -> Array:
	var output = []
	var pending_export = false
	var lines = text.split("\n")
	var code_lines = _symbol_code_lines(lines)
	for index in range(lines.size()):
		var raw = str(code_lines[index]).trim_suffix("\r")
		var trimmed = raw.strip_edges()
		var signature = str(lines[index]).strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#"): continue
		if raw != raw.lstrip(" \t"): continue
		if trimmed.begins_with("@"):
			var at = trimmed.find("var ")
			if at >= 0:
				var exported = "export" in trimmed or pending_export
				_add_symbol(output, path, index + 1, "export" if exported else "var", _symbol_name(trimmed.substr(at + 4)), signature)
				pending_export = false
			else:
				pending_export = "export" in trimmed and not "group" in trimmed and not "category" in trimmed
			continue
		var added_kind = ""
		var added_name = ""
		if trimmed.begins_with("class_name "):
			added_kind = "class"
			added_name = trimmed.substr(11).split(" ")[0]
		elif trimmed.begins_with("class "):
			added_kind = "class"
			added_name = trimmed.substr(6).split(":")[0].split(" ")[0]
		elif trimmed.begins_with("static func "):
			added_kind = "function"
			added_name = trimmed.substr(12).split("(")[0].strip_edges()
		elif trimmed.begins_with("func "):
			added_kind = "function"
			added_name = trimmed.substr(5).split("(")[0].strip_edges()
		elif trimmed.begins_with("signal "):
			added_kind = "signal"
			added_name = trimmed.substr(7).split("(")[0].split(":")[0].strip_edges()
		elif trimmed.begins_with("enum "):
			added_kind = "enum"
			added_name = trimmed.substr(5).split("{")[0].split(":")[0].strip_edges()
		elif trimmed.begins_with("const "):
			added_kind = "constant"
			added_name = trimmed.substr(6).split("=")[0].split(":")[0].strip_edges()
		elif trimmed.begins_with("var "):
			added_kind = "export" if pending_export else "var"
			added_name = _symbol_name(trimmed.substr(4))
		if not added_name.is_empty(): _add_symbol(output, path, index + 1, added_kind, added_name, signature)
		pending_export = false
	return output

static func _symbol_code_lines(lines: PackedStringArray) -> PackedStringArray:
	# Mask whole spans using native string searches instead of copying per character.
	var output = PackedStringArray()
	var quote = ""
	for line in lines:
		var parts = PackedStringArray()
		var index = 0
		while index < line.length():
			if not quote.is_empty():
				var closing = line.find(quote, index)
				while closing >= 0:
					var slashes = 0
					var cursor = closing - 1
					while cursor >= 0 and line[cursor] == "\\":
						slashes += 1
						cursor -= 1
					if slashes % 2 == 0: break
					closing = line.find(quote, closing + 1)
				if closing < 0:
					parts.append(" ".repeat(line.length() - index))
					break
				var end = closing + quote.length()
				parts.append(" ".repeat(end - index))
				index = end
				quote = ""
				continue
			var next = line.length()
			for marker in ["#", "\"", "'"]:
				var at = line.find(marker, index)
				if at >= 0: next = mini(next, at)
			parts.append(line.substr(index, next - index))
			if next == line.length(): break
			if line[next] == "#":
				parts.append(" ".repeat(line.length() - next))
				break
			quote = line[next].repeat(3) if line.substr(next, 3) == line[next].repeat(3) else line[next]
			parts.append(" ".repeat(quote.length()))
			index = next + quote.length()
		output.append("".join(parts))
	return output

static func _symbol_name(value: String) -> String:
	return value.split(":")[0].split("=")[0].split("(")[0].strip_edges()

static func _add_symbol(output: Array, path: String, line: int, kind: String, name: String, signature: String) -> void:
	if name.is_empty(): return
	output.append({"name": name, "kind": kind, "path": path, "line": line, "signature": signature.left(240)})

static func prepare_patch(text: String, edits: Array) -> Dictionary:
	if edits.is_empty() or edits.size() > 20: return Common.failure("Un patch trebuie să conțină între 1 și 20 modificări.", "invalid_arguments")
	var updated = text
	var changes = []
	for edit in edits:
		if not edit is Dictionary or not edit.get("old_text") is String or not edit.get("new_text") is String: return Common.failure("Modificare de patch invalidă.", "invalid_arguments")
		var before = str(edit["old_text"])
		var after = str(edit["new_text"])
		var index = updated.find(before)
		if before.is_empty() or index < 0 or updated.find(before, index + 1) >= 0: return Common.failure("Textul vechi trebuie să apară exact o dată. Citește un context mai precis.", "patch_conflict")
		changes.append({"line": updated.left(index).count("\n") + 1, "before": before.left(800), "after": after.left(800), "preview_truncated": before.length() > 800 or after.length() > 800})
		updated = updated.left(index) + after + updated.substr(index + before.length())
		if updated.to_utf8_buffer().size() > 1024 * 1024: return Common.failure("Rezultatul patch-ului depășește 1 MB.", "invalid_arguments")
	return Common.success({"text": updated, "before_sha256": text.sha256_text(), "after_sha256": updated.sha256_text(), "changes": changes, "changed": text != updated})

func _apply_patch(args: Dictionary) -> Dictionary:
	var path = Common.project_path(str(args["path"]))
	if path == "res://project.godot": return Common.failure("Pentru setări folosește godot_set_setting.", "invalid_path")
	var read = _read_text(path)
	if not read.get("ok", false): return read
	if str(read["result"]["sha256"]) != str(args["expected_sha256"]).to_lower(): return Common.failure("Fișierul s-a schimbat. Citește-l din nou înainte de patch.", "patch_conflict")
	var source = str(read["result"]["text"])
	if _dirty_script(path, source): return Common.failure("Scriptul are modificări nesalvate în editor. Salvează-le înainte de patch.", "unsaved_changes")
	var patch = prepare_patch(source, args["edits"])
	if not patch.get("ok", false): return patch
	var info: Dictionary = patch["result"]
	var text = str(info["text"])
	info.erase("text")
	info["path"] = path
	info["dry_run"] = bool(args.get("dry_run", true))
	var syntax = _syntax_check(text, path)
	if not syntax.is_empty(): info["syntax"] = syntax
	if info["dry_run"]:
		var compared = Diff.compare(source, text)
		info["change_preview"] = [{"path": path, "state": "Propus", "exact": compared["exact"], "added": compared.get("added", 0), "removed": compared.get("removed", 0), "diff": Diff.unified(path, compared), "first_line": compared.get("first_line", 1)}]
	if info["dry_run"] or not info["changed"]: return Common.success(info)
	var recovery = _snapshot(path)
	if recovery < 0: return Common.failure("Copia de recuperare nu a putut fi salvată.", "recovery_failed")
	var temporary = path + ".ai-" + Common.uid() + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return Common.failure("Nu pot pregăti fișierul modificat.", "write_failed")
	file.store_string(text)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_sha256(temporary) != info["after_sha256"]:
		DirAccess.remove_absolute(temporary)
		return Common.failure("Scrierea patch-ului nu a putut fi verificată.", "write_failed")
	if FileAccess.get_sha256(path) != info["before_sha256"]:
		DirAccess.remove_absolute(temporary)
		return Common.failure("Fișierul s-a schimbat în timpul pregătirii patch-ului.", "patch_conflict")
	var error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return Common.failure(error_string(error), "write_failed")
	file_changes[recovery]["after_sha"] = info["after_sha256"]
	info["recovery_index"] = recovery
	var saved = Common.atomic_json(backup_directory.path_join("journal.json"), file_changes)
	_request_scan()
	if saved != OK: return {"ok": false, "code": "journal_failed", "error": "Patch aplicat, dar jurnalul nu a putut fi actualizat. Verifică fișierul și copia de recuperare.", "result": info}
	return Common.success(info)

func _dirty_script(path: String, disk: String) -> bool:
	var editor = EditorInterface.get_script_editor()
	var scripts = editor.get_open_scripts()
	var controls = editor.get_open_script_editors()
	for index in range(scripts.size()):
		if scripts[index].resource_path != path: continue
		if scripts.size() != controls.size(): return true
		var control = controls[index].get_base_editor()
		if control is TextEdit: return control.text.replace("\r\n", "\n") != disk.replace("\r\n", "\n")
	return false

func _syntax_check(text: String, path: String) -> Dictionary:
	if path.get_extension() != "gd": return {}
	if plugin == null or not plugin.has_method("script_diagnostics"): return {}
	var checked: Dictionary = plugin.script_diagnostics(text, path)
	if not checked.get("ok", false): return {}
	var info: Dictionary = checked.get("result", {})
	var errors = []
	var total = 0
	for item in info.get("diagnostics", []):
		if not item is Dictionary or item.get("severity") != "error": continue
		total += 1
		if errors.size() >= 20: continue
		errors.append({"line": int(item.get("line", 0)), "column": int(item.get("column", 0)), "message": str(item.get("message", "")).left(400)})
	return {"valid": bool(info.get("valid", false)) and errors.is_empty(), "errors": errors, "truncated": total > errors.size()}

func _script_diagnostics(args: Dictionary) -> Dictionary:
	var path = Common.project_path(str(args["path"]))
	if path.is_empty() or path.get_extension() != "gd": return Common.failure("Alege un script GDScript din proiect.", "invalid_path")
	var text = str(args.get("text", ""))
	if not args.has("text"):
		var read = _read_text(path)
		if not read.get("ok", false): return read
		text = str(read["result"]["text"])
	if text.to_utf8_buffer().size() > 1024 * 1024: return Common.failure("Scriptul depășește 1 MB.", "invalid_file")
	if plugin == null or not plugin.has_method("script_diagnostics"): return Common.failure("Diagnosticarea structurată necesită editorul nativ recompilat cu această versiune.", "native_bridge_unavailable")
	var result: Dictionary = plugin.script_diagnostics(text, path)
	if result.get("ok", false):
		result["result"]["sha256"] = text.sha256_text()
		result["result"]["source"] = "draft" if args.has("text") else "disk"
	return result

func _recent_project_paths() -> Array:
	var paths = []
	for index in range(file_changes.size() - 1, -1, -1):
		var path = Common.project_path(str(file_changes[index].get("path", "")))
		if path.is_empty() or not FileAccess.file_exists(path) or path in paths: continue
		paths.append(path)
		if paths.size() >= 12: break
	return paths

func _snapshot(path: String) -> int:
	var entry = {"turn_id": turn_id, "path": path, "existed": FileAccess.file_exists(path), "backup": "", "time": Time.get_datetime_string_from_system(true)}
	if entry["existed"]:
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > Common.MAX_ASSET_BYTES: return -1
		DirAccess.make_dir_recursive_absolute(backup_directory)
		entry["backup"] = backup_directory.path_join(Common.uid() + ".bak")
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), str(entry["backup"])) != OK: return -1
	entry["after_sha"] = FileAccess.get_sha256(str(entry["backup"])) if entry["existed"] else "missing"
	file_changes.append(entry)
	if Common.atomic_json(backup_directory.path_join("journal.json"), file_changes) != OK:
		file_changes.pop_back()
		return -1
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
	file_changes[index]["after_sha"] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	Common.atomic_json(backup_directory.path_join("journal.json"), file_changes)
	_request_scan()
	var result = {"path": path, "recovery_index": index}
	if operation == "godot_write_file":
		var syntax = _syntax_check(str(args["text"]), path)
		if not syntax.is_empty(): result["syntax"] = syntax
	return Common.success(result)

func _restore(index: int) -> Dictionary:
	if index < 0 or index >= file_changes.size(): return Common.failure("Index de recuperare invalid.")
	var change: Dictionary = file_changes[index]
	var path = Common.project_path(str(change["path"]))
	if path.is_empty(): return Common.failure("Calea nu mai este validă.")
	var current_sha = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	if change.has("after_sha") and current_sha != change["after_sha"]: return Common.failure("Fișierul a fost modificat ulterior. Compară diferențele înainte de restaurare.", "restore_conflict")
	if change.has("set_id"):
		var original = FileAccess.get_file_as_string(str(change["backup"]))
		var current = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		if change["existed"] and original.sha256_text() != change.get("before_sha", ""): return Common.failure("Copia lotului este coruptă; restaurarea a fost oprită.", "recovery_failed")
		if _change_guard(path, current) and _change_guard(path, original): return Common.failure("Există editări nesalvate în editor.", "unsaved_changes")
	var error = OK
	if change["existed"]: error = DirAccess.copy_absolute(str(change["backup"]), ProjectSettings.globalize_path(path))
	elif FileAccess.file_exists(path): error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_request_scan()
	return Common.success(path) if error == OK else Common.failure(error_string(error))

func _request_scan() -> void:
	if scan_pending: return
	scan_pending = true
	_scan_when_ready.call_deferred()

func _scan_when_ready() -> void:
	if not is_instance_valid(panel) or not panel.is_inside_tree():
		scan_pending = false
		return
	var filesystem = EditorInterface.get_resource_filesystem()
	while filesystem.is_scanning():
		if not is_instance_valid(panel) or not panel.is_inside_tree():
			scan_pending = false
			return
		await panel.get_tree().process_frame
	filesystem.scan()
	scan_pending = false

func _settings(name: String, args: Dictionary) -> Dictionary:
	if args.get("scope", "project") not in ["project", "editor"]: return Common.failure("Scope trebuie să fie project sau editor.", "invalid_arguments")
	var settings: Object = EditorInterface.get_editor_settings() if args.get("scope", "project") == "editor" else ProjectSettings
	if name == "godot_set_setting":
		var key = str(args["key"])
		if key.is_empty() or key.begins_with("ai_assistant/") or _sensitive(key): return Common.failure("Setare rezervată sau secretă.")
		if key == "editor_plugins/enabled": return Common.failure("Pentru activarea/dezactivarea pluginurilor folosește plugin_enable; simpla schimbare a listei nu încarcă pluginul.", "dedicated_tool_required")
		var value: Variant = Common.decode_variant(args["value"])
		if value is Dictionary and value.has("$type"): return Common.failure("Descriptor de tip invalid sau nesuportat.", "invalid_arguments")
		if settings.has_setting(key):
			var specification = {"type": typeof(settings.get_setting(key))}
			var problem = _type_error(value, specification)
			if not problem.is_empty(): return Common.failure(problem, "invalid_arguments")
			value = _convert_argument(value, specification)
		var previous: Variant = settings.get_setting(key) if settings.has_setting(key) else null
		settings.set_setting(key, value)
		if not _values_equal(settings.get_setting(key), value):
			settings.set_setting(key, previous)
			return Common.failure("Setarea nu are valoarea cerută.", "setting_not_applied")
		if args.get("scope", "project") == "editor": return Common.success({"key": key, "value": _encode(settings.get_setting(key)), "persistence": "editor-managed"})
		var error = settings.save()
		if error != OK: settings.set_setting(key, previous)
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
			var rect: Rect2 = node.get_global_rect()
			item["rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
			item["window"] = _encode(node.get_window())
			if node is BaseButton: item["enabled"] = not node.disabled
			elif node is LineEdit or node is TextEdit: item["editable"] = node.editable and not (node is LineEdit and node.secret)
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

func _debugger_snapshot() -> Dictionary:
	if not is_instance_valid(plugin) or not plugin.has_method("debugger_snapshot"):
		return Common.failure("Citirea nativă a Debuggerului necesită editorul recompilat. Textul consolei nu dovedește lipsa erorilor.", "debugger_unavailable")
	return plugin.debugger_snapshot()

func _panel_data(args: Dictionary) -> Dictionary:
	if str(args.get("section", "")) in ["inspector", "selection", "audio_buses", "animation"]: return _public_panel_data(args)
	if not is_instance_valid(plugin) or not plugin.has_method("panel_snapshot"):
		return Common.failure("Citirea datelor native din panouri necesită editorul recompilat. Poți inspecta separat controalele existente cu godot_panels și godot_panel_read.", "panel_data_unavailable")
	if not str(args.get("monitor", "")).is_empty():
		return plugin.panel_snapshot(str(args["section"]), int(args.get("session", -1)), int(args.get("offset", 0)), int(args.get("limit", 40)), int(args.get("frame", -1)), str(args["monitor"]))
	return plugin.panel_snapshot(str(args["section"]), int(args.get("session", -1)), int(args.get("offset", 0)), int(args.get("limit", 40)), int(args.get("frame", -1)))

func _console_snapshot() -> Dictionary:
	var lines = []
	var probe = _panel_data({"section": "output", "limit": 1})
	if probe.get("ok", false):
		var offset = maxi(0, int(probe["result"].get("total", 0)) - 40)
		var measured = _panel_data({"section": "output", "offset": offset, "limit": 40})
		if measured.get("ok", false):
			var data: Dictionary = measured["result"]
			for row in data.get("items", []):
				var text = str(row.get("text", ""))
				if int(row.get("type", 0)) == 1 and not text.begins_with("ERROR:"): text = "ERROR: " + text
				elif int(row.get("type", 0)) == 3 and not text.begins_with("WARNING:"): text = "WARNING: " + text
				lines.append(text)
			return {"native": true, "lines": lines, "data": data.merged({"offset": offset}), "partial": offset > 0 or data.get("partial", false) or int(data.get("next_offset", -1)) != -1}
	_collect_output(EditorInterface.get_base_control(), lines)
	return {"native": false, "lines": lines, "partial": true}

func _public_panel_data(args: Dictionary) -> Dictionary:
	var section = str(args["section"])
	var rows = []
	var paged_total = -1
	var result = {"available": true, "collected": true, "section": section, "read_only": true, "source": "public_editor_api"}
	var offset = maxi(0, int(args.get("offset", 0)))
	var limit = clampi(int(args.get("limit", 40)), 1, 100)
	if section == "selection":
		rows = EditorInterface.get_selection().get_selected_nodes().map(func(node: Node) -> Variant: return _encode(node))
	elif section == "inspector":
		var object = EditorInterface.get_inspector().get_edited_object()
		result["object"] = _encode(object)
		result["collected"] = object != null
		if object != null:
			for property in object.get_property_list():
				if not _panels()._credential_name(str(property["name"])) and int(property["usage"]) & PROPERTY_USAGE_EDITOR: rows.append(property)
		result["scope"] = "Inspected object and displayed property descriptors. Read selected values with godot_get and the returned object handle; no bulk property getters are executed here."
	elif section == "audio_buses":
		for index in AudioServer.bus_count:
			var row = {"index": index, "name": AudioServer.get_bus_name(index), "volume_db": AudioServer.get_bus_volume_db(index), "mute": AudioServer.is_bus_mute(index), "solo": AudioServer.is_bus_solo(index), "bypass_effects": AudioServer.is_bus_bypassing_effects(index), "send": AudioServer.get_bus_send(index), "effects": [], "signal_activity_available": false}
			for effect in AudioServer.get_bus_effect_count(index): row["effects"].append({"index": effect, "enabled": AudioServer.is_bus_effect_enabled(index, effect), "resource": _encode(AudioServer.get_bus_effect(index, effect))})
			if plugin != null and plugin.has_method("audio_bus_activity"):
				var activity: Dictionary = plugin.audio_bus_activity(index)
				row["signal_activity_available"] = activity.get("available", false)
				if row["signal_activity_available"]: row["signal_active"] = activity["active"]
			row["peak_left_db"] = AudioServer.get_bus_peak_volume_left_db(index, 0)
			row["peak_right_db"] = AudioServer.get_bus_peak_volume_right_db(index, 0)
			rows.append(row)
		result["scope"] = "Editor AudioServer bus configuration; the separately running game's audio state is not measured here."
	elif section == "animation":
		var player = _resolve(str(args.get("handle", ""))) as AnimationPlayer
		if player == null:
			for node in EditorInterface.get_selection().get_selected_nodes():
				if node is AnimationPlayer:
					player = node
					break
		if player == null:
			result["collected"] = false
			result["reason"] = "Select an AnimationPlayer or supply its handle."
		else:
			result["player"] = _encode(player)
			result["playing"] = player.is_playing()
			var name = str(args.get("animation", ""))
			if name.is_empty():
				for animation_name in player.get_animation_list():
					var animation = player.get_animation(animation_name)
					rows.append({"name": animation_name, "length": animation.length, "loop_mode": animation.loop_mode, "tracks": animation.get_track_count(), "resource": _encode(animation)})
			elif not player.has_animation(name): return Common.failure("Animația nu există.", "animation_unavailable")
			else:
				var animation = player.get_animation(name)
				result["animation"] = name
				if args.has("track"):
					var track = int(args["track"])
					if track >= animation.get_track_count(): return Common.failure("Pista nu există.", "invalid_track")
					paged_total = animation.track_get_key_count(track)
					for key in range(offset, mini(offset + limit, paged_total)): rows.append({"index": key, "time": animation.track_get_key_time(track, key), "transition": animation.track_get_key_transition(track, key), "value": _encode(animation.track_get_key_value(track, key))})
					result["track"] = track
				else:
					paged_total = animation.get_track_count()
					for track in range(offset, mini(offset + limit, paged_total)): rows.append({"index": track, "path": str(animation.track_get_path(track)), "type": animation.track_get_type(track), "enabled": animation.track_is_enabled(track), "keys": animation.track_get_key_count(track), "interpolation": animation.track_get_interpolation_type(track)})
		result["scope"] = "Selected player's animation resources and keys. Reading never plays, seeks, edits or evaluates an animation graph."
	result["items"] = rows if paged_total >= 0 else rows.slice(offset, offset + limit)
	result["total"] = paged_total if paged_total >= 0 else rows.size()
	result["offset"] = offset
	result["next_offset"] = offset + limit if offset + limit < int(result["total"]) else -1
	return Common.success(result)

func _debugger_text(event: Dictionary) -> String:
	var text = ("WARNING: " if event.get("severity") == "warning" else "ERROR: ") + str(event.get("message", ""))
	text += "\n at: %s (%s:%d) [debugger session=%s generation=%s %s]" % [event.get("function", ""), event.get("path", ""), int(event.get("line", 0)), event.get("session", "?"), event.get("generation", "?"), "active" if event.get("active", false) else "stopped"]
	for frame in event.get("stack", []):
		text += "\n at: %s (%s:%d)" % [frame.get("function", ""), frame.get("path", ""), int(frame.get("line", 0))]
	return text

func _collect_output(node: Node, output: Array) -> void:
	if node == panel or output.size() >= 12: return
	if node is RichTextLabel and node.is_visible_in_tree():
		var path = str(node.get_path()).to_lower()
		if "output" in path or "debug" in path or "log" in path: output.append(node.get_parsed_text().right(16000))
	for child in node.get_children(): _collect_output(child, output)

func _scene_history() -> UndoRedo:
	var root = EditorInterface.get_edited_scene_root()
	if root == null: return null
	var manager = plugin.get_undo_redo()
	return manager.get_history_undo_redo(manager.get_object_history_id(root))

func _begin_scene_change(label: String = "Modifică scena") -> void:
	if turn_id.is_empty(): return
	var history = _scene_history()
	if history == null: return
	if not scene_changes.has(turn_id): scene_changes[turn_id] = {"history": weakref(history), "before": history.get_version(), "after": history.get_version(), "count": 0, "conflict": false, "operations": []}
	var change: Dictionary = scene_changes[turn_id]
	change["pending_label"] = label
	if change["after"] != history.get_version(): change["conflict"] = true

func _end_scene_change() -> void:
	if not scene_changes.has(turn_id): return
	var change: Dictionary = scene_changes[turn_id]
	var history = _scene_history()
	change["after"] = history.get_version()
	change["count"] += 1
	change["operations"].append(change.get("pending_label", "Modifică scena"))

func change_summary(id: String) -> Array:
	var initial = {}
	var latest = {}
	for change in file_changes:
		if change.get("turn_id") == id:
			if not initial.has(change["path"]): initial[change["path"]] = change
			latest[change["path"]] = change
	var summary = []
	for path in initial:
		var change: Dictionary = initial[path]
		var before_path = str(change.get("backup", ""))
		var safe = Common.project_path(str(path))
		if safe.is_empty(): continue
		var before_sha = FileAccess.get_sha256(before_path) if change.get("existed", false) else "missing"
		var after_sha = FileAccess.get_sha256(safe) if FileAccess.file_exists(safe) else "missing"
		var state = "Restaurat" if before_sha == after_sha else ("Conflict" if latest[path].get("after_sha", after_sha) != after_sha else "Aplicat")
		var length = 0
		for file_path in [before_path, safe]:
			var input = FileAccess.open(file_path, FileAccess.READ) if not file_path.is_empty() else null
			if input != null: length += input.get_length(); input.close()
		var result = {"exact": false, "reason": "Fișier mare"}
		if length <= 2 * 1024 * 1024:
			var before = FileAccess.get_file_as_bytes(before_path) if change.get("existed", false) else PackedByteArray()
			var after = FileAccess.get_file_as_bytes(safe) if FileAccess.file_exists(safe) else PackedByteArray()
			var binary = 0 in before or 0 in after
			result = {"exact": false, "reason": "Fișier binar"} if binary else Diff.compare(before.get_string_from_utf8(), after.get_string_from_utf8())
		var item = {"path": path, "state": state, "exact": result["exact"], "added": result.get("added", 0), "removed": result.get("removed", 0), "diff": Diff.unified(path, result), "first_line": result.get("first_line", 1), "before_sha256": before_sha, "after_sha256": after_sha}
		summary.append(item)
	if scene_changes.has(id):
		var change: Dictionary = scene_changes[id]
		var history: UndoRedo = change["history"].get_ref()
		var state = "Aplicat"
		if history == null or change["conflict"]: state = "Conflict"
		elif history.get_version() == change["before"]: state = "Restaurat"
		elif history.get_version() != change["after"]: state = "Conflict"
		summary.append({"kind": "scene", "path": "Scenă · Undo", "state": state, "exact": false, "operations": change["count"], "diff": "Scenă · " + state + "\n" + "\n".join(change.get("operations", []))})

	for item in external_changes:
		if item.get("turn_id") == id: summary.append(item.duplicate(true))
	return summary

func external_snapshot() -> Dictionary:
	var listed: Array = _files({"path": "res://"}).get("result", [])
	var files = {}
	var skipped = []
	var budget = 16 * 1024 * 1024
	for path in listed:
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null: skipped.append(path); continue
		var length = file.get_length()
		if length > 1024 * 1024 or length > budget: skipped.append(path); continue
		budget -= length
		files[path] = FileAccess.get_sha256(path)
	return {"files": files, "complete": listed.size() < 400 and skipped.is_empty(), "skipped": skipped}

func record_external(before: Dictionary, after: Dictionary) -> Dictionary:
	var changed = []
	var all_paths = before.get("files", {}).keys()
	for path in after.get("files", {}):
		if path not in all_paths: all_paths.append(path)
	for path in all_paths:
		if not before.get("files", {}).has(path) and not before.get("complete", false): continue
		if not after.get("files", {}).has(path) and FileAccess.file_exists(path): continue
		if path in before.get("skipped", []) or path in after.get("skipped", []): continue
		var old = str(before.get("files", {}).get(path, "missing"))
		var current = str(after.get("files", {}).get(path, "missing"))
		if old == current: continue
		var item = {"turn_id": turn_id, "path": path, "kind": "external", "state": "Extern · fără recuperare", "exact": false, "before_sha256": old, "after_sha256": current, "diff": "Schimbare observată după comanda Linux; nu există copie de recuperare nativă."}
		external_changes.append(item)
		changed.append(item)
	Common.atomic_json(backup_directory.path_join("external.json"), external_changes)
	_request_scan()
	return {"changes": changed, "complete": before.get("complete", false) and after.get("complete", false), "note": "Bounded observation: at most 400 visible files, 1 MiB/file and 16 MiB total. Concurrent manual edits are not attributed exclusively to the command. No automatic recovery is claimed."}

func diff_turn(id: String) -> String:
	var output = ""
	for item in change_summary(id): output += str(item["diff"]) + "\n"
	return output + "\nRestaurarea verifică editările manuale și istoricul Undo al scenei."

func restore_turn(id: String) -> Dictionary:
	if external_changes.any(func(item: Dictionary) -> bool: return item.get("turn_id") == id): return Common.failure("Turnul include schimbări externe fără copie nativă. Verifică-le separat; restaurarea completă nu poate fi garantată.", "external_changes_untracked")
	var latest = {}
	for change in file_changes:
		if change.get("turn_id") == id and not change.get("restored", false): latest[change["path"]] = change
	for path in latest:
		var safe = Common.project_path(str(path))
		if safe.is_empty(): return Common.failure("Cale de restaurare invalidă.")
		var sha = FileAccess.get_sha256(safe) if FileAccess.file_exists(safe) else "missing"
		if latest[path].get("after_sha", "") != sha: return Common.failure("Conflict: fișier modificat ulterior: " + str(path), "restore_conflict")
	var scene: Dictionary = scene_changes.get(id, {})
	if not scene.is_empty():
		var history = scene["history"].get_ref()
		if history == null or scene["conflict"] or history.get_version() != scene["after"]: return Common.failure("Istoricul scenei a fost modificat ulterior.", "restore_conflict")
	for index in range(file_changes.size() - 1, -1, -1):
		var change: Dictionary = file_changes[index]
		if change.get("turn_id") != id or change.get("restored", false): continue
		var restored = _restore(index)
		if not restored.get("ok", false): return restored
		change["restored"] = true
	if not scene.is_empty():
		var history = scene["history"].get_ref()
		for step in range(scene["count"]): history.undo()
		scene_changes.erase(id)
	Common.atomic_json(backup_directory.path_join("journal.json"), file_changes)
	return Common.success("Modificările reversibile au fost restaurate. Verifică scena și fișierele.")

func _finalize_snapshot(index: int) -> void:
	if index < 0 or index >= file_changes.size(): return
	var path = str(file_changes[index]["path"])
	file_changes[index]["after_sha"] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	Common.atomic_json(backup_directory.path_join("journal.json"), file_changes)
