@tool
extends RefCounted
## Independent project copies, with source hashes and guarded integration.
## This is filesystem separation, not an OS security sandbox for project scripts.
static var Common: GDScript
static var EngineeringStore: GDScript
var directory = ""

func configure(path: String) -> void: directory = path.path_join("engineering/experiments")

func list_saved() -> Dictionary:
	var folders = DirAccess.get_directories_at(directory) if DirAccess.dir_exists_absolute(directory) else PackedStringArray()
	var rows = []
	for id in folders:
		if rows.size() >= 50: break
		if not EngineeringStore.valid_id(id): continue
		var item: Variant = Common.read_json(directory.path_join(id).path_join("manifest.json"), {})
		if item is Dictionary and item.get("id") == id: rows.append({"id": id, "label": item.get("label", ""), "state": item.get("state", "unknown"), "created": item.get("created", 0)})
	return Common.success({"items": rows, "truncated": folders.size() > 50})

static func snapshot(root: String, caches: bool = false) -> Dictionary:
	var queue = [""]
	var files = {}
	var excluded = []
	var bytes = 0
	while not queue.is_empty():
		var relative: String = queue.pop_front()
		var dir = DirAccess.open(root.path_join(relative))
		if dir == null: return Common.failure("Directorul proiectului nu poate fi citit.", "snapshot_unavailable")
		for folder in dir.get_directories():
			if dir.is_link(folder): return Common.failure("Copia necesită fișiere locale, fără legături simbolice.", "snapshot_symlink")
			var child = relative.path_join(folder)
			if folder in [".git", ".ai-qa", ".godot_ai", "node_modules"]: excluded.append(child); continue
			if folder == ".godot" and not caches: continue
			if relative == ".godot" and folder != "imported": continue
			queue.append(child)
		for filename in dir.get_files():
			if dir.is_link(filename): return Common.failure("Copia conține o legătură simbolică.", "snapshot_symlink")
			if filename == ".git": excluded.append(relative.path_join(filename)); continue
			if relative == ".godot" and filename not in ["uid_cache.bin", "global_script_class_cache.cfg", "extension_list.cfg"]: continue
			var child = relative.path_join(filename)
			if filename.begins_with(".env") or filename.get_extension().to_lower() in ["key", "pem", "keystore"]: excluded.append(child); continue
			var file = FileAccess.open(root.path_join(child), FileAccess.READ)
			if file == null: return Common.failure("Fișier necitibil: " + child, "snapshot_unavailable")
			bytes += file.get_length()
			if files.size() >= 2000 or bytes > 512 * 1024 * 1024: return Common.failure("Copia depășește bugetul de 2.000 fișiere / 512 MB.", "snapshot_budget")
			files["res://" + child] = FileAccess.get_sha256(root.path_join(child))
	return Common.success({"files": files, "digest": JSON.stringify(files, "", true).sha256_text(), "bytes": bytes, "excluded": excluded})

func create(label: String, tree: SceneTree, cancel: Dictionary = {}) -> Dictionary:
	var root = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var captured = snapshot(root, true)
	if not captured.get("ok", false): return captured
	var id = Common.uid()
	var folder = directory.path_join(id)
	var copied_root = folder.path_join("project")
	var item = {"version": 1, "id": id, "label": label.left(160), "state": "copying", "project": copied_root, "base": {}, "excluded": captured["result"]["excluded"], "created": Time.get_unix_time_from_system()}
	if Common.atomic_json(folder.path_join("manifest.json"), item) != OK: return Common.failure("Copia nu poate fi pregătită.", "checkpoint_failed")
	var count = 0
	for path in captured["result"]["files"]:
		if cancel.get("cancelled", false): return Common.failure("Copiere întreruptă; proiectul original este păstrat.", "cancelled")
		var relative = str(path).trim_prefix("res://")
		var input_path = root.path_join(relative)
		var output_path = copied_root.path_join(relative)
		if DirAccess.make_dir_recursive_absolute(output_path.get_base_dir()) != OK: return Common.failure("Directorul copiei nu poate fi creat.", "copy_failed")
		var input = FileAccess.open(input_path, FileAccess.READ)
		var output = FileAccess.open(output_path, FileAccess.WRITE)
		if input == null or output == null: return Common.failure("Copiere eșuată.", "copy_failed")
		while input.get_position() < input.get_length():
			if cancel.get("cancelled", false): return Common.failure("Copiere oprită.", "cancelled")
			output.store_buffer(input.get_buffer(mini(256 * 1024, input.get_length() - input.get_position())))
		output.close()
		if FileAccess.get_sha256(output_path) != captured["result"]["files"][path] or FileAccess.get_sha256(input_path) != captured["result"]["files"][path]: return Common.failure("Proiectul s-a schimbat în timpul copierii.", "snapshot_conflict")
		if not relative.begins_with(".godot/"): item["base"][path] = captured["result"]["files"][path]
		count += 1
		if count % 8 == 0 and tree != null: await tree.process_frame
	item["state"] = "ready"
	item["files"] = count
	if Common.atomic_json(folder.path_join("manifest.json"), item) != OK: return Common.failure("Manifestul copiei nu a putut fi confirmat.", "checkpoint_failed")
	return Common.success(item.merged({"isolation": "Independent files; project scripts are not an OS sandbox. Run only through the managed native launcher."}))

