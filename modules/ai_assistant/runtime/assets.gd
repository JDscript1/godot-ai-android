@tool
extends RefCounted

signal artifact_ready(job: Dictionary)

static var Common: GDScript
static var Transport: GDScript
static var AssetExports: GDScript
static var GenerationCatalog: GDScript
var transport: RefCounted
var vault: RefCounted
var owner: Node
var cache_directory = ""
var jobs: Array = []
var catalog_urls = {"runware": "https://runware.ai/docs/models/index.json"}
var catalog_prices: Dictionary = {}

# Endpoints are fixed in production. Tests can replace this instance map only.
var api_urls = {"runware": "https://api.runware.ai/v1", "meshy": "https://api.meshy.ai", "tripo": "https://openapi.tripo3d.ai/v3", "openai_image": "https://api.openai.com/v1"}
var test_http = false
const KINDS = ["runware", "comfy", "meshy", "tripo", "openai_image"]
const LABELS = ["Runware", "ComfyUI local", "Meshy", "Tripo", "OpenAI Images"]
const IMAGE_PURPOSES = ["generic", "reference_3d", "sprite", "texture", "background"]
const IMAGE_PURPOSE_LABELS = ["Imagine obișnuită", "Referință pentru 3D", "Sprite 2D", "Textură", "Fundal"]

func _init(node: Node = null, secret_store: RefCounted = null) -> void:
	owner = node
	transport = Transport.new(node)
	vault = secret_store

func configure(directory: String) -> void:
	cache_directory = directory
	DirAccess.make_dir_recursive_absolute(cache_directory)
	jobs = Common.read_json(cache_directory.path_join("jobs.json"), [])
	var saved_prices: Variant = Common.read_json(cache_directory.path_join("catalog-prices.json"), {})
	catalog_prices = saved_prices if saved_prices is Dictionary else {}
	var interrupted = false
	for job in jobs:
		if job.get("status") == "submitting":
			job["status"] = "submission_unknown"
			job["error"] = "Trimitere întreruptă înainte de confirmare. Verifică sarcina existentă la furnizor înainte de o generare nouă."
			interrupted = true
	if interrupted: _save()

func definitions() -> Array:
	return [
		Common.tool("asset_export", "Export a completed 3D job into its named project folder. GLB is the immutable original; glTF is a ZIP with dependencies; OBJ/STL/PLY are static geometry only. FBX, USDZ, 3MF and Meshy BLEND use explicit provider conversion and may consume credits. Resume with the same job and format to avoid duplicate conversions. If a submission response was lost, obtain the existing conversion task_id from the user/provider dashboard to recover; never invent an ID or resubmit blindly. Never overwrite project files.", {"job": Common.string_field(), "task_id": Common.string_field(), "format": {"type": "string", "enum": ["glb", "gltf", "fbx", "obj", "stl", "ply", "usdz", "blend", "3mf"]}}, ["job", "format"], "external"),
		Common.tool("asset_generate", "Generate an image or GLB with a saved profile. For images always specify purpose: reference_3d for an isolated reconstruction reference, sprite for a 2D game asset, texture for a tileable surface, background for scenery, generic for an illustration. reference_3d and sprite default to transparent; override background only for an explicit user requirement. Inspect quality.ready_for_use after asset_wait: PNG alone does not prove transparency. Use asset_remove_background on an opaque cutout instead of generating it again. Cloud generation consumes credits. Originals are auto-imported into named folders. Keep arguments and variant unchanged on retries; a new variant requires an explicit user request.", {"profile": Common.string_field(), "prompt": Common.string_field(), "purpose": {"type": "string", "enum": IMAGE_PURPOSES}, "background": {"type": "string", "enum": ["auto", "transparent", "opaque"]}, "reference": Common.string_field(), "variant": Common.string_field()}, ["profile", "prompt"], "external"),
		Common.tool("asset_remove_background", "Remove an existing image's background through a saved Runware profile. Uses provider credits, preserves the original, and creates a separate PNG job. Wait with asset_wait and inspect quality.ready_for_use. Reuse the same reference on retries; never generate the source again merely to remove its background.", {"profile": Common.string_field(), "reference": Common.string_field(), "purpose": {"type": "string", "enum": ["reference_3d", "sprite", "generic"]}}, ["profile", "reference"], "external"),
		Common.tool("asset_status", "Refresh an existing generation job and download its completed result.", {"job": Common.string_field()}, ["job"]),
		Common.tool("asset_wait", "Wait for a generation job without consuming repeated model turns. Cancellable; defaults to 300 seconds, maximum 600. Returns processing if the deadline expires.", {"job": Common.string_field(), "max_seconds": {"type": "integer"}}, ["job"]),
		Common.tool("asset_import", "Import a validated generated artifact into a dedicated named folder under res:// without overwriting existing files.", {"job": Common.string_field(), "directory": Common.string_field()}, ["job", "directory"], "write")]

