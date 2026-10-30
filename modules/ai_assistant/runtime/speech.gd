@tool
extends RefCounted
static var Common: GDScript
static var Transport: GDScript
var owner: Node
var vault: RefCounted
var transport: RefCounted
var listening = false
var transcribing = false
var phase = "idle"
var level = 0.0
var recorder: AudioEffectRecord
var player: AudioStreamPlayer
var bus = -1
var started = 0
var cancel = {}
var backend = 0
var native_session = false
var native_token = ""
var request_id = 0
var record_preferences = {}
var previous_audio_input: Variant = null

func _init(panel: Node = null, secrets: RefCounted = null) -> void:
	owner = panel
	vault = secrets
	transport = Transport.new(panel)

func _phase(value: String) -> void:
	phase = value
	listening = value in ["permission", "starting", "recording"]
	transcribing = value == "transcribing"
	if value == "recording" and started == 0: started = Time.get_ticks_msec()

func elapsed_seconds() -> int:
	return mini(60, maxi(0, int((Time.get_ticks_msec() - started) / 1000))) if started > 0 else 0

func start(preferences: Dictionary) -> void:
	if transcribing:
		stop()
		owner._status("Transcriere anulată.")
		return
	if listening:
		finish(preferences)
		return
	backend = int(preferences.get("voice_backend", 0))
	if backend == 1:
		var url = Common.parse_url(str(preferences.get("voice_url", "")), bool(preferences.get("voice_allow_http", false)))
		if not url.get("ok", false):
			owner._status("Configurează endpointul de transcriere din Setări → Voce.")
			return
	native_session = owner.plugin.has_method("speech_request") and (backend == 0 or OS.has_feature("android"))
	if backend == 0 and not native_session:
		owner._status("Dictarea Android necesită APK-ul; pe desktop configurează endpointul Whisper.")
		return
	request_id += 1
	cancel = {"cancelled": false}
	record_preferences = preferences.duplicate(true)
	started = 0
	level = 0.0
	if native_session:
		native_token = Common.uid()
		_phase("permission")
		var response: Dictionary = owner.plugin.speech_request("start" if backend == 0 else "record_start", {"language": preferences.get("voice_language", "ro"), "client": native_token})
		if response.has("error") or not response.get("ok", false):
			_fail(str(response.get("error", "Serviciul vocal Android nu este disponibil în acest APK.")))
			return
		owner._status("Pregătesc microfonul. Confirmă permisiunea Android dacă este cerută.")
		return
	previous_audio_input = ProjectSettings.get_setting("audio/driver/enable_input", false)
	ProjectSettings.set_setting("audio/driver/enable_input", true)
	bus = AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Godot AI Voice")
	AudioServer.set_bus_mute(bus, true)
	recorder = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(bus, recorder)
	player = AudioStreamPlayer.new()
	player.stream = AudioStreamMicrophone.new()
	player.bus = "Godot AI Voice"
	owner.add_child(player)
	recorder.set_recording_active(true)
	player.play()
	_phase("recording")
	owner._status("Înregistrez · maximum 60 secunde. Oprește pentru transcriere sau anulează.")

func poll(_preferences: Dictionary) -> void:
	if phase == "idle": return
	if native_session:
		for _event in 8:
			var event: Dictionary = owner.plugin.speech_request("poll", {})
			if event.has("client") and str(event["client"]) != native_token: continue
			if event.has("error"):
				_fail(str(event["error"]))
				return
			if event.get("cancelled", false):
				stop()
				owner._status("Înregistrare anulată.")
				return
			if event.has("text"):
				_accept_text(str(event["text"]))
				native_session = false
				_phase("idle")
				return
			if event.has("audio_base64"):
				native_session = false
				_transcribe(Marshalls.base64_to_raw(str(event["audio_base64"])), record_preferences, request_id)
				return
			if event.has("state"):
				_phase(str(event["state"]))
				if phase == "recording": owner._status("Înregistrez · maximum 60 secunde. Oprește pentru transcriere sau anulează.")
			elif event.has("level"):
				level = clampf(float(event["level"]), 0, 1)
				break
			else: break
	if phase == "recording" and elapsed_seconds() >= 60: finish(record_preferences)

func stop() -> void:
	request_id += 1
	cancel["cancelled"] = true
	_phase("idle")
	level = 0.0
	if native_session and owner != null and owner.plugin.has_method("speech_request"): owner.plugin.speech_request("cancel", {"client": native_token})
	native_session = false
	_cleanup()

func _fail(message: String) -> void:
	stop()
	owner._status(message)

