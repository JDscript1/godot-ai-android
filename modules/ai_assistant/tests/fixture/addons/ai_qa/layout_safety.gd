extends RefCounted

func run(qa: EditorPlugin, panel: Control, output: String) -> void:
	var old_lock = panel.chat.workspace_expanded
	var old_global = EditorInterface.is_distraction_free_mode_enabled()
	panel.chat.set_workspace_expanded(false)
	panel.hide()
	EditorInterface.set_distraction_free_mode(true)
	for frame in range(4): await qa.get_tree().process_frame
	qa._check(not panel.chat.workspace_expanded, "A hidden assistant never adopts another main tab's distraction-free lock")
	EditorInterface.set_distraction_free_mode(old_global)
	panel.chat.set_workspace_expanded(old_lock)
	panel.show()
	var box = VBoxContainer.new()
	box.position = Vector2(10, 70)
	box.size = Vector2(minf(1440, panel.get_viewport_rect().size.x - 20), 330)
	qa.add_child(box)
	var view = panel.ChatView.new()
	box.add_child(view)
	view.show_history(false)
	view.set_context(32768, 32768)
	var rows = []
	for index in 20: rows.append({"text": "Queued test " + str(index), "selection": {}})
	view.show_queue(rows, true, false)
	for frame in range(12): await qa.get_tree().process_frame
	view.queue_scroll.scroll_vertical = int(view.queue_scroll.get_v_scroll_bar().max_value)
	for frame in range(6): await qa.get_tree().process_frame
	var last: Control = view.queue_rows.get_child(19)
	qa._check(view.queue_scroll.size.y >= last.get_combined_minimum_size().y, "A short chat reserves at least one complete queue card instead of clipping its controls")
	qa._check(view.queue_scroll.get_global_rect().grow(1).encloses(last.get_global_rect()), "The last queued card remains fully reachable in a 330-pixel chat allocation")
	qa._check(view.scroll.size.y >= minf(80 * EditorInterface.get_editor_scale(), view.size.y * 0.15), "A compact queue preserves a usable conversation area while reclaiming layout space")
	qa._check(view.get_global_rect().grow(1).encloses(view.compose_panel.get_global_rect()), "Compact queue sizing preserves the complete composer")
	if not output.is_empty():
		panel.Common.atomic_json(output.path_join("compact-queue.json"), {"chat": str(view.get_global_rect()), "queue": str(view.queue_scroll.get_global_rect()), "last": str(last.get_global_rect()), "conversation": view.scroll.size.y, "row_minimum": last.get_combined_minimum_size().y})
	view.show_queue([], false, false)
	for frame in range(4): await qa.get_tree().process_frame
	qa._check(view.scroll.get_parent().custom_minimum_size.y == 0, "Removing the queue releases its temporary conversation minimum")
	box.queue_free()
	await qa.get_tree().process_frame