static func generation_contract(profile: Dictionary, prompt: String, options: Dictionary = {}) -> Dictionary:
	var purpose = str(options.get("purpose", profile.get("purpose", "generic")))
	var background = str(options.get("background", profile.get("background", "auto")))
	if purpose not in IMAGE_PURPOSES or background not in ["auto", "transparent", "opaque"]: return Common.failure("Utilizare sau fundal de imagine invalid.", "invalid_generation_options")
	if profile.get("asset_kind", "image") == "mesh":
		if purpose != "generic" or background != "auto": return Common.failure("Scopul imaginii și fundalul se aplică profilului de imagini, nu mesh-ului.", "image_profile_required")
		return Common.success({"purpose": "mesh", "background": "none", "generation_prompt": prompt})
	if background == "auto":
		if purpose in ["reference_3d", "sprite"]: background = "transparent"
		elif purpose in ["texture", "background"]: background = "opaque"
	var rules = ""
	match purpose:
		"reference_3d": rules = "Image for 3D reconstruction: one isolated complete subject, centered with padding, all parts visible, readable volume, a clear three-quarter view unless a different view was requested. No scenery, floor, pedestal, cast shadow, labels, text, watermark, collage or multiple views unless explicitly requested. Preserve the requested style and object details."
		"sprite": rules = "2D game sprite: preserve the requested art style, camera direction and framing; clean readable silhouette and consistent scale. Follow exactly the requested frame count and sheet layout, if any. No scene, floor, pedestal, cast shadow, labels or watermark. Do not turn the sprite into a 3D reconstruction reference."
		"texture": rules = "Game surface texture: flat orthographic material surface, seamless and tileable in both directions unless requested otherwise. No staged object, perspective, scene, borders, labels or watermark."
		"background": rules = "Game background or scenery: complete composition suitable for the requested scene. Preserve the environment and requested aspect ratio; do not isolate or cut out the scene as an object. No unrequested text or watermark."
	if background == "transparent": rules += " Output a transparent PNG with real alpha around the subject. No colored backdrop, no painted checkerboard, no fake transparency."
	elif background == "opaque": rules += " Output an opaque image." + (" Use a plain neutral backdrop behind the isolated subject." if purpose in ["reference_3d", "sprite"] else "")
	return Common.success({"purpose": purpose, "background": background, "generation_prompt": prompt + ("\n\nAsset requirements: " + rules.strip_edges() if not rules.is_empty() else "")})

static func image_quality(path: String, expected: String) -> Dictionary:
	var image = Image.load_from_file(path)
	if image == null: return {"ready_for_use": false, "warning": "Imaginea nu poate fi citită."}
	var transparent = image.detect_alpha() != Image.ALPHA_NONE
	var empty = image.is_invisible()
	var ready = not empty and (transparent if expected == "transparent" else (not transparent if expected == "opaque" else true))
	var warning = ""
	if empty: warning = "Imaginea este complet transparentă; nu există un subiect vizibil."
	elif not ready: warning = "Lipsește transparența reală. Elimină fundalul imaginii existente înainte de utilizare; nu regenera automat." if expected == "transparent" else "Imaginea conține transparență, dar a fost cerut un rezultat opac."
	return {"ready_for_use": ready, "background_expected": expected, "has_transparency": transparent, "empty": empty, "warning": warning}

func verify_key(profile: Dictionary, cancel: Dictionary, key: String = "") -> Dictionary:
	if str(profile.get("kind", "")) == "runware":
		if _headers(profile, key).is_empty(): return Common.failure("Adaugă o cheie Runware.", "missing_credentials")
		var response = await _runware(profile, [{"taskType": "ping", "ping": true}], cancel, key)
		if not response.get("ok", false): return response
		return Common.success({"credential_verified": true}) if response.get("result", []).any(func(item: Variant) -> bool: return item is Dictionary and item.get("pong", false)) else Common.failure("Runware nu a confirmat cheia.")
	var checked = await models(profile, cancel, key)
	if not checked.get("ok", false): return checked
	return Common.success({"credential_verified": bool(checked.get("credential_verified", false))})

