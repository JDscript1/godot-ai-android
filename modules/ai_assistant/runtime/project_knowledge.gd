@tool
extends RefCounted
## Bounded, persistent project facts. Never loads/instantiates project resources.
static var Common: GDScript
const MAX_FILES = 600
const MAX_ENTRIES = 4000
const MAX_BYTES = 4 * 1024 * 1024
const TEXT_TYPES = ["gd", "tscn", "tres", "gdshader", "gdshaderinc", "godot", "gdextension"]
var owner: Node
var location = ""
var state = {"version": 1, "revision": 0, "files": {}, "partial": true}
var dirty = true
var refreshing = false
var change_serial = 0

func _init(node: Node = null) -> void:
	owner = node

func configure(directory: String) -> void:
	location = directory.path_join("project-map.json")
	var saved: Variant = Common.read_json(location, {})
	if saved is Dictionary and saved.get("version") == 1 and saved.get("root") == ProjectSettings.globalize_path("res://").sha256_text() and saved.get("files") is Dictionary and saved["files"].size() <= MAX_FILES:
		var valid = saved["files"].values().all(func(entry: Variant) -> bool: return entry is Dictionary and entry.get("path") is String and entry.get("dependencies") is Array and entry.get("symbols") is Array and entry["dependencies"].all(func(value: Variant) -> bool: return value is String))
		if valid: state = saved
	# Disk facts must be refreshed after a restart, even if the cache was valid.
	dirty = true

static func definition() -> Dictionary:
	return Common.tool("godot_project_map", "Refresh and query the persistent project map without loading scripts/resources. Returns hashes, literal dependencies, reverse dependents, symbols and missing references. Bounded coverage is explicit; partial scans never prove absence. Use before cross-file changes or after a stale-map notice.", {"path": Common.string_field(), "query": Common.string_field(), "limit": {"type": "integer", "minimum": 1, "maximum": 80}}, [])

func refresh(toolset: RefCounted, cancel: Dictionary = {}, requested_scope: String = "res://") -> Dictionary:
	if refreshing: return Common.failure("Harta proiectului este deja în actualizare.", "map_busy")
	var scope = Common.project_path(requested_scope)
	if scope.is_empty(): return Common.failure("Cale de indexare invalidă.", "invalid_path")
	refreshing = true
	var started_serial = change_serial
	var queue = [scope]
	var files = {}
	var examined = 0
	var used = 0
	var partial = false
	var skipped = 0
	while not queue.is_empty():
		if cancel.get("cancelled", false):
			refreshing = false
			dirty = true
			return Common.failure("Actualizarea hărții a fost oprită.", "cancelled")
		var path: String = queue.pop_front()
		examined += 1
		if examined > MAX_ENTRIES or files.size() >= MAX_FILES:
			partial = true
			break
		if DirAccess.dir_exists_absolute(path):
			var dir = DirAccess.open(path)
			if dir == null:
				partial = true
				continue
			var children = Array(dir.get_directories()) + Array(dir.get_files())
			children.sort()
			for child in children:
				if str(child).begins_with(".") or child in ["node_modules", "recovery"] or dir.is_link(child): continue
				if queue.size() + examined >= MAX_ENTRIES:
					partial = true
					break
				queue.append(path.path_join(child))
			continue
		var extension = path.get_extension().to_lower()
		if extension not in TEXT_TYPES and extension not in ["glb", "gltf", "png", "jpg", "webp", "wav", "ogg", "fbx", "blend"]: continue
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			partial = true
			continue
		var bytes = file.get_length()
		var entry = {"path": path, "kind": extension, "bytes": bytes, "modified": FileAccess.get_modified_time(path), "dependencies": [], "symbols": []}
		if extension in TEXT_TYPES:
			if bytes > 1024 * 1024 or used + bytes > MAX_BYTES:
				skipped += 1
				partial = true
				entry["content_indexed"] = false
			else:
				var text = file.get_as_text()
				used += bytes
				entry["sha256"] = text.sha256_text()
				entry["content_indexed"] = true
				var cached: Dictionary = state.get("files", {}).get(path, {})
				if cached.get("sha256") == entry["sha256"]:
					entry = cached.duplicate(true)
					entry["modified"] = FileAccess.get_modified_time(path)
				else:
					entry["dependencies"] = _dependencies(text, extension, toolset)
					if extension == "gd":
						for symbol in toolset._scan_symbols(path, text).slice(0, 80): entry["symbols"].append({"name": symbol["name"], "kind": symbol["kind"], "line": symbol["line"]})
		else: entry["content_indexed"] = false
		file.close()
		entry["resolved_dependencies"] = entry["dependencies"].map(_resolve_reference)
		entry["symbols_limit_reached"] = entry["symbols"].size() >= 80
		entry["dependencies_limit_reached"] = entry["dependencies"].size() >= 100
		if entry["symbols_limit_reached"] or entry["dependencies_limit_reached"]: partial = true
		files[path] = entry
		if files.size() % 16 == 0 and is_instance_valid(owner) and owner.is_inside_tree(): await owner.get_tree().process_frame
	if cancel.get("cancelled", false):
		refreshing = false
		dirty = true
		return Common.failure("Actualizarea hărții a fost oprită.", "cancelled")
	var digest = JSON.stringify(files).sha256_text()
	var changed = digest != state.get("digest", "") or partial != state.get("partial", true)
	state = {"version": 1, "root": ProjectSettings.globalize_path("res://").sha256_text(), "coverage_scope": scope, "revision": int(state.get("revision", 0)) + (1 if changed else 0), "digest": digest, "files": files, "partial": partial, "scanned_bytes": used, "examined": examined, "skipped_large": skipped}
	refreshing = false
	dirty = change_serial != started_serial
	if not location.is_empty() and Common.atomic_json(location, state) != OK: return Common.failure("Harta a fost actualizată, dar salvarea a eșuat.", "map_save_failed")
	return Common.success(summary())