func finish(_preferences: Dictionary) -> void:
	if not listening: return
	if native_session:
		owner.plugin.speech_request("stop" if backend == 0 else "record_stop", {"client": native_token})
		_phase("transcribing")
		owner._status("Transcriu înregistrarea…")
		return
	recorder.set_recording_active(false)
	var audio = recorder.get_recording()
	_cleanup()
	if audio == null or audio.get_data().is_empty():
		_fail("Microfonul nu a furnizat audio. Verifică permisiunea și dispozitivul de intrare.")
		return
	_transcribe(wav_16k(audio.get_data(), audio.mix_rate, 2 if audio.stereo else 1), record_preferences, request_id)

func _transcribe(wav: PackedByteArray, preferences: Dictionary, expected_request: int) -> void:
	if wav.size() < 46 or wav.size() > 1920044 or wav.slice(0, 4).get_string_from_ascii() != "RIFF":
		_fail("Înregistrarea audio este goală sau invalidă.")
		return
	_phase("transcribing")
	var boundary = "GodotAI" + Common.uid()
	var body = PackedByteArray()
	for pair in [["model", preferences.get("voice_model", "")], ["language", preferences.get("voice_language", "ro")]]:
		if not str(pair[1]).is_empty(): body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % [boundary, pair[0], pair[1]]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voice.wav\"\r\nContent-Type: audio/wav\r\n\r\n" % boundary).to_utf8_buffer())
	body.append_array(wav)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var headers = PackedStringArray(["Content-Type: multipart/form-data; boundary=" + boundary])
	var key = vault.read("transcription")
	if not key.is_empty(): headers.append("Authorization: Bearer " + key)
	owner._status("Transcriu înregistrarea…")
	var transcription_cancel = cancel
	var result = await transport.request(str(preferences["voice_url"]), HTTPClient.METHOD_POST, headers, body, {"allow_http": preferences.get("voice_allow_http", false), "cancel": transcription_cancel})
	if expected_request != request_id or transcription_cancel.get("cancelled", false): return
	_phase("idle")
	if result.get("ok", false) and result.get("json") is Dictionary and result["json"].get("text") is String:
		_accept_text(str(result["json"]["text"]))
	else: owner._status(str(result.get("error", "Endpointul nu a returnat textul transcris.")))

func _accept_text(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		owner._status("Nu am detectat vorbire.")
		return
	var input = owner.composer
	var previous = input.text
	var line = input.get_caret_line()
	var column = input.get_caret_column()
	var at_end = line == input.get_line_count() - 1 and column == input.get_line(line).length()
	input.deselect()
	input.set_caret_line(input.get_line_count() - 1)
	input.set_caret_column(input.get_line(input.get_line_count() - 1).length())
	input.insert_text_at_caret((" " if not previous.is_empty() and not previous.right(1) in [" ", "\t", "\n", "\r"] else "") + text)
	if not at_end:
		input.set_caret_line(line)
		input.set_caret_column(column)
	owner._status("Transcriere gata. Verifică textul înainte de trimitere.")

func _cleanup() -> void:
	if is_instance_valid(player): player.queue_free()
	player = null
	if bus >= 0 and bus < AudioServer.bus_count and AudioServer.get_bus_name(bus) == "Godot AI Voice": AudioServer.remove_bus(bus)
	bus = -1
	recorder = null
	if previous_audio_input != null:
		ProjectSettings.set_setting("audio/driver/enable_input", previous_audio_input)
		previous_audio_input = null

static func wav_16k(pcm: PackedByteArray, rate: int, channels: int) -> PackedByteArray:
	var source_frames = pcm.size() / (2 * channels)
	var count = mini(960000, int(source_frames * 16000.0 / maxi(rate, 1)))
	var samples = PackedByteArray()
	samples.resize(count * 2)
	for index in range(count):
		var position = minf(index * rate / 16000.0, maxf(0, source_frames - 1))
		var left = int(position)
		var right = mini(left + 1, source_frames - 1)
		var value = 0.0
		for channel in range(channels): value += lerpf(pcm.decode_s16((left * channels + channel) * 2), pcm.decode_s16((right * channels + channel) * 2), position - left)
		samples.encode_s16(index * 2, clampi(roundi(value / channels), -32768, 32767))
	var header = PackedByteArray()
	header.resize(44)
	for entry in [[0, "RIFF"], [8, "WAVE"], [12, "fmt "], [36, "data"]]:
		var text = str(entry[1]).to_ascii_buffer()
		for offset in range(4): header[int(entry[0]) + offset] = text[offset]
	header.encode_u32(4, 36 + samples.size())
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)
	header.encode_u16(22, 1)
	header.encode_u32(24, 16000)
	header.encode_u32(28, 32000)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(40, samples.size())
	header.append_array(samples)
	return header