func catalog(profile: Dictionary, cancel: Dictionary, key: String = "", update: Callable = Callable()) -> Dictionary:
	# The draft key is held in memory, never put in a profile or sent to public docs.
	if profile.get("kind") == "runware":
		var verified = await verify_key(profile, cancel, key)
		if not verified.get("ok", false): return verified
	var forward = func(event: Dictionary) -> void:
		if profile.get("kind") == "runware" and event.has("result"): event["credential_verified"] = true
		if update.is_valid(): update.call(event)
	var result = await models(profile, cancel, key, forward)
	if result.get("ok", false) and profile.get("kind") == "runware": result["credential_verified"] = true
	return result

func models(profile: Dictionary, cancel: Dictionary, key: String = "", update: Callable = Callable()) -> Dictionary:
	var provider = str(profile.get("kind", "runware"))
	var kind = str(profile.get("asset_kind", "image"))
	if provider in ["meshy", "tripo", "openai_image"]:
		var endpoint = "/openapi/v1/balance" if provider == "meshy" else ("/account/balance" if provider == "tripo" else "/models")
		var checked = await _cloud_request(profile, endpoint, null, cancel, [], key)
		if not checked.get("ok", false): return checked
		var available = GenerationCatalog.presets(provider, kind)
		if provider == "openai_image" and kind == "image":
			for model in checked.get("result", {}).get("data", []):
				if not model is Dictionary: continue
				var id = str(model.get("id", ""))
				if not id.begins_with("gpt-image-") or id == "gpt-image-1" or id.begins_with("gpt-image-1-20"): continue
				available.append({"id": id, "name": str(model.get("name", id)), "price": GenerationCatalog.openai_price(id)})
		var result = {"ok": true, "result": available, "credential_verified": true, "source": "documented_presets" if provider != "openai_image" else "account_catalog"}
		if update.is_valid(): update.call(result)
		return result
	if provider == "comfy":
		return await transport.request(str(profile["url"]).trim_suffix("/") + "/object_info", HTTPClient.METHOD_GET, _headers(profile, key), null, _options(profile, cancel))
	if provider != "runware": return Common.failure("Furnizor de generare necunoscut.")
	var result = await _catalog_document(str(catalog_urls["runware"]), cancel)
	if not result.get("ok", false): return result
	if not result.get("json") is Array: return Common.failure("Catalogul public Runware nu este disponibil.")
	var available = GenerationCatalog.runware_models(result["json"], kind)
	var queue: Array = []
	for model in available:
		var cached_value: Variant = catalog_prices.get(model["id"], {})
		var cached: Dictionary = cached_value if cached_value is Dictionary else {}
		var age = Time.get_unix_time_from_system() - float(cached.get("fetched_at", 0))
		if not cached.is_empty() and age >= 0 and age < 86400:
			model["price"] = cached
		else: queue.append(model)
	var response = {"ok": true, "result": available, "source": "public_catalog", "credential_verified": false}
	if update.is_valid(): update.call(response)
	var state = {"workers": 4}
	for worker in range(4): _catalog_price_worker(queue, cancel, update, state)
	while state["workers"] > 0 and is_instance_valid(owner) and owner.is_inside_tree(): await owner.get_tree().process_frame
	if not cache_directory.is_empty(): Common.atomic_json(cache_directory.path_join("catalog-prices.json"), catalog_prices)
	return Common.failure("Încărcarea catalogului a fost oprită.", "cancelled") if cancel.get("cancelled", false) else response

func _catalog_document(url: String, cancel: Dictionary) -> Dictionary:
	var trusted = url.begins_with("https://runware.ai/docs/models/") and not ".." in url and not "?" in url and not "#" in url
	if not trusted and not (test_http and url.begins_with(str(catalog_urls["runware"]).get_base_dir() + "/")): return Common.failure("Adresă de catalog nepermisă.", "untrusted_catalog")
	return await transport.request(url, HTTPClient.METHOD_GET, ["Accept: application/json", "User-Agent: Mozilla/5.0 Godot-AI-Catalog/1.0"], null, {"cancel": cancel, "allow_http": test_http, "timeout": 15, "connect_timeout": 5, "max_bytes": 2097152})

