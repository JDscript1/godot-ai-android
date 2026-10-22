@tool
extends HBoxContainer
static var Common: GDScript
signal action(name: String, args: Dictionary)
var sidebar: VBoxContainer
var chats: ItemList
var search: LineEdit
var archived: CheckBox
var title: Label
var thread: VBoxContainer
var scroll: ScrollContainer
var composer: TextEdit
var provider_picker: OptionButton
var model_picker: OptionButton
var mode_picker: OptionButton
var effort_picker: OptionButton
var full_control: CheckBox
var send_button: Button
var status: Label
var context_label: Label
var reference_label: Label
var tasks_label: Label
var model_button: Button
var picker: AcceptDialog
var picker_search: LineEdit
var picker_list: ItemList
var catalog: Array = []
var follow_bottom = true
var loaded = 50
var selected_message = ""
var backdrop: GradientTexture2D
var runtime_options: PopupPanel
var options_button: Button
var stop_button: Button
var root_column: VBoxContainer
var compose_panel: PanelContainer
var attachment_chips: HFlowContainer
var expand_button: Button
var activity_group: VBoxContainer
var message_records: Array = []
var restoring = false
var motion_enabled = true
var icon_cache = {}
var status_revision = 0
var streaming_dirty: Array = []
var stream_clock = 0.0
var attachment_signature = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_theme()
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color("171523"), Color("111b2b"), Color("101218")])
	backdrop = GradientTexture2D.new()
	backdrop.gradient = gradient
	backdrop.fill_from = Vector2.ZERO
	backdrop.fill_to = Vector2(1, 1)
	resized.connect(queue_redraw)

	sidebar = VBoxContainer.new()
	sidebar.custom_minimum_size.x = 220 * EditorInterface.get_editor_scale()
	add_child(sidebar)
	button(sidebar, "＋ Conversație nouă", func() -> void: action.emit("new", {}))
	search = LineEdit.new()
	search.placeholder_text = "Caută conversații…"
	sidebar.add_child(search)
	search.text_changed.connect(func(_text: String) -> void: action.emit("history", {}))
	archived = CheckBox.new()
	archived.text = "Arhivate"
	sidebar.add_child(archived)
	archived.toggled.connect(func(_on: bool) -> void: action.emit("history", {}))
	chats = ItemList.new()
	chats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(chats)
	chats.item_selected.connect(func(index: int) -> void: action.emit("open", {"id": chats.get_item_metadata(index)}))
	var history_actions = HFlowContainer.new()
	sidebar.add_child(history_actions)
	for pair in [["☆", "favorite"], ["✎", "rename"], ["Arhivează", "archive"], ["Export", "export"], ["Șterge", "delete"]]:
		button(history_actions, pair[0], func() -> void: action.emit(pair[1], {}))
	root_column = VBoxContainer.new()
	root_column.add_theme_constant_override("separation", int(6 * EditorInterface.get_editor_scale()))
	root_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root_column)
	var header = HBoxContainer.new()
	root_column.add_child(header)
	icon_button(header, "Menu", "Istoricul conversațiilor", func() -> void: sidebar.visible = not sidebar.visible)
	title = label(header, "Conversație nouă")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.hide()
	model_button = button(header, "Conectează un furnizor", _open_picker)
	model_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	model_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_button.clip_text = true
	model_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	icon_button(header, "Add", "Conversație nouă", func() -> void: action.emit("new", {}))
	expand_button = icon_button(header, "Expand", "Extinde / restrânge chatul", _toggle_expanded)
	icon_button(header, "Settings", "Setări", func() -> void: action.emit("settings", {}))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(scroll)
	scroll.resized.connect(_size_messages)
	var center = HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	thread = VBoxContainer.new()
	thread.add_theme_constant_override("separation", int(18 * EditorInterface.get_editor_scale()))
	thread.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(thread)
	scroll.get_v_scroll_bar().value_changed.connect(func(value: float) -> void: follow_bottom = value >= scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page - 60)
	tasks_label = label(root_column, "")
	tasks_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tasks_label.hide()
	reference_label = label(root_column, "")
	reference_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reference_label.hide()
	compose_panel = PanelContainer.new()
	var compose_style = style(Color("1d2130"), 18)
	compose_style.set_content_margin_all(10 * EditorInterface.get_editor_scale())
	compose_style.border_color = Color("35364c")
	compose_style.set_border_width_all(1)
	compose_panel.add_theme_stylebox_override("panel", compose_style)
	root_column.add_child(compose_panel)
	var compose_column = VBoxContainer.new()
	compose_panel.add_child(compose_column)
	attachment_chips = HFlowContainer.new()
	attachment_chips.hide()
	compose_column.add_child(attachment_chips)
	composer = TextEdit.new()
	composer.placeholder_text = "Scrie un mesaj…"
	composer.tooltip_text = "@ fișiere · $ noduri · / comenzi"
	composer.custom_minimum_size.y = 32 * EditorInterface.get_editor_scale()
	composer.custom_maximum_size.y = 112 * EditorInterface.get_editor_scale()
	composer.scroll_fit_content_height = true
	composer.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var input_style = style(Color.TRANSPARENT, 8)
	input_style.set_content_margin_all(3 * EditorInterface.get_editor_scale())
	composer.add_theme_stylebox_override("normal", input_style)
	compose_column.add_child(composer)
	composer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not event.shift_pressed and not OS.has_feature("android"):
			composer.accept_event()
			action.emit("send", {}))
	var controls = HBoxContainer.new()
	compose_column.add_child(controls)
	icon_button(controls, "Add", "Atașează o imagine sau un fișier", func() -> void: action.emit("attach", {}))
	options_button = button(controls, "Analiză ▾", _open_options)
	options_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	options_button.clip_text = false
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	icon_button(controls, "Microphone", "Dictare", func() -> void: action.emit("voice", {}))
	send_button = icon_button(controls, "ArrowUp", "Trimite mesajul", func() -> void: action.emit("send", {}))
	send_button.add_theme_stylebox_override("normal", style(Color("7650c5")))
	stop_button = icon_button(controls, "Stop", "Oprește agentul", func() -> void: action.emit("stop", {}))
	stop_button.hide()
	provider_picker = OptionButton.new()
	model_picker = OptionButton.new()
	for hidden in [provider_picker, model_picker]:
		hidden.hide()
		add_child(hidden)
	runtime_options = PopupPanel.new()
	runtime_options.name = "OpțiuniAgent"
	runtime_options.theme = theme
	add_child(runtime_options)
	var options = VBoxContainer.new()
	options.add_theme_constant_override("separation", int(8 * EditorInterface.get_editor_scale()))
	runtime_options.add_child(options)
	label(options, "Mod de lucru")
	mode_picker = OptionButton.new()
	for mode in Common.MODES: mode_picker.add_item(mode)
	options.add_child(mode_picker)
	label(options, "Nivel de raționament")
	effort_picker = OptionButton.new()
	options.add_child(effort_picker)
	full_control = CheckBox.new()
	full_control.text = "Permite modificări în această sesiune"
	full_control.tooltip_text = "Necesar pentru Confirmare și Autonom. Analiza și Planul rămân doar pentru citire."
	options.add_child(full_control)
	context_label = label(options, "Context: —")
	context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button(options, "Extinde / restrânge chatul", func() -> void:
		EditorInterface.set_distraction_free_mode(not EditorInterface.is_distraction_free_mode_enabled())
		runtime_options.hide())
	status = label(root_column, "")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("b4bdd1"))
	status.hide()
	picker = AcceptDialog.new()
	picker.title = "Furnizori și modele"
	add_child(picker)
	var body = VBoxContainer.new()
	picker.add_child(body)
	picker_search = LineEdit.new()
	picker_search.placeholder_text = "Caută serviciu, profil sau model…"
	body.add_child(picker_search)
	picker_search.text_changed.connect(func(_text: String) -> void: _filter_models())
	picker_list = ItemList.new()
	picker_list.custom_minimum_size = Vector2(260, 300)
	body.add_child(picker_list)
	picker_list.item_activated.connect(_pick_model)
	picker.confirmed.connect(func() -> void:
		var selected = picker_list.get_selected_items()
		if not selected.is_empty(): _pick_model(selected[0]))
	resized.connect(_resize)
	_resize()

