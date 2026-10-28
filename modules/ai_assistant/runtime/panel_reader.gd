@tool
extends RefCounted
## Read-only UI snapshots. Never opens a panel, expands a tree or calls plugin methods.
static var Common: GDScript
const MAX_NODES = 30000
const MAX_ROWS = 10000
const MAX_CELLS = 30000
const MAX_TEXT = 4 * 1024 * 1024
var owner: WeakRef
var tools: RefCounted:
	get: return owner.get_ref() if owner != null else null
var snapshots = {}

func _init(editor_tools: RefCounted = null) -> void:
	owner = weakref(editor_tools) if editor_tools != null else null

func _credential_name(value: String) -> bool:
	var key = value.to_lower().replace("-", "_").replace(" ", "_")
	return ["api_key", "apikey", "access_token", "refresh_token", "auth_token", "client_secret", "private_key", "password"].any(func(part: String) -> bool: return part in key)

func _protected(node: Node) -> bool:
	while node != null:
		if node == tools.panel: return true
		if _credential_name(str(node.name)): return true
		if node is LineEdit and node.secret: return true
		node = node.get_parent()
	return false

func _label(node: Node) -> String:
	if _protected(node): return ""
	if node is Label or node is Button: return str(node.text)
	if node is Window: return node.title
	if node is LineEdit: return node.text
	return str(node.name)

func _visible(node: Node) -> bool:
	return node.visible if node is Window else node.is_visible_in_tree() if node is CanvasItem else false

func _summary(node: Node) -> Dictionary:
	var item: Dictionary = tools._encode(node)
	item["path"] = str(node.get_path()) if node.is_inside_tree() else str(node.name)
	item["parent"] = tools._encode(node.get_parent()) if node.get_parent() != null else {}
	item["visible"] = _visible(node)
	item["label"] = _label(node).left(400)
	item["protected"] = _protected(node)
	if node is Control and not item["protected"]:
		item["tooltip"] = node.tooltip_text.left(1000)
		item["tooltip_truncated"] = node.tooltip_text.length() > 1000
	item["reader"] = "tree" if node is Tree else "list" if node is ItemList or node is PopupMenu or node is OptionButton else "text" if node is TextEdit or node is RichTextLabel or node is LineEdit or node is Label else "value" if node is Range or node is BaseButton else "tabs" if node is TabContainer else "container"
	item["role"] = "dock" if node is EditorDock else "window" if node is Window else "control"
	item["children"] = node.get_child_count(true)
	if node is GraphEdit: item["reader"] = "graph"
	elif node is GraphElement: item["reader"] = "graph_node"
	elif node is TextureRect: item["reader"] = "texture"
	elif node is ColorPicker: item["reader"] = "color"
	item["readable"] = not item["protected"] and item["reader"] != "container"
	if node.get_parent() is TabContainer:
		var parent: TabContainer = node.get_parent()
		for index in parent.get_tab_count():
			if parent.get_tab_control(index) == node:
				item["role"] = "tab"
				item["tab_title"] = parent.get_tab_title(index)
				item["tab_index"] = index
				break
	return item

func _store(data: Dictionary) -> String:
	for id in snapshots.keys():
		if Time.get_ticks_msec() - snapshots[id].get("accessed", snapshots[id]["created"]) > 300000: snapshots.erase(id)
	while snapshots.size() >= 4: snapshots.erase(snapshots.keys()[0])
	var id = Common.uid()
	snapshots[id] = data.merged({"created": Time.get_ticks_msec()})
	return id

func _saved(args: Dictionary, kind: String) -> Dictionary:
	var id = str(args.get("snapshot", ""))
	if id.is_empty(): return {}
	var data: Dictionary = snapshots.get(id, {})
	if data.is_empty() or data.get("kind") != kind or Time.get_ticks_msec() - data.get("accessed", data["created"]) > 300000:
		return {"error": Common.failure("Snapshot expirat sau de alt tip; citește din nou panoul.", "stale_panel_snapshot")}
	data["accessed"] = Time.get_ticks_msec()
	return data

