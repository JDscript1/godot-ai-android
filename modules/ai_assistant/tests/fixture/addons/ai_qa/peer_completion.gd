extends RefCounted

class Host:
	extends RefCounted
	var panel: Control
	var contexts: Array = []
	var replies = 0
	func complete(context: Array, _tools: Array, _cancel: Dictionary, _delta: Callable) -> Dictionary:
		contexts.append(context.duplicate(true))
		replies += 1
		var calls = [{"id": "barrier-start", "name": "ziva_task_start", "arguments": {"prompt": "Verifică scena."}}] if replies == 1 else []
		return {"ok": true, "message": {"role": "assistant", "content": "Final fără așteptare" if replies == 2 else "Am citit rezultatul real.", "tool_calls": calls}, "calls": calls, "finish": "stop"}
	func execute(name: String, args: Dictionary) -> Dictionary: return await panel._agent_call(name, args)

func run(qa: EditorPlugin, panel: Control, bridge: Node) -> void:
	var saved = {"jobs": panel.ziva_jobs.duplicate(true), "turn": panel.current_turn, "busy": panel.busy, "cancel": panel.cancel, "mutations": panel.turn_has_mutations, "plan": panel.planner.snapshot(), "verification": panel.verification.snapshot(), "poll": panel.ziva_poll_interval}
	panel.busy = true
	panel.current_turn = "barrier-fixture"
	panel.ziva_poll_interval = 0.01
	var definitions: Array = panel._agent_definitions().filter(func(tool: Dictionary) -> bool: return tool["name"] == "ziva_task_start")
	for state in ["completed", "error", "permission_required", "question_required"]:
		panel.ziva_jobs = {}
		panel.cancel = {"cancelled": false}
		panel.turn_has_mutations = false
		panel.verification.reset()
		panel.planner.reset("barrier-fixture")
		bridge.chat["scripted"] = [{"state": "running"}, {"state": "running"}, {"state": state, "answer": "Rezultat extern verificat.", "error": "Problemă simulată" if state == "error" else "", "tools": 0}]
		var host = Host.new()
		host.panel = panel
		var core = panel.Harness.new(qa)
		var messages = []
		var outcome: Dictionary = await core.run({"metadata": {"turn_id": panel.current_turn}, "messages": messages, "tools": definitions, "cancel": panel.cancel, "max_steps": 8}, {"complete": host.complete, "execute": host.execute, "completion_prepare": panel._prepare_completion, "completion_problem": panel._completion_problem})
		if state == "completed":
			qa._check(outcome.get("status") == "completed" and host.replies == 3, "The real native harness awaits an asynchronous Ziva result without spending no-progress reminders")
			qa._check(host.contexts[2].any(func(message: Dictionary) -> bool: return message.get("application_message") == "external_result" and "Rezultat extern verificat." in str(message.get("content", ""))), "The model receives the actual collaborator result before producing its final answer")
			var job_id = str(bridge.chat["job"])
			await panel._agent_call("ziva_task_cancel", {"job_id": job_id})
			qa._check(panel.ziva_jobs[job_id]["state"] == "completed" and panel._completion_problem().is_empty(), "Cancelling a completed backend job preserves its true completed state")
		else:
			qa._check(outcome.get("status") == "blocked" and outcome.get("code") == "verification_required", "The real native harness rejects a final success claim while Ziva reports " + state)
	# Unknown and unconsumed states also fail closed.
	panel.ziva_jobs = {"unconsumed": {"job_id": "unconsumed", "turn_id": panel.current_turn, "state": "completed", "required": true, "ingested": false}}
	qa._check(not panel._completion_problem().is_empty(), "A completed but unread external result cannot bypass completion verification")
	panel.ziva_jobs["unconsumed"]["state"] = "future_wait_state"
	qa._check(not panel._completion_problem().is_empty() and panel._peer_request("query", {"text": "Circular"}).get("code") == "peer_cycle", "Unknown external wait states block success and circular incoming tasks")
	var snapshot: Dictionary = panel._ziva_checkpoint()
	panel.ziva_jobs = {}
	var before = bridge.requests.size()
	panel._ziva_restore(snapshot)
	qa._check(panel.ziva_jobs["unconsumed"]["state"] == "interrupted" and not panel._completion_problem().is_empty() and bridge.requests.size() == before, "Resuming preserves an unfinished delegation without resubmitting its external effects")
	panel.ziva_jobs = {}
	for index in panel.ZIVA_JOB_LIMIT: panel.ziva_jobs[str(index)] = {"turn_id": panel.current_turn, "state": "error", "required": true}
	var refused: Dictionary = await panel._ziva_task({"prompt": "Nu elimina eșecurile anterioare."}, false)
	qa._check(refused.get("code") == "delegation_capacity" and panel.ziva_jobs.size() == panel.ZIVA_JOB_LIMIT and bridge.requests.size() == before and not panel._completion_problem().is_empty(), "Capacity checks never discard unmet current-turn delegations or send another external job")
	panel.ziva_jobs = saved["jobs"]
	panel.current_turn = saved["turn"]
	panel.busy = saved["busy"]
	panel.cancel = saved["cancel"]
	panel.turn_has_mutations = saved["mutations"]
	panel.planner.restore(saved["plan"])
	panel.verification.restore(saved["verification"])
	panel.ziva_poll_interval = saved["poll"]
