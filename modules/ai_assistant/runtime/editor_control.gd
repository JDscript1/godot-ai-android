@tool
extends RefCounted
## Editor-window capture/input; never controls other Android applications.
static var Common: GDScript
var owner: Node
var tools: RefCounted
var frames: Dictionary = {}
var held: Array = []
var expires = 0
var injecting = false
var interrupted = false

func _init(node: Node = null, editor_tools: RefCounted = null) -> void:
	owner = node
	tools = editor_tools

static func definitions() -> Array:
	return [Common.tool("editor_capture", "Capture actual Godot editor pixels. target=editor, viewport_2d, viewport_3d or control; control requires a handle from godot_ui_tree. Optional region is [x,y,width,height] in normalized capture coordinates. Returns a fresh frame ID required for coordinate input.", {"target": {"type": "string", "enum": ["editor", "window", "viewport_2d", "viewport_3d", "control"]}, "handle": Common.string_field(), "region": {"type": "array", "minItems": 4, "maxItems": 4, "items": {"type": "number"}}}, []), Common.tool("editor_input", "Operate the Godot editor using a fresh editor_capture frame. action=click,drag,scroll,key,text,touch. x/y and to_x/to_y are normalized within that captured region. key is a Godot keycode; ctrl/shift/alt set modifiers. duration_ms<=1500. Re-observe after actions. This does not inject OS-wide input.", {"frame": Common.string_field(), "action": {"type": "string", "enum": ["click", "drag", "scroll", "key", "text", "touch"]}, "x": {"type": "number", "minimum": 0, "maximum": 1}, "y": {"type": "number", "minimum": 0, "maximum": 1}, "to_x": {"type": "number", "minimum": 0, "maximum": 1}, "to_y": {"type": "number", "minimum": 0, "maximum": 1}, "key": {"type": "integer"}, "text": Common.string_field(), "ctrl": {"type": "boolean"}, "shift": {"type": "boolean"}, "alt": {"type": "boolean"}, "amount": {"type": "integer", "minimum": -5, "maximum": 5}, "duration_ms": {"type": "integer", "minimum": 1, "maximum": 1500}}, ["frame", "action"], "write")]

func capture(args: Dictionary, cancel: Dictionary) -> Dictionary:
	if cancel.get("cancelled", false): return Common.failure("Oprit.", "cancelled")
	var base = EditorInterface.get_base_control()
	var viewport: Viewport = base.get_viewport()
	var control: Control
	var target = str(args.get("target", "editor"))
	if target == "viewport_2d": viewport = EditorInterface.get_editor_viewport_2d()
	elif target == "viewport_3d": viewport = EditorInterface.get_editor_viewport_3d(0)
	elif target == "window":
		var window = tools._resolve(str(args.get("handle", ""))) as Window
		if window == null or not window.visible: return Common.failure("Fereastră indisponibilă.")
		viewport = window
	elif target == "control":
		control = tools._resolve(str(args.get("handle", ""))) as Control
		if control == null or not control.is_visible_in_tree(): return Common.failure("Controlul nu este disponibil.")
		viewport = control.get_viewport()
	if viewport == null: return Common.failure("Viewport indisponibil.")
	await owner.get_tree().process_frame
	RenderingServer.force_draw(false)
	if cancel.get("cancelled", false) or not is_instance_valid(viewport): return Common.failure("Captură oprită.", "cancelled")
	var image = viewport.get_texture().get_image()
	if image == null or image.is_empty(): return Common.failure("Viewport fără imagine capturabilă.")
	var original_size = image.get_size()
	_mask_secrets(viewport, viewport, image)
	var input_viewport = viewport
	var input_rect = Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	if viewport is SubViewport and viewport.get_parent() is SubViewportContainer:
		input_rect = viewport.get_parent().get_global_rect()
		input_viewport = viewport.get_parent().get_viewport()
	var logical_size = viewport.get_visible_rect().size
	var rect = Rect2(Vector2.ZERO, original_size)
	if control != null:
		var visible: Rect2 = control.get_global_rect()
		rect = Rect2(visible.position / logical_size * Vector2(original_size), visible.size / logical_size * Vector2(original_size))
	if args.has("region"):
		var values: Array = args["region"]
		if values.size() != 4 or float(values[0]) < 0 or float(values[1]) < 0 or float(values[2]) <= 0 or float(values[3]) <= 0 or float(values[0]) + float(values[2]) > 1 or float(values[1]) + float(values[3]) > 1: return Common.failure("Regiune de captură invalidă.")
		rect = Rect2(rect.position + Vector2(values[0], values[1]) * rect.size, Vector2(values[2], values[3]) * rect.size)
	rect = rect.intersection(Rect2(Vector2.ZERO, original_size))
	if rect.size.x < 1 or rect.size.y < 1: return Common.failure("Regiune în afara viewportului.")
	image = image.get_region(Rect2i(rect))
	while max(image.get_width(), image.get_height()) > 1536: image.resize(maxi(1, image.get_width() / 2), maxi(1, image.get_height() / 2))
	var id = Common.uid()
	frames.clear()
	frames[id] = {"input_viewport": weakref(input_viewport), "input_rect": input_rect, "layout": _layout(input_viewport), "viewport": weakref(viewport), "size": logical_size, "texture_size": original_size, "rect": rect, "created": Time.get_ticks_msec()}
	var bytes = image.save_png_to_buffer()
	while bytes.size() > 2 * 1024 * 1024 and image.get_width() > 256:
		image.resize(maxi(1, image.get_width() / 2), maxi(1, image.get_height() / 2))
		bytes = image.save_png_to_buffer()
	return {"ok": true, "result": {"frame": id, "target": target, "width": image.get_width(), "height": image.get_height()}, "images": [{"name": "editor-" + target + ".png", "mimeType": "image/png", "data": Marshalls.raw_to_base64(bytes)}]}

