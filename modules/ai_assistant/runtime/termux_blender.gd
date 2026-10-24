@tool
extends RefCounted
## Optional Android Blender backend. The AI harness itself stays inside Godot.
signal changed
signal diagnostic(entry: Dictionary)
static var Common: GDScript
static var Transport: GDScript
static var FileRegistry: GDScript
var owner: Node
var bridge: Object
var transport: RefCounted
var native_override = Callable()
var url = ""
var token = ""
var state: Dictionary = {}
var runtime: Dictionary = {}
var verified: Dictionary = {}
var pending: Dictionary = {}
var directory = ""
var project_directory = ""
var working = false
var connected = false
var refreshing = false
var setup_cancel: Dictionary = {}
var log_text = ""
var log_entries: Array = []
var job_log = ""
var last_diagnostic = ""
var last_check = 0
var manual_setup_pending = false
var discovery_complete = false

const ACTIVATION = "mkdir -p ~/.termux && touch ~/.termux/termux.properties && sed -i '/^[[:space:]]*allow-external-apps[[:space:]]*=/d' ~/.termux/termux.properties && printf '\\nallow-external-apps=true\\n' >> ~/.termux/termux.properties && termux-reload-settings"
const TERMINAL = ["completed", "failed", "cancelled", "interrupted"]
const LOG_LIMIT = 32000

func _init(node: Node = null, native_bridge: Object = null) -> void:
	owner = node
	bridge = native_bridge
	transport = Transport.new(node)

func configure(global_directory: String, project_data: String) -> void:
	directory = global_directory.path_join("blender")
	project_directory = project_data.path_join("blender")
	DirAccess.make_dir_recursive_absolute(directory)
	DirAccess.make_dir_recursive_absolute(project_directory)
	verified = Common.read_json(directory.path_join("verified.json"), {})
	pending = Common.read_json(project_directory.path_join("pending.json"), {})
	var saved = Common.read_json(directory.path_join("diagnostics.json"), {})
	log_entries = saved.get("entries", []).slice(-100)
	job_log = str(saved.get("job_log", "")).right(LOG_LIMIT)
	_render_log()

func _safe(text: String) -> String:
	return Common.redact(text, [token] if not token.is_empty() else [])

func _render_log() -> void:
	var lines = PackedStringArray()
	for entry in log_entries:
		lines.append("[%s] %s · %s" % [entry.get("time", ""), entry.get("code", "blender"), _safe(str(entry.get("message", "")))])
	if not job_log.is_empty(): lines.append("--- Blender ---\n" + _safe(job_log))
	log_text = "\n".join(lines).right(LOG_LIMIT * 2)

func _save_log() -> void:
	job_log = _safe(job_log).right(LOG_LIMIT)
	_render_log()
	if not directory.is_empty(): Common.atomic_json(directory.path_join("diagnostics.json"), {"entries": log_entries, "job_log": _safe(job_log)})

func note(message: String, code: String = "blender", failed: bool = false) -> void:
	message = _safe(message).left(6000)
	if not log_entries.is_empty() and log_entries[-1].get("message") == message and log_entries[-1].get("code") == code: return
	var entry = {"time": Time.get_datetime_string_from_system(true) + "Z", "code": code, "message": message, "failed": failed}
	log_entries.append(entry)
	log_entries = log_entries.slice(-100)
	_save_log()
	diagnostic.emit(entry)
	changed.emit()