func catalog(root: Node, args: Dictionary) -> Dictionary:
	var data = _saved(args, "catalog")
	if data.has("error"): return data["error"]
	var id = str(args.get("snapshot", ""))
	if not data.is_empty() and args.has("handle") and str(args["handle"]) != data.get("root_handle", ""):
		return Common.failure("Snapshot-ul aparține altui panou.", "snapshot_mismatch")
	if data.is_empty():
		var rows = []
		var pending = [root]
		var examined = 0
		var filter = str(args.get("filter", "")).to_lower()
		var scene_root = EditorInterface.get_edited_scene_root() if Engine.is_editor_hint() else null
		while not pending.is_empty() and examined < MAX_NODES and rows.size() < MAX_ROWS:
			var node: Node = pending.pop_back()
			examined += 1
			if node == tools.panel: continue
			if node == scene_root and node != root: continue # Project nodes have dedicated scene/runtime tools.
			if (node is Control or node is Window) and (args.get("include_hidden", true) or _visible(node)):
				var item = _summary(node)
				if filter.is_empty() or filter in (item["path"] + " " + item["label"] + " " + str(item.get("class", "")) + " " + str(item.get("tab_title", ""))).to_lower(): rows.append(item)
			var children = node.get_children(true)
			children.reverse()
			pending.append_array(children)
		data = {"kind": "catalog", "root_handle": str(args.get("handle", "")), "rows": rows, "partial": not pending.is_empty(), "examined": examined, "include_hidden": args.get("include_hidden", true), "filter": filter}
		id = _store(data)
	var result = _page(data, id, args)
	result["result"]["collection"] = {"examined_nodes": data.get("examined", 0), "root_handle": data.get("root_handle", ""), "filter": data.get("filter", ""), "include_hidden": data.get("include_hidden", true)}
	result["result"]["scope"] = "Instantiated Godot controls, including hidden tabs. Assistant UI and secret contents are excluded. Unloaded plugin panels do not have readable state yet."
	return result

func _page(data: Dictionary, id: String, args: Dictionary) -> Dictionary:
	var offset = maxi(0, int(args.get("offset", 0)))
	var limit = clampi(int(args.get("limit", 40)), 1, 100)
	var rows: Array = data.get("rows", [])
	return Common.success({"snapshot": id, "snapshot_age_ms": Time.get_ticks_msec() - int(data.get("created", Time.get_ticks_msec())), "items": rows.slice(offset, offset + limit), "total": rows.size(), "offset": offset, "next_offset": offset + limit if offset + limit < rows.size() else -1, "partial": data.get("partial", false), "snapshot_only": true})

func read(node: Node, args: Dictionary) -> Dictionary:
	var data = _saved(args, "control")
	if data.has("error"): return data["error"]
	var id = str(args.get("snapshot", ""))
	if data.is_empty():
		if not (node is Control or node is Window): return Common.failure("Handle-ul nu mai indică un control Godot.", "stale_handle")
		if _protected(node): return Common.failure("Conținut protejat sau interfața proprie a asistentului.", "protected_control")
		data = _capture(node)
		data["kind"] = "control"
		data["handle"] = str(args.get("handle", ""))
		id = _store(data)
	elif args.has("handle") and args["handle"] != data.get("handle"): return Common.failure("Handle diferit de cel al snapshot-ului.", "snapshot_mismatch")
	var result = _page(data, id, args)
	var payload: Dictionary = result["result"]
	payload["control"] = data["control"]
	payload["state"] = data.get("state", {})
	payload["coverage"] = data["coverage"]
	var text = str(data.get("text", ""))
	if args.get("field", "text") == "tooltip": text = str(data.get("tooltip", ""))
	if args.has("item"):
		var index = int(args["item"])
		if index < 0 or index >= data["rows"].size(): return Common.failure("Element inexistent în snapshot.", "invalid_item")
		var row: Dictionary = data["rows"][index]
		payload["items"] = [row]
		payload["selected_item"] = index
		payload["next_offset"] = -1
		var cells: Array = row.get("cells", [])
		var column = int(args.get("column", 0))
		if not cells.is_empty():
			if column < 0 or column >= cells.size(): return Common.failure("Coloană inexistentă.", "invalid_column")
			text = str(cells[column].get(str(args.get("field", "text")), ""))
		else: text = str(row.get("tooltip", "")) if args.get("field", "text") == "tooltip" else str(row.get("text", row.get("title", "")))
	var start = maxi(0, int(args.get("text_offset", 0)))
	var length = clampi(int(args.get("text_limit", 4000)), 1, 16000)
	payload["text"] = {"value": text.substr(start, length), "offset": start, "length": text.length(), "next_offset": start + length if start + length < text.length() else -1, "sha256": text.sha256_text()}
	# Keep long cells pageable without returning their entire contents on every row page.
	var visible = []
	for raw in payload["items"]:
		var row: Dictionary = raw.duplicate(true)
		for key in ["text", "title", "tooltip"]:
			if row.get(key) is String:
				row[key + "_length"] = row[key].length()
				row[key] = row[key].left(512)
		if row.has("cells"):
			for cell in row["cells"]:
				cell["text_length"] = str(cell.get("text", "")).length()
				cell["text"] = str(cell.get("text", "")).left(512)
				cell["tooltip"] = str(cell.get("tooltip", "")).left(512)
		visible.append(row)
	payload["items"] = visible
	return result

