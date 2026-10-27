@tool
extends RefCounted
## A per-run catalog. Deferred discovery cannot expose a tool outside this catalog.
static var Common: GDScript

const INITIAL = ["godot_project", "godot_files", "godot_read_file", "godot_read_range", "godot_search_code", "godot_scene_tree", "task_update", "plan_ask", "agent_wait", "agent_cancel", "playtest_observe", "playtest_state", "file_catalog", "file_observe", "file_preview"]
const SUPPORTED = ["$schema", "$id", "$defs", "definitions", "$ref", "title", "description", "default", "examples", "deprecated", "readOnly", "writeOnly", "format", "type", "enum", "const", "properties", "required", "additionalProperties", "items", "minItems", "maxItems", "uniqueItems", "minLength", "maxLength", "pattern", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "allOf", "anyOf", "oneOf", "not", "minProperties", "maxProperties"]
var catalog = {}
var loaded = {}
var error = ""
const FAMILIES = [
	["godot_create_scene", "godot_create_node", "godot_set", "godot_get", "godot_save_scene", "godot_open_scene", "godot_create_resource", "godot_attach_script", "godot_connect_signal"],
	["godot_write_file", "godot_apply_patch", "godot_script_diagnostics", "godot_run", "godot_stop", "godot_output", "godot_run_state"],
	["store_search", "store_describe", "store_install", "plugin_enable", "godot_output"]]

func _load(name: String) -> void:
	if not catalog.has(name): return
	loaded[name] = true
	for family in FAMILIES:
		if name in family:
			for member in family:
				if catalog.has(member): loaded[member] = true

func restore(messages: Array) -> void:
	# Restore schemas only from this conversation and only within the current allowed catalog.
	for message in messages:
		for call in message.get("tool_calls", []):
			var name = str(call.get("name", ""))
			if name == "tool_describe": _load(str(call.get("arguments", {}).get("name", "")))
			elif catalog.has(name): _load(name)
		if message.get("role") == "tool" and message.get("tool_name") in ["tool_search", "tool_describe"]:
			var response: Variant = Common.parse_json(str(message.get("content", "")))
			if not response is Dictionary or not response.get("ok", false): continue
			var found: Dictionary = response.get("result", {})
			if found.get("tool") is Dictionary: _load(str(found["tool"].get("name", "")))
			for tool in found.get("tools", []):
				if tool is Dictionary: _load(str(tool.get("name", "")))

func _init(definitions: Array = [], deferred: bool = false) -> void:
	for definition in definitions:
		if not definition is Dictionary or not definition.get("name") is String:
			error = "Definiție de instrument invalidă."
			return
		var name = str(definition["name"])
		if name.is_empty() or catalog.has(name) or name in ["tool_search", "tool_describe"]:
			error = "Nume de instrument lipsă, rezervat sau duplicat."
			return
		catalog[name] = definition.duplicate(true)
		if not deferred or name in INITIAL: loaded[name] = true
	if deferred:
		for definition in discovery_definitions():
			catalog[definition["name"]] = definition
			loaded[definition["name"]] = true

static func discovery_definitions() -> Array:
	return [Common.tool("tool_search", "Find and load tools for the next model request. Search English names/descriptions, e.g. patch script, material, animation or generation. Only permitted session tools are searchable.", {"query": Common.string_field(), "limit": {"type": "integer", "minimum": 1, "maximum": 10}, "offset": {"type": "integer", "minimum": 0, "maximum": 5000}}, ["query"]), Common.tool("tool_describe", "Read a tool's exact arguments and load it for the next model request. Never guess the arguments of a tool.", {"name": Common.string_field()}, ["name"])]

func active_definitions() -> Array:
	var result = []
	for name in catalog:
		if loaded.has(name): result.append(catalog[name])
	return result