func _resize() -> void:
	if sidebar == null: return
	var scale = EditorInterface.get_editor_scale()
	sidebar.visible = size.x / scale >= 900
	_size_messages.call_deferred()

func _size_messages() -> void:
	if thread == null or scroll == null: return
	var scale = EditorInterface.get_editor_scale()
	thread.custom_minimum_size.x = minf(760 * scale, maxf(180, scroll.size.x - 24 * scale))
	for record in message_records:
		if is_instance_valid(record["card"]) and record["role"] == "user": _size_user(record)

func style(color: Color, radius: int = 12) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(radius * EditorInterface.get_editor_scale()))
	box.content_margin_left = 14 * EditorInterface.get_editor_scale()
	box.content_margin_right = 14 * EditorInterface.get_editor_scale()
	box.content_margin_top = 10 * EditorInterface.get_editor_scale()
	box.content_margin_bottom = 10 * EditorInterface.get_editor_scale()
	return box

func _apply_theme() -> void:
	var skin = Theme.new()
	for type in ["Label", "Button", "LineEdit", "TextEdit", "CodeEdit", "OptionButton", "CheckBox", "RichTextLabel", "ItemList"]:
		skin.set_color("font_color", type, Color("e7eaf4"))
		skin.set_color("font_hover_color", type, Color.WHITE)
		skin.set_color("font_selected_color", type, Color.WHITE)
		skin.set_color("font_disabled_color", type, Color("9aa4b4"))
	for type in ["Button", "OptionButton"]:
		skin.set_stylebox("normal", type, style(Color("252939")))
		skin.set_stylebox("hover", type, style(Color("393456")))
		skin.set_stylebox("pressed", type, style(Color("59458c")))
	for type in ["LineEdit", "TextEdit", "ItemList"]:
		var field = style(Color("0d1320"))
		field.border_color = Color("30394e")
		field.set_border_width_all(1)
		skin.set_stylebox("panel" if type == "ItemList" else "normal", type, field)
		skin.set_color("caret_color", type, Color("a78bfa"))
	skin.set_stylebox("panel", "AcceptDialog", style(Color("131723"), 16))
	skin.set_stylebox("panel", "PopupPanel", style(Color("191e2c"), 16))
	skin.set_stylebox("selected", "ItemList", style(Color("393150"), 8))
	var plain = StyleBoxEmpty.new()
	skin.set_stylebox("normal", "RichTextLabel", plain)
	skin.set_stylebox("focus", "RichTextLabel", plain)
	skin.set_stylebox("normal", "CodeEdit", style(Color("0d1320"), 8))
	skin.set_color("background_color", "CodeEdit", Color("0d1320"))
	theme = skin

