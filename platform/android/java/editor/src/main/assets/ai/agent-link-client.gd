extends RefCounted
## Called by Ziva's execute_script in its own subprocess; never blocks the host editor.
var directory = "/run/godot-ai-agent-link"

func request(action: String, arguments: Dictionary = {}) -> Dictionary:
	var connection: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("connection.json")))
	if not connection is Dictionary or not connection.get("available", false):
		return {"ok": false, "code": "agent_unavailable", "error": "Deschide agentul Godot AI în același proiect."}
	var id = Crypto.new().generate_random_bytes(16).hex_encode()
	var owner = str(connection.get("owner", ""))
	var envelope = JSON.stringify({"id": id, "owner": owner, "action": action, "arguments": arguments})
	if envelope.to_utf8_buffer().size() > 64000: return {"ok": false, "code": "request_too_large"}
	var pending = directory.path_join("requests/" + id + ".tmp")
	var target = directory.path_join("requests/" + id + ".json")
	var stream = FileAccess.open(pending, FileAccess.WRITE)
	if stream == null: return {"ok": false, "code": "agent_unavailable"}
	stream.store_string(envelope)
	stream.close()
	if DirAccess.rename_absolute(pending, target) != OK: return {"ok": false, "code": "mailbox_error"}
	var answer = directory.path_join("responses/" + id + ".json")
	var deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(answer):
			var response: Variant = JSON.parse_string(FileAccess.get_file_as_string(answer))
			if response is Dictionary and response.get("id") == id and response.get("owner") == owner and response.get("result") is Dictionary:
				return response["result"]
		OS.delay_msec(50)
	# An unclaimed timed-out command must never execute later without its caller.
	DirAccess.remove_absolute(target)
	return {"ok": false, "code": "agent_timeout", "request_id": id, "error": "Editorul Godot AI nu a răspuns; nu presupune executarea comenzii."}
