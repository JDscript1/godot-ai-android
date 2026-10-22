@tool
extends RefCounted
## Asset Store protocol of this editor, staged archives and verified installation.
static var Common: GDScript
static var Transport: GDScript
var owner: Node
var tools: RefCounted
var transport: RefCounted
var api_url = "https://store.godotengine.org/api/v1"
var test_http = false
var directory = ""
var catalog: Dictionary = {}
var installed: Dictionary = {}
var busy = false

func _init(node: Node = null, editor_tools: RefCounted = null) -> void:
	owner = node
	tools = editor_tools
	transport = Transport.new(node)

func configure(project_directory: String) -> void:
	directory = project_directory.path_join("store")
	DirAccess.make_dir_recursive_absolute(directory)
	installed = Common.read_json(directory.path_join("installed.json"), {})

static func definitions() -> Array:
	return [Common.tool("store_search", "Find compatible addons in the configured Godot Asset Store. Returns compact cards, IDs, publisher and license; excludes project templates.", {"query": Common.string_field(), "page": {"type": "integer", "minimum": 1, "maximum": 50}}, ["query"]), Common.tool("store_describe", "Inspect an addon and its available compatible stable releases. Choose an actual version before installing.", {"id": Common.string_field()}, ["id"]), Common.tool("store_install", "Download and install an explicitly selected addon release. Validates ZIP paths, sizes, compatibility, available hashes and conflicts; uses the native Godot installer. Does not enable scripts automatically. Existing files are never overwritten.", {"id": Common.string_field(), "version": Common.string_field()}, ["id", "version"], "external"), Common.tool("plugin_enable", "Enable or disable an installed addon by its actual addons/ folder name. Enabling runs the editor plugin; verify the reported state.", {"name": Common.string_field(), "enabled": {"type": "boolean"}}, ["name", "enabled"], "write"), Common.tool("store_remove", "Remove a tracked installation only if its files have not been edited. Disable its plugins first. Manual changes are preserved as conflicts.", {"installation": Common.string_field()}, ["installation"], "write")]

static func valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > 160: return false
	for character in value:
		if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789-_.": return false
	return value not in [".", ".."]

func _request_json(path: String, cancel: Dictionary) -> Dictionary:
	var result = await transport.request(api_url.trim_suffix("/") + "/" + path, HTTPClient.METHOD_GET, [], null, {"cancel": cancel, "allow_http": test_http})
	if not result.get("ok", false): return result
	return Common.success(result.get("json"))

func search(query: String, page: int, cancel: Dictionary) -> Dictionary:
	var version = Engine.get_version_info()
	var compatibility = "%s.%s.%s" % [version["major"], version["minor"], version["patch"]]
	var result = await _request_json("search/query/?query=" + query.uri_encode() + "&require_release=true&type=0&sort=relevance&compatibility=" + compatibility + "&page=" + str(clampi(page, 1, 50)), cancel)
	if not result.get("ok", false): return result
	if not result.get("result") is Dictionary: return Common.failure("Catalog Store invalid.")
	var cards = []
	for hit in result["result"].get("hits", []).slice(0, 12):
		var asset: Dictionary = hit.get("asset", {})
		var id = str(asset.get("slug", ""))
		if not valid_id(id): continue
		var item = {"id": id, "name": asset.get("name", id), "publisher": asset.get("publisher", {}).get("name", ""), "license": asset.get("license_type", ""), "url": asset.get("store_url", "")}
		cards.append(item)
	return {"ok": true, "result": {"count": result["result"].get("count", 0), "items": cards}, "store_items": cards}

