@tool
extends RefCounted

static var Common: GDScript
static var Diff: GDScript
const MAX_FILES = 16
const MAX_BYTES = 4 * 1024 * 1024
var directory = ""
var root_hash = ""
var busy = false

func configure(storage: String) -> void:
	directory = storage
	root_hash = ProjectSettings.globalize_path("res://").sha256_text()

static func definitions() -> Array:
	var id = {"type": "string", "pattern": "^[a-f0-9-]{36}$"}
	return [
		Common.tool("godot_changes_prepare", "Stage a coordinated UTF-8 file change set in private recovery storage. No project files change. Read existing files first and supply their SHA-256, or missing for new files. Up to 16 files/4 MB. Returns bounded diffs and an ID for apply. Use for dependent script/scene edits. Draft syntax is advisory against the current project, not the staged project.", {"changes": {"type": "array", "minItems": 1, "maxItems": MAX_FILES, "items": {"type": "object", "properties": {"path": {"type": "string"}, "action": {"type": "string", "enum": ["write", "delete"]}, "expected_sha256": {"type": "string", "pattern": "^(missing|[a-fA-F0-9]{64})$"}, "text": {"type": "string"}}, "required": ["path", "action", "expected_sha256"], "additionalProperties": false}}}, ["changes"]),
		Common.tool("godot_changes_apply", "Apply a prepared change set after rechecking every file and unsaved editor buffers. Stop or failure triggers compensating rollback; later user edits become conflicts and are preserved. Not a globally atomic filesystem transaction. Inspect the result, then validate saved scripts and run the scene.", {"id": id}, ["id"], "write"),
		Common.tool("godot_changes_rollback", "Restore a change set's verified recovery copies. Only restores files still matching this set's output; later edits are preserved and reported as conflicts. Also recovers interrupted applications without resubmitting them.", {"id": id}, ["id"], "write"),
		Common.tool("godot_changes_status", "Inspect one staged change set, its diffs and recovery state; omit ID to list recent sets. Reconciles interrupted journals against actual hashes without writing project files. Never resumes writes automatically.", {"id": id}, []),
	]

func _hash(path: String) -> String:
	if DirAccess.dir_exists_absolute(path): return "directory"
	if not FileAccess.file_exists(path): return "missing"
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return "unreadable"
	var oversized = file.get_length() > 1024 * 1024
	file.close()
	if oversized: return "oversized"
	var value = FileAccess.get_sha256(path)
	return value if not value.is_empty() else "unreadable"

func _valid_path(raw: String) -> String:
	var path = Common.project_path(raw)
	if path.is_empty() or path == "res://" or path == "res://project.godot": return ""
	if ProjectSettings.globalize_path(path).begins_with(ProjectSettings.globalize_path(directory).trim_suffix("/") + "/"): return ""
	return path

func _manifest_path(id: String) -> String:
	return directory.path_join(id).path_join("manifest.json")

func _blob(id: String, index: int, kind: String) -> String:
	return directory.path_join(id).path_join(str(index) + "." + kind)

func _blob_text(id: String, index: int, kind: String) -> String:
	var file = FileAccess.open(_blob(id, index, kind), FileAccess.READ)
	if file == null or file.get_length() > 1024 * 1024: return "[copie privată indisponibilă]"
	return file.get_as_text()

func _save(data: Dictionary) -> Error:
	return Common.atomic_json(_manifest_path(data["id"]), data)

func _load(id: String) -> Dictionary:
	if id.length() != 36 or id.replace("-", "").length() != 32 or not id.replace("-", "").is_valid_hex_number(): return {}
	var data = Common.read_json(_manifest_path(id), {})
	if not data is Dictionary or data.get("version") != 1 or data.get("id") != id or data.get("root") != root_hash: return {}
	var entries = data.get("entries")
	if not entries is Array or entries.is_empty() or entries.size() > MAX_FILES: return {}
	var paths = {}
	for entry in entries:
		if not entry is Dictionary or not entry.get("path") is String: return {}
		var path = _valid_path(entry["path"])
		if path.is_empty() or path != entry["path"] or paths.has(path): return {}
		paths[path] = true
		for field in ["before", "after"]:
			var hash_value = str(entry.get(field, ""))
			if hash_value != "missing" and (hash_value.length() != 64 or not hash_value.is_valid_hex_number()): return {}
		if not entry.get("parents", []) is Array: return {}
		for parent in entry.get("parents", []):
			if not parent is String or parent == "res://" or Common.project_path(parent) != parent or not path.begins_with(parent + "/"): return {}
	return data