func read(id: String) -> Dictionary:
	if not EngineeringStore.valid_id(id): return Common.failure("ID de experiment invalid.", "invalid_experiment")
	var item: Variant = Common.read_json(directory.path_join(id).path_join("manifest.json"), {})
	if not item is Dictionary or item.get("id") != id or item.get("project") != directory.path_join(id).path_join("project") or item.get("state") != "ready": return Common.failure("Experiment inexistent sau incomplet.", "experiment_unavailable")
	return Common.success(item)

func _path(item: Dictionary, virtual_path: String) -> String:
	var path = Common.project_path(virtual_path)
	if path.is_empty(): return ""
	var current = str(item["project"])
	for component in path.trim_prefix("res://").split("/", false):
		var dir = DirAccess.open(current)
		if dir != null and dir.is_link(component): return ""
		current = current.path_join(component)
	return current

func read_file(id: String, path: String) -> Dictionary:
	var item = read(id)
	if not item.get("ok", false): return item
	var target = _path(item["result"], path)
	if target.is_empty(): return Common.failure("Cale invalidă.", "invalid_path")
	var file = FileAccess.open(target, FileAccess.READ)
	if file == null or file.get_length() > 1024 * 1024: return Common.failure("Text inexistent sau mai mare de 1 MB.", "invalid_file")
	var bytes = file.get_buffer(file.get_length())
	var text = bytes.get_string_from_utf8()
	if bytes.has(0) or text.to_utf8_buffer() != bytes: return Common.failure("Fișierul nu este text UTF-8.", "invalid_file")
	return Common.success({"path": path, "text": text, "sha256": FileAccess.get_sha256(target), "experiment": id})

func write_file(id: String, path: String, text: String, expected: String) -> Dictionary:
	var item = read(id)
	if not item.get("ok", false): return item
	var target = _path(item["result"], path)
	if target.is_empty() or text.to_utf8_buffer().size() > 1024 * 1024: return Common.failure("Cale sau text invalid.", "invalid_file")
	var hash = FileAccess.get_sha256(target) if FileAccess.file_exists(target) else "missing"
	if expected != hash: return Common.failure("Copia s-a schimbat; recitește fișierul.", "experiment_conflict")
	if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK: return Common.failure("Directorul nu poate fi creat.", "write_failed")
	var temporary = target + "." + Common.uid() + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return Common.failure("Fișierul nu poate fi scris.", "write_failed")
	file.store_string(text)
	file.close()
	if DirAccess.rename_absolute(temporary, target) != OK: return Common.failure("Copia nu a putut fi înlocuită.", "write_failed")
	return read_file(id, path)

func differences(id: String) -> Dictionary:
	var item = read(id)
	if not item.get("ok", false): return item
	var current = snapshot(item["result"]["project"])
	if not current.get("ok", false): return current
	var base: Dictionary = item["result"]["base"]
	var keys = base.keys()
	for path in current["result"]["files"]:
		if path not in keys: keys.append(path)
	var changes = []
	for path in keys:
		var before = str(base.get(path, "missing"))
		var after = str(current["result"]["files"].get(path, "missing"))
		if before != after: changes.append({"path": path, "before": before, "after": after})
	return Common.success({"id": id, "changes": changes, "digest": current["result"]["digest"], "base_digest": JSON.stringify(base, "", true).sha256_text()})

func proposals(id: String, paths: Array = []) -> Dictionary:
	var differences_result = differences(id)
	if not differences_result.get("ok", false): return differences_result
	var proposed = []
	for change in differences_result["result"]["changes"]:
		if not paths.is_empty() and change["path"] not in paths: continue
		var current_hash = FileAccess.get_sha256(change["path"]) if FileAccess.file_exists(change["path"]) else "missing"
		if current_hash != change["before"]: return Common.failure("Proiectul original a fost modificat între timp: " + str(change["path"]), "experiment_conflict")
		var operation = {"path": change["path"], "expected_sha256": current_hash}
		if change["after"] == "missing": operation["action"] = "delete"
		else:
			var source = read_file(id, change["path"])
			if not source.get("ok", false): return source
			operation["action"] = "write"
			operation["text"] = source["result"]["text"]
		proposed.append(operation)
	if proposed.is_empty(): return Common.failure("Nicio modificare text selectată.", "empty_experiment")
	return Common.success({"changes": proposed, "experiment": id, "digest": differences_result["result"]["digest"]})
