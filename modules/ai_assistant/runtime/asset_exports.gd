@tool
extends RefCounted
## Export keeps the original GLB immutable. Native geometry exports need no companion.
static var Common: GDScript
var assets: RefCounted
const LOCAL = ["glb", "gltf", "obj", "stl", "ply"]
const MESHY = ["fbx", "usdz", "blend", "3mf"]
const TRIPO = ["fbx", "usdz", "3mf"]

func _init(generator: RefCounted = null) -> void:
	assets = generator

static func formats(provider: String) -> Array:
	var result = LOCAL.duplicate()
	result.append_array(MESHY if provider == "meshy" else (TRIPO if provider == "tripo" else []))
	return result

static func note(format: String) -> String:
	if format in ["obj", "stl", "ply"]: return "Geometrie statică · fără materiale, rig sau animații"
	if format == "gltf": return "Pachet ZIP · glTF, buffere și texturi"
	if format == "glb": return "Fișierul original · preview și import Godot"
	return "Conversie la furnizor · poate consuma credite"

func export_job(job: Dictionary, profile: Dictionary, format: String, cancel: Dictionary, task_id: String = "") -> Dictionary:
	format = format.to_lower()
	if job.get("kind") != "mesh" or job.get("status") != "completed": return Common.failure("Selectează un model 3D finalizat.")
	if format not in formats(str(job.get("provider", ""))): return Common.failure("Format indisponibil pentru acest furnizor.", "unsupported_format")
	var validation = assets.validate_artifact(str(job.get("file", "")), "mesh")
	if not validation.get("ok", false): return validation
	if cancel.get("cancelled", false): return Common.failure("Export oprit.", "cancelled")
	if format == "glb": return Common.success({"file": str(job["file"]), "format": "glb", "status": "completed"})
	if format in LOCAL:
		if not job.has("exports"): job["exports"] = {}
		var previous: Dictionary = job["exports"].get(format, {})
		var fingerprint = FileAccess.get_sha256(str(job["file"]))
		if previous.get("source_sha256") == fingerprint and FileAccess.file_exists(str(previous.get("file", ""))): return Common.success(previous.duplicate(true))
		var result = await native_export(str(job["file"]), format, assets.cache_directory.path_join("exports"), cancel)
		if result.get("ok", false):
			result["result"]["source_sha256"] = fingerprint
			job["exports"][format] = result["result"].duplicate(true)
			assets._save()
		return result
	if str(profile.get("id", "")) != str(job.get("profile_id", "")) or profile.get("kind") != job.get("provider"): return Common.failure("Profilul original este necesar pentru conversie.")
	if not task_id.is_empty():
		var pattern = RegEx.new()
		pattern.compile("^[A-Za-z0-9_-]{1,160}$")
		var previous: Dictionary = job.get("exports", {}).get(format, {})
		if pattern.search(task_id) == null or previous.get("status") != "unknown": return Common.failure("ID de recuperare invalid sau conversie fără răspuns pierdut.")
		previous.merge({"external_id": task_id, "status": "processing"}, true)
		assets._save()
	return await _cloud(job, profile, format, cancel)

