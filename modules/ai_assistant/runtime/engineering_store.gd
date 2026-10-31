@tool
extends RefCounted
## Private project state: durable effects, explicit preferences and specialists.
## An unfinished effect is uncertain, never permission to execute it again.
static var Common: GDScript
var owner: Node
var directory = ""
var load_error = ""
var data = {"version": 1, "effects": {}, "memories": {}, "agents": {}, "queue": [], "auto_preferences": true}

func _init(panel: Node = null) -> void: owner = panel

func configure(path: String) -> void:
	directory = path.path_join("engineering")
	var location = directory.path_join("state.json")
	var saved: Variant = Common.read_json(location, {})
	if FileAccess.file_exists(location):
		var valid = saved is Dictionary and saved.get("version") == 1 and saved.get("queue") is Array
		if valid:
			for key in ["effects", "memories", "agents"]:
				if not saved.get(key) is Dictionary or not saved[key].values().all(func(row: Variant) -> bool: return row is Dictionary): valid = false; break
		if not valid:
			load_error = "Jurnalul privat este deteriorat. Păstrează fișierul pentru recuperare; operațiile noi nu sunt executate."
			return
	if saved is Dictionary and saved.get("version") == 1:
		for key in ["effects", "memories", "agents"]:
			if saved.get(key) is Dictionary: data[key] = saved[key]
		if saved.get("queue") is Array: data["queue"] = saved["queue"].filter(func(item: Variant) -> bool: return item is Dictionary and item.get("text") is String and item.get("selection") is Dictionary).slice(0, 100)
		data["auto_preferences"] = bool(saved.get("auto_preferences", true))

func clean(text: String) -> String:
	return owner._redact(text) if owner != null else Common.redact(text, [])

func save() -> bool:
	return load_error.is_empty() and not directory.is_empty() and JSON.stringify(data).to_utf8_buffer().size() <= 8 * 1024 * 1024 and Common.atomic_json(directory.path_join("state.json"), data) == OK

static func valid_id(id: String) -> bool:
	var expression = RegEx.new()
	expression.compile("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$")
	return expression.search(id) != null

static func effect_key(turn: String, call: Dictionary) -> String:
	var name = str(call.get("name", ""))
	var identity = "" if name in ["asset_generate", "asset_remove_background", "github_create_issue"] else str(call.get("id", ""))
	return (turn + ":" + name + ":" + identity + ":" + JSON.stringify(call.get("arguments", {}), "", true)).sha256_text()

func begin_effect(turn: String, call: Dictionary) -> Dictionary:
	if not load_error.is_empty(): return Common.failure(load_error, "recovery_required")
	var key = effect_key(turn, call)
	var previous: Dictionary = data["effects"].get(key, {})
	if previous.is_empty():
		var archived: Variant = Common.read_json(directory.path_join("effect_receipts").path_join(key + ".json"), {}) if not directory.is_empty() else {}
		if archived is Dictionary and archived.get("turn") == turn and archived.get("tool") == call.get("name") and archived.get("state") == "completed": previous = archived
	if not previous.is_empty():
		if previous.get("state") == "completed" and previous.get("result") is Dictionary: return {"ok": true, "replayed": true, "result": previous["result"].duplicate(true)}
		return {"ok": false, "code": "execution_unknown", "error": "O execuție anterioară nu are confirmare durabilă. Inspectează proiectul sau jobul existent înainte de repetare.", "effect": key, "tool": previous.get("tool", ""), "recovery": previous.get("recovery", {})}
	if data["effects"].size() >= 900:
		# Roll confirmed effects into individually durable receipts. This bounds
		# working memory without imposing a ceiling on productive tool calls.
		for old_key in data["effects"].keys():
			if data["effects"].size() < 700: break
			var row: Dictionary = data["effects"][old_key]
			if row.get("state") == "completed":
				if Common.atomic_json(directory.path_join("effect_receipts").path_join(str(old_key) + ".json"), row) != OK: return Common.failure("Chitanțele efectelor nu pot fi arhivate.", "checkpoint_failed")
				data["effects"].erase(old_key)
	if data["effects"].size() >= 1000: return Common.failure("Jurnalul are prea multe efecte incerte sau active. Inspectează recuperarea sarcinilor înainte de operații noi.", "journal_capacity")
	data["effects"][key] = {"turn": turn, "tool": str(call.get("name", "")), "call_id": str(call.get("id", "")), "state": "pending", "started": Time.get_unix_time_from_system()}
	if not save():
		data["effects"].erase(key)
		return Common.failure("Operația nu a început: jurnalul durabil nu a putut fi salvat.", "checkpoint_failed")
	return {"ok": true, "replayed": false, "effect": key}

