@tool
extends SubViewportContainer
## One native renderer for interactive and offscreen inspection.
static var Common: GDScript
signal pose_changed(pose: Dictionary)
var viewport: SubViewport
var world: Node3D
var pivot: Node3D
var camera: Camera3D
var environment: Environment
var information: Dictionary = {}
var yaw = 0.7
var pitch = 0.35
var distance = 3.0
var radius = 1.0
var target = Vector3.ZERO
var touches = {}
var dragging = false
var last_magnify_msec = -1000
var players: Array = []
var active_animation = -1
var grid: MeshInstance3D
var input_surface: Control

func _ready() -> void:
	stretch = false
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_target = true
	viewport = SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	stretch = true
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	world.add_child(sun)
	var holder = WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("182030")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b2bdd0")
	environment.ambient_light_energy = 0.7
	holder.environment = environment
	world.add_child(holder)
	# Keep navigation in the viewer's GUI, above the rendered SubViewport.
	# Embedded editor windows must not send these gestures into the 3D scene.
	viewport.gui_disable_input = true
	input_surface = Control.new()
	input_surface.name = "ModelNavigation"
	input_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	input_surface.focus_mode = Control.FOCUS_ALL
	input_surface.mouse_default_cursor_shape = Control.CURSOR_DRAG
	input_surface.tooltip_text = "Trage pentru rotire · două degete pentru zoom și deplasare · săgeți pentru rotire · Home pentru reset"
	add_child(input_surface)
	input_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_surface.gui_input.connect(_navigation_input)
	var directions = HBoxContainer.new()
	input_surface.add_child(directions)
	directions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	var scale = EditorInterface.get_editor_scale()
	directions.offset_left = -152 * scale
	directions.offset_top = -40 * scale
	directions.offset_right = -8 * scale
	directions.offset_bottom = -8 * scale
	directions.add_theme_constant_override("separation", int(4 * scale))
	for entry in [["←", "stânga", Vector2(-24, 0)], ["→", "dreapta", Vector2(24, 0)], ["↑", "sus", Vector2(0, -24)], ["↓", "jos", Vector2(0, 24)]]:
		var control = Button.new()
		control.name = "Orbit_" + str(entry[1])
		control.text = str(entry[0])
		control.tooltip_text = "Rotește " + str(entry[1])
		control.custom_minimum_size = Vector2(32, 32) * scale
		control.add_theme_font_size_override("font_size", int(16 * scale))
		for state in ["normal", "hover", "pressed"]:
			var compact = StyleBoxFlat.new()
			compact.bg_color = Color("252939") if state == "normal" else Color("393450" if state == "hover" else "59458c")
			compact.set_corner_radius_all(int(6 * scale))
			compact.set_content_margin_all(4 * scale)
			control.add_theme_stylebox_override(state, compact)
		control.pressed.connect(func() -> void:
			_orbit(entry[2] * scale)
			_update_camera()
			pose_changed.emit(pose()))
		directions.add_child(control)
	get_window().focus_exited.connect(_release_navigation)
	visibility_changed.connect(func() -> void:
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
		if not is_visible_in_tree():
			_release_navigation()
			for player in players:
				if is_instance_valid(player): player.pause())

