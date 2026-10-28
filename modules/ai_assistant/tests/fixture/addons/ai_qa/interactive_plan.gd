extends RefCounted
## Exercise the real panel, harness, persisted conversation and rendered controls; no API calls.
var host: EditorPlugin
var panel: Control

class PlanningProvider:
	extends RefCounted
	var requests = 0
	var contexts: Array = []
	var questions = [{"id": "view", "title": "Din ce perspectivă construim jocul?", "options": [{"id": "top", "label": "De sus", "description": "Hartă și explorare liberă."}, {"id": "side", "label": "Lateral", "description": "Platforme și obstacole."}]}, {"id": "features", "title": "Ce includem în primul prototip?", "multiple": true, "options": [{"id": "save", "label": "Salvarea progresului"}, {"id": "touch", "label": "Comenzi tactile"}]}]
	func complete(_profile: Dictionary, messages: Array, definitions: Array, _model: String, _effort: String, _cancel: Dictionary, _delta: Callable) -> Dictionary:
		requests += 1
		contexts.append({"messages": messages.duplicate(true), "tools": definitions.duplicate(true)})
		var calls = []
		if requests == 1: calls = [{"id": "planning-question", "name": "plan_ask", "arguments": {"questions": questions.duplicate(true)}}]
		if requests == 2: calls = [{"id": "planning-proposal", "name": "task_update", "arguments": {"intent": "propose", "phase": "completed", "tasks": ["Aplică perspectiva aleasă și comenzile tactile", "Verifică salvarea progresului"], "explanation": "Plan adaptat răspunsurilor primite."}}]
		return {"ok": true, "message": {"role": "assistant", "content": "Planul este pregătit conform alegerilor tale." if calls.is_empty() else "", "reasoning": {"kind": "chat", "content": "fixture verified reasoning"}, "tool_calls": calls}, "calls": calls, "finish": "stop"}

func _wait(predicate: Callable, label: String) -> bool:
	var deadline = Time.get_ticks_msec() + 10000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await host.get_tree().process_frame
	var ready = bool(predicate.call())
	host._check(ready, label)
	if not ready:
		host._activity_capture("interactive-plan-failure")
		print("Planning QA state: ", JSON.stringify({"busy": panel.busy, "question_waiting": panel.question_waiting, "status": panel.chat.status.text, "selection": panel._selection()}))
	return ready

func _click(control: Control) -> void:
	# Browsing to an older option is an explicit user scroll. Programmatic
	# ensure_control_visible must not race the active streaming follow mode.
	panel.chat.follow_bottom = false
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	panel.chat.scroll.ensure_control_visible(control)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.pressed = true
	control.get_viewport().push_input(event, true)
	event.pressed = false
	control.get_viewport().push_input(event, true)
	await host.get_tree().process_frame

func _touch(control: Control, drag: bool = false) -> void:
	panel.chat.follow_bottom = false
	panel.chat.scroll.ensure_control_visible(control)
	await host.get_tree().process_frame
	var point = control.get_global_rect().get_center()
	var event = InputEventScreenTouch.new()
	event.index = 2
	event.position = point
	event.pressed = true
	control.get_viewport().push_input(event, true)
	if drag:
		var motion = InputEventScreenDrag.new()
		motion.index = 2
		motion.position = point - Vector2(0, 70)
		motion.relative = Vector2(0, -70)
		control.get_viewport().push_input(motion, true)
		event.position = motion.position
	event.pressed = false
	control.get_viewport().push_input(event, true)
	await host.get_tree().process_frame

func _start(service: RefCounted) -> Dictionary:
	panel._new_conversation()
	panel.providers = service
	panel.mode_picker.select(2)
	panel._start_chat.call_deferred("Vreau să planificăm un joc pentru telefon.")
	if not await _wait(func() -> bool: return not panel.question_waiting.is_empty(), "The Plan provider opens an interactive question card"): return {}
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	return panel._question_record(panel.question_waiting)

