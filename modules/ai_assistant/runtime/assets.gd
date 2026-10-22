@tool
extends RefCounted

static var Common: GDScript
static var Transport: GDScript
var transport: RefCounted
var vault: RefCounted
var owner: Node
var cache_directory = ""
var jobs: Array = []

# Endpoints are fixed in production. Tests can replace this instance map only.
var api_urls = {"meshy": "https://api.meshy.ai", "tripo": "https://openapi.tripo3d.ai/v3", "openai_image": "https://api.openai.com/v1"}
var test_http = false
const KINDS = ["runware", "comfy", "meshy", "tripo", "openai_image"]
const LABELS = ["Runware", "ComfyUI local", "Meshy", "Tripo", "OpenAI Images"]

func _init(node: Node = null, secret_store: RefCounted = null) -> void:
	owner = node
	transport = Transport.new(node)
	vault = secret_store

func configure(directory: String) -> void:
	cache_directory = directory
	DirAccess.make_dir_recursive_absolute(cache_directory)
	jobs = Common.read_json(cache_directory.path_join("jobs.json"), [])

func definitions() -> Array:
	return [Common.tool("asset_generate", "Generate an image or GLB with a configured Runware, ComfyUI, Meshy, Tripo or OpenAI Images profile. Meshy text-to-3D produces preview geometry; image-to-3D includes textures. Cloud generation consumes provider credits. The job is retained for later polling; use asset_wait to wait for its result before importing.", {"profile": Common.string_field(), "prompt": Common.string_field(), "reference": Common.string_field()}, ["profile", "prompt"], "external"), Common.tool("asset_status", "Refresh an existing generation job and download its completed result.", {"job": Common.string_field()}, ["job"]), Common.tool("asset_wait", "Wait for a generation job without consuming repeated model turns. Cancellable; defaults to 300 seconds, maximum 600. Returns processing if the deadline expires.", {"job": Common.string_field(), "max_seconds": {"type": "integer"}}, ["job"]), Common.tool("asset_import", "Import a validated generated artifact into res:// without overwriting existing files.", {"job": Common.string_field(), "directory": Common.string_field()}, ["job", "directory"], "write")]

func models(profile: Dictionary, cancel: Dictionary) -> Dictionary:
	var provider = str(profile.get("kind", "runware"))
	if provider in ["meshy", "tripo", "openai_image"]:
		var endpoint = "/openapi/v1/balance" if provider == "meshy" else ("/account/balance" if provider == "tripo" else "/models")
		var checked = await _cloud_request(profile, endpoint, null, cancel)
		if not checked.get("ok", false): return checked
		var available = []
		if provider == "meshy": available = [{"id": "latest", "name": "Meshy · implicit"}]
		elif provider == "tripo": available = [{"id": "v3.1-20260211", "name": "Tripo H 3.1"}] if profile.get("asset_kind") == "mesh" else [{"id": "seedream_v5", "name": "Seedream V5"}]
		else:
			for model in checked.get("result", {}).get("data", []):
				if model is Dictionary and str(model.get("id", "")).begins_with("gpt-image-"): available.append(model)
		return {"ok": true, "result": available, "credential_verified": true, "source": "documented_presets" if provider != "openai_image" else "account_catalog"}
	if profile.get("kind") == "comfy":
		return await transport.request(str(profile["url"]).trim_suffix("/") + "/object_info", HTTPClient.METHOD_GET, _headers(profile), null, _options(profile, cancel))
	var result = await transport.request("https://runware.ai/docs/models/index.json", HTTPClient.METHOD_GET, [], null, {"cancel": cancel})
	if not result.get("ok", false): return result
	if not result.get("json") is Array: return Common.failure("Catalogul public Runware nu este disponibil.")
	var available = []
	for model in result["json"]:
		if not model is Dictionary or model.get("status") == "retired": continue
		# SAM also requires a mask; the simple one-reference form cannot supply it.
		if str(model.get("air", "")).begins_with("meta:sam@3d"): continue
		var capabilities: Array = model.get("capabilities", [])
		var suitable = "text-to-image" in capabilities if profile.get("asset_kind", "image") == "image" else ("text-to-3d" in capabilities or "image-to-3d" in capabilities)
		if suitable: available.append(model)
	return {"ok": true, "result": available, "source": "public_catalog", "credential_verified": false}

