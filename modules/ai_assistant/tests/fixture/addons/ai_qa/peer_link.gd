extends RefCounted

func run(qa: EditorPlugin, panel: Control, bridge: Node) -> void:
	var saved = {"busy": panel.busy, "queued": panel.queued.duplicate(true), "jobs": panel.peer_jobs.duplicate(true), "origin": panel.current_origin.duplicate(true), "turn": panel.current_turn, "history": panel.history.duplicate(true), "paused": panel.queue_paused, "waiting": panel.ziva_waiting, "mode": panel.mode_picker.selected, "runtime": panel.ziva_runtime}
	saved["profiles"] = panel.config["providers"].duplicate(true)
	saved["selection"] = panel._selection()
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
	panel.current_origin["peer_source"] = "ziva"
	var bounced: Dictionary = await panel._ziva_task({"prompt": "Bounce"}, false)
	qa._check(bounced.get("code") == "peer_cycle", "A Ziva-origin native task cannot delegate itself back to Ziva")
	panel.current_origin.erase("peer_source")
	var started: Dictionary = await panel._agent_call("ziva_task_start", {"prompt": "Mesaj asincron."})
	qa._check(started.get("ok", false) and started["result"]["state"] == "running" and panel.ziva_waiting == 0, "Native agents can start a Ziva job without blocking their own turn")
	var cancelled: Dictionary = await panel._agent_call("ziva_task_cancel", {"job_id": started.get("result", {}).get("job_id", "")})
	qa._check(cancelled.get("state") == "cancelled", "Native agents can cancel an exact Ziva job")
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
	panel.current_origin = saved["origin"]
	panel.current_turn = saved["turn"]
	panel.history = saved["history"]
	panel.queue_paused = saved["paused"]
	panel.ziva_waiting = saved["waiting"]
	panel.mode_picker.select(saved["mode"])
	panel.ziva_runtime = saved["runtime"]
	panel._sync_queue()
