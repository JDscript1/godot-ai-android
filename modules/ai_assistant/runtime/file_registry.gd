@tool
extends RefCounted
## Revisioned, conversation-scoped file snapshots. Originals are never modified.
static var Common: GDScript
static var Assets: GDScript
var owner: Node
var directory = ""
var entries: Dictionary = {}
var roots: Array = []
var chosen: Array = []
var extra_roots: Array = []
const IMAGE_EXT = ["png", "jpg", "jpeg", "webp"]
const MESH_EXT = ["glb", "gltf"]
const TEXT_EXT = ["txt", "md", "gd", "json", "tscn", "tres", "cfg", "csv", "shader", "gdshader", "py"]
const MAX_FILE = 128 * 1024 * 1024

func _init(node: Node = null) -> void: owner = node

func configure(project_directory: String) -> void:
	directory = project_directory.path_join("files")
	DirAccess.make_dir_recursive_absolute(directory)
	var saved = Common.read_json(directory.path_join("index.json"), {})
	entries = saved.get("entries", {})
	chosen = saved.get("chosen", [])
	extra_roots = saved.get("roots", [])
	roots = [ProjectSettings.globalize_path("res://").trim_suffix("/")]
	if OS.has_feature("android"):
		roots.append_array(["/storage/emulated/0/Pictures/Screenshots", "/storage/emulated/0/Download", "/storage/emulated/0/DCIM/Screenshots"])
	else:
		for path in [OS.get_system_dir(OS.SYSTEM_DIR_PICTURES), OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)]:
			if not path.is_empty() and DirAccess.dir_exists_absolute(path): roots.append(path)

	for path in extra_roots:
		if path not in roots: roots.append(path)

static func definitions() -> Array:
	return [Common.tool("file_catalog", "List files already shared in this conversation, including pinned references. A pin retains metadata; pixels are loaded only when needed.", {"pinned_only": {"type": "boolean"}}, []), Common.tool("storage_search", "Find recent files in accessible project, Screenshots/Pictures and Downloads folders. kind=image/mesh/text/any; query matches filename, path optionally narrows a configured root. Returns at most six preview cards in chat. Never claims access to unavailable folders.", {"query": Common.string_field(), "kind": {"type": "string", "enum": ["image", "mesh", "text", "any"]}, "path": Common.string_field(), "limit": {"type": "integer", "minimum": 1, "maximum": 6}, "after": {"type": "number"}}, []), Common.tool("file_show", "Display existing conversation file IDs as preview cards for the user to identify. Does not send image pixels to the model.", {"ids": {"type": "array", "minItems": 1, "maxItems": 6, "items": {"type": "string"}}}, ["ids"]), Common.tool("file_observe", "Read a conversation file snapshot: image pixels for a vision model, text excerpt or 3D metadata/rendered views. Use the exact ID from storage_search or a user mention.", {"id": Common.string_field()}, ["id"])]

func permit(path: String, folder: bool = false) -> void:
	var normalized = ProjectSettings.globalize_path(path).simplify_path().trim_suffix("/")
	if folder:
		if normalized not in roots: roots.append(normalized)
		if normalized not in extra_roots: extra_roots.append(normalized)
	else:
		if normalized not in chosen: chosen.append(normalized)
	_save()

func allowed(path: String) -> bool:
	var normalized = ProjectSettings.globalize_path(path).simplify_path()
	if normalized in chosen: return true
	for root in roots:
		if normalized != root and not normalized.begins_with(str(root) + "/"): continue
		var relative = normalized.trim_prefix(str(root)).trim_prefix("/")
		var walk = str(root)
		for segment in relative.split("/", false):
			if segment in [".godot", ".git", ".codex", ".ssh", ".godot_ai"]: return false
			var parent = DirAccess.open(walk)
			if parent != null and parent.is_link(segment): return false
			walk = walk.path_join(segment)
		return true
	return false