func native_export(source: String, format: String, directory: String, cancel: Dictionary = {}) -> Dictionary:
	if format not in ["obj", "stl", "ply", "gltf"]: return Common.failure("Format nativ indisponibil.")
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	if document.append_from_file(source, state) != OK: return Common.failure("Modelul GLB nu poate fi încărcat.")
	var scene = document.generate_scene(state)
	if scene == null: return Common.failure("Modelul nu conține o scenă exportabilă.")
	var meshes = []
	var stack = [{"node": scene, "transform": Transform3D.IDENTITY}]
	var visited = 0
	while not stack.is_empty():
		var entry: Dictionary = stack.pop_back()
		var node: Node = entry["node"]
		visited += 1
		if visited > 5000:
			scene.free()
			return Common.failure("Scenă prea complexă pentru export rapid.")
		var transform: Transform3D = entry["transform"]
		if node is Node3D: transform = transform * node.transform
		if node is ImporterMeshInstance3D:
			var converted = MeshInstance3D.new()
			converted.name = node.name
			converted.transform = node.transform
			converted.skin = node.skin
			converted.skeleton = node.skeleton_path
			converted.mesh = node.mesh.get_mesh() if node.mesh != null else null
			node.replace_by(converted)
			if node == scene: scene = converted
			node.free()
			node = converted
		if node is MeshInstance3D and node.mesh != null: meshes.append({"mesh": node.mesh, "transform": transform})
		for child in node.get_children(): stack.append({"node": child, "transform": transform})
	var staging = directory.path_join(Common.uid())
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		scene.free()
		return Common.failure("Nu pot crea destinația exportului.")
	var result: Dictionary
	if format == "gltf":
		var output_state = GLTFState.new()
		var error = document.append_from_scene(scene, output_state)
		if error == OK: error = document.write_to_filesystem(output_state, staging.path_join("model.gltf"))
		result = _package(staging, staging + ".zip") if error == OK else Common.failure("Exportul glTF a eșuat: " + error_string(error))
	else:
		result = await _geometry(meshes, format, staging.path_join("model." + format), cancel)
	scene.free()
	if result.get("ok", false): result["result"].merge({"format": format, "status": "completed", "note": note(format)}, true)
	return result

func _geometry(meshes: Array, format: String, path: String, cancel: Dictionary) -> Dictionary:
	var triangles = []
	for entry in meshes:
		var mesh: Mesh = entry["mesh"]
		var transform: Transform3D = entry["transform"]
		for surface in range(mesh.get_surface_count()):
			if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count = indices.size() if not indices.is_empty() else vertices.size()
			for offset in range(0, count - 2, 3):
				if triangles.size() % 4096 == 0:
					if cancel.get("cancelled", false): return Common.failure("Export oprit.", "cancelled")
					await assets.owner.get_tree().process_frame
				if triangles.size() >= 1000000: return Common.failure("Export limitat la un milion de triunghiuri.")
				var triangle = PackedVector3Array()
				var order = [0, 1, 2] if transform.basis.determinant() < 0 else [0, 2, 1]
				for step in order:
					var index = indices[offset + step] if not indices.is_empty() else offset + step
					if index < 0 or index >= vertices.size(): return Common.failure("Indici de geometrie invalizi.")
					var point = transform * vertices[index]
					if not point.is_finite(): return Common.failure("Coordonate de geometrie invalide.")
					triangle.append(point)
				triangles.append(triangle)
	if triangles.is_empty(): return Common.failure("Modelul nu conține triunghiuri exportabile.")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return Common.failure("Nu pot scrie exportul.")
	if format == "stl":
		var header = PackedByteArray()
		header.resize(80)
		file.store_buffer(header)
		file.store_32(triangles.size())
	elif format == "ply":
		file.store_string("ply\nformat ascii 1.0\ncomment Godot AI geometry export\nelement vertex %s\nproperty float x\nproperty float y\nproperty float z\nelement face %s\nproperty list uchar int vertex_indices\nend_header\n" % [triangles.size() * 3, triangles.size()])
	else: file.store_string("# Godot AI static geometry\n")
	for triangle_index in range(triangles.size()):
		if triangle_index % 4096 == 0:
			if cancel.get("cancelled", false):
				file.close()
				DirAccess.remove_absolute(path)
				return Common.failure("Export oprit.", "cancelled")
			await assets.owner.get_tree().process_frame
		var triangle: PackedVector3Array = triangles[triangle_index]
		if file.get_position() > Common.MAX_ASSET_BYTES:
			file.close()
			DirAccess.remove_absolute(path)
			return Common.failure("Exportul depășește limita de dimensiune.")
		if format == "stl":
			var normal: Vector3 = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0]).normalized()
			for point in [normal, triangle[0], triangle[1], triangle[2]]:
				file.store_float(point.x)
				file.store_float(point.y)
				file.store_float(point.z)
			file.store_16(0)
		else:
			for point in triangle: file.store_string(("v " if format == "obj" else "") + "%.9f %.9f %.9f\n" % [point.x, point.y, point.z])
	if format != "stl":
		for index in range(triangles.size()):
			var start = index * 3 + (1 if format == "obj" else 0)
			file.store_string(("f " if format == "obj" else "3 ") + "%s %s %s\n" % [start, start + 1, start + 2])
	var error = file.get_error()
	var length = file.get_position()
	file.close()
	if error != OK or length > Common.MAX_ASSET_BYTES:
		DirAccess.remove_absolute(path)
		return Common.failure("Export prea mare sau scriere eșuată.")
	return Common.success({"file": path, "triangles": triangles.size()})

