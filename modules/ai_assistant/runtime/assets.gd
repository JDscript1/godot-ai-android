@tool
extends RefCounted

static var Common: GDScript
static var Transport: GDScript
var transport: RefCounted
var vault: RefCounted
var owner: Node
var cache_directory = ""
var jobs: Array = []

func _init(node: Node = null, secret_store: RefCounted = null) -> void:
	owner = node
	transport = Transport.new(node)
	vault = secret_store

func configure(directory: String) -> void:
	cache_directory = directory
	DirAccess.make_dir_recursive_absolute(cache_directory)
	jobs = Common.read_json(cache_directory.path_join("jobs.json"), [])

func definitions() -> Array:
	return [Common.tool("asset_generate", "Generate an image or GLB with a configured Runware or local ComfyUI profile. The job is retained for later polling; use asset_status to retrieve it.", {"profile": Common.string_field(), "prompt": Common.string_field(), "reference": Common.string_field()}, ["profile", "prompt"], "external"), Common.tool("asset_status", "Refresh an existing generation job and download its completed result.", {"job": Common.string_field()}, ["job"]), Common.tool("asset_import", "Import a validated generated artifact into res:// without overwriting existing files.", {"job": Common.string_field(), "directory": Common.string_field()}, ["job", "directory"], "write")]

func models(profile: Dictionary, cancel: Dictionary) -> Dictionary:
	if profile.get("kind") == "comfy":
		return await transport.request(str(profile["url"]).trim_suffix("/") + "/object_info", HTTPClient.METHOD_GET, _headers(profile), null, _options(profile, cancel))
	var result = await _runware(profile, [{"taskType": "modelSearch", "taskUUID": Common.uid(), "search": str(profile.get("search", "")), "limit": 100}], cancel)
	return result

func submit(profile: Dictionary, prompt: String, reference: String, cancel: Dictionary) -> Dictionary:
	var id = Common.uid()
	var kind = str(profile.get("asset_kind", "image"))
	var job = {"id": id, "profile_id": profile["id"], "kind": kind, "provider": profile.get("kind", "runware"), "external_id": id, "status": "submitting", "created": Time.get_datetime_string_from_system(true), "prompt": prompt, "file": ""}
	var result: Dictionary
	if profile.get("kind") == "comfy":
		var workflow: Variant = profile.get("workflow", {})
		if not workflow is Dictionary or workflow.is_empty(): return Common.failure("Importă un workflow ComfyUI în format API.")
		workflow = workflow.duplicate(true)
		var prompt_node = str(profile.get("prompt_node", ""))
		var prompt_input = str(profile.get("prompt_input", "text"))
		var output_node = str(profile.get("output_node", ""))
		if not workflow.has(output_node): return Common.failure("Nodul de rezultat nu există în workflow.")
		if not prompt_node.is_empty():
			if not workflow.has(prompt_node) or not workflow[prompt_node].get("inputs", {}).has(prompt_input): return Common.failure("Câmpul pentru prompt nu există în workflow.")
			workflow[prompt_node]["inputs"][prompt_input] = prompt
		var catalog = await transport.request(str(profile["url"]).trim_suffix("/") + "/object_info", HTTPClient.METHOD_GET, _headers(profile), null, _options(profile, cancel))
		if not catalog.get("ok", false): return catalog
		if not catalog.get("json") is Dictionary: return Common.failure("Serverul nu a returnat definițiile nodurilor.")
		for node_id in workflow:
			if not workflow[node_id] is Dictionary or not catalog["json"].has(str(workflow[node_id].get("class_type", ""))): return Common.failure("Workflowul folosește noduri care nu sunt instalate pe server.")
		if not reference.is_empty():
			var upload = await _comfy_upload(profile, reference, cancel)
			if not upload.get("ok", false): return upload
			var reference_node = str(profile.get("reference_node", ""))
			if not workflow.has(reference_node): return Common.failure("Configurează nodul imaginii de referință.")
			workflow[reference_node]["inputs"][str(profile.get("reference_input", "image"))] = upload["result"]
		result = await transport.request(str(profile["url"]).trim_suffix("/") + "/prompt", HTTPClient.METHOD_POST, _headers(profile), {"prompt": workflow, "client_id": id}, _options(profile, cancel))
		if not result.get("ok", false): return result
		if not result.get("json") is Dictionary or not result["json"].has("prompt_id"): return Common.failure("ComfyUI nu a acceptat workflowul.")
		job["external_id"] = result["json"]["prompt_id"]
		job["output_node"] = output_node
	else:
		var model = str(profile.get("model", ""))
		if model.is_empty(): return Common.failure("Alege modelul de generare.")
		var task = {"taskType": "3dInference" if kind == "mesh" else "imageInference", "taskUUID": id, "model": model, "deliveryMethod": "async", "includeCost": true, "outputFormat": "GLB" if kind == "mesh" else "PNG"}
		if kind == "image":
			task["positivePrompt"] = prompt
			task["width"] = int(profile.get("width", 1024))
			task["height"] = int(profile.get("height", 1024))
		elif model.to_lower().begins_with("microsoft:trellis-2"):
			var source = _reference_data(reference)
			if source.is_empty(): return Common.failure("Acest model 3D necesită o imagine de referință.")
			task["inputs"] = {"image": source}
		else:
			task["positivePrompt"] = prompt
			if not reference.is_empty():
				var source = _reference_data(reference)
				if source.is_empty(): return Common.failure("Imagine de referință invalidă.")
				task["inputImages"] = [source]
		result = await _runware(profile, [task], cancel)
		if not result.get("ok", false): return result
	job["status"] = "processing"
	jobs.append(job)
	_save()
	return Common.success(job.duplicate(true))