func input(args: Dictionary, cancel: Dictionary) -> Dictionary:
	var frame: Dictionary = frames.get(str(args.get("frame", "")), {})
	if frame.is_empty(): return Common.failure("Capturează din nou înainte de input.", "stale_frame")
	var captured: Viewport = frame["viewport"].get_ref()
	var viewport: Viewport = frame["input_viewport"].get_ref()
	if viewport == null or captured == null or captured.get_visible_rect().size != frame["size"] or _layout(viewport) != frame["layout"] or Time.get_ticks_msec() - int(frame["created"]) > 30000: return Common.failure("Fereastra sau captura s-a schimbat. Capturează din nou.", "stale_frame")
	if cancel.get("cancelled", false): return Common.failure("Oprit.", "cancelled")
	frames.clear()
	interrupted = false
	var focus = viewport.gui_get_focus_owner()
	if focus != null and (owner == focus or owner.is_ancestor_of(focus)): return Common.failure("Agentul nu își poate opera propriile setări sau conversația.")
	var action = str(args["action"])
	if action in ["text", "key"] and focus is LineEdit and focus.secret: return Common.failure("Câmp secret; configurare manuală.")
	var rect: Rect2 = frame["rect"]
	var input_rect: Rect2 = frame["input_rect"]
	var point: Vector2 = input_rect.position + (rect.position + Vector2(args.get("x", 0.5), args.get("y", 0.5)) * rect.size) / Vector2(frame["texture_size"]) * input_rect.size
	if action not in ["text", "key"] and owner is Control and owner.is_visible_in_tree() and owner.get_viewport() == viewport and owner.get_global_rect().has_point(point): return Common.failure("Inputul în panoul agentului se face manual.")
	expires = Time.get_ticks_msec() + 2000
	var duration = clampi(int(args.get("duration_ms", 80)), 1, 1500)
	if action == "text":
		if focus is LineEdit and focus.secret: return Common.failure("Câmp secret; configurare manuală.")
		if not (focus is LineEdit or focus is TextEdit) or not focus.editable: return Common.failure("Focalizează un câmp editabil.")
		focus.insert_text_at_caret(str(args.get("text", "")).left(4000))
		return Common.success({"delivered": true, "observe_again": true})
	elif action == "key":
		var key = InputEventKey.new()
		key.keycode = int(args.get("key", 0))
		if key.keycode == 0: return Common.failure("Tastă invalidă.")
		key.ctrl_pressed = args.get("ctrl", false)
		key.shift_pressed = args.get("shift", false)
		key.alt_pressed = args.get("alt", false)
		key.pressed = true
		_hold(viewport, key)
	elif action == "scroll":
		for index in range(absi(int(args.get("amount", 1)))):
			var wheel = InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP if int(args.get("amount", 1)) > 0 else MOUSE_BUTTON_WHEEL_DOWN
			wheel.position = point
			wheel.global_position = point
			wheel.pressed = true
			_hold(viewport, wheel)
			release()
		return Common.success({"delivered": true, "observe_again": true})
	elif action == "touch" or (action == "click" and not owner.plugin.has_method("push_editor_input")):
		var touch = InputEventScreenTouch.new()
		touch.position = point
		touch.pressed = true
		_hold(viewport, touch)
	else:
		if interrupted or cancel.get("cancelled", false) or _layout(viewport) != frame["layout"]: return Common.failure("Input oprit; capturează din nou.", "stale_frame")
		var hover = InputEventMouseMotion.new()
		hover.position = point
		hover.global_position = point
		_push(viewport, hover)
		var press = InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.button_mask = MOUSE_BUTTON_MASK_LEFT
		press.position = point
		press.global_position = point
		press.pressed = true
		_hold(viewport, press)
		if action == "drag":
			var end = input_rect.position + (rect.position + Vector2(args.get("to_x", 0.5), args.get("to_y", 0.5)) * rect.size) / Vector2(frame["texture_size"]) * input_rect.size
			var previous = point
			for step in range(1, 13):
				if cancel.get("cancelled", false) or interrupted: break
				var motion = InputEventMouseMotion.new()
				motion.position = point.lerp(end, float(step) / 12)
				motion.global_position = motion.position
				motion.relative = motion.position - previous
				motion.button_mask = MOUSE_BUTTON_MASK_LEFT
				_push(viewport, motion)
				previous = motion.position
				await owner.get_tree().create_timer(float(duration) / 12000).timeout
			press.position = end
			press.global_position = end
	if action != "drag": await owner.get_tree().create_timer(float(duration) / 1000).timeout
	release()
	return Common.failure("Oprit.", "cancelled") if cancel.get("cancelled", false) or interrupted else Common.success({"delivered": true, "observe_again": true})

