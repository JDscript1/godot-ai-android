@tool
extends RefCounted
## Native asset preparation. Original GLB/glTF is always preserved.
static var Common: GDScript

static func _load(path: String) -> Dictionary:
	path = Common.project_path(path)
	if path.is_empty() or path.get_extension().to_lower() not in ["glb", "gltf"]: return Common.failure("Este necesar un GLB/glTF din proiect.", "invalid_asset")
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > Common.MAX_ASSET_BYTES: return Common.failure("Asset inexistent sau mai mare de 100 MB.", "invalid_asset")
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	if document.append_from_file(path, state) != OK or state.get_nodes().size() > 5000: return Common.failure("Assetul nu poate fi importat în bugetul mobil.", "invalid_asset")
	var scene = document.generate_scene(state)
	if scene == null: return Common.failure("Asset fără scenă.", "invalid_asset")
	return {"ok": true, "scene": scene, "source_sha256": FileAccess.get_sha256(path)}

static func inspect_scene(scene: Node, triangle_budget: int = 100000) -> Dictionary:
	var queue = [scene]
	var bounds = AABB()
	var meshes = 0
	var triangles = 0
	var surfaces = 0
	var vertices = 0
	var lods = 0
	var collisions = 0
	var nodes = 0
	var materials = {}
	var textures = {}
	var issues = []
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		nodes += 1
		if nodes > 5000: return Common.failure("Prea multe noduri.", "asset_budget")
		if node.get_script() != null: node.set_script(null)
		if node is CollisionShape3D and node.shape != null: collisions += 1
		var mesh: Mesh = null
		if node is ImporterMeshInstance3D and node.mesh != null:
			for surface in range(node.mesh.get_surface_count()): lods += node.mesh.get_surface_lod_count(surface)
			mesh = node.mesh.get_mesh()
		elif node is MeshInstance3D: mesh = node.mesh
		if mesh != null:
			var transform = Transform3D.IDENTITY
			var walk = node
			while walk is Node3D:
				transform = walk.transform * transform
				if walk == scene: break
				walk = walk.get_parent()
			var box: AABB = transform * mesh.get_aabb()
			if not box.position.is_finite() or not box.size.is_finite(): return Common.failure("Limite geometrice nefinite.", "invalid_geometry")
			bounds = box if meshes == 0 else bounds.merge(box)
			meshes += 1
			for index in range(mesh.get_surface_count()):
				surfaces += 1
				vertices += mesh.surface_get_array_len(index)
				if mesh.surface_get_primitive_type(index) == Mesh.PRIMITIVE_TRIANGLES: triangles += int((mesh.surface_get_array_index_len(index) if mesh.surface_get_array_index_len(index) > 0 else mesh.surface_get_array_len(index)) / 3)
				var material = mesh.surface_get_material(index)
				if material == null:
					if "missing_material" not in issues: issues.append("missing_material")
				else: materials[material.get_instance_id()] = true
				if material is BaseMaterial3D:
					for slot in range(BaseMaterial3D.TEXTURE_MAX):
						var texture = material.get_texture(slot)
						if texture != null: textures[texture.get_instance_id()] = texture.get_width() * texture.get_height() * 4
			if triangles > 1000000 or vertices > 3000000: return Common.failure("Geometrie prea mare pentru prelucrare mobilă.", "asset_budget")
		queue.append_array(node.get_children())
	if meshes == 0 or triangles == 0: issues.append("empty_mesh")
	if triangles > triangle_budget: issues.append("triangle_budget_exceeded")
	var estimated_texture_bytes = 0
	for value in textures.values(): estimated_texture_bytes += int(value)
	if estimated_texture_bytes > 128 * 1024 * 1024: issues.append("texture_budget_exceeded")
	return Common.success({"meshes": meshes, "triangles": triangles, "vertices": vertices, "surfaces": surfaces, "materials": materials.size(), "textures": textures.size(), "texture_rgba_estimate_bytes": estimated_texture_bytes, "lod_levels": lods, "collision_shapes": collisions, "bounds": {"position": [bounds.position.x, bounds.position.y, bounds.position.z], "size": [bounds.size.x, bounds.size.y, bounds.size.z]}, "issues": issues, "ready_for_use": issues.is_empty(), "triangle_budget": triangle_budget, "scope": "Static geometry/material budgets; style, animation quality and gameplay suitability require separate checks."})