func _catalog_price_worker(queue: Array, cancel: Dictionary, update: Callable, state: Dictionary) -> void:
	while not queue.is_empty() and not cancel.get("cancelled", false):
		var model: Dictionary = queue.pop_front()
		var response = await _catalog_document(str(model.get("schema", "")), cancel)
		if cancel.get("cancelled", false): break
		var value = GenerationCatalog.runware_price(response["json"], str(model.get("asset_kind", ""))) if response.get("ok", false) and response.get("json") is Dictionary else {"basis": "unknown", "source": GenerationCatalog.SOURCES["runware"]}
		value["fetched_at"] = Time.get_unix_time_from_system()
		if value.get("basis") != "unknown": catalog_prices[model["id"]] = value
		model["price"] = value
		if update.is_valid(): update.call({"model": model})
	state["workers"] -= 1

func submit(profile: Dictionary, prompt: String, reference: String, cancel: Dictionary, options: Dictionary = {}) -> Dictionary:
	if cancel.get("cancelled", false): return Common.failure("Generarea nu a fost trimisă.", "cancelled")
	var checked = generation_contract(profile, prompt, options)
	if not checked.get("ok", false): return checked
	var contract: Dictionary = checked["result"]
	if profile.get("asset_kind") == "mesh" and not reference.is_empty():
		var reference_path = Common.project_path(reference)
		for source in jobs:
			if reference == str(source.get("file", "")) or (not reference_path.is_empty() and reference_path == Common.project_path(str(source.get("imported_path", "")))):
				if source.get("kind") == "image" and not image_quality(reference_path if not reference_path.is_empty() else reference, str(source.get("background", "auto"))).get("ready_for_use", false):
					return Common.failure("Referința generată nu respectă fundalul cerut. Corectează imaginea existentă înainte de conversia 3D.", "reference_needs_review")
	if str(profile.get("kind", "runware")) in ["meshy", "tripo", "openai_image"]: return await _cloud_submit(profile, prompt, reference, cancel, contract)
	var id = Common.uid()
	var kind = str(profile.get("asset_kind", "image"))
	var job = {"id": id, "profile_id": profile["id"], "kind": kind, "provider": profile.get("kind", "runware"), "external_id": id, "status": "submitting", "created": Time.get_datetime_string_from_system(true), "prompt": prompt, "destination": profile.get("destination", "res://ai_assets"), "file": ""}
	job.merge(contract)
	if profile.get("kind") == "comfy": job["external_id"] = ""
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
			workflow[prompt_node]["inputs"][prompt_input] = contract["generation_prompt"]
		elif contract["purpose"] != "generic" and kind == "image": return Common.failure("Configurează nodul de prompt pentru a aplica regulile imaginii în workflow.", "prompt_binding_required")
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
		if not _begin_submission(job): return Common.failure("Nu pot salva sarcina înainte de trimitere.", "checkpoint_failed")
		result = await transport.request(str(profile["url"]).trim_suffix("/") + "/prompt", HTTPClient.METHOD_POST, _headers(profile), {"prompt": workflow, "client_id": id}, _options(profile, cancel))
		if not result.get("ok", false): return _submission_failed(job, result)
		if not result.get("json") is Dictionary or not result["json"].has("prompt_id"): return _submission_failed(job, Common.failure("ComfyUI nu a confirmat identificatorul sarcinii."))
		job["external_id"] = result["json"]["prompt_id"]
		job["output_node"] = output_node
	else:
		var reference_data = _reference_data(reference) if not reference.is_empty() else ""
		if not reference.is_empty() and reference_data.is_empty(): return Common.failure("Imagine de referință invalidă.")
		var built = build_runware_task(profile, str(contract["generation_prompt"]), reference_data, id)
		if not built.get("ok", false): return built
		if not _begin_submission(job): return Common.failure("Nu pot salva sarcina înainte de trimitere.", "checkpoint_failed")
		result = await _runware(profile, [built["result"]], cancel)
		if not result.get("ok", false): return _submission_failed(job, result)
	job["status"] = "processing"
	if not _save(): return Common.failure("Cererea a fost trimisă, dar confirmarea nu a putut fi salvată. Verifică sarcina existentă înainte de a genera din nou.", "checkpoint_failed").merged({"result": job.duplicate(true)})
	return Common.success(job.duplicate(true))