func _hold(viewport: Viewport, event: InputEvent) -> void:
	held.append({"viewport": weakref(viewport), "event": event})
	_push(viewport, event)

func release() -> void:
	var active = held.duplicate()
	held.clear()
	for item in active:
		var viewport = item["viewport"].get_ref()
		if viewport == null: continue
		var event: InputEvent = item["event"].duplicate()
		event.pressed = false
		if event is InputEventMouseButton: event.button_mask = 0
		_push(viewport, event)
	held.clear()

func poll() -> void:
	if not held.is_empty() and Time.get_ticks_msec() > expires: release()

func _push(viewport: Viewport, event: InputEvent) -> void:
	injecting = true
	if event is InputEventFromWindow and viewport is Window: event.window_id = viewport.get_window_id()
	if owner.plugin.has_method("push_editor_input"): owner.plugin.push_editor_input(viewport, event)
	else: viewport.push_input(event, true)
	injecting = false

func user_input(event: InputEvent) -> void:
	if injecting: return
	if event is InputEventKey or event is InputEventScreenTouch or event is InputEventMouseButton:
		frames.clear()
		interrupted = true
		if not held.is_empty():
			release()

func _layout(viewport: Viewport) -> int:
	var parts = []
	var queue: Array = [viewport]
	while not queue.is_empty() and parts.size() < 3000:
		var node: Node = queue.pop_back()
		if node == owner: continue
		if node is Control and node.is_visible_in_tree(): parts.append([node.get_instance_id(), node.get_global_rect(), node.text if node is BaseButton else "", node.disabled if node is BaseButton else false])
		elif node is Window: parts.append([node.get_instance_id(), node.visible, node.position, node.size])
		queue.append_array(node.get_children())
	return hash(parts)

func _mask_secrets(node: Node, viewport: Viewport, image: Image) -> void:
	if node is LineEdit and node.secret and node.is_visible_in_tree() and node.get_viewport() == viewport:
		var logical = viewport.get_visible_rect().size
		var rect = node.get_global_rect()
		image.fill_rect(Rect2i(Rect2(rect.position / logical * Vector2(image.get_size()), rect.size / logical * Vector2(image.get_size()))).intersection(Rect2i(Vector2i.ZERO, image.get_size())), Color("141a29"))
	for child in node.get_children(): _mask_secrets(child, viewport, image)