func mark_changed() -> void:
	change_serial += 1
	dirty = true

static func _dependencies(text: String, extension: String, toolset: RefCounted) -> Array:
	var output = []
	var expression = RegEx.new()
	var pattern = "(?:preload|load)\\s*\\(\\s*[\"']([^\"']+)[\"']|extends\\s+[\"']([^\"']+)[\"']" if extension == "gd" else "path\\s*=\\s*\"([^\"]+)\"|#include\\s+\"([^\"]+)\""
	if extension == "godot": pattern = "[A-Za-z_][A-Za-z0-9_/]*\\s*=\\s*\"\\*?((?:res|uid)://[^\"]+)\""
	expression.compile(pattern)
	var masked = "\n".join(toolset._symbol_code_lines(text.split("\n"))) if extension == "gd" else ""
	for match_result in expression.search_all(text):
		if extension == "gd" and masked.substr(match_result.get_start(), 4).strip_edges().is_empty(): continue
		if extension in ["tscn", "tres"]:
			var start = text.rfind("\n", match_result.get_start()) + 1
			if not text.substr(start, match_result.get_start() - start).strip_edges().begins_with("[ext_resource"): continue
		var dependency = match_result.get_string(1) if not match_result.get_string(1).is_empty() else match_result.get_string(2)
		if dependency.begins_with("res://"):
			dependency = Common.project_path(dependency)
			if dependency.is_empty(): continue
		elif not dependency.begins_with("uid://"): continue
		if dependency not in output: output.append(dependency)
	return output.slice(0, 100)

static func _resolve_reference(reference: String) -> String:
	if reference.begins_with("uid://"):
		var id = ResourceUID.text_to_id(reference)
		if ResourceUID.has_id(id): return ResourceUID.get_id_path(id)
	return reference

func summary() -> Dictionary:
	return {"revision": state.get("revision", 0), "coverage_scope": state.get("coverage_scope", "res://"), "indexed_files": state.get("files", {}).size(), "partial": state.get("partial", true), "stale": dirty, "scanned_bytes": state.get("scanned_bytes", 0), "symbols_per_file": 80, "dependencies_per_file": 100, "scope": "Literal resource references and top-level GDScript symbols. Dynamic paths, binary contents and dependents outside coverage_scope are not indexed."}

func query(args: Dictionary = {}) -> Dictionary:
	var rows = []
	var path = str(args.get("path", ""))
	if not path.is_empty() and Common.project_path(path).is_empty(): return Common.failure("Cale de proiect invalidă.", "invalid_path")
	if not path.is_empty(): path = Common.project_path(path)
	var needle = str(args.get("query", "")).to_lower()
	var total = 0
	var reverse = {}
	for entry in state.get("files", {}).values():
		for dependency in entry["dependencies"].map(_resolve_reference):
			if not reverse.has(dependency): reverse[dependency] = []
			reverse[dependency].append(entry["path"])
	for entry in state.get("files", {}).values():
		if not path.is_empty() and entry["path"] != path and not str(entry["path"]).begins_with(path.trim_suffix("/") + "/"): continue
		if not needle.is_empty() and needle not in str(entry["path"]).to_lower() and not entry["symbols"].any(func(symbol: Dictionary) -> bool: return needle in str(symbol["name"]).to_lower()): continue
		total += 1
		if rows.size() >= clampi(int(args.get("limit", 30)), 1, 80): continue
		var item: Dictionary = entry.duplicate(true)
		item["resolved_dependencies"] = entry["dependencies"].map(_resolve_reference)
		item["missing"] = item["resolved_dependencies"].filter(func(dependency: String) -> bool: return dependency.begins_with("res://") and not FileAccess.file_exists(dependency))
		item["unresolved_uids"] = item["resolved_dependencies"].filter(func(dependency: String) -> bool: return dependency.begins_with("uid://"))
		item["dependents"] = reverse.get(entry["path"], [])
		rows.append(item)
	return Common.success(summary().merged({"files": rows, "total": total, "truncated": total > rows.size()}))

func missing_references() -> Array:
	var grouped = {}
	for entry in state.get("files", {}).values():
		for dependency in entry["dependencies"].map(_resolve_reference):
			if dependency.begins_with("uid://") or (dependency.begins_with("res://") and not FileAccess.file_exists(dependency)):
				if not grouped.has(dependency): grouped[dependency] = []
				grouped[dependency].append(entry["path"])
	var output = []
	for path in grouped: output.append({"source": "references", "path": path, "severity": "error", "category": "unresolved_uid" if path.begins_with("uid://") else "missing_resource", "message": "Referenced resource UID is unresolved." if path.begins_with("uid://") else "Referenced project resource does not exist.", "related": grouped[path].slice(0, 20)})
	return output
