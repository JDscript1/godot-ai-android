@tool
extends Window
## Full usable-window viewer; closing never clears the conversation or draft.
static var Common: GDScript
static var Icons: GDScript
static var ModelPreview: GDScript
var load_result: Dictionary = {}
var model_views: Array = []
signal action(name: String, args: Dictionary)
var registry: RefCounted
var scope = ""
var ids: Array = []
var current = 0
var content: HBoxContainer
var caption: Label
var detail: Label
var canvases: Array = []
var commands: Dictionary = {}

class ImageCanvas:
	extends Control
	signal pose_changed(value: Dictionary)
	var image: Image
	var texture: ImageTexture
	var checker: ImageTexture
	var zoom = 1.0
	var offset = Vector2.ZERO
	var touches = {}
	var selection = Rect2()
	var choosing = false
	var drawing = false
	var start = Vector2.ZERO
	var previous = Vector2.ZERO
	var arrows: Array = []
	var arrow_mode = false
	var last_tap = 0
	var last_tap_position = Vector2.ZERO

	func setup(value: Image) -> void:
		image = value
		texture = ImageTexture.create_from_image(image)
		if image.detect_alpha() != Image.ALPHA_NONE:
			var cell = maxi(8, int(12 * EditorInterface.get_editor_scale()))
			var board = Image.create(cell * 2, cell * 2, false, Image.FORMAT_RGB8)
			board.fill(Color("1c2432"))
			for origin in [Vector2i.ZERO, Vector2i(cell, cell)]: board.fill_rect(Rect2i(origin, Vector2i(cell, cell)), Color("2b3444"))
			checker = ImageTexture.create_from_image(board)
		clip_contents = true
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		resized.connect(queue_redraw)

	func display_rect() -> Rect2:
		if image == null: return Rect2()
		var fit = minf(size.x / image.get_width(), size.y / image.get_height())
		var extent = image.get_size() * fit * zoom
		return Rect2((size - extent) * 0.5 + offset, extent)

	func image_point(point: Vector2) -> Vector2:
		var rect = display_rect()
		if rect.size.x <= 0: return Vector2.ZERO
		return ((point - rect.position) / rect.size * image.get_size()).clamp(Vector2.ZERO, image.get_size())

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("111522"))
		if texture == null: return
		var rect = display_rect()
		if checker != null: draw_texture_rect(checker, rect, true)
		draw_texture_rect(texture, rect, false)
		if selection.has_area():
			var ratio = rect.size / image.get_size()
			draw_rect(Rect2(rect.position + selection.position * ratio, selection.size * ratio), Color("bc9bf0"), false, 3)
		for arrow in arrows:
			var a: Vector2 = rect.position + arrow[0] / image.get_size() * rect.size
			var b: Vector2 = rect.position + arrow[1] / image.get_size() * rect.size
			draw_line(a, b, Color("ff665a"), 4)
			var direction = (b - a).normalized()
			draw_line(b, b - direction.rotated(0.5) * 16, Color("ff665a"), 4)
			draw_line(b, b - direction.rotated(-0.5) * 16, Color("ff665a"), 4)

	func _gui_input(event: InputEvent) -> void:
		if event.device == -1: return
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: zoom_at(event.position, 1.2)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: zoom_at(event.position, 1 / 1.2)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if event.double_click: zoom = 1; offset = Vector2.ZERO
				drawing = event.pressed
				start = image_point(event.position)
				previous = event.position
		elif event is InputEventMouseMotion and drawing and touches.is_empty(): _drag(event.position, event.relative)
		elif event is InputEventScreenTouch:
			if event.pressed:
				if touches.is_empty() and not choosing and not arrow_mode:
					var now = Time.get_ticks_msec()
					if now - last_tap < 320 and event.position.distance_to(last_tap_position) < 24 * EditorInterface.get_editor_scale(): zoom = 1; offset = Vector2.ZERO
					last_tap = now
					last_tap_position = event.position
				touches[event.index] = event.position
				start = image_point(event.position)
			else: touches.erase(event.index)
		elif event is InputEventScreenDrag and touches.has(event.index):
			var before: Array = touches.values()
			touches[event.index] = event.position
			var after: Array = touches.values()
			if before.size() == 2 and not choosing and not arrow_mode:
				var distance = Vector2(before[0]).distance_to(before[1])
				if distance > 1: zoom_at((Vector2(after[0]) + Vector2(after[1])) * 0.5, Vector2(after[0]).distance_to(after[1]) / distance)
			else: _drag(event.position, event.relative)
		queue_redraw()
		if not choosing and not arrow_mode: pose_changed.emit({"zoom": zoom, "offset": offset / size.max(Vector2.ONE)})
		accept_event()

	func _drag(point: Vector2, relative: Vector2) -> void:
		if choosing: selection = Rect2(start, image_point(point) - start).abs()
		elif arrow_mode:
			if arrows.is_empty() or not Vector2(arrows[-1][0]).is_equal_approx(start): arrows.append([start, image_point(point)])
			else: arrows[-1][1] = image_point(point)
		else: offset += relative

	func zoom_at(point: Vector2, factor: float) -> void:
		var old = display_rect()
		var anchor = (point - old.position) / old.size if old.size.x > 0 else Vector2.ZERO
		zoom = clampf(zoom * factor, 0.25, 16)
		var updated = display_rect()
		offset += point - (updated.position + anchor * updated.size)
		queue_redraw()

	func set_pose(value: Dictionary) -> void:
		zoom = value["zoom"]
		offset = Vector2(value["offset"]) * size
		queue_redraw()

	func exported(crop: bool) -> Image:
		var result = image.duplicate()
		for arrow in arrows:
			var from: Vector2 = arrow[0]
			var to: Vector2 = arrow[1]
			var direction = (to - from).normalized()
			var head = minf(24, from.distance_to(to) * 0.3)
			for segment in [[from, to], [to, to - direction.rotated(0.5) * head], [to, to - direction.rotated(-0.5) * head]]:
				var length = int(Vector2(segment[0]).distance_to(segment[1]))
				for index in range(mini(length + 1, 20000)):
					var position = Vector2(segment[0]).lerp(segment[1], float(index) / maxi(length, 1))
					for dx in range(-2, 3):
						for dy in range(-2, 3):
							var x = clampi(int(position.x) + dx, 0, result.get_width() - 1)
							var y = clampi(int(position.y) + dy, 0, result.get_height() - 1)
							result.set_pixel(x, y, Color("ff665a"))
		if crop and selection.has_area(): result = result.get_region(Rect2i(selection).intersection(Rect2i(Vector2i.ZERO, result.get_size())))
		return result