func register_file(path: String, scope: String) -> Dictionary:
	var source = ProjectSettings.globalize_path(path).simplify_path()
	if scope.is_empty() or not allowed(source): return Common.failure("Fișier în afara surselor autorizate.", "file_access_denied")
	var file = FileAccess.open(source, FileAccess.READ)
	if file == null: return Common.failure("Fișierul nu poate fi citit. Verifică accesul la stocare.", "file_unavailable")
	var size = file.get_length()
	file.close()
	var extension = source.get_extension().to_lower()
	var kind = "image" if extension in IMAGE_EXT else ("mesh" if extension in MESH_EXT else ("text" if extension in TEXT_EXT else "file"))
	if size == 0 or size > MAX_FILE or (kind == "image" and size > 32 * 1024 * 1024) or (kind == "text" and size > 1024 * 1024): return Common.failure("Fișier gol sau prea mare pentru preview.", "file_too_large")
	if extension == "glb":
		var validated = Assets.validate_artifact(source, "mesh")
		if not validated.get("ok", false): return validated
	if extension == "gltf" and size > 8 * 1024 * 1024: return Common.failure("Document glTF prea mare pentru preview.")
	if kind == "image":
		var dimensions = image_dimensions(source)
		if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x * dimensions.y > 24000000 or max(dimensions.x, dimensions.y) > 16384: return Common.failure("Imagine invalidă sau peste bugetul de preview.", "image_too_large")
	var sha = FileAccess.get_sha256(source)
	var bundle = {}
	if extension == "gltf":
		bundle = _gltf_bundle(source)
		if not bundle.get("ok", false): return bundle
		sha = bundle["result"]["sha256"]
	var id = (source + ":" + sha).sha256_text().left(32)
	if entries.has(id):
		if scope not in entries[id]["scopes"]: entries[id]["scopes"].append(scope)
		_save()
		return Common.success(describe(id, scope))
	var snapshot = directory.path_join(sha + "." + extension)
	var needed = int(bundle["result"]["bytes"]) if extension == "gltf" else size
	if _cache_bytes() + needed > 512 * 1024 * 1024: return Common.failure("Cache-ul de preview a ajuns la limita de 512 MB. Versiunile existente sunt păstrate.", "cache_full")
	if extension == "gltf":
		var copied = _gltf_snapshot(source, sha, bundle["result"]["dependencies"])
		if not copied.get("ok", false): return copied
		snapshot = copied["result"]
	elif not FileAccess.file_exists(snapshot) and DirAccess.copy_absolute(source, snapshot) != OK: return Common.failure("Nu pot păstra versiunea fișierului.")
	if extension != "gltf" and FileAccess.get_sha256(snapshot) != sha: return Common.failure("Fișierul s-a schimbat în timpul copierii. Reîncearcă.")
	var item = {"id": id, "name": source.get_file(), "kind": kind, "source": source, "path": snapshot, "sha256": sha, "bytes": size, "modified": FileAccess.get_modified_time(source), "scopes": [scope], "preview": "", "pinned": false}
	if kind == "image":
		var image = Image.load_from_file(snapshot)
		if image == null or image.is_empty() or image.get_width() * image.get_height() > 24000000: return Common.failure("Imagine coruptă sau format nesuportat.")
		item["width"] = image.get_width()
		item["height"] = image.get_height()
		var ratio = minf(1.0, 512.0 / maxf(image.get_width(), image.get_height()))
		if ratio < 1: image.resize(maxi(1, int(image.get_width() * ratio)), maxi(1, int(image.get_height() * ratio)))
		item["preview"] = directory.path_join(sha + "-thumb.png")
		if image.save_png(item["preview"]) != OK: return Common.failure("Nu pot crea miniatura.")
	entries[id] = item
	if _save() != OK:
		entries.erase(id)
		return Common.failure("Nu pot salva registrul fișierelor.")
	return Common.success(describe(id, scope))

func _gltf_bundle(source: String) -> Dictionary:
	var document: Variant = Common.parse_json(FileAccess.get_file_as_string(source))
	if not document is Dictionary: return Common.failure("Document glTF invalid.")
	var dependencies = {}
	var total = FileAccess.get_file_as_bytes(source).size()
	for part in document.get("buffers", []) + document.get("images", []):
		if not part is Dictionary: return Common.failure("Dependență glTF invalidă.")
		var uri = str(part.get("uri", ""))
		if uri.is_empty() or uri.begins_with("data:"): continue
		var decoded = uri.uri_decode()
		if decoded.is_absolute_path() or ":" in decoded or ".." in decoded.split("/") or "\\" in decoded: return Common.failure("Dependență glTF externă nepermisă.")
		var original = source.get_base_dir().path_join(decoded)
		if not allowed(original) or not FileAccess.file_exists(original): return Common.failure("Dependență glTF lipsă sau inaccesibilă: " + decoded)
		var input = FileAccess.open(original, FileAccess.READ)
		if input == null: return Common.failure("Dependență glTF inaccesibilă.")
		total += input.get_length()
		input.close()
		if total > MAX_FILE: return Common.failure("Modelul și dependențele depășesc limita de preview.")
		dependencies[decoded] = FileAccess.get_sha256(original)
	var fingerprint = FileAccess.get_sha256(source)
	var keys = dependencies.keys()
	keys.sort()
	for key in keys: fingerprint += "\n" + str(key) + ":" + str(dependencies[key])
	return Common.success({"sha256": fingerprint.sha256_text(), "dependencies": dependencies, "bytes": total})