func button(parent: Node, text: String, callback: Callable) -> Button:
	var control = Button.new()
	control.text = text
	control.custom_minimum_size.y = 44 * EditorInterface.get_editor_scale()
	control.pressed.connect(callback)
	parent.add_child(control)
	return control

func label(parent: Node, text: String) -> Label:
	var control = Label.new()
	control.text = text
	parent.add_child(control)
	return control

func _open_picker() -> void:
	if catalog.is_empty():
		action.emit("settings", {"section": "providers"})
		return
	_filter_models()
	picker.popup_centered_clamped(Vector2i(640, 470), 0.92)
	picker_search.grab_focus()

func _filter_models() -> void:
	picker_list.clear()
	var query = picker_search.text.to_lower()
	for group in ["API cloud", "Abonamente", "Modele locale"]:
		var heading = false
		for profile in catalog:
			var category = "Abonamente" if profile.get("kind") in ["siwc", "companion"] else ("Modele locale" if profile.get("issuer") in ["ollama", "lmstudio", "llamacpp"] else "API cloud")
			if category != group: continue
			for model in profile.get("models", []):
				var text = str(profile["name"]) + " · " + str(model.get("name", model["id"]))
				if not query.is_empty() and not query in (text + " " + str(model["id"])).to_lower(): continue
				if not heading:
					picker_list.add_item("── " + group + " ──")
					picker_list.set_item_disabled(picker_list.item_count - 1, true)
					heading = true
				picker_list.add_item(text)
				picker_list.set_item_metadata(picker_list.item_count - 1, {"profile": profile["id"], "model": model["id"]})
	if picker_list.item_count == 0: label_once("Adaugă un profil și actualizează modelele din Setări → Furnizori.")

