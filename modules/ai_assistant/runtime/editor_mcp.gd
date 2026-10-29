@tool
extends Node
## Project-scoped Streamable HTTP MCP endpoint. No model, planner or provider state.
static var Common: GDScript
static var ToolRegistry: GDScript
signal tool_finished(name: String, ok: bool, code: String)
const HEADER_LIMIT = 16384
const BODY_LIMIT = 1048576
const RESPONSE_LIMIT = 2097152
const VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26"]
var listener = TCPServer.new()
var clients: Array = []
var sessions: Dictionary = {}
var definitions: Dictionary = {}
var execute_tool: Callable
var secret = ""
var port = 0
var read_only = false
var busy = false
var initialized_clients = 0
var cached_bytes = 0
var discovered_pages = 0
var completed_calls = 0
var last_tool = ""
var last_ok = false
var active_cancel: Dictionary = {}

func start(catalog: Array, executor: Callable) -> Dictionary:
	if listener.is_listening(): return Common.failure("Conexiunea MCP este deja pornită.", "already_running")
	if not executor.is_valid(): return Common.failure("Executor MCP indisponibil.")
	var bytes = Crypto.new().generate_random_bytes(32)
	if bytes.size() != 32: return Common.failure("Autentificarea locală nu a putut fi pregătită.")
	if listener.listen(0, "127.0.0.1") != OK: return Common.failure("Portul local MCP nu poate fi deschis.")
	secret = bytes.hex_encode()
	port = listener.get_local_port()
	definitions.clear()
	for item in catalog: definitions[str(item["name"])] = item.duplicate(true)
	execute_tool = executor
	initialized_clients = 0
	cached_bytes = 0
	discovered_pages = 0
	completed_calls = 0
	last_tool = ""
	set_process(true)
	return Common.success({"url": "http://127.0.0.1:%d/mcp" % port, "token": secret})

func stop() -> void:
	listener.stop()
	active_cancel["cancelled"] = true
	for client in clients: client["peer"].disconnect_from_host()
	clients.clear()
	sessions.clear()
	initialized_clients = 0
	cached_bytes = 0
	secret = ""
	port = 0
	set_process(false)

func _exit_tree() -> void: stop()

func snapshot() -> Dictionary:
	return {"listening": listener.is_listening(), "clients_initialized": initialized_clients, "discovered_pages": discovered_pages, "tool_calls": completed_calls, "last_tool": last_tool, "last_ok": last_ok, "busy": busy, "read_only": read_only}

func _process(_delta: float) -> void:
	for id in sessions.keys():
		if Time.get_ticks_msec() - sessions[id]["accessed"] > 1800000 and sessions[id]["pending"].is_empty(): _remove_session(id)
	while listener.is_connection_available():
		var peer = listener.take_connection()
		if clients.size() >= 8: peer.disconnect_from_host(); continue
		clients.append({"peer": peer, "input": PackedByteArray(), "output": PackedByteArray(), "sent": 0, "header": {}, "body_at": -1, "length": 0, "started": Time.get_ticks_msec(), "waiting": false, "done": false})
	for client in clients.duplicate():
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			clients.erase(client)
			continue
		if not client["output"].is_empty():
			if Time.get_ticks_msec() - client["started"] > 15000: peer.disconnect_from_host(); clients.erase(client); continue
			var written = peer.put_partial_data(client["output"].slice(client["sent"]))
			if written[0] != OK: peer.disconnect_from_host(); clients.erase(client); continue
			client["sent"] += written[1]
			if client["sent"] == client["output"].size(): peer.disconnect_from_host(); clients.erase(client)
			continue
		if client["waiting"] or client["done"]: continue
		if Time.get_ticks_msec() - client["started"] > 15000: _reply(client, 408); continue
		var available = peer.get_available_bytes()
		if available <= 0: continue
		var chunk = peer.get_data(mini(available, 65536))
		if chunk[0] != OK: peer.disconnect_from_host(); clients.erase(client); continue
		client["input"].append_array(chunk[1])
		if client["body_at"] < 0:
			var boundary = _header_end(client["input"])
			if boundary < 0:
				if client["input"].size() > HEADER_LIMIT: _reply(client, 431)
				continue
			if boundary > HEADER_LIMIT: _reply(client, 431); continue
			if not _headers(client, boundary): continue
		if client["input"].size() - client["body_at"] > client["length"]: _reply(client, 400); continue
		if client["input"].size() - client["body_at"] == client["length"]:
			client["waiting"] = true
			_dispatch(client)

func _header_end(bytes: PackedByteArray) -> int:
	for i in range(maxi(0, bytes.size() - 65540), bytes.size() - 3):
		if bytes[i] == 13 and bytes[i + 1] == 10 and bytes[i + 2] == 13 and bytes[i + 3] == 10: return i
	return -1