func setup(store: RefCounted, conversation: String, files: Array, id: String, compare: String = "") -> void:
	registry = store
	scope = conversation
	ids = files.duplicate()
	if id not in ids: ids.append(id)
	current = ids.find(id)
	borderless = true
	transient = true
	exclusive = true
	unresizable = false
	close_requested.connect(hide)
	visibility_changed.connect(func() -> void:
		if not visible and content != null: _clear_content())
	var background = ColorRect.new()
	background.color = Color("111827")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var column = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var toolbar = HFlowContainer.new()
	column.add_child(toolbar)
	for entry in [["‹", "previous"], ["›", "next"], ["Menționează", "mention"], ["Decupare", "crop"], ["Săgeată", "arrow"], ["Atașează zona", "region"], ["Zoom +", "zoom_in"], ["Zoom −", "zoom_out"], ["Reset", "reset"], ["Față", "front"], ["Lateral", "side"], ["Sus", "top"], ["Wireframe", "wireframe"], ["Grilă", "grid"], ["Lumină", "light"], ["Animație", "animation"], ["×", "close"]]:
		var button = Button.new()
		button.text = entry[0]
		var symbol = {"previous": "Back", "next": "ArrowRight", "mention": "Attach", "crop": "Crop", "arrow": "Annotate", "region": "Attach", "zoom_in": "Search", "zoom_out": "Search", "reset": "Reset", "front": "Preview3D", "side": "Preview3D", "top": "Preview3D", "wireframe": "Wireframe", "grid": "Grid", "light": "Light", "animation": "Animation", "close": "Close"}.get(entry[1], "More")
		var pixels = Image.new()
		if pixels.load_svg_from_string(str(Icons.DATA.get(symbol, Icons.DATA["More"])).replace("currentColor", "#dce2f2"), EditorInterface.get_editor_scale()) == OK: button.icon = ImageTexture.create_from_image(pixels)
		button.add_theme_constant_override("icon_max_width", int(16 * EditorInterface.get_editor_scale()))
		button.pressed.connect(func() -> void: _command(entry[1]))
		toolbar.add_child(button)
		commands[entry[1]] = button
		button.add_theme_font_size_override("font_size", int(12 * EditorInterface.get_editor_scale()))
		button.custom_minimum_size.y = 32 * EditorInterface.get_editor_scale()
	caption = Label.new()
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(caption)
	content = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)
	detail = Label.new()
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(detail)
	_show(id, compare)