func submit(profile: Dictionary, prompt: String, reference: String, cancel: Dictionary) -> Dictionary:
	if str(profile.get("kind", "runware")) in ["meshy", "tripo", "openai_image"]: return await _cloud_submit(profile, prompt, reference, cancel)
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
		var reference_data = _reference_data(reference) if not reference.is_empty() else ""
		if not reference.is_empty() and reference_data.is_empty(): return Common.failure("Imagine de referință invalidă.")
		var built = build_runware_task(profile, prompt, reference_data, id)
		if not built.get("ok", false): return built
		result = await _runware(profile, [built["result"]], cancel)
		if not result.get("ok", false): return result
	job["status"] = "processing"
	jobs.append(job)
	_save()
	return Common.success(job.duplicate(true))

static func build_runware_task(profile: Dictionary, prompt: String, reference_data: String, id: String) -> Dictionary:
	var kind = str(profile.get("asset_kind", "image"))
	var model = str(profile.get("model", ""))
	if model.is_empty(): return Common.failure("Alege modelul de generare.")
	var task = {"taskType": "3dInference" if kind == "mesh" else "imageInference", "taskUUID": id, "model": model, "deliveryMethod": "async", "includeCost": true, "outputFormat": "GLB" if kind == "mesh" else "PNG"}
	if kind == "image":
		if not reference_data.is_empty(): return Common.failure("Profilul Runware de imagini generează din text. Pentru un workflow cu imagine de referință configurează ComfyUI.")
		task["positivePrompt"] = prompt
		task["width"] = int(profile.get("width", 1024))
		task["height"] = int(profile.get("height", 1024))
	elif model.begins_with("meta:sam@3d"):
		return Common.failure("SAM 3D necesită și o mască. Configurează un workflow ComfyUI cu toate intrările necesare sau alege alt model.")
	elif model.to_lower().begins_with("microsoft:trellis-2"):
		if reference_data.is_empty(): return Common.failure("Acest model 3D necesită o imagine de referință.")
		task["inputs"] = {"image": reference_data}
	elif not reference_data.is_empty():
		# Current Runware schemas use singular image for Hunyuan Rapid, arrays elsewhere.
		task["inputs"] = {"image": reference_data} if model.begins_with("tencent:hunyuan-3d@3.1-rapid") else {"images": [reference_data]}
	else:
		task["positivePrompt"] = prompt
	return Common.success(task)

func refresh(id: String, profile: Dictionary, cancel: Dictionary) -> Dictionary:
	var job = find_job(id)
	if job.is_empty(): return Common.failure("Sarcină de generare inexistentă.")
	if str(job.get("profile_id", "")) != str(profile.get("id", "")) or job.get("provider") != profile.get("kind", "runware"): return Common.failure("Profilul nu corespunde sarcinii salvate.")
	if job.get("status") == "failed": return Common.failure(str(job.get("error", "Generarea a eșuat.")), "generation_failed")
	if job["status"] == "completed" and FileAccess.file_exists(str(job["file"])): return Common.success(job.duplicate(true))
	var download_url = ""
	if job["provider"] in ["meshy", "tripo", "openai_image"]:
		var polled = await _cloud_poll(job, profile, cancel)
		if not polled.get("ok", false): return polled
		download_url = str(polled.get("result", ""))
	elif job["provider"] == "comfy":
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
		if download_url.is_empty() and history.get("status", {}).get("status_str", "") == "success":
			job["status"] = "failed"
			_save()
			return Common.failure("Workflowul s-a încheiat, dar nodul rezultat selectat nu oferă fișierul PNG/GLB cerut. Verifică nodul și formatul rezultatului.", "missing_artifact")
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
			if item.get("status") in ["success", "completed"]:
				job["status"] = "failed"
				_save()
				return Common.failure("Furnizorul a finalizat sarcina fără o adresă de rezultat recunoscută.", "missing_artifact")
		if not download_url.is_empty():
			var parsed = Common.parse_url(download_url)
			if not parsed.get("ok", false) or not (str(parsed["host"]) == "runware.ai" or str(parsed["host"]).ends_with(".runware.ai")): return Common.failure("Destinație de descărcare Runware nevalidată.")
	if download_url.is_empty(): return Common.success(job.duplicate(true))
	var extension = ".glb" if job["kind"] == "mesh" else ".png"
	var temporary = cache_directory.path_join(id + extension + ".part")
	var options = _options(profile, cancel)
	if job["provider"] in ["meshy", "tripo"]: options["allow_http"] = test_http
	options["save_path"] = temporary
	options["max_bytes"] = Common.MAX_ASSET_BYTES
	options["timeout"] = 120
	# Provider credentials are never sent to storage/CDN URLs.
	var download = await transport.request(download_url, HTTPClient.METHOD_GET, _headers(profile) if job["provider"] == "comfy" else PackedStringArray(), null, options)
	if not download.get("ok", false): return download
	return _finish_download(job, temporary)

