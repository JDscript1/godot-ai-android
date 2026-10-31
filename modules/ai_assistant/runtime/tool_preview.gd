@tool
extends RefCounted
## Bounded, redacted snapshots of native inspection results. Never re-read disk
## when restoring a conversation: an old result must stay an old result.
static var Common: GDScript
const MAX_ROWS = 100
const MAX_CHARS = 12000
const MAX_MATCHES = 12

static func build(name: String, args: Dictionary, result: Dictionary, redact: Callable) -> Dictionary:
	if not result.get("ok", false): return {}
	var data: Variant = result.get("result")
	var preview = {"kind": "", "items": [], "partial": false}
	var budget = {"chars": 0, "rows": 0, "partial": false}
	if name in ["godot_read_file", "godot_read_range"]:
		var path = Common.project_path(str(data.get("path", args.get("path", ""))) if data is Dictionary else str(args.get("path", "")))
		if path.is_empty() or str(redact.call(path)) != path: return {}
		var rows = []
		if name == "godot_read_file" and data is String:
			# Split only the bounded prefix; never duplicate an entire large tool body.
			var redacted = str(redact.call(data))
			var prefix = redacted.left(MAX_CHARS)
			var lines = prefix.split("\n")
			for index in range(mini(lines.size(), MAX_ROWS)):
				_add_row(rows, index + 1, lines[index], budget, redact)
			preview["partial"] = prefix.length() < redacted.length() or lines.size() > MAX_ROWS
		elif name == "godot_read_range" and data is Dictionary and data.get("lines") is Array:
			for row in data["lines"].slice(0, MAX_ROWS):
				if not row is Dictionary: continue
				_add_row(rows, int(row.get("line", 0)), row.get("text"), budget, redact)
				if row.get("truncated", false): budget["partial"] = true
			preview["partial"] = data["lines"].size() > MAX_ROWS or int(data.get("next_line", -1)) > 0
		if rows.is_empty():
			if data is String and data.is_empty(): preview["empty"] = true
			else: return {}
		preview["kind"] = "read"
		preview["items"].append({"path": path, "line": rows[0]["line"] if not rows.is_empty() else 1, "rows": rows})
	elif name == "godot_search_code" and data is Dictionary and data.get("matches") is Array:
		preview["kind"] = "search"
		preview["query"] = str(redact.call(str(args.get("query", "")).left(240))).left(240)
		preview["partial"] = data.get("truncated", false) or data["matches"].size() > MAX_MATCHES
		for hit in data["matches"].slice(0, MAX_MATCHES):
			if not hit is Dictionary: continue
			var path = Common.project_path(str(hit.get("path", "")))
			if path.is_empty() or str(redact.call(path)) != path or int(hit.get("line", 0)) < 1 or int(hit.get("line", 0)) > 1000000: continue
			var rows = []
			for nearby in hit.get("before", []).slice(0, 4) if hit.get("before") is Array else []:
				if nearby is Dictionary: _add_row(rows, int(nearby.get("line", 0)), nearby.get("text"), budget, redact)
			_add_row(rows, int(hit.get("line", 0)), hit.get("text"), budget, redact)
			for nearby in hit.get("after", []).slice(0, 4) if hit.get("after") is Array else []:
				if nearby is Dictionary: _add_row(rows, int(nearby.get("line", 0)), nearby.get("text"), budget, redact)
			preview["items"].append({"path": path, "line": clampi(int(hit.get("line", 1)), 1, 1000000), "column": clampi(int(hit.get("column", 1)), 1, 1000000), "rows": rows, "excerpt_column": int(hit.get("excerpt_column", 1))})
	elif name == "godot_files" and data is Array:
		preview["kind"] = "files"
		preview["partial"] = data.size() > 30
		for entry in data.slice(0, 30):
			if not entry is String: continue
			var path = Common.project_path(entry)
			if not path.is_empty() and str(redact.call(path)) == path: preview["items"].append({"path": path, "line": 1})
	else: return {}
	preview["partial"] = preview["partial"] or budget["partial"]
	return preview

static func _add_row(rows: Array, line: int, value: Variant, budget: Dictionary, redact: Callable) -> void:
	if not value is String or line < 1 or line > 1000000: return
	if budget["rows"] >= MAX_ROWS or budget["chars"] >= MAX_CHARS:
		budget["partial"] = true
		return
	# Redact before clipping, so a secret crossing the boundary cannot leak a prefix.
	var text = str(redact.call(value)).trim_suffix("\r")
	var clipped = text.left(mini(800, MAX_CHARS - budget["chars"]))
	if clipped.length() < text.length(): budget["partial"] = true
	rows.append({"line": line, "text": clipped})
	budget["chars"] += clipped.length()
	budget["rows"] += 1