func refresh(id: String, profile: Dictionary, cancel: Dictionary) -> Dictionary:
	var job = find_job(id)
	if job.is_empty(): return Common.failure("Sarcină de generare inexistentă.")
	if job["status"] == "completed" and FileAccess.file_exists(str(job["file"])): return Common.success(job.duplicate(true))
	var download_url = ""
	if job["provider"] == "comfy":
		var result = await transport.request(str(profile["url"]).trim_suffix("/") + "/history/" + str(job["external_id"]).uri_encode(), HTTPClient.METHOD_GET, _headers(profile), null, _options(profile, cancel))
		if not result.get("ok", false): return result
		if not result.get("json") is Dictionary: return Common.failure("Istoric ComfyUI invalid.")
		var history: Dictionary = result["json"].get(str(job["external_id"]), {})
		if history.get("status", {}).get("status_str", "") == "error":
			job["status"] = "failed"
			_save()
			return Common.failure("Workflowul ComfyUI a eșuat. Consultă istoricul serverului.")
		var output: Dictionary = history.get("outputs", {}).get(str(job.get("output_node", "")), {})
		var candidates = []
		for category in ["images", "3d", "mesh", "files", "gltf", "models"]:
			if output.get(category) is Array: candidates.append_array(output[category])
		var extension = "glb" if job["kind"] == "mesh" else "png"
		for artifact in candidates:
			if not artifact is Dictionary or str(artifact.get("filename", "")).get_extension().to_lower() != extension: continue
			var filename = str(artifact["filename"])
			var subfolder = str(artifact.get("subfolder", ""))
			if ".." in filename or ".." in subfolder or filename.is_absolute_path(): return Common.failure("Cale de rezultat ComfyUI invalidă.")
			download_url = str(profile["url"]).trim_suffix("/") + "/view?filename=" + filename.uri_encode() + "&subfolder=" + subfolder.uri_encode() + "&type=" + str(artifact.get("type", "output")).uri_encode()
			break
	else:
		var result = await _runware(profile, [{"taskType": "getResponse", "taskUUID": str(job["external_id"])}], cancel)
		if not result.get("ok", false): return result
		for item in result.get("result", []):
			if not item is Dictionary: continue
			if item.get("status") == "error":
				job["status"] = "failed"
				_save()
				return Common.failure(str(item.get("message", "Generarea a eșuat.")))
			download_url = str(item.get("modelURL", item.get("modelUrl", item.get("imageURL", ""))))
			if download_url.is_empty() and not item.get("outputs", {}).get("files", []).is_empty(): download_url = str(item["outputs"]["files"][0].get("url", ""))
			if item.has("cost"): job["cost_usd"] = item["cost"]
			if not download_url.is_empty(): break
		if not download_url.is_empty():
			var parsed = Common.parse_url(download_url)
			if not parsed.get("ok", false) or not (str(parsed["host"]) == "runware.ai" or str(parsed["host"]).ends_with(".runware.ai")): return Common.failure("Destinație de descărcare Runware nevalidată.")
	if download_url.is_empty(): return Common.success(job.duplicate(true))
	var extension = ".glb" if job["kind"] == "mesh" else ".png"
	var temporary = cache_directory.path_join(id + extension + ".part")
	var options = _options(profile, cancel)
	options["save_path"] = temporary
	options["max_bytes"] = Common.MAX_ASSET_BYTES
	options["timeout"] = 120
	# Provider credentials are never sent to storage/CDN URLs.
	var download = await transport.request(download_url, HTTPClient.METHOD_GET, _headers(profile) if job["provider"] == "comfy" else PackedStringArray(), null, options)
	if not download.get("ok", false): return download
	var validation = validate_artifact(temporary, str(job["kind"]))
	if not validation.get("ok", false): return validation
	var path = cache_directory.path_join(id + extension)
	if DirAccess.rename_absolute(temporary, path) != OK: return Common.failure("Nu pot păstra rezultatul descărcat.")
	job["file"] = path
	job["status"] = "completed"
	_save()
	return Common.success(job.duplicate(true))