func _finish_download(job: Dictionary, temporary: String) -> Dictionary:
	var validation = validate_artifact(temporary, str(job["kind"]))
	if not validation.get("ok", false):
		DirAccess.remove_absolute(temporary)
		return validation
	var extension = ".glb" if job["kind"] == "mesh" else ".png"
	var path = cache_directory.path_join(str(job["id"]) + extension)
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

func wait_for_job(id: String, profile: Dictionary, cancel: Dictionary, max_seconds: int = 300) -> Dictionary:
	var deadline = Time.get_ticks_msec() + clampi(max_seconds, 1, 600) * 1000
	while not cancel.get("cancelled", false):
		var result = await refresh(id, profile, cancel)
		if not result.get("ok", false) or result.get("result", {}).get("status") in ["completed", "failed"]: return result
		if Time.get_ticks_msec() >= deadline: return result
		await owner.get_tree().create_timer(1.0).timeout
	return Common.failure("Urmărirea a fost oprită. Sarcina poate continua la furnizor; reia verificarea din Generare.", "cancelled")

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
		var document: Variant = Common.parse_json(file.get_buffer(length).get_string_from_utf8())
		if not document is Dictionary or str(document.get("asset", {}).get("version", "")) != "2.0": return Common.failure("Document glTF invalid.")
		for image in document.get("images", []):
			if image.has("uri") and not str(image["uri"]).begins_with("data:"): return Common.failure("GLB conține imagini externe; este necesar un fișier autonom.")
		for buffer in document.get("buffers", []):
			if buffer.has("uri") and not str(buffer["uri"]).begins_with("data:"): return Common.failure("GLB conține buffere externe.")
	else:
		file.seek(0)
		if file.get_buffer(8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]): return Common.failure("Rezultatul nu este PNG.")
		var image = Image.new()
		file.seek(0)
		if image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK or image.is_empty(): return Common.failure("Imagine PNG coruptă.")
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

# Native REST adapters. No shell, SDK or companion process is required.
static func cloud_payload(profile: Dictionary, prompt: String, reference: String = "") -> Dictionary:
	var provider = str(profile.get("kind", ""))
	var kind = str(profile.get("asset_kind", "image"))
	var model = str(profile.get("model", "")).strip_edges()
	var body = {}
	var endpoint = ""
	match provider:
		"meshy":
			if kind != "mesh": return Common.failure("Meshy este configurat pentru modele GLB.")
			endpoint = "/openapi/v2/text-to-3d" if reference.is_empty() else "/openapi/v1/image-to-3d"
			body = {"mode": "preview", "prompt": prompt, "target_formats": ["glb"]} if reference.is_empty() else {"image_url": reference, "should_texture": true, "enable_pbr": true, "target_formats": ["glb"]}
			if not model.is_empty(): body["ai_model"] = model
		"tripo":
			if kind == "image":
				if not reference.is_empty(): return Common.failure("Profilul Tripo de imagini generează din text; referințele sunt acceptate pentru 3D.")
				endpoint = "/generation/text-to-image"
				body = {"prompt": prompt, "model": model if not model.is_empty() else "seedream_v5", "output_format": "png"}
			else:
				endpoint = "/generation/text-to-model" if reference.is_empty() else "/generation/image-to-model"
				body = {"texture": true, "pbr": true}
				body["prompt" if reference.is_empty() else "input"] = prompt if reference.is_empty() else reference
				if not model.is_empty(): body["model"] = model
		"openai_image":
			if kind != "image" or not reference.is_empty(): return Common.failure("OpenAI Images generează imagini PNG din text în acest profil.")
			endpoint = "/images/generations"
			body = {"model": model if not model.is_empty() else "gpt-image-2.5-flare", "prompt": prompt, "n": 1, "output_format": "png"}
		_:
			return Common.failure("Furnizor de generare necunoscut.")
	return Common.success({"endpoint": endpoint, "body": body})

