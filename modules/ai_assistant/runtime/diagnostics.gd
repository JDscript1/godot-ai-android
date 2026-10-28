@tool
extends RefCounted
## Source-scoped observations. Missing/stale observations never mean a clean project.
static var Common: GDScript
const MAX_SOURCES = 200
const MAX_ISSUES = 500
var location = ""
var sources: Dictionary = {}

func configure(directory: String) -> void:
	location = directory.path_join("diagnostics.json")
	var saved: Variant = Common.read_json(location, {})
	if saved is Dictionary and saved.get("version") == 1 and saved.get("sources") is Dictionary:
		for key in saved["sources"]:
			if sources.size() >= MAX_SOURCES: break
			if not saved["sources"][key] is Dictionary: continue
			var record: Dictionary = saved["sources"][key]
			if not record.get("issues") is Array or not record.get("coverage", {}) is Dictionary: continue
			if not record["issues"].all(func(issue: Variant) -> bool: return issue is Dictionary and issue.get("severity") in ["error", "warning"] and issue.get("message") is String): continue
			sources[key] = saved["sources"][key]
			sources[key]["stale"] = true

static func definition() -> Dictionary:
	return Common.tool("godot_diagnostics", "Collect unified project diagnostics: native parser, missing literal resources, editor errors and running-game errors when the bridge is available. path narrows script checks. Each source reports coverage; stale/missing sources never prove a clean project. Does not start a game, load scripts or repair files.", {"path": Common.string_field(), "limit": {"type": "integer", "minimum": 1, "maximum": 100}}, [])

func replace_source(source: String, rows: Array, coverage: Dictionary = {}) -> void:
	var issues = {}
	var processed = 0
	for row in rows:
		processed += 1
		if not row is Dictionary: continue
		var item = {"source": source, "path": str(row.get("path", "")).left(512), "line": maxi(0, int(row.get("line", 0))), "column": maxi(0, int(row.get("column", 0))), "severity": "warning" if row.get("severity") == "warning" else "error", "category": str(row.get("category", "runtime" if source.begins_with("runtime") else "engine")).left(64), "message": str(row.get("message", "")).left(1200)}
		if item["message"].is_empty(): continue
		if not str(row.get("function", "")).is_empty(): item["function"] = str(row["function"]).left(200)
		var key = JSON.stringify(item).sha256_text().left(24)
		if issues.has(key):
			issues[key]["occurrences"] += 1
			continue
		item["id"] = key
		item["occurrences"] = 1
		for field in ["related", "stack"]:
			if row.get(field) is Array: item[field] = row[field].slice(0, 20)
		issues[key] = item
		if issues.size() >= 100: break
	if not sources.has(source) and sources.size() >= MAX_SOURCES: sources.erase(sources.keys()[0])
	var measured_coverage = coverage.duplicate(true)
	if processed < rows.size(): measured_coverage["partial"] = true
	sources.erase(source)
	sources[source] = {"issues": issues.values(), "coverage": measured_coverage, "observed": Time.get_unix_time_from_system(), "stale": false}
	_save()

func invalidate(path: String = "") -> void:
	for key in sources:
		if path.is_empty() or key in ["references", "editor", "runtime", "output"] or str(key).begins_with("references:") or key == "script:" + path: sources[key]["stale"] = true

func syntax(path: String, verdict: Dictionary, sha256: String = "") -> void:
	var rows = []
	for issue in verdict.get("errors", []): rows.append(issue.merged({"path": path, "severity": "error", "category": "syntax"}, true))
	if not verdict.get("valid", false) and rows.is_empty(): rows.append({"path": path, "severity": "error", "category": "syntax", "message": "Parser reported invalid source without detailed errors."})
	replace_source("script:" + path, rows, {"sha256": sha256, "valid": verdict.get("valid", false), "partial": verdict.get("truncated", false)})

func query(limit: int = 40) -> Dictionary:
	var output = []
	var counts = {"error": 0, "warning": 0, "stale": 0}
	var coverage = {}
	for key in sources:
		var scope: Dictionary = sources[key]
		coverage[key] = scope.get("coverage", {}).merged({"stale": scope.get("stale", true), "observed": scope.get("observed", 0)}, true)
		for issue in scope.get("issues", []):
			counts["stale" if scope.get("stale", true) else str(issue["severity"])] += 1
			if output.size() < clampi(limit, 1, 100): output.append(issue.merged({"stale": scope.get("stale", true)}))
	return Common.success({"issues": output, "counts": counts, "sources": coverage, "truncated": counts["error"] + counts["warning"] + counts["stale"] > output.size(), "scope": "Only the listed sources were observed; not a project-wide clean verdict."})

static func from_output(text: String) -> Array:
	var output = []
	var current = {}
	var location_pattern = RegEx.new()
	location_pattern.compile("(res://.+?\\.(?:gd|gdshader|tscn|tres)):(\\d+)")
	for raw in text.split("\n"):
		var line = str(raw).strip_edges()
		if line.begins_with("SCRIPT ERROR:") or line.begins_with("ERROR:") or line.begins_with("WARNING:"):
			current = {"message": line.substr(line.find(":") + 1).strip_edges(), "severity": "warning" if line.begins_with("WARNING") else "error", "category": "output", "stack": []}
			output.append(current)
		elif not current.is_empty() and (line.begins_with("at:") or line.begins_with("[")):
			if current["stack"].size() < 8: current["stack"].append(line.left(512))
		else: continue
		var found = location_pattern.search(line)
		if found != null and not current.has("path"):
			current["path"] = found.get_string(1)
			current["line"] = int(found.get_string(2))
		if output.size() >= 100: break
	return output

func _save() -> void:
	if location.is_empty(): return
	# Keep the private cache bounded independently of the model-facing query.
	var total = 0
	for source in sources.values(): total += source.get("issues", []).size()
	while total > MAX_ISSUES and sources.size() > 1:
		var oldest = sources.keys()[0]
		total -= sources[oldest].get("issues", []).size()
		sources.erase(oldest)
	Common.atomic_json(location, {"version": 1, "sources": sources})