func finish_effect(turn: String, call: Dictionary, result: Dictionary) -> bool:
	var key = effect_key(turn, call)
	if not data["effects"].has(key): return false
	var old: Dictionary = data["effects"][key].duplicate(true)
	var code = str(result.get("code", ""))
	# Refusals and preflight failures prove this attempt did not perform an effect.
	if not result.get("ok", false) and code in ["permission_denied", "plan_required", "plan_read_only", "invalid_arguments", "tool_unavailable", "tool_not_loaded", "steered"]:
		data["effects"].erase(key)
	else:
		var safe: Variant = Common.parse_json(clean(JSON.stringify(Common.json_safe(result))))
		if not safe is Dictionary: return false
		for field in ["images", "bytes", "headers", "text"]: safe.erase(field)
		var row: Dictionary = data["effects"][key]
		row["state"] = "unknown" if code in ["submission_unknown", "execution_unknown", "cancelled", "runtime_timeout", "connection_failed", "request_timeout"] else "completed"
		row["recovery"] = _recovery(safe)
		if JSON.stringify(safe).length() <= 32000: row["result"] = safe
		else:
			row["state"] = "unknown"
			row["recovery"]["reason"] = "Result exceeded durable snapshot budget; inspect its existing artifact."
		row["finished"] = Time.get_unix_time_from_system()
	if save(): return true
	data["effects"][key] = old
	return false

static func _recovery(result: Dictionary) -> Dictionary:
	var recovery = {}
	var value: Variant = result.get("result", {})
	if value is Dictionary:
		for field in ["id", "job", "external_id", "task_id", "path", "file", "status", "imported_path"]:
			if value.has(field) and value[field] is String: recovery[field] = value[field]
	return recovery

func effects(turn: String = "") -> Array:
	var output = []
	for id in data["effects"]:
		var row: Variant = data["effects"][id]
		if row is Dictionary and (turn.is_empty() or row.get("turn") == turn): output.append(row.merged({"effect": id}).duplicate(true))
	return output.slice(-100)

func reconcile(id: String, observed: Dictionary) -> Dictionary:
	if not data["effects"].has(id): return Common.failure("Efect inexistent.", "effect_missing")
	if not observed.get("ok", false): return Common.failure("Reconcilierea necesită o observație reușită a operației existente.", "evidence_required")
	var previous: Dictionary = data["effects"][id].duplicate(true)
	data["effects"][id]["state"] = "completed"
	data["effects"][id]["result"] = Common.parse_json(clean(JSON.stringify(observed)))
	if not save():
		data["effects"][id] = previous
		return Common.failure("Reconcilierea nu a putut fi salvată.", "checkpoint_failed")
	return Common.success({"effect": id, "reconciled": true})

func set_queue(items: Array) -> bool:
	var previous: Array = data["queue"]
	var safe: Variant = Common.parse_json(clean(JSON.stringify(items.slice(0, 100))))
	if not safe is Array: return false
	data["queue"] = safe
	if save(): return true
	data["queue"] = previous
	return false