func _write_blob(path: String, bytes: PackedByteArray) -> Error:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var error = file.get_error()
	file.close()
	FileAccess.set_unix_permissions(path, 384)
	return error

func prepare(changes: Array, turn: String = "", guard: Callable = Callable(), syntax: Callable = Callable()) -> Dictionary:
	if busy: return Common.failure("Un lot este în curs de modificare.", "changes_busy")
	if changes.is_empty() or changes.size() > MAX_FILES: return Common.failure("Lotul acceptă 1–16 fișiere.", "invalid_arguments")
	var entries = []
	var drafts = []
	var originals = []
	var total = 0
	for change in changes:
		if not change is Dictionary: return Common.failure("Modificare invalidă.", "invalid_arguments")
		var path = _valid_path(str(change.get("path", "")))
		if path.is_empty(): return Common.failure("Cale nepermisă; folosește instrumentele de setări pentru project.godot.", "invalid_path")
		for entry in entries:
			if path == entry["path"] or path.begins_with(entry["path"] + "/") or str(entry["path"]).begins_with(path + "/"): return Common.failure("Căi duplicate sau suprapuse în lot.", "invalid_path")
		var before = _hash(path)
		if before in ["directory", "unreadable"] or before != str(change.get("expected_sha256", "")).to_lower(): return Common.failure("Versiunea fișierului s-a schimbat: " + path, "patch_conflict")
		var action = str(change.get("action", ""))
		if action not in ["write", "delete"] or (action == "write" and not change.get("text") is String) or (action == "delete" and (before == "missing" or change.has("text"))): return Common.failure("Folosește write cu text sau delete pentru un fișier existent.", "invalid_arguments")
		var bytes = PackedByteArray()
		if before != "missing":
			var file = FileAccess.open(path, FileAccess.READ)
			if file == null or file.get_length() > 1024 * 1024: return Common.failure("Fișierul nu poate fi citit sau depășește 1 MB.", "invalid_file")
			bytes = file.get_buffer(file.get_length())
			file.close()
		var original = bytes.get_string_from_utf8()
		var text = str(change.get("text", ""))
		var draft = text.to_utf8_buffer()
		if bytes != original.to_utf8_buffer() or 0 in bytes or 0 in draft or draft.size() > 1024 * 1024: return Common.failure("Loturile acceptă numai text UTF-8 fără NUL, maximum 1 MB per fișier.", "invalid_file")
		total += bytes.size() + draft.size()
		if total > MAX_BYTES: return Common.failure("Lotul și copiile sale depășesc 4 MB.", "invalid_arguments")
		if guard.is_valid() and guard.call(path, original): return Common.failure("Fișierul are editări nesalvate: " + path, "unsaved_changes")
		if _hash(path) != before: return Common.failure("Fișier modificat în timpul citirii: " + path, "patch_conflict")
		var parents = []
		var parent = path.get_base_dir()
		while parent != "res://" and not DirAccess.dir_exists_absolute(parent):
			if FileAccess.file_exists(parent): return Common.failure("Un părinte este fișier: " + parent, "invalid_path")
			parents.append(parent)
			parent = parent.get_base_dir()
		var entry = {"path": path, "before": before, "after": "missing" if action == "delete" else text.sha256_text(), "parents": parents, "touched": false}
		if action == "write" and syntax.is_valid():
			var verdict = syntax.call(text, path)
			if verdict is Dictionary and not verdict.is_empty(): entry["draft_syntax"] = verdict
		entries.append(entry)
		drafts.append(draft)
		originals.append(bytes)
	var id = Common.uid()
	if DirAccess.make_dir_recursive_absolute(directory.path_join(id)) != OK: return Common.failure("Nu pot crea stocarea privată a lotului.", "recovery_failed")
	for index in entries.size():
		if _write_blob(_blob(id, index, "before"), originals[index]) != OK or _write_blob(_blob(id, index, "after"), drafts[index]) != OK: return Common.failure("Nu pot salva copiile lotului.", "recovery_failed")
	var data = {"version": 1, "id": id, "root": root_hash, "turn": turn, "state": "prepared", "created": Time.get_datetime_string_from_system(true), "entries": entries}
	if _save(data) != OK: return Common.failure("Nu pot salva jurnalul lotului.", "journal_failed")
	return _result(data)