func discover(name: String, args: Dictionary) -> Dictionary:
	if name == "tool_describe":
		var target = str(args.get("name", ""))
		if not catalog.has(target): return Common.failure("Instrument indisponibil în această sesiune.", "tool_unavailable")
		_load(target)
		return Common.success({"tool": catalog[target], "loaded": true})
	var query = str(args.get("query", "")).strip_edges().to_lower()
	var ranked = []
	for target in catalog:
		if target in ["tool_search", "tool_describe"]: continue
		var definition: Dictionary = catalog[target]
		var haystack = target.to_lower() + " " + str(definition.get("description", "")).to_lower()
		var score = 0
		for word in query.split(" ", false):
			if word in target.to_lower(): score += 8
			elif word in haystack: score += 1
		if query.is_empty() or score > 0: ranked.append({"name": target, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["name"] < b["name"] if a["score"] == b["score"] else a["score"] > b["score"])
	var offset = clampi(int(args.get("offset", 0)), 0, 5000)
	var limit = clampi(int(args.get("limit", 5)), 1, 10)
	var found = []
	for entry in ranked.slice(offset, offset + limit):
		_load(entry["name"])
		found.append(catalog[entry["name"]])
	return Common.success({"tools": found, "total": ranked.size(), "next_offset": offset + found.size() if offset + found.size() < ranked.size() else -1, "loaded": true})

static func validate(definition: Dictionary, args: Dictionary) -> Dictionary:
	var schema: Variant = definition.get("parameters", {})
	if not schema is Dictionary: return Common.failure("Schema instrumentului este invalidă.", "unsupported_schema")
	var unsupported = _schema_problem(schema, 0, schema)
	if not unsupported.is_empty(): return Common.failure(unsupported, "unsupported_schema")
	var problem = _validate(args, schema, schema, "$", 0)
	return Common.success() if problem.is_empty() else Common.failure(problem, "invalid_arguments")

static func _schema_problem(schema: Variant, depth: int, root: Dictionary) -> String:
	if depth > 24: return "Schema depășește limita de adâncime."
	if schema is bool: return ""
	if not schema is Dictionary: return "Schema trebuie să fie obiect sau boolean."
	for keyword in schema:
		if not keyword in SUPPORTED: return "Constrângere de schemă nesuportată: " + str(keyword)
	var children = []
	for keyword in ["properties", "$defs", "definitions"]:
		if not schema.has(keyword): continue
		if not schema[keyword] is Dictionary: return "Câmp de schemă invalid: " + keyword
		children.append_array(schema[keyword].values())
	for keyword in ["items", "additionalProperties", "not"]:
		if schema.has(keyword): children.append(schema[keyword])
	for keyword in ["allOf", "anyOf", "oneOf"]:
		if not schema.has(keyword): continue
		if not schema[keyword] is Array or schema[keyword].is_empty(): return "Schemă compusă invalidă: " + keyword
		children.append_array(schema[keyword])
	for child in children:
		var problem = _schema_problem(child, depth + 1, root)
		if not problem.is_empty(): return problem
	if schema.has("required"):
		if not schema["required"] is Array: return "Câmpul required trebuie să fie listă."
		for key in schema["required"]:
			if not key is String: return "Nume invalid în required."
	if schema.has("enum") and not schema["enum"] is Array: return "Câmpul enum trebuie să fie listă."
	for keyword in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"]:
		if schema.has(keyword) and not (schema[keyword] is int or schema[keyword] is float): return "Limită numerică invalidă: " + keyword
	for keyword in ["minItems", "maxItems", "minLength", "maxLength", "minProperties", "maxProperties"]:
		if schema.has(keyword) and (not (schema[keyword] is int or schema[keyword] is float) or schema[keyword] < 0 or schema[keyword] != floor(schema[keyword])): return "Limită întreagă invalidă: " + keyword
	for keyword in ["pattern", "$ref"]:
		if schema.has(keyword) and not schema[keyword] is String: return "Text de schemă invalid: " + keyword
	if schema.has("$ref"):
		if not str(schema["$ref"]).begins_with("#/"): return "Referințele de schemă externe nu sunt suportate."
		var target: Variant = root
		for key in str(schema["$ref"]).trim_prefix("#/").split("/"):
			var decoded = key.replace("~1", "/").replace("~0", "~")
			if not target is Dictionary or not target.has(decoded): return "Referință de schemă invalidă."
			target = target[decoded]
		var problem = _schema_problem(target, depth + 1, root)
		if not problem.is_empty(): return problem
	if schema.has("type"):
		var types: Array = schema["type"] if schema["type"] is Array else [schema["type"]]
		if types.is_empty(): return "Lista tipurilor nu poate fi goală."
		for kind in types:
			if not kind is String or kind not in ["object", "array", "string", "boolean", "null", "number", "integer"]: return "Tip de schemă invalid."
	if schema.has("uniqueItems") and not schema["uniqueItems"] is bool: return "uniqueItems trebuie să fie boolean."
	return ""

static func _validate(value: Variant, schema: Variant, root: Dictionary, path: String, depth: int) -> String:
	if depth > 24: return path + ": schema depășește limita de adâncime."
	if schema is bool: return "" if schema else path + ": valoare nepermisă."
	if not schema is Dictionary: return path + ": schemă invalidă."
	# This is an explicit JSON Schema subset. Unsupported constraints fail closed.
	for keyword in schema:
		if not keyword in SUPPORTED: return path + ": constrângere de schemă nesuportată: " + str(keyword)
	if schema.has("$ref"):
		var reference = str(schema["$ref"])
		if not reference.begins_with("#/"): return path + ": referințele externe nu sunt suportate."
		var target: Variant = root
		for key in reference.trim_prefix("#/").split("/"):
			var decoded = key.replace("~1", "/").replace("~0", "~")
			if not target is Dictionary or not target.has(decoded): return path + ": referință de schemă invalidă."
			target = target[decoded]
		var problem = _validate(value, target, root, path, depth + 1)
		if not problem.is_empty(): return problem
	for combinator in ["allOf", "anyOf", "oneOf"]:
		if not schema.has(combinator): continue
		if not schema[combinator] is Array: return path + ": schemă compusă invalidă."
		var matches = 0
		var details = []
		for branch in schema[combinator]:
			var issue = _validate(value, branch, root, path, depth + 1)
			if issue.is_empty(): matches += 1
			else: details.append(issue)
		if (combinator == "allOf" and matches != schema[combinator].size()) or (combinator == "anyOf" and matches == 0) or (combinator == "oneOf" and matches != 1): return path + ": valoarea nu corespunde " + combinator + " (" + "; ".join(details) + ")"
	if schema.has("not") and _validate(value, schema["not"], root, path, depth + 1).is_empty(): return path + ": valoare exclusă de schemă."
	if schema.has("type"):
		var types: Array = schema["type"] if schema["type"] is Array else [schema["type"]]
		var matches = false
		for kind in types:
			match str(kind):
				"object": matches = matches or value is Dictionary
				"array": matches = matches or value is Array
				"string": matches = matches or value is String
				"boolean": matches = matches or value is bool
				"null": matches = matches or value == null
				"number": matches = matches or value is int or value is float
				"integer": matches = matches or value is int or (value is float and is_finite(value) and value == floor(value))
				_: return path + ": tip de schemă necunoscut."
		if not matches: return path + ": tip invalid; așteptat " + str(schema["type"])
	if schema.has("enum") and (not schema["enum"] is Array or not value in schema["enum"]): return path + ": valoare în afara enum."
	if schema.has("const") and value != schema["const"]: return path + ": valoare diferită de const."
	if value is Dictionary:
		var properties: Variant = schema.get("properties", {})
		var required: Variant = schema.get("required", [])
		if not properties is Dictionary or not required is Array: return path + ": proprietăți de schemă invalide."
		for key in required:
			if not value.has(key): return path + ": argument obligatoriu: " + str(key)
		if value.size() < int(schema.get("minProperties", 0)) or value.size() > int(schema.get("maxProperties", 100000)): return path + ": număr invalid de proprietăți."
		for key in value:
			var specification: Variant = properties.get(key, schema.get("additionalProperties", true))
			var problem = _validate(value[key], specification, root, path + "." + str(key), depth + 1)
			if not problem.is_empty(): return problem
	if value is Array:
		if value.size() < int(schema.get("minItems", 0)) or value.size() > int(schema.get("maxItems", 100000)): return path + ": număr invalid de elemente."
		var seen = {}
		for index in range(value.size()):
			if schema.get("uniqueItems", false):
				var encoded = JSON.stringify(value[index], "", true)
				if seen.has(encoded): return path + ": element duplicat."
				seen[encoded] = true
			var problem = _validate(value[index], schema.get("items", {}), root, path + "[%s]" % index, depth + 1)
			if not problem.is_empty(): return problem
	if value is String:
		if value.length() < int(schema.get("minLength", 0)) or value.length() > int(schema.get("maxLength", 100000000)): return path + ": %s caractere; lungimea permisă este %s–%s." % [value.length(), schema.get("minLength", 0), schema.get("maxLength", 100000000)]
		if schema.has("pattern"):
			var expression = RegEx.new()
			if expression.compile(str(schema["pattern"])) != OK or expression.search(value) == null: return path + ": textul nu corespunde pattern."
	if value is int or value is float:
		if not is_finite(float(value)): return path + ": număr nefinit."
		if (schema.has("minimum") and value < schema["minimum"]) or (schema.has("maximum") and value > schema["maximum"]): return path + ": număr în afara limitelor."
		if (schema.has("exclusiveMinimum") and value <= schema["exclusiveMinimum"]) or (schema.has("exclusiveMaximum") and value >= schema["exclusiveMaximum"]): return path + ": număr în afara limitelor exclusive."
	return ""
