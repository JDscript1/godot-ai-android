@tool
extends RefCounted

func run(host: Node, panel: Control) -> void:
	var chat = panel.chat
	var draft = panel.composer.text
	panel.composer.text = "O pădure cu poteci și copaci"
	# Use a real positive start tick. A short, focused scenario can finish before
	# the editor has twelve seconds of uptime; backdating then creates no session.
	panel.speech.started = maxi(1, Time.get_ticks_msec())
	panel.speech.level = 0.7
	panel.speech._phase("recording")
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	host._check(chat.voice_strip.visible and not chat.input_row.visible and not chat.composer_controls.visible, "Recording replaces the input controls without adding a second toolbar")
	# Rendering may cross a second boundary on a busy CI runner. Inspect the
	# timer format instead of requiring one exact wall-clock second.
	var clock = chat.voice_state.text.get_slice(" ", 1)
	var seconds = clock.get_slice(":", 1)
	var elapsed_visible = clock.begins_with("00:") and seconds.length() == 2 and seconds.is_valid_int() and int(seconds) >= 0 and int(seconds) < 60
	host._check(elapsed_visible and chat.voice_state.text.ends_with(" / 01:00") and chat.voice_finish.visible and chat.voice_wave.visible, "Voice UI shows elapsed recording, level and a distinct stop action")
	host._check(chat.compose_panel.get_global_rect().encloses(chat.voice_strip.get_global_rect()), "Voice controls fit entirely inside the responsive composer")
	await RenderingServer.frame_post_draw
	var output = OS.get_environment("GODOT_AI_QA_OUTPUT")
	if not output.is_empty(): panel.get_viewport().get_texture().get_image().save_png(output.path_join("voice-recording.png"))
	panel.speech._phase("transcribing")
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	host._check(chat.voice_strip.visible and chat.voice_state.text == "Transcriu…" and not chat.voice_finish.visible, "Transcription remains cancellable without offering a duplicate recording stop")
	chat.action.emit("voice_cancel", {})
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	host._check(not chat.voice_strip.visible and chat.input_row.visible and chat.composer_controls.visible, "Cancelling restores the normal composer")
	host._check(panel.composer.text == "O pădure cu poteci și copaci" and panel.speech.phase == "idle", "Voice cancellation preserves the entire draft")
	panel.composer.text = draft
	panel._status("")