func remove_background(profile: Dictionary, reference: String, cancel: Dictionary, purpose: String = "generic") -> Dictionary:
	if cancel.get("cancelled", false): return Common.failure("Operația nu a fost trimisă.", "cancelled")
	if profile.get("kind") != "runware": return Common.failure("Eliminarea fundalului necesită un profil Runware salvat.", "unsupported_provider")
	if _headers(profile).is_empty(): return Common.failure("Adaugă cheia Runware.", "missing_credentials")
	if purpose not in ["reference_3d", "sprite", "generic"]: return Common.failure("Utilizare de imagine invalidă.")
	var source_path = reference
	var subject = reference.get_file().get_basename()
	for source in jobs:
		if reference in [str(source.get("file", "")), str(source.get("imported_path", ""))]:
			subject = str(source.get("prompt", subject))
			if source.get("file") == reference and not str(source.get("imported_path", "")).is_empty(): source_path = str(source["imported_path"])
	var data = _reference_data(source_path)
	if data.is_empty(): return Common.failure("Imagine de referință invalidă.")
	var source_hash = FileAccess.get_sha256(source_path)
	for existing in jobs:
		if existing.get("operation") == "remove_background" and existing.get("profile_id") == profile["id"] and existing.get("source_sha256") == source_hash and existing.get("purpose") == purpose and existing.get("status") != "failed":
			if existing.get("status") in ["submitting", "submission_unknown"]: return Common.failure("Eliminarea fundalului a fost deja trimisă, fără confirmare. Verifică sarcina existentă.", "submission_unknown").merged({"result": existing.duplicate(true)})
			return Common.success(existing.duplicate(true))
	var id = Common.uid()
	var job = {"id": id, "profile_id": profile["id"], "kind": "image", "provider": "runware", "external_id": id, "status": "submitting", "created": Time.get_datetime_string_from_system(true), "prompt": subject + " cutout", "purpose": purpose, "background": "transparent", "operation": "remove_background", "source": reference, "source_sha256": source_hash, "destination": profile.get("destination", "res://ai_assets"), "file": ""}
	var task = {"taskType": "removeBackground", "taskUUID": id, "model": "runware:109@1", "deliveryMethod": "async", "outputFormat": "PNG", "includeCost": true, "inputs": {"image": data}, "settings": {"alphaMatting": true, "postProcessMask": true, "returnOnlyMask": false, "rgba": [255, 255, 255, 0]}}
	if not _begin_submission(job): return Common.failure("Nu pot salva sarcina înainte de trimitere.", "checkpoint_failed")
	var result = await _runware(profile, [task], cancel)
	if not result.get("ok", false): return _submission_failed(job, result)
	job["status"] = "processing"
	if not _save(): return Common.failure("Cererea a fost trimisă, dar confirmarea nu a putut fi salvată.", "checkpoint_failed").merged({"result": job.duplicate(true)})
	return Common.success(job.duplicate(true))

func _begin_submission(job: Dictionary) -> bool:
	jobs.append(job)
	if _save(): return true
	jobs.erase(job)
	return false

