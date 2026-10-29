@tool
extends RefCounted
## Independent upstream UI/process. No prompts or credentials enter our agent harness.
static var Common: GDScript
static var Tools: GDScript
static var EditorMCP: GDScript
signal changed()
var bridge: Node
var state: Dictionary = {}
var last_refresh = 0
var project_directory = ""
var owner: Node
var editor_mcp: Node
var editor_tools: RefCounted
var recovery_directory = ""
var playtest_deadline = 0

func _init(native_bridge: Node = null, project: String = "") -> void:
	bridge = native_bridge
	project_directory = project

func configure(panel: Node, recovery: String) -> void:
	owner = panel
	recovery_directory = recovery

func editor_busy() -> bool:
	return is_instance_valid(editor_mcp) and editor_mcp.busy

func editor_configuration() -> Dictionary:
	if not is_instance_valid(editor_mcp) or not editor_mcp.listener.is_listening(): return {}
	return {"url": "http://127.0.0.1:%d/mcp" % editor_mcp.port, "headers": {"Authorization": "Bearer ${GODOT_AI_EDITOR_MCP_TOKEN}"}}

func _start_editor() -> Dictionary:
	if not is_instance_valid(owner) or not Engine.is_editor_hint(): return Common.failure("Editorul nativ nu este disponibil.", "editor_unavailable")
	if is_instance_valid(editor_mcp): return Common.failure("Conexiunea editorului este deja activă.", "already_running")
	editor_tools = Tools.new(bridge, owner)
	editor_tools.backup_directory = recovery_directory
	editor_tools.file_changes = Common.read_json(recovery_directory.path_join("journal.json"), [])
	editor_tools.turn_id = "ziva-" + Common.uid()
	editor_mcp = EditorMCP.new()
	owner.add_child(editor_mcp)
	editor_mcp.tool_finished.connect(_tool_finished)
	return editor_mcp.start(editor_tools.definitions(), _execute_editor)

func _execute_editor(name: String, args: Dictionary, cancel: Dictionary) -> Dictionary:
	if cancel.get("cancelled", false): return Common.failure("Oprit.", "cancelled")
	var validation = editor_tools.validate(name, args)
	if not validation.get("ok", false): return validation
	if validation["result"] != "read" and owner.get("busy"): return Common.failure("Agentul Godot AI lucrează în proiect. Așteaptă încheierea înainte de modificări Ziva.", "project_busy")
	var result: Dictionary
	if name.begins_with("godot_changes_"): result = await editor_tools.execute_changes(name, args, cancel)
	else: result = editor_tools.execute(name, args, 1, true)
	if name == "godot_run" and result.get("ok", false) and result.get("result", {}).get("requested", false): playtest_deadline = Time.get_ticks_msec() + 120000
	# Native tools already exclude secret controls/settings. Also redact configured
	# secrets from text results before any external MCP client can receive them.
	return Common.parse_json(owner._redact(JSON.stringify(result))) if is_instance_valid(owner) and owner.has_method("_redact") else result

func _tool_finished(name: String, ok: bool, code: String) -> void:
	if is_instance_valid(owner) and owner.has_method("_record_event"):
		owner._record_event("ziva_tool", {"tool": name}, {"ok": ok, "code": code})
	changed.emit()

func _stop_editor() -> void:
	if editor_tools != null:
		editor_tools.finish_playtest(editor_tools.turn_id, true)
	if is_instance_valid(editor_mcp):
		editor_mcp.stop()
		editor_mcp.queue_free()
	editor_mcp = null
	editor_tools = null
	playtest_deadline = 0

func close() -> void:
	if is_instance_valid(editor_mcp): _request("stop")
	_stop_editor()

func refresh() -> Dictionary:
	last_refresh = Time.get_ticks_msec()
	state = _request("status", {"project_directory": project_directory} if not project_directory.is_empty() else {})
	if is_instance_valid(editor_mcp):
		if not state.get("busy", false): _stop_editor()
		else:
			state["editor_mcp"] = editor_mcp.snapshot()
			state["editor_connected"] = editor_mcp.initialized_clients > 0
			state["ready"] = state.get("running", false) and state["editor_connected"]
	if playtest_deadline > 0 and Time.get_ticks_msec() >= playtest_deadline and editor_tools != null:
		editor_tools.finish_playtest(editor_tools.turn_id)
		playtest_deadline = 0
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
		var connection = _start_editor()
		if not connection.get("ok", false): _stop_editor(); return connection
		args["editor_mcp_port"] = editor_mcp.port
		args["editor_mcp_token"] = connection["result"]["token"]
	var result = _request(action, args)
	if action == "stop" or (action == "start" and not result.get("ok", false)): _stop_editor()
	refresh()
	return result

func caption() -> String:
	if not state.get("ok", false) or not state.get("enabled", false): return "Disponibil în pachetul separat Godot AI Ziva"
	var status = str(state.get("status", ""))
	if status == "running":
		if not state.get("editor_connected", false): return "Server Ziva pornit · editor neconectat"
		var measured: Dictionary = state.get("editor_mcp", {})
		return "Ziva · editor conectat · %d apeluri MCP" % int(measured.get("tool_calls", 0))
	if status in ["queued", "installing", "starting", "stopping", "error", "interrupted"]: return str(state.get("message", "Ziva în așteptare"))
	return "Ziva instalat · " + str(state.get("version", "")) if state.get("installed", false) else "Ziva nu este instalat"