func label_once(text: String) -> void:
	picker_list.add_item(text)
	picker_list.set_item_disabled(picker_list.item_count - 1, true)

func _pick_model(index: int) -> void:
	var selected: Variant = picker_list.get_item_metadata(index)
	if not selected is Dictionary: return
	action.emit("model", selected)
	picker.hide()

func refresh_history(entries: Array, active: String) -> void:
	chats.clear()
	for entry in entries:
		chats.add_item(("★ " if entry.get("favorite", false) else "") + str(entry["title"]))
		chats.set_item_metadata(chats.item_count - 1, entry["id"])
		if entry["id"] == active: chats.select(chats.item_count - 1)

func clear_messages() -> void:
	message_records.clear()
	streaming_dirty.clear()
	activity_group = null
	for child in thread.get_children():
		thread.remove_child(child)
		child.queue_free()

func append_message(role: String, text: String, metadata: Dictionary = {}, rich: bool = true) -> RichTextLabel:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thread.add_child(row)
	if role == "user":
		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_END if role == "user" else Control.SIZE_EXPAND_FILL
	var surface = style(Color("2c2940") if role == "user" else Color.TRANSPARENT, 16)
	if role != "user": surface.set_content_margin_all(2 * EditorInterface.get_editor_scale())
	card.add_theme_stylebox_override("panel", surface)
	row.add_child(card)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", int(8 * EditorInterface.get_editor_scale()))
	card.add_child(column)
	if role != "user":
		var heading = label(column, str(metadata.get("origin_label", "Godot AI")))
		heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		heading.add_theme_color_override("font_color", Color("b5a4d9"))
	var body = VBoxContainer.new()
	column.add_child(body)
	var anchor = RichTextLabel.new()
	anchor.hide()
	column.add_child(anchor)
	var record = {"role": role, "row": row, "card": card, "column": column, "body": body, "blocks": [], "text": text, "metadata": metadata.duplicate(true), "rich": rich, "streaming": role == "assistant" and not metadata.has("id")}
	anchor.set_meta("message", record)
	message_records.append(record)
	_render_content(record)
	if role == "user": _size_user(record)
	for attachment in metadata.get("attachments", []):
		if attachment.has("data"):
			var preview = Image.new()
			if preview.load_png_from_buffer(Marshalls.base64_to_raw(str(attachment["data"]))) == OK:
				var picture = TextureRect.new()
				picture.texture = ImageTexture.create_from_image(preview)
				picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				picture.custom_minimum_size.y = 180
				column.add_child(picture)
	if role == "assistant": _message_actions(record)
	activity_group = null
	if motion_enabled and not restoring and is_visible_in_tree():
		row.modulate.a = 0.0
		create_tween().tween_property(row, "modulate:a", 1.0, 0.12)
	_follow.call_deferred()
	return anchor

