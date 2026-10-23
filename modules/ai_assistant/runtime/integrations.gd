@tool
extends RefCounted
## Optional native HTTP integrations and desktop-only Blender process control.
static var Common: GDScript
static var Transport: GDScript
const GITHUB_CLIENT_ID = "" # Set only to the public ID of this project's registered OAuth app.
var owner: Node
var vault: RefCounted
var transport: RefCounted
var api_url = "https://api.github.com"
var test_http = false
var processes: Array = []
var github_login_url = "https://github.com"
var github_flow: Dictionary = {}
var github_auth_generation = 0

func github_begin(client_id: String, private_repositories: bool = false) -> Dictionary:
	github_cancel()
	if client_id.strip_edges().is_empty(): return Common.failure("Configurează Client ID-ul aplicației OAuth GitHub.", "missing_client_id")
	var generation = github_auth_generation
	var body = "client_id=" + client_id.strip_edges().uri_encode() + "&scope=" + ("read:user " + ("repo" if private_repositories else "public_repo")).uri_encode()
	var response = await transport.request(github_login_url + "/login/device/code", HTTPClient.METHOD_POST, ["Accept: application/json", "Content-Type: application/x-www-form-urlencoded"], body, {"allow_http": test_http, "max_bytes": 16000, "timeout": 30})
	if generation != github_auth_generation: return Common.failure("Autentificare anulată.", "cancelled")
	var data: Variant = response.get("json")
	if not response.get("ok", false) or not data is Dictionary or str(data.get("device_code", "")).is_empty(): return Common.failure("GitHub nu a pornit autentificarea. Verifică Client ID-ul și activarea Device Flow.", "github_auth_error")
	# Only the public user code is exposed to the interface. Device code stays in memory.
	if str(data.get("verification_uri", "")) != "https://github.com/login/device": return Common.failure("Adresă de autentificare GitHub neașteptată.")
	github_flow = {"client_id": client_id.strip_edges(), "device_code": str(data["device_code"]), "interval": maxi(5, int(data.get("interval", 5))), "expires": Time.get_ticks_msec() + clampi(int(data.get("expires_in", 900)), 1, 1800) * 1000, "generation": generation}
	return Common.success({"user_code": str(data.get("user_code", "")), "verification_uri": "https://github.com/login/device"})

func github_poll(cancel: Dictionary) -> Dictionary:
	if github_flow.is_empty(): return Common.failure("Autentificare inactivă.", "cancelled")
	var flow = github_flow.duplicate(true)
	while not cancel.get("cancelled", false) and int(flow["generation"]) == github_auth_generation:
		var next_poll = Time.get_ticks_msec() + (20 if test_http else int(flow["interval"]) * 1000)
		while Time.get_ticks_msec() < next_poll:
			if cancel.get("cancelled", false) or int(flow["generation"]) != github_auth_generation: return Common.failure("Autentificare anulată.", "cancelled")
			if not is_instance_valid(owner) or not owner.is_inside_tree(): return Common.failure("Autentificare anulată.", "cancelled")
			await owner.get_tree().process_frame
		if Time.get_ticks_msec() >= int(flow["expires"]):
			github_cancel()
			return Common.failure("Cod expirat. Apasă din nou Sign in.", "expired_token")
		var body = "client_id=" + str(flow["client_id"]).uri_encode() + "&device_code=" + str(flow["device_code"]).uri_encode() + "&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"
		var response = await transport.request(github_login_url + "/login/oauth/access_token", HTTPClient.METHOD_POST, ["Accept: application/json", "Content-Type: application/x-www-form-urlencoded"], body, {"allow_http": test_http, "cancel": cancel, "max_bytes": 16000, "timeout": 30})
		if cancel.get("cancelled", false) or int(flow["generation"]) != github_auth_generation: return Common.failure("Autentificare anulată.", "cancelled")
		var data: Variant = response.get("json")
		if not response.get("ok", false) or not data is Dictionary: return Common.failure("Conexiunea de autentificare GitHub a eșuat.", "github_auth_error")
		var error = str(data.get("error", ""))
		if error == "authorization_pending": continue
		if error == "slow_down":
			flow["interval"] = int(flow["interval"]) + 5
			continue
		if not error.is_empty():
			github_cancel()
			return Common.failure("Autentificarea GitHub a fost refuzată sau a expirat. Reîncearcă Sign in.", error)
		var token = str(data.get("access_token", ""))
		if token.is_empty(): return Common.failure("GitHub nu a returnat un token.", "github_auth_error")
		var identity = await github_account(cancel, token)
		if cancel.get("cancelled", false) or int(flow["generation"]) != github_auth_generation: return Common.failure("Autentificare anulată.", "cancelled")
		if not identity.get("ok", false): return identity
		if not vault.store("integration_github", token): return Common.failure("Tokenul GitHub nu a putut fi salvat.", "vault_error")
		github_cancel()
		return identity
	github_cancel()
	return Common.failure("Autentificare anulată.", "cancelled")

