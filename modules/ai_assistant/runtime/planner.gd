@tool
extends RefCounted
## Explicit task state. Planning never changes the user's selected Auto/Default/Plan mode.
static var Common: GDScript
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
	return Common.tool("task_update", "Publish or revise a visible task plan. Use for multi-step, uncertain or cross-file work before modifying the project. Update actual step states as you work; at most one in_progress. planning is read-only. Switch to executing before writes, verifying for checks, completed only after finishing. For a plan-only request set intent=propose; mark blocked with explanation if you cannot continue. Default mode allows simple tasks without a plan; Auto requires a short executing plan before any mutation or external operation.", {"tasks": {"type": "array", "minItems": 1, "maxItems": 16, "items": {"anyOf": [{"type": "string", "minLength": 1, "maxLength": 600}, Common.schema({"step": {"type": "string", "minLength": 1, "maxLength": 600}, "status": {"type": "string", "enum": ["pending", "in_progress", "completed"]}}, ["step", "status"])]}}, "phase": {"type": "string", "enum": ["planning", "executing", "verifying", "completed", "blocked"]}, "intent": {"type": "string", "enum": ["execute", "propose"]}, "explanation": Common.string_field(), "verification_kind": {"type": "string", "enum": ["inspection", "runtime", "interaction"], "description": "Use interaction for controls, clicks, collection, victory and restart; runtime for executable behavior; inspection for static edits."}, "verification": {"type": "string", "maxLength": 1600, "description": "For completed execution plans, summarize actual post-change checks and observed results. Unverified criteria must remain blocked or pending."}}, ["tasks"])

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