func _cloud_request(profile: Dictionary, endpoint: String, body: Variant, cancel: Dictionary, extra_headers: PackedStringArray = []) -> Dictionary:
	var provider = str(profile.get("kind", ""))
	if not api_urls.has(provider): return Common.failure("Furnizor de generare necunoscut.")
	if _headers(profile).is_empty(): return Common.failure("Adaugă cheia API pentru acest profil.", "missing_credentials")
	var options = {"cancel": cancel, "allow_http": test_http, "timeout": 240, "max_bytes": Common.MAX_ASSET_BYTES}
	var headers = _headers(profile)
	headers.append_array(extra_headers)
	var response = await transport.request(str(api_urls[provider]) + endpoint, HTTPClient.METHOD_GET if body == null else HTTPClient.METHOD_POST, headers, body, options)
	if not response.get("ok", false): return response
	var data: Variant = response.get("json")
	if not data is Dictionary: return Common.failure("Răspuns de generare invalid.")
	if provider == "tripo":
		if int(data.get("code", -1)) != 0: return Common.failure(str(data.get("message", "Tripo a respins solicitarea.")).left(1000), "generation_failed")
		data = data.get("data", {})
	if not data is Dictionary: return Common.failure("Răspuns de generare invalid.")
	return Common.success(data)

func _cloud_submit(profile: Dictionary, prompt: String, reference: String, cancel: Dictionary) -> Dictionary:
	var provider = str(profile["kind"])
	var reference_value = ""
	if not reference.is_empty():
		if provider == "meshy":
			reference_value = _reference_data(reference)
			if reference_value.is_empty(): return Common.failure("Imagine de referință invalidă.")
		elif provider == "tripo" and profile.get("asset_kind") == "mesh":
			var upload = await _tripo_upload(profile, reference, cancel)
			if not upload.get("ok", false): return upload
			reference_value = str(upload["result"])
		else: return Common.failure("Acest profil generează imagini din text; nu acceptă referințe.")
	var built = cloud_payload(profile, prompt, reference_value)
	if not built.get("ok", false): return built
	var result = await _cloud_request(profile, str(built["result"]["endpoint"]), built["result"]["body"], cancel)
	if not result.get("ok", false): return result
	var data: Dictionary = result["result"]
	var id = Common.uid()
	var job = {"id": id, "profile_id": profile["id"], "kind": profile.get("asset_kind", "image"), "provider": provider, "external_id": "", "status": "processing", "created": Time.get_datetime_string_from_system(true), "prompt": prompt, "file": "", "endpoint": built["result"]["endpoint"]}
	if provider == "openai_image":
		var images: Variant = data.get("data", [])
		if not images is Array or images.is_empty() or not images[0] is Dictionary: return Common.failure("OpenAI nu a returnat o imagine.", "missing_artifact")
		var bytes = Marshalls.base64_to_raw(str(images[0].get("b64_json", "")))
		if bytes.is_empty() or bytes.size() > Common.MAX_ASSET_BYTES: return Common.failure("Rezultat imagine lipsă sau prea mare.")
		var temporary = cache_directory.path_join(id + ".png.part")
		var file = FileAccess.open(temporary, FileAccess.WRITE)
		if file == null: return Common.failure("Nu pot păstra imaginea generată.")
		file.store_buffer(bytes)
		file.close()
		jobs.append(job)
		var finished = _finish_download(job, temporary)
		if not finished.get("ok", false):
			job["status"] = "failed"
			job["error"] = finished.get("error", "Imagine invalidă.")
			_save()
		return finished
	job["external_id"] = str(data.get("result", "")) if provider == "meshy" else str(data.get("task_id", ""))
	if str(job["external_id"]).is_empty(): return Common.failure("Furnizorul nu a returnat identificatorul sarcinii.")
	jobs.append(job)
	_save()
	return Common.success(job.duplicate(true))