func _capture(node: Node) -> Dictionary:
	var data = {"control": _summary(node), "rows": [], "text": "", "state": {}, "partial": false, "coverage": {"hidden_supported": true, "collapsed_supported": true, "custom_draw_data": false, "scope": "Cached standard controls only; container children must be read separately. Custom-drawn data requires a native source or capture."}}
	data["tooltip"] = node.tooltip_text.left(MAX_TEXT) if node is Control else ""
	if node is Control and node.tooltip_text.length() > MAX_TEXT: data["partial"] = true
	data["coverage"]["contents_readable"] = data["control"]["readable"]
	var rows: Array = data["rows"]
	var budget = MAX_TEXT
	budget -= data["tooltip"].length()
	var visited_cells = 0
	if node is Tree:
		var pending = []
		if node.get_root() != null: pending.append({"item": node.get_root(), "depth": 0})
		while not pending.is_empty() and rows.size() < MAX_ROWS and budget > 0 and visited_cells < MAX_CELLS:
			var current: Dictionary = pending.pop_back()
			var item: TreeItem = current["item"]
			var cells = []
			for column in mini(node.columns, 32):
				if visited_cells >= MAX_CELLS:
					data["partial"] = true
					break
				visited_cells += 1
				var raw_text = item.get_text(column)
				var cell_text = raw_text.left(maxi(0, budget))
				budget -= cell_text.length()
				var raw_tip = item.get_tooltip_text(column)
				var tip = raw_tip.left(maxi(0, budget))
				budget -= tip.length()
				if cell_text.length() < raw_text.length(): data["partial"] = true
				if tip.length() < raw_tip.length(): data["partial"] = true
				cells.append({"column": column, "text": cell_text, "tooltip": tip, "checked": item.is_checked(column), "selected": item.is_selected(column), "editable": item.is_editable(column), "mode": item.get_cell_mode(column), "range": item.get_range(column)})
			rows.append({"index": rows.size(), "depth": current["depth"], "collapsed": item.collapsed, "cells": cells})
			var children = []
			var child = item.get_first_child()
			while child != null:
				children.append({"item": child, "depth": current["depth"] + 1})
				child = child.get_next()
			children.reverse()
			pending.append_array(children)
		data["partial"] = data["partial"] or not pending.is_empty() or node.columns > 32
	elif node is ItemList or node is OptionButton or node is PopupMenu:
		for index in mini(node.item_count, MAX_ROWS):
			if budget <= 0:
				data["partial"] = true
				break
			var raw_text = node.get_item_text(index)
			var value = raw_text.left(budget)
			budget -= value.length()
			if value.length() < raw_text.length(): data["partial"] = true
			var item = {"index": index, "text": value, "disabled": node.is_item_disabled(index)}
			if node is ItemList: item["selected"] = node.is_selected(index)
			elif node is OptionButton:
				item["selected"] = node.selected == index
				item["id"] = node.get_item_id(index)
			elif node is PopupMenu:
				item["checked"] = node.is_item_checked(index)
				item["id"] = node.get_item_id(index)
				item["separator"] = node.is_item_separator(index)
			rows.append(item)
		data["partial"] = data["partial"] or node.item_count > MAX_ROWS
	elif node is TabContainer:
		for index in mini(node.get_tab_count(), MAX_ROWS): rows.append({"index": index, "title": node.get_tab_title(index), "hidden": node.is_tab_hidden(index), "disabled": node.is_tab_disabled(index), "selected": node.current_tab == index, "control": tools._encode(node.get_tab_control(index))})
	elif node is GraphEdit:
		data["rows"] = node.get_connection_list().slice(0, MAX_ROWS)
		data["partial"] = node.get_connection_list().size() > MAX_ROWS
		data["coverage"]["graph_connections"] = true
	elif node is TextEdit or node is Label or node is LineEdit or node is Button: data["text"] = node.text
	elif node is Window: data["text"] = node.title
	elif node is RichTextLabel: data["text"] = node.get_parsed_text()
	if node is TextEdit: data["state"] = {"read_only": not node.editable, "caret_line": node.get_caret_line(), "caret_column": node.get_caret_column(), "line_count": node.get_line_count()}
	elif node is LineEdit: data["state"] = {"editable": node.editable, "caret_column": node.caret_column}
	elif node is Range: data["state"] = {"value": node.value, "min": node.min_value, "max": node.max_value, "step": node.step}
	elif node is BaseButton: data["state"] = {"disabled": node.disabled, "toggle": node.toggle_mode, "pressed": node.button_pressed}
	if node is GraphEdit: data["state"] = {"zoom": node.zoom, "scroll_offset": [node.scroll_offset.x, node.scroll_offset.y]}
	elif node is GraphElement:
		data["state"] = {"position_offset": [node.position_offset.x, node.position_offset.y], "selected": node.selected, "draggable": node.draggable}
		if node is GraphNode: data["state"].merge({"title": node.title, "input_ports": node.get_input_port_count(), "output_ports": node.get_output_port_count()})
	elif node is TextureRect:
		data["state"] = {"texture": tools._encode(node.texture), "width": node.texture.get_width() if node.texture != null else 0, "height": node.texture.get_height() if node.texture != null else 0}
	elif node is ColorPicker or node is ColorPickerButton: data["state"]["color"] = [node.color.r, node.color.g, node.color.b, node.color.a]
	if str(data["text"]).length() > MAX_TEXT:
		data["text"] = data["text"].left(MAX_TEXT)
		data["partial"] = true
	data["coverage"]["partial"] = data["partial"]
	return data
