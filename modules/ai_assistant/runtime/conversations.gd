@tool
extends RefCounted
static var Common: GDScript
var directory = ""
var index = {"version": 2, "active": "", "items": []}
var last_error = OK

func configure(project_directory: String) -> void:
	directory = project_directory.path_join("conversations")
	var saved: Variant = Common.read_json(directory.path_join("index.json"), {})
	if saved is Dictionary and saved.get("version") == 2 and saved.get("items") is Array:
		index = saved
	else:
		var legacy: Variant = Common.read_json(project_directory.path_join("history.json"), [])
		create("Conversație importată" if legacy is Array and not legacy.is_empty() else "Conversație nouă", legacy if legacy is Array else [])
	if item(str(index.get("active", ""))).is_empty(): create()

func item(id: String) -> Dictionary:
	for entry in index["items"]:
		if entry.get("id") == id: return entry
	return {}

func _path(id: String) -> String:
	return directory.path_join(id + ".json") if not item(id).is_empty() and id.is_valid_filename() else ""

func create(title: String = "Conversație nouă", messages: Array = []) -> String:
	var id = Common.uid()
	index["items"].append({"id": id, "title": title, "favorite": false, "archived": false, "updated": Time.get_unix_time_from_system(), "selection": {}})
	index["active"] = id
	save(messages.duplicate(true))
	return id

func load_active() -> Array:
	var saved: Variant = Common.read_json(_path(str(index["active"])), {})
	var messages: Array = saved.get("messages", []) if saved is Dictionary and saved.get("messages", []) is Array else []
	for message in messages.slice(-50):
		for attachment in message.get("attachments", []):
			var id = str(attachment.get("cache_id", ""))
			if id.is_valid_filename() and not id.is_empty():
				var path = directory.path_join("attachments").path_join(id + ".png")
				var file = FileAccess.open(path, FileAccess.READ)
				if file != null and file.get_length() <= 2 * 1024 * 1024: attachment["data"] = Marshalls.raw_to_base64(file.get_buffer(file.get_length()))
	return messages

func select(id: String) -> bool:
	if item(id).is_empty(): return false
	index["active"] = id
	_flush()
	return true

func save(messages: Array, selection: Dictionary = {}) -> Error:
	var entry = item(str(index["active"]))
	if entry.is_empty(): return ERR_INVALID_DATA
	entry["updated"] = Time.get_unix_time_from_system()
	if not selection.is_empty(): entry["selection"] = selection.duplicate(true)
	if entry["title"] == "Conversație nouă":
		for message in messages:
			if message.get("role") == "user":
				entry["title"] = str(message.get("content", "")).replace("\n", " ").left(64)
				break
	var persisted = messages.duplicate(true)
	for index in range(messages.size()):
		var originals: Array = messages[index].get("attachments", [])
		var copies: Array = persisted[index].get("attachments", [])
		for attachment_index in range(originals.size()):
			var attachment: Dictionary = originals[attachment_index]
			if attachment.has("data"):
				if attachment.has("file_id"):
					copies[attachment_index].erase("data")
					continue
				if not attachment.has("cache_id"): attachment["cache_id"] = Common.uid()
				var id = str(attachment["cache_id"])
				if not id.is_valid_filename(): return ERR_INVALID_DATA
				var path = directory.path_join("attachments").path_join(id + ".png")
				if not FileAccess.file_exists(path):
					DirAccess.make_dir_recursive_absolute(path.get_base_dir())
					var file = FileAccess.open(path, FileAccess.WRITE)
					if file == null: return ERR_CANT_CREATE
					file.store_buffer(Marshalls.base64_to_raw(str(attachment["data"])))
				copies[attachment_index]["cache_id"] = id
				copies[attachment_index].erase("data")
	last_error = Common.atomic_json(_path(str(entry["id"])), {"version": 2, "messages": persisted})
	if last_error == OK: _flush()
	return last_error

func update(id: String, changes: Dictionary) -> void:
	var entry = item(id)
	if entry.is_empty(): return
	for key in ["title", "favorite", "archived"]:
		if changes.has(key): entry[key] = changes[key]
	_flush()

func fork_at(message_id: String) -> String:
	var messages = []
	for message in load_active():
		messages.append(message.duplicate(true))
		if message.get("id") == message_id: break
	# A fork ends at a visible message, never at an unresolved tool call.
	if not messages.is_empty():
		for key in ["tool_calls", "provider_items", "provider_blocks", "reasoning_content"]: messages[-1].erase(key)
	var selection = item(str(index["active"])).get("selection", {}).duplicate(true)
	var id = create("Ramură · " + str(item(str(index["active"])).get("title", "Chat")).left(80), messages)
	save(messages, selection)
	return id

func remove(id: String) -> void:
	var path = _path(id)
	if path.is_empty() or not item(id).get("archived", false): return
	if DirAccess.remove_absolute(path) != OK: return
	index["items"] = index["items"].filter(func(entry: Dictionary) -> bool: return entry["id"] != id)
	if index["active"] == id: create()
	_flush()

func listing(query: String = "", archived: bool = false) -> Array:
	var result = index["items"].filter(func(entry: Dictionary) -> bool: return entry.get("archived", false) == archived and (query.is_empty() or query.to_lower() in str(entry["title"]).to_lower()))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["updated"] > b["updated"] if a.get("favorite", false) == b.get("favorite", false) else a.get("favorite", false))
	return result

func markdown() -> String:
	var text = "# " + str(item(str(index["active"])).get("title", "Chat")) + "\n"
	for message in load_active():
		if message.get("role") in ["user", "assistant"]:
			text += "\n## " + ("Tu" if message["role"] == "user" else str(message.get("origin_label", "AI"))) + "\n\n" + str(message.get("content", "")) + "\n"
	return text

func _flush() -> void:
	last_error = Common.atomic_json(directory.path_join("index.json"), index)