func _preflight(data: Dictionary, guard: Callable) -> Dictionary:
	for index in data["entries"].size():
		var entry = data["entries"][index]
		var path = _valid_path(entry["path"])
		if path.is_empty() or _hash(path) != entry["before"]: return Common.failure("Conflict înainte de aplicare: " + str(entry["path"]), "patch_conflict")
		for kind in ["before", "after"]:
			if entry[kind] != "missing" and _hash(_blob(data["id"], index, kind)) != entry[kind]: return Common.failure("Copia lotului nu corespunde jurnalului.", "recovery_failed")
		var original = _blob_text(data["id"], index, "before")
		if guard.is_valid() and guard.call(path, original): return Common.failure("Editări nesalvate: " + path, "unsaved_changes")
	return Common.success(true)

func apply(id: String, cancel: Dictionary = {}, tree: SceneTree = null, guard: Callable = Callable()) -> Dictionary:
	if busy: return Common.failure("Un lot este în curs de modificare.", "changes_busy")
	var data = _load(id)
	if data.is_empty(): return Common.failure("Lot necunoscut sau jurnal invalid.", "invalid_changeset")
	if data["state"] == "applied":
		var existing = _result(data)
		if existing["result"]["files"].any(func(item: Dictionary) -> bool: return item["position"] != "after"): return _result(data, "restore_conflict", "Fișierele diferă de lotul aplicat. Inspectează starea; lotul nu a fost reaplicat.")
		return existing
	if data["state"] != "prepared": return Common.failure("Lotul a fost întrerupt sau restaurat. Verifică status și rollback; nu îl reaplica.", "recovery_required")
	var checked = _preflight(data, guard)
	if not checked.get("ok", false): return checked
	if cancel.get("cancelled", false): return Common.failure("Oprit înainte de modificări.", "cancelled")
	busy = true
	data["state"] = "applying"
	if _save(data) != OK:
		busy = false
		return Common.failure("Nu pot salva intenția de aplicare.", "journal_failed")
	var failure = {}
	for index in data["entries"].size():
		if tree != null: await tree.process_frame
		var entry = data["entries"][index]
		if cancel.get("cancelled", false): failure = Common.failure("Oprit; restaurez modificările lotului.", "cancelled"); break
		var source = _blob_text(id, index, "before")
		if guard.is_valid() and guard.call(entry["path"], source): failure = Common.failure("Au apărut editări nesalvate.", "unsaved_changes"); break
		# Record only directories missing at the actual commit, not at preparation.
		entry["parents"] = []
		var parent = str(entry["path"]).get_base_dir()
		while parent != "res://" and not DirAccess.dir_exists_absolute(parent):
			if FileAccess.file_exists(parent): break
			entry["parents"].append(parent)
			parent = parent.get_base_dir()
		# Write intent is durable before each rename/delete. Recovery uses actual hashes.
		entry["touched"] = entry["before"] != entry["after"]
		if _save(data) != OK: failure = Common.failure("Jurnalul lotului nu poate fi actualizat.", "journal_failed"); break
		var written = _replace(data, index, "before", "after")
		if not written.get("ok", false): failure = written; break
		entry["committed"] = true
		if _save(data) != OK: failure = Common.failure("Scriere efectuată, dar jurnalul nu poate fi actualizat.", "journal_failed"); break
	if failure.is_empty():
		for entry in data["entries"]:
			if _valid_path(entry["path"]).is_empty() or _hash(entry["path"]) != entry["after"]:
				failure = Common.failure("Un membru s-a schimbat înainte de confirmarea lotului.", "restore_conflict")
				break
	if failure.is_empty():
		data["state"] = "applied"
		if _save(data) != OK: failure = Common.failure("Nu pot confirma finalizarea jurnalului.", "journal_failed")
	if not failure.is_empty():
		var restored = _rollback(data, guard)
		busy = false
		return _result(data, str(failure.get("code", "write_failed")), str(failure.get("error", "")) + (" Restaurare incompletă; inspectează conflictele." if not restored else " Lot restaurat."))
	busy = false
	return _result(data)

