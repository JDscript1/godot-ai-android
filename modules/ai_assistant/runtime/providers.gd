@tool
extends RefCounted

static var Common: GDScript
static var Transport: GDScript

const CATALOG = [
	{"id": "openai", "name": "OpenAI", "kind": "responses", "url": "https://api.openai.com/v1", "prefix": "sk-proj-"},
	{"id": "anthropic", "name": "Anthropic Claude", "kind": "anthropic", "url": "https://api.anthropic.com/v1", "prefix": "sk-ant-"},
	{"id": "gemini", "name": "Google Gemini", "kind": "gemini", "url": "https://generativelanguage.googleapis.com/v1beta", "prefix": "AIza"},
	{"id": "deepseek", "name": "DeepSeek", "kind": "chat", "url": "https://api.deepseek.com", "prefix": ""},
	{"id": "openrouter", "name": "OpenRouter", "kind": "chat", "url": "https://openrouter.ai/api/v1", "prefix": "sk-or-v1-"},
	{"id": "qwen", "name": "Qwen International", "kind": "chat", "url": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", "prefix": ""},
	{"id": "qwen-cn", "name": "Qwen China", "kind": "chat", "url": "https://dashscope.aliyuncs.com/compatible-mode/v1", "prefix": ""},
	{"id": "kimi", "name": "Kimi / Moonshot", "kind": "chat", "url": "https://api.moonshot.ai/v1", "prefix": ""},
	{"id": "mistral", "name": "Mistral", "kind": "chat", "url": "https://api.mistral.ai/v1", "prefix": ""},
	{"id": "groq", "name": "Groq", "kind": "chat", "url": "https://api.groq.com/openai/v1", "prefix": "gsk_"},
	{"id": "xai", "name": "xAI", "kind": "chat", "url": "https://api.x.ai/v1", "prefix": "xai-"},
	{"id": "zai", "name": "Z.AI / GLM", "kind": "chat", "url": "https://api.z.ai/api/paas/v4", "prefix": ""},
	{"id": "minimax", "name": "MiniMax", "kind": "chat", "url": "https://api.minimax.io/v1", "prefix": ""},
	{"id": "nvidia", "name": "NVIDIA NIM", "kind": "chat", "url": "https://integrate.api.nvidia.com/v1", "prefix": "nvapi-"},
	{"id": "siliconflow", "name": "SiliconFlow", "kind": "chat", "url": "https://api.siliconflow.cn/v1", "prefix": ""},
	{"id": "ollama", "name": "Ollama", "kind": "chat", "url": "http://127.0.0.1:11434/v1", "prefix": "", "local": true},
	{"id": "lmstudio", "name": "LM Studio", "kind": "chat", "url": "http://127.0.0.1:1234/v1", "prefix": "", "local": true},
	{"id": "llamacpp", "name": "llama.cpp", "kind": "chat", "url": "http://127.0.0.1:8080/v1", "prefix": "", "local": true},
	{"id": "custom", "name": "OpenAI-compatible", "kind": "chat", "url": "", "prefix": ""},
]

var transport: RefCounted
var vault: RefCounted

func _init(node: Node = null, secret_store: RefCounted = null) -> void:
	transport = Transport.new(node)
	vault = secret_store

static func detect(key: String, issuer: String = "") -> Dictionary:
	var normalized = key.strip_edges()
	var assignment = normalized.find("=")
	if assignment > 0 and normalized.substr(0, assignment).ends_with("_API_KEY"):
		var label = normalized.substr(0, assignment).trim_prefix("export ").to_lower().trim_suffix("_api_key")
		normalized = normalized.substr(assignment + 1).strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
		if issuer.is_empty(): issuer = label
	for entry in CATALOG:
		if (not issuer.is_empty() and entry["id"] == issuer) or (issuer.is_empty() and not str(entry["prefix"]).is_empty() and normalized.begins_with(str(entry["prefix"]))):
			return {"ok": true, "profile": entry.duplicate(true), "secret": normalized}
	return Common.failure("Cheia este ambiguă. Alege furnizorul sau introdu adresa API.", "provider_ambiguous")

func headers(profile: Dictionary) -> PackedStringArray:
	var secret = vault.read(str(profile["id"])) if vault != null else ""
	if profile.get("kind") == "siwc":
		var tokens: Variant = JSON.parse_string(secret)
		secret = str(tokens.get("access_token", "")) if tokens is Dictionary else ""
	var result = PackedStringArray()
	match str(profile.get("kind", "chat")):
		"anthropic":
			result.append("anthropic-version: 2023-06-01")
			if not secret.is_empty(): result.append("x-api-key: " + secret)
		"gemini":
			if not secret.is_empty(): result.append("x-goog-api-key: " + secret)
		_:
			if not secret.is_empty(): result.append("Authorization: Bearer " + secret)
	return result

func list_models(profile: Dictionary, cancel: Dictionary = {}) -> Dictionary:
	var url = str(profile.get("url", "")).trim_suffix("/")
	var result = await transport.request(url + "/models", HTTPClient.METHOD_GET, headers(profile), null, {"allow_http": profile.get("allow_http", false), "cancel": cancel})
	if not result.get("ok", false): return result
	var payload = result.get("json")
	if not payload is Dictionary: return Common.failure("Catalogul de modele nu este JSON valid.")
	var models = []
	var entries: Array = payload.get("data", payload.get("models", []))
	for item in entries:
		if not item is Dictionary: continue
		if profile.get("kind") == "siwc" and item.get("visibility", "list") != "list": continue
		var id = str(item.get("id", item.get("slug", item.get("name", "")))).trim_prefix("models/")
		if id.is_empty(): continue
		if item.has("supportedGenerationMethods") and not "generateContent" in item["supportedGenerationMethods"]: continue
		if str(item.get("type", "")) in ["embedding", "embeddings"]: continue
		var capabilities: Dictionary = item.get("capabilities", {}).duplicate(true) if item.get("capabilities", {}) is Dictionary else {}
		var supported: Dictionary = item.get("supported_parameters", {}) if item.get("supported_parameters", {}) is Dictionary else {}
		if item.get("supported_parameters", null) is Array: capabilities["tools"] = "tools" in item["supported_parameters"]
		if supported.has("tools"): capabilities["tools"] = supported["tools"]
		models.append({"id": id, "name": str(item.get("display_name", item.get("displayName", item.get("name", id)))), "capabilities": capabilities, "context": item.get("context_window", item.get("inputTokenLimit", 0)), "efforts": item.get("effort", {}).get("supported_levels", []) if item.get("effort", {}) is Dictionary else [], "source": "live"})
	return Common.success(models)

func ollama_capabilities(profile: Dictionary, model: String, cancel: Dictionary = {}) -> Dictionary:
	var root = str(profile["url"]).trim_suffix("/").trim_suffix("/v1")
	return await transport.request(root + "/api/show", HTTPClient.METHOD_POST, headers(profile), {"model": model}, {"allow_http": profile.get("allow_http", false), "cancel": cancel})

func complete(profile: Dictionary, messages: Array, tools: Array, model: String, effort: String, cancel: Dictionary, on_delta: Callable = Callable()) -> Dictionary:
	var kind = str(profile.get("kind", "chat"))
	var wire = build_request(kind, messages, tools, model, effort)
	var path = str(wire["path"])
	var collected = {"text": "", "reasoning": "", "calls": {}, "blocks": {}, "items": [], "terminal": false, "finish": "", "usage": {}, "error": ""}
	var receive = func(event: Dictionary) -> void:
		var before = str(collected["text"])
		consume_event(kind, event, collected)
		var delta = str(collected["text"]).substr(before.length())
		if not delta.is_empty() and on_delta.is_valid(): on_delta.call(delta)
	var result = await transport.request(str(profile["url"]).trim_suffix("/") + path, HTTPClient.METHOD_POST, headers(profile), wire["body"], {"allow_http": profile.get("allow_http", false), "cancel": cancel, "on_event": receive})
	if not result.get("ok", false): return result
	if not str(collected["error"]).is_empty(): return Common.failure(str(collected["error"]), "provider_error")
	if not collected["terminal"]: return Common.failure("Fluxul s-a încheiat înaintea confirmării de finalizare.", "incomplete_stream")
	var calls = []
	for index in collected["calls"]:
		var item: Dictionary = collected["calls"][index]
		var arguments: Variant = item.get("arguments", {})
		if arguments is String: arguments = JSON.parse_string(arguments)
		if not arguments is Dictionary: return Common.failure("Modelul a produs argumente JSON invalide.", "invalid_tool_arguments")
		calls.append({"id": str(item.get("id", Common.uid())), "name": str(item.get("name", "")), "arguments": arguments})
	var message = {"role": "assistant", "content": str(collected["text"]), "tool_calls": calls}
	if not str(collected["reasoning"]).is_empty(): message["reasoning_content"] = collected["reasoning"]
	if not collected["items"].is_empty(): message["provider_items"] = collected["items"]
	if not collected["blocks"].is_empty(): message["provider_blocks"] = collected["blocks"].values()
	return {"ok": true, "message": message, "calls": calls, "usage": collected["usage"], "finish": collected["finish"]}

static func build_request(kind: String, messages: Array, tools: Array, model: String, effort: String = "") -> Dictionary:
	var system = []
	for message in messages:
		if message.get("role") == "system": system.append(str(message.get("content", "")))
	var body: Dictionary = {"model": model, "stream": true}
	var path = "/chat/completions"
	if kind in ["responses", "siwc"]:
		path = "/responses"
		body["store"] = false
		body["instructions"] = "\n\n".join(system)
		var input = []
		for message in messages:
			var role = str(message.get("role", "user"))
			if role == "system": continue
			if role == "tool":
				input.append({"type": "function_call_output", "call_id": message["tool_call_id"], "output": str(message["content"])})
			elif role == "assistant" and message.has("provider_items"):
				input.append_array(message["provider_items"])
			else:
				input.append({"role": role, "content": str(message.get("content", ""))})
				for call in message.get("tool_calls", []): input.append({"type": "function_call", "call_id": call["id"], "name": call["name"], "arguments": JSON.stringify(call["arguments"])})
		body["input"] = input
		if not tools.is_empty():
			var definitions = []
			for tool in tools: definitions.append({"type": "function", "name": tool["name"], "description": tool["description"], "parameters": tool["parameters"], "strict": false})
			body["tools"] = [{"type": "namespace", "name": "godot", "description": "Godot editor and configured external tools", "tools": definitions}] if kind == "siwc" else definitions
		if not effort.is_empty(): body["reasoning"] = {"effort": effort}
		if kind == "responses": body["include"] = ["reasoning.encrypted_content"]
	elif kind == "anthropic":
		path = "/messages"
		body["max_tokens"] = 8192
		body["system"] = "\n\n".join(system)
		var history = []
		for message in messages:
			var role = str(message.get("role", "user"))
			if role == "system": continue
			var content = []
			if role == "tool":
				role = "user"
				content.append({"type": "tool_result", "tool_use_id": message["tool_call_id"], "content": str(message["content"])})
			elif message.has("provider_blocks"):
				content = message["provider_blocks"].duplicate(true)
			else:
				if not str(message.get("content", "")).is_empty(): content.append({"type": "text", "text": str(message["content"])})
				for call in message.get("tool_calls", []): content.append({"type": "tool_use", "id": call["id"], "name": call["name"], "input": call["arguments"]})
			if not history.is_empty() and history[-1]["role"] == role: history[-1]["content"].append_array(content)
			else: history.append({"role": role, "content": content})
		body["messages"] = history
		if not tools.is_empty():
			body["tools"] = []
			for tool in tools: body["tools"].append({"name": tool["name"], "description": tool["description"], "input_schema": tool["parameters"]})
	elif kind == "gemini":
		path = "/models/" + model.uri_encode() + ":streamGenerateContent?alt=sse"
		body = {"systemInstruction": {"parts": [{"text": "\n\n".join(system)}]}, "contents": []}
		for message in messages:
			var role = str(message.get("role", "user"))
			if role == "system": continue
			var parts = []
			if role == "tool": parts.append({"functionResponse": {"name": message.get("tool_name", ""), "response": {"result": str(message["content"])}}})
			elif message.has("provider_items"): parts = message["provider_items"].duplicate(true)
			else:
				if not str(message.get("content", "")).is_empty(): parts.append({"text": str(message["content"])})
				for call in message.get("tool_calls", []): parts.append({"functionCall": {"name": call["name"], "args": call["arguments"]}})
			body["contents"].append({"role": "model" if role == "assistant" else "user", "parts": parts})
		if not tools.is_empty():
			var declarations = []
			for tool in tools: declarations.append({"name": tool["name"], "description": tool["description"], "parameters": tool["parameters"]})
			body["tools"] = [{"functionDeclarations": declarations}]
	else:
		body["messages"] = []
		for message in messages:
			var wire = {"role": message["role"], "content": str(message.get("content", ""))}
			if message.get("role") == "tool": wire["tool_call_id"] = message["tool_call_id"]
			if message.has("reasoning_content"): wire["reasoning_content"] = message["reasoning_content"]
			if not message.get("tool_calls", []).is_empty():
				wire["tool_calls"] = []
				for call in message["tool_calls"]: wire["tool_calls"].append({"id": call["id"], "type": "function", "function": {"name": call["name"], "arguments": JSON.stringify(call["arguments"])}})
			body["messages"].append(wire)
		if not tools.is_empty():
			body["tools"] = []
			for tool in tools: body["tools"].append({"type": "function", "function": {"name": tool["name"], "description": tool["description"], "parameters": tool["parameters"]}})
		if not effort.is_empty(): body["reasoning_effort"] = effort
	return {"path": path, "body": body}

static func consume_event(kind: String, event: Dictionary, state: Dictionary) -> void:
	if event.has("error"):
		state["error"] = JSON.stringify(event["error"])
		return
	if kind in ["responses", "siwc"]:
		match str(event.get("type", "")):
			"response.output_text.delta": state["text"] += str(event.get("delta", ""))
			"response.completed":
				state["terminal"] = true
				var response: Dictionary = event.get("response", {})
				state["items"] = response.get("output", [])
				state["usage"] = response.get("usage", {})
				for item in state["items"]:
					if item.get("type") == "function_call": state["calls"][str(item.get("call_id", item.get("id", Common.uid())))] = {"id": item.get("call_id", item.get("id", Common.uid())), "name": item.get("name", ""), "arguments": item.get("arguments", "{}")}
			"response.failed", "response.incomplete", "error": state["error"] = JSON.stringify(event)
	elif kind == "anthropic":
		var index = str(event.get("index", 0))
		match str(event.get("type", "")):
			"content_block_start": state["blocks"][index] = event.get("content_block", {}).duplicate(true)
			"content_block_delta":
				var delta: Dictionary = event.get("delta", {})
				if not state["blocks"].has(index): return
				var block: Dictionary = state["blocks"][index]
				match str(delta.get("type", "")):
					"text_delta":
						state["text"] += str(delta.get("text", ""))
						block["text"] = str(block.get("text", "")) + str(delta.get("text", ""))
					"input_json_delta": block["_partial_json"] = str(block.get("_partial_json", "")) + str(delta.get("partial_json", ""))
					"thinking_delta": block["thinking"] = str(block.get("thinking", "")) + str(delta.get("thinking", ""))
					"signature_delta": block["signature"] = str(block.get("signature", "")) + str(delta.get("signature", ""))
			"content_block_stop":
				if not state["blocks"].has(index): return
				var block: Dictionary = state["blocks"][index]
				if block.has("_partial_json"):
					block["input"] = JSON.parse_string(str(block["_partial_json"]))
					block.erase("_partial_json")
				if block.get("type") == "tool_use": state["calls"][index] = {"id": block["id"], "name": block["name"], "arguments": block.get("input", {})}
			"message_delta":
				state["finish"] = str(event.get("delta", {}).get("stop_reason", ""))
				state["usage"] = event.get("usage", {})
			"message_stop": state["terminal"] = true
	elif kind == "gemini":
		state["usage"] = event.get("usageMetadata", state["usage"])
		for candidate in event.get("candidates", []):
			for part in candidate.get("content", {}).get("parts", []):
				state["items"].append(part)
				if part.has("text") and not part.get("thought", false): state["text"] += str(part["text"])
				if part.has("functionCall"):
					var call: Dictionary = part["functionCall"]
					state["calls"][Common.uid()] = {"id": call.get("id", Common.uid()), "name": call.get("name", ""), "arguments": call.get("args", {})}
			if candidate.has("finishReason"):
				state["terminal"] = true
				state["finish"] = str(candidate["finishReason"])
	else:
		state["usage"] = event.get("usage", state["usage"])
		for choice in event.get("choices", []):
			var delta: Dictionary = choice.get("delta", {})
			state["text"] += str(delta.get("content", "")) if delta.get("content") != null else ""
			state["reasoning"] += str(delta.get("reasoning_content", "")) if delta.get("reasoning_content") != null else ""
			for fragment in delta.get("tool_calls", []):
				var index = str(fragment.get("index", 0))
				if not state["calls"].has(index): state["calls"][index] = {"id": Common.uid(), "name": "", "arguments": ""}
				var call: Dictionary = state["calls"][index]
				if fragment.has("id"): call["id"] = fragment["id"]
				call["name"] += str(fragment.get("function", {}).get("name", ""))
				call["arguments"] += str(fragment.get("function", {}).get("arguments", ""))
			if choice.get("finish_reason") != null:
				state["terminal"] = true
				state["finish"] = str(choice["finish_reason"])