func _headers(client: Dictionary, boundary: int) -> bool:
	var bytes: PackedByteArray = client["input"].slice(0, boundary)
	for byte in bytes:
		if byte != 13 and byte != 10 and (byte < 32 or byte > 126): _reply(client, 400); return false
	var lines = bytes.get_string_from_ascii().split("\r\n")
	var request = lines[0].split(" ")
	if request.size() != 3 or request[2] != "HTTP/1.1": _reply(client, 400); return false
	var headers: Dictionary = {}
	for line in lines.slice(1):
		var colon = line.find(":")
		if colon <= 0 or line.begins_with(" "): _reply(client, 400); return false
		var key = line.left(colon).to_lower()
		if headers.has(key) or key != key.strip_edges(): _reply(client, 400); return false
		headers[key] = line.substr(colon + 1).strip_edges()
	var authority = "127.0.0.1:%d" % port
	if headers.get("host", "") != authority: _reply(client, 403); return false
	if headers.has("origin") and headers["origin"] != "http://" + authority: _reply(client, 403); return false
	if not Crypto.new().constant_time_compare(("Bearer " + secret).to_utf8_buffer(), str(headers.get("authorization", "")).to_utf8_buffer()): _reply(client, 401); return false
	if request[1] != "/mcp": _reply(client, 404); return false
	if request[0] not in ["POST", "DELETE"]: _reply(client, 405); return false
	if headers.has("transfer-encoding"): _reply(client, 400); return false
	var length = str(headers.get("content-length", "0"))
	if not length.is_valid_int() or length.begins_with("-") or length.begins_with("+"): _reply(client, 400); return false
	if int(length) > BODY_LIMIT: _reply(client, 413); return false
	if request[0] == "POST" and (int(length) == 0 or str(headers.get("content-type", "")).get_slice(";", 0).strip_edges() != "application/json"): _reply(client, 415); return false
	client["header"] = headers
	client["method"] = request[0]
	client["length"] = int(length)
	client["body_at"] = boundary + 4
	return true

func _dispatch(client: Dictionary) -> void:
	var session_id = str(client["header"].get("mcp-session-id", ""))
	if client["method"] == "DELETE":
		if not sessions.has(session_id): _reply(client, 404); return
		_cancel_session(session_id)
		_remove_session(session_id)
		_reply(client, 200)
		return
	var parser = JSON.new()
	if parser.parse(client["input"].slice(client["body_at"]).get_string_from_utf8()) != OK:
		_reply(client, 200, _error(null, -32700, "Parse error")); return
	var input: Variant = parser.data
	if input is Array:
		if input.is_empty() or input.size() > 16 or not sessions.has(session_id) or sessions[session_id]["version"] != "2025-03-26":
			_reply(client, 200, _error(null, -32600, "Invalid batch")); return
		var results: Array = []
		for message in input:
			var result: Dictionary = await _rpc(message, session_id)
			if not result.is_empty(): results.append(result)
		_reply(client, 202 if results.is_empty() else 200, null if results.is_empty() else results)
		return
	if input is Dictionary and input.get("method") == "initialize":
		if not _valid_request(input) or not input.has("id") or not input.get("params") is Dictionary:
			_reply(client, 200, _error(input.get("id"), -32600, "Invalid initialize request")); return
		if sessions.size() >= 8: _reply(client, 503); return
		var version = str(input["params"].get("protocolVersion", ""))
		if version not in VERSIONS: version = VERSIONS[0]
		session_id = Crypto.new().generate_random_bytes(24).hex_encode()
		sessions[session_id] = {"version": version, "initialized": false, "calls": {}, "pending": {}, "bytes": 0, "accessed": Time.get_ticks_msec()}
		_reply(client, 200, {"jsonrpc": "2.0", "id": input["id"], "result": {"protocolVersion": version, "capabilities": {"tools": {"listChanged": false}}, "serverInfo": {"name": "godot-ai-editor", "version": "1.0.0"}, "instructions": "Use these tools for the live Android Godot editor, scenes, files, diagnostics and panels. This is independent of the built-in agent. Inspect errors and actual results. Stop temporary playtests after verification. Project shell changes do not provide native Undo."}}, session_id)
		return
	if not sessions.has(session_id): _reply(client, 404); return
	sessions[session_id]["accessed"] = Time.get_ticks_msec()
	var protocol = str(client["header"].get("mcp-protocol-version", sessions[session_id]["version"]))
	if protocol != sessions[session_id]["version"]: _reply(client, 400); return
	var result: Dictionary = await _rpc(input, session_id)
	_reply(client, 202 if result.is_empty() else 200, null if result.is_empty() else result)

func _valid_request(message: Variant) -> bool:
	if not message is Dictionary or message.get("jsonrpc") != "2.0" or not message.get("method") is String: return false
	if message.has("id") and not (message["id"] is String or message["id"] is float or message["id"] is int): return false
	return not message.has("params") or message["params"] is Dictionary