func diagnostics() -> Dictionary:
	if available(): return {"code": "ready", "message": "Disponibil", "next_action": ""}
	if working or refreshing: return {"code": "busy", "message": str(state.get("stage", "Verificare Blender…")), "next_action": "Așteaptă finalizarea operației."}
	if state.is_empty(): return {"code": "unchecked", "message": "Conexiunea Blender nu a fost verificată.", "next_action": "Deschide Integrări → Blender."}
	if not state.get("ok", false): return {"code": "missing_bridge", "message": _safe(str(state.get("error", "Conectorul Android nu este disponibil."))), "next_action": "Verifică versiunea aplicației."}
	if not state.get("supported", true): return {"code": "unsupported_arch", "message": "Configurarea automată necesită Android ARM64.", "next_action": ""}
	if not state.get("installed", false): return {"code": "missing_termux", "message": "Termux nu este instalat sau nu este vizibil editorului.", "next_action": "Instalează și deschide Termux o dată."}
	if not state.get("compatible", true): return {"code": "incompatible_termux", "message": "Este necesar Termux 0.118 sau mai nou.", "next_action": "Actualizează Termux."}
	if manual_mode() and not connected: return {"code": "manual_start_required", "message": "Această versiune Termux necesită pornirea conectorului din terminal.", "next_action": "Apasă Pornește în Termux, lipește comanda, apasă Enter și revino în Godot."}
	if not manual_mode() and not state.get("permission", false): return {"code": "permission_required", "message": "Permisiunea Android pentru comenzi Termux nu este acordată.", "next_action": "Apasă Acordă permisiunea în Integrări → Blender."}
	if not str(state.get("error", "")).is_empty(): return {"code": "termux_start_failed", "message": _safe(str(state["error"])).left(6000), "next_action": "Verifică jurnalul și activarea comenzilor externe în Termux."}
	if not str(state.get("error_code", "")).is_empty(): return {"code": str(state["error_code"]), "message": _safe(str(state.get("stage", "Conectarea Blender a eșuat."))), "next_action": "Deschide Integrări → Blender și verifică jurnalul."}
	if not pending.is_empty(): return {"code": "pending_job", "message": "Există o sarcină Blender de recuperat.", "next_action": "Apasă Recuperează în Integrări → Blender."}
	if connected and discovery_complete and runtime.is_empty(): return {"code": "runtime_missing", "message": "Conectorul răspunde, dar Blender nu a fost detectat.", "next_action": "Apasă Instalează Blender în Integrări → Blender."}
	if verified.is_empty(): return {"code": "setup_required", "message": "Configurarea inițială Blender nu a fost finalizată.", "next_action": "Apasă Conectează în Integrări → Blender."}
	if not connected: return {"code": "disconnected", "message": "Conectorul Blender nu răspunde.", "next_action": "Deschide Termux, apoi apasă Conectează în Integrări → Blender."}
	return {"code": "verification_required", "message": "Instalarea Blender necesită verificare.", "next_action": "Apasă Verifică în Integrări → Blender."}

func _report_state() -> void:
	var detail = diagnostics()
	var signature = str(detail["code"]) + ":" + str(detail["message"])
	state["stage"] = str(detail["message"]).left(240)
	if signature != last_diagnostic:
		last_diagnostic = signature
		note(str(detail["message"]) + (" " + str(detail["next_action"]) if not str(detail["next_action"]).is_empty() else ""), str(detail["code"]), detail["code"] in ["missing_bridge", "termux_start_failed", "connection_failed"])

func _failure(response: Dictionary) -> void:
	state["error_code"] = str(response.get("code", "connection_failed"))
	state["stage"] = _safe(str(response.get("error", "Blender indisponibil."))).left(240)
	note(str(response.get("error", "Blender indisponibil.")), str(state["error_code"]), true)

