extends RefCounted

func _peer_temp_dir() -> String:
	var path = ProjectSettings.globalize_path("user://").path_join("ai_qa_peer_" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(path)
	return path

func _remove_tree(path: String) -> void:
	var directory = DirAccess.open(path)
	if directory == null: return
	for file in directory.get_files(): DirAccess.remove_absolute(path.path_join(file))
	for child in directory.get_directories(): _remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)

func run(qa: EditorPlugin, panel: Control, bridge: Node) -> void:
	var saved = {"busy": panel.busy, "queued": panel.queued.duplicate(true), "jobs": panel.peer_jobs.duplicate(true), "origin": panel.current_origin.duplicate(true), "turn": panel.current_turn, "history": panel.history.duplicate(true), "paused": panel.queue_paused, "waiting": panel.ziva_waiting, "mode": panel.mode_picker.selected, "runtime": panel.ziva_runtime}
	saved["profiles"] = panel.config["providers"].duplicate(true)
	saved["selection"] = panel._selection()
	saved["archive"] = panel.peer_archive.duplicate(true)
	saved["peer_directory"] = panel.peer_store_directory
	saved["peer_error"] = panel.peer_journal_error
	saved["ziva_jobs"] = panel.ziva_jobs.duplicate(true)
	saved["ziva_poll"] = panel.ziva_poll_interval
	saved["mutations"] = panel.turn_has_mutations
	saved["verification"] = panel.verification.snapshot()
	saved["planner"] = panel.planner.snapshot()
	var peer_directory = _peer_temp_dir()
	panel.peer_store_directory = peer_directory
	panel._peer_load_jobs()
	panel.config["providers"] = [{"id": "peer-fixture", "name": "Peer fixture", "kind": "chat", "url": "http://127.0.0.1:1", "models": [{"id": "peer-model", "name": "Peer model", "context_window": 32768}]}]
	panel._refresh_profiles()
	panel.ziva_runtime = bridge
	panel.busy = true
	panel.current_turn = "peer-active"
	panel.peer_jobs = {}
	panel.queued = []
	panel.ziva_waiting = 0
	panel.mode_picker.select(1)
	var selection: Dictionary = panel._selection()
	panel.current_origin = {"profile_id": selection["profile"], "model_id": selection["model"], "effort": selection["effort"], "work_mode": selection["work_mode"], "provider_kind": "chat"}
	var state: Dictionary = panel._peer_request("status", {})
	qa._check(state.get("ok", false) and state["result"]["turn_id"] == "peer-active" and state["result"]["busy"], "Ziva can inspect the exact native agent turn without starting a model request")
	var received: Dictionary = panel._peer_request("query", {"text": "Descrie scena salvată."}, "peer-request-1")
	qa._check(received.get("ok", false) and received["result"]["state"] == "queued", "An inbound Ziva question is acknowledged as queued instead of completed")
	var id = str(received.get("result", {}).get("job_id", ""))
	qa._check(not id.is_empty() and panel.queued[-1]["selection"]["peer_job"] == id and panel.queued[-1]["selection"]["ui_mode"] == 3, "Peer queries are correlated and always use the real read-only Ask mode")
	qa._check(panel.queued[-1]["selection"]["files"].is_empty() and panel.queued[-1]["selection"]["attachments"].is_empty(), "Peer requests never inherit unrelated draft files or attachments")
	var journal_path = peer_directory.path_join("peer_jobs.json")
	var persisted: Variant = JSON.parse_string(FileAccess.get_file_as_string(journal_path))
	var persisted_jobs: Dictionary = persisted.get("jobs", {}) if persisted is Dictionary else {}
	qa._check(persisted is Dictionary and persisted.get("version") == 1 and persisted_jobs.has(id) and persisted_jobs[id].get("request_id") == "peer-request-1" and persisted_jobs[id].get("state") == "queued", "An inbound peer request is durably recorded before it is acknowledged or queued")
	var duplicate: Dictionary = panel._peer_request("query", {"text": "Descrie scena salvată."}, "peer-request-1")
	qa._check(duplicate.get("ok", false) and duplicate["result"]["job_id"] == id and panel.queued.size() == 1, "A repeated request_id returns the original job without enqueuing a duplicate")
	qa._check(panel._peer_request("task", {"text": "Alt tip."}, "peer-request-1").get("code") == "request_conflict", "A request_id reused for a different action is rejected")
	qa._check(panel._peer_request("query", {"text": "Alt text."}, "peer-request-1").get("code") == "request_conflict", "A repeated request id cannot silently replace the original message")
	var task: Dictionary = panel._peer_request("task", {"text": "Verifică scriptul."})
	var task_id = str(task.get("result", {}).get("job_id", ""))
	qa._check(task.get("ok", false) and task_id != id and panel.queued[-1]["selection"]["ui_mode"] == 1, "Inbound tasks get distinct jobs and retain the selected execution mode")
	var stopped: Dictionary = panel._peer_request("cancel", {"job_id": task_id})
	qa._check(stopped.get("result", {}).get("state") == "cancelled" and panel.queued.size() == 1 and panel.queued[0]["selection"]["peer_job"] == id and panel.busy, "Cancelling a queued peer job preserves other requests and the active turn")
	qa._check(panel._peer_request("cancel", {"turn_id": "older-turn"}).get("code") == "stale_turn" and panel._peer_request("steer", {"turn_id": "older-turn", "text": "Ajustare"}).get("code") == "stale_turn", "Stale peer controls cannot stop or steer a newer native turn")
	var steering: Dictionary = panel._peer_request("steer", {"turn_id": "peer-active", "text": "Inspectează și scriptul."})
	qa._check(steering.get("ok", false) and panel.queued[-1]["delivery"] == "steer" and panel.queued[-1]["turn"] == "peer-active", "Ziva steering uses the existing next-step delivery for the exact active turn")
	panel.ziva_waiting = 1
	qa._check(panel._peer_request("query", {"text": "Nu aștepta circular."}).get("code") == "peer_cycle" and panel._peer_request("status", {})["result"]["waiting_for_ziva"], "A native turn awaiting Ziva refuses circular delegation while keeping status available")
	panel.ziva_waiting = 0
	panel._peer_started(id, "peer-result")
	panel.history.append({"role": "assistant", "turn_id": "unrelated", "content": "Unrelated answer"})
	panel.history.append({"role": "assistant", "turn_id": "peer-result", "content": "Detaliu ".repeat(1000)})
	panel._peer_finished("peer-result", "completed")
	var answer: Dictionary = panel._peer_request("result", {"job_id": id, "offset": 6000, "limit": 200})
	qa._check(answer.get("ok", false) and answer["result"]["state"] == "completed" and answer["result"]["answer"].length() == 200 and answer["result"]["next_offset"] == 6200 and not "Unrelated" in answer["result"]["answer"], "Peer results keep exact turn correlation and bounded answer pagination")
	qa._check(panel._peer_request("result", {"job_id": "missing"}).get("code") == "unknown_job" and panel._peer_request("approve", {}).get("code") == "unknown_action", "The peer cannot read unknown jobs or approve permission dialogs")
	var completed_file: Variant = JSON.parse_string(FileAccess.get_file_as_string(journal_path))
	var completed_jobs: Dictionary = completed_file.get("jobs", {}) if completed_file is Dictionary else {}
	qa._check(completed_jobs.get(id, {}).get("state") == "completed" and str(completed_jobs[id].get("answer", "")).length() > 6000, "Completed peer answers are retained durably with their full pagination range")
	panel.peer_jobs = {}
	panel.peer_archive = []
	panel._peer_load_jobs()
	var restored_answer: Dictionary = panel._peer_request("result", {"job_id": id, "offset": 6000, "limit": 200})
	qa._check(restored_answer.get("ok", false) and restored_answer["result"]["state"] == "completed" and restored_answer["result"]["answer"].length() == 200 and restored_answer["result"]["next_offset"] == 6200, "Completed peer answers and pagination survive a reload")
	var running: Dictionary = panel._peer_request("task", {"text": "Sarcină întreruptă."})
	var running_id = str(running.get("result", {}).get("job_id", ""))
	panel.queued = panel.queued.filter(func(item: Dictionary) -> bool: return item.get("selection", {}).get("peer_job") != running_id)
	panel._sync_queue()
	panel._peer_started(running_id, "peer-restart-turn")
	panel.peer_jobs = {}
	panel.peer_archive = []
	panel._peer_load_jobs()
	var interrupted: Dictionary = panel._peer_request("result", {"job_id": running_id, "limit": 200})
	qa._check(interrupted.get("ok", false) and interrupted["result"]["state"] == "interrupted" and interrupted["result"]["turn_id"] == "" and not panel.queued.any(func(item: Dictionary) -> bool: return item.get("selection", {}).get("peer_job") == running_id), "A running peer job is recovered as interrupted without replay or requeue")
	var orphan: Dictionary = panel._peer_request("query", {"text": "Cerere fără coadă."})
	var orphan_id = str(orphan.get("result", {}).get("job_id", ""))
	panel.queued = panel.queued.filter(func(item: Dictionary) -> bool: return item.get("selection", {}).get("peer_job") != orphan_id)
	panel._sync_queue()
	panel.peer_jobs = {}
	panel.peer_archive = []
	panel._peer_load_jobs()
	var orphan_result: Dictionary = panel._peer_request("result", {"job_id": orphan_id})
	qa._check(orphan_result.get("ok", false) and orphan_result["result"]["state"] == "cancelled", "A queued peer job missing from the durable queue is recovered as cancelled")
	var file = FileAccess.open(journal_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	panel.peer_jobs = {}
	panel.peer_archive = []
	panel._peer_load_jobs()
	var queue_before_corrupt = panel.queued.size()
	var corrupt_rejected: Dictionary = panel._peer_request("query", {"text": "Nu trebuie acceptată."})
	qa._check(not panel.peer_journal_error.is_empty() and corrupt_rejected.get("code") == "peer_journal_unavailable" and panel.queued.size() == queue_before_corrupt and panel.peer_jobs.is_empty(), "A corrupt peer journal fails closed without accepting or queueing new work")
	DirAccess.remove_absolute(journal_path)
	panel._peer_load_jobs()
	DirAccess.make_dir_recursive_absolute(journal_path)
	panel._peer_load_jobs()
	var queue_before_write = panel.queued.size()
	var write_rejected: Dictionary = panel._peer_request("query", {"text": "Nu se poate salva."})
	qa._check(write_rejected.get("code") == "peer_journal_unavailable" and panel.queued.size() == queue_before_write and panel.peer_jobs.is_empty(), "A failed durable write rejects the request before it is acknowledged or queued")
	DirAccess.remove_absolute(journal_path)
	panel._peer_load_jobs()
	panel.peer_jobs = {}
	panel.peer_archive = []
	for index in range(24):
		var old_id = "peer-old-" + str(index)
		panel.peer_jobs[old_id] = {"job_id": old_id, "request_id": "old-" + str(index), "state": "completed", "turn_id": "", "answer": "Răspuns arhivat " + str(index), "kind": "query", "created": index, "updated": index}
	panel._peer_persist()
	var capped: Dictionary = panel._peer_request("query", {"text": "Cerere după plafon."})
	qa._check(capped.get("ok", false) and panel.peer_jobs.size() == 24 and panel.peer_archive.size() == 1, "Active peer jobs are capped by archiving terminal records instead of deleting them")
	var archived_result: Dictionary = panel._peer_request("result", {"job_id": "peer-old-0"})
	qa._check(archived_result.get("ok", false) and archived_result["result"]["state"] == "completed" and archived_result["result"]["answer"] == "Răspuns arhivat 0", "Archived peer jobs remain retrievable with their completed answer")
	var cached_archive: Array = panel.peer_archive.duplicate(true)
	panel.peer_archive.clear()
	var receipt_answer: Dictionary = panel._peer_request("result", {"job_id": "peer-old-0"})
	var queued_before_receipt = panel.queued.size()
	var receipt_replay: Dictionary = panel._peer_request("query", {"text": "Original archived request"}, "old-0")
	qa._check(receipt_answer.get("result", {}).get("answer") == "Răspuns arhivat 0" and receipt_replay.get("result", {}).get("job_id") == "peer-old-0" and panel.queued.size() == queued_before_receipt, "Archived receipts preserve answers and request replay protection after cache eviction")
	panel.peer_archive = cached_archive
	await _storage_failures(qa, panel, peer_directory)
	panel.current_origin["peer_source"] = "ziva"
	var bounced: Dictionary = await panel._ziva_task({"prompt": "Bounce"}, false)
	qa._check(bounced.get("code") == "peer_cycle", "A Ziva-origin native task cannot delegate itself back to Ziva")
	panel.current_origin.erase("peer_source")
	var started: Dictionary = await panel._agent_call("ziva_task_start", {"prompt": "Mesaj asincron."})
	qa._check(started.get("ok", false) and started["result"]["state"] == "running" and panel.ziva_waiting == 0, "Native agents can start a Ziva job without blocking their own turn")
	var cancelled: Dictionary = await panel._agent_call("ziva_task_cancel", {"job_id": started.get("result", {}).get("job_id", "")})
	qa._check(cancelled.get("state") == "cancelled", "Native agents can cancel an exact Ziva job")
	# A started outbound job is required turn work by default, not fire-and-forget.
	panel.planner.reset("peer-active", false)
	panel.turn_has_mutations = false
	panel.verification.reset()
	panel.ziva_jobs = {}
	panel.cancel = {"cancelled": false}
	panel.ziva_poll_interval = 0.01
	bridge.chat["state"] = "running"
	bridge.chat["answer"] = ""
	bridge.chat["error"] = ""
	bridge.chat["waiting"] = {}
	bridge.chat["scripted"] = []
	var before_revision = panel.verification.revision
	var required_start: Dictionary = await panel._agent_call("ziva_task_start", {"prompt": "Verifică obligatoriu.", "background": true})
	var required_id = str(required_start.get("result", {}).get("job_id", ""))
	qa._check(required_start.get("ok", false) and not required_id.is_empty() and panel.ziva_jobs.get(required_id, {}).get("required", false) and panel.ziva_jobs[required_id].get("turn_id") == "peer-active", "A started Ziva job is required for the native turn regardless of model hints")
	var running_problem = panel._completion_problem()
	qa._check(not running_problem.is_empty() and required_id in running_problem, "Completion is blocked while a required Ziva job is still running")
	var polls_before = bridge.requests.filter(func(request: Dictionary) -> bool: return request["action"] == "ziva_chat_poll").size()
	bridge.chat["scripted"] = [{"state": "running"}, {"state": "running"}, {"state": "completed", "answer": "Rezultat verificat de Ziva.", "tools": 0}]
	var prepared: Dictionary = await panel._prepare_completion()
	var polls_after = bridge.requests.filter(func(request: Dictionary) -> bool: return request["action"] == "ziva_chat_poll").size()
	var notice_text = ""
	if not prepared.get("notices", []).is_empty(): notice_text = str(prepared["notices"][0].get("content", ""))
	qa._check(prepared.get("ok", false) and prepared.get("notices", []).size() == 1 and "Rezultat verificat de Ziva." in notice_text and polls_after - polls_before >= 3, "Completion preparation awaits real Ziva polls instead of consuming no-progress reminders")
	qa._check(panel.ziva_jobs[required_id].get("state") == "completed" and panel._completion_problem().is_empty(), "A completed required Ziva job unblocks completion without verification churn")
	var cached_result: Dictionary = panel._ziva_completed({"job_id": required_id, "state": "completed", "answer": "Rezultat verificat de Ziva.", "tools": 1})
	qa._check(cached_result.get("ok", false) and panel.verification.revision == before_revision and not panel.turn_has_mutations, "Repeated completion polling is idempotent and does not invalidate verification again")
	panel.ziva_jobs = {}
	panel.turn_has_mutations = false
	panel.verification.reset()
	before_revision = panel.verification.revision
	var mutating_start: Dictionary = await panel._agent_call("ziva_task_start", {"prompt": "Verifică mutațiile."})
	var mutating_id = str(mutating_start.get("result", {}).get("job_id", ""))
	panel._ziva_completed({"job_id": mutating_id, "state": "completed", "answer": "Am modificat proiectul.", "tools": 1})
	qa._check(panel.verification.revision == before_revision + 1 and panel.turn_has_mutations, "A real Ziva mutation invalidates verification once")
	panel._ziva_completed({"job_id": mutating_id, "state": "completed", "answer": "Am modificat proiectul.", "tools": 1})
	qa._check(panel.verification.revision == before_revision + 1, "Repeated polling of the same Ziva completion does not invalidate verification again")
	panel.ziva_jobs = {}
	panel.turn_has_mutations = false
	panel.verification.reset()
	var failed_start: Dictionary = await panel._agent_call("ziva_task_start", {"prompt": "Eșuează obligatoriu."})
	var failed_id = str(failed_start.get("result", {}).get("job_id", ""))
	bridge.chat["scripted"] = [{"state": "error", "error": "Eroare obligatorie simulată."}]
	var failed_prepare: Dictionary = await panel._prepare_completion()
	qa._check(failed_prepare.get("ok", false) and panel.ziva_jobs.get(failed_id, {}).get("state") == "error", "Completion preparation records a terminal Ziva failure instead of retrying forever")
	var failed_problem = panel._completion_problem()
	qa._check(not failed_problem.is_empty() and "Eroare obligatorie simulată." in failed_problem, "A failed required Ziva job blocks a success claim")
	panel.ziva_jobs = {}
	panel.turn_has_mutations = false
	panel.verification.reset()
	var cancelled_start: Dictionary = await panel._agent_call("ziva_task_start", {"prompt": "Anulează obligatoriu."})
	var cancelled_id = str(cancelled_start.get("result", {}).get("job_id", ""))
	await panel._agent_call("ziva_task_cancel", {"job_id": cancelled_id})
	var cancelled_problem = panel._completion_problem()
	qa._check(not cancelled_problem.is_empty() and cancelled_id in cancelled_problem, "A cancelled required Ziva job blocks a success claim")
	panel.ziva_jobs = {}
	panel.ziva_poll_interval = saved["ziva_poll"]
	panel.turn_has_mutations = saved["mutations"]
	panel.verification.restore(saved["verification"])
	await load(get_script().resource_path.get_base_dir().path_join("peer_completion.gd")).new().run(qa, panel, bridge)
	var original_provider = panel.providers
	var original_draft = panel.composer.text
	var original_files: Array = panel.pending_files.duplicate()
	var e2e: Dictionary = panel._peer_request("query", {"text": "Inspectează proiectul fără modificări."})
	var e2e_id = str(e2e.get("result", {}).get("job_id", ""))
	var queued_query: Dictionary = panel.queued.filter(func(item: Dictionary) -> bool: return item.get("selection", {}).get("peer_job") == e2e_id)[0]
	panel.queued.clear()
	panel.history.clear()
	panel.busy = false
	panel.composer.text = "Ciornă păstrată"
	panel.pending_files = ["draft-file"]
	var provider = qa.FixtureAskProvider.new()
	panel.providers = provider
	await panel._start_chat(str(queued_query["text"]), queued_query["selection"])
	var e2e_answer: Dictionary = panel._peer_request("result", {"job_id": e2e_id})
	qa._check(e2e_answer.get("result", {}).get("state") == "completed" and e2e_answer["result"]["answer"] == "Proiect inspectat fără modificări." and panel.current_origin.get("peer_source") == "ziva", "A real inbound query runs through the native harness and publishes its correlated answer")
	qa._check(not FileAccess.file_exists("res://ask-must-not-exist.txt") and not provider.catalog.any(func(tool: Dictionary) -> bool: return tool.get("risk") != "read"), "A provider attempting a write during a peer query cannot escape Ask restrictions")
	qa._check(panel.composer.text == "Ciornă păstrată" and panel.pending_files == ["draft-file"], "Executing a peer query preserves the user's composer draft and draft attachments")
	panel.providers = original_provider
	panel.composer.text = original_draft
	panel.pending_files = original_files
	panel.config["providers"] = saved["profiles"]
	panel._refresh_profiles()
	panel._choose(saved["selection"])
	panel.busy = saved["busy"]
	panel.queued = saved["queued"]
	panel.peer_jobs = saved["jobs"]
	panel.peer_archive = saved["archive"]
	panel.peer_store_directory = saved["peer_directory"]
	panel.peer_journal_error = saved["peer_error"]
	panel.ziva_jobs = saved["ziva_jobs"]
	panel.ziva_poll_interval = saved["ziva_poll"]
	panel.turn_has_mutations = saved["mutations"]
	panel.verification.restore(saved["verification"])
	panel.planner.restore(saved["planner"])
	panel.current_origin = saved["origin"]
	panel.current_turn = saved["turn"]
	panel.history = saved["history"]
	panel.queue_paused = saved["paused"]
	panel.ziva_waiting = saved["waiting"]
	panel.mode_picker.select(saved["mode"])
	panel.ziva_runtime = saved["runtime"]
	_remove_tree(peer_directory)
	panel._sync_queue()

func _storage_failures(qa: EditorPlugin, panel: Control, directory: String) -> void:
	var old_error = panel.engineering_store.load_error
	var before: Array = panel.queued.duplicate(true)
	panel.engineering_store.load_error = "Fixture queue journal failure"
	var refused: Dictionary = panel._peer_request("query", {"text": "Do not acknowledge an unsaved queue"})
	qa._check(refused.get("code") == "peer_queue_unavailable" and panel.queued == before, "Peer work is not acknowledged or dispatched when queue persistence fails")
	panel.engineering_store.load_error = old_error
	var received: Dictionary = panel._peer_request("query", {"text": "Do not dispatch an unsaved start"})
	var id = str(received.get("result", {}).get("job_id", ""))
	var entry: Dictionary = panel.queued.filter(func(item: Dictionary) -> bool: return item.get("selection", {}).get("peer_job") == id)[0]
	panel.queued = panel.queued.filter(func(item: Dictionary) -> bool: return item.get("selection", {}).get("peer_job") != id)
	panel._sync_queue()
	var saved = {"provider": panel.providers, "turn": panel.current_turn, "origin": panel.current_origin.duplicate(true), "mode": panel.mode_picker.selected, "plan": panel.planner.snapshot(), "verification": panel.verification.snapshot(), "mutations": panel.turn_has_mutations, "busy": panel.busy, "tools_turn": panel.tools.turn_id}
	var broken = directory.path_join("not-a-directory")
	var file = FileAccess.open(broken, FileAccess.WRITE)
	file.store_string("fixture")
	file.close()
	panel.peer_store_directory = broken
	panel.busy = false
	var provider = qa.FixtureAskProvider.new()
	panel.providers = provider
	await panel._start_chat(str(entry["text"]), entry["selection"])
	qa._check(provider.requests == 0 and not panel.busy and panel.peer_jobs[id]["state"] == "interrupted", "The actual native turn never reaches a provider or mutation if its peer start cannot be checkpointed")
	panel.providers = saved["provider"]
	panel.current_turn = saved["turn"]
	panel.current_origin = saved["origin"]
	panel.mode_picker.select(saved["mode"])
	panel.planner.restore(saved["plan"])
	panel.verification.restore(saved["verification"])
	panel.turn_has_mutations = saved["mutations"]
	panel.busy = saved["busy"]
	panel.tools.turn_id = saved["tools_turn"]
	panel.peer_store_directory = directory
	panel.peer_journal_error = ""
	panel._peer_persist()
	DirAccess.remove_absolute(broken)
