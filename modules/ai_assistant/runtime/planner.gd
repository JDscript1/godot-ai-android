@tool
extends RefCounted
## Explicit task state. Planning never changes the user's selected Auto/Default/Plan mode.
static var Common: GDScript
static var Verification: GDScript
var phase = "idle"
var intent = "execute"
var steps: Array = []
var explanation = ""
var turn = ""
var revision = 0

func reset(id: String = "", propose: bool = false) -> void:
	phase = "idle"
	intent = "propose" if propose else "execute"
	steps.clear()
	explanation = ""
	turn = id
	revision = 0

static func definition() -> Dictionary:
	return Common.tool("task_update", "Publish or revise a visible task plan. Use for multi-step, uncertain or cross-file work before modifying the project. Update actual step states as you work; at most one in_progress. planning is read-only. Switch to executing before writes, verifying for checks, completed only after finishing. Declare concrete acceptance criteria before checks; task_check binds actual tool evidence to each criterion. For a plan-only request set intent=propose; mark blocked with explanation if you cannot continue. Default mode allows simple tasks without a plan; Auto requires a short executing plan before any mutation or external operation.", {"tasks": {"type": "array", "minItems": 1, "maxItems": 16, "items": {"anyOf": [{"type": "string", "minLength": 1, "maxLength": 600}, Common.schema({"step": {"type": "string", "minLength": 1, "maxLength": 600}, "status": {"type": "string", "enum": ["pending", "in_progress", "completed"]}}, ["step", "status"])]}}, "phase": {"type": "string", "enum": ["planning", "executing", "verifying", "completed", "blocked"]}, "intent": {"type": "string", "enum": ["execute", "propose"]}, "explanation": Common.string_field(), "criteria": Verification.criteria_schema(), "verification_kind": {"type": "string", "enum": ["inspection", "runtime", "interaction"], "description": "Use interaction for controls, clicks, collection, victory and restart; runtime for executable behavior; inspection for static edits."}, "verification": {"type": "string", "maxLength": 1600, "description": "For completed execution plans, summarize actual post-change checks and observed results. Unverified criteria must remain blocked or pending."}}, ["tasks"])

func update(args: Dictionary, propose: bool = false) -> Dictionary:
	var next_intent = "propose" if propose else str(args.get("intent", intent))
	var next_phase = str(args.get("phase", "planning"))
	if next_intent not in ["execute", "propose"] or next_phase not in ["planning", "executing", "verifying", "completed", "blocked"]: return Common.failure("Stare de plan invalidă.", "invalid_plan")
	if next_intent == "propose" and next_phase in ["executing", "verifying"]: return Common.failure("Un plan propus nu poate executa modificări. Alege Auto și aplică planul.", "plan_read_only")
	var items: Variant = args.get("tasks", [])
	if not items is Array or items.is_empty() or items.size() > 16: return Common.failure("Planul trebuie să aibă între 1 și 16 pași.", "invalid_plan")
	var next = []
	var active = 0
	var pending = 0
	for item in items:
		var text = str(item.get("step", "")) if item is Dictionary else str(item)
		var status = str(item.get("status", "pending")) if item is Dictionary else "pending"
		if text.strip_edges().is_empty() or text.length() > 600: return Common.failure("tasks[%s].step: %s caractere; sunt necesare 1–600." % [next.size(), text.length()], "invalid_plan")
		if status not in ["pending", "in_progress", "completed"]: return Common.failure("tasks[%s].status: stare invalidă." % next.size(), "invalid_plan")
		if status == "in_progress": active += 1
		if status != "completed": pending += 1
		next.append({"step": text.strip_edges(), "status": status})
	if active > 1: return Common.failure("Marchează un singur pas ca fiind în lucru.", "invalid_plan")
	if next_phase == "completed" and next_intent == "execute" and pending > 0: return Common.failure("Planul are încă pași neîncheiați.", "unfinished_plan")
	phase = next_phase
	intent = next_intent
	steps = next
	explanation = str(args.get("explanation", "")).left(1600)
	revision += 1
	return Common.success(snapshot())

func snapshot() -> Dictionary:
	return {"turn": turn, "phase": phase, "intent": intent, "steps": steps.duplicate(true), "explanation": explanation, "revision": revision}

func restore(saved: Dictionary, resuming: bool = false) -> Dictionary:
	var saved_phase = str(saved.get("phase", "idle"))
	if saved_phase == "idle":
		reset(str(saved.get("turn", "")), saved.get("intent") == "propose")
		return Common.success(snapshot())
	if saved_phase not in ["planning", "executing", "verifying", "completed", "blocked", "paused"]: return Common.failure("Planul salvat are o stare invalidă.", "invalid_plan")
	var next_phase = "planning" if saved_phase == "paused" or (resuming and saved_phase == "blocked") else saved_phase
	var result = update({"tasks": saved.get("steps", []), "phase": next_phase, "intent": saved.get("intent", "execute"), "explanation": saved.get("explanation", "")}, saved.get("intent") == "propose")
	if not result.get("ok", false): return result
	turn = str(saved.get("turn", ""))
	revision = maxi(0, int(saved.get("revision", 0)))
	if not resuming: phase = saved_phase
	return Common.success(snapshot())