func _submission_failed(job: Dictionary, failure: Dictionary) -> Dictionary:
	var rejected = int(failure.get("status", 0)) in [400, 401, 403, 404, 405, 413, 415, 422, 429]
	rejected = rejected or str(failure.get("code", "")) in ["generation_failed", "missing_credentials"]
	job["status"] = "failed" if rejected else "submission_unknown"
	job["error"] = str(failure.get("error", "Confirmarea furnizorului lipsește.")).left(1600)
	_save()
	if rejected: return failure.merged({"result": job.duplicate(true)})
	return Common.failure("Trimitere neconfirmată. Sarcina poate exista la furnizor; verifică rezultatul existent înainte de o generare nouă.", "submission_unknown").merged({"result": job.duplicate(true)})

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
	if str(job.get("external_id", "")).is_empty(): return Common.failure("Trimitere neconfirmată, fără ID de la furnizor. Verifică istoricul furnizorului înainte de o generare nouă.", "submission_unknown").merged({"result": job.duplicate(true)})
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
			var parsed = Common.parse_url(download_url, test_http)
			if not parsed.get("ok", false) or not (str(parsed["host"]) == "runware.ai" or str(parsed["host"]).ends_with(".runware.ai") or (test_http and str(parsed["host"]) == "127.0.0.1")): return Common.failure("Destinație de descărcare Runware nevalidată.")
	if download_url.is_empty(): return Common.success(job.duplicate(true))
	var extension = ".glb" if job["kind"] == "mesh" else ".png"
	var temporary = cache_directory.path_join(id + extension + ".part")
	var options = _options(profile, cancel)
	if job["provider"] in ["meshy", "tripo", "runware"]: options["allow_http"] = test_http
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
	if job["kind"] == "image": job["quality"] = image_quality(path, str(job.get("background", "auto")))
	var imported = import_job(str(job["id"]), str(job.get("destination", "res://ai_assets")))
	if not imported.get("ok", false): job["import_error"] = str(imported.get("error", "Import automat eșuat."))
	_save()
	artifact_ready.emit(job.duplicate(true))
	return Common.success(job.duplicate(true))

func import_job(id: String, directory: String) -> Dictionary:
	var job = find_job(id)
	if job.is_empty() or job.get("status") != "completed": return Common.failure("Generarea nu este finalizată.")
	if not str(job.get("imported_path", "")).is_empty() and FileAccess.file_exists(str(job["imported_path"])): return Common.success({"path": job["imported_path"], "import_requested": false})
	var target = Common.project_path(directory)
	if target.is_empty(): return Common.failure("Alege o destinație din res://.")
	var validation = validate_artifact(str(job["file"]), str(job["kind"]))
	if not validation.get("ok", false): return validation
	var subject = asset_slug(str(job.get("prompt", "")))
	var folder = target.path_join(subject + "_" + id.left(8))
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return Common.failure("Nu pot crea destinația.")
	var extension = ".glb" if job["kind"] == "mesh" else ".png"
	var path = folder.path_join(subject + extension)
	if FileAccess.file_exists(path): return Common.failure("Fișierul există deja; importul nu îl suprascrie.")
	var error = DirAccess.copy_absolute(str(job["file"]), ProjectSettings.globalize_path(path))
	if error != OK: return Common.failure(error_string(error))
	if Engine.is_editor_hint(): EditorInterface.get_resource_filesystem().scan_sources()
	job["imported_path"] = path
	_save()
	return Common.success({"path": path, "import_requested": true})

static func asset_slug(prompt: String) -> String:
	var normalized = prompt.to_lower().strip_edges().get_slice("\n", 0)
	for pair in [["ă", "a"], ["â", "a"], ["î", "i"], ["ș", "s"], ["ţ", "t"], ["ț", "t"]]: normalized = normalized.replace(pair[0], pair[1])
	var result = ""
	for character in normalized:
		if character in "abcdefghijklmnopqrstuvwxyz0123456789": result += character
		elif not result.ends_with("-") and not result.is_empty(): result += "-"
		if result.length() >= 40: break
	result = result.trim_suffix("-")
	return result if not result.is_empty() else "resursa"

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
		if file.get_32() != 0x4E4F534A or length > file.get_length() - 20 or length > 8 * 1024 * 1024: return Common.failure("GLB fără document JSON valid.")
		var document: Variant = Common.parse_json(file.get_buffer(length).get_string_from_utf8())
		if not document is Dictionary or not document.get("asset") is Dictionary or str(document["asset"].get("version", "")) != "2.0": return Common.failure("Document glTF invalid.")
		if not document.get("images", []) is Array or not document.get("buffers", []) is Array: return Common.failure("Liste de dependențe glTF invalide.")
		for image in document.get("images", []):
			if not image is Dictionary: return Common.failure("Imagine glTF invalidă.")
			if image.has("uri") and not str(image["uri"]).begins_with("data:"): return Common.failure("GLB conține imagini externe; este necesar un fișier autonom.")
		for buffer in document.get("buffers", []):
			if not buffer is Dictionary: return Common.failure("Buffer glTF invalid.")
			if buffer.has("uri") and not str(buffer["uri"]).begins_with("data:"): return Common.failure("GLB conține buffere externe.")
	else:
		file.seek(0)
		if file.get_buffer(8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]): return Common.failure("Rezultatul nu este PNG.")
		var image = Image.new()
		file.seek(0)
		if image.load_png_from_buffer(file.get_buffer(file.get_length())) != OK or image.is_empty(): return Common.failure("Imagine PNG coruptă.")
	return Common.success()