func _cloud_poll(job: Dictionary, profile: Dictionary, cancel: Dictionary) -> Dictionary:
	var provider = str(job["provider"])
	if provider == "openai_image": return Common.failure("Imaginea salvată nu mai este disponibilă. Generează o imagine nouă.", "missing_artifact")
	var endpoint = str(job.get("endpoint", "/openapi/v2/text-to-3d")) + "/" if provider == "meshy" else "/tasks/"
	var response = await _cloud_request(profile, endpoint + str(job["external_id"]).uri_encode(), null, cancel)
	if not response.get("ok", false): return response
	var data: Dictionary = response["result"]
	var status = str(data.get("status", "")).to_lower()
	job["progress"] = clampi(int(data.get("progress", 0)), 0, 100)
	if data.has("credits_consumed"): job["credits_consumed"] = data["credits_consumed"]
	if status in ["failed", "canceled", "cancelled"]:
		job["status"] = "failed"
		var task_error: Variant = data.get("task_error", {})
		job["error"] = str(task_error.get("message", "Generarea a eșuat sau a fost anulată.") if task_error is Dictionary else "Generarea a eșuat sau a fost anulată.").left(1000)
		_save()
		return Common.failure(job["error"], "generation_failed")
	if status not in ["success", "succeeded"]:
		_save()
		return Common.success("")
	var url = str(data.get("model_urls", {}).get("glb", "")) if provider == "meshy" else str(data.get("output", {}).get("model_url" if job["kind"] == "mesh" else "generated_image_url", ""))
	if url.is_empty():
		job["status"] = "failed"
		job["error"] = "Generarea s-a încheiat fără fișierul PNG/GLB cerut."
		_save()
		return Common.failure(job["error"], "missing_artifact")
	var parsed = Common.parse_url(url, test_http)
	if not parsed.get("ok", false): return parsed
	var host = str(parsed["host"]).to_lower()
	var allowed = ["meshy.ai"] if provider == "meshy" else ["tripo3d.ai", "tripo3d.com"]
	var trusted = test_http and host == "127.0.0.1"
	for domain in allowed:
		if host == domain or host.ends_with("." + domain): trusted = true
	if not trusted: return Common.failure("Domeniu de descărcare nerecunoscut pentru " + provider + ".")
	return Common.success(url)

func _tripo_upload(profile: Dictionary, path: String, cancel: Dictionary) -> Dictionary:
	var data_uri = _reference_data(path)
	if data_uri.is_empty(): return Common.failure("Imagine de referință invalidă.")
	var bytes = Marshalls.base64_to_raw(data_uri.get_slice(",", 1))
	var image = Image.new()
	if data_uri.begins_with("data:image/webp"):
		if image.load_webp_from_buffer(bytes) != OK: return Common.failure("Imagine WebP invalidă.")
		bytes = image.save_png_to_buffer()
	var boundary = "godotai" + Common.uid()
	var png = data_uri.begins_with("data:image/png") or data_uri.begins_with("data:image/webp")
	var body = ("--" + boundary + "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"reference." + ("png" if png else "jpg") + "\"\r\nContent-Type: image/" + ("png" if png else "jpeg") + "\r\n\r\n").to_utf8_buffer()
	body.append_array(bytes)
	body.append_array(("\r\n--" + boundary + "--\r\n").to_utf8_buffer())
	var result = await _cloud_request(profile, "/files", body, cancel, PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary]))
	if not result.get("ok", false): return result
	var token = str(result.get("result", {}).get("file_token", ""))
	return Common.success(token) if not token.is_empty() else Common.failure("Tripo nu a acceptat imaginea de referință.")
