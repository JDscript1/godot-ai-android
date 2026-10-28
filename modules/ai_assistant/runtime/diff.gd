@tool
extends RefCounted
## Bounded Myers line diff. Limits are explicit; truncated results have no fake counts.
static func lines(text: String) -> Array:
	if text.is_empty(): return []
	var result: Array = text.replace("\r\n", "\n").split("\n")
	if result[-1] == "": result.pop_back()
	return result

static func compare(before: String, after: String) -> Dictionary:
	if before.length() + after.length() > 2 * 1024 * 1024: return {"exact": false, "reason": "Fișier mare", "operations": []}
	var a = lines(before)
	var b = lines(after)
	if a.size() + b.size() > 20000: return {"exact": false, "reason": "Prea multe linii", "operations": []}
	var prefix = 0
	while prefix < mini(a.size(), b.size()) and a[prefix] == b[prefix]: prefix += 1
	var suffix = 0
	while suffix < mini(a.size(), b.size()) - prefix and a[-1 - suffix] == b[-1 - suffix]: suffix += 1
	var left = a.slice(prefix, a.size() - suffix)
	var right = b.slice(prefix, b.size() - suffix)
	var frontier = {1: 0}
	var trace = []
	var operations = []
	var complete = false
	var cost = 0
	for depth in range(mini(left.size() + right.size(), 512) + 1):
		trace.append(frontier.duplicate())
		for diagonal in range(-depth, depth + 1, 2):
			var x = int(frontier.get(diagonal + 1, 0)) if diagonal == -depth or (diagonal != depth and int(frontier.get(diagonal - 1, 0)) < int(frontier.get(diagonal + 1, 0))) else int(frontier.get(diagonal - 1, 0)) + 1
			var y = x - diagonal
			while x < left.size() and y < right.size() and left[x] == right[y]: x += 1; y += 1; cost += 1
			frontier[diagonal] = x
			cost += 1
			if cost > 500000: return {"exact": false, "reason": "Diff prea mare", "operations": []}
			if x >= left.size() and y >= right.size():
				operations = _backtrack(trace, left, right, depth)
				complete = true
				break
		if complete: break
	if not complete: return {"exact": false, "reason": "Prea multe diferențe", "operations": []}
	var all = []
	for line in a.slice(0, prefix): all.append([" ", line])
	all.append_array(operations)
	for line in a.slice(a.size() - suffix) if suffix > 0 else []: all.append([" ", line])
	if not all.is_empty() and all[-1][0] == " " and before.ends_with("\n") != after.ends_with("\n"):
		var line = all.pop_back()[1]
		all.append(["-", line])
		all.append(["+", line])
		operations = all
	var added = 0
	var removed = 0
	for operation in operations:
		if operation[0] == "+": added += 1
		elif operation[0] == "-": removed += 1
	var first_line = 1
	for op in all:
		if op[0] != " ": break
		first_line += 1
	return {"exact": true, "added": added, "removed": removed, "operations": all, "first_line": first_line, "before_newline": before.ends_with("\n"), "after_newline": after.ends_with("\n")}

static func _backtrack(trace: Array, a: Array, b: Array, depth: int) -> Array:
	var x = a.size()
	var y = b.size()
	var output = []
	for index in range(depth, -1, -1):
		var frontier: Dictionary = trace[index]
		var diagonal = x - y
		var previous = diagonal + 1 if diagonal == -index or (diagonal != index and int(frontier.get(diagonal - 1, 0)) < int(frontier.get(diagonal + 1, 0))) else diagonal - 1
		var old_x = int(frontier.get(previous, 0))
		var old_y = old_x - previous
		while x > old_x and y > old_y:
			output.append([" ", a[x - 1]])
			x -= 1; y -= 1
		if index == 0: break
		if x == old_x: output.append(["+", b[y - 1]]); y -= 1
		else: output.append(["-", a[x - 1]]); x -= 1
	output.reverse()
	return output

static func hunks(result: Dictionary, context: int = 3) -> Array:
	if not result.get("exact", false): return []
	var operations: Array = result["operations"]
	var ranges = []
	for index in range(operations.size()):
		if operations[index][0] == " ": continue
		var start = maxi(0, index - context)
		var end = mini(operations.size(), index + context + 1)
		if not ranges.is_empty() and start <= ranges[-1][1]: ranges[-1][1] = maxi(int(ranges[-1][1]), end)
		else: ranges.append([start, end])
	var locations = []
	var old_line = 1
	var new_line = 1
	for op in operations:
		locations.append([old_line, new_line])
		if op[0] != "+": old_line += 1
		if op[0] != "-": new_line += 1
	var output = []
	for index in range(ranges.size()):
		var span: Array = ranges[index]
		var added = 0
		var removed = 0
		for op in operations.slice(span[0], span[1]):
			if op[0] == "+": added += 1
			elif op[0] == "-": removed += 1
		output.append({"index": index, "start": span[0], "end": span[1], "old_start": locations[span[0]][0], "new_start": locations[span[0]][1], "added": added, "removed": removed})
	return output

static func select(result: Dictionary, accepted: Array) -> String:
	if not result.get("exact", false): return ""
	var operations: Array = result["operations"]
	var spans = hunks(result)
	var hunk_of = {}
	for hunk in spans:
		for index in range(hunk["start"], hunk["end"]): hunk_of[index] = hunk["index"]
	var keep = {}
	for index in accepted: keep[int(index)] = true
	var output = []
	for index in range(operations.size()):
		var op: Array = operations[index]
		if op[0] == " ": output.append(op[1])
		elif hunk_of.has(index) and (keep.has(hunk_of[index]) == (op[0] == "+")): output.append(op[1])
	var newline = bool(result.get("after_newline", false))
	if bool(result.get("before_newline", false)) != newline and not spans.is_empty() and not keep.has(int(spans[-1]["index"])):
		newline = bool(result.get("before_newline", false))
	return "\n".join(output) + ("\n" if newline and not output.is_empty() else "")

static func unified(path: String, result: Dictionary) -> String:
	if not result.get("exact", false): return path + " · " + str(result.get("reason", "Diff indisponibil"))
	var operations: Array = result["operations"]
	var ranges = []
	for index in range(operations.size()):
		if operations[index][0] == " ": continue
		var start = maxi(0, index - 3)
		var end = mini(operations.size(), index + 4)
		if not ranges.is_empty() and start <= ranges[-1][1]: ranges[-1][1] = end
		else: ranges.append([start, end])
	var old_line = 1
	var new_line = 1
	var locations = []
	for op in operations:
		locations.append([old_line, new_line])
		if op[0] != "+": old_line += 1
		if op[0] != "-": new_line += 1
	var output = "--- " + path + "\n+++ " + path + "\n"
	for span in ranges:
		var old_count = 0
		var new_count = 0
		for op in operations.slice(span[0], span[1]):
			if op[0] != "+": old_count += 1
			if op[0] != "-": new_count += 1
		output += "@@ -%s,%s +%s,%s @@\n" % [locations[span[0]][0], old_count, locations[span[0]][1], new_count]
		for op in operations.slice(span[0], span[1]): output += op[0] + str(op[1]) + "\n"
	return output