func _clear_content() -> void:
	for child in content.get_children(): content.remove_child(child); child.queue_free()
	canvases.clear()
	model_views.clear()

func _show(id: String, compare: String = "") -> void:
	load_result = Common.failure("Preview indisponibil pentru acest fișier.", "preview_unavailable")
	_clear_content()
	var primary = registry.describe(id, scope)
	var kind = primary.get("kind", "file")
	for command in ["crop", "arrow", "region"]: commands[command].visible = kind == "image"
	for command in ["zoom_in", "zoom_out"]: commands[command].visible = kind in ["image", "mesh"]
	for command in ["front", "side", "top", "wireframe", "grid", "light", "animation"]: commands[command].visible = kind == "mesh"
	for selected in [id, compare] if not compare.is_empty() else [id]:
		var item = registry.describe(selected, scope)
		if item.is_empty(): continue
		caption.text = str(item["name"]) + (" · comparație" if not compare.is_empty() else "")
		detail.text = str(item["source"]) + " · " + String.humanize_size(int(item["bytes"]))
		if item["kind"] == "image":
			var image = Image.load_from_file(item["path"])
			if image == null: continue
			var canvas = ImageCanvas.new()
			canvas.setup(image)
			content.add_child(canvas)
			canvases.append(canvas)
			load_result = {"ok": true, "result": {"kind": "image"}}
			canvas.pose_changed.connect(func(pose: Dictionary) -> void:
				for other in canvases:
					if other != canvas: other.set_pose(pose))
		elif item["kind"] == "mesh":
			var view = ModelPreview.new()
			content.add_child(view)
			var loaded = view.load_file(item["path"])
			load_result = loaded
			if loaded.get("ok", false):
				model_views.append(view)
				detail.text = "Meshuri: %s · Triunghiuri: %s · Materiale: %s" % [loaded["result"]["meshes"], loaded["result"]["triangles"], loaded["result"]["materials"]]
				view.pose_changed.connect(func(pose: Dictionary) -> void:
					for other in model_views:
						if other != view: other.set_pose(pose))
			else:
				var error = Label.new()
				error.text = loaded.get("error", "Preview indisponibil")
				error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				content.add_child(error)
		else:
			var text = CodeEdit.new()
			text.editable = false
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.size_flags_vertical = Control.SIZE_EXPAND_FILL
			text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			text.text = FileAccess.get_file_as_string(item["path"]).left(32000) if item["kind"] == "text" else "Preview indisponibil pentru acest format."
			content.add_child(text)

func _command(command: String) -> void:
	for model in model_views: model.command(command)
	match command:
		"close": hide()
		"previous", "next":
			current = posmod(current + (-1 if command == "previous" else 1), ids.size())
			_show(str(ids[current]))
		"mention": hide(); action.emit("file_mention", {"id": ids[current]})
		"crop", "arrow":
			for canvas in canvases:
				canvas.choosing = command == "crop" and not canvas.choosing
				canvas.arrow_mode = command == "arrow" and not canvas.arrow_mode
		"region":
			if not canvases.is_empty(): action.emit("file_region", {"id": ids[current], "image": canvases[0].exported(true), "region": [canvases[0].selection.position.x, canvases[0].selection.position.y, canvases[0].selection.size.x, canvases[0].selection.size.y]})
		"reset":
			for canvas in canvases:
				canvas.zoom = 1; canvas.offset = Vector2.ZERO; canvas.selection = Rect2(); canvas.arrows.clear(); canvas.queue_redraw()
		"zoom_in", "zoom_out":
			for canvas in canvases: canvas.zoom_at(canvas.size * 0.5, 1.25 if command == "zoom_in" else 0.8)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_BACK]: hide(); set_input_as_handled()