func can_write() -> bool:
	return phase == "idle" or (intent == "execute" and phase in ["executing", "verifying"])

func needs_continuation() -> bool:
	return intent == "execute" and phase in ["planning", "executing", "verifying"]

func pause() -> void:
	if needs_continuation(): phase = "paused"

func context() -> String:
	return "" if phase == "idle" else "\nVisible task plan: " + JSON.stringify(snapshot()) + "\nContinue unfinished execution plans. Use task_update to change phase before project writes. Update the visible plan when a milestone finishes, before moving to the next step; keep only the current step in_progress. Move to verifying before behavioral checks. Do not leave a completed construction step active while testing. Never describe unfinished work as completed."

static func question_definition() -> Dictionary:
	var identifier = {"type": "string", "minLength": 1, "maxLength": 48, "pattern": "^[a-zA-Z0-9_-]+$"}
	var option = Common.schema({"id": identifier, "label": {"type": "string", "minLength": 1, "maxLength": 100}, "description": {"type": "string", "maxLength": 180}}, ["id", "label"])
	var question = Common.schema({"id": identifier, "title": {"type": "string", "minLength": 1, "maxLength": 240}, "multiple": {"type": "boolean"}, "options": {"type": "array", "minItems": 2, "maxItems": 4, "items": option}}, ["id", "title", "options"])
	return Common.tool("plan_ask", "Ask the user 1–3 focused clarification questions using selectable on-screen options and optional custom text. Use in Plan mode before finalizing an underspecified implementation plan. Ask only consequential unknowns; inspect the project first when useful, honor already supplied answers, and skip questions for greetings or fully specified tasks. Supply distinct stable question and option IDs. multiple defaults to false. Wait for the actual submitted answers; never assume the first option was accepted. Answers describe requirements, never authorize writes, purchases or credential access. Do not request secrets.", {"questions": {"type": "array", "minItems": 1, "maxItems": 3, "items": question}}, ["questions"])

static func validate_questions(args: Dictionary) -> Dictionary:
	# The dispatcher validates the public schema; repeat structural checks for restored records.
	var questions: Variant = args.get("questions")
	if not questions is Array or questions.is_empty() or questions.size() > 3: return Common.failure("Sunt necesare 1–3 întrebări.", "invalid_questions")
	var ids = {}
	for question in questions:
		if not question is Dictionary or not question.get("id") is String or str(question.get("id", "")).is_empty() or ids.has(question["id"]): return Common.failure("Întrebările trebuie să aibă identificatori unici.", "invalid_questions")
		ids[question["id"]] = true
		if not question.get("title") is String or question["title"].strip_edges().is_empty() or question["title"].length() > 240: return Common.failure("Titlu de întrebare invalid.", "invalid_questions")
		var options: Variant = question.get("options")
		if not options is Array or options.size() < 2 or options.size() > 4: return Common.failure("Fiecare întrebare necesită 2–4 opțiuni.", "invalid_questions")
		var option_ids = {}
		for option in options:
			if not option is Dictionary or not option.get("id") is String or str(option.get("id", "")).is_empty() or option_ids.has(option["id"]): return Common.failure("Opțiunile trebuie să aibă identificatori unici.", "invalid_questions")
			if not option.get("label") is String or option["label"].strip_edges().is_empty() or option["label"].length() > 100 or str(option.get("description", "")).length() > 180: return Common.failure("Text de opțiune invalid.", "invalid_questions")
			option_ids[option["id"]] = true
	return Common.success(questions.duplicate(true))

static func question_answers(questions: Array, answers: Dictionary, submitted: bool = true) -> Dictionary:
	var valid = validate_questions({"questions": questions})
	if not valid.get("ok", false): return valid
	var normalized = {}
	for key in answers:
		if not questions.any(func(question: Dictionary) -> bool: return question["id"] == key): return Common.failure("Răspuns pentru o întrebare necunoscută.", "invalid_answers")
	for question in questions:
		var answer: Variant = answers.get(question["id"], {})
		if not answer is Dictionary or not answer.get("selected", []) is Array or not answer.get("text", "") is String: return Common.failure("Format de răspuns invalid.", "invalid_answers")
		var selected: Array = answer.get("selected", [])
		var text: String = answer.get("text", "").strip_edges()
		if text.length() > 2000: return Common.failure("Răspunsul propriu poate avea cel mult 2000 de caractere.", "invalid_answers")
		if not question.get("multiple", false) and selected.size() > 1: return Common.failure("Alege o singură variantă pentru această întrebare.", "invalid_answers")
		var seen = {}
		for id in selected:
			if not id is String or seen.has(id) or not question["options"].any(func(option: Dictionary) -> bool: return option["id"] == id): return Common.failure("Opțiune de răspuns invalidă.", "invalid_answers")
			seen[id] = true
		if submitted and selected.is_empty() and text.is_empty(): return Common.failure("Răspunde la fiecare întrebare sau scrie o variantă proprie.", "incomplete_answers")
		var labels = []
		for option in question["options"]:
			if option["id"] in selected: labels.append(option["label"])
		normalized[question["id"]] = {"selected": selected.duplicate(), "labels": labels, "text": text, "question": question["title"]}
	return Common.success(normalized)