func _markdown(target: RichTextLabel, text: String) -> void:
	# Construct formatting without interpreting model-supplied BBCode or HTML.
	target.clear()
	var lines = text.strip_edges().split("\n")
	for line_index in range(lines.size()):
		var line = lines[line_index]
		var heading = line.begins_with("#")
		if heading: target.push_bold()
		var pieces = line.trim_prefix("### ").trim_prefix("## ").trim_prefix("# ").split("**")
		for index in range(pieces.size()):
			if index % 2: target.push_bold()
			target.add_text(pieces[index])
			if index % 2: target.pop()
		if heading: target.pop()
		if line_index < lines.size() - 1: target.add_text("\n")

func _size_user(record: Dictionary) -> void:
	var scale = EditorInterface.get_editor_scale()
	var available = maxf(thread.size.x, thread.custom_minimum_size.x)
	var font = get_theme_font("font", "Label")
	var width = 0.0
	for line in str(record["text"]).split("\n"):
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size", "Label")).x)
	var wanted = minf(maxf(64 * scale, width + 30 * scale), available * 0.74)
	if not record["metadata"].get("attachments", []).is_empty(): wanted = minf(320 * scale, available * 0.74)
	record["card"].custom_minimum_size.x = wanted
	record["card"].custom_maximum_size.x = wanted

func _render_content(record: Dictionary) -> void:
	var pieces = str(record["text"]).split("```") if record["rich"] else PackedStringArray([record["text"]])
	var blocks: Array = record["blocks"]
	for index in range(pieces.size()):
		var code_block = index % 2 == 1
		if index >= blocks.size():
			if code_block:
				var box = VBoxContainer.new()
				record["body"].add_child(box)
				var header = HBoxContainer.new()
				box.add_child(header)
				var language = label(header, "GDScript")
				language.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				language.add_theme_color_override("font_color", Color("9faac0"))
				var editor = CodeEdit.new()
				editor.editable = false
				editor.scroll_fit_content_height = true
				editor.custom_minimum_size.y = 54 * EditorInterface.get_editor_scale()
				editor.custom_maximum_size.y = 360 * EditorInterface.get_editor_scale()
				editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var colors = CodeHighlighter.new()
				for word in ["func", "var", "extends", "if", "else", "return", "class_name", "await", "for", "in", "const", "static", "signal", "true", "false", "null"]: colors.add_keyword_color(word, Color("c4a4fc"))
				colors.number_color = Color("91c9eb")
				colors.symbol_color = Color("b5bfd4")
				colors.function_color = Color("91c9eb")
				colors.member_variable_color = Color("e7eaf4")
				colors.add_color_region("\"", "\"", Color("b4d6a3"))
				colors.add_color_region("#", "", Color("7e8ba0"), true)
				editor.syntax_highlighter = colors
				icon_button(header, "Copy", "Copiază codul", func() -> void: DisplayServer.clipboard_set(editor.text))
				box.add_child(editor)
				blocks.append({"node": box, "editor": editor, "language": language})
			else:
				var text = RichTextLabel.new()
				text.fit_content = true
				text.scroll_active = false
				text.selection_enabled = true
				text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				record["body"].add_child(text)
				blocks.append({"node": text})
		var block: Dictionary = blocks[index]
		if code_block:
			var source = pieces[index]
			block["language"].text = source.get_slice("\n", 0).strip_edges() if "\n" in source else "Cod"
			block["editor"].text = (source.substr(source.find("\n") + 1) if "\n" in source else source).trim_suffix("\n")
		else:
			_markdown(block["node"], pieces[index])
			block["node"].visible = not pieces[index].strip_edges().is_empty()
	while blocks.size() > pieces.size():
		var stale = blocks.pop_back()["node"]
		record["body"].remove_child(stale)
		stale.queue_free()

func stream_text(anchor: RichTextLabel, piece: String) -> void:
	if not is_instance_valid(anchor) or not anchor.has_meta("message"): return
	var record: Dictionary = anchor.get_meta("message")
	record["text"] += piece
	if not streaming_dirty.has(anchor): streaming_dirty.append(anchor)

