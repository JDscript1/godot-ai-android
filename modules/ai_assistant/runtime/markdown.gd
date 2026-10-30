@tool
extends RefCounted
## A small safe Markdown renderer: model text is never interpreted as BBCode/HTML.
static var Common: GDScript
static var token_pattern: RegEx

## Line-based fences preserve literal backticks inside code and tolerate partial
## provider chunks. Paragraphs are separate widgets so completed blocks need no
## further layout or Markdown work while the tail is streaming.
static func blocks(text: String, streaming: bool = false) -> Array:
	var result: Array = []
	var prose: Array[String] = []
	var code: Array[String] = []
	var marker = ""
	var language = ""
	var lines = text.replace("\r\n", "\n").split("\n")
	for index in range(lines.size()):
		var line = lines[index]
		var trimmed = line.strip_edges()
		var fence = trimmed.left(1)
		var count = 0
		if fence in ["`", "~"]:
			while count < trimmed.length() and trimmed[count] == fence: count += 1
		var tail = index == lines.size() - 1
		if marker.is_empty():
			if count >= 3 and line.length() - line.strip_edges(true, false).length() <= 3:
				if not prose.is_empty(): result.append({"kind": "text", "text": "\n".join(prose)})
				prose.clear()
				marker = fence.repeat(count)
				language = trimmed.substr(count).strip_edges().get_slice(" ", 0).left(40)
			elif streaming and tail and count in [1, 2] and trimmed.length() == count:
				pass # Wait for a possible opening fence instead of flashing its marker.
			elif trimmed.is_empty():
				if not prose.is_empty(): result.append({"kind": "text", "text": "\n".join(prose)})
				prose.clear()
			else: prose.append(line)
		elif trimmed.begins_with(marker) and trimmed.replace(marker[0], "").is_empty():
			result.append({"kind": "code", "text": "\n".join(code), "language": language, "complete": true})
			code.clear()
			marker = ""
		elif streaming and tail and trimmed.length() < marker.length() and not trimmed.is_empty() and trimmed.replace(marker[0], "").is_empty():
			pass # An incomplete closing fence is not source code.
		else: code.append(line)
	if not marker.is_empty():
		# An opening fence's unfinished language tag is held until its newline.
		if not streaming or not code.is_empty(): result.append({"kind": "code", "text": "\n".join(code).trim_suffix("\n"), "language": language, "complete": false})
	elif not prose.is_empty(): result.append({"kind": "text", "text": "\n".join(prose)})
	return result

static func inline_text(target: RichTextLabel, value: String, depth: int = 0) -> void:
	if depth > 5:
		target.add_text(value)
		return
	if token_pattern == null:
		token_pattern = RegEx.new()
		token_pattern.compile("`[^`\\n]+`|\\*\\*[^*\\n]+\\*\\*|~~[^~\\n]+~~|\\[[^\\]\\n]+\\]\\((?:https?://|res://)[^\\s)]+\\)|res://[^\\s`\\]<>]+|(?<!\\*)\\*[^*\\n]+\\*(?!\\*)")
	var offset = 0
	for match_result in token_pattern.search_all(value):
		target.add_text(value.substr(offset, match_result.get_start() - offset))
		var part = match_result.get_string()
		if part.begins_with("`"):
			target.push_font(target.get_theme_font("font", "CodeEdit"))
			target.push_bgcolor(Color("29283b"))
			target.push_color(Color("d2bff4"))
			var literal = part.substr(1, part.length() - 2)
			var link = Common.project_link(literal)
			if not link.is_empty(): target.push_meta(link, RichTextLabel.META_UNDERLINE_ALWAYS)
			target.add_text(literal)
			if not link.is_empty(): target.pop()
			target.pop(); target.pop(); target.pop()
		elif part.begins_with("**"):
			target.push_bold()
			inline_text(target, part.substr(2, part.length() - 4), depth + 1)
			target.pop()
		elif part.begins_with("~~"):
			target.push_strikethrough()
			inline_text(target, part.substr(2, part.length() - 4), depth + 1)
			target.pop()
		elif part.begins_with("["):
			var split = part.find("](")
			var url = part.substr(split + 2, part.length() - split - 3)
			var project = Common.project_link(url)
			if not project.is_empty() or Common.parse_url(url, true).get("ok", false):
				target.push_meta(project if not project.is_empty() else url, RichTextLabel.META_UNDERLINE_ON_HOVER)
				target.push_color(Color("a7c6fa"))
				inline_text(target, part.substr(1, split - 1), depth + 1)
				target.pop(); target.pop()
			else: target.add_text(part)
		elif part.begins_with("res://"):
			var path = part.rstrip(".,;)")
			var link = Common.project_link(path)
			if not link.is_empty():
				target.push_meta(link, RichTextLabel.META_UNDERLINE_ALWAYS)
				target.push_color(Color("a7c6fa"))
				target.add_text(path)
				target.pop(); target.pop()
				target.add_text(part.substr(path.length()))
			else: target.add_text(part)
		else:
			target.push_italics()
			inline_text(target, part.substr(1, part.length() - 2), depth + 1)
			target.pop()
		offset = match_result.get_end()
	target.add_text(value.substr(offset))