func _package(directory: String, destination: String) -> Dictionary:
	var archive = ZIPPacker.new()
	if archive.open(destination) != OK: return Common.failure("Nu pot crea pachetul glTF.")
	var pending = [directory]
	var total_bytes = 0
	while not pending.is_empty():
		var current = str(pending.pop_back())
		for name in DirAccess.get_directories_at(current): pending.append(current.path_join(name))
		for name in DirAccess.get_files_at(current):
			var path = current.path_join(name)
			var source = FileAccess.open(path, FileAccess.READ)
			if source == null:
				archive.close()
				return Common.failure("Dependență glTF indisponibilă.")
			total_bytes += source.get_length()
			if total_bytes > Common.MAX_ASSET_BYTES:
				archive.close()
				DirAccess.remove_absolute(destination)
				return Common.failure("Dependențele glTF depășesc limita exportului.")
			var error = archive.start_file(path.trim_prefix(directory + "/"))
			if error == OK: error = archive.write_file(source.get_buffer(source.get_length()))
			if error == OK: error = archive.close_file()
			if error != OK:
				archive.close()
				return Common.failure("Pachetul glTF nu a putut fi scris.")
	if archive.close() != OK: return Common.failure("Pachetul glTF nu a putut fi închis.")
	return Common.success({"file": destination})