func finish_stream(anchor: RichTextLabel, metadata: Dictionary) -> void:
	if not is_instance_valid(anchor) or not anchor.has_meta("message"): return
	var record: Dictionary = anchor.get_meta("message")
	record["metadata"] = metadata.duplicate(true)
	record["streaming"] = false
	record["text"] = str(metadata.get("content", record["text"]))
	streaming_dirty.erase(anchor)
	_render_content(record)
	for control in record.get("actions", []): control.disabled = false

func _process(delta: float) -> void:
	stream_clock += delta
	if stream_clock < 0.08 or streaming_dirty.is_empty(): return
	stream_clock = 0.0
	for anchor in streaming_dirty:
		if is_instance_valid(anchor): _render_content(anchor.get_meta("message"))
	streaming_dirty.clear()
	_follow.call_deferred()

func _message_actions(record: Dictionary) -> void:
	var actions = HBoxContainer.new()
	record["column"].add_child(actions)
	record["actions"] = []
	for pair in [["Copy", "Copiază răspunsul", "copy"], ["Retry", "Continuă răspunsul", "retry"], ["Changes", "Modificări / Undo", "changes"]]:
		var control = icon_button(actions, pair[0], pair[1], func() -> void: _message_action(record, pair[2]))
		control.disabled = record["streaming"]
		record["actions"].append(control)
	var more = MenuButton.new()
	more.icon = _icon("More")
	more.tooltip_text = "Mai multe acțiuni"
	more.custom_minimum_size = Vector2(44, 44) * EditorInterface.get_editor_scale()
	more.get_popup().add_item("Ramifică de aici", 0)
	if record["metadata"].get("plan", false): more.get_popup().add_item("Aplică planul", 1)
	more.get_popup().id_pressed.connect(func(id: int) -> void: _message_action(record, "fork" if id == 0 else "apply_plan"))
	more.disabled = record["streaming"]
	record["actions"].append(more)
	actions.add_child(more)

func _message_action(record: Dictionary, name: String) -> void:
	var metadata: Dictionary = record["metadata"]
	if metadata.has("id"): action.emit(name, {"message": metadata["id"], "turn": metadata.get("turn_id", "")})

func activity(text: String, details: String = "") -> void:
	if not is_instance_valid(activity_group):
		activity_group = VBoxContainer.new()
		thread.add_child(activity_group)
		var entries = VBoxContainer.new()
		var toggle = button(activity_group, "Activitate", func() -> void: entries.visible = not entries.visible)
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		activity_group.add_child(entries)
		entries.hide()
		activity_group.set_meta("entries", entries)
		activity_group.set_meta("toggle", toggle)
	var entries: VBoxContainer = activity_group.get_meta("entries")
	var column = VBoxContainer.new()
	entries.add_child(column)
	var body = label(column, details.left(12000))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.hide()
	var toggle = button(column, "› " + text, func() -> void: body.visible = not body.visible)
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.move_child(toggle, 0)
	activity_group.get_meta("toggle").text = "Activitate · %s operații  ▾" % entries.get_child_count()
	_follow.call_deferred()

func _follow() -> void:
	if follow_bottom and is_instance_valid(scroll): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func _draw() -> void:
	if backdrop != null: draw_texture_rect(backdrop, Rect2(Vector2.ZERO, size), false)

func icon_button(parent: Node, icon_name: String, hint: String, callback: Callable) -> Button:
	var control = button(parent, "", callback)
	control.icon = _icon(icon_name)
	control.add_theme_constant_override("icon_max_width", int(20 * EditorInterface.get_editor_scale()))
	control.tooltip_text = hint
	control.custom_minimum_size = Vector2(44, 44) * EditorInterface.get_editor_scale()
	control.add_theme_stylebox_override("normal", style(Color.TRANSPARENT, 10))
	return control