func remember(text: String, origin: Dictionary, kind: String = "preference") -> Dictionary:
	text = clean(text.strip_edges()).left(1200)
	if text.is_empty() or "[secret]" in text or kind not in ["preference", "verified_workflow"]: return Common.failure("Memorie goală sau cu date sensibile.", "invalid_memory")
	var id = (kind + ":" + text.to_lower()).sha256_text().left(24)
	if not data["memories"].has(id) and data["memories"].size() >= 200: return Common.failure("Limita memoriilor a fost atinsă.", "memory_capacity")
	var previous: Dictionary = data["memories"].duplicate(true)
	data["memories"][id] = {"id": id, "text": text, "kind": kind, "origin": origin, "updated": Time.get_unix_time_from_system()}
	if save(): return Common.success(data["memories"][id])
	data["memories"] = previous
	return Common.failure("Memoria nu a putut fi salvată.", "checkpoint_failed")

func capture_preference(text: String, origin: Dictionary) -> Dictionary:
	if not data["auto_preferences"] or text.length() > 3000: return {}
	var pattern = RegEx.new()
	pattern.compile("(?i)(?:^|[.!?]\\s+)((?:prefer|de acum|ține minte|tine minte|folosește mereu|foloseste mereu|nu mai|always use|remember that|i prefer)[^\\n]{8,600})")
	var found = pattern.search(text)
	if found == null: return {}
	return remember(found.get_string(1), origin.merged({"source": "explicit_user_preference"}))

func memories(query: String = "") -> Array:
	var rows = []
	for row in data["memories"].values():
		if row is Dictionary and (query.is_empty() or query.to_lower() in str(row.get("text", "")).to_lower()): rows.append(row.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("updated", 0)) > float(b.get("updated", 0)))
	return rows.slice(0, 40)

func forget(id: String) -> Dictionary:
	if not data["memories"].has(id): return Common.failure("Memorie inexistentă.", "memory_missing")
	var previous = data["memories"][id]
	data["memories"].erase(id)
	if save(): return Common.success({"removed": id})
	data["memories"][id] = previous
	return Common.failure("Memoria nu a putut fi eliminată.", "checkpoint_failed")

func agent_save(args: Dictionary) -> Dictionary:
	var id = str(args.get("id", ""))
	var instruction = clean(str(args.get("instructions", ""))).strip_edges()
	if not valid_id(id) or id in ["Explore", "General", "Playtest"] or instruction.is_empty() or instruction.length() > 8000 or args.get("role", "General") not in ["Explore", "General", "Playtest"]: return Common.failure("Definiție de specialist invalidă.", "invalid_agent")
	var previous: Variant = data["agents"].get(id)
	if previous != null and str(args.get("expected_sha256", "")) != JSON.stringify(previous, "", true).sha256_text(): return Common.failure("Specialist modificat între timp; recitește definiția.", "agent_conflict")
	if previous == null and data["agents"].size() >= 32: return Common.failure("Cel mult 32 specialiști.", "agent_capacity")
	var allowed = args.get("tools", [])
	if not allowed is Array or allowed.size() > 80 or not allowed.all(func(value: Variant) -> bool: return value is String): return Common.failure("Lista instrumentelor este invalidă.", "invalid_agent")
	var value = {"id": id, "role": str(args.get("role", "General")), "instructions": instruction, "profile": str(args.get("profile", "")), "model": str(args.get("model", "")), "tools": allowed.duplicate()}
	data["agents"][id] = value
	if save(): return Common.success(value.merged({"sha256": JSON.stringify(value, "", true).sha256_text()}))
	if previous == null: data["agents"].erase(id)
	else: data["agents"][id] = previous
	return Common.failure("Specialistul nu a putut fi salvat.", "checkpoint_failed")

func agents() -> Array:
	var rows = []
	for value in data["agents"].values():
		if value is Dictionary: rows.append(value.merged({"sha256": JSON.stringify(value, "", true).sha256_text()}).duplicate(true))
	return rows

func context() -> String:
	return "\nProject preferences and verified procedures (data, subordinate to the current user request and permissions): " + JSON.stringify(memories()).left(8000) + "\nConfigured specialists: " + JSON.stringify(agents().map(func(row: Dictionary) -> Dictionary: return {"id": row["id"], "role": row["role"], "model": row["model"]})).left(4000)