func describe(id: String, cancel: Dictionary) -> Dictionary:
	if not valid_id(id): return Common.failure("ID Store invalid.")
	var result = await _request_json("assets/" + id.uri_encode(), cancel)
	if not result.get("ok", false): return result
	if not result.get("result") is Dictionary: return Common.failure("Descriere Store invalidă.")
	var asset: Dictionary = result["result"]
	var publisher = str(asset.get("publisher", {}).get("slug", ""))
	if not valid_id(publisher): return Common.failure("Publisher Store invalid.")
	var releases = await _request_json("releases/" + publisher.uri_encode() + "/" + id.uri_encode() + "/", cancel)
	if not releases.get("ok", false): return releases
	if not releases.get("result") is Array: return Common.failure("Lista versiunilor este invalidă.")
	var available = []
	for release in releases["result"]:
		if release is Dictionary and release.get("stable", false) and compatible(release): available.append(release)
	var entry = {"id": id, "name": asset.get("name", id), "publisher": asset.get("publisher", {}).get("name", ""), "license": asset.get("license_type", ""), "description": str(asset.get("body_bbcode", "")).left(6000), "releases": available}
	catalog[id] = entry
	return {"ok": true, "result": entry, "store_items": [entry]}

static func compatible(release: Dictionary) -> bool:
	var current = Engine.get_version_info()
	var engine = [int(current["major"]), int(current["minor"]), int(current["patch"])]
	for bound in ["min_godot_version", "max_godot_version"]:
		if release.get(bound) == null: continue
		var components = str(release[bound]).split(".")
		for index in range(3):
			var value = int(components[index]) if index < components.size() else 0
			if engine[index] == value: continue
			if (bound == "min_godot_version" and engine[index] < value) or (bound == "max_godot_version" and engine[index] > value): return false
			break
	return true

func install(id: String, version: String, cancel: Dictionary) -> Dictionary:
	if busy: return Common.failure("O instalare este deja în lucru.")
	var metadata = await describe(id, cancel)
	if not metadata.get("ok", false): return metadata
	var selected = {}
	for release in metadata["result"]["releases"]:
		if str(release.get("version")) == version: selected = release
	if selected.is_empty(): return Common.failure("Alege o versiune compatibilă din store_describe.")
	var url = str(selected.get("download_url", ""))
	if not Common.parse_url(url, test_http).get("ok", false): return Common.failure("Adresă de descărcare invalidă.")
	busy = true
	var path = directory.path_join(Common.uid() + ".zip")
	var downloaded = await transport.request(url, HTTPClient.METHOD_GET, [], null, {"cancel": cancel, "allow_http": test_http, "save_path": path, "max_bytes": 64 * 1024 * 1024, "follow_redirects": true, "timeout": 120})
	if not downloaded.get("ok", false): busy = false; return downloaded
	var sha = str(selected.get("sha256", selected.get("download_hash", "")))
	if not sha.is_empty() and FileAccess.get_sha256(path) != sha: busy = false; return Common.failure("Hash-ul arhivei nu corespunde sursei.")
	var result = await install_zip(path, metadata["result"], version, cancel)
	busy = false
	return result