static func cells(line: String) -> PackedStringArray:
	var row = line.strip_edges().trim_prefix("|").trim_suffix("|").split("|")
	for index in range(row.size()): row[index] = row[index].strip_edges()
	return row

static func table_separator(line: String) -> bool:
	if not "|" in line: return false
	for cell in cells(line):
		var value = cell.trim_prefix(":").trim_suffix(":")
		if value.length() < 3 or not value.replace("-", "").is_empty(): return false
	return true

static func render(target: RichTextLabel, text: String, scale: float = 1.0) -> void:
	target.clear()
	var lines = text.strip_edges().split("\n")
	var index = 0
	while index < lines.size():
		var line = lines[index]
		if index + 1 < lines.size() and "|" in line and table_separator(lines[index + 1]) and cells(line).size() == cells(lines[index + 1]).size() and cells(line).size() <= 6:
			var columns = cells(line).size()
			target.push_table(columns)
			for column in range(columns): target.set_table_column_expand(column, true)
			var row = 0
			while index < lines.size() and "|" in lines[index] and cells(lines[index]).size() == columns:
				if table_separator(lines[index]):
					index += 1
					continue
				for cell in cells(lines[index]):
					target.push_cell()
					if row == 0: target.push_bold()
					inline_text(target, cell)
					if row == 0: target.pop()
					target.pop()
				row += 1
				index += 1
			target.pop()
			if index < lines.size(): target.add_text("\n\n")
			continue
		var heading = 0
		while heading < line.length() and line[heading] == "#": heading += 1
		var is_heading = heading > 0 and heading <= 6 and line.substr(heading).begins_with(" ")
		if is_heading:
			target.push_font_size(int((19 if heading == 1 else (17 if heading == 2 else 15)) * scale))
			target.push_bold()
			inline_text(target, line.substr(heading + 1))
			target.pop(); target.pop()
		elif line.strip_edges() in ["---", "***", "___"]:
			target.push_color(Color("495166"))
			target.add_text("────────────────")
			target.pop()
		elif line.begins_with(">"):
			target.push_color(Color("acb8d0"))
			target.add_text("│  ")
			inline_text(target, line.trim_prefix(">").trim_prefix(" "))
			target.pop()
		else:
			var trimmed = line.strip_edges(true, false)
			var indent = line.length() - trimmed.length()
			if trimmed.begins_with("- ") or trimmed.begins_with("* ") or trimmed.begins_with("+ "):
				target.add_text("  ".repeat(mini(indent / 2, 4)) + "•  ")
				inline_text(target, trimmed.substr(2))
			else: inline_text(target, line)
		if index < lines.size() - 1: target.add_text("\n")
		index += 1