static func audit(path: String, budget: int = 100000) -> Dictionary:
	var loaded = _load(path)
	if not loaded.get("ok", false): return loaded
	var result = inspect_scene(loaded["scene"], clampi(budget, 1, 1000000))
	loaded["scene"].free()
	if result.get("ok", false): result["result"].merge({"path": path, "sha256": loaded["source_sha256"]})
	return result

static func prepare(args: Dictionary) -> Dictionary:
	var path = Common.project_path(str(args.get("path", "")))
	var destination = Common.project_path(str(args.get("destination", "")))
	var height = float(args.get("height_m", 0.0))
	var collision = str(args.get("collision", "none"))
	if destination.is_empty() or destination.get_extension() not in ["tscn", "scn"] or FileAccess.file_exists(destination) or height < 0 or not is_finite(height) or collision not in ["none", "convex", "trimesh"]: return Common.failure("Destinație nouă, înălțime sau coliziune invalidă. Fișierele existente sunt păstrate.", "invalid_asset_destination")
	var loaded = _load(path)
	if not loaded.get("ok", false): return loaded
	var scene: Node = loaded["scene"]
	var inspected = inspect_scene(scene, int(args.get("triangle_budget", 100000)))
	if not inspected.get("ok", false) or "empty_mesh" in inspected.get("result", {}).get("issues", []):
		scene.free()
		return inspected if not inspected.get("ok", false) else Common.failure("Asset fără geometrie.", "empty_mesh")
	if collision != "none" and int(inspected["result"]["triangles"]) > 100000:
		scene.free()
		return Common.failure("Simplifică mesh-ul înaintea construirii coliziunilor pentru peste 100.000 triunghiuri.", "collision_budget")
	var root = Node3D.new()
	root.name = destination.get_file().get_basename().validate_node_name()
	root.add_child(scene)
	var box: Dictionary = inspected["result"]["bounds"]
	var size = Vector3(box["size"][0], box["size"][1], box["size"][2])
	var position = Vector3(box["position"][0], box["position"][1], box["position"][2])
	if height > 0 and size.y <= 0.00001:
		root.free()
		return Common.failure("Mesh-ul nu are înălțime măsurabilă.", "invalid_geometry")
	var factor = height / size.y if height > 0 else 1.0
	var holder = Node3D.new()
	holder.name = "Asset"
	root.remove_child(scene)
	root.add_child(holder)
	holder.add_child(scene)
	holder.scale = Vector3.ONE * factor
	if args.get("ground_pivot", true): holder.position = Vector3(-(position.x + size.x * 0.5), -position.y, -(position.z + size.z * 0.5)) * factor
	var queue = [scene]
	var generated_lods = 0
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node is ImporterMeshInstance3D:
			var converted = MeshInstance3D.new()
			converted.name = node.name
			converted.transform = node.transform
			converted.skin = node.skin
			converted.skeleton = node.skeleton_path
			if node.mesh != null:
				if args.get("generate_lods", true): node.mesh.generate_lods(25.0, 60.0, [])
				for surface in range(node.mesh.get_surface_count()): generated_lods += node.mesh.get_surface_lod_count(surface)
				converted.mesh = node.mesh.get_mesh()
			node.replace_by(converted)
			node.free()
			node = converted
		if node.get_script() != null: node.set_script(null)
		if node is MeshInstance3D and node.mesh != null:
			if collision == "convex": node.create_convex_collision(true, true)
			elif collision == "trimesh": node.create_trimesh_collision()
		queue.append_array(node.get_children())
	queue = [holder]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		node.owner = root
		queue.append_array(node.get_children())
	var prepared = inspect_scene(root, int(args.get("triangle_budget", 100000)))
	var packed = PackedScene.new()
	var error = packed.pack(root)
	if error == OK: error = DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if error == OK: error = ResourceSaver.save(packed, destination, ResourceSaver.FLAG_BUNDLE_RESOURCES)
	root.free()
	if error != OK: return Common.failure("Prefab-ul nu a putut fi salvat.", "asset_save_failed")
	return Common.success({"path": destination, "source": path, "source_sha256": loaded["source_sha256"], "sha256": FileAccess.get_sha256(destination), "generated_lod_levels": generated_lods, "collision": collision, "scale_factor": factor, "audit": prepared.get("result", {}), "original_preserved": FileAccess.get_sha256(path) == loaded["source_sha256"]})