func import_job(id: String, directory: String) -> Dictionary:
	var job = find_job(id)
	if job.is_empty() or job.get("status") != "completed": return Common.failure("Generarea nu este finalizată.")
	var target = Common.project_path(directory)
	if target.is_empty(): return Common.failure("Alege o destinație din res://.")
	var validation = validate_artifact(str(job["file"]), str(job["kind"]))
	if not validation.get("ok", false): return validation
	if DirAccess.make_dir_recursive_absolute(target) != OK: return Common.failure("Nu pot crea destinația.")
	var extension = ".glb" if job["kind"] == "mesh" else ".png"
	var path = target.path_join("generated_" + id.left(12) + extension)
	if FileAccess.file_exists(path): path = target.path_join("generated_" + Common.uid().left(12) + extension)
	var error = DirAccess.copy_absolute(str(job["file"]), ProjectSettings.globalize_path(path))
	if error != OK: return Common.failure(error_string(error))
	if Engine.is_editor_hint(): EditorInterface.get_resource_filesystem().scan()
	job["imported_path"] = path
	_save()
	return Common.success({"path": path, "import_requested": true})

func find_job(id: String) -> Dictionary:
	for job in jobs:
		if job["id"] == id: return job
	return {}

static func validate_artifact(path: String, kind: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() == 0 or file.get_length() > Common.MAX_ASSET_BYTES: return Common.failure("Rezultat lipsă sau prea mare.")
	if kind == "mesh":
		if file.get_length() < 20 or file.get_32() != 0x46546C67 or file.get_32() != 2: return Common.failure("Rezultatul nu este GLB 2.0 valid.")
		if file.get_32() != file.get_length(): return Common.failure("GLB trunchiat.")
		var length = file.get_32()
		if file.get_32() != 0x4E4F534A or length > file.get_length() - 20: return Common.failure("GLB fără document JSON valid.")
		var document: Variant = JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
		if not document is Dictionary or str(document.get("asset", {}).get("version", "")) != "2.0": return Common.failure("Document glTF invalid.")
		for image in document.get("images", []):
			if image.has("uri") and not str(image["uri"]).begins_with("data:"): return Common.failure("GLB conține imagini externe; este necesar un fișier autonom.")
		for buffer in document.get("buffers", []):
			if buffer.has("uri") and not str(buffer["uri"]).begins_with("data:"): return Common.failure("GLB conține buffere externe.")
	else:
		file.seek(0)
		if file.get_buffer(8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]): return Common.failure("Rezultatul nu este PNG.")
		var image = Image.new()
		if image.load(path) != OK or image.is_empty(): return Common.failure("Imagine PNG coruptă.")
	return Common.success()

