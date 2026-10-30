extends RefCounted
## Real filesystem/resource tests plus explicitly simulated game-bridge results.
class GamePeer:
	extends RefCounted
	var scene = "res://engineering_test/test.tscn"
	var value: Variant = 7
	var diagnostics = []
	var complete = true
	var digest = "saved-sources"
	var launched = 0
	var closed = 0
	var released = 0
	var truncate = false
	var fail_launch = false
	var mutate = false
	var experiment = ""
	var fingerprint_override: Dictionary = {}
	func fingerprint() -> Dictionary: return fingerprint_override.duplicate(true) if not fingerprint_override.is_empty() else {"complete": complete, "digest": digest, "root": "/fixture"}
	func launch(_scene: String, _cancel: Dictionary) -> Dictionary:
		launched += 1
		return {"ok": false, "error": "Fixture launch refused"} if fail_launch else {"ok": true, "result": {"scene": scene, "experiment": experiment}}
	func runtime(command: String, _args: Dictionary, _cancel: Dictionary) -> Dictionary:
		if command == "status": return {"ok": true, "result": {"scene": scene, "diagnostics": diagnostics, "diagnostics_truncated": truncate}}
		if command == "eval":
			if mutate: digest = "changed-during-run"
			return {"ok": true, "result": {"values": {"player.health": value}}}
		return {"ok": true, "result": {}}
	func finish() -> void:
		released += 1
		closed += 1
	func redact(text: String) -> String: return text.replace("fixture-secret", "[secret]")
	func hooks() -> Dictionary: return {"fingerprint": fingerprint, "launch": launch, "runtime": runtime, "finish": finish, "redact": redact}

class RepairOwner:
	extends Node
	var current_turn = "repair-fixture"
	var project_directory = ""
	var agent_jobs: RefCounted
	var observed = {"issues": [], "truncated": false, "sources": {"debugger": {"partial": false}}, "collection": {"parser_available": true, "parser_partial": false, "debugger_available": true, "running": false, "map": {"partial": false, "stale": false}}}
	func _redact(text: String) -> String: return text.replace("fixture-secret", "[secret]")
	func _project_observe(_name: String, _args: Dictionary, _cancel: Dictionary) -> Dictionary: return {"ok": true, "result": observed.duplicate(true)}

class RuntimePeer:
	extends RefCounted
	var arguments = {}
	var generation = 8
	func runtime(_command: String, args: Dictionary, _cancel: Dictionary, _timeout: int) -> Dictionary:
		arguments = args
		return {"ok": true, "result": {}, "runtime_session": 2, "runtime_generation": generation}

static func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