func _replace(data: Dictionary, index: int, from: String, to: String) -> Dictionary:
	var entry = data["entries"][index]
	var path = _valid_path(entry["path"])
	if path.is_empty() or _hash(path) != entry[from]: return Common.failure("Fișier modificat între timp: " + str(entry["path"]), "restore_conflict")
	if entry[from] == entry[to]: return Common.success(false)
	if entry[to] == "missing":
		return Common.success(true) if DirAccess.remove_absolute(path) == OK else Common.failure("Nu pot șterge fișierul.", "write_failed")
	var blob = _blob(data["id"], index, to)
	if _hash(blob) != entry[to]: return Common.failure("Copia privată nu mai corespunde jurnalului.", "recovery_failed")
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK or not DirAccess.dir_exists_absolute(path.get_base_dir()): return Common.failure("Nu pot crea directorul destinație.", "write_failed")
	var temporary = path + ".ai-" + str(data["id"]) + ".tmp"
	if FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary): return Common.failure("Fișier temporar ocupat; verifică lotul.", "write_failed")
	entry["temporary_owned"] = true
	if _save(data) != OK: return Common.failure("Nu pot salva intenția de scriere temporară.", "journal_failed")
	var error = DirAccess.copy_absolute(ProjectSettings.globalize_path(blob), ProjectSettings.globalize_path(temporary))
	if error == OK and (_hash(temporary) != entry[to] or _hash(path) != entry[from] or _valid_path(path).is_empty()): error = ERR_BUSY
	if error == OK: error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
		return Common.failure("Scriere verificată nereușită: " + error_string(error), "write_failed")
	return Common.success(true)

func _rollback(data: Dictionary, guard: Callable) -> bool:
	data["state"] = "rolling_back"
	if _save(data) != OK:
		data["state"] = "recovery_required"
		return false
	var conflicts = []
	for index in range(data["entries"].size() - 1, -1, -1):
		var entry = data["entries"][index]
		if not entry.get("touched", false): continue
		var path = _valid_path(entry["path"])
		var source = FileAccess.get_file_as_string(path) if _hash(path) in [entry["before"], entry["after"]] and FileAccess.file_exists(path) else ""
		var original = _blob_text(data["id"], index, "before")
		if path.is_empty() or (guard.is_valid() and guard.call(path, source) and guard.call(path, original)):
			conflicts.append({"path": entry["path"], "code": "unsaved_or_invalid_path"}); continue
		var temporary = path + ".ai-" + str(data["id"]) + ".tmp"
		if entry.get("temporary_owned", false) and (FileAccess.file_exists(temporary) or DirAccess.dir_exists_absolute(temporary)):
			if not Common.project_path(temporary).is_empty() and _hash(temporary) in [entry["before"], entry["after"]]:
				if DirAccess.remove_absolute(temporary) != OK: conflicts.append({"path": temporary, "code": "temporary_cleanup_failed"})
			else: conflicts.append({"path": temporary, "code": "temporary_conflict"})
		var current = _hash(path)
		if current == entry["before"]: continue
		if current != entry["after"]:
			conflicts.append({"path": path, "code": "restore_conflict"}); continue
		var restored = _replace(data, index, "after", "before")
		if not restored.get("ok", false): conflicts.append({"path": path, "code": restored.get("code", "write_failed")})
	for entry in data["entries"]:
		if not entry.get("touched", false): continue
		for parent in entry.get("parents", []):
			if not Common.project_path(parent).is_empty() and DirAccess.dir_exists_absolute(parent): DirAccess.remove_absolute(parent) # Only empty directories are removed.
	data["conflicts"] = conflicts
	data["state"] = "rolled_back" if conflicts.is_empty() else "rollback_conflict"
	if _save(data) != OK:
		data["state"] = "recovery_required"
		return false
	return conflicts.is_empty()