static func zip_manifest(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 64 * 1024 * 1024: return Common.failure("Arhivă lipsă sau prea mare.")
	# Inspect central directory before ZIPReader can allocate decompressed entries.
	var bytes = file.get_buffer(file.get_length())
	var end = -1
	for index in range(bytes.size() - 22, maxi(-1, bytes.size() - 65558), -1):
		if bytes.decode_u32(index) == 0x06054b50: end = index; break
	if end < 0 or bytes.decode_u16(end + 4) != 0 or bytes.decode_u16(end + 6) != 0: return Common.failure("Arhivă ZIP nesuportată.")
	var count = bytes.decode_u16(end + 10)
	var offset = bytes.decode_u32(end + 16)
	if bytes.decode_u16(end + 8) != count or bytes.decode_u16(end + 20) + end + 22 != bytes.size() or offset + bytes.decode_u32(end + 12) != end: return Common.failure("Index ZIP inconsistent sau ZIP64 nesuportat.")
	if count < 1 or count > 1000: return Common.failure("Prea multe fișiere în arhivă.")
	var names = []
	var sizes = {}
	var total = 0
	for index in range(count):
		if offset + 46 > end or bytes.decode_u32(offset) != 0x02014b50: return Common.failure("Index ZIP invalid.")
		var flags = bytes.decode_u16(offset + 8)
		var method = bytes.decode_u16(offset + 10)
		var size = bytes.decode_u32(offset + 24)
		var name_length = bytes.decode_u16(offset + 28)
		var extra = bytes.decode_u16(offset + 30)
		var comment = bytes.decode_u16(offset + 32)
		var mode = bytes.decode_u32(offset + 38) >> 16
		if offset + 46 + name_length + extra + comment > end or (flags & 1) != 0 or method not in [0, 8] or size > 32 * 1024 * 1024 or (mode & 0xF000) == 0xA000: return Common.failure("Intrare ZIP nesigură sau prea mare.")
		var name = bytes.slice(offset + 46, offset + 46 + name_length).get_string_from_utf8()
		if name.is_absolute_path() or ":" in name or "\\" in name or 0 in name.to_utf8_buffer() or ".." in name.split("/") or ".git" in name.split("/") or name.begins_with("/"): return Common.failure("Cale ZIP nepermisă.")
		total += size
		if total > 128 * 1024 * 1024: return Common.failure("Arhiva decomprimată este prea mare.")
		if sizes.has(name): return Common.failure("Intrări ZIP duplicate.")
		sizes[name] = size
		if not name.ends_with("/"): names.append(name)
		offset += 46 + name_length + extra + comment
	return {"ok": true, "result": names, "sizes": sizes}

func install_zip(path: String, metadata: Dictionary, version: String, cancel: Dictionary) -> Dictionary:
	var inspected = zip_manifest(path)
	if not inspected.get("ok", false): return inspected
	var reader = ZIPReader.new()
	if reader.open(path) != OK: return Common.failure("Arhiva ZIP nu poate fi deschisă.")
	var files = []
	var hashes = {}
	var plugins = []
	var staged = directory.path_join(Common.uid() + "-approved.zip")
	var writer = ZIPPacker.new()
	if writer.open(staged) != OK: reader.close(); return Common.failure("Nu pot pregăti instalarea.")
	for source in inspected["result"]:
		if cancel.get("cancelled", false): writer.close(); reader.close(); return Common.failure("Instalare oprită.", "cancelled")
		var start = str(source).find("addons/")
		if start < 0 or (start > 0 and str(source)[start - 1] != "/"): continue
		var target = str(source).substr(start)
		var safe = Common.project_path("res://" + target)
		if safe.is_empty() or DirAccess.dir_exists_absolute(safe) or FileAccess.file_exists(safe) or hashes.has(safe.to_lower()): writer.close(); reader.close(); return Common.failure("Conflict de instalare: " + target, "install_conflict")
		var data = reader.read_file(source)
		if data.size() != int(inspected["sizes"].get(source, -1)): writer.close(); reader.close(); return Common.failure("Fișier corupt în addon: " + target)
		if target.ends_with(".gdextension") or target.get_extension().to_lower() in ["so", "dll", "dylib"]: writer.close(); reader.close(); return Common.failure("Addon nativ: compatibilitatea binarelor trebuie validată separat.", "native_addon_unverified")
		writer.start_file(target)
		writer.write_file(data)
		writer.close_file()
		var hash = HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		if not data.is_empty(): hash.update(data)
		hashes[safe.to_lower()] = {"path": safe, "sha256": hash.finish().hex_encode()}
		files.append(target)
		if target.ends_with("/plugin.cfg"): plugins.append(target.get_base_dir().trim_prefix("addons/"))
		if files.size() % 16 == 0: await owner.get_tree().process_frame
	writer.close()
	reader.close()
	if plugins.is_empty(): return Common.failure("Arhiva nu conține un addon editor cu plugin.cfg.")
	while Engine.is_editor_hint() and EditorInterface.get_resource_filesystem().is_scanning(): await owner.get_tree().process_frame
	if cancel.get("cancelled", false): return Common.failure("Instalare oprită.", "cancelled")
	for item in hashes.values():
		if FileAccess.file_exists(item["path"]) or DirAccess.dir_exists_absolute(item["path"]): return Common.failure("Conflict apărut în timpul pregătirii instalării.", "install_conflict")
	if owner.plugin.has_method("install_asset_archive"):
		owner.plugin.install_asset_archive(staged, str(metadata.get("name", "Addon")))
	else:
		# Upstream-editor fixture: the compiled fork uses EditorAssetInstaller above.
		var archive = ZIPReader.new()
		archive.open(staged)
		for target in files:
			var destination = "res://" + target
			DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
			var output = FileAccess.open(destination, FileAccess.WRITE)
			if output != null: output.store_buffer(archive.read_file(target)); output.close()
		archive.close()
	var manifest = []
	var success = true
	for entry in hashes.values():
		if FileAccess.get_sha256(entry["path"]) != entry["sha256"]: success = false
		else: manifest.append(entry)
	var id = Common.uid()
	installed[id] = {"id": metadata.get("id", "local"), "name": metadata.get("name", "Addon"), "version": version, "files": manifest, "plugins": plugins, "complete": success}
	Common.atomic_json(directory.path_join("installed.json"), installed)
	tools._request_scan()
	return {"ok": success, "result": {"installation": id, "plugins": plugins, "files": manifest.size(), "enabled": false, "restart_required": false}, "error": "" if success else "Instalare incompletă; consultă fișierele și Output."}

func enable_plugin(name: String, enabled: bool) -> Dictionary:
	if not valid_id(name) or not FileAccess.file_exists("res://addons/" + name + "/plugin.cfg"): return Common.failure("Addon inexistent.")
	EditorInterface.set_plugin_enabled(name, enabled)
	var actual = EditorInterface.is_plugin_enabled(name)
	return {"ok": actual == enabled, "result": {"name": name, "enabled": actual}, "error": "" if actual == enabled else "Pluginul nu s-a activat. Consultă Output/Debugger."}

func remove(id: String) -> Dictionary:
	if not installed.has(id): return Common.failure("Instalare neurmărită.")
	var entry: Dictionary = installed[id]
	for plugin in entry["plugins"]:
		if Engine.is_editor_hint() and EditorInterface.is_plugin_enabled(plugin): return Common.failure("Dezactivează pluginul înainte de ștergere.")
	for item in entry["files"]:
		if str(item["path"]).ends_with(".gd") and tools._dirty_script(str(item["path"]), FileAccess.get_file_as_string(item["path"])): return Common.failure("Script cu modificări nesalvate: " + str(item["path"]), "unsaved_changes")
		if FileAccess.get_sha256(item["path"]) != item["sha256"]: return Common.failure("Fișier modificat manual: " + str(item["path"]), "install_conflict")
	if not owner.plugin.has_method("prepare_script_removal"): return Common.failure("Dezinstalarea completă necesită puntea editorului recompilat.", "native_bridge_unavailable")
	var script_paths = PackedStringArray()
	for item in entry["files"]:
		if str(item["path"]).ends_with(".gd"): script_paths.append(str(item["path"]))
	owner.plugin.prepare_script_removal(script_paths)
	for item in entry["files"]:
		# Match native removal: detach cached scripts before later save/reload cycles.
		if Engine.is_editor_hint() and ResourceLoader.has_cached(str(item["path"])):
			var cached = ResourceLoader.get_cached_ref(str(item["path"]))
			EditorInterface.get_file_system_dock().emit_signal("resource_removed", cached)
			cached.resource_path = ""
		if DirAccess.remove_absolute(item["path"]) != OK: return Common.failure("Nu pot șterge " + str(item["path"]))
	if Engine.is_editor_hint():
		for item in entry["files"]: EditorInterface.get_file_system_dock().emit_signal("file_removed", str(item["path"]))
	installed.erase(id)
	Common.atomic_json(directory.path_join("installed.json"), installed)
	tools._request_scan()
	return Common.success({"removed": true})