func _cloud(job: Dictionary, profile: Dictionary, format: String, cancel: Dictionary) -> Dictionary:
	if not job.has("exports"): job["exports"] = {}
	var record: Dictionary = job["exports"].get(format, {})
	if record.get("status") == "completed" and FileAccess.file_exists(str(record.get("file", ""))): return Common.success(record.duplicate(true))
	var provider = str(job["provider"])
	if record.get("status") == "unknown": return Common.failure("Răspunsul conversiei s-a pierdut. Verifică sarcinile furnizorului și reia cu ID-ul existent; nu retrimit o conversie plătită.", "conversion_unknown")
	if record.is_empty():
		var endpoint = "/openapi/v1/convert" if provider == "meshy" else "/models/convert"
		var body = {"input_task_id": job["external_id"], "target_formats": [format]} if provider == "meshy" else {"input": job["external_id"], "format": format.to_upper()}
		# A lost POST response is ambiguous. Persist before sending; never auto-resubmit it.
		record = {"external_id": "", "status": "unknown", "format": format, "endpoint": endpoint, "file": ""}
		job["exports"][format] = record
		if not assets._save():
			job["exports"].erase(format)
			return Common.failure("Nu pot salva starea conversiei înainte de trimitere.")
		var submitted = await assets._cloud_request(profile, endpoint, body, cancel)
		if not submitted.get("ok", false):
			# Explicit rejection can be retried after fixing credentials/input. Transport loss cannot.
			if int(submitted.get("status", 0)) in range(400, 500) or submitted.get("code") in ["missing_credentials", "generation_failed"]:
				job["exports"].erase(format)
				assets._save()
			return submitted
		var external_id = str(submitted["result"].get("result" if provider == "meshy" else "task_id", ""))
		if external_id.is_empty(): return Common.failure("Furnizorul nu a returnat identificatorul conversiei.")
		record.merge({"external_id": external_id, "status": "processing"}, true)
		assets._save()
	if record.get("status") == "failed": return Common.failure("Conversia a eșuat la furnizor. Verifică sarcina înainte de a crea o nouă conversie.", "conversion_failed")
	var deadline = Time.get_ticks_msec() + 120000
	while not cancel.get("cancelled", false):
		var route = str(record["endpoint"]) + "/" if provider == "meshy" else "/tasks/"
		var response = await assets._cloud_request(profile, route + str(record["external_id"]).uri_encode(), null, cancel)
		if not response.get("ok", false): return response
		var data: Dictionary = response["result"]
		var status = str(data.get("status", "")).to_lower()
		if status in ["failed", "canceled", "cancelled"]:
			record["status"] = "failed"
			assets._save()
			return Common.failure("Conversia a eșuat la furnizor.", "conversion_failed")
		if status in ["success", "succeeded"]:
			var url = str(data.get("model_urls", {}).get(format, "")) if provider == "meshy" else str(data.get("output", {}).get("model_url", ""))
			if not assets.trusted_download(url, provider): return Common.failure("Adresă de export nerecunoscută.")
			var directory = assets.cache_directory.path_join("exports")
			DirAccess.make_dir_recursive_absolute(directory)
			var temporary = directory.path_join(str(job["id"]) + "-" + format + ".part")
			var downloaded = await assets.transport.request(url, HTTPClient.METHOD_GET, [], null, {"cancel": cancel, "allow_http": assets.test_http, "max_bytes": Common.MAX_ASSET_BYTES, "timeout": 120, "save_path": temporary})
			if not downloaded.get("ok", false): return downloaded
			var checked = validate_export(temporary, format)
			if not checked.get("ok", false):
				DirAccess.remove_absolute(temporary)
				return checked
			var destination = directory.path_join(str(job["id"]) + "-" + format + "." + str(checked["result"]["extension"]))
			if DirAccess.rename_absolute(temporary, destination) != OK: return Common.failure("Nu pot păstra exportul.")
			record.merge({"file": destination, "status": "completed", "credits_consumed": data.get("consumed_credits", data.get("credits_consumed", 0))}, true)
			assets._save()
			return Common.success(record.duplicate(true))
		if Time.get_ticks_msec() >= deadline: return Common.success(record.duplicate(true))
		await assets.owner.get_tree().create_timer(1.0).timeout
	return Common.failure("Așteptare oprită. Conversia poate continua la furnizor; Export reia aceeași sarcină.", "cancelled")

static func validate_export(path: String, format: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 8 or file.get_length() > Common.MAX_ASSET_BYTES: return Common.failure("Export lipsă sau prea mare.")
	var bytes = file.get_buffer(mini(256, file.get_length()))
	file.close()
	if bytes.slice(0, 2).get_string_from_ascii() == "PK":
		var archive = ZIPReader.new()
		if archive.open(path) != OK: return Common.failure("Arhivă de export invalidă.")
		var found = false
		for entry in archive.get_files():
			if entry.is_absolute_path() or ".." in entry.replace("\\", "/").split("/"):
				archive.close()
				return Common.failure("Arhivă cu o cale invalidă.")
			if entry.get_extension().to_lower() == format or (format == "usdz" and entry.get_extension().to_lower() in ["usd", "usda", "usdc"]) or (format == "3mf" and entry.ends_with(".model")): found = true
		archive.close()
		if not found: return Common.failure("Arhiva nu conține formatul cerut.")
		return Common.success({"extension": format if format in ["usdz", "3mf"] else "zip"})
	var text = bytes.get_string_from_ascii()
	if format == "fbx" and (text.begins_with("Kaydara FBX Binary") or text.begins_with("; FBX")): return Common.success({"extension": "fbx"})
	if format == "blend" and text.begins_with("BLENDER"): return Common.success({"extension": "blend"})
	return Common.failure("Rezultatul nu corespunde formatului " + format.to_upper() + ".")
