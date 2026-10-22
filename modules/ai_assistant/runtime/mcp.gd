@tool
extends RefCounted

static var Common: GDScript
static var Transport: GDScript
static var ToolRegistry: GDScript
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
			tool_index[name] = {"server": server.duplicate(true), "original": tool["name"], "risk": definition["risk"], "parameters": definition["parameters"], "output_schema": tool.get("outputSchema", {})}
		cursor = str(payload.get("nextCursor", ""))
		if cursor.is_empty(): return Common.success(tools)
	return Common.failure("Catalogul MCP depășește limita de paginare.")

func call_tool(name: String, args: Dictionary, mode: int, full_control: bool, cancel: Dictionary) -> Dictionary:
	if not tool_index.has(name): return Common.failure("Instrument MCP necunoscut.")
	var tool: Dictionary = tool_index[name]
	if tool["risk"] != "read" and (mode in [0, 3] or not full_control): return Common.failure("Instrumentul MCP necesită permisiune de modificare.", "permission_denied")
	var validation = ToolRegistry.validate(tool, args)
	if not validation.get("ok", false): return validation
	var response = await _rpc(tool["server"], "tools/call", {"name": tool["original"], "arguments": args}, cancel)
	return normalize_result(response.get("result"), tool.get("output_schema", {})) if response.get("ok", false) else response

static func normalize_result(payload: Variant, output_schema: Variant = {}) -> Dictionary:
	if not payload is Dictionary or not payload.get("content", []) is Array: return Common.failure("Rezultat MCP invalid.", "invalid_mcp_result")
	var content = []
	var text: Array[String] = []
	var images = []
	for block in payload.get("content", []):
		if not block is Dictionary: return Common.failure("Bloc de rezultat MCP invalid.", "invalid_mcp_result")
		match str(block.get("type", "")):
			"text":
				if not block.get("text") is String: return Common.failure("Text MCP invalid.", "invalid_mcp_result")
				text.append(str(block["text"]))
				content.append({"type": "text", "text": block["text"]})
			"image":
				var mime = str(block.get("mimeType", ""))
				var data = str(block.get("data", ""))
				if mime not in ["image/png", "image/jpeg", "image/webp"] or data.length() > 2800000 or data.is_empty() or images.size() >= 4: return Common.failure("Imagine MCP nesuportată sau prea mare.", "invalid_mcp_result")
				var bytes = Marshalls.base64_to_raw(data)
				var image = Image.new()
				var error = image.load_png_from_buffer(bytes) if mime == "image/png" else (image.load_jpg_from_buffer(bytes) if mime == "image/jpeg" else image.load_webp_from_buffer(bytes))
				if error != OK: return Common.failure("Imaginea MCP nu poate fi decodată.", "invalid_mcp_result")
				images.append({"name": "mcp_%s" % images.size(), "mimeType": mime, "data": data})
				content.append({"type": "image", "mimeType": mime, "width": image.get_width(), "height": image.get_height()})
			"resource_link": content.append({"type": "resource_link", "uri": str(block.get("uri", "")), "name": str(block.get("name", "")), "description": str(block.get("description", ""))})
			"resource":
				var resource: Variant = block.get("resource", {})
				if not resource is Dictionary or not resource.get("text") is String: return Common.failure("Resursa MCP binară necesită un adaptor dedicat.", "unsupported_mcp_content")
				content.append({"type": "resource", "uri": str(resource.get("uri", "")), "text": resource["text"], "mimeType": str(resource.get("mimeType", "text/plain"))})
			_: return Common.failure("Tip de conținut MCP nesuportat: " + str(block.get("type", "")), "unsupported_mcp_content")
	var result = {"content": content, "text": "\n".join(text)}
	var failed = bool(payload.get("isError", false))
	if payload.has("structuredContent"):
		if not payload["structuredContent"] is Dictionary: return Common.failure("structuredContent MCP trebuie să fie obiect.", "invalid_mcp_result")
		if output_schema != {} and not failed:
			var validation = ToolRegistry.validate({"parameters": output_schema}, payload["structuredContent"])
			if not validation.get("ok", false): return Common.failure("Rezultatul MCP nu corespunde outputSchema: " + str(validation.get("error", "")), "invalid_mcp_result")
		result["structuredContent"] = payload["structuredContent"]
	elif output_schema != {} and not failed: return Common.failure("Lipsește structuredContent cerut de outputSchema.", "invalid_mcp_result")
	if failed: return {"ok": false, "code": "mcp_tool_error", "error": result["text"] if not result["text"].is_empty() else "Serverul MCP a raportat o eroare de execuție.", "result": result, "images": images}
	return {"ok": true, "result": result, "images": images}

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
