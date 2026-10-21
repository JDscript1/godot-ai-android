extends SceneTree

var scripts: Dictionary = {}
var failures = 0
var assertions = 0
var source_directory = ""

class FakeVault:
	extends RefCounted
	var values = {}
	func store(name: String, value: String) -> bool:
		values[name] = value
		return true
	func read(name: String) -> String: return str(values.get(name, ""))
	func erase(name: String) -> bool: return values.erase(name)

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="): source_directory = argument.trim_prefix("--source=")
	if source_directory.is_empty():
		push_error("Pass -- --source=/absolute/path/to/modules/ai_assistant")
		quit(2)
		return
	for name in ["common", "transport", "providers", "editor_tools", "mcp", "assets", "accounts", "panel"]:
		var script = GDScript.new()
		script.take_over_path("res://__godot_ai_builtin__/" + name + ".gd")
		script.source_code = FileAccess.get_file_as_string(source_directory.path_join("runtime/" + name + ".gd"))
		var error = script.reload()
		check(error == OK, "Embedded script compiles: " + name)
		if error != OK:
			quit(1)
			return
		var bindings = {"common": "Common", "transport": "Transport", "providers": "Providers", "editor_tools": "Tools", "mcp": "MCP", "assets": "Assets", "accounts": "Accounts"}
		for dependency in scripts: script.set(bindings[dependency], scripts[dependency])
		scripts[name] = script
	var common = scripts["common"]
	check(common.project_path("res://../outside.txt").is_empty(), "Reject project traversal")
	check(common.project_path("res://.godot/cache").is_empty(), "Reject editor-private project paths")
	check(common.project_path("res://scripts/player.gd") == "res://scripts/player.gd", "Accept project file")
	check(not common.parse_url("https://example.com@attacker.test").get("ok", false), "Reject URL userinfo")
	check(not common.parse_url("https://example.test/\nAuthorization: secret").get("ok", false), "Reject URL header injection")
	check(not common.parse_url("http://127.0.0.1:1234/v1").get("ok", false), "HTTP requires explicit local opt-in")
	check(common.parse_url("http://192.168.1.8:1234/v1", true).get("ok", false), "Allow configured LAN endpoint")
	check(common.parse_url("http://[::1]:1234/v1", true).get("ok", false), "Allow configured IPv6 endpoint")
	check(common.uid().length() == 36 and common.uid().get_slice("-", 2).begins_with("4"), "Task identifiers use UUIDv4")
	check(common.decode_variant({"$type": "Vector3", "value": [1, 2, 3]}) == Vector3(1, 2, 3), "Decode typed Godot arguments")
	check(not "fixture-secret" in common.redact("Bearer fixture-secret", ["fixture-secret"]), "Redact credentials")
	var decoder = scripts["transport"].SSEDecoder.new()
	var events = []
	var data = "data: {\"value\":\"română 🐦\"}\r\n\r\ndata: [DONE]\n\n".to_utf8_buffer()
	for byte in data: decoder.feed(PackedByteArray([byte]), func(event: Dictionary) -> void: events.append(event))
	check(events.size() == 1 and events[0]["value"] == "română 🐦", "SSE preserves UTF-8 across arbitrary byte boundaries")
	check(decoder.ended, "SSE recognizes terminal sentinel")
	var providers = scripts["providers"]
	check(not providers.detect("sk-generic-fixture").get("ok", false), "Ambiguous keys never trigger issuer guessing")
	check(providers.detect("DEEPSEEK_API_KEY=sk-generic-fixture").get("profile", {}).get("id") == "deepseek", "Labeled key determines issuer")
	var messages = [{"role": "system", "content": "Inspect"}, {"role": "user", "content": "Create"}, {"role": "assistant", "content": "", "reasoning_content": "Retained reasoning", "tool_calls": [{"id": "a", "name": "godot_project", "arguments": {}}]}, {"role": "tool", "tool_call_id": "a", "tool_name": "godot_project", "content": "{}"}]
	var chat = providers.build_request("chat", messages, [], "fixture")
	check(chat["body"]["messages"][2]["tool_calls"][0]["function"]["name"] == "godot_project", "Preserve multi-turn chat tool calls")
	check(chat["body"]["messages"][2]["reasoning_content"] == "Retained reasoning", "Retain DeepSeek reasoning during tool loops")
	var siwc = providers.build_request("siwc", messages, [], "fixture")
	check(siwc["body"]["store"] == false and siwc["body"]["stream"] == true, "SIWC streaming and storage requirements")
	check(not siwc["body"].has("max_output_tokens") and not siwc["body"].has("temperature"), "SIWC omits unsupported request parameters")
	check(siwc["body"]["input"][-1]["type"] == "function_call_output", "Responses tool result round trip")
	var anthropic = providers.build_request("anthropic", messages, [], "fixture")
	check(anthropic["body"]["messages"][-1]["content"][0]["type"] == "tool_result", "Anthropic tool result round trip")
	var tools = scripts["editor_tools"].new()
	check(tools.execute("godot_write_file", {"path": "res://must-not-exist.txt", "text": "unsafe"}, 0, true).get("code") == "permission_denied", "Analysis denies mutations even with full control")
	check(tools.execute("godot_call", {"handle": "x", "method": "set", "arguments": []}, 2, false).get("code") == "permission_denied", "Full-control toggle independently gates reflection")
	check(not FileAccess.file_exists("res://must-not-exist.txt"), "Denied tools have no file side effects")
	check(not tools.validate("godot_read_file", {"path": 2}).get("ok", false), "Reject invalid tool argument types")
	var auth = scripts["accounts"]
	check(auth._parse_query("state=abc&code=a%2Bb")["code"] == "a+b", "OAuth callback decoding")
	check(auth._parse_query("client_id=oaiapp_test")["client_id"] == "oaiapp_test", "Issued client ID is retained")
	check(auth._unbase64url(auth._base64url(PackedByteArray([0, 255, 128]))) == PackedByteArray([0, 255, 128]), "PKCE/base64url round trip")
	var panel = scripts["panel"].new()
	panel.history = messages.duplicate(true)
	panel.history.append({"role": "assistant", "content": "", "tool_calls": [{"id": "interrupted", "name": "godot_run", "arguments": {}}]})
	panel._close_unanswered_calls()
	check(panel.history[-1].get("tool_call_id") == "interrupted" and "cancelled" in str(panel.history[-1].get("content", "")), "Interrupted tool loops can be resumed")
	panel.free()
	var node = Node.new()
	root.add_child(node)
	var transport = scripts["transport"].new(node)
	var pre_cancelled = await transport.request("http://127.0.0.1:1/", HTTPClient.METHOD_GET, [], null, {"allow_http": true, "cancel": {"cancelled": true}})
	check(not pre_cancelled.get("ok", false), "Pre-cancelled requests terminate")
	node.queue_free()
	print("Godot AI: %s assertions, %s failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