func _gltf_snapshot(source: String, sha: String, dependencies: Dictionary) -> Dictionary:
	var target = directory.path_join(sha)
	var path = target.path_join("model.gltf")
	if FileAccess.file_exists(path): return Common.success(path)
	DirAccess.make_dir_recursive_absolute(target)
	for decoded in dependencies:
		var output = target.path_join(str(decoded))
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		if DirAccess.copy_absolute(source.get_base_dir().path_join(str(decoded)), output) != OK or FileAccess.get_sha256(output) != dependencies[decoded]: return Common.failure("Dependența glTF s-a schimbat în timpul copierii. Reîncearcă.")
	if DirAccess.copy_absolute(source, path) != OK: return Common.failure("Nu pot copia documentul glTF.")
	var verified = _gltf_bundle(source)
	if not verified.get("ok", false) or verified["result"]["sha256"] != sha:
		DirAccess.remove_absolute(path)
		return Common.failure("Modelul s-a schimbat în timpul copierii. Reîncearcă.")
	return Common.success(path)

func describe(id: String, scope: String) -> Dictionary:
	if not entries.has(id) or scope not in entries[id].get("scopes", []): return {}
	var item: Dictionary = entries[id].duplicate(true)
	item.erase("scopes")
	item["pinned"] = scope in item.get("pinned_scopes", [])
	item.erase("pinned_scopes")
	item["available"] = FileAccess.file_exists(str(item["path"]))
	item["source_changed"] = not FileAccess.file_exists(str(item["source"])) or FileAccess.get_modified_time(str(item["source"])) != int(item["modified"])
	return item

func image_attachment(id: String, scope: String) -> Dictionary:
	var item = describe(id, scope)
	if item.is_empty() or item.get("kind") != "image" or not item.get("available", false): return {}
	var image = Image.load_from_file(item["path"])
	if image == null: return {}
	while max(image.get_width(), image.get_height()) > 1536: image.resize(maxi(1, image.get_width() / 2), maxi(1, image.get_height() / 2))
	var bytes = image.save_png_to_buffer()
	while bytes.size() > 2 * 1024 * 1024 and image.get_width() > 256:
		image.resize(maxi(1, image.get_width() / 2), maxi(1, image.get_height() / 2))
		bytes = image.save_png_to_buffer()
	return {"name": item["name"], "mimeType": "image/png", "data": Marshalls.raw_to_base64(bytes), "file_id": id} if bytes.size() <= 2 * 1024 * 1024 else {}

func search(args: Dictionary, scope: String, cancel: Dictionary = {}) -> Dictionary:
	var queue = []
	var requested = str(args.get("path", ""))
	if not requested.is_empty():
		if not allowed(requested): return Common.failure("Folderul nu este autorizat.")
		queue.append([ProjectSettings.globalize_path(requested), 0])
	else:
		for root in roots: queue.append([root, 0])
	var found = []
	var seen = {}
	var scanned = 0
	var inaccessible = []
	var kind = str(args.get("kind", "any"))
	while not queue.is_empty() and scanned < 4000:
		if cancel.get("cancelled", false): return Common.failure("Căutare oprită.", "cancelled")
		var next: Array = queue.pop_front()
		var folder = DirAccess.open(str(next[0]))
		if folder == null:
			inaccessible.append(next[0])
			continue
		folder.list_dir_begin()
		var name = folder.get_next()
		while not name.is_empty() and scanned < 4000:
			var path = str(next[0]).path_join(name)
			scanned += 1
			if not name.begins_with(".") and not folder.is_link(name) and allowed(path):
				if folder.current_is_dir():
					if int(next[1]) < 6: queue.append([path, int(next[1]) + 1])
				elif not seen.has(path):
					seen[path] = true
					var extension = name.get_extension().to_lower()
					var match_kind = kind == "any" or (kind == "image" and extension in IMAGE_EXT) or (kind == "mesh" and extension in MESH_EXT) or (kind == "text" and extension in TEXT_EXT)
					if match_kind and (str(args.get("query", "")).is_empty() or str(args["query"]).to_lower() in name.to_lower()) and FileAccess.get_modified_time(path) >= float(args.get("after", 0)): found.append({"path": path, "modified": FileAccess.get_modified_time(path)})
			if scanned % 32 == 0 and is_instance_valid(owner): await owner.get_tree().process_frame
			name = folder.get_next()
		folder.list_dir_end()
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["modified"] > b["modified"] if a["modified"] != b["modified"] else a["path"] < b["path"])
	var cards = []
	for candidate in found.slice(0, clampi(int(args.get("limit", 4)), 1, 6)):
		if cancel.get("cancelled", false): return Common.failure("Căutare oprită.", "cancelled")
		var registered = register_file(str(candidate["path"]), scope)
		if registered.get("ok", false): cards.append(registered["result"])
	return {"ok": true, "result": cards, "files": cards.map(func(item: Dictionary) -> String: return item["id"]), "inaccessible": inaccessible, "scan_limited": scanned >= 4000, "examined": scanned, "candidates": found.size()}

