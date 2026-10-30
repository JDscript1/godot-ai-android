extends RefCounted
var host: EditorPlugin
var panel: Control
var chat: Control

func check(value: bool, text: String) -> void:
	host._check(value, text)

func pause() -> void:
	await host.get_tree().create_timer(0.2).timeout

func capture(name: String) -> void:
	host._workspace_capture(OS.get_environment("GODOT_AI_QA_OUTPUT"), name)

func run(qa: EditorPlugin, target: Control) -> void:
	host = qa
	panel = target
	chat = panel.chat
	chat.motion_enabled = false
	chat.clear_messages()
	var source = "extends Node\n" + "# source line\n".repeat(54)
	var path = "res://ai_inspection_probe.gd"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(source)
	file.close()
	EditorInterface.get_resource_filesystem().scan()
	await pause()
	chat.append_message("user", "Verifică mișcarea jucătorului și arată rezultatele.", {"id": "inspect-user", "turn_id": "inspect"})
	var metadata = {"turn_id": "inspect", "origin_label": "Godot AI · inspecție nativă"}
	var read = {"ok": true, "result": {"path": path, "lines": [{"line": 42, "text": "func move_player():"}, {"line": 43, "text": "\tvelocity = direction * speed"}, {"line": 44, "text": "\t# fixture-private-token"}], "next_line": 45}}
	panel.secrets.append("fixture-private-token")
	panel._chat_tool_event({"kind": "tool_started", "id": "range", "name": "godot_read_range", "arguments": {"path": path, "start_line": 42}}, metadata)
	panel._chat_tool_event({"kind": "tool_result", "id": "range", "name": "godot_read_range", "arguments": {"path": path, "start_line": 42}, "result": read, "duration_ms": 34}, metadata)
	panel._chat_tool_event({"kind": "tool_result", "id": "search", "name": "godot_search_code", "arguments": {"query": "move_player"}, "result": {"ok": true, "result": {"matches": [{"path": path, "line": 42, "column": 6, "text": "func move_player():", "before": [{"line": 41, "text": "# movement"}], "after": [{"line": 43, "text": "\tvelocity = direction * speed"}]}]}}}, metadata)
	chat.append_message("assistant", "Am citit mișcarea și am găsit funcția în [script](res://ai_inspection_probe.gd:42:6).", metadata.merged({"id": "inspect-answer"}))
	var group: Dictionary = chat.response_groups[-1]
	check(group["operations_rows"].get_child_count() == 0, "Collapsed inspection history constructs no source widgets")
	group["operations_toggle"].pressed.emit()
	var read_column = group["operations_rows"].get_child(0)
	check(read_column.get_child(1).get_child_count() == 0, "Collapsed read operations defer construction of source previews")
	read_column.get_child(0).pressed.emit()
	var details = read_column.get_child(1)
	var editors = details.find_children("*", "CodeEdit", true, false)
	check(editors.size() == 1 and editors[0].text.contains("velocity = direction") and not editors[0].text.contains("fixture-private-token"), "Expanded read cards show redacted native source snapshots")
	var editor: CodeEdit = editors[0]
	check(editor.get_line_gutter_text(0, editor.get_gutter_count() - 1) == "42", "Read card line gutters display actual one-based source locations")
	check(details.find_children("*", "Label", true, false).any(func(item: Label) -> bool: return item.text.contains("parțială")), "A bounded read displays an explicit partial-content notice")
	var requested = []
	var collect = func(name: String, args: Dictionary) -> void: requested.append({"name": name, "args": args})
	chat.action.disconnect(panel._chat_action)
	chat.action.connect(collect)
	var link: RichTextLabel = details.find_child("InspectionPath", true, false)
	link.meta_clicked.emit({"path": path, "line": 42, "column": 1})
	check(requested.size() == 1 and requested[0] == {"name": "project_open", "args": {"path": path, "line": 42, "column": 1}}, "Read card project links route to native navigation, never the OS URL handler")
	chat.scroll.ensure_control_visible(link)
	await pause()
	var link_touch = InputEventScreenTouch.new()
	link_touch.index = 9
	link_touch.position = link.get_global_rect().position + Vector2(6, 8) * EditorInterface.get_editor_scale()
	link_touch.pressed = true
	chat.get_viewport().push_input(link_touch, true)
	link_touch.pressed = false
	chat.get_viewport().push_input(link_touch, true)
	await pause()
	check(requested.size() == 2 and requested[-1]["name"] == "project_open" and requested[-1]["args"]["line"] == 42, "A native touch tap activates project-link metadata at the actual source line")
	link.meta_clicked.emit({"path": "res://../outside.gd", "line": 1})
	check(requested.size() == 2, "Forged project metadata cannot escape the project boundary")
	chat._jump_to_latest()
	await pause()
	capture("chat-read-card")
	read_column.get_child(0).pressed.emit()
	var search_column = group["operations_rows"].get_child(1)
	search_column.get_child(0).pressed.emit()
	var search_details = search_column.get_child(1)
	var snippets = search_details.find_children("*", "CodeEdit", true, false)
	check(snippets.size() == 1 and snippets[0].text == "# movement\nfunc move_player():\n\tvelocity = direction * speed", "Search cards show the actual match and its numbered neighboring lines")
	search_details.find_child("InspectionPath", true, false).meta_clicked.emit({"path": path, "line": 42, "column": 6})
	check(requested[-1]["args"]["column"] == 6, "Search hit links retain the exact matched source column")
	chat.action.disconnect(collect)
	chat.action.connect(panel._chat_action)
	await pause()
	capture("chat-search-card")
	var opened: Dictionary = panel._open_project_link({"path": path, "line": 42, "column": 6})
	await pause()
	check(opened.get("ok", false) and EditorInterface.get_script_editor().get_current_script().resource_path == path, "Explicit project navigation opens the real script in the native Godot editor")
	var script_editor = EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	check(script_editor is CodeEdit and script_editor.get_caret_line() == 41 and script_editor.get_caret_column() == 5, "Script navigation reaches the requested one-based line without an off-by-one error")
	check(not panel._open_project_link({"path": "res://.godot/private.gd"}).get("ok", false) and not panel._open_project_link({"path": "res://missing-inspection-file.gd"}).get("ok", false), "Private and missing project paths cannot be opened from chat")
	var text_file = FileAccess.open("res://ai_inspection_probe.txt", FileAccess.WRITE)
	text_file.store_string("First\nSecond\nThird\nFourth")
	text_file.close()
	var opened_text: Dictionary = panel._open_project_link({"path": "res://ai_inspection_probe.txt", "line": 3, "column": 1})
	await pause()
	var text_editor = panel.project_text_view.get_node("Source")
	check(opened_text.get("ok", false) and panel.project_text_view.visible and text_editor.get_caret_line() == 2 and not text_editor.editable, "Ordinary UTF-8 text links open a native read-only source window at the requested line")
	check(text_editor.highlight_current_line and text_editor.get_theme_font_size("font_size") == int(13 * EditorInterface.get_editor_scale()), "The source viewer highlights its target line and scales text to the actual editor density")
	check(panel.project_text_view.size.x <= panel.get_viewport_rect().size.x and panel.project_text_view.size.y <= panel.get_viewport_rect().size.y, "The project text viewer stays within the actual device viewport")
	RenderingServer.force_draw(false)
	panel.project_text_view.get_texture().get_image().save_png(OS.get_environment("GODOT_AI_QA_OUTPUT").path_join("chat-project-text-viewer.png"))
	panel.project_text_view.hide()
	EditorInterface.set_main_screen_editor("AI Assistant" if host.native else "AI Assistant QA")
	await pause()
	# History restoration resolves arguments from the most recent preceding call,
	# even across a visible-history boundary and when provider call IDs repeat.
	var old_history = panel.history
	var old_loaded = chat.loaded
	panel.history = [
		{"role": "user", "id": "restore-user", "content": "Citește două fișiere.", "turn_id": "restore"},
		{"role": "assistant", "tool_calls": [{"id": "same", "name": "godot_read_file", "arguments": {"path": path}}], "turn_id": "restore"},
		{"role": "tool", "tool_call_id": "same", "tool_name": "godot_read_file", "content": JSON.stringify({"ok": true, "result": "OLD SNAPSHOT"}), "turn_id": "restore"},
		{"role": "assistant", "tool_calls": [{"id": "same", "name": "godot_read_file", "arguments": {"path": "res://second-probe.gd"}}], "turn_id": "restore"},
		{"role": "tool", "tool_call_id": "same", "tool_name": "godot_read_file", "content": JSON.stringify({"ok": true, "result": "SECOND SNAPSHOT"}), "turn_id": "restore"}]
	chat.loaded = 3
	panel._render_history()
	var operations: Array = chat.response_groups[-1]["operations"]
	check(operations.size() == 2 and operations[0]["preview"]["items"][0]["path"] == path and operations[1]["preview"]["items"][0]["path"] == "res://second-probe.gd", "Restored read cards resolve preceding calls across pagination and reused call IDs")
	check(operations[0]["preview"]["items"][0]["rows"][0]["text"] == "OLD SNAPSHOT", "Restoring a read never replaces its original snapshot with current disk content")
	panel.history = old_history
	chat.loaded = old_loaded
	chat.clear_messages()
	chat.append_message("user", "Arată logica de mișcare și atac.", {"id": "diagram-user", "turn_id": "diagram"})
	var source_graph = 'flowchart TD\nStart([Jucător]) --> Input{Atac?}\nInput -->|Da| Attack[Atacă]\nInput -->|Nu| Move[Deplasează]\nAttack --> End([Continuă])\nMove --> End'
	var anchor = chat.append_message("assistant", "```mermaid\n" + source_graph + "\n```", {"id": "diagram-answer", "turn_id": "diagram"})
	var diagram: Dictionary = anchor.get_meta("message")["blocks"][0]
	await pause()
	var canvas = diagram["canvas"]
	check(diagram["kind"] == "diagram" and diagram["model"].get("ok", false) and canvas.is_visible_in_tree() and not diagram["editor"].visible, "Completed Mermaid flowcharts render natively with source collapsed")
	check(canvas.extent.x * canvas.zoom <= canvas.size.x + 1 and canvas.extent.y * canvas.zoom <= canvas.size.y + 1, "The complete diagram initially fits the actual device-sized chat canvas")
	check(not chat._native_touch_control(canvas), "Diagram viewing leaves ordinary touch scrolling attached to the conversation")
	chat._jump_to_latest()
	await pause()
	capture("chat-native-diagram")
	var zoom = canvas.zoom
	canvas.magnify(1.3)
	check(canvas.zoom > zoom, "Native diagram zoom enlarges the rendered graph")
	canvas.explore(true)
	check(chat._native_touch_control(canvas), "Explore mode hands touch gestures to the diagram without message selection")
	# Push native touch through the viewport, not just through a direct method.
	chat.scroll.ensure_control_visible(canvas)
	await pause()
	var pan_before_input = canvas.pan
	var actual_touch = InputEventScreenTouch.new()
	actual_touch.index = 23
	actual_touch.position = canvas.get_global_rect().get_center()
	actual_touch.pressed = true
	canvas.get_viewport().push_input(actual_touch, true)
	var actual_drag = InputEventScreenDrag.new()
	actual_drag.index = 23
	actual_drag.position = actual_touch.position + Vector2(20, 18)
	actual_drag.relative = Vector2(20, 18)
	canvas.get_viewport().push_input(actual_drag, true)
	actual_touch.pressed = false
	actual_touch.position = actual_drag.position
	canvas.get_viewport().push_input(actual_touch, true)
	check(canvas.pan.distance_to(pan_before_input + Vector2(20, 18)) < 1, "Viewport-dispatched touch gestures reach the native diagram in Explore mode")
	var pan = canvas.pan
	var touch = InputEventScreenTouch.new()
	touch.pressed = true
	touch.index = 17
	touch.position = Vector2(40, 60)
	canvas._gui_input(touch)
	var drag = InputEventScreenDrag.new()
	drag.index = 17
	drag.position = Vector2(75, 80)
	canvas._gui_input(drag)
	check(canvas.pan == pan + Vector2(35, 20), "Explore mode pans by the actual touch displacement")
	touch.pressed = false
	canvas._gui_input(touch)
	canvas.explore(false)
	canvas.fit()
	diagram["source_toggle"].pressed.emit()
	check(diagram["editor"].visible and diagram["editor"].text == source_graph, "Diagram source can be inspected without losing the rendered model")
	diagram["copy"].pressed.emit()
	check(DisplayServer.clipboard_get() == source_graph, "Copy preserves the entire original Mermaid source")
	chat._show_find(true)
	chat.find_input.text = "Input -->|Da|"
	chat._search_find()
	check(diagram["source_visible"] and diagram["editor"].visible, "Conversation search reveals matching Mermaid source")
	chat._show_find(false)
	var fallback = chat.append_message("assistant", "```mermaid\nsequenceDiagram\nA->>B: salut\n```", {"id": "unsupported-diagram", "turn_id": "fallback"}).get_meta("message")["blocks"][0]
	check(not fallback["canvas"].visible and fallback["editor"].visible and fallback["diagram_note"].text.contains("Sursa este păstrată"), "Unsupported diagrams show a clear explanation and readable source instead of a broken widget")
	var partial = chat.append_message("assistant", "", {"turn_id": "stream-diagram"})
	chat.stream_text(partial, "```mermaid\nflowchart LR\nA --> B")
	await pause()
	var streamed: Dictionary = partial.get_meta("message")["blocks"][0]
	check(not streamed["canvas"].visible and streamed["editor"].visible, "Incomplete streaming diagrams remain source until their block is complete")
	chat.stream_text(partial, "\n```")
	await pause()
	check(streamed["canvas"].visible and streamed["model"].get("ok", false), "A complete streamed diagram fence triggers native rendering exactly at completion")
	streamed["canvas"].magnify(1.3)
	var zoom_before_finish = streamed["canvas"].zoom
	chat.finish_stream(partial, {"id": "stream-diagram-final", "turn_id": "stream-diagram", "content": partial.get_meta("message")["text"]})
	check(is_equal_approx(streamed["canvas"].zoom, zoom_before_finish), "Finishing a response does not reset a completed diagram's zoom")
	var state_anchor = chat.append_message("assistant", '```mermaid\nstateDiagram-v2\n[*] --> Idle\nIdle --> Move: intrare\nMove --> Idle: stop\nMove --> [*]\n```', {"id": "state-diagram", "turn_id": "states"})
	var state_block: Dictionary = state_anchor.get_meta("message")["blocks"][0]
	await pause()
	check(state_block["canvas"].visible and state_block["canvas"].positions.size() == 4, "Flat state diagrams with cycles and terminals render as actual native controls")
	var loop = chat.append_message("assistant", "```mermaid\nflowchart TD\nA --> A\n```", {"id": "self-loop", "turn_id": "loop"}).get_meta("message")["blocks"][0]
	await pause()
	check(loop["canvas"].positions["A"].y >= 30 and loop["canvas"].extent.x >= 240 and loop["canvas"].extent.y >= 110, "Fit includes a self-loop's connector beyond the node bounds")
	panel.secrets.erase("fixture-private-token")