func load_file(path: String) -> Dictionary:
	if path.get_extension().to_lower() not in ["glb", "gltf"]: return Common.failure("Preview 3D disponibil pentru GLB/glTF.")
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	if document.append_from_file(path, state) != OK: return Common.failure("Modelul nu poate fi încărcat de Godot.")
	if state.get_nodes().size() > 5000: return Common.failure("Model prea complex pentru preview mobil.", "preview_too_complex")
	var scene = document.generate_scene(state)
	if scene == null: return Common.failure("Modelul nu conține o scenă validă.")
	var queue = [scene]
	var bounds = AABB()
	var meshes = 0
	var triangles = 0
	var nodes = 0
	var materials = {}
	var textures = {}
	var texture_bytes = 0
	var animation_names = []
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		nodes += 1
		if nodes > 5000:
			players.clear()
			scene.free()
			return Common.failure("Model prea complex pentru preview mobil.")
		if node is ImporterMeshInstance3D:
			var converted = MeshInstance3D.new()
			converted.name = node.name
			converted.transform = node.transform
			converted.skin = node.skin
			converted.skeleton = node.skeleton_path
			converted.mesh = node.mesh.get_mesh() if node.mesh != null else null
			node.replace_by(converted)
			node.free()
			node = converted
		if node.get_script() != null: node.set_script(null)
		if node is AnimationPlayer:
			node.stop()
			players.append(node)
			animation_names.append_array(Array(node.get_animation_list()))
		if node is MeshInstance3D and node.mesh != null:
			var transform = Transform3D.IDENTITY
			var walk: Node = node
			while walk is Node3D:
				transform = walk.transform * transform
				if walk == scene: break
				walk = walk.get_parent()
			var box: AABB = transform * node.get_aabb()
			bounds = box if meshes == 0 else bounds.merge(box)
			meshes += 1
			for index in range(node.mesh.get_surface_count()):
				if node.mesh.surface_get_primitive_type(index) == Mesh.PRIMITIVE_TRIANGLES: triangles += (node.mesh.surface_get_array_index_len(index) if node.mesh.surface_get_array_index_len(index) > 0 else node.mesh.surface_get_array_len(index)) / 3
				var material = node.get_active_material(index)
				if material != null: materials[material.get_instance_id()] = true
				if material is BaseMaterial3D:
					for slot in range(BaseMaterial3D.TEXTURE_MAX):
						var texture = material.get_texture(slot)
						if texture != null and not textures.has(texture.get_instance_id()):
							textures[texture.get_instance_id()] = [texture.get_width(), texture.get_height()]
							texture_bytes += texture.get_width() * texture.get_height() * 4
		if triangles > 1000000 or texture_bytes > 256 * 1024 * 1024:
			scene.free()
			players.clear()
			return Common.failure("Model prea complex pentru bugetul de preview mobil.", "preview_too_complex")
		queue.append_array(node.get_children())
	if meshes == 0:
		players.clear()
		scene.free()
		return Common.failure("Model fără geometrie vizibilă.")
	if pivot != null: world.remove_child(pivot); pivot.queue_free()
	pivot = Node3D.new()
	world.add_child(pivot)
	pivot.add_child(scene)
	pivot.position = -bounds.get_center()
	radius = maxf(bounds.size.length() * 0.5, 0.01)
	distance = radius * 3
	camera.near = maxf(radius / 1000, 0.001)
	camera.far = maxf(radius * 100, 100)
	information = {"meshes": meshes, "triangles": triangles, "materials": materials.size(), "nodes": nodes, "bounds": {"center": Common.json_safe(bounds.get_center()), "size": Common.json_safe(bounds.size)}, "textures": textures.size(), "texture_dimensions": textures.values(), "animations": animation_names}
	_make_grid()
	_update_camera()
	return Common.success(information)

func _make_grid() -> void:
	if grid != null: world.remove_child(grid); grid.queue_free()
	grid = MeshInstance3D.new()
	var mesh = ImmediateMesh.new()
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("38475b")
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in range(-5, 6):
		mesh.surface_add_vertex(Vector3(index * radius / 2, -radius, -2.5 * radius))
		mesh.surface_add_vertex(Vector3(index * radius / 2, -radius, 2.5 * radius))
		mesh.surface_add_vertex(Vector3(-2.5 * radius, -radius, index * radius / 2))
		mesh.surface_add_vertex(Vector3(2.5 * radius, -radius, index * radius / 2))
	mesh.surface_end()
	grid.mesh = mesh
	world.add_child(grid)

func pose() -> Dictionary: return {"yaw": yaw, "pitch": pitch, "distance_ratio": distance / radius, "target": target / radius}

func set_pose(value: Dictionary) -> void:
	yaw = float(value.get("yaw", yaw))
	pitch = float(value.get("pitch", pitch))
	distance = float(value.get("distance_ratio", 3)) * radius
	target = value.get("target", Vector3.ZERO) * radius
	_update_camera()

func preset(name: String) -> void:
	yaw = 0 if name in ["front", "top"] else (PI / 2 if name == "side" else 0.7)
	pitch = 1.55 if name == "top" else (0.0 if name in ["front", "side"] else 0.35)
	distance = radius * 3
	target = Vector3.ZERO
	_update_camera()
	pose_changed.emit(pose())

