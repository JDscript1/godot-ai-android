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

class HarnessHost:
	extends RefCounted
	var replies: Array = []
	var contexts: Array = []
	var catalogs: Array = []
	var executed: Array = []
	var checkpoints: Array = []
	var token = {}
	var stop_after_tool = false
	var tool_result = {"ok": true, "result": "fixture-secret"}
	var fail_checkpoint_status = ""
	var reenter: RefCounted
	var reentry_result = {}

	func complete(context: Array, _tools: Array, _cancel: Dictionary, delta: Callable) -> Dictionary:
		if reenter != null: reentry_result = await reenter.run({}, hooks())
		contexts.append(context.duplicate(true))
		catalogs.append(_tools.duplicate(true))
		if replies.is_empty(): return {"ok": false, "code": "fixture_exhausted", "error": "No fixture response"}
		var reply: Dictionary = replies.pop_front()
		if reply.has("_delta"): delta.call(str(reply["_delta"]))
		return reply

	func execute(name: String, arguments: Dictionary) -> Dictionary:
		executed.append({"name": name, "arguments": arguments})
		if stop_after_tool: token["cancelled"] = true
		return tool_result

	func checkpoint(snapshot: Dictionary) -> bool:
		checkpoints.append(snapshot.duplicate(true))
		return snapshot.get("status") != fail_checkpoint_status
	func redact(value: String) -> String: return value.replace("fixture-secret", "[redacted]")
	func hooks() -> Dictionary: return {"complete": complete, "execute": execute, "checkpoint": checkpoint, "redact": redact}

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
	for name in ["common", "transport", "tool_registry", "providers", "editor_tools", "mcp", "assets", "accounts", "conversations", "icons", "planner", "markdown", "chat_view", "harness", "agent_jobs", "speech", "workspace", "integrations", "panel"]:
		var script = GDScript.new()
		script.take_over_path("res://__godot_ai_builtin__/" + name + ".gd")
		script.source_code = FileAccess.get_file_as_string(source_directory.path_join("runtime/" + name + ".gd"))
		var error = script.reload()
		check(error == OK, "Embedded script compiles: " + name)
		if error != OK:
			quit(1)
			return
		var bindings = {"common": "Common", "transport": "Transport", "tool_registry": "ToolRegistry", "providers": "Providers", "editor_tools": "Tools", "mcp": "MCP", "assets": "Assets", "accounts": "Accounts", "conversations": "Conversations", "icons": "Icons", "planner": "Planner", "markdown": "Markdown", "chat_view": "ChatView", "harness": "Harness", "agent_jobs": "AgentJobs", "speech": "Speech", "workspace": "Workspace", "integrations": "Integrations"}
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
	_tool_registry_tests()
	var node = Node.new()
	root.add_child(node)
	var transport = scripts["transport"].new(node)
	_planning_tests(node)
	await _harness_tests(node)
	var pre_cancelled = await transport.request("http://127.0.0.1:1/", HTTPClient.METHOD_GET, [], null, {"allow_http": true, "cancel": {"cancelled": true}})
	check(not pre_cancelled.get("ok", false), "Pre-cancelled requests terminate")
	if not mock_url.is_empty():
		await _network_tests(node)
		await _integration_tests(node)
	node.queue_free()
	await process_frame
	print("Godot AI: %s assertions, %s failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func _agent_response(text: String = "", calls: Array = [], finish: String = "stop") -> Dictionary:
	return {"ok": true, "message": {"role": "assistant", "content": text, "tool_calls": calls}, "calls": calls, "finish": finish}

func _integration_tests(node: Node) -> void:
	var service = scripts["integrations"].new(node, FakeVault.new())
	service.api_url = mock_url
	service.test_http = true
	check(not scripts["integrations"].valid_repository("../outside") and not scripts["integrations"].valid_repository("user/project?token=x"), "GitHub repository scope rejects paths and query injection")
	var result = await service.github_request("fixture/project", {"resource": "repository"})
	check(result.get("result", {}).get("full_name") == "fixture/project", "Native GitHub HTTP adapter reads the configured repository")
	result = await service.github_request("fixture/project", {"resource": "contents", "path": "script.gd", "ref": "main"})
	check(result.get("result", {}).get("text") == "extends Node\n" and result["result"]["sha"] == "fixture-sha", "GitHub content decoding retains source text and revision")
	result = await service.github_request("fixture/project", {"resource": "contents", "path": "../outside"})
	check(result.get("code") == "invalid_path", "GitHub content reads reject parent traversal")
	result = await service.github_request("fixture/project", {"resource": "issues", "page": 2})
	check(result.get("result", []).size() == 1 and not result["result"][0].has("body"), "GitHub lists return bounded summarized entries")
	result = await service.github_request("fixture/project", {"title": "Fixture request", "body": "Test only"}, {}, true)
	check(result.get("result", {}).get("number") == 4, "Issue publication uses the configured endpoint and native POST against a fixture")
	check(scripts["workspace"].valid_id("scene-workflow") and not scripts["workspace"].valid_id("../secret") and not scripts["workspace"].valid_id("folder/name"), "Portable skill identifiers cannot escape their project directory")
	for definition in scripts["workspace"].definitions() + service.definitions(true, true):
		check(scripts["tool_registry"].new([definition]).error.is_empty(), "Integration/skill schema is supported: " + str(definition["name"]))
	if service.desktop_blender() and FileAccess.file_exists("/usr/bin/blender"):
		var scratch = OS.get_user_data_dir().path_join("blender-integration")
		DirAccess.make_dir_recursive_absolute(scratch)
		var target = scratch.path_join("probe.glb")
		var source = "res://ai_test_blender.py"
		var file = FileAccess.open(source, FileAccess.WRITE)
		file.store_string("import bpy\nbpy.ops.mesh.primitive_cube_add()\nbpy.ops.export_scene.gltf(filepath=" + JSON.stringify(target) + ", export_format='GLB')\nprint('GODOT_AI_BLENDER_PROBE')\n")
		file.close()
		result = await service.blender("/usr/bin/blender", {"script": source, "seconds": 45})
		check(result.get("ok", false) and "GODOT_AI_BLENDER_PROBE" in str(result.get("result", {}).get("output", "")) and scripts["assets"].validate_artifact(target, "mesh").get("ok", false), "Real Blender CLI executes project Python and produces a validated GLB")
		var document = GLTFDocument.new()
		var state = GLTFState.new()
		var parsed = document.append_from_file(target, state)
		var scene = document.generate_scene(state) if parsed == OK else null
		check(scene != null and scene.get_child_count() > 0, "Godot imports the GLB produced by the real Blender CLI")
		if scene != null: scene.free()
		file = FileAccess.open(source, FileAccess.WRITE)
		file.store_string("raise RuntimeError('GODOT_AI_EXPECTED_FAILURE')\n")
		file.close()
		result = await service.blender("/usr/bin/blender", {"script": source, "seconds": 15})
		check(result.get("code") == "blender_error" and "EXPECTED_FAILURE" in str(result.get("error", "")), "Blender Python errors propagate as failures instead of success")
		result = await service.blender("/usr/bin/blender", {"script": source}, {"cancelled": true})
		check(result.get("code") == "cancelled" and service.processes.is_empty(), "Cancelled Blender operations do not launch a process")
		file = FileAccess.open(source, FileAccess.WRITE)
		file.store_string("import time\ntime.sleep(6)\n")
		file.close()
		result = await service.blender("/usr/bin/blender", {"script": source, "seconds": 1})
		check(result.get("code") == "timeout" and service.processes.is_empty(), "Blender execution is bounded and terminates a timed-out child")
		DirAccess.remove_absolute(source)

func _planning_tests(node: Node) -> void:
	var plan = scripts["planner"].new()
	plan.reset("plan-test")
	check(plan.can_write() and not plan.needs_continuation(), "A simple Auto task does not require a plan or extra requests")
	var steps = [{"step": "Inspect", "status": "in_progress"}, {"step": "Verify", "status": "pending"}]
	check(scripts["tool_registry"].validate(scripts["planner"].definition(), {"tasks": steps, "phase": "planning"}).get("ok", false), "Structured plans use the common tool schema validator")
	check(plan.update({"tasks": steps, "phase": "planning"}).get("ok", false) and not plan.can_write() and plan.needs_continuation(), "Auto planning is inspect-only and remains an unfinished task")
	plan.update({"tasks": steps, "phase": "executing"})
	check(plan.can_write() and plan.needs_continuation(), "Explicit execution phase permits Auto to apply the plan")
	check(not plan.update({"tasks": steps, "phase": "completed"}).get("ok", true) and plan.phase == "executing", "A plan cannot finish with pending steps and failed updates are atomic")
	check(not plan.update({"tasks": [{"step": "A", "status": "in_progress"}, {"step": "B", "status": "in_progress"}]}).get("ok", true), "Only one plan step can be in progress")
	plan.update({"tasks": steps, "phase": "blocked", "explanation": "Need project input"})
	check(not plan.can_write() and not plan.needs_continuation(), "A blocked plan stops automatic continuation and writes")
	plan.update({"tasks": steps, "phase": "executing"})
	plan.pause()
	check(plan.phase == "paused" and plan.steps[1]["status"] == "pending", "Stopping a plan does not mark unfinished steps completed")
	plan.reset("proposal", true)
	check(not plan.update({"tasks": steps, "phase": "executing"}, true).get("ok", true), "Manual Plan cannot switch itself into execution")
	check(plan.update({"tasks": steps, "phase": "completed"}, true).get("ok", false) and not plan.can_write() and not plan.needs_continuation(), "A completed proposal retains pending implementation steps without executing them")
	plan.reset()
	check(plan.update({"tasks": ["Legacy checklist"]}).get("ok", false) and plan.steps[0]["status"] == "pending", "Legacy checklist strings remain readable without inventing completed steps")
	var rich = RichTextLabel.new()
	node.add_child(rich)
	scripts["markdown"].render(rich, "## Titlu\n\n**Bold** și `cod`\n- Element\n> Citat\n[b]literal[/b]\n[x](javascript:alert(1))")
	var rendered = rich.get_parsed_text()
	check("Titlu" in rendered and "•  Element" in rendered and not "**Bold**" in rendered and "[b]literal[/b]" in rendered and "javascript:alert" in rendered, "Markdown formats text while keeping BBCode, HTML and unsupported links literal")
	scripts["markdown"].render(rich, "| Nume | Valoare |\n| --- | --- |\n| Nod | 12 |")
	check("Nume" in rich.get_parsed_text() and "12" in rich.get_parsed_text() and not "---" in rich.get_parsed_text(), "Markdown tables render as structured native cells")
	rich.queue_free()

func _tool_registry_tests() -> void:
	var registry_script = scripts["tool_registry"]
	var tools = scripts["editor_tools"].new()
	var registry = registry_script.new(tools.definitions(), true)
	var names = registry.active_definitions().map(func(item: Dictionary) -> String: return item["name"])
	check("tool_search" in names and "godot_read_range" in names and not "godot_apply_patch" in names, "Deferred registry starts with discovery and a small inspection set")
	var found = registry.discover("tool_search", {"query": "godot_apply_patch", "limit": 1})
	check(found.get("result", {}).get("tools", [{}])[0].get("name") == "godot_apply_patch" and registry.loaded.has("godot_apply_patch"), "Search returns the exact schema and activates a specialized tool")
	var reads = tools.definitions().filter(func(item: Dictionary) -> bool: return item["risk"] == "read")
	var read_registry = registry_script.new(reads, true)
	check(not read_registry.discover("tool_describe", {"name": "godot_apply_patch"}).get("ok", false), "Discovery cannot expose a tool excluded by the session mode")
	check(not registry_script.new([reads[0], reads[0]]).error.is_empty(), "Duplicate tool definitions are rejected")
	var schema = {"parameters": {"type": "object", "properties": {"items": {"type": "array", "items": {"$ref": "#/$defs/item"}, "minItems": 1}}, "$defs": {"item": {"type": "object", "properties": {"count": {"type": "integer", "minimum": 1}, "name": {"type": "string", "enum": ["allowed"]}}, "required": ["count", "name"], "additionalProperties": false}}, "required": ["items"], "additionalProperties": false}}
	check(registry_script.validate(schema, {"items": [{"count": 2.0, "name": "allowed"}]}).get("ok", false), "Nested schemas and local references accept integral JSON numbers")
	for invalid in [{"items": [{"count": 1.5, "name": "allowed"}]}, {"items": [{"count": 0, "name": "allowed"}]}, {"items": [{"count": 1, "name": "other"}]}, {"items": [{"count": 1, "name": "allowed", "extra": true}]}, {"items": []}, {}]:
		check(not registry_script.validate(schema, invalid).get("ok", false), "Reject invalid nested tool arguments: " + JSON.stringify(invalid))
	check(registry_script.validate({"parameters": {"not": {"if": {}}}}, {}).get("code") == "unsupported_schema", "Unsupported constraints cannot be hidden inside schema negation")
	check(registry_script.validate({"parameters": {"not": {"$ref": "https://example.test/schema"}}}, {}).get("code") == "unsupported_schema", "External schema references fail explicitly without fetching anything")
	check(not tools.validate("godot_restore_file", {"index": 1.5}).get("ok", false), "All native tool calls reject fractional integer arguments")
	var source = "extends Node\r\nvar value = 1 # română 🐦\r\n"
	var patch = scripts["editor_tools"].prepare_patch(source, [{"old_text": "value = 1", "new_text": "value = 2"}])
	check(patch.get("ok", false) and patch["result"]["text"] == source.replace("value = 1", "value = 2") and patch["result"]["changes"][0]["line"] == 2, "Exact patches preserve UTF-8 and CRLF and report line numbers")
	check(not scripts["editor_tools"].prepare_patch("aaa", [{"old_text": "aa", "new_text": "b"}]).get("ok", false), "Overlapping repeated patch anchors are ambiguous")
	check(not scripts["editor_tools"].prepare_patch(source, [{"old_text": "value = 1", "new_text": "value = 2"}, {"old_text": "missing", "new_text": "x"}]).get("ok", false), "A later invalid edit rejects the entire patch before writing")
	var mcp = scripts["mcp"]
	var error = mcp.normalize_result({"isError": true, "content": [{"type": "text", "text": "Fixture execution failed"}]})
	check(not error.get("ok", true) and error.get("code") == "mcp_tool_error", "MCP isError is an execution failure rather than a successful RPC")
	check(mcp.normalize_result({"isError": true, "content": [{"type": "text", "text": "Bad input"}]}, {"type": "object", "required": ["answer"]}).get("code") == "mcp_tool_error", "MCP execution failures do not need the success output schema")
	var image = Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var encoded = Marshalls.raw_to_base64(image.save_png_to_buffer())
	var result = mcp.normalize_result({"content": [{"type": "text", "text": "Fixture frame"}, {"type": "image", "mimeType": "image/png", "data": encoded}], "structuredContent": {"count": 2}}, {"type": "object", "properties": {"count": {"type": "integer"}}, "required": ["count"]})
	check(result.get("ok", false) and result.get("images", []).size() == 1 and not "data" in result["result"]["content"][1] and result["result"]["structuredContent"]["count"] == 2, "MCP preserves structured data and separates validated image attachments")
	check(not mcp.normalize_result({"content": [], "structuredContent": {"count": "bad"}}, {"type": "object", "properties": {"count": {"type": "integer"}}}).get("ok", false), "MCP output schemas reject mismatched structured results")
	check(mcp.normalize_result({"content": [{"type": "audio"}]}).get("code") == "unsupported_mcp_content", "Unsupported MCP content is reported explicitly")

func _harness_tests(node: Node) -> void:
	var core = scripts["harness"].new(node)
	var definitions = [scripts["common"].tool("write_fixture", "Fixture", {}, [], "write")]
	var call = {"id": "one", "name": "write_fixture", "arguments": {}}
	var deferred = HarnessHost.new()
	deferred.replies = [_agent_response("", [{"id": "discover", "name": "tool_describe", "arguments": {"name": "write_fixture"}}]), _agent_response("", [call]), _agent_response("Done")]
	var discovered = await core.run({"tools": definitions, "deferred_tools": true}, deferred.hooks())
	check(discovered.get("ok", false) and deferred.executed.size() == 1 and deferred.catalogs[0].size() == 2 and deferred.catalogs[1].any(func(item: Dictionary) -> bool: return item["name"] == "write_fixture"), "Harness loads discovered definitions on the next provider request")
	deferred = HarnessHost.new()
	deferred.replies = [_agent_response("", [call]), _agent_response("Unavailable until discovery")]
	var unloaded_messages = []
	await core.run({"tools": definitions, "deferred_tools": true, "messages": unloaded_messages}, deferred.hooks())
	check(deferred.executed.is_empty() and "tool_not_loaded" in str(unloaded_messages[1].get("content")), "Guessing an undeclared tool name cannot bypass deferred discovery")
	var host = HarnessHost.new()
	host.replies = [{"ok": false, "status": 429, "headers": {"Retry-After": "0"}, "error": "Temporary"}, _agent_response("", [call]), _agent_response("Verified fixture-secret")]
	var messages = [{"role": "user", "content": "Inspect and edit"}]
	var events = []
	core.event.connect(func(value: Dictionary) -> void: events.append(value))
	var outcome = await core.run({"messages": messages, "tools": definitions, "retry_delay_ms": 0}, host.hooks())
	check(outcome.get("status") == "completed" and outcome.get("requests") == 3 and outcome.get("retries") == 1 and outcome.get("steps") == 2, "Native harness retries rate limits and completes a tool turn")
	check(host.executed.size() == 1 and messages.size() == 4 and host.contexts[-1][-1].get("role") == "tool", "Native harness passes tool results back to the model")
	check(not "fixture-secret" in JSON.stringify(messages) and not "fixture-secret" in JSON.stringify(events), "Harness transcripts and events redact credentials")
	check(host.checkpoints.any(func(value: Dictionary) -> bool: return value.get("status") == "waiting_tool") and host.checkpoints[-1].get("status") == "completed", "Harness checkpoints before side effects and after settlement")

	# Simulate resuming a persisted conversation whose provider repeats its call ID.
	host = HarnessHost.new()
	host.replies = [_agent_response("", [call]), _agent_response("Previously applied")]
	outcome = await core.run({"messages": messages, "tools": definitions}, host.hooks())
	check(outcome.get("ok", false) and host.executed.is_empty(), "Resume reuses recorded tool results without replaying project writes")
	var changed = call.duplicate(true)
	changed["arguments"] = {"unexpected": true}
	host = HarnessHost.new()
	host.replies = [_agent_response("", [changed])]
	outcome = await core.run({"messages": messages, "tools": definitions}, host.hooks())
	check(outcome.get("code") == "invalid_response" and host.executed.is_empty(), "Conflicting reused IDs are rejected before any execution")

	host = HarnessHost.new()
	host.replies = [_agent_response("", [call, call])]
	outcome = await core.run({"tools": definitions}, host.hooks())
	check(outcome.get("code") == "invalid_response" and host.executed.is_empty(), "Duplicate IDs in one model response cannot duplicate writes")
	host = HarnessHost.new()
	host.replies = [_agent_response("", [{"id": "unknown", "name": "hidden_tool", "arguments": {}}]), _agent_response("Unavailable")]
	messages = []
	outcome = await core.run({"messages": messages, "tools": definitions}, host.hooks())
	check(host.executed.is_empty() and "tool_unavailable" in str(messages[1].get("content")), "Tools outside the active registry never reach the executor")
	host = HarnessHost.new()
	host.replies = [_agent_response("", [call]), _agent_response("Unavailable")]
	var blocked_messages = [_agent_response("", [call])["message"], {"role": "tool", "tool_call_id": "one", "content": "{\"ok\":true}"}]
	outcome = await core.run({"messages": blocked_messages, "tools": []}, host.hooks())
	check(host.executed.is_empty() and outcome.get("tool_calls") == 0 and "tool_unavailable" in str(blocked_messages[-2].get("content", "")), "A recorded result does not bypass the current tool registry")
	host = HarnessHost.new()
	host.replies = [_agent_response("", [{"id": "bad", "name": "write_fixture", "arguments": "invalid"}])]
	outcome = await core.run({"tools": definitions}, host.hooks())
	check(outcome.get("code") == "invalid_response" and host.executed.is_empty(), "Malformed model arguments cannot reach the executor")

	host = HarnessHost.new()
	host.stop_after_tool = true
	host.token = {"cancelled": false}
	var next = call.duplicate(true)
	next["id"] = "two"
	host.replies = [_agent_response("", [call, next])]
	messages = []
	outcome = await core.run({"messages": messages, "tools": definitions, "cancel": host.token}, host.hooks())
	check(outcome.get("status") == "cancelled" and host.executed.size() == 1, "Stop between batch tools prevents the remaining side effect")
	check(messages.size() == 3 and messages[-1].get("tool_call_id") == "two" and "cancelled" in str(messages[-1].get("content")), "Cancellation closes every pending call for a valid next turn")
	host = HarnessHost.new()
	outcome = await core.run({"cancel": {"cancelled": true}}, host.hooks())
	check(outcome.get("status") == "cancelled" and host.contexts.is_empty(), "Pre-cancelled harness never contacts a model")
	host = HarnessHost.new()
	host.token = {"cancelled": false}
	host.replies = [{"ok": false, "status": 503, "error": "Temporary"}]
	var stopping = host.token
	var stop_retry = func(value: Dictionary) -> void:
		if value.get("kind") == "retry": stopping["cancelled"] = true
	core.event.connect(stop_retry)
	outcome = await core.run({"cancel": stopping}, host.hooks())
	core.event.disconnect(stop_retry)
	check(outcome.get("status") == "cancelled" and host.contexts.size() == 1, "Stop interrupts retry backoff before another request")

	host = HarnessHost.new()
	host.replies = [{"ok": false, "code": "incomplete_stream", "error": "Interrupted", "_delta": "Partial"}]
	outcome = await core.run({}, host.hooks())
	check(outcome.get("status") == "failed" and host.contexts.size() == 1, "A visible partial response is never silently regenerated by retry")
	host = HarnessHost.new()
	host.replies = [{"ok": false, "status": 401, "error": "Invalid credentials"}]
	outcome = await core.run({}, host.hooks())
	check(host.contexts.size() == 1 and outcome.get("status") == "failed", "Authentication errors are not retried")
	host = HarnessHost.new()
	host.replies = [{"ok": false, "status": 503, "error": "Temporary"}, {"ok": false, "status": 503, "error": "Temporary"}, {"ok": false, "status": 503, "error": "Temporary"}]
	outcome = await core.run({"retry_delay_ms": 0}, host.hooks())
	check(outcome.get("status") == "failed" and host.contexts.size() == 3 and outcome.get("retries") == 2, "Transient failures stop at the retry budget")
	host = HarnessHost.new()
	host.reenter = core
	host.replies = [_agent_response("Original turn")]
	outcome = await core.run({}, host.hooks())
	check(outcome.get("ok", false) and host.reentry_result.get("code") == "busy" and outcome.get("text") == "Original turn", "A concurrent turn cannot overwrite an active harness session")
	host.reenter = null
	host = HarnessHost.new()
	host.replies = [_agent_response("", [call])]
	outcome = await core.run({"tools": definitions, "max_steps": 1}, host.hooks())
	check(outcome.get("status") == "limited" and outcome.get("code") == "step_limit" and not outcome.get("ok", true), "Step exhaustion is distinct from completion")
	host = HarnessHost.new()
	host.replies = [_agent_response("Partial answer", [], "length")]
	outcome = await core.run({}, host.hooks())
	check(outcome.get("status") == "limited" and outcome.get("code") == "output_limit", "Output exhaustion is distinct from completion")
	host = HarnessHost.new()
	host.fail_checkpoint_status = "waiting_tool"
	host.replies = [_agent_response("", [call])]
	messages = []
	outcome = await core.run({"tools": definitions, "messages": messages}, host.hooks())
	check(outcome.get("code") == "checkpoint_failed" and host.executed.is_empty() and messages.size() == 2 and "checkpoint_failed" in str(messages[-1].get("content", "")), "Failed durable checkpoint stops the write and closes its call")
	host = HarnessHost.new()
	host.tool_result = {"ok": true, "result": "x".repeat(30000)}
	host.replies = [_agent_response("", [call]), _agent_response("Done")]
	messages = []
	outcome = await core.run({"tools": definitions, "messages": messages}, host.hooks())
	var bounded: Variant = JSON.parse_string(str(messages[1]["content"]))
	check(outcome.get("ok", false) and bounded is Dictionary and bounded.get("truncated", false) and str(messages[1]["content"]).length() <= 24000, "Large tool results remain bounded valid JSON")
	host = HarnessHost.new()
	var encoded = Marshalls.raw_to_base64(Image.create_empty(2, 2, false, Image.FORMAT_RGBA8).save_png_to_buffer())
	host.tool_result = {"ok": true, "result": {"text": "Frame"}, "images": [{"name": "frame.png", "mimeType": "image/png", "data": encoded}]}
	host.replies = [_agent_response("", [call]), _agent_response("Observed")]
	messages = []
	outcome = await core.run({"tools": definitions, "messages": messages}, host.hooks())
	check(outcome.get("ok", false) and messages[1].get("attachments", []).size() == 1 and not encoded in str(messages[1]["content"]), "Tool images reach the model as attachments without base64 in its text context")

	var repaired = scripts["harness"].repair_messages([_agent_response("", [call])["message"]])
	host = HarnessHost.new()
	host.replies = [_agent_response("", [call]), _agent_response("Inspect first")]
	outcome = await core.run({"tools": definitions, "messages": repaired}, host.hooks())
	check(outcome.get("ok", false) and host.executed.is_empty(), "An interrupted persisted write is not automatically executed again")
	host = HarnessHost.new()
	host.replies = [_agent_response("Plan ready"), _agent_response("Implemented and verified")]
	var pending = {"yes": true}
	var hooks = host.hooks()
	hooks["needs_continuation"] = func() -> bool:
		var result: bool = pending["yes"]
		pending["yes"] = false
		return result
	outcome = await core.run({}, hooks)
	check(outcome.get("ok", false) and host.contexts.size() == 2 and outcome.get("text") == "Implemented and verified", "An unfinished Auto plan continues after an intermediate answer instead of ending the task")
	host = HarnessHost.new()
	host.replies = [_agent_response("Still planning"), _agent_response("Still planning")]
	hooks = host.hooks()
	hooks["needs_continuation"] = func() -> bool: return true
	outcome = await core.run({"max_steps": 2}, hooks)
	check(outcome.get("code") == "step_limit" and host.contexts.size() == 2, "Plan continuation respects the harness step budget")

func _network_tests(node: Node) -> void:
	var vault = FakeVault.new()
	var adapter = scripts["providers"].new(node, vault)
	vault.store("oauth-record", JSON.stringify({"access_token": "fixture-access", "refresh_token": "fixture-refresh"}))
	var mismatched = await adapter.list_models({"id": "oauth-record", "kind": "chat", "url": mock_url + "/v1", "allow_http": true})
	check(mismatched.get("code") == "credential_type_mismatch", "OAuth records never become API-key headers")
	var wrong_host = await adapter.list_models({"id": "oauth-record", "kind": "siwc", "url": mock_url + "/v1", "allow_http": true})
	check(wrong_host.get("code") == "credential_type_mismatch", "ChatGPT credentials are bound to the official OpenAI endpoint")
	var profile = {"id": "fixture", "kind": "chat", "url": mock_url + "/v1", "allow_http": true}
	var core = scripts["harness"].new(node)
	var direct_messages = [{"role": "user", "content": "Inspect through the native harness"}]
	var direct_complete = func(context: Array, catalog: Array, stopping: Dictionary, delta: Callable) -> Dictionary:
		return await adapter.complete(profile, context, catalog, "fixture", "", stopping, delta)
	var direct_tools = []
	var dispatch = func(name: String, args: Dictionary) -> Dictionary:
		direct_tools.append(name)
		return scripts["common"].success(args)
	var direct = await core.run({"messages": direct_messages, "tools": [scripts["common"].tool("godot_project", "Inspect", {}, [])]}, {"complete": direct_complete, "execute": dispatch})
	check(direct.get("ok", false) and direct_tools == ["godot_project"] and direct.get("steps") == 2 and direct_messages[-1].get("content") == "Verificat: română 🐦", "Own harness performs a real HTTP model/tool/result loop without a companion")
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
		var failed = await mcp.call_tool(name, {"fail": true}, 2, true, {})
		check(not failed.get("ok", true) and failed.get("code") == "mcp_tool_error", "Real MCP HTTP execution errors propagate through the normalized result")
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

	check(store.item(fork_id).get("selection", {}).get("model") == "vision", "Fork retains its originating model selection")
	var jobs = scripts["agent_jobs"].new()
	jobs.jobs = {"one": {"status": "running", "profile": {"id": "one"}}, "two": {"status": "running", "profile": {"id": "two"}}}
	check(not jobs.spawn("Inspect", "Explore", {"id": "third"}, "m", "", "p").get("ok", false), "Cloud child limit applies across provider profiles")
	jobs.jobs.erase("two")
	check(not jobs.spawn("Inspect", "General", {"id": "local", "issuer": "ollama"}, "m", "", "p").get("ok", false), "Local models do not start an extra parallel child")
