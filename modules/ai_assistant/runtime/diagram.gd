@tool
extends Control
## Native, deliberately bounded Mermaid flowchart / flat state-diagram subset.
## No JS, web service, shell, embedded HTML or click directives are executed.
const MAX_NODES = 40
const MAX_EDGES = 80
var model: Dictionary = {}
var positions: Dictionary = {}
var extent = Vector2.ONE
var zoom = 1.0
var pan = Vector2.ZERO
var interactive = false
var gesture: Dictionary = {}
var unit = 1.0

static func _error(message: String, line: int = 0) -> Dictionary:
	return {"ok": false, "error": ("Linia %d: " % line if line > 0 else "") + message}

static func _label(text: String) -> String:
	return text.trim_prefix("\"").trim_suffix("\"").replace("\\n", "\n").replace("<br/>", "\n").replace("<br>", "\n")

static func _node(text: String, state: bool, terminal: String = "") -> Dictionary:
	var raw = text.strip_edges(true, false)
	if state and raw.begins_with("[*]"):
		return {"id": "__" + terminal, "label": "Start" if terminal == "start" else "Stop", "shape": "terminal", "rest": raw.substr(3)}
	var pattern = RegEx.new()
	pattern.compile("^[A-Za-z_](?:(?!-->|---|-\\.->|==>)[A-Za-z0-9_-])*")
	var found = pattern.search(raw)
	if found == null: return {}
	var id = found.get_string()
	var rest = raw.substr(id.length())
	var node = {"id": id, "label": id, "shape": "box", "rest": rest, "explicit": false}
	if state: return node
	var pairs = [["((", "))", "circle"], ["([", "])", "round"], ["[", "]", "box"], ["{", "}", "diamond"], ["(", ")", "round"]]
	for pair in pairs:
		if not rest.begins_with(pair[0]): continue
		var quoted = false
		var end = -1
		for index in range(str(pair[0]).length(), rest.length()):
			if rest[index] == "\"": quoted = not quoted
			if not quoted and rest.substr(index).begins_with(pair[1]): end = index; break
		if end < 0: return {}
		node["label"] = _label(rest.substr(str(pair[0]).length(), end - str(pair[0]).length()))
		if node["label"].length() > 240: return {}
		node["shape"] = pair[2]
		node["explicit"] = true
		node["rest"] = rest.substr(end + str(pair[1]).length())
		return node
	return node

static func _remember(nodes: Dictionary, node: Dictionary) -> void:
	if not nodes.has(node["id"]) or node.get("explicit", false):
		nodes[node["id"]] = {"id": node["id"], "label": node["label"], "shape": node["shape"]}

static func _statements(source: String) -> Array:
	var statements = []
	var current = ""
	var quoted = false
	var depth = 0
	var pipe = false
	var line = 1
	var start = 1
	for character in source:
		if character == "\"": quoted = not quoted
		if not quoted:
			if character in ["[", "(", "{"]: depth += 1
			if character in ["]", ")", "}"]: depth -= 1
			if character == "|" and depth == 0: pipe = not pipe
		if character == "\n" or (character == ";" and not quoted and depth == 0 and not pipe):
			if not current.strip_edges().is_empty(): statements.append({"text": current.strip_edges(), "line": start})
			current = ""
			start = line + 1 if character == "\n" else line
		else: current += character
		if character == "\n": line += 1
	if not current.strip_edges().is_empty(): statements.append({"text": current.strip_edges(), "line": start})
	return statements

