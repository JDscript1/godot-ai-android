@tool
extends RefCounted

const VERSION = "0.1.0"
const BUILTIN_PREFIX = "res://__godot_ai_builtin__/"
const MAX_ASSET_BYTES = 100 * 1024 * 1024
const MODES = ["Auto", "Default", "Plan"]
const MODE_IDS = [2, 4, 3]
const MODE_ICONS = ["Agent", "Chat", "Plan"]

static func uid() -> String:
	var bytes = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]

static func failure(message: String, code: String = "error") -> Dictionary:
	return {"ok": false, "error": message, "code": code}

static func success(value: Variant = null) -> Dictionary:
	return {"ok": true, "result": value}

static func schema(properties: Dictionary = {}, required: Array = []) -> Dictionary:
	return {"type": "object", "properties": properties, "required": required, "additionalProperties": false}

static func string_field(description: String = "") -> Dictionary:
	return {"type": "string", "description": description}

static func tool(name: String, description: String, properties: Dictionary, required: Array, risk: String = "read") -> Dictionary:
	return {"name": name, "description": description, "parameters": schema(properties, required), "risk": risk}

static func parse_url(raw: String, allow_http: bool = false) -> Dictionary:
	var expression = RegEx.new()
	expression.compile("^(https?)://(\\[[^\\]]+\\]|[^/:?#@\\s]+)(?::([0-9]+))?(/[^#]*|\\?[^#]*)?$")
	var match_result = expression.search(raw.strip_edges())
	if match_result == null or "\r" in raw or "\n" in raw:
		return failure("Adresa serverului nu este validă.", "invalid_url")
	var scheme = match_result.get_string(1)
	var host = match_result.get_string(2).trim_prefix("[").trim_suffix("]")
	if scheme == "http" and not allow_http:
		return failure("Activează explicit HTTP pentru această conexiune locală.", "http_not_enabled")
	var port_text = match_result.get_string(3)
	var port = int(port_text) if not port_text.is_empty() else (443 if scheme == "https" else 80)
	if port < 1 or port > 65535:
		return failure("Port invalid.", "invalid_url")
	var path = match_result.get_string(4)
	if path.is_empty(): path = "/"
	if not path.begins_with("/"): path = "/" + path
	return {"ok": true, "scheme": scheme, "host": host, "port": port, "path": path}

static func project_path(raw: String) -> String:
	if not raw.begins_with("res://") or "\\" in raw:
		return ""
	for component in raw.trim_prefix("res://").split("/"):
		if component in ["..", ".git", ".godot", "__godot_ai_builtin__"]:
			return ""
	var simplified = raw.simplify_path()
	if not simplified.begins_with("res://"): return ""
	# Resolve symlinks at every existing parent, including links to other project directories.
	var current = "res://"
	for component in simplified.trim_prefix("res://").split("/", false):
		var directory = DirAccess.open(current)
		if directory != null and directory.is_link(component): return ""
		current = current.path_join(component)
	return simplified

static func atomic_json(path: String, value: Variant) -> Error:
	var error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK: return error
	var temporary = path + "." + uid() + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	FileAccess.set_unix_permissions(temporary, 384)
	return DirAccess.rename_absolute(temporary, path)

static func read_json(path: String, fallback: Variant = {}) -> Variant:
	if not FileAccess.file_exists(path): return fallback
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 16 * 1024 * 1024: return fallback
	var value = parse_json(file.get_as_text())
	return fallback if value == null else value

static func json_safe(value: Variant, depth: int = 0) -> Variant:
	# A reflected method's arguments are nested beneath result/methods/args.
	if depth > 12: return "[depth limit]"
	if value is Dictionary:
		var output = {}
		for key in value:
			output[str(key)] = json_safe(value[key], depth + 1)
		return output
	if value is Array:
		var output = []
		for item in value.slice(0, 2000): output.append(json_safe(item, depth + 1))
		return output
	if value is Object: return {"class": value.get_class()}
	if value is Vector2: return {"$type": "Vector2", "value": [value.x, value.y]}
	if value is Vector3: return {"$type": "Vector3", "value": [value.x, value.y, value.z]}
	if value is Color: return {"$type": "Color", "value": [value.r, value.g, value.b, value.a]}
	if value is Quaternion: return {"$type": "Quaternion", "value": [value.x, value.y, value.z, value.w]}
	if typeof(value) in [TYPE_STRING_NAME, TYPE_NODE_PATH]: return str(value)
	if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]: return value
	return var_to_str(value)

static func parse_json(text: String) -> Variant:
	if text.is_empty(): return null
	var parser = JSON.new()
	return parser.data if parser.parse(text) == OK else null

static func contains_inline_secrets(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			var normalized = str(key).to_lower().replace("_", "").replace("-", "")
			if normalized in ["apikey", "accesstoken", "refreshtoken", "password", "authorization"] and value[key] is String and not str(value[key]).is_empty(): return true
			if contains_inline_secrets(value[key]): return true
	elif value is Array:
		for item in value:
			if contains_inline_secrets(item): return true
	return false

static func decode_variant(value: Variant) -> Variant:
	if value is Dictionary and value.has("$type"):
		var components = value.get("value", [])
		match str(value["$type"]):
			"PackedStringArray":
				if components is Array and components.all(func(item: Variant) -> bool: return item is String): return PackedStringArray(components)
			"PackedInt32Array", "PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array":
				if components is Array and components.all(func(item: Variant) -> bool: return item is int or (item is float and is_finite(item))):
					var packed_type = {"PackedInt32Array": TYPE_PACKED_INT32_ARRAY, "PackedInt64Array": TYPE_PACKED_INT64_ARRAY, "PackedFloat32Array": TYPE_PACKED_FLOAT32_ARRAY, "PackedFloat64Array": TYPE_PACKED_FLOAT64_ARRAY}[value["$type"]]
					if packed_type in [TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY] and not components.all(func(item: Variant) -> bool: return float(item) == floor(float(item))): return value
					return type_convert(components, packed_type)
			"Vector2":
				if components is Array and components.size() == 2: return Vector2(float(components[0]), float(components[1]))
			"Vector3":
				if components is Array and components.size() == 3: return Vector3(float(components[0]), float(components[1]), float(components[2]))
			"Color":
				if components is Array and components.size() == 4: return Color(float(components[0]), float(components[1]), float(components[2]), float(components[3]))
			"Quaternion":
				if components is Array and components.size() == 4: return Quaternion(float(components[0]), float(components[1]), float(components[2]), float(components[3]))
	if value is Array:
		var result = []
		for item in value: result.append(decode_variant(item))
		return result
	if value is Dictionary:
		var result = {}
		for key in value: result[key] = decode_variant(value[key])
		return result
	return value

static func redact(text: String, secrets: Array) -> String:
	var output = text
	for secret in secrets:
		if str(secret).length() >= 8: output = output.replace(str(secret), "[secret]")
	var expression = RegEx.new()
	expression.compile("(?i)(Bearer\\s+|(?:api[_-]?key|refresh_token|access_token)[\\\"\\s:=]+)[A-Za-z0-9_.+/=-]{8,}")
	return expression.sub(output, "$1[secret]", true)

static func work_mode_index(selection: Dictionary) -> int:
	if selection.has("work_mode"):
		var index = ["auto", "default", "plan"].find(str(selection["work_mode"]))
		return index if index >= 0 else 1
	# Older conversations stored only Auto=0 / Plan=1. Never restore Plan as Default.
	return 2 if int(selection.get("ui_mode", 0)) in [1, 2, 3] else 0
