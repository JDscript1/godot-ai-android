@tool
extends RefCounted
## Independent upstream UI/process. No prompts or credentials enter our agent harness.
static var Common: GDScript
signal changed()
var bridge: Node
var state: Dictionary = {}
var last_refresh = 0
var project_directory = ""

func _init(native_bridge: Node = null, project: String = "") -> void:
	bridge = native_bridge
	project_directory = project

func refresh() -> Dictionary:
	last_refresh = Time.get_ticks_msec()
	state = _request("status", {"project_directory": project_directory} if not project_directory.is_empty() else {})
	changed.emit()
	return state

func _request(action: String, args: Dictionary = {}) -> Dictionary:
	if bridge == null or not bridge.has_method("linux_runtime_request"):
		return Common.failure("Disponibil în pachetul Android Godot AI Ziva.", "ziva_unavailable")
	var result: Variant = bridge.call("linux_runtime_request", "ziva_" + action, args)
	return result if result is Dictionary else Common.failure("Răspuns Ziva invalid.", "ziva_protocol_error")

func request(action: String, project: String = "") -> Dictionary:
	if not action in ["install", "start", "stop", "open"]: return Common.failure("Operație Ziva necunoscută.")
	if action in ["start", "open"] and project.is_empty(): return Common.failure("Deschide un proiect pentru Ziva.", "project_required")
	var args = {"project_directory": project} if action in ["start", "open"] else {}
	if action == "start":
		var status = refresh()
		if not status.get("enabled", false): return Common.failure("Disponibil în pachetul separat Godot AI Ziva.", "ziva_unavailable")
		if status.get("busy", false): return Common.failure("Ziva este deja în lucru.", "already_running")
	var result = _request(action, args)
	refresh()
	return result

func close() -> void:
	pass # The Android service owns the companion editor lifetime; closing the panel must not stop it.

func caption() -> String:
	if not state.get("ok", false) or not state.get("enabled", false): return "Disponibil în pachetul separat Godot AI Ziva"
	var status = str(state.get("status", ""))
	if status == "running":
		var port = int(state.get("ui_port", 0))
		return "Ziva · editor separat activ · interfață pe portul %d" % port if port > 0 else "Ziva · editor separat activ"
	if status in ["queued", "installing", "starting", "stopping", "error", "interrupted"]: return str(state.get("message", "Ziva în așteptare"))
	return "Ziva instalat · " + str(state.get("version", "")) if state.get("installed", false) else "Ziva nu este instalat"