static func parse(source: String) -> Dictionary:
	if source.length() > 16000: return _error("Diagrama depășește limita de 16.000 caractere.")
	var statements = _statements(source.replace("\r\n", "\n"))
	var nodes = {}
	var edges = []
	var direction = "TD"
	var kind = ""
	var header = RegEx.new()
	header.compile("^(?:flowchart|graph)\\s+(TD|TB|BT|LR|RL)$")
	var state_alias = RegEx.new()
	state_alias.compile('^state\\s+"([^"\\n]{1,240})"\\s+as\\s+([A-Za-z_][A-Za-z0-9_-]*)$')
	var connector = RegEx.new()
	connector.compile("^(-->|---|-\\.->|==>)(?:\\s*\\|([^|\\n]{1,160})\\|)?\\s*")
	var labeled = RegEx.new()
	labeled.compile("^--\\s+([^<>|\\n]{1,160}?)\\s+-->\\s*")
	for statement in statements:
		var text = str(statement["text"])
		var number = int(statement["line"])
		if text.begins_with("%%") and not text.begins_with("%%{"): continue
		if kind.is_empty():
			var flow = header.search(text)
			if flow != null: kind = "flowchart"; direction = flow.get_string(1)
			elif text == "stateDiagram-v2": kind = "state"
			else: return _error("Sunt suportate flowchart / graph și stateDiagram-v2 simplu.", number)
			continue
		if kind == "state" and text.begins_with("direction "):
			var wanted = text.trim_prefix("direction ").strip_edges()
			if wanted not in ["TD", "TB", "BT", "LR", "RL"]: return _error("Direcție nesuportată.", number)
			direction = wanted
			continue
		if kind == "state":
			var alias = state_alias.search(text)
			if alias != null:
				_remember(nodes, {"id": alias.get_string(2), "label": alias.get_string(1), "shape": "round", "explicit": true})
				if nodes.size() > MAX_NODES: return _error("Maximum 40 de noduri.", number)
				continue
		var left = _node(text, kind == "state", "start")
		if left.is_empty(): return _error("Nod sau sintaxă nesuportată; sursa rămâne disponibilă.", number)
		_remember(nodes, left)
		var rest = str(left["rest"]).strip_edges()
		if kind == "state" and rest.begins_with(":"):
			var description = rest.trim_prefix(":").strip_edges()
			if description.length() > 240: return _error("Etichetă prea lungă.", number)
			nodes[left["id"]]["label"] = _label(description)
			rest = ""
		while not rest.is_empty():
			var edge = connector.search(rest)
			var alt = labeled.search(rest) if edge == null and kind == "flowchart" else null
			if edge == null and alt == null: return _error("Conector, directivă sau structură nesuportată.", number)
			var end = edge.get_end() if edge != null else alt.get_end()
			var right = _node(rest.substr(end), kind == "state", "stop")
			if right.is_empty(): return _error("Destinație invalidă sau etichetă prea lungă.", number)
			_remember(nodes, right)
			var caption = edge.get_string(2) if edge != null else alt.get_string(1)
			var tail = str(right["rest"]).strip_edges()
			if kind == "state" and tail.begins_with(":"):
				caption = tail.trim_prefix(":").strip_edges()
				if caption.length() > 160: return _error("Etichetă de tranziție prea lungă.", number)
				tail = ""
			edges.append({"from": left["id"], "to": right["id"], "label": _label(caption), "arrow": edge == null or edge.get_string(1) != "---", "dashed": edge != null and edge.get_string(1) == "-.->"})
			left = right
			rest = tail
			if edges.size() > MAX_EDGES or nodes.size() > MAX_NODES: return _error("Maximum 40 de noduri și 80 de legături.", number)
		if nodes.size() > MAX_NODES: return _error("Maximum 40 de noduri.", number)
	if nodes.is_empty(): return _error("Diagrama nu conține noduri.")
	return {"ok": true, "nodes": nodes, "edges": edges, "direction": direction, "kind": kind}

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(func() -> void: fit())

func configure(value: Dictionary, scale_factor: float) -> void:
	model = value
	unit = scale_factor
	custom_minimum_size.y = 280 * unit
	_layout()
	fit.call_deferred()