func rollback(id: String, guard: Callable = Callable()) -> Dictionary:
	if busy: return Common.failure("Un lot este în curs de modificare.", "changes_busy")
	var data = _load(id)
	if data.is_empty(): return Common.failure("Lot necunoscut sau jurnal invalid.", "invalid_changeset")
	if data["state"] == "prepared": return Common.failure("Lotul este doar pregătit; nu există scrieri de restaurat.", "not_applied")
	if data["state"] == "rolled_back": return _result(data)
	busy = true
	var restored = _rollback(data, guard)
	busy = false
	return _result(data, "" if restored else "restore_conflict", "" if restored else "Unele fișiere necesită verificare; editările ulterioare sunt păstrate.")

func status(id: String = "") -> Dictionary:
	if id.is_empty():
		var summaries = []
		var folder = DirAccess.open(directory)
		if folder != null:
			var recent = []
			for name in folder.get_directories(): recent.append({"name": name, "time": FileAccess.get_modified_time(_manifest_path(name))})
			recent.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] > b["time"])
			for item in recent.slice(0, 64):
				var data = _load(item["name"])
				if not data.is_empty(): summaries.append({"id": data["id"], "state": "interrupted" if data["state"] in ["applying", "rolling_back"] and not busy else data["state"], "created": data.get("created", ""), "files": data["entries"].size()})
			return Common.success({"sets": summaries, "truncated": recent.size() > 64})
		return Common.success({"sets": [], "truncated": false})
	var data = _load(id)
	if data.is_empty(): return Common.failure("Lot necunoscut sau jurnal invalid.", "invalid_changeset")
	return _result(data)

func _result(data: Dictionary, code: String = "", message: String = "") -> Dictionary:
	var files = []
	var previews = []
	var budget = 24000
	var mutated = false
	for index in data["entries"].size():
		var entry = data["entries"][index]
		var current = _hash(entry["path"]) if not _valid_path(entry["path"]).is_empty() else "invalid_path"
		var position = "before" if current == entry["before"] else ("after" if current == entry["after"] else "conflict")
		files.append({"path": entry["path"], "before_sha256": entry["before"], "after_sha256": entry["after"], "position": position, "touched": entry.get("touched", false), "member_index": index})
		mutated = mutated or bool(entry.get("touched", false))
		if budget > 0:
			var before = _blob_text(data["id"], index, "before")
			var after = _blob_text(data["id"], index, "after")
			var compared = Diff.compare(before, after)
			var diff = Diff.unified(entry["path"], compared)
			var bound = mini(budget, 4000)
			previews.append({"path": entry["path"], "exact": compared.get("exact", false), "added": compared.get("added", 0), "removed": compared.get("removed", 0), "diff": diff.left(bound), "truncated": diff.length() > bound, "draft_syntax": entry.get("draft_syntax", {})})
			budget -= mini(bound, diff.length())
	var state = str(data["state"])
	if state in ["applying", "rolling_back"] and not busy: state = "interrupted"
	return {"ok": code.is_empty(), "code": code, "error": message, "project_mutated": mutated, "result": {"id": data["id"], "state": state, "files": files, "change_preview": previews, "preview_truncated": previews.size() < files.size(), "conflicts": data.get("conflicts", []), "recovery_required": state in ["interrupted", "rollback_conflict", "recovery_required"]}}
