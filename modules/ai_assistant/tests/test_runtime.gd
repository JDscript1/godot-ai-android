extends SceneTree

var scripts: Dictionary = {}
var failures = 0
var assertions = 0
var source_directory = ""
var mock_url = ""

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
		if argument.begins_with("--mock-url="): mock_url = argument.trim_prefix("--mock-url=")
	if source_directory.is_empty():
		push_error("Pass -- --source=/absolute/path/to/modules/ai_assistant")
		quit(2)
		return
	for name in ["common", "transport", "providers", "editor_tools", "mcp", "assets", "accounts", "conversations", "chat_view", "agent_jobs", "speech", "panel"]:
		var script = GDScript.new()
		script.take_over_path("res://__godot_ai_builtin__/" + name + ".gd")
		script.source_code = FileAccess.get_file_as_string(source_directory.path_join("runtime/" + name + ".gd"))
		var error = script.reload()
		check(error == OK, "Embedded script compiles: " + name)
		if error != OK:
			quit(1)
			return
		var bindings = {"common": "Common", "transport": "Transport", "providers": "Providers", "editor_tools": "Tools", "mcp": "MCP", "assets": "Assets", "accounts": "Accounts", "conversations": "Conversations", "chat_view": "ChatView", "agent_jobs": "AgentJobs", "speech": "Speech"}
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
	var assets_script = scripts["assets"]
	var rodin = assets_script.build_runware_task({"asset_kind": "mesh", "model": "hyper3d:rodin@gen-2"}, "bird", "data:image/png;base64,fixture", common.uid())
	check(rodin.get("result", {}).get("inputs", {}).get("images") == ["data:image/png;base64,fixture"] and not rodin["result"].has("inputImages"), "Rodin reference uses documented nested inputs.images")
	var rapid = assets_script.build_runware_task({"asset_kind": "mesh", "model": "tencent:hunyuan-3d@3.1-rapid"}, "bird", "data:image/png;base64,fixture", common.uid())
	check(rapid.get("result", {}).get("inputs", {}).has("image") and not rapid["result"].has("positivePrompt"), "Hunyuan Rapid reference uses inputs.image without exclusive prompt")
	check(not assets_script.build_runware_task({"asset_kind": "mesh", "model": "microsoft:trellis-2@4b"}, "bird", "", common.uid()).get("ok", false), "Image-only 3D model requires a reference before submitting")
	check(not assets_script.build_runware_task({"asset_kind": "image", "model": "fixture"}, "bird", "fixture-reference", common.uid()).get("ok", false), "Unsupported image reference is reported rather than silently discarded")
	check(common.decode_variant({"$type": "Vector3", "value": [1, 2, 3]}) == Vector3(1, 2, 3), "Decode typed Godot arguments")
	check(not "fixture-secret" in common.redact("Bearer fixture-secret", ["fixture-secret"]), "Redact credentials")
	check(common.contains_inline_secrets({"1": {"inputs": {"api_key": "fixture-key"}}}), "Workflow credentials are detected before saving")
	check(not common.contains_inline_secrets({"1": {"inputs": {"token_count": 77}}}), "Ordinary workflow parameters remain supported")
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
	_new_feature_tests()
	var node = Node.new()
	root.add_child(node)
	var transport = scripts["transport"].new(node)
	var pre_cancelled = await transport.request("http://127.0.0.1:1/", HTTPClient.METHOD_GET, [], null, {"allow_http": true, "cancel": {"cancelled": true}})
	check(not pre_cancelled.get("ok", false), "Pre-cancelled requests terminate")
	if not mock_url.is_empty(): await _network_tests(node)
	node.queue_free()
	await process_frame
	print("Godot AI: %s assertions, %s failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func _network_tests(node: Node) -> void:
	var vault = FakeVault.new()
	var adapter = scripts["providers"].new(node, vault)
	vault.store("oauth-record", JSON.stringify({"access_token": "fixture-access", "refresh_token": "fixture-refresh"}))
	var mismatched = await adapter.list_models({"id": "oauth-record", "kind": "chat", "url": mock_url + "/v1", "allow_http": true})
	check(mismatched.get("code") == "credential_type_mismatch", "OAuth records never become API-key headers")
	var wrong_host = await adapter.list_models({"id": "oauth-record", "kind": "siwc", "url": mock_url + "/v1", "allow_http": true})
	check(wrong_host.get("code") == "credential_type_mismatch", "ChatGPT credentials are bound to the official OpenAI endpoint")
	var profile = {"id": "fixture", "kind": "chat", "url": mock_url + "/v1", "allow_http": true}
	var listed = await adapter.list_models(profile)
	check(listed.get("ok", false) and listed.get("result", []).size() == 1, "Real HTTP model discovery")
	check(listed.get("result", [{}])[0].get("efforts", []) == ["high", "max"], "Use provider-declared reasoning efforts")
	var history = [{"role": "user", "content": "Inspect"}]
	var first = await adapter.complete(profile, history, [], "fixture", "", {})
	check(first.get("ok", false) and first.get("calls", []).size() == 1, "Real HTTP streaming tool call")
	if first.get("ok", false):
		history.append(first["message"])
		history.append({"role": "tool", "tool_call_id": "fixture-call", "tool_name": "godot_project", "content": "{}"})
		var second = await adapter.complete(profile, history, [], "fixture", "", {})
		check(second.get("ok", false) and second.get("message", {}).get("content") == "Verificat: română 🐦", "Real multi-turn tool/result continuation")
	var incomplete_profile = profile.duplicate()
	var json_profile = profile.duplicate()
	json_profile["url"] = mock_url + "/json/v1"
	var json_first = await adapter.complete(json_profile, [{"role": "user", "content": "Inspect"}], [], "fixture", "", {})
	check(json_first.get("ok", false) and json_first.get("calls", []).size() == 2, "Compatible JSON-only servers retain separate tool calls")
	if json_first.get("ok", false):
		var json_history = [{"role": "user", "content": "Inspect"}, json_first["message"]]
		for call in json_first["calls"]: json_history.append({"role": "tool", "tool_call_id": call["id"], "tool_name": call["name"], "content": "{}"})
		var json_second = await adapter.complete(json_profile, json_history, [], "fixture", "", {})
		check(json_second.get("ok", false) and json_second.get("message", {}).get("content") == "JSON verified", "Compatible JSON-only server tool continuation")
	incomplete_profile["url"] = mock_url + "/incomplete/v1"
	var incomplete = await adapter.complete(incomplete_profile, [{"role": "user", "content": "Inspect"}], [], "fixture", "", {})
	check(not incomplete.get("ok", false) and incomplete.get("code") == "incomplete_stream", "Interrupted provider streams never report success")
	for kind in ["responses", "anthropic", "gemini"]:
		var native_profile = profile.duplicate()
		native_profile["kind"] = kind
		var result = await adapter.complete(native_profile, [{"role": "user", "content": "Inspect"}], [], "fixture", "", {})
		check(result.get("ok", false) and not str(result.get("message", {}).get("content", "")).is_empty(), "Real HTTP adapter: " + kind)
	var stopping = {"cancelled": false}
	var slow_profile = profile.duplicate()
	slow_profile["url"] = mock_url + "/slow/v1"
	create_timer(0.05).timeout.connect(func() -> void: stopping["cancelled"] = true)
	var stopped = await adapter.complete(slow_profile, [{"role": "user", "content": "Inspect"}], [], "fixture", "", stopping)
	check(not stopped.get("ok", false) and stopped.get("code") == "cancelled", "Cancel a provider HTTP request in flight")
	var mcp = scripts["mcp"].new(node, vault)
	var server = {"id": "fixture-mcp", "url": mock_url + "/mcp", "allow_http": true, "trusted_read": false}
	var catalog = await mcp.discover(server)
	check(catalog.get("ok", false) and catalog.get("result", []).size() == 2, "MCP initialize, session and paginated discovery")
	if catalog.get("ok", false):
		var name = str(catalog["result"][0]["name"])
		var denied = await mcp.call_tool(name, {}, 0, false, {})
		check(denied.get("code") == "permission_denied", "Untrusted MCP read annotations do not grant access")
		var called = await mcp.call_tool(name, {}, 2, true, {})
		check(called.get("ok", false) and "real fixture tool result" in JSON.stringify(called), "MCP real HTTP tool execution")
	var assets = scripts["assets"].new(node, vault)
	var scratch = OS.get_user_data_dir().path_join("ai_test_generation")
	assets.configure(scratch)
	for kind in ["image", "mesh"]:
		var generation = {"id": "fixture-comfy", "kind": "comfy", "asset_kind": kind, "url": mock_url, "allow_http": true, "workflow": {"1": {"class_type": "SaveGLB" if kind == "mesh" else "SaveImage", "inputs": {"text": ""}}}, "prompt_node": "1", "prompt_input": "text", "output_node": "1"}
		var submitted = await assets.submit(generation, "Fixture", "", {})
		check(submitted.get("ok", false), "ComfyUI submit: " + kind)
		if not submitted.get("ok", false): continue
		var refreshed = await assets.refresh(str(submitted["result"]["id"]), generation, {})
		check(refreshed.get("ok", false) and refreshed.get("result", {}).get("status") == "completed", "ComfyUI download and artifact validation: " + kind)
		if not refreshed.get("ok", false): continue
		var waited = await assets.wait_for_job(str(submitted["result"]["id"]), generation, {}, 1)
		check(waited.get("ok", false) and waited.get("result", {}).get("status") == "completed", "Generation wait returns the verified result: " + kind)
		if kind == "mesh":
			var document = GLTFDocument.new()
			var state = GLTFState.new()
			check(document.append_from_file(str(refreshed["result"]["file"]), state) == OK, "Generated GLB actually loads through Godot's importer")
			var scene = document.generate_scene(state)
			check(scene != null, "Godot builds the generated GLB scene")
			if scene != null: scene.free()
		var imported = assets.import_job(str(submitted["result"]["id"]), "res://ai_test_assets")
		check(imported.get("ok", false) and FileAccess.file_exists(str(imported.get("result", {}).get("path", ""))), "Import artifact into the fixture project: " + kind)
		var again = assets.import_job(str(submitted["result"]["id"]), "res://ai_test_assets")
		check(again.get("ok", false) and again.get("result", {}).get("path") != imported.get("result", {}).get("path"), "Artifact import never overwrites: " + kind)
	var bad_profile = {"id": "fixture-bad-output", "kind": "comfy", "asset_kind": "mesh", "url": mock_url, "allow_http": true, "workflow": {"2": {"class_type": "FixturePrompt", "inputs": {"text": ""}}}, "prompt_node": "2", "prompt_input": "text", "output_node": "2"}
	var bad_submit = await assets.submit(bad_profile, "Fixture", "", {})
	if bad_submit.get("ok", false):
		var missing = await assets.refresh(str(bad_submit["result"]["id"]), bad_profile, {})
		check(missing.get("code") == "missing_artifact", "Completed workflows with wrong output bindings fail explicitly")

func _new_feature_tests() -> void:
	var common = scripts["common"]
	var directory = OS.get_user_data_dir().path_join("conversation_" + common.uid())
	common.atomic_json(directory.path_join("history.json"), [{"id": "legacy", "role": "user", "content": "Original"}])
	var store = scripts["conversations"].new()
	store.configure(directory)
	var original_id = str(store.index["active"])
	check(store.load_active().size() == 1, "Migrate legacy conversation without losing messages")
	store.configure(directory)
	check(store.index["items"].size() == 1 and str(store.index["active"]) == original_id, "Conversation migration is idempotent")
	check(FileAccess.file_exists(directory.path_join("history.json")), "Migration preserves original history file")
	var image = Image.create(2, 2, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	var data = Marshalls.raw_to_base64(image.save_png_to_buffer())
	store.save([{"id": "image", "role": "user", "content": "Image", "attachments": [{"mimeType": "image/png", "data": data}]}], {"profile": "local", "model": "vision"})
	check(store.load_active()[0]["attachments"][0]["data"] == data, "Attachment cache survives conversation reload")
	check(not "data" in common.read_json(store._path(original_id), {})["messages"][0]["attachments"][0], "History JSON references image cache instead of duplicating base64")
	var fork_id = store.fork_at("image")
	check(fork_id != original_id and store.load_active().size() == 1 and store.index["items"].size() == 2, "Fork preserves the original conversation")
	store.update(fork_id, {"title": "Local vision", "favorite": true})
	check(store.listing("VISION").size() == 1, "Conversation search ignores case")
	store.remove(fork_id)
	check(not store.item(fork_id).is_empty(), "Only archived conversations can be deleted")
	store.update(fork_id, {"archived": true})
	check(store.listing("", true).size() == 1, "Archive and active history have separate lists")
	var provider = scripts["providers"]
	var internals = [{"role": "assistant", "content": "Public", "wire_source": "a:m", "reasoning_content": "private", "provider_items": [{"type": "reasoning"}], "provider_blocks": [{"type": "thinking"}]}]
	var normalized = provider.normalize_context({"id": "b"}, "m", internals)
	check(not normalized[0].has("reasoning_content") and not normalized[0].has("provider_blocks") and not normalized[0].has("provider_items"), "Provider switching strips foreign reasoning and signed blocks")
	check(provider.normalize_context({"id": "a"}, "m", internals)[0].has("reasoning_content"), "Same-model tool loops retain required reasoning")
	var multimodal = [{"role": "user", "content": "Describe", "attachments": [{"mimeType": "image/png", "data": data}]}]
	check(provider.build_request("chat", multimodal, [], "v")["body"]["messages"][0]["content"][1]["type"] == "image_url", "Chat image request uses image_url")
	check(provider.build_request("responses", multimodal, [], "v")["body"]["input"][0]["content"][1]["type"] == "input_image", "Responses image request uses input_image")
	check(provider.build_request("anthropic", multimodal, [], "v")["body"]["messages"][0]["content"][1]["source"]["type"] == "base64", "Anthropic image request uses base64 source")
	check(provider.build_request("gemini", multimodal, [], "v")["body"]["contents"][0]["parts"][0].has("inlineData"), "Gemini image request uses inlineData")
	var pcm = PackedByteArray()
	pcm.resize(192000)
	var wav = scripts["speech"].wav_16k(pcm, 48000, 2)
	check(wav.slice(0, 4).get_string_from_ascii() == "RIFF" and wav.decode_u32(24) == 16000 and wav.decode_u16(22) == 1 and wav.size() == 32044, "Voice resampling creates valid mono 16kHz one-second WAV")
	var tools = scripts["editor_tools"].new()
	check(tools.execute("godot_write_file", {"path": "res://blocked.txt", "text": "x"}, 3, true).get("code") == "permission_denied", "Plan mode independently denies mutations")