func _layout() -> void:
	positions.clear()
	var nodes: Dictionary = model.get("nodes", {})
	var incoming = {}
	for id in nodes: incoming[id] = 0
	for edge in model.get("edges", []): incoming[edge["to"]] += 1
	var ranks = {}
	var queue = []
	for id in nodes:
		if incoming[id] == 0: ranks[id] = 0; queue.append(id)
	while ranks.size() < nodes.size() or not queue.is_empty():
		if queue.is_empty():
			for id in nodes:
				if not ranks.has(id): ranks[id] = 0; queue.append(id); break
		var id = queue.pop_front()
		for edge in model.get("edges", []):
			if edge["from"] == id and not ranks.has(edge["to"]):
				ranks[edge["to"]] = int(ranks[id]) + 1
				queue.append(edge["to"])
	var groups = {}
	var horizontal = model.get("direction") in ["LR", "RL"]
	for id in nodes:
		var rank = int(ranks[id])
		var slot = int(groups.get(rank, 0))
		groups[rank] = slot + 1
		positions[id] = Vector2(rank * 320, slot * 142) if horizontal else Vector2(slot * 270, rank * 166)
	extent = Vector2.ONE
	for point in positions.values(): extent = extent.max(Vector2(point) + Vector2(210, 80))
	# Center short ranks within a branching graph, keeping roots and joins aligned.
	for id in positions:
		var rank = int(ranks[id])
		if horizontal: positions[id].y += (extent.y - (int(groups[rank]) - 1) * 142 - 80) * 0.5
		else: positions[id].x += (extent.x - (int(groups[rank]) - 1) * 270 - 210) * 0.5
	if model.get("direction") in ["BT", "RL"]:
		for id in positions:
			if horizontal: positions[id].x = extent.x - 210 - positions[id].x
			else: positions[id].y = extent.y - 80 - positions[id].y
	# A self-loop extends past the node's right/top bounds. Include the whole
	# connector in Fit instead of cropping it at the canvas edge.
	var minimum = Vector2.ZERO
	var maximum = extent
	for edge in model.get("edges", []):
		if edge["from"] != edge["to"]: continue
		minimum = minimum.min(Vector2(positions[edge["from"]]) + Vector2(0, -30))
		maximum = maximum.max(Vector2(positions[edge["from"]]) + Vector2(240, 80))
	for id in positions: positions[id] -= minimum
	extent = maximum - minimum

func fit() -> void:
	zoom = minf(1.3 * unit, minf(maxf(1, size.x - 24 * unit) / extent.x, maxf(1, size.y - 24 * unit) / extent.y))
	pan = (size - extent * zoom) * 0.5
	queue_redraw()

func magnify(factor: float) -> void:
	var previous = zoom
	zoom = clampf(zoom * factor, 0.03 * unit, 3.0 * unit)
	pan = size * 0.5 - (size * 0.5 - pan) * zoom / previous
	queue_redraw()

func explore(enabled: bool) -> void:
	interactive = enabled
	set_meta("chat_native_gesture", enabled)
	gesture.clear()

func _gui_input(event: InputEvent) -> void:
	if not interactive: return
	if event is InputEventPanGesture:
		pan -= event.delta * 20 * unit
		queue_redraw()
		accept_event()
	elif event is InputEventMagnifyGesture:
		magnify(event.factor)
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed and gesture.is_empty(): gesture = {"index": event.index, "point": event.position}
		elif not event.pressed and gesture.get("index", -1) == event.index: gesture.clear()
		accept_event()
	elif event is InputEventScreenDrag and gesture.get("index", -1) == event.index:
		pan += event.position - Vector2(gesture["point"])
		gesture["point"] = event.position
		queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and event.device != -1:
		if event.button_index == MOUSE_BUTTON_LEFT:
			gesture = {"index": -2, "point": event.position} if event.pressed else {}
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: magnify(1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2)
		accept_event()
	elif event is InputEventMouseMotion and gesture.get("index", -1) == -2:
		pan += event.relative
		queue_redraw()
		accept_event()

