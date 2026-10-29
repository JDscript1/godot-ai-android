@tool
extends RefCounted
## Independent upstream UI/process. No prompts or credentials enter our agent harness.
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
	if not is_instance_valid(bridge) or not bridge.has_method("linux_runtime_request"):
		return _failure("Disponibil în pachetul Android Godot AI Ziva.", "ziva_unavailable")
	var result: Variant = bridge.call("linux_runtime_request", "ziva_" + action, args)
	return result if result is Dictionary else _failure("Răspuns Ziva invalid.", "ziva_protocol_error")

func request(action: String, _project: String = "") -> Dictionary:
	if not action in ["install", "restart", "check_updates", "update", "attach"]: return _failure("Operație Ziva necunoscută.")
	var args = {"project_directory": project_directory}
	var result = _request(action, args)
	refresh()
	return result

func embed(rect: Rect2, visible_ui: bool, reload_ui: bool = false) -> Dictionary:
	return _request("embed", {"visible": visible_ui, "bounds": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "project_directory": project_directory, "reload": reload_ui})

func close() -> void:
	pass # Activity ownership controls lifetime, not tab visibility.

func _failure(message: String, code: String = "ziva_error") -> Dictionary:
	return {"ok": false, "error": message, "code": code}

func caption() -> String:
	if not state.get("ok", false) or not state.get("enabled", false): return "Disponibil în pachetul separat Godot AI Ziva"
	var status = str(state.get("status", ""))
	if status == "running":
		var port = int(state.get("ui_port", 0))
		return "Ziva · editor separat activ · interfață pe portul %d" % port if port > 0 else "Ziva · editor separat activ"
	if status in ["queued", "installing", "starting", "stopping", "error", "interrupted"]: return str(state.get("message", "Ziva în așteptare"))
	return "Ziva instalat · " + str(state.get("version", "")) if state.get("installed", false) else "Ziva nu este instalat"