func run(test_host: EditorPlugin, test_panel: Control) -> void:
	host = test_host
	panel = test_panel
	var original_service = panel.providers
	var original_providers = panel.config["providers"].duplicate(true)
	var original_selection = panel._selection()
	var original_permission = panel.full_control.button_pressed
	var original_history_requested = panel.chat.history_requested
	panel.settings_window.hide()
	panel.chat.show_history(false)
	panel.config["providers"] = [{"id": "interactive-plan", "name": "Plan QA", "kind": "chat", "issuer": "custom", "models": [{"id": "fixture"}]}]
	panel._refresh_profiles()
	panel._choose({"profile": "interactive-plan", "model": "fixture", "work_mode": "plan"})
	panel.full_control.button_pressed = true
	var service = PlanningProvider.new()
	var record = await _start(service)
	if record.is_empty(): return
	var id = str(record["id"])
	var card: Dictionary = panel.chat.question_cards[id]
	host._check(panel.busy and service.requests == 1 and card["submit"].disabled, "The harness waits without polling the model or accepting a preselected answer")
	host._check(not card["controls"]["view"]["choices"].values().any(func(button: CheckBox) -> bool: return button.button_pressed), "All choices begin unselected")
	panel.secrets.append("fixture-planning-secret")
	panel._save_question_draft({"id": id, "answers": {"view": {"text": "fixture-planning-secret"}}})
	host._check(not str(record["draft"]).contains("fixture-planning-secret"), "Draft persistence redacts configured credentials before writing conversation metadata")
	panel.secrets.erase("fixture-planning-secret")
	await _click(card["controls"]["view"]["choices"]["top"])
	await _click(card["controls"]["view"]["choices"]["side"])
	host._check(card["controls"]["view"]["choices"]["side"].button_pressed and not card["controls"]["view"]["choices"]["top"].button_pressed, "Mouse input switches a single-choice answer exclusively")
	await _touch(card["controls"]["view"]["choices"]["top"])
	host._check(card["controls"]["view"]["choices"]["top"].button_pressed and not card["controls"]["view"]["choices"]["side"].button_pressed, "A touch release selects a choice exactly once")
	await _touch(card["controls"]["view"]["choices"]["side"], true)
	host._check(card["controls"]["view"]["choices"]["top"].button_pressed and not card["controls"]["view"]["choices"]["side"].button_pressed, "Dragging over an option scrolls without changing the answer")
	await _touch(card["controls"]["view"]["choices"]["side"])
	await _click(card["controls"]["features"]["choices"]["save"])
	await _click(card["controls"]["features"]["choices"]["touch"])
	card["controls"]["features"]["text"].text = "Ecran landscape"
	card["controls"]["features"]["text"].text_changed.emit()
	host._check(not card["submit"].disabled and service.requests == 1 and card["controls"]["features"]["choices"]["save"].button_pressed and card["controls"]["features"]["choices"]["touch"].button_pressed, "Multiple selections and custom text enable Submit without auto-submission")
	await host.get_tree().create_timer(0.4).timeout
	var restored: Array = panel.conversations.load_active()
	host._check(str(restored).contains("Ecran landscape") and str(restored).contains("plan_questions"), "The pending question and edited draft are persisted before the agent continues")
	host._check(card["node"].size.x <= minf(440 * EditorInterface.get_editor_scale(), panel.chat.scroll.size.x - 36 * EditorInterface.get_editor_scale()) + 2, "Question cards respect the narrow plan-card width")
	panel.chat.scroll.ensure_control_visible(card["node"])
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	host._activity_capture("interactive-plan-choices")
	await _click(card["submit"])
	if not await _wait(func() -> bool: return not panel.busy, "Explicit Submit lets the agent finish the proposed plan"): return
	host._check(service.requests == 3 and panel.harness.state == "completed" and panel.planner.intent == "propose" and panel.planner.phase == "completed", "The provider receives the answer and publishes a plan with pending implementation steps")
	var result = {}
	for message in panel.history:
		if message.get("tool_name") == "plan_ask": result = panel.Common.parse_json(message["content"])
	host._check(result.get("ok", false) and result["result"]["answers"]["view"]["labels"] == ["Lateral"] and result["result"]["answers"]["features"]["selected"].size() == 2, "Actual submitted choices reach the model as the paired tool result")
	host._check(str(service.contexts[-1]["messages"]).contains("Ecran landscape") and service.contexts[0]["tools"].all(func(tool: Dictionary) -> bool: return tool.get("risk") == "read"), "The final planning context includes custom answers while exposing only read tools")
	host._check(panel.mode_picker.get_selected_id() == 3 and not await panel._authorize({"name": "godot_write_file", "risk": "write"}, {}), "Answering questions cannot grant write permission, even with YOLO enabled")
	panel._render_history()
	host._check(panel.chat.question_cards.size() == 1 and not panel.chat.question_cards[id].has("submit") and not panel.chat.question_cards[id].has("resume"), "Restored completed plans retain a read-only answer summary without offering duplicate submission")
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	host._check(not panel.chat.stop_button.visible and not panel.chat._work_running() and panel.chat.status.text == "Plan pregătit", "The completed Plan renders a settled status and removes the working controls")
	host._activity_capture("interactive-plan-completed")
	service = PlanningProvider.new()
	record = await _start(service)
	if record.is_empty(): return
	id = str(record["id"])
	card = panel.chat.question_cards[id]
	card["controls"]["view"]["text"].text = "Izometric"
	card["controls"]["view"]["text"].text_changed.emit()
	var turn = panel.current_turn
	panel._stop()
	if not await _wait(func() -> bool: return not panel.busy, "Stop cancels the waiting tool without hanging the harness"): return
	host._check(record["status"] == "paused" and service.requests == 1 and panel.chat.question_cards[id]["editing"], "The unanswered card can be resumed explicitly after Stop")
	# Recreate the conversation from its disk representation and repair interrupted tool calls.
	panel.history = panel.conversations.load_active()
	panel._close_unanswered_calls()
	panel._render_history()
	card = panel.chat.question_cards[id]
	host._check(card["controls"]["view"]["text"].text == "Izometric", "Restoring a stopped conversation retains the custom draft")
	await _click(card["controls"]["features"]["choices"]["touch"])
	host._check(not card["submit"].disabled and card["controls"]["features"]["choices"]["touch"].button_pressed, "The restored question accepts a new selection before submission")
	await _click(card["submit"])
	if not await _wait(func() -> bool: return not panel.busy and service.requests == 3, "Submitting a restored card resumes the same task"): return
	host._check(panel.current_turn == turn and panel.history.filter(func(message: Dictionary) -> bool: return message.get("role") == "user").size() == 1, "Restored answers resume the original turn without inventing another user request")
	var replay = panel.Providers.application_context(panel.history)
	host._check(str(replay).contains("Izometric") and panel.history.any(func(message: Dictionary) -> bool: return message.get("tool_name") == "plan_ask" and '"ok":true' in str(message.get("content", ""))), "Interrupted question results are repaired from the persisted user submission")
	var requests = service.requests
	panel._chat_action("plan_answer", {"id": id, "answers": {"view": {"text": "Overwrite"}, "features": {"text": "Overwrite"}}})
	await host.get_tree().process_frame
	host._check(service.requests == requests and not str(panel._question_record(id)["answers"]).contains("Overwrite"), "Duplicate or stale submissions cannot overwrite confirmed answers")
	panel._new_conversation()
	panel._chat_action("plan_continue", {"id": id})
	host._check(service.requests == requests and panel.history.is_empty(), "Question actions from another conversation are ignored")
	service = PlanningProvider.new()
	record = await _start(service)
	if record.is_empty(): return
	id = str(record["id"])
	panel._answer_question({"id": id, "answers": {"view": {"text": "Prima persoană"}, "features": {"text": "Explorare"}}})
	# Snapshot the narrow crash window after the durable answer, before the awaiting tool returns.
	var crash_snapshot: Array = panel.conversations.load_active()
	panel._stop()
	if not await _wait(func() -> bool: return not panel.busy, "The live tool settles after a confirmed-answer interruption"): return
	panel.history = crash_snapshot
	panel._close_unanswered_calls()
	panel._render_history()
	host._check(panel.chat.question_cards[id].has("resume") and panel.history.any(func(message: Dictionary) -> bool: return message.get("tool_name") == "plan_ask" and '"ok":true' in str(message.get("content", ""))), "A crash between answer persistence and tool completion recovers the real answer and offers Continue")
	var configured = panel.config["providers"].duplicate(true)
	panel.config["providers"] = [{"id": "different-profile", "name": "Other provider", "kind": "chat", "models": [{"id": "other-model"}]}]
	panel._refresh_profiles()
	await _click(panel.chat.question_cards[id]["resume"])
	host._check(not panel.busy and service.requests == 1 and panel.chat.question_cards[id].has("resume"), "Recovery refuses to silently switch to another provider when the saved profile disappears")
	panel.config["providers"] = configured
	panel._refresh_profiles()
	await _click(panel.chat.question_cards[id]["resume"])
	if not await _wait(func() -> bool: return not panel.busy and service.requests == 3, "Recovered confirmed answers continue without re-asking the questions"): return
	host._check(str(service.contexts[-1]["messages"]).contains("Prima persoană") and not panel.chat.question_cards[id].has("resume"), "Custom-only answers survive recovery and completed plans remove the recovery action")
	service = PlanningProvider.new()
	record = await _start(service)
	if record.is_empty(): return
	id = str(record["id"])
	panel._stop()
	if not await _wait(func() -> bool: return not panel.busy, "A waiting questionnaire can be stopped before a new task"): return
	service.requests = 3
	await panel._start_chat("Mulțumesc, trecem la altă cerere.")
	panel._chat_action("plan_answer", {"id": id, "answers": {"view": {"text": "Late answer"}, "features": {"text": "Late answer"}}})
	host._check(not panel.chat.question_cards[id]["editing"] and panel.chat.question_cards[id]["submit"].disabled and not record.has("answers") and service.requests == 4, "A newer request disables unanswered old cards and rejects delayed answers in the same conversation")
	panel.config["providers"] = original_providers
	panel.providers = original_service
	panel.full_control.button_pressed = original_permission
	panel._refresh_profiles()
	panel._choose(original_selection)
	panel.chat.history_requested = original_history_requested
	panel.chat._resize()
	await host.get_tree().process_frame