func command(name: String) -> void:
	match name:
		"zoom_in", "zoom_out":
			_zoom(0.8 if name == "zoom_in" else 1.25)
			_update_camera()
			pose_changed.emit(pose())
		"wireframe": viewport.debug_draw = Viewport.DEBUG_DRAW_DISABLED if viewport.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME else Viewport.DEBUG_DRAW_WIREFRAME
		"grid": grid.visible = not grid.visible
		"light": environment.ambient_light_energy = 1.2 if environment.ambient_light_energy < 1 else 0.7
		"animation":
			if players.is_empty(): return
			var player: AnimationPlayer = players[0]
			var available = player.get_animation_list()
			if available.is_empty(): return
			active_animation = posmod(active_animation + 1, available.size())
			player.play(available[active_animation])
		_: preset(name)

func _update_camera() -> void:
	if camera == null: return
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)

func _release_navigation() -> void:
	touches.clear()
	dragging = false
	last_magnify_msec = -1000

func _zoom(factor: float) -> void:
	if not is_finite(factor) or factor <= 0: return
	distance = clampf(distance * factor, radius * 0.2, radius * 30)

func _navigation_input(event: InputEvent) -> void:
	if event.device == -1: return
	if event is InputEventMagnifyGesture:
		if not is_finite(event.factor) or event.factor <= 0: return
		_zoom(1.0 / event.factor)
		last_magnify_msec = Time.get_ticks_msec()
	elif event is InputEventPanGesture:
		if touches.is_empty(): target += (-camera.global_basis.x * event.delta.x + camera.global_basis.y * event.delta.y) * radius / 30.0
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if dragging: input_surface.grab_focus()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: distance *= 0.85 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.15
		else: return
	elif event is InputEventMouseMotion:
		if not dragging or not touches.is_empty(): return
		_orbit(event.relative)
	elif event is InputEventScreenTouch:
		if event.pressed:
			dragging = false
			touches[event.index] = event.position
			input_surface.grab_focus()
		else: touches.erase(event.index)
	elif event is InputEventScreenDrag and touches.has(event.index):
		var previous: Array = touches.values()
		touches[event.index] = event.position
		var after: Array = touches.values()
		if after.size() == 2:
			var old = Vector2(previous[0]).distance_to(previous[1])
			var now = Vector2(after[0]).distance_to(after[1])
			if now > 1 and Time.get_ticks_msec() - last_magnify_msec > 100: _zoom(old / now)
			var movement = ((Vector2(after[0]) + Vector2(after[1])) - (Vector2(previous[0]) + Vector2(previous[1]))) * 0.5
			target += (-camera.global_basis.x * movement.x + camera.global_basis.y * movement.y) * radius / (300 * EditorInterface.get_editor_scale())
		elif after.size() == 1: _orbit(event.relative)
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT: _orbit(Vector2(-12, 0))
			KEY_RIGHT: _orbit(Vector2(12, 0))
			KEY_UP: _orbit(Vector2(0, -12))
			KEY_DOWN: _orbit(Vector2(0, 12))
			KEY_HOME: preset("reset")
			KEY_PLUS, KEY_EQUAL, KEY_KP_ADD: _zoom(0.8)
			KEY_MINUS, KEY_KP_SUBTRACT: _zoom(1.25)
			_: return
	else: return
	distance = clampf(distance, radius * 0.2, radius * 30)
	_update_camera()
	pose_changed.emit(pose())
	input_surface.accept_event()

func _orbit(relative: Vector2) -> void:
	var sensitivity = 0.008 / EditorInterface.get_editor_scale()
	yaw -= relative.x * sensitivity
	pitch = clampf(pitch + relative.y * sensitivity, -1.55, 1.55)

func capture() -> Image:
	if not is_visible_in_tree():
		stretch = false
		viewport.size = Vector2i(512, 512)
	await get_tree().process_frame
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Editor low-processor mode may not draw a hidden viewport without a request.
	RenderingServer.force_draw(false)
	var result = viewport.get_texture().get_image()
	if is_visible_in_tree(): viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	else: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if result != null and not result.is_empty() and result.get_size() != Vector2i(512, 512): result.resize(512, 512)
	return result
