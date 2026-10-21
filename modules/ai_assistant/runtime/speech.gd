@tool
extends RefCounted
static var Common: GDScript
static var Transport: GDScript
var owner: Node
var vault: RefCounted
var transport: RefCounted
var listening = false
var recorder: AudioEffectRecord
var player: AudioStreamPlayer
var bus = -1
var started = 0
var cancel = {}
var backend = 0
var previous_audio_input: Variant = null

func _init(panel: Node = null, secrets: RefCounted = null) -> void:
	owner = panel
	vault = secrets
	transport = Transport.new(panel)

func start(preferences: Dictionary) -> void:
	if listening:
		await finish(preferences)
		return
	backend = int(preferences.get("voice_backend", 0))
	cancel = {"cancelled": false}
	if backend == 0:
		if not owner.plugin.has_method("speech_request"):
			owner._status("Dictarea Android necesită APK-ul; pe desktop configurează endpointul Whisper.")
			return
		owner.plugin.speech_request("start", {"language": preferences.get("voice_language", "ro"), "on_device": true})
		listening = true
		started = Time.get_ticks_msec()
		owner._status("Dictare · vorbește, apoi apasă din nou microfonul.")
	else:
		var url = Common.parse_url(str(preferences.get("voice_url", "")), bool(preferences.get("voice_allow_http", false)))
		if not url.get("ok", false):
			owner._status("Configurează endpointul de transcriere din Setări → Voce.")
			return
		if OS.has_feature("android") and owner.plugin.has_method("speech_request"):
			var permission: Dictionary = owner.plugin.speech_request("permission", {})
			if not permission.get("granted", false):
				owner._status("Permite microfonul în dialogul Android, apoi apasă din nou microfonul.")
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
		listening = true
		started = Time.get_ticks_msec()
		owner._status("Înregistrez pentru endpointul configurat · maximum 60 secunde.")

func poll(preferences: Dictionary) -> void:
	if not listening: return
	if backend == 0 and owner.plugin.has_method("speech_request"):
		var event: Dictionary = owner.plugin.speech_request("poll", {})
		if event.has("text"):
			owner.composer.insert_text_at_caret(str(event["text"]))
			listening = false
			owner._status("Transcriere gata. Verifică textul înainte de trimitere.")
		elif event.has("error"):
			listening = false
			owner._status(str(event["error"]))
	if Time.get_ticks_msec() - started >= 60000: finish(preferences)

func stop() -> void:
	cancel["cancelled"] = true
	listening = false
	if owner != null and owner.plugin.has_method("speech_request"): owner.plugin.speech_request("cancel", {})
	_cleanup()

func finish(preferences: Dictionary) -> void:
	if not listening: return
	if backend == 0:
		owner.plugin.speech_request("stop", {})
		started = Time.get_ticks_msec()
		return
	listening = false
	recorder.set_recording_active(false)
	var audio = recorder.get_recording()
	_cleanup()
	if audio == null or audio.get_data().is_empty():
		owner._status("Microfonul nu a furnizat audio. Verifică permisiunea și dispozitivul de intrare.")
		return
	var wav = wav_16k(audio.get_data(), audio.mix_rate, 2 if audio.stereo else 1)
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
	var result = await transport.request(str(preferences["voice_url"]), HTTPClient.METHOD_POST, headers, body, {"allow_http": preferences.get("voice_allow_http", false), "cancel": cancel})
	if result.get("ok", false) and result.get("json") is Dictionary and result["json"].get("text") is String:
		owner.composer.insert_text_at_caret(str(result["json"]["text"]))
		owner._status("Transcriere gata. Verifică textul înainte de trimitere.")
	else: owner._status(str(result.get("error", "Endpointul nu a returnat textul transcris.")))

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
