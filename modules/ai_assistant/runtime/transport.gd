@tool
extends RefCounted

static var Common: GDScript
var owner: Node
var timeout_seconds = 180

class SSEDecoder:
	extends RefCounted
	var pending = PackedByteArray()
	var data_lines: Array[String] = []
	var event_name = ""
	var ended = false

	func feed(bytes: PackedByteArray, callback: Callable) -> void:
		pending.append_array(bytes)
		while true:
			var newline = pending.find(10)
			if newline < 0: break
			var line = pending.slice(0, newline).get_string_from_utf8().trim_suffix("\r")
			pending = pending.slice(newline + 1)
			if line.is_empty():
				flush(callback)
			elif line.begins_with("data:"):
				data_lines.append(line.substr(5).trim_prefix(" "))
			elif line.begins_with("event:"):
				event_name = line.substr(6).strip_edges()

	func flush(callback: Callable) -> void:
		if data_lines.is_empty(): return
		var data = "\n".join(data_lines)
		data_lines.clear()
		if data == "[DONE]":
			ended = true
			return
		var parser = JSON.new()
		var parsed: Variant = parser.data if parser.parse(data) == OK else null
		if parsed is Dictionary:
			if not event_name.is_empty(): parsed["_event"] = event_name
			callback.call(parsed)
		event_name = ""

func _init(node: Node = null) -> void:
	owner = node

func request(url: String, method: int = HTTPClient.METHOD_GET, headers: PackedStringArray = [], body: Variant = null, options: Dictionary = {}) -> Dictionary:
	var location = Common.parse_url(url, bool(options.get("allow_http", false)))
	if not location.get("ok", false): return location
	if owner == null or not owner.is_inside_tree(): return Common.failure("Transport fără editor activ.")
	var cancel: Dictionary = options.get("cancel", {})
	var client = HTTPClient.new()
	var tls: TLSOptions = TLSOptions.client() if location["scheme"] == "https" else null
	var error = client.connect_to_host(str(location["host"]), int(location["port"]), tls)
	if error != OK: return Common.failure("Conexiunea nu a putut porni (%s)." % error)
	var deadline = Time.get_ticks_msec() + int(options.get("timeout", timeout_seconds)) * 1000
	while client.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		if _expired(deadline, cancel):
			client.close()
			return Common.failure("Oprit sau conexiune expirată.", "cancelled" if cancel.get("cancelled", false) else "timeout")
		client.poll()
		await owner.get_tree().process_frame
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		client.close()
		return Common.failure("Serverul nu poate fi contactat. Verifică adresa și rețeaua.", "connection_failed")
	var encoded: PackedByteArray
	if body is PackedByteArray:
		encoded = body
	elif body is String:
		encoded = body.to_utf8_buffer()
	elif body != null:
		encoded = JSON.stringify(body).to_utf8_buffer()
	if body is Dictionary or body is Array: headers.append("Content-Type: application/json")
	for header in headers:
		if "\r" in header or "\n" in header:
			client.close()
			return Common.failure("Antet HTTP invalid.")
	error = client.request_raw(method, str(location["path"]), headers, encoded)
	if error != OK:
		client.close()
		return Common.failure("Cererea HTTP nu a putut porni (%s)." % error)
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		if _expired(deadline, cancel):
			client.close()
			return Common.failure("Oprit sau cerere expirată.", "cancelled" if cancel.get("cancelled", false) else "timeout")
		client.poll()
		await owner.get_tree().process_frame
	if not client.has_response():
		client.close()
		return Common.failure("Serverul nu a returnat un răspuns HTTP.")
	var status = client.get_response_code()
	var response_headers = client.get_response_headers_as_dictionary()
	var max_bytes = int(options.get("max_bytes", 16 * 1024 * 1024))
	var bytes = PackedByteArray()
	var total = 0
	var events: Array = []
	var decoder = SSEDecoder.new()
	var event_callback: Callable = options.get("on_event", Callable())
	var content_type = ""
	for key in response_headers:
		if str(key).to_lower() == "content-type": content_type = str(response_headers[key])
	var is_sse = "text/event-stream" in content_type
	var receive = func(event: Dictionary) -> void:
		if events.size() < 20000: events.append(event)
		if event_callback.is_valid(): event_callback.call(event)
	var file: FileAccess = null
	var save_path = str(options.get("save_path", ""))
	if not save_path.is_empty() and status >= 200 and status < 300:
		file = FileAccess.open(save_path, FileAccess.WRITE)
		if file == null:
			client.close()
			return Common.failure("Nu pot scrie fișierul descărcat.")
	while client.get_status() == HTTPClient.STATUS_BODY:
		if _expired(deadline, cancel):
			client.close()
			if file != null: file.close()
			return Common.failure("Oprit sau răspuns expirat.", "cancelled" if cancel.get("cancelled", false) else "timeout")
		client.poll()
		var chunk = client.read_response_body_chunk()
		total += chunk.size()
		if total > max_bytes:
			client.close()
			if file != null: file.close()
			return Common.failure("Răspunsul depășește limita de dimensiune.", "response_too_large")
		if file != null:
			file.store_buffer(chunk)
		elif is_sse:
			decoder.feed(chunk, receive)
		else:
			bytes.append_array(chunk)
		await owner.get_tree().process_frame
	var final_status = client.get_status()
	client.close()
	if file != null: file.close()
	if is_sse: decoder.flush(receive)
	if final_status not in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
		return Common.failure("Fluxul HTTP a fost întrerupt.", "interrupted")
	var text = bytes.get_string_from_utf8() if file == null else ""
	var result = {"ok": status >= 200 and status < 300, "status": status, "headers": response_headers, "json": Common.parse_json(text), "text": text, "events": events, "bytes": bytes, "saved_path": save_path}
	if not result["ok"]: result["error"] = "HTTP %s: %s" % [status, text.left(1000)]
	return result

func _expired(deadline: int, cancel: Dictionary) -> bool:
	return cancel.get("cancelled", false) or Time.get_ticks_msec() > deadline
