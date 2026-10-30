extends RefCounted

class VoiceBridge:
	extends RefCounted
	var events: Array = []
	var calls: Array = []
	var client = ""
	var immediate_error = false
	func speech_request(action: String, args: Dictionary) -> Dictionary:
		calls.append(action)
		if action == "start":
			client = str(args.get("client", ""))
			if immediate_error: return {"error": "Fixture denied microphone"}
		if action == "poll": return events.pop_front() if not events.is_empty() else {"client": client, "level": 0.3}
		return {"ok": true}
	func emit_event(value: Dictionary) -> void:
		value["client"] = client
		events.append(value)

class VoiceHost:
	extends Node
	var plugin = VoiceBridge.new()
	var composer = TextEdit.new()
	var status = ""
	func _status(text: String) -> void: status = text

class VoiceVault:
	extends RefCounted
	func read(_id: String) -> String: return ""

class TranscriptionTransport:
	extends RefCounted
	var owner: Node
	var calls = 0
	var body = PackedByteArray()
	var response = {"ok": true, "json": {"text": "copac nou"}}
	func request(_url: String, _method: int, _headers: PackedStringArray, data: PackedByteArray, _options: Dictionary) -> Dictionary:
		calls += 1
		body = data
		await owner.get_tree().process_frame
		return response

func run(host, scripts: Dictionary) -> void:
	var owner = VoiceHost.new()
	host.root.add_child(owner)
	owner.add_child(owner.composer)
	var service = scripts["speech"].new(owner, VoiceVault.new())
	owner.composer.text = "Salut"
	owner.composer.set_caret_column(1)
	service.start({})
	host.check(service.phase == "permission" and service.listening and not service.transcribing, "Voice waits for permission without pretending to record")
	host.check(owner.plugin.calls.back() == "start" and not owner.plugin.client.is_empty(), "Native dictation has an isolated client token")
	owner.plugin.emit_event({"state": "starting"})
	service.poll({})
	host.check(service.listening and service.started == 0, "Recognizer startup does not consume the recording timer before audio is ready")
	owner.plugin.emit_event({"state": "recording"})
	service.poll({})
	host.check(service.phase == "recording" and service.started > 0 and is_equal_approx(service.level, 0.3), "Microphone readiness starts the real timer and level")
	owner.plugin.emit_event({"state": "transcribing"})
	service.poll({})
	host.check(service.transcribing and not service.listening, "Stopping speech exposes transcription as a separate cancellable phase")
	owner.plugin.emit_event({"text": " lume "})
	service.poll({})
	host.check(owner.composer.text == "Salut lume" and service.phase == "idle", "Dictation appends the final text to the existing draft")
	host.check(owner.composer.get_caret_column() == 1 and not owner.composer.has_focus(), "Dictation preserves an existing edit position and never opens the keyboard")
	service.start({})
	var previous_client = owner.plugin.client
	service.stop()
	host.check(service.phase == "idle" and owner.plugin.calls.back() == "cancel", "Cancel immediately releases the native voice session")
	service.start({})
	host.check(previous_client != owner.plugin.client, "Restarting dictation cannot reuse a cancelled client identity")
	owner.plugin.events.append({"client": previous_client, "text": "STALE"})
	owner.plugin.emit_event({"text": "nou"})
	service.poll({})
	host.check(owner.composer.text == "Salut lume nou", "Late transcription from an old session cannot alter the draft")
	owner.plugin.immediate_error = true
	service.start({})
	host.check(service.phase == "idle" and not service.listening and "denied" in owner.status, "A native permission/start error never leaves the microphone stuck active")
	owner.plugin.immediate_error = false
	service.start({})
	owner.plugin.emit_event({"cancelled": true})
	service.poll({})
	host.check(service.phase == "idle" and "anulată" in owner.status, "Leaving the Android activity cancels the pending voice UI")
	var transport = TranscriptionTransport.new()
	transport.owner = owner
	service.transport = transport
	var pcm = PackedByteArray([0, 0, 1, 0, 2, 0, 3, 0])
	var wav = scripts["speech"].wav_16k(pcm, 16000, 1)
	var preferences = {"voice_url": "https://fixture.invalid/audio/transcriptions", "voice_model": "fixture", "voice_language": "ro"}
	service.cancel = {"cancelled": false}
	service._transcribe(wav, preferences, service.request_id)
	host.check(service.transcribing and transport.calls == 1, "Recorded audio enters the configured transcription flow once")
	owner.composer.text = "Ciornă editată în timpul transcrierii"
	await host.process_frame
	await host.process_frame
	host.check(owner.composer.text == "Ciornă editată în timpul transcrierii copac nou" and service.phase == "idle", "Transcription merges with the current draft instead of overwriting edits made while waiting")
	var wav_offset = transport.body.find(82)
	host.check(transport.body.get_string_from_ascii().contains("audio/wav") and wav_offset >= 0 and transport.body.slice(wav_offset, wav_offset + wav.size()) == wav, "The endpoint receives the actual WAV in a multipart upload")
	service.cancel = {"cancelled": false}
	service._transcribe(wav, preferences, service.request_id)
	var saved_draft = owner.composer.text
	service.stop()
	await host.process_frame
	await host.process_frame
	host.check(owner.composer.text == saved_draft and service.phase == "idle", "Cancelled endpoint results cannot append or reactivate the voice UI")
	var calls = transport.calls
	service._transcribe(PackedByteArray(), preferences, service.request_id)
	host.check(service.phase == "idle" and transport.calls == calls, "An invalid recording never starts a transcription request")
	service.stop()
	owner.free()
