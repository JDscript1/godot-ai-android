@tool
extends RefCounted
## Optional native HTTP integrations and desktop-only Blender process control.
static var Common: GDScript
static var Transport: GDScript
var owner: Node
var vault: RefCounted
var transport: RefCounted
var api_url = "https://api.github.com"
var test_http = false
var processes: Array = []

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
	var headers = PackedStringArray(["Accept: application/vnd.github+json", "X-GitHub-Api-Version: 2026-03-10", "User-Agent: Godot-AI-Editor"])
	var key = vault.read("integration_github")
	if not key.is_empty(): headers.append("Authorization: Bearer " + key)
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