func pin(id: String, scope: String, enabled: bool) -> Error:
	if describe(id, scope).is_empty(): return ERR_UNAUTHORIZED
	var previous: Array = entries[id].get("pinned_scopes", []).duplicate()
	var scopes = previous.duplicate()
	if enabled and scope not in scopes: scopes.append(scope)
	elif not enabled: scopes.erase(scope)
	entries[id]["pinned_scopes"] = scopes
	var error = _save()
	if error != OK: entries[id]["pinned_scopes"] = previous
	return error

func catalog(scope: String, pinned_only: bool = false) -> Array:
	var result = []
	for id in entries:
		var item = describe(str(id), scope)
		if not item.is_empty() and (not pinned_only or item.get("pinned", false)): result.append(item)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["modified"]) > int(b["modified"]))
	return result.slice(0, 50)

func _save() -> Error: return Common.atomic_json(directory.path_join("index.json"), {"version": 1, "entries": entries, "chosen": chosen, "roots": extra_roots})

func _cache_bytes() -> int:
	var total = 0
	var queue = [directory]
	while not queue.is_empty():
		var path: String = queue.pop_back()
		var folder = DirAccess.open(path)
		if folder == null: continue
		for subfolder in folder.get_directories():
			if not folder.is_link(subfolder): queue.append(path.path_join(subfolder))
		for name in folder.get_files():
			var input = FileAccess.open(path.path_join(name), FileAccess.READ)
			if input != null: total += input.get_length(); input.close()
	return total

static func image_dimensions(path: String) -> Vector2i:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 12: return Vector2i.ZERO
	var head = file.get_buffer(12)
	if head.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) and file.get_length() >= 24:
		file.big_endian = true
		file.seek(16)
		return Vector2i(file.get_32(), file.get_32())
	if head[0] == 255 and head[1] == 216:
		file.big_endian = true
		file.seek(2)
		for segment in range(512):
			if file.get_position() + 4 > file.get_length() or file.get_8() != 255: break
			var marker = file.get_8()
			while marker == 255 and file.get_position() < file.get_length(): marker = file.get_8()
			if marker in [0xD9, 0xDA]: break
			if marker == 0xD8 or marker == 0x01 or marker in range(0xD0, 0xD8): continue
			var length = file.get_16()
			if length < 2 or file.get_position() + length - 2 > file.get_length(): break
			if marker in [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF] and length >= 7:
				file.get_8()
				var height = file.get_16()
				return Vector2i(file.get_16(), height)
			file.seek(file.get_position() + length - 2)
	elif head.slice(0, 4).get_string_from_ascii() == "RIFF" and head.slice(8, 12).get_string_from_ascii() == "WEBP":
		for chunk in range(32):
			if file.get_position() + 8 > file.get_length(): break
			var name = file.get_buffer(4).get_string_from_ascii()
			var length = file.get_32()
			var start = file.get_position()
			if start + length > file.get_length(): break
			if name == "VP8X" and length >= 10:
				file.get_32()
				var values = file.get_buffer(6)
				return Vector2i(1 + values[0] + (values[1] << 8) + (values[2] << 16), 1 + values[3] + (values[4] << 8) + (values[5] << 16))
			if name == "VP8L" and length >= 5 and file.get_8() == 0x2F:
				var bits = file.get_32()
				return Vector2i(1 + (bits & 0x3FFF), 1 + ((bits >> 14) & 0x3FFF))
			if name == "VP8 " and length >= 10:
				file.seek(start + 3)
				if file.get_buffer(3) == PackedByteArray([0x9D, 0x01, 0x2A]): return Vector2i(file.get_16() & 0x3FFF, file.get_16() & 0x3FFF)
			file.seek(start + length + (length % 2))
	return Vector2i.ZERO