func github_cancel() -> void:
	github_auth_generation += 1
	github_flow.clear()

func _github_headers(token: String = "") -> PackedStringArray:
	var headers = PackedStringArray(["Accept: application/vnd.github+json", "X-GitHub-Api-Version: 2026-03-10", "User-Agent: Godot-AI-Editor"])
	var key = token if not token.is_empty() else vault.read("integration_github")
	if not key.is_empty(): headers.append("Authorization: Bearer " + key)
	return headers

func github_account(cancel: Dictionary = {}, token: String = "") -> Dictionary:
	var response = await transport.request(api_url + "/user", HTTPClient.METHOD_GET, _github_headers(token), null, {"cancel": cancel, "allow_http": test_http, "max_bytes": 64000})
	var data: Variant = response.get("json")
	if not response.get("ok", false) or not data is Dictionary or str(data.get("login", "")).is_empty(): return Common.failure("Cont GitHub neverificat. Reautentifică-te.", "github_auth_error")
	return Common.success({"login": str(data["login"]), "name": str(data.get("name", "")), "id": int(data.get("id", 0))})

func github_repositories(page: int = 1, cancel: Dictionary = {}) -> Dictionary:
	if vault.read("integration_github").is_empty(): return Common.failure("Conectează contul GitHub.", "missing_credentials")
	var response = await transport.request(api_url + "/user/repos?sort=updated&per_page=30&page=" + str(clampi(page, 1, 100)), HTTPClient.METHOD_GET, _github_headers(), null, {"cancel": cancel, "allow_http": test_http, "max_bytes": 2 * 1024 * 1024})
	if not response.get("ok", false) or not response.get("json") is Array: return Common.failure("Lista de repository-uri nu este disponibilă.", "github_error")
	var result = []
	for item in response["json"]:
		if item is Dictionary and valid_repository(str(item.get("full_name", ""))): result.append({"full_name": str(item["full_name"]), "private": bool(item.get("private", false))})
	return Common.success(result)

func _init(node: Node = null, store: RefCounted = null) -> void:
	owner = node
	vault = store
	transport = Transport.new(node)

static func desktop_blender() -> bool:
	return not OS.has_feature("android") and OS.get_name() in ["Windows", "Linux"]

static func definitions(github: bool, blender: bool) -> Array:
	var result = []
	if github:
		result.append(Common.tool("github_read", "Inspect the configured GitHub repository: repository, branches, issues, pulls or a file/directory. No git CLI required. Lists are paginated, 30 per page.", {"resource": {"type": "string", "enum": ["repository", "branches", "issues", "pulls", "contents"]}, "path": Common.string_field(), "ref": Common.string_field(), "page": {"type": "integer", "minimum": 1, "maximum": 100}}, ["resource"]))
		result.append(Common.tool("github_create_issue", "Create an issue in the configured repository only when the user requested it. This publishes externally. Never put credentials or private project data into the issue.", {"title": Common.string_field(), "body": Common.string_field()}, ["title", "body"], "external"))
	if blender and desktop_blender():
		result.append(Common.tool("blender_run", "Run a saved project Python script in Blender background mode on Windows/Linux. Blender has desktop filesystem access. Inspect the script first, use explicit project output paths, then inspect/import the produced assets with Godot tools.", {"script": Common.string_field(), "blend": Common.string_field(), "seconds": {"type": "integer", "minimum": 1, "maximum": 600}}, ["script"], "external"))
	return result

static func valid_repository(value: String) -> bool:
	var pattern = RegEx.new()
	pattern.compile("^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$")
	return pattern.search(value) != null and value.get_slice("/", 1) not in [".", ".."]