func _headers(profile: Dictionary, key: String = "") -> PackedStringArray:
	var secret = key if not key.is_empty() else (vault.read(str(profile.get("credential_id", profile["id"]))) if vault != null else "")
	return PackedStringArray(["Authorization: Bearer " + secret]) if not secret.is_empty() else PackedStringArray()

func _options(profile: Dictionary, cancel: Dictionary) -> Dictionary:
	return {"allow_http": profile.get("allow_http", false), "cancel": cancel}

func _runware(profile: Dictionary, tasks: Array, cancel: Dictionary, key: String = "") -> Dictionary:
	var result = await transport.request(str(api_urls["runware"]), HTTPClient.METHOD_POST, _headers(profile, key), tasks, {"cancel": cancel, "allow_http": test_http})
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

func _save() -> bool:
	return Common.atomic_json(cache_directory.path_join("jobs.json"), jobs) == OK

# Native REST adapters. No shell, SDK or companion process is required.
static func cloud_payload(profile: Dictionary, prompt: String, reference: String = "") -> Dictionary:
	var provider = str(profile.get("kind", ""))
	var kind = str(profile.get("asset_kind", "image"))
	var model = str(profile.get("model", "")).strip_edges()
	var body = {}
	var endpoint = ""
	match provider:
		"meshy":
			if kind == "image":
				if not reference.is_empty(): return Common.failure("Profilul Meshy de imagini generează din text în acest adaptor.")
				endpoint = "/openapi/v1/text-to-image"
				body = {"ai_model": model if not model.is_empty() else "nano-banana-2", "prompt": prompt, "aspect_ratio": "1:1"}
			else:
				endpoint = "/openapi/v2/text-to-3d" if reference.is_empty() else "/openapi/v1/image-to-3d"
				body = {"mode": "preview", "prompt": prompt, "target_formats": ["glb"]} if reference.is_empty() else {"image_url": reference, "should_texture": true, "enable_pbr": true, "target_formats": ["glb"]}
				if model.begins_with("meshy-t"): body["model_type"] = "smart-topology"
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

func _cloud_request(profile: Dictionary, endpoint: String, body: Variant, cancel: Dictionary, extra_headers: PackedStringArray = [], key: String = "") -> Dictionary:
	var provider = str(profile.get("kind", ""))
	if not api_urls.has(provider): return Common.failure("Furnizor de generare necunoscut.")
	if _headers(profile, key).is_empty(): return Common.failure("Adaugă cheia API pentru acest profil.", "missing_credentials")
	var options = {"cancel": cancel, "allow_http": test_http, "timeout": 240, "max_bytes": Common.MAX_ASSET_BYTES}
	var headers = _headers(profile, key)
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