func _headers(profile: Dictionary) -> PackedStringArray:
	var secret = vault.read(str(profile["id"])) if vault != null else ""
	return PackedStringArray(["Authorization: Bearer " + secret]) if not secret.is_empty() else PackedStringArray()

func _options(profile: Dictionary, cancel: Dictionary) -> Dictionary:
	return {"allow_http": profile.get("allow_http", false), "cancel": cancel}

func _runware(profile: Dictionary, tasks: Array, cancel: Dictionary) -> Dictionary:
	var result = await transport.request("https://api.runware.ai/v1", HTTPClient.METHOD_POST, _headers(profile), tasks, {"cancel": cancel})
	if not result.get("ok", false): return result
	var json: Variant = result.get("json")
	if not json is Dictionary: return Common.failure("Răspuns Runware invalid.")
	if not json.get("errors", []).is_empty(): return Common.failure(JSON.stringify(json["errors"]).left(2000), "generation_failed")
	return Common.success(json.get("data", []))

func _reference_data(path: String) -> String:
	var safe = Common.project_path(path)
	if safe.is_empty() or not FileAccess.file_exists(safe): return ""
	var file = FileAccess.open(safe, FileAccess.READ)
	if file == null or file.get_length() > 16 * 1024 * 1024: return ""
	var extension = safe.get_extension().to_lower()
	if extension not in ["png", "jpg", "jpeg", "webp"]: return ""
	return "data:image/" + ("jpeg" if extension == "jpg" else extension) + ";base64," + Marshalls.raw_to_base64(file.get_buffer(file.get_length()))

func _comfy_upload(profile: Dictionary, path: String, cancel: Dictionary) -> Dictionary:
	var safe = Common.project_path(path)
	if safe.is_empty(): return Common.failure("Referința trebuie importată în proiect.")
	var file = FileAccess.open(safe, FileAccess.READ)
	if file == null or file.get_length() > 16 * 1024 * 1024: return Common.failure("Imagine inexistentă sau prea mare.")
	var boundary = "godotai" + Common.uid()
	var bytes = ("--" + boundary + "\r\nContent-Disposition: form-data; name=\"image\"; filename=\"" + Common.uid() + "." + safe.get_extension() + "\"\r\nContent-Type: application/octet-stream\r\n\r\n").to_utf8_buffer()
	bytes.append_array(file.get_buffer(file.get_length()))
	bytes.append_array(("\r\n--" + boundary + "--\r\n").to_utf8_buffer())
	var headers = _headers(profile)
	headers.append("Content-Type: multipart/form-data; boundary=" + boundary)
	var result = await transport.request(str(profile["url"]).trim_suffix("/") + "/upload/image", HTTPClient.METHOD_POST, headers, bytes, _options(profile, cancel))
	if not result.get("ok", false): return result
	if not result.get("json") is Dictionary or not result["json"].has("name"): return Common.failure("Încărcarea referinței nu a reușit.")
	return Common.success(str(result["json"].get("subfolder", "")).path_join(str(result["json"]["name"])).trim_prefix("/"))

func _save() -> void:
	Common.atomic_json(cache_directory.path_join("jobs.json"), jobs)