func github_request(repository: String, args: Dictionary, cancel: Dictionary = {}, issue: bool = false) -> Dictionary:
	if not valid_repository(repository): return Common.failure("Repository invalid. Folosește proprietar/proiect.", "invalid_repository")
	var route = "/repos/" + repository
	var resource = str(args.get("resource", "repository"))
	var body: Variant = null
	if issue:
		var title = str(args.get("title", "")).strip_edges()
		if title.is_empty() or title.length() > 256 or str(args.get("body", "")).length() > 16000: return Common.failure("Issue invalid.")
		route += "/issues"
		body = {"title": title, "body": str(args.get("body", ""))}
	elif resource == "contents":
		var path = str(args.get("path", ""))
		if path.begins_with("/") or "\\" in path or ".." in path.split("/"): return Common.failure("Cale GitHub invalidă.", "invalid_path")
		var parts = []
		for part in path.split("/", false): parts.append(part.uri_encode())
		route += "/contents/" + "/".join(parts)
		if not str(args.get("ref", "")).is_empty(): route += "?ref=" + str(args["ref"]).uri_encode()
	elif resource in ["branches", "issues", "pulls"]:
		route += "/" + resource + "?per_page=30&page=" + str(clampi(int(args.get("page", 1)), 1, 100))
	elif resource != "repository": return Common.failure("Resursă GitHub invalidă.")
	var headers = _github_headers()
	var response = await transport.request(api_url + route, HTTPClient.METHOD_POST if issue else HTTPClient.METHOD_GET, headers, body, {"cancel": cancel, "allow_http": test_http, "max_bytes": 2 * 1024 * 1024})
	if not response.get("ok", false): return Common.failure(str(response.get("error", "GitHub indisponibil.")), "github_error")
	var value: Variant = response.get("json")
	if resource == "contents" and value is Dictionary and value.get("type") == "file":
		if value.get("encoding") != "base64" or int(value.get("size", 0)) > 256000: return Common.failure("Fișier prea mare sau codificare nesuportată.")
		value = {"path": value.get("path"), "sha": value.get("sha"), "text": Marshalls.base64_to_raw(str(value.get("content", "")).replace("\n", "")).get_string_from_utf8()}
	elif value is Array:
		value = value.slice(0, 30).map(func(item: Dictionary) -> Dictionary:
			var entry = {}
			for field in ["name", "path", "type", "sha", "number", "title", "state", "html_url"]:
				if item.has(field): entry[field] = item[field]
			return entry)
	elif value is Dictionary:
		var entry = {}
		for field in ["full_name", "description", "private", "default_branch", "html_url", "open_issues_count", "number", "title", "state", "permissions"]:
			if value.has(field): entry[field] = value[field]
		value = entry
	else: return Common.failure("Răspuns GitHub invalid.")
	return Common.success(value)

func stop() -> void:
	github_cancel()
	for pid in processes:
		if OS.is_process_running(pid): OS.kill(pid)
	processes.clear()

func blender(executable: String, args: Dictionary, cancel: Dictionary = {}, version: bool = false) -> Dictionary:
	if cancel.get("cancelled", false): return Common.failure("Blender oprit.", "cancelled")
	if not desktop_blender(): return Common.failure("Blender CLI este disponibil pe Windows și Linux.", "unsupported_platform")
	if executable.is_empty() or not executable.is_absolute_path() or not FileAccess.file_exists(executable): return Common.failure("Selectează executabilul Blender.", "missing_blender")
	var command = PackedStringArray(["--version"])
	if not version:
		var script = Common.project_path(str(args.get("script", "")))
		if script.is_empty() or script.get_extension().to_lower() != "py" or not FileAccess.file_exists(script): return Common.failure("Selectează un script Python din proiect.", "invalid_script")
		command = PackedStringArray(["--background", "--factory-startup", "--disable-autoexec"])
		if not str(args.get("blend", "")).is_empty():
			var blend = Common.project_path(str(args["blend"]))
			if blend.is_empty() or blend.get_extension().to_lower() != "blend" or not FileAccess.file_exists(blend): return Common.failure("Fișier .blend invalid.")
			command.append(ProjectSettings.globalize_path(blend))
		command.append_array(["--python-exit-code", "1", "--python", ProjectSettings.globalize_path(script)])
	var process = OS.execute_with_pipe(executable, command, false)
	if process.is_empty(): return Common.failure("Blender nu a putut porni.")
	var pid = int(process["pid"])
	processes.append(pid)
	var deadline = Time.get_ticks_msec() + (15 if version else clampi(int(args.get("seconds", 120)), 1, 600)) * 1000
	var output = PackedByteArray()
	var interrupted = ""
	while true:
		for key in ["stdio", "stderr"]:
			var chunk: PackedByteArray = process[key].get_buffer(4096)
			if output.size() < 64000: output.append_array(chunk.slice(0, 64000 - output.size()))
		if not OS.is_process_running(pid): break
		if cancel.get("cancelled", false) or not is_instance_valid(owner) or not owner.is_inside_tree(): interrupted = "cancelled"
		elif Time.get_ticks_msec() > deadline: interrupted = "timeout"
		if not interrupted.is_empty():
			OS.kill(pid)
			break
		await owner.get_tree().process_frame
	# Drain trailing data without blocking, including output after process exit.
	for key in ["stdio", "stderr"]:
		for attempt in range(16):
			var chunk: PackedByteArray = process[key].get_buffer(4096)
			if chunk.is_empty(): break
			if output.size() < 64000: output.append_array(chunk.slice(0, 64000 - output.size()))
		process[key].close()
	processes.erase(pid)
	if cancel.get("cancelled", false): interrupted = "cancelled"
	if not interrupted.is_empty(): return Common.failure("Blender oprit: " + interrupted, interrupted)
	var exit_code = OS.get_process_exit_code(pid)
	return Common.success({"exit_code": exit_code, "output": output.get_string_from_utf8()}) if exit_code == 0 else Common.failure("Blender: cod %s\n%s" % [exit_code, output.get_string_from_utf8()], "blender_error")
