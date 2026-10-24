extends SceneTree
## Real Godot client -> loopback worker -> existing Termux/PRoot Blender.
## The Android Intent boundary is deliberately substituted, never reported as tested.
var assertions = 0
var failures: Array = []
var source = ""
var endpoint = ""
var report_path = ""

class FailDownloadOnce:
	extends RefCounted
	var source: RefCounted
	var failed = false
	func _init(value: RefCounted) -> void: source = value
	func request(url: String, method: int, headers: PackedStringArray, body: Variant, options: Dictionary) -> Dictionary:
		if "/outputs/" in url and not failed:
			failed = true
			return {"ok": false, "code": "connection_failed", "error": "Injected lost download"}
		return await source.request(url, method, headers, body, options)

func _initialize() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures.append(label)
		push_error(label)

func write(path: String, text: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func cancel_after(token: Dictionary) -> void:
	await create_timer(1).timeout
	token["cancelled"] = true

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="): source = argument.trim_prefix("--source=")
		if argument.begins_with("--url="): endpoint = argument.trim_prefix("--url=")
		if argument.begins_with("--report="): report_path = argument.trim_prefix("--report=")
	var scripts = {}
	for name in ["common", "transport", "file_registry", "termux_blender"]:
		var script = GDScript.new()
		script.take_over_path("res://__godot_ai_builtin__/" + name + ".gd")
		script.source_code = FileAccess.get_file_as_string(source.path_join("runtime/" + name + ".gd"))
		check(script.reload() == OK, "Compile " + name)
		if failures.size() > 0: quit(1); return
		if scripts.has("common"): script.set("Common", scripts["common"])
		if scripts.has("transport"): script.set("Transport", scripts["transport"])
		if scripts.has("file_registry"): script.set("FileRegistry", scripts["file_registry"])
		scripts[name] = script
	var host = Node.new()
	root.add_child(host)
	var client = scripts["termux_blender"].new(host)
	var native_actions = []
	client.native_override = func(action: String, _args: Dictionary) -> Dictionary:
		native_actions.append(action)
		if action == "connection": return {"ok": true, "url": endpoint, "token": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
		return {"ok": true, "installed": true, "permission": false, "supported": true, "compatible": true, "launch_mode": "manual"}
	client.configure(OS.get_user_data_dir(), OS.get_user_data_dir().path_join("project"))
	check(not client.available(), "Unverified backend is unavailable")
	check(not client.valid_relative("a/../b.glb") and not client.valid_relative("/outside") and client.valid_relative("models/tree.glb"), "Artifact paths stay within their folder")
	client.manual_setup_pending = true
	await client.refresh()
	check(client.available(), "Returning after manual pairing discovers Blender, verifies real export and Godot import automatically")
	check(not native_actions.has("start") and not native_actions.has("permission"), "The real manual connection works without RUN_COMMAND or its Android permission")
	var result = {}
	var detected = client.runtime.duplicate(true)
	if not client.available():
		_finish(detected)
		return
	client.connected = false
	client.runtime = {}
	check(await client.ensure_ready() and client.available(), "A configured editor reconnects without reinstalling or re-running the verification job")
	# The installer must reuse the existing executable, without invoking pkg/apt.
	result = await client.setup("install")
	check(result.get("ok", false) and client.runtime.get("container") == detected.get("container"), "Install action reuses the existing Blender runtime")
	write("res://parameters.py", "size = 1.25\n")
	write("res://create_box.py", "import bpy,os\nfrom parameters import size\nassert os.path.isdir(os.environ['GODOT_AI_PROJECT_DIR'])\nbpy.ops.object.select_all(action='SELECT')\nbpy.ops.object.delete(use_global=False)\nbpy.ops.mesh.primitive_cube_add(size=size)\nroot=os.environ['GODOT_AI_OUTPUT_DIR']\nbpy.ops.export_scene.gltf(filepath=os.path.join(root,'box.glb'),export_format='GLB')\nbpy.ops.export_scene.gltf(filepath=os.path.join(root,'box.gltf'),export_format='GLTF_SEPARATE')\nbpy.ops.export_scene.fbx(filepath=os.path.join(root,'box.fbx'))\nbpy.ops.wm.save_as_mainfile(filepath=os.path.join(root,'box.blend'))\n")
	result = await client.run({"script": "res://create_box.py", "inputs": ["res://parameters.py"], "output_directory": "res://generated", "seconds": 60})
	check(result.get("ok", false) and result.get("result", {}).get("outputs", []).size() >= 5, "Streamed inputs produce GLB, glTF dependencies, FBX and BLEND: " + str(result.get("error", "")))
	for path in result.get("result", {}).get("outputs", []):
		check(FileAccess.file_exists(path) and str(path).begins_with("res://generated/create_box_"), "Result is imported into its own named project folder")
		if str(path).ends_with(".glb"):
			var document = GLTFDocument.new()
			check(document.append_from_file(path, GLTFState.new()) == OK, "Generated GLB imports in Godot")
		if str(path).ends_with(".blend"): check(FileAccess.file_exists(str(path) + ".import") and "keep" in FileAccess.get_file_as_string(str(path) + ".import"), "Editable BLEND is retained without triggering Android's desktop-only importer")
	# A lost result transfer retains a completed job; recovery never starts it again.
	var actual_transport = client.transport
	client.transport = FailDownloadOnce.new(actual_transport)
	result = await client.run({"script": "res://create_box.py", "inputs": ["res://parameters.py"], "seconds": 60})
	check(not result.get("ok", false) and not client.pending.is_empty(), "Lost download retains the job checkpoint")
	var saved_id = str(client.pending.get("id", ""))
	client.transport = actual_transport
	result = await client.setup("resume")
	check(result.get("ok", false) and result.get("result", {}).get("job") == saved_id and client.pending.is_empty(), "Recovery retrieves the same completed execution")
	write("res://slow.py", "import time\ntime.sleep(30)\n")
	var stopping = {}
	cancel_after(stopping)
	result = await client.run({"script": "res://slow.py", "seconds": 60}, stopping)
	check(not result.get("ok", false) and result.get("code") == "cancelled" and client.pending.is_empty(), "Cancellation stops the owned Blender job and clears its checkpoint")
	client.verified["fingerprint"] = "changed"
	check(not client.available(), "A changed runtime fingerprint removes readiness")
	_finish(detected)

func _finish(runtime: Dictionary) -> void:
	var report = {"assertions": assertions, "failures": failures, "runtime": runtime, "android_intent_tested": false, "real_blender": true}
	write(report_path, JSON.stringify(report, "\t"))
	print("Blender connector: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