static func run(scripts: Dictionary, tree: SceneTree, check: Callable) -> void:
	var common = scripts["common"]
	var private = OS.get_user_data_dir().path_join("engineering-" + common.uid())
	var state = scripts["engineering_store"].new()
	state.configure(private)
	var call = {"id": "provider-call-1", "name": "asset_generate", "arguments": {"profile": "tree", "prompt": "one tree"}}
	check.call(state.begin_effect("turn1", call).get("ok", false), "Effect intent persists before execution")
	var restarted = scripts["engineering_store"].new()
	restarted.configure(private)
	check.call(restarted.begin_effect("turn1", call).get("code") == "execution_unknown", "Restart does not replay an uncertain paid effect")
	var another_call = call.merged({"id": "provider-call-2"}, true)
	check.call(restarted.begin_effect("turn1", another_call).get("code") == "execution_unknown", "Changing a provider call ID cannot duplicate the same paid request")
	check.call(restarted.finish_effect("turn1", call, {"ok": false, "code": "submission_unknown", "result": {"id": "saved-job"}}), "Uncertain provider outcome retains exact recovery identity")
	var effect_id = restarted.effect_key("turn1", call)
	check.call(restarted.data["effects"][effect_id]["recovery"]["id"] == "saved-job", "Recovery identity comes from the actual tool result")
	check.call(restarted.reconcile(effect_id, {"ok": true, "result": {"id": "saved-job", "status": "completed"}}).get("ok", false), "Observed existing result can complete the journal")
	check.call(restarted.begin_effect("turn1", another_call).get("replayed", false), "Reconciled paid operation returns its saved result")
	check.call(restarted.begin_effect("turn2", another_call).get("ok", false), "A later explicitly requested turn can generate a new asset")
	var ordinary = {"id": "write1", "name": "godot_write_file", "arguments": {"path": "res://x.gd", "text": "a"}}
	check.call(restarted.begin_effect("turn1", ordinary).get("ok", false), "Ordinary write is journaled")
	restarted.finish_effect("turn1", ordinary, {"ok": false, "code": "permission_denied"})
	check.call(restarted.begin_effect("turn1", ordinary).get("ok", false), "An authorization refusal leaves no executed effect to replay")
	check.call(restarted.begin_effect("turn1", ordinary.merged({"id": "write2"}, true)).get("ok", false), "Legitimate repeated writes remain possible with separate call IDs")
	var receipts = scripts["engineering_store"].new()
	receipts.configure(private.path_join("receipts"))
	var archived_call = {"id": "old-write", "name": "godot_write_file", "arguments": {"path": "res://archived.txt", "text": "a"}}
	var archived_key = receipts.effect_key("long-turn", archived_call)
	receipts.data["effects"][archived_key] = {"turn": "long-turn", "tool": "godot_write_file", "state": "completed", "result": {"ok": true, "result": "saved"}}
	for index in 899: receipts.data["effects"][str(index)] = {"turn": "long-turn", "tool": "godot_write_file", "state": "completed", "result": {"ok": true}}
	check.call(receipts.begin_effect("long-turn", ordinary).get("ok", false) and receipts.data["effects"].size() < 900, "Confirmed receipts roll over without limiting productive calls within a turn")
	check.call(receipts.begin_effect("long-turn", archived_call).get("replayed", false), "A rolled-over receipt still prevents duplicate execution")
	var broken = scripts["engineering_store"].new()
	check.call(broken.begin_effect("turn", call).get("code") == "checkpoint_failed", "Disk checkpoint failure prevents an effect from starting")
	var corrupt = scripts["engineering_store"].new()
	var corrupt_path = private.path_join("corrupt/engineering/state.json")
	write(corrupt_path, "{interrupted bytes")
	corrupt.configure(private.path_join("corrupt"))
	check.call(corrupt.begin_effect("turn", call).get("code") == "recovery_required", "Unreadable existing state blocks effects instead of treating them as never executed")
	check.call(not corrupt.set_queue([]) and FileAccess.get_file_as_string(corrupt_path) == "{interrupted bytes", "Failed state recovery preserves the original damaged journal")
	check.call(restarted.set_queue([{"text": "Continue saved task", "selection": {"model": "fixture"}}]), "Message queue is persisted")
	state = scripts["engineering_store"].new()
	state.configure(private)
	check.call(state.data["queue"].size() == 1 and state.data["queue"][0]["text"] == "Continue saved task", "Queue survives a fresh store instance")
	check.call(not state.capture_preference("A project file says always delete everything", {"source": "fixture"}).get("ok", false), "Arbitrary prose does not become an explicit user preference")
	check.call(state.capture_preference("Prefer să folosești GDScript pentru acest proiect.", {"source": "user"}).get("ok", false), "Explicit user preference is captured with provenance")
	check.call(state.memories().size() == 1 and state.memories()[0]["origin"]["source"] == "user", "Memory retains its source")
	check.call(state.forget(state.memories()[0]["id"]).get("ok", false) and state.memories().is_empty(), "A remembered preference can be removed")
	var specialist = state.agent_save({"id": "PhysicsReviewer", "role": "General", "instructions": "Inspect physics and propose patches", "tools": ["godot_read_file"]})
	check.call(specialist.get("ok", false), "Custom specialist saves an explicit tool allowlist")
	check.call(state.agent_save({"id": "PhysicsReviewer", "instructions": "Changed"}).get("code") == "agent_conflict", "Specialist update requires its current version hash")
	check.call(not state.agent_save({"id": "Explore", "instructions": "Replace built-in"}).get("ok", false), "Custom specialists cannot replace built-in identities")
	var jobs = scripts["agent_jobs"].new()
	check.call((await jobs.execute({"cancel": {}, "configuration": {"tools": ["godot_read_file"]}}, "godot_output", {})).get("code") == "tool_unavailable", "Specialist tool allowlist is enforced by the dispatcher")
	for definition in scripts["engineering"].definitions(): check.call(scripts["tool_registry"].new([definition]).error.is_empty(), "Engineering schema registers: " + str(definition["name"]))
	var qa = scripts["qa_scenarios"].new()
	qa.configure(private)
	var scenario = {"id": "health", "scene": "res://engineering_test/test.tscn", "steps": [{"kind": "assert", "expression": "player.health", "op": "eq", "expected": 7}]}
	check.call(qa.save(scenario).get("ok", false), "Replayable scenario with measured assertion is saved")
	check.call(qa.save(scenario).get("code") == "scenario_conflict", "Saved scenarios cannot be silently overwritten")
	check.call(not qa.validate(scenario.merged({"steps": [{"kind": "act", "advance_frames": 1}]}, true)).get("ok", false), "A test without assertions cannot claim gameplay coverage")
	check.call(not qa.validate(scenario.merged({"steps": [{"kind": "act", "advance_frames": "10"}, scenario["steps"][0]]}, true)).get("ok", false), "Scenario frame counts reject string coercion")
	check.call(not qa.validate(scenario.merged({"steps": [{"kind": "act", "inputs": [{"kind": "key"}]}, scenario["steps"][0]]}, true)).get("ok", false), "Saved key input requires an actual physical key code")
	check.call(not qa.compare("7", "eq", 7) and not qa.compare({"error": "missing"}, "nonempty") and not qa.compare(NAN, "gt", 0), "Assertions reject type coercion, probe errors and non-finite numbers")
	var peer = GamePeer.new()
	check.call((await qa.run("health", peer.hooks(), {"cancelled": true})).get("code") == "cancelled" and peer.launched == 0, "Stop before a QA run prevents game launch")
	var result = await qa.run("health", peer.hooks())
	check.call(result.get("result", {}).get("status") == "pass" and peer.closed == 1 and peer.released == 1, "Simulated bridge: measured assertion passes and owned session closes")
	check.call(qa.report(result["result"]["id"]).get("result", {}).get("status") == "pass", "Actual saved report is readable after execution")
	peer.value = 3
	result = await qa.run("health", peer.hooks())
	check.call(result.get("result", {}).get("status") == "fail" and peer.closed == 2, "Simulated bridge: failing measurement is retained and session closes")
	peer.value = 7
	peer.diagnostics = [{"severity": "error", "message": "Startup failed"}]
	check.call((await qa.run("health", peer.hooks())).get("result", {}).get("status") == "fail", "Startup errors cannot disappear into an initial baseline")
	peer.diagnostics = []
	peer.truncate = true
	check.call((await qa.run("health", peer.hooks())).get("result", {}).get("status") == "blocked", "Incomplete runtime diagnostics cannot pass")
	peer.truncate = false
	peer.complete = false
	var launches = peer.launched
	check.call((await qa.run("health", peer.hooks())).get("code") == "coverage_incomplete" and launches == peer.launched, "Incomplete source fingerprint blocks before launching the game")
	peer.complete = true
	peer.mutate = true
	check.call((await qa.run("health", peer.hooks())).get("result", {}).get("status") == "blocked", "Changing sources during a test invalidates the verdict")
	peer.mutate = false
	peer.fail_launch = true
	check.call((await qa.run("health", peer.hooks())).get("result", {}).get("status") == "blocked", "Failed game launch is reported and cleaned up")
	var measured = {"id": "before", "status": "measured", "scene": peer.scene, "frames": 240, "warmup_frames": 60, "environment": {"os": "fixture"}, "measurements": {"average_frame_ms": 20, "p95_frame_ms": 30}}
	var after = measured.duplicate(true)
	after["id"] = "after"
	after["measurements"]["average_frame_ms"] = 10
	check.call(scripts["engineering"].compare_measurements(measured, after).get("result", {}).get("metrics", {}).get("average_frame_ms", {}).get("percent") == -50, "Performance comparison computes actual metric deltas")
	after["environment"]["os"] = "other-device"
	check.call(scripts["engineering"].compare_measurements(measured, after).get("code") == "profile_incomparable", "Profiles from different environments cannot be compared")
	check.call(scripts["engineering"].current_errors({"issues": [{"severity": "error", "stale": false, "source": "debugger", "active": false}, {"severity": "error", "stale": true, "source": "script:a"}, {"severity": "error", "stale": false, "source": "script:b"}]}).size() == 1, "Repair evidence separates current errors from stale and stopped-session history")
	check.call(not scripts["engineering"].diagnostics_complete({}), "Missing diagnostics never prove a clean repair")
	var repair_owner = RepairOwner.new()
	repair_owner.project_directory = private
	repair_owner.agent_jobs = RuntimePeer.new()
	tree.root.add_child(repair_owner)
	var coordinator = scripts["engineering"].new()
	coordinator.configure(repair_owner, private, state)
	coordinator.qa_session = 2
	coordinator.qa_generation = 7
	check.call((await coordinator.runtime("status", {}, {})).get("code") == "runtime_session_changed" and repair_owner.agent_jobs.arguments["__session"] == 2 and repair_owner.agent_jobs.arguments["__generation"] == 7, "Simulated peer: coordinator pins session/generation and rejects a replacement runtime")
	var persisted_job = "interrupted-child"
	common.atomic_json(private.path_join("jobs").path_join(persisted_job + ".json"), {"id": persisted_job, "status": "running", "report": ""})
	var recovered_jobs = scripts["agent_jobs"].new(repair_owner)
	check.call((await recovered_jobs.wait_for(persisted_job, {})).get("result", {}).get("status") == "interrupted", "After restart an unfinished child report remains interrupted instead of being silently relaunched")
	peer = GamePeer.new()
	peer.fingerprint_override = coordinator.fingerprint()
	peer.value = 3
	var failing = await coordinator.scenarios.run("health", peer.hooks())
	var repair = await coordinator.repair_start({"goal": "Restore health", "reports": [failing["result"]["id"]]}, {})
	check.call(repair.get("result", {}).get("observed_failure", false), "Repair baseline records an actual failed saved assertion: " + JSON.stringify(repair))
	if not repair.get("ok", false):
		repair_owner.queue_free()
		return
	var blocked = await coordinator.repair_check({"id": repair["result"]["id"]}, {})
	check.call(blocked.get("result", {}).get("status") == "blocked", "Clean parser output alone cannot certify a behavioral repair")
	peer.value = 7
	var passing = await coordinator.scenarios.run("health", peer.hooks())
	var verified = await coordinator.repair_check({"id": repair["result"]["id"], "reports": [passing["result"]["id"]]}, {})
	check.call(verified.get("result", {}).get("status") == "verified" and state.memories().any(func(item: Dictionary) -> bool: return item.get("kind") == "verified_workflow"), "Simulated diagnostics and game bridge: unchanged regression plus fresh clean sources verify repair and record evidence-backed workflow")
	var unproven = await coordinator.repair_start({"goal": "Unobserved theory", "hypothesis": "Maybe physics"}, {})
	check.call((await coordinator.repair_check({"id": unproven["result"]["id"], "reports": [passing["result"]["id"]]}, {})).get("result", {}).get("status") == "blocked", "An unobserved hypothesis cannot become a verified repair")
	write("res://engineering_test/stale-proof.txt", "changed after test")
	check.call((await coordinator.repair_check({"id": repair["result"]["id"], "reports": [passing["result"]["id"]]}, {})).get("code") == "stale_evidence", "Repair check rejects a passed report after saved project sources change")
	var toolset = scripts["editor_tools"].new()
	var source = "[gd_scene load_steps=2 format=3]\n[ext_resource type=\"Script\" path=\"res://engineering_test/player.gd\" id=\"1\"]\n[node name=\"Root\" type=\"Node\"]\nscript = ExtResource(\"1\")\n[node name=\"Button\" type=\"Button\" parent=\".\"]\n[connection signal=\"pressed\" from=\"Button\" to=\".\" method=\"_on_pressed\"]\n"
	var relations = scripts["project_knowledge"]._relations(source, "tscn", toolset)
	check.call(relations.any(func(row: Dictionary) -> bool: return row.get("kind") == "attached_script" and row.get("node") == "." and row.get("script") == "res://engineering_test/player.gd"), "Scene map associates scripts with actual node paths")
	check.call(relations.any(func(row: Dictionary) -> bool: return row.get("kind") == "signal_connection" and row.get("method") == "_on_pressed"), "Scene map retains signal connections and target methods")
	var code_relations = scripts["project_knowledge"]._relations("extends Node\nsignal ready_for_test\n# get_node(\"Fake\")\nfunc f():\n\treturn $Player/Health\n", "gd", toolset)
	check.call(code_relations.size() == 2, "Script map extracts signals and literal node paths while excluding comments")
	var knowledge = scripts["project_knowledge"].new()
	knowledge.state["files"] = {"res://a.gd": {"path": "res://a.gd", "dependencies": []}, "res://b.tscn": {"path": "res://b.tscn", "dependencies": ["res://a.gd"]}, "res://c.tscn": {"path": "res://c.tscn", "dependencies": ["res://b.tscn"]}}
	check.call(knowledge.impact("res://a.gd").get("result", {}).get("affected", []).size() == 3, "Impact map follows transitive dependents")
	write("res://engineering_test/player.gd", "extends Node\n")
	write("res://engineering_test/test.tscn", source)
	var copies = scripts["experiments"].new()
	copies.configure(private)
	var created = await copies.create("Alternative A", tree, {})
	check.call(created.get("ok", false), "Experiment creates a real independent copy of the fixture project")
	if created.get("ok", false):
		var id: String = created["result"]["id"]
		var original_hash = FileAccess.get_sha256("res://engineering_test/player.gd")
		var changed = copies.write_file(id, "res://engineering_test/player.gd", "extends Node\n# alternative\n", original_hash)
		check.call(changed.get("ok", false) and FileAccess.get_sha256("res://engineering_test/player.gd") == original_hash, "Editing an experiment leaves original bytes untouched")
		check.call(copies.proposals(id, ["res://engineering_test/player.gd"]).get("result", {}).get("changes", [])[0].get("action") == "write", "Experiment prepares the existing guarded change-set format")
		write("res://engineering_test/player.gd", "extends Node\n# user changed original\n")
		check.call(copies.proposals(id).get("code") == "experiment_conflict", "Later edits in the original block experiment integration")
		check.call(copies.write_file(id, "res://../outside.gd", "outside", "missing").get("code") == "invalid_file", "Experiment writes reject traversal outside the copy")
		check.call(copies.write_file(id, "res://engineering_test/player.gd", "old", original_hash).get("code") == "experiment_conflict", "Experiment writes require a fresh content hash")
		copies.write_file(id, "res://engineering_test/dependent.txt", "requires alternative player", "missing")
		coordinator.qa_project = created["result"]["project"]
		peer = GamePeer.new()
		peer.experiment = id
		peer.fingerprint_override = coordinator.fingerprint()
		var tested_copy = await coordinator.scenarios.run("health", peer.hooks())
		var guarded_stage = await coordinator._stage({"id": id, "report": tested_copy["result"]["id"], "paths": ["res://engineering_test/player.gd"]}, {})
		check.call(guarded_stage.get("code") == "partial_experiment", "A passed full-copy test cannot certify a subset that omits a changed dependency")
		check.call((await coordinator._stage({"id": id, "report": tested_copy["result"]["id"]}, {})).get("code") == "experiment_conflict", "Even a passed experiment report preserves the user's later original edit")
		check.call(copies.list_saved().get("result", {}).get("items", []).any(func(row: Dictionary) -> bool: return row.get("id") == id), "Experiment IDs remain discoverable from their saved manifests")
	var mesh_root = Node3D.new()
	var mesh = MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	mesh.mesh.height = 4
	mesh.mesh.radius = 2
	mesh.mesh.material = StandardMaterial3D.new()
	mesh_root.add_child(mesh)
	var document = GLTFDocument.new()
	var gltf_state = GLTFState.new()
	var exported = document.append_from_scene(mesh_root, gltf_state) == OK and document.write_to_filesystem(gltf_state, "res://engineering_test/sphere.glb") == OK
	mesh_root.free()
	check.call(exported, "Asset test exports real geometry through native GLTFDocument")
	if exported:
		var hash = FileAccess.get_sha256("res://engineering_test/sphere.glb")
		var audit = scripts["asset_audit"].audit("res://engineering_test/sphere.glb")
		check.call(audit.get("ok", false) and audit["result"]["meshes"] == 1 and audit["result"]["triangles"] > 0, "Asset audit measures actual imported GLB geometry")
		var prepared = scripts["asset_audit"].prepare({"path": "res://engineering_test/sphere.glb", "destination": "res://engineering_test/prepared.tscn", "height_m": 2, "ground_pivot": true, "generate_lods": true, "collision": "convex"})
		check.call(prepared.get("ok", false), "Asset preparation creates a real game prefab with collision and LOD processing")
		check.call(FileAccess.get_sha256("res://engineering_test/sphere.glb") == hash, "Asset preparation preserves the original GLB exactly")
		check.call(not scripts["asset_audit"].prepare({"path": "res://engineering_test/sphere.glb", "destination": "res://engineering_test/prepared.tscn"}).get("ok", false), "Asset preparation never overwrites an existing prefab")
		if prepared.get("ok", false):
			var packed: PackedScene = load("res://engineering_test/prepared.tscn")
			var instance = packed.instantiate()
			var measured_asset = scripts["asset_audit"].inspect_scene(instance)
			check.call(measured_asset.get("ok", false) and is_equal_approx(measured_asset["result"]["bounds"]["size"][1], 2.0) and absf(measured_asset["result"]["bounds"]["position"][1]) < 0.001 and measured_asset["result"]["collision_shapes"] >= 1, "Reloaded prefab has normalized height, grounded pivot and actual collision geometry")
			instance.free()

	repair_owner.queue_free()