func native(action: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary
	if native_override.is_valid(): result = native_override.call(action, args)
	elif bridge == null or not bridge.has_method("termux_blender_request"): result = Common.failure("Conectorul necesită un APK Android actualizat.", "missing_bridge")
	else: result = bridge.termux_blender_request(action, args)
	var labels = {"permission": "Permisiune Android solicitată. Confirmă dialogul Android sau verifică Setări Android.", "settings": "Setările Android au fost solicitate.", "open_termux": "Deschiderea Termux a fost solicitată.", "install_termux": "Pagina oficială de instalare Termux a fost solicitată.", "copy_bootstrap": "Comanda privată de conectare a fost copiată. Lipește-o în Termux, apasă Enter și revino în Godot."}
	if labels.has(action):
		if result.get("ok", false): note(labels[action], action)
		else: _failure(result)
	return result

func manual_mode() -> bool:
	return state.get("launch_mode", "direct") == "manual"

func prepare_manual() -> Dictionary:
	if working or refreshing: return Common.failure("Blender este ocupat.", "busy")
	var result = native("copy_bootstrap", {"install_python": true})
	if not result.get("ok", false): return result
	manual_setup_pending = true
	state.erase("error_code")
	state.erase("error")
	return native("open_termux")

static func fingerprint(value: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [value.get("kind", ""), value.get("container", ""), value.get("executable", ""), value.get("version", ""), value.get("binary_stamp", "")]

func available() -> bool:
	return connected and not runtime.is_empty() and verified.get("protocol") == 1 and verified.get("fingerprint", "") == fingerprint(runtime) and "glb" in runtime.get("capabilities", {}).get("formats", [])

func _credentials() -> bool:
	var connection = native("connection")
	var location = Common.parse_url(str(connection.get("url", "")), true)
	if not connection.get("ok", false) or location.get("host") != "127.0.0.1" or location.get("scheme") != "http" or int(location.get("port", 0)) < 1024: return false
	url = str(connection["url"])
	token = str(connection.get("token", ""))
	return token.length() == 64 and token.is_valid_hex_number(false)

func _http(route: String, method: int = HTTPClient.METHOD_GET, body: Variant = null, options: Dictionary = {}) -> Dictionary:
	var settings = {"allow_http": true, "timeout": 10, "max_bytes": 128 * 1024}
	settings.merge(options, true)
	var reply = await transport.request(url + route, method, PackedStringArray(["Authorization: Bearer " + token]), body, settings)
	if reply.get("json") is Dictionary:
		var data: Dictionary = reply["json"]
		if data.has("ok"):
			data["http_status"] = reply.get("status", 0)
			return data
	return reply

func _health(timeout: float = 1.0) -> bool:
	var reply = await _http("/v1/health", HTTPClient.METHOD_GET, null, {"timeout": timeout})
	connected = reply.get("ok", false) and int(reply.get("protocol", 0)) == 1
	if connected:
		runtime = reply.get("runtime", {})
		if not runtime.is_empty(): discovery_complete = true
		if state.get("error_code") in ["permission_required", "manual_start_required", "connection_failed", "termux_start_failed"]: state.erase("error_code")
		state.erase("error")
		native("connected")
	return connected

func refresh() -> void:
	if working or refreshing: return
	refreshing = true
	state.merge(native("status"), true)
	connected = false
	if state.get("installed", false) and (manual_mode() or state.get("permission", false)) and _credentials(): await _health()
	last_check = Time.get_ticks_msec()
	refreshing = false
	if manual_mode() and connected and manual_setup_pending:
		manual_setup_pending = false
		if pending.is_empty(): await setup("connect")
	_report_state()
	changed.emit()

func _connect(prepare: bool = false) -> Dictionary:
	note("Verificare Termux și permisiune Android.", "preflight")
	state = native("status")
	if not state.get("ok", false): return state
	note("Termux: %s · Pornire: %s." % [str(state.get("version", "detectat")) if state.get("installed", false) else "absent", "din terminal" if manual_mode() else "directă, permisiune " + ("acordată" if state.get("permission", false) else "neacordată")], "device")
	if not state.get("installed", false): return Common.failure("Instalează și deschide Termux o dată.", "missing_termux")
	if not manual_mode() and not state.get("permission", false): return Common.failure("Acordă permisiunea de rulare a comenzilor în Termux.", "permission_required")
	if not _credentials(): return Common.failure("Conexiunea locală nu poate fi pregătită.", "missing_bridge")
	if await _health():
		note("Conectorul local răspunde.", "connected")
		return Common.success(runtime)
	if manual_mode(): return Common.failure("Pornește conectorul din Termux: copiază comanda din Integrări → Blender, lipește-o în terminal și apasă Enter.", "manual_start_required")
	note("Pornire conector local prin Android → Termux.", "starting")
	var launched = native("start", {"install_python": prepare})
	if not launched.get("ok", false): return launched
	state["stage"] = "Pregătire conector Termux…"
	changed.emit()
	var deadline = Time.get_ticks_msec() + (300000 if prepare else 30000)
	while Time.get_ticks_msec() < deadline:
		if setup_cancel.get("cancelled", false): return Common.failure("Conectare oprită.", "cancelled")
		if await _health():
			note("Conectorul local răspunde.", "connected")
			return Common.success(runtime)
		var current = native("status")
		if not str(current.get("error", "")).is_empty(): return Common.failure(str(current["error"]), "termux_start_failed")
		if not is_instance_valid(owner) or not owner.is_inside_tree(): return Common.failure("Editorul s-a închis.", "interrupted")
		await owner.get_tree().create_timer(0.5).timeout
	return Common.failure("Termux nu răspunde. Deschide-l, activează comenzile externe și verifică permisiunile.", "connection_failed")

func ensure_ready(cancel: Dictionary = {}) -> bool:
	if working or refreshing: return false
	if verified.is_empty():
		await refresh()
		return false
	setup_cancel = cancel
	working = true
	var result = await _connect(false)
	working = false
	if not result.get("ok", false): _failure(result)
	else:
		state.erase("error_code")
		state.erase("error")
		_report_state()
	changed.emit()
	return result.get("ok", false) and available()

func _remember() -> bool:
	return Common.atomic_json(project_directory.path_join("pending.json"), pending) == OK

func _clear_pending() -> bool:
	var previous = pending
	pending = {}
	if _remember(): return true
	pending = previous
	return false

func _wait(id: String, cancel: Dictionary) -> Dictionary:
	var sent_cancel = false
	while is_instance_valid(owner) and owner.is_inside_tree():
		if cancel.get("cancelled", false) and not sent_cancel:
			await _http("/v1/jobs/" + id + "/cancel", HTTPClient.METHOD_POST, {})
			sent_cancel = true
		var response = await _http("/v1/jobs/" + id)
		if not response.get("ok", false):
			connected = false
			return Common.failure("Conexiune întreruptă. Folosește Recuperează pentru sarcina " + id + ".", "connection_lost")
		var job: Dictionary = response["result"]
		state["stage"] = str(job.get("stage", "În lucru…"))
		if job.get("cancel_requested", false): state["stage"] = "Oprire după etapa curentă…" if job.get("kind") == "install" else "Oprire…"
		var output = _safe(str(job.get("log", ""))).right(LOG_LIMIT)
		if output != job_log:
			job_log = output
			_save_log()
		changed.emit()
		if job.get("status") in TERMINAL:
			if job.get("status") != "completed":
				_clear_pending()
				return Common.failure(str(job.get("error", "Sarcină oprită.")), str(job.get("code", "interrupted")))
			return Common.success(job.get("result", {}))
		await owner.get_tree().create_timer(0.4).timeout
	return Common.failure("Editor închis; verifică starea sarcinii la revenire.", "interrupted")

func _submit(kind: String, args: Dictionary, cancel: Dictionary, id: String = "", context: Dictionary = {}) -> Dictionary:
	if cancel.get("cancelled", false): return Common.failure("Sarcină oprită.", "cancelled")
	if not pending.is_empty(): return Common.failure("Există o sarcină de recuperat. Folosește Recuperează în Integrări.", "pending_job")
	if id.is_empty(): id = Common.uid()
	job_log = ""
	note(str({"discover": "Caut Blender în instalările existente.", "install": "Pornesc instalarea Blender.", "verify": "Verific exportul Blender și importul GLB în Godot.", "run": "Pornesc sarcina Blender."}.get(kind, "Pornesc sarcina Blender.")), kind)
	if kind == "verify":
		verified = {}
		Common.atomic_json(directory.path_join("verified.json"), {})
	pending = {"id": id, "kind": kind, "args": args}
	pending.merge(context)
	if not _remember():
		pending = {}
		return Common.failure("Nu pot salva identificatorul sarcinii.", "checkpoint_failed")
	var response = await _http("/v1/jobs", HTTPClient.METHOD_POST, {"id": id, "kind": kind, "args": args})
	if not response.get("ok", false):
		if int(response.get("http_status", 0)) in [400, 409]: _clear_pending()
		return response
	return await _wait(id, cancel) if kind != "run" else response

func setup(action: String) -> Dictionary:
	if working or refreshing: return Common.failure("Blender este ocupat.", "busy")
	working = true
	setup_cancel = {}
	var response = await _connect(action in ["connect", "install", "repair"])
	if response.get("ok", false):
		if action == "resume":
			response = await _resume(setup_cancel)
		else:
			var kind = "install" if action in ["install", "repair"] else "discover" if action == "connect" else "verify"
			response = await _submit(kind, {"repair": true} if action == "repair" else {}, setup_cancel)
			if response.get("ok", false):
				if kind == "verify": response = await _accept_verification(response["result"], setup_cancel)
				else:
					discovery_complete = true
					runtime = response["result"] if response["result"].get("found", false) else {}
					_clear_pending()
					if not runtime.is_empty():
						response = await _submit("verify", {}, setup_cancel)
						if response.get("ok", false): response = await _accept_verification(response["result"], setup_cancel)
	if response.get("ok", false):
		state.erase("error_code")
		state.erase("error")
		state["stage"] = "Disponibil" if available() else "Blender nu este instalat"
		note(str(state["stage"]), "ready" if available() else "runtime_missing")
	else: _failure(response)
	working = false
	changed.emit()
	return response

func _resume(cancel: Dictionary) -> Dictionary:
	if pending.is_empty(): return Common.failure("Nu există o sarcină de recuperat.", "missing_job")
	var status = await _http("/v1/jobs/" + str(pending["id"]))
	if status.get("code") == "missing_job":
		_clear_pending()
		return Common.failure("Sarcina nu a ajuns la Termux. Poți porni din nou operația.", "missing_job")
	if status.get("ok", false) and status.get("result", {}).get("status") == "staging":
		for item in pending.get("args", {}).get("inputs", []):
			var uploaded = await _upload(str(pending["id"]), item, "res://" + str(item["path"]), cancel)
			if not uploaded.get("ok", false): return uploaded
		var started = await _http("/v1/jobs/" + str(pending["id"]) + "/start", HTTPClient.METHOD_POST, {})
		if not started.get("ok", false): return started
	var result = await _wait(str(pending["id"]), cancel)
	if not result.get("ok", false): return result
	match str(pending.get("kind")):
		"verify": return await _accept_verification(result["result"], cancel)
		"run": return await _accept_run(result["result"], cancel)
		_:
			runtime = result["result"] if result["result"].get("found", false) else {}
			_clear_pending()
			if runtime.is_empty(): return result
			result = await _submit("verify", {}, cancel)
			return await _accept_verification(result["result"], cancel) if result.get("ok", false) else result

func _download(result: Dictionary, cancel: Dictionary) -> Dictionary:
	var id = str(pending.get("id", ""))
	var target = project_directory.path_join(id)
	DirAccess.make_dir_recursive_absolute(target)
	var files = []
	var total = 0
	for item in result.get("artifacts", []):
		var name = str(item.get("path", ""))
		if not valid_relative(name): return Common.failure("Cale de rezultat invalidă.", "invalid_artifact")
		var size = int(item.get("bytes", 0))
		total += size
		if size <= 0 or size > 512 * 1024 * 1024 or total > 1024 * 1024 * 1024 or files.size() >= 256: return Common.failure("Rezultate prea mari.", "artifact_limit")
		var path = target.path_join(name)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != str(item.get("sha256", "")):
			var reply = await _http("/v1/jobs/" + id + "/outputs/" + encode_path(name), HTTPClient.METHOD_GET, null, {"timeout": 300, "idle_timeout": 30, "max_bytes": size, "save_path": path + ".part", "cancel": cancel})
			if not reply.get("ok", false): return reply
			var temporary = FileAccess.open(path + ".part", FileAccess.READ)
			if temporary == null or temporary.get_length() != size or FileAccess.get_sha256(path + ".part") != str(item.get("sha256", "")): return Common.failure("Transfer incomplet sau hash invalid.", "hash_mismatch")
			temporary.close()
			if DirAccess.rename_absolute(path + ".part", path) != OK: return Common.failure("Nu pot salva rezultatul.")
		files.append({"name": name, "path": path, "sha256": item.get("sha256")})
	for item in files:
		var extension = str(item["name"]).get_extension().to_lower()
		if extension in ["png", "jpg", "jpeg", "webp"]:
			var dimensions = FileRegistry.image_dimensions(str(item["path"]))
			if dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x * dimensions.y > 24000000: return Common.failure("Imaginea depășește bugetul de previzualizare.", "invalid_artifact")
			var image = Image.load_from_file(str(item["path"]))
			if image == null or image.is_empty(): return Common.failure("Imagine rezultată invalidă.", "invalid_artifact")
		elif extension in ["glb", "gltf"]:
			var safe = validate_model(str(item["path"]), target)
			if not safe.get("ok", false): return safe
			if GLTFDocument.new().append_from_file(str(item["path"]), GLTFState.new()) != OK: return Common.failure("Model rezultat invalid.", "invalid_artifact")
	return Common.success(files)

func _accept_verification(result: Dictionary, cancel: Dictionary) -> Dictionary:
	var downloaded = await _download(result, cancel)
	if not downloaded.get("ok", false): return downloaded
	var glb = ""
	for file in downloaded["result"]:
		if file["name"] == "probe.glb": glb = file["path"]
	if glb.is_empty(): return Common.failure("Proba nu conține GLB.", "missing_artifact")
	state["stage"] = "Verificare import în Godot…"
	changed.emit()
	var document = GLTFDocument.new()
	var gltf = GLTFState.new()
	if document.append_from_file(glb, gltf) != OK: return Common.failure("Godot nu poate importa GLB-ul de probă.", "import_failed")
	var scene = document.generate_scene(gltf)
	if scene == null: return Common.failure("Scena GLB de probă este invalidă.", "import_failed")
	var meshes = scene_mesh_count(scene)
	scene.free()
	if meshes == 0: return Common.failure("Proba nu conține un mesh.", "empty_mesh")
	note("GLB verificat în Godot: %d mesh-uri cu geometrie." % meshes, "import_verified")
	runtime = result.get("runtime", {})
	verified = {"fingerprint": fingerprint(runtime), "verified_at": Time.get_unix_time_from_system(), "protocol": 1}
	if Common.atomic_json(directory.path_join("verified.json"), verified) != OK: return Common.failure("Nu pot salva verificarea Blender.", "checkpoint_failed")
	var id = str(pending["id"])
	if not _clear_pending(): return Common.failure("Nu pot confirma verificarea. Reia recuperarea.", "checkpoint_failed")
	await _http("/v1/jobs/" + id + "/ack", HTTPClient.METHOD_POST, {})
	_release_downloads(downloaded["result"])
	return Common.success(runtime)

static func scene_mesh_count(scene: Node) -> int:
	# Editor imports keep ImporterMeshInstance3D; game runtime imports use MeshInstance3D.
	# Include the root itself, and only count instances with actual mesh surfaces.
	var queue = [scene] if scene != null else []
	var count = 0
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node is MeshInstance3D or node is ImporterMeshInstance3D:
			if node.mesh != null and node.mesh.get_surface_count() > 0: count += 1
		queue.append_array(node.get_children())
	return count

func run(args: Dictionary, cancel: Dictionary = {}) -> Dictionary:
	if working or refreshing: return Common.failure("Blender este ocupat.", "busy")
	if not available(): return Common.failure("Verifică Blender din Integrări înainte de utilizare.", "blender_not_ready")
	working = true
	var response = await _connect()
	if response.get("ok", false) and not available(): response = Common.failure("Instalarea Blender s-a schimbat. Repetă verificarea.", "blender_not_ready")
	if response.get("ok", false): response = await _run_files(args, cancel)
	working = false
	changed.emit()
	return response

func _run_files(args: Dictionary, cancel: Dictionary) -> Dictionary:
	var script = Common.project_path(str(args.get("script", "")))
	var blend = Common.project_path(str(args.get("blend", ""))) if not str(args.get("blend", "")).is_empty() else ""
	if script.is_empty() or not safe_project_path(script) or script.get_extension() != "py": return Common.failure("Selectează un script Python din proiect.", "invalid_script")
	if not str(args.get("blend", "")).is_empty() and (blend.is_empty() or blend.get_extension() != "blend"): return Common.failure("Fișier .blend invalid.", "invalid_blend")
	var paths = [script]
	if not blend.is_empty(): paths.append(blend)
	for input in args.get("inputs", []):
		var path = Common.project_path(str(input))
		if path.is_empty(): return Common.failure("Intrare din afara proiectului.", "invalid_input")
		if path not in paths: paths.append(path)
	var manifest = []
	for path in paths:
		if not safe_project_path(str(path)): return Common.failure("Intrările nu pot include legături simbolice sau directoare private.", "invalid_input")
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null: return Common.failure("Fișier absent: " + path, "missing_input")
		var length = file.get_length()
		file.close()
		if length > 512 * 1024 * 1024: return Common.failure("Fișier de intrare prea mare.", "input_limit")
		manifest.append({"path": str(path).trim_prefix("res://"), "bytes": length, "sha256": FileAccess.get_sha256(path)})
	var output = Common.project_path(str(args.get("output_directory", "res://ai_assets/blender")))
	if output.is_empty() or not safe_project_path(output): return Common.failure("Directorul rezultatului trebuie să fie în proiect.", "invalid_output")
	var payload = {"script": script.trim_prefix("res://"), "blend": blend.trim_prefix("res://"), "inputs": manifest, "seconds": clampi(int(args.get("seconds", 120)), 1, 600)}
	var response = await _submit("run", payload, cancel, "", {"output_directory": output, "asset_name": script.get_file().get_basename().validate_filename().left(64)})
	if not response.get("ok", false): return response
	for input in manifest:
		response = await _upload(str(pending["id"]), input, "res://" + str(input["path"]), cancel)
		if not response.get("ok", false):
			if cancel.get("cancelled", false):
				await _http("/v1/jobs/" + str(pending["id"]) + "/cancel", HTTPClient.METHOD_POST, {})
				_clear_pending()
				return Common.failure("Transfer oprit.", "cancelled")
			return response
	response = await _http("/v1/jobs/" + str(pending["id"]) + "/start", HTTPClient.METHOD_POST, {})
	if not response.get("ok", false): return response
	response = await _wait(str(pending["id"]), cancel)
	return await _accept_run(response["result"], cancel) if response.get("ok", false) else response

func _accept_run(result: Dictionary, cancel: Dictionary) -> Dictionary:
	var downloaded = await _download(result, cancel)
	if not downloaded.get("ok", false): return downloaded
	var base = Common.project_path(str(pending.get("output_directory", "res://ai_assets/blender")))
	if base.is_empty() or not safe_project_path(base): return Common.failure("Destinație invalidă.", "invalid_output")
	var folder = base.path_join(str(pending.get("asset_name", "asset")).validate_filename() + "_" + str(pending["id"]).left(8))
	var absolute = ProjectSettings.globalize_path(folder)
	var staging = absolute.get_base_dir().path_join("." + absolute.get_file() + ".pending")
	var parent = DirAccess.open(absolute.get_base_dir())
	if parent != null and (parent.is_link(absolute.get_file()) or parent.is_link(staging.get_file())): return Common.failure("Destinația conține o legătură simbolică.", "invalid_output")
	var files = []
	# A reconnect after the final rename reuses the same complete folder and hashes.
	var committed = DirAccess.dir_exists_absolute(absolute)
	for item in downloaded["result"]:
		if cancel.get("cancelled", false): return Common.failure("Import oprit.", "cancelled")
		var target = (absolute if committed else staging).path_join(str(item["name"]))
		if committed:
			if FileAccess.get_sha256(target) != item["sha256"]: return Common.failure("Directorul rezultatului a fost modificat. Nu suprascriu fișierele.", "output_conflict")
		else:
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			if DirAccess.copy_absolute(str(item["path"]), target) != OK: return Common.failure("Nu pot importa fișierul rezultat.", "import_failed")
			if FileAccess.get_sha256(target) != item["sha256"]: return Common.failure("Fișier modificat în timpul importului.", "hash_mismatch")
			if str(item["name"]).get_extension().to_lower() == "blend":
				# Android's built-in .blend importer cannot launch the Termux executable.
				# Keep the editable source; the sibling GLB supplies the Godot scene/preview.
				var keep = FileAccess.open(target + ".import", FileAccess.WRITE)
				if keep == null: return Common.failure("Nu pot păstra sursa Blender.", "import_failed")
				keep.store_string("[remap]\n\nimporter=\"keep\"\n")
				keep.close()
		files.append(folder.path_join(str(item["name"])))
	if not committed and not files.is_empty() and DirAccess.rename_absolute(staging, absolute) != OK: return Common.failure("Nu pot finaliza directorul rezultatului.", "import_failed")
	var response = Common.success({"job": pending["id"], "exit_code": 0, "outputs": files, "output": log_text})
	var id = str(pending["id"])
	if not _clear_pending(): return Common.failure("Importat, dar confirmarea nu a putut fi salvată. Reia recuperarea.", "checkpoint_failed")
	await _http("/v1/jobs/" + id + "/ack", HTTPClient.METHOD_POST, {})
	_release_downloads(downloaded["result"])
	if Engine.is_editor_hint() and not files.is_empty(): EditorInterface.get_resource_filesystem().scan()
	return response

func _release_downloads(files: Array) -> void:
	for item in files:
		var path = str(item["path"])
		if path.begins_with(project_directory + "/"): DirAccess.remove_absolute(path)
		var folder = path.get_base_dir()
		while folder.begins_with(project_directory + "/"):
			if DirAccess.remove_absolute(folder) != OK: break
			folder = folder.get_base_dir()

static func valid_relative(path: String) -> bool:
	if path.is_empty() or path.length() > 1024 or path.is_absolute_path() or "\\" in path or path.to_utf8_buffer().find(0) >= 0: return false
	for segment in path.split("/", true):
		if segment.is_empty() or segment.begins_with("."): return false
	return true

static func safe_project_path(path: String) -> bool:
	if Common.project_path(path).is_empty() or not valid_relative(path.trim_prefix("res://")): return false
	var walk = ProjectSettings.globalize_path("res://")
	for segment in path.trim_prefix("res://").split("/"):
		var parent = DirAccess.open(walk)
		if parent != null and parent.is_link(segment): return false
		walk = walk.path_join(segment)
	return true

static func validate_model(path: String, root: String) -> Dictionary:
	var input = FileAccess.open(path, FileAccess.READ)
	if input == null: return Common.failure("Model absent.", "invalid_artifact")
	var document: Variant
	if path.get_extension().to_lower() == "glb":
		if input.get_length() < 20 or input.get_32() != 0x46546c67 or input.get_32() != 2 or input.get_32() != input.get_length(): return Common.failure("Antet GLB invalid.", "invalid_artifact")
		var length = input.get_32()
		if length > 8 * 1024 * 1024 or length > input.get_length() - 20 or input.get_32() != 0x4e4f534a: return Common.failure("Document GLB invalid sau prea mare.", "invalid_artifact")
		document = Common.parse_json(input.get_buffer(length).get_string_from_utf8())
	else:
		if input.get_length() > 8 * 1024 * 1024: return Common.failure("Document glTF prea mare.", "invalid_artifact")
		document = Common.parse_json(input.get_as_text())
	input.close()
	if not document is Dictionary or not document.get("buffers", []) is Array or not document.get("images", []) is Array: return Common.failure("Document 3D invalid.", "invalid_artifact")
	for part in document.get("buffers", []) + document.get("images", []):
		if not part is Dictionary: return Common.failure("Dependență 3D invalidă.", "invalid_artifact")
		var uri = str(part.get("uri", ""))
		if uri.is_empty() or uri.begins_with("data:"): continue
		var decoded = uri.uri_decode()
		var dependency = path.get_base_dir().path_join(decoded).simplify_path()
		if not valid_relative(decoded) or ":" in decoded or not dependency.begins_with(root + "/") or not FileAccess.file_exists(dependency): return Common.failure("Dependență 3D externă sau lipsă.", "invalid_artifact")
	return Common.success()

static func encode_path(path: String) -> String:
	var encoded = []
	for part in path.split("/"): encoded.append(part.uri_encode())
	return "/".join(encoded)

func _upload(id: String, item: Dictionary, path: String, cancel: Dictionary) -> Dictionary:
	# HTTPClient buffers request bodies. Use a bounded, loopback-only stream for uploads.
	var peer = StreamPeerTCP.new()
	var port = int(Common.parse_url(url, true).get("port", 0))
	if peer.connect_to_host("127.0.0.1", port) != OK: return Common.failure("Transferul nu poate porni.")
	var deadline = Time.get_ticks_msec() + 300000
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		peer.poll()
		if cancel.get("cancelled", false) or Time.get_ticks_msec() > deadline: return Common.failure("Transfer oprit.", "cancelled")
		await owner.get_tree().process_frame
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: return Common.failure("Conexiune locală indisponibilă.")
	var header = "PUT /v1/jobs/%s/inputs/%s HTTP/1.1\r\nHost: 127.0.0.1:%s\r\nAuthorization: Bearer %s\r\nContent-Length: %s\r\nConnection: close\r\n\r\n" % [id, encode_path(str(item["path"])), port, token, item["bytes"]]
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return Common.failure("Fișier de intrare absent.")
	var chunk = header.to_utf8_buffer()
	while true:
		if cancel.get("cancelled", false) or Time.get_ticks_msec() > deadline:
			peer.disconnect_from_host()
			return Common.failure("Transfer oprit.", "cancelled" if cancel.get("cancelled", false) else "timeout")
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: return Common.failure("Transfer întrerupt.", "interrupted_upload")
		if chunk.is_empty():
			if file.get_position() >= file.get_length(): break
			chunk = file.get_buffer(256 * 1024)
		var sent = peer.put_partial_data(chunk)
		if sent[0] != OK: return Common.failure("Transfer întrerupt.", "interrupted_upload")
		chunk = chunk.slice(int(sent[1]))
		await owner.get_tree().process_frame
	file.close()
	var response = PackedByteArray()
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: break
		var count = peer.get_available_bytes()
		if count > 0:
			var data = peer.get_partial_data(mini(count, 65536))
			if data[0] != OK: break
			response.append_array(data[1])
		if response.size() > 65536: break
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: break
		if cancel.get("cancelled", false): break
		await owner.get_tree().process_frame
	peer.disconnect_from_host()
	var text = response.get_string_from_utf8()
	var boundary = text.find("\r\n\r\n")
	var parsed: Variant = Common.parse_json(text.substr(boundary + 4)) if boundary >= 0 else null
	if not parsed is Dictionary: return Common.failure("Fișierul nu a fost acceptat de Termux.", "upload_failed")
	if not text.begins_with("HTTP/1.1 200 ") and parsed.get("ok", true): return Common.failure("Fișierul nu a fost acceptat de Termux.", "upload_failed")
	return parsed

func stop() -> void:
	setup_cancel["cancelled"] = true
	if not pending.is_empty() and connected:
		var result = await _http("/v1/jobs/" + str(pending["id"]) + "/cancel", HTTPClient.METHOD_POST, {})
		if not working and result.get("ok", false) and result.get("result", {}).get("status") in TERMINAL:
			_clear_pending()
			state["stage"] = "Sarcină închisă"
			changed.emit()