func _cloud_submit(profile: Dictionary, prompt: String, reference: String, cancel: Dictionary, contract: Dictionary = {}) -> Dictionary:
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
	var built = cloud_payload(profile, str(contract.get("generation_prompt", prompt)), reference_value)
	if not built.get("ok", false): return built
	var id = Common.uid()
	var job = {"id": id, "profile_id": profile["id"], "kind": profile.get("asset_kind", "image"), "provider": provider, "external_id": "", "status": "submitting", "created": Time.get_datetime_string_from_system(true), "prompt": prompt, "destination": profile.get("destination", "res://ai_assets"), "file": "", "endpoint": built["result"]["endpoint"]}
	job.merge(contract)
	if not _begin_submission(job): return Common.failure("Nu pot salva sarcina înainte de trimitere.", "checkpoint_failed")
	var result = await _cloud_request(profile, str(built["result"]["endpoint"]), built["result"]["body"], cancel)
	if not result.get("ok", false): return _submission_failed(job, result)
	var data: Dictionary = result["result"]
	if provider == "openai_image":
		var images: Variant = data.get("data", [])
		if not images is Array or images.is_empty() or not images[0] is Dictionary: return _submission_failed(job, Common.failure("OpenAI nu a returnat o imagine.", "missing_artifact"))
		var bytes = Marshalls.base64_to_raw(str(images[0].get("b64_json", "")))
		if bytes.is_empty() or bytes.size() > Common.MAX_ASSET_BYTES: return _submission_failed(job, Common.failure("Rezultat imagine lipsă sau prea mare."))
		var temporary = cache_directory.path_join(id + ".png.part")
		var file = FileAccess.open(temporary, FileAccess.WRITE)
		if file == null: return _submission_failed(job, Common.failure("Nu pot păstra imaginea generată."))
		file.store_buffer(bytes)
		file.close()
		var finished = _finish_download(job, temporary)
		if not finished.get("ok", false):
			job["status"] = "failed"
			job["error"] = finished.get("error", "Imagine invalidă.")
			_save()
		return finished
	job["external_id"] = str(data.get("result", "")) if provider == "meshy" else str(data.get("task_id", ""))
	if str(job["external_id"]).is_empty(): return _submission_failed(job, Common.failure("Furnizorul nu a returnat identificatorul sarcinii."))
	job["status"] = "processing"
	if not _save(): return Common.failure("Cererea a fost trimisă, dar confirmarea nu a putut fi salvată.", "checkpoint_failed").merged({"result": job.duplicate(true)})
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
	if provider == "meshy" and job["kind"] == "image":
		var images: Variant = data.get("image_urls", [])
		url = str(images[0]) if images is Array and not images.is_empty() else ""
	if url.is_empty():
		job["status"] = "failed"
		job["error"] = "Generarea s-a încheiat fără fișierul PNG/GLB cerut."
		_save()
		return Common.failure(job["error"], "missing_artifact")
	if not trusted_download(url, provider): return Common.failure("Domeniu de descărcare nerecunoscut pentru " + provider + ".")
	return Common.success(url)

func trusted_download(url: String, provider: String) -> bool:
	var parsed = Common.parse_url(url, test_http)
	if not parsed.get("ok", false): return false
	var host = str(parsed["host"]).to_lower()
	if test_http and host == "127.0.0.1": return true
	for domain in (["meshy.ai"] if provider == "meshy" else ["tripo3d.ai", "tripo3d.com"]):
		if host == domain or host.ends_with("." + domain): return true
	return false

func export_job(id: String, profile: Dictionary, format: String, cancel: Dictionary, task_id: String = "") -> Dictionary:
	var job = find_job(id)
	if job.is_empty(): return Common.failure("Sarcină de generare inexistentă.")
	var result = await AssetExports.new(self).export_job(job, profile, format, cancel, task_id)
	if not result.get("ok", false) or result.get("result", {}).get("status") != "completed": return result
	var existing = str(job.get("exports", {}).get(format, {}).get("project_path", ""))
	if not existing.is_empty() and FileAccess.file_exists(existing):
		result["result"]["project_path"] = existing
		return result
	var imported = import_job(id, str(job.get("destination", "res://ai_assets")))
	if not imported.get("ok", false): return result
	if format == "glb":
		result["result"]["project_path"] = imported["result"]["path"]
		return result
	var source = str(result["result"].get("file", ""))
	var folder = str(imported["result"]["path"]).get_base_dir()
	var filename = asset_slug(str(job.get("prompt", ""))) + "_" + format + "." + source.get_extension()
	var destination = folder.path_join(filename)
	var suffix = 2
	while FileAccess.file_exists(destination) and FileAccess.get_sha256(destination) != FileAccess.get_sha256(source) and suffix < 1000:
		destination = folder.path_join(asset_slug(str(job.get("prompt", ""))) + "_" + format + "_" + str(suffix) + "." + source.get_extension())
		suffix += 1
	if FileAccess.file_exists(destination) and FileAccess.get_sha256(destination) != FileAccess.get_sha256(source): return Common.failure("Nu am găsit un nume liber pentru export.")
	if not FileAccess.file_exists(destination):
		var error = DirAccess.copy_absolute(source, ProjectSettings.globalize_path(destination))
		if error != OK: return Common.failure("Exportul este în cache, dar nu îl pot salva în proiect: " + error_string(error))
	if not job.has("exports"): job["exports"] = {}
	if not job["exports"].has(format): job["exports"][format] = {}
	job["exports"][format]["project_path"] = destination
	result["result"]["project_path"] = destination
	_save()
	if Engine.is_editor_hint(): EditorInterface.get_resource_filesystem().scan_sources()
	return result


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