func _icon(name: String) -> Texture2D:
	if icon_cache.has(name): return icon_cache[name]
	var paths = {"Add": "M12 5v14M5 12h14", "ArrowUp": "m6 12 6-6 6 6M12 6v13", "Stop": "M6 6h12v12H6Z", "Microphone": "M9 5a3 3 0 0 1 6 0v6a3 3 0 0 1-6 0ZM6 10v1a6 6 0 0 0 12 0v-1M12 17v4M8 21h8", "Menu": "M4 6h16M4 12h16M4 18h16", "Settings": "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1Z", "Expand": "M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5", "Copy": "M8 8h12v12H8ZM16 4H4v12", "Retry": "M4 11a8 8 0 1 1 2 7M4 4v7h7", "More": "M5 11h1v2H5ZM11 11h1v2h-1ZM17 11h1v2h-1Z", "Changes": "M8 3H4v18h16V7l-4-4H8ZM8 11h8M8 15h8M12 8v6", "Close": "m6 6 12 12M18 6 6 18"}
	var image = Image.new()
	var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 24 24"><path d="%s" fill="none" stroke="#dce1ef" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>' % [int(24 * EditorInterface.get_editor_scale()), int(24 * EditorInterface.get_editor_scale()), paths.get(name, paths["More"])]
	image.load_svg_from_string(svg)
	icon_cache[name] = ImageTexture.create_from_image(image)
	return icon_cache[name]

func _toggle_expanded() -> void:
	EditorInterface.set_distraction_free_mode(not EditorInterface.is_distraction_free_mode_enabled())

func show_status(message: String, working: bool = false) -> void:
	status_revision += 1
	var revision = status_revision
	status.text = message
	status.modulate.a = 1.0
	status.visible = not message.is_empty()
	if working or message.is_empty(): return
	await get_tree().create_timer(4.0).timeout
	if revision == status_revision: status.hide()

func show_attachments(images: Array, references: Array) -> void:
	var signature = JSON.stringify(images.map(func(item: Dictionary) -> String: return str(item.get("name", "")) + str(str(item.get("data", "")).length()))) + JSON.stringify(references)
	if signature == attachment_signature: return
	attachment_signature = signature
	for child in attachment_chips.get_children():
		attachment_chips.remove_child(child)
		child.queue_free()
	for kind in ["image", "reference"]:
		var values = images if kind == "image" else references
		for index in range(values.size()):
			var item: Variant = values[index]
			var name = str(item.get("name", "Imagine")) if item is Dictionary else str(item).get_file()
			var chip = button(attachment_chips, name.left(22) + "  ×", func() -> void: action.emit("remove_attachment", {"kind": kind, "index": index}))
			chip.tooltip_text = name + " · elimină atașamentul"
			if item is Dictionary and item.has("data"):
				var preview = Image.new()
				if preview.load_png_from_buffer(Marshalls.base64_to_raw(item["data"])) == OK:
					chip.icon = ImageTexture.create_from_image(preview)
					chip.add_theme_constant_override("icon_max_width", int(28 * EditorInterface.get_editor_scale()))
	attachment_chips.visible = attachment_chips.get_child_count() > 0

func _open_options() -> void:
	var wanted = Vector2i(330, 270) * EditorInterface.get_editor_scale()
	var window = get_window()
	runtime_options.size = Vector2i(mini(wanted.x, window.size.x - 32), mini(wanted.y, window.size.y - 32))
	var origin = Vector2i(options_button.get_global_rect().position) + window.position
	runtime_options.position = Vector2i(clampi(origin.x, window.position.x + 12, window.position.x + window.size.x - runtime_options.size.x - 12), maxi(window.position.y + 12, origin.y - runtime_options.size.y - 8))
	runtime_options.popup()

func set_working(working: bool) -> void:
	if stop_button != null: stop_button.visible = working
	if options_button != null and mode_picker != null and mode_picker.selected >= 0:
		options_button.text = ["Analiză", "Confirmă", "Autonom", "Plan"][mode_picker.selected] + " ▾"

func show_welcome() -> void:
	thread.alignment = BoxContainer.ALIGNMENT_CENTER
	var heading = label(thread, "Ce construim astăzi?")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", int(24 * EditorInterface.get_editor_scale()))
	var hint = label(thread, "Trimite un mesaj sau atașează un fișier din proiect.")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("abb5c9"))