func _point(point: Vector2) -> Vector2:
	return point * zoom + pan

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101725"))
	if not model.get("ok", false): return
	var horizontal = model.get("direction") in ["LR", "RL"]
	var font = get_theme_font("font", "Label")
	for edge in model["edges"]:
		var a: Vector2 = positions[edge["from"]] + Vector2(105, 40)
		var b: Vector2 = positions[edge["to"]] + Vector2(105, 40)
		var delta = b - a
		var forward = delta.x >= 0 if horizontal else delta.y >= 0
		var vector = Vector2(1 if forward else -1, 0) if horizontal else Vector2(0, 1 if forward else -1)
		var start = a + vector * (105 if horizontal else 40)
		var end = b - vector * (105 if horizontal else 40)
		var points = PackedVector2Array()
		if a == b:
			points = PackedVector2Array([_point(a + Vector2(105, 0)), _point(a + Vector2(135, 0)), _point(a + Vector2(135, -70)), _point(a + Vector2(0, -70)), _point(a + Vector2(0, -40))])
		else:
			var bend = (start + end) * 0.5
			points = PackedVector2Array([_point(start), _point(Vector2(bend.x, start.y) if horizontal else Vector2(start.x, bend.y)), _point(Vector2(bend.x, end.y) if horizontal else Vector2(end.x, bend.y)), _point(end)])
		for index in range(points.size() - 1):
			if edge["dashed"]: draw_dashed_line(points[index], points[index + 1], Color("849dbd"), 1.5 * unit, 5 * unit)
			else: draw_line(points[index], points[index + 1], Color("849dbd"), 1.5 * unit, true)
		if edge["arrow"]:
			var tip = points[-1]
			var direct = (tip - points[-2]).normalized()
			if direct.is_zero_approx(): direct = vector
			var normal = Vector2(-direct.y, direct.x)
			draw_colored_polygon(PackedVector2Array([tip, tip - direct * 8 * unit + normal * 4 * unit, tip - direct * 8 * unit - normal * 4 * unit]), Color("9db6d4"))
		if not str(edge["label"]).is_empty():
			var at = points[1].lerp(points[2], 0.5)
			var text_size = int(clampf(12 * zoom, 8 * unit, 14 * unit))
			var label_size = font.get_string_size(edge["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, text_size)
			draw_rect(Rect2(at - Vector2(label_size.x * 0.5 + 4 * unit, label_size.y), label_size + Vector2(8 * unit, 4 * unit)), Color("101725"))
			draw_string(font, at - Vector2(label_size.x * 0.5, 3 * unit), edge["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color("c7d5e9"))
	for id in model["nodes"]:
		var node: Dictionary = model["nodes"][id]
		var rect = Rect2(_point(positions[id]), Vector2(210, 80) * zoom)
		if node["shape"] == "diamond":
			var points = PackedVector2Array([rect.position + Vector2(rect.size.x * 0.5, 0), rect.position + Vector2(rect.size.x, rect.size.y * 0.5), rect.position + Vector2(rect.size.x * 0.5, rect.size.y), rect.position + Vector2(0, rect.size.y * 0.5)])
			draw_colored_polygon(points, Color("423554"))
			points.append(points[0])
			draw_polyline(points, Color("c2a3df"), maxf(1, unit), true)
		elif node["shape"] in ["circle", "terminal"]:
			# An ellipse fits the same readable label box as other nodes.
			var points = PackedVector2Array()
			for index in range(49): points.append(rect.get_center() + Vector2(cos(index * TAU / 48.0), sin(index * TAU / 48.0)) * rect.size * 0.5)
			draw_colored_polygon(points, Color("243a40"))
			draw_polyline(points, Color("91b8b5"), maxf(1, unit), true)
		else:
			var style = StyleBoxFlat.new()
			style.bg_color = Color("26344c")
			style.border_color = Color("8ba4ca")
			style.set_border_width_all(maxi(1, int(unit)))
			style.set_corner_radius_all(int((16 if node["shape"] == "round" else 7) * zoom))
			draw_style_box(style, rect)
		# Fit the graph, but keep its labels readable on a phone. Zooming in
		# grows the text too; longer labels wrap/ellipsize inside each node.
		var font_size = int(clampf(14 * zoom, 10 * unit, 28 * unit))
		var paragraph = TextParagraph.new()
		paragraph.add_string(node["label"], font, font_size)
		paragraph.width = rect.size.x * (0.66 if node["shape"] == "diamond" else 0.88)
		paragraph.alignment = HORIZONTAL_ALIGNMENT_CENTER
		paragraph.max_lines_visible = clampi(int(rect.size.y / font.get_height(font_size)), 1, 3)
		paragraph.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		paragraph.draw(get_canvas_item(), rect.get_center() - Vector2(paragraph.width, paragraph.get_size().y) * 0.5, Color("e0e8f6"))