func _rpc(message: Variant, session_id: String) -> Dictionary:
	if not _valid_request(message): return _error(message.get("id") if message is Dictionary else null, -32600, "Invalid Request")
	var session: Dictionary = sessions.get(session_id, {})
	if session.is_empty(): return _error(message.get("id"), -32600, "Session closed")
	var method: String = message["method"]
	var args: Dictionary = message.get("params", {})
	if not message.has("id"):
		if method == "notifications/initialized" and not session["initialized"]:
			session["initialized"] = true
			initialized_clients += 1
		elif method == "notifications/cancelled":
			var key = JSON.stringify(args.get("requestId"))
			if session["pending"].has(key): session["pending"][key]["cancelled"] = true
		return {}
	var id: Variant = message["id"]
	if method == "ping": return {"jsonrpc": "2.0", "id": id, "result": {}}
	if not session["initialized"]: return _error(id, -32000, "Initialize the session first")
	if method == "tools/list":
		discovered_pages += 1
		var offset = str(args.get("cursor", "0"))
		if not offset.is_valid_int() or int(offset) < 0 or int(offset) > definitions.size(): return _error(id, -32602, "Invalid cursor")
		var catalog: Array = []
		for item in definitions.values().slice(int(offset), int(offset) + 20):
			catalog.append({"name": item["name"], "description": item["description"], "inputSchema": item["parameters"], "annotations": {"readOnlyHint": item.get("risk", "write") == "read", "openWorldHint": false}})
		var listing = {"tools": catalog}
		if int(offset) + catalog.size() < definitions.size(): listing["nextCursor"] = str(int(offset) + catalog.size())
		return {"jsonrpc": "2.0", "id": id, "result": listing}
	if method != "tools/call": return _error(id, -32601, "Method not found")
	var name = str(args.get("name", ""))
	if not definitions.has(name): return _error(id, -32602, "Unknown tool")
	if not args.get("arguments", {}) is Dictionary: return _error(id, -32602, "Invalid arguments")
	var validation = ToolRegistry.validate(definitions[name], args.get("arguments", {}))
	if not validation.get("ok", false): return _error(id, -32602, str(validation.get("error", "Invalid arguments")))
	if read_only and definitions[name].get("risk", "write") != "read": return _tool_result(id, Common.failure("Conexiunea Ziva este doar pentru citire.", "read_only"))
	var key = JSON.stringify(id)
	var fingerprint = JSON.stringify(args, "", true).sha256_text()
	if session["calls"].has(key):
		var cached: Dictionary = session["calls"][key]
		return cached["response"] if cached["fingerprint"] == fingerprint else _error(id, -32600, "Request ID already used")
	if busy: return _tool_result(id, Common.failure("Editorul execută deja un instrument MCP. Așteaptă rezultatul.", "editor_busy"))
	if session["calls"].size() >= 256 or cached_bytes >= 8388608: return _error(id, -32000, "Session request cache full; initialize a new session")
	busy = true
	active_cancel = {"cancelled": false}
	session["pending"][key] = active_cancel
	var result: Dictionary = await execute_tool.call(name, args.get("arguments", {}), active_cancel)
	session["pending"].erase(key)
	busy = false
	completed_calls += 1
	last_tool = name
	last_ok = bool(result.get("ok", false))
	var response = _tool_result(id, result)
	session["calls"][key] = {"fingerprint": fingerprint, "response": response}
	var size = JSON.stringify(response).to_utf8_buffer().size()
	session["bytes"] += size
	if sessions.has(session_id): cached_bytes += size
	tool_finished.emit(name, last_ok, str(result.get("code", "")))
	return response

func _cancel_session(id: String) -> void:
	for cancel in sessions[id]["pending"].values(): cancel["cancelled"] = true

func _remove_session(id: String) -> void:
	if sessions[id]["initialized"]: initialized_clients -= 1
	cached_bytes -= sessions[id]["bytes"]
	sessions.erase(id)

func _tool_result(id: Variant, value: Dictionary) -> Dictionary:
	var text = JSON.stringify(value)
	var too_large = text.to_utf8_buffer().size() > RESPONSE_LIMIT / 2
	if too_large: text = JSON.stringify(Common.failure("Rezultat prea mare; cere un interval sau un filtru mai restrâns.", "result_too_large"))
	return {"jsonrpc": "2.0", "id": id, "result": {"content": [{"type": "text", "text": text}], "isError": not value.get("ok", false) or too_large}}

func _error(id: Variant, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message.left(1000)}}

func _reply(client: Dictionary, status: int, body: Variant = null, session: String = "") -> void:
	if client["done"]: return
	client["done"] = true
	client["started"] = Time.get_ticks_msec()
	var encoded = "" if body == null else JSON.stringify(body)
	var header = "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n" % [status, "OK" if status in [200, 202] else "Request rejected", encoded.to_utf8_buffer().size()]
	if not session.is_empty(): header += "Mcp-Session-Id: " + session + "\r\n"
	if status == 405: header += "Allow: POST, DELETE\r\n"
	client["output"] = (header + "\r\n" + encoded).to_utf8_buffer()
