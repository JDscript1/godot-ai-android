@tool
extends RefCounted

static var Common: GDScript
static var Transport: GDScript
var transport: RefCounted
var vault: RefCounted
var sessions: Dictionary = {}
var tool_index: Dictionary = {}

func _init(node: Node = null, secret_store: RefCounted = null) -> void:
	transport = Transport.new(node)
	vault = secret_store

func discover(server: Dictionary, cancel: Dictionary = {}) -> Dictionary:
	var id = str(server["id"])
	if server.get("transport", "http") == "stdio":
		return Common.failure("Serverele stdio se configurează în companion și se conectează prin URL-ul HTTP publicat de acesta.")
	var initialized = await _rpc(server, "initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "godot-ai-android", "version": Common.VERSION}}, cancel, false, false)
	if not initialized.get("ok", false): return initialized
	var notification = await _rpc(server, "notifications/initialized", {}, cancel, true)
	if not notification.get("ok", false): return notification
	var tools = []
	var cursor = ""
	for _page in range(20):
		var result = await _rpc(server, "tools/list", {} if cursor.is_empty() else {"cursor": cursor}, cancel)
		if not result.get("ok", false): return result
		var payload: Dictionary = result["result"]
		for tool in payload.get("tools", []):
			if not tool is Dictionary or not tool.has("name") or not tool.get("inputSchema", {}) is Dictionary: continue
			var name = "mcp_" + id.sha256_text().left(8) + "_" + str(tool["name"]).validate_node_name().replace(" ", "_").left(40)
			if tool_index.has(name) and tool_index[name]["original"] != tool["name"]: return Common.failure("Nume MCP în conflict după normalizare.")
			var read_only = bool(server.get("trusted_read", false)) and bool(tool.get("annotations", {}).get("readOnlyHint", false))
			var definition = {"name": name, "description": str(tool.get("description", tool["name"])).left(2000), "parameters": tool.get("inputSchema", Common.schema()), "risk": "read" if read_only else "external"}
			tools.append(definition)
			tool_index[name] = {"server": server.duplicate(true), "original": tool["name"], "risk": definition["risk"]}
		cursor = str(payload.get("nextCursor", ""))
		if cursor.is_empty(): return Common.success(tools)
	return Common.failure("Catalogul MCP depășește limita de paginare.")

func call_tool(name: String, args: Dictionary, mode: int, full_control: bool, cancel: Dictionary) -> Dictionary:
	if not tool_index.has(name): return Common.failure("Instrument MCP necunoscut.")
	var tool: Dictionary = tool_index[name]
	if tool["risk"] != "read" and (mode == 0 or not full_control): return Common.failure("Instrumentul MCP necesită permisiune de modificare.", "permission_denied")
	return await _rpc(tool["server"], "tools/call", {"name": tool["original"], "arguments": args}, cancel)

func _rpc(server: Dictionary, method: String, params: Dictionary, cancel: Dictionary, notification: bool = false, use_session: bool = true) -> Dictionary:
	var id = Common.uid()
	var body = {"jsonrpc": "2.0", "method": method, "params": params}
	if not notification: body["id"] = id
	var headers = PackedStringArray(["Accept: application/json, text/event-stream", "MCP-Protocol-Version: 2025-11-25"])
	var secret = vault.read(str(server["id"])) if vault != null else ""
	if not secret.is_empty(): headers.append("Authorization: Bearer " + secret)
	var server_id = str(server["id"])
	if use_session and sessions.has(server_id): headers.append("Mcp-Session-Id: " + str(sessions[server_id]))
	var result = await transport.request(str(server["url"]), HTTPClient.METHOD_POST, headers, body, {"allow_http": server.get("allow_http", false), "cancel": cancel})
	if not result.get("ok", false):
		if result.get("status", 0) in [401, 403]: return Common.failure("Serverul MCP necesită autentificare sau reconectare.", "reauthentication_required")
		if result.get("status", 0) == 404: sessions.erase(server_id)
		return result
	for header in result.get("headers", {}):
		if str(header).to_lower() == "mcp-session-id": sessions[server_id] = result["headers"][header]
	if notification: return Common.success()
	var reply: Variant = result.get("json")
	if not reply is Dictionary:
		for event in result.get("events", []):
			if str(event.get("id", "")) == id: reply = event
	if not reply is Dictionary or str(reply.get("id", "")) != id: return Common.failure("Răspuns MCP incomplet sau cu identificator diferit.")
	if reply.has("error"): return Common.failure(JSON.stringify(reply["error"]).left(2000), "mcp_error")
	return Common.success(reply.get("result", {}))
