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
var root_column: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apply_theme()
	var gradient = Gradient.new()
	gradient.colors = PackedColorArray([Color("251a3c"), Color("142139"), Color("111318")])
	backdrop = GradientTexture2D.new()
	backdrop.gradient = gradient
	backdrop.fill_from = Vector2.ZERO
	backdrop.fill_to = Vector2(1, 1)
	resized.connect(queue_redraw)

	sidebar = VBoxContainer.new()
	sidebar.custom_minimum_size.x = 220
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
	root_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root_column)
	var header = HBoxContainer.new()
	root_column.add_child(header)
	button(header, "☰", func() -> void: sidebar.visible = not sidebar.visible)
	title = label(header, "Conversație nouă")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button(header, "＋", func() -> void: action.emit("new", {}))
	button(header, "⚙ Setări", func() -> void: action.emit("settings", {}))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(scroll)
	scroll.resized.connect(_size_messages)
	var center = HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	thread = VBoxContainer.new()
	thread.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(thread)
	scroll.get_v_scroll_bar().value_changed.connect(func(value: float) -> void: follow_bottom = value >= scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page - 60)
	tasks_label = label(root_column, "")
	tasks_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reference_label = label(root_column, "")
	reference_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var compose_panel = PanelContainer.new()
	compose_panel.add_theme_stylebox_override("panel", style(Color("202331"), 20))
	root_column.add_child(compose_panel)
	var compose_column = VBoxContainer.new()
	compose_panel.add_child(compose_column)
	composer = TextEdit.new()
	composer.placeholder_text = "Ce construim în Godot? @fișiere · $noduri · /comenzi"
	composer.custom_minimum_size.y = 92
	composer.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	composer.add_theme_stylebox_override("normal", style(Color.TRANSPARENT, 12))
	compose_column.add_child(composer)
	composer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not event.shift_pressed and not OS.has_feature("android"):
			composer.accept_event()
			action.emit("send", {}))
	var controls = HFlowContainer.new()
	compose_column.add_child(controls)
	button(controls, "＋", func() -> void: action.emit("attach", {}))
	model_button = button(controls, "Alege furnizor / model ▾", _open_picker)
	model_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	model_button.custom_minimum_size.x = 170
	provider_picker = OptionButton.new()
	model_picker = OptionButton.new()
	for hidden in [provider_picker, model_picker]:
		hidden.hide()
		add_child(hidden)
	mode_picker = OptionButton.new()
	for mode in Common.MODES: mode_picker.add_item(mode)
	controls.add_child(mode_picker)
	effort_picker = OptionButton.new()
	controls.add_child(effort_picker)
	full_control = CheckBox.new()
	full_control.text = "Control complet"
	full_control.tooltip_text = "Permisiune pentru sesiunea curentă."
	controls.add_child(full_control)
	button(controls, "Voce", func() -> void: action.emit("voice", {}))
	send_button = button(controls, "↑ Trimite", func() -> void: action.emit("send", {}))
	button(controls, "■", func() -> void: action.emit("stop", {}))
	context_label = label(root_column, "Context · —")
	status = label(root_column, "")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	if model_button != null: model_button.custom_minimum_size.x = minf(260, maxf(150, size.x / scale - 100))
	_size_messages.call_deferred()

func _size_messages() -> void:
	if thread == null or scroll == null: return
	var scale = EditorInterface.get_editor_scale()
	thread.custom_minimum_size.x = minf(760 * scale, maxf(180, scroll.size.x - 24 * scale))

func style(color: Color, radius: int = 12) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

func _apply_theme() -> void:
	var skin = Theme.new()
	for type in ["Label", "Button", "LineEdit", "TextEdit", "OptionButton", "CheckBox", "RichTextLabel", "ItemList"]:
		skin.set_color("font_color", type, Color("e7eaf4"))
		skin.set_color("font_hover_color", type, Color.WHITE)
		skin.set_color("font_selected_color", type, Color.WHITE)
		skin.set_color("font_disabled_color", type, Color("9aa4b4"))
	for type in ["Button", "OptionButton"]:
		skin.set_stylebox("normal", type, style(Color("252939")))
		skin.set_stylebox("hover", type, style(Color("393456")))
		skin.set_stylebox("pressed", type, style(Color("59458c")))
	for type in ["LineEdit", "TextEdit", "ItemList"]:
		skin.set_stylebox("normal", type, style(Color("191c26")))
		skin.set_color("caret_color", type, Color("a78bfa"))
	skin.set_stylebox("normal", "RichTextLabel", style(Color.TRANSPARENT, 0))
	theme = skin

func button(parent: Node, text: String, callback: Callable) -> Button:
	var control = Button.new()
	control.text = text
	control.custom_minimum_size.y = 44
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
		action.emit("settings", {})
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
	for child in thread.get_children():
		thread.remove_child(child)
		child.queue_free()

func append_message(role: String, text: String, metadata: Dictionary = {}, rich: bool = true) -> RichTextLabel:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", style(Color("282c3c") if role == "user" else Color(0, 0, 0, 0.12), 16))
	thread.add_child(card)
	var column = VBoxContainer.new()
	card.add_child(column)
	var origin = "Tu" if role == "user" else str(metadata.get("origin_label", "Godot AI"))
	var heading = label(column, origin)
	heading.add_theme_color_override("font_color", Color("bca8ef") if role != "user" else Color("b5c5e6"))
	var last: RichTextLabel = null
	var blocks = text.split("```") if rich else PackedStringArray([text])
	for index in range(blocks.size()):
		var block = blocks[index]
		if index % 2 == 1:
			var language = block.get_slice("\n", 0)
			var code = block.substr(block.find("\n") + 1) if "\n" in block else block
			var code_header = HBoxContainer.new()
			column.add_child(code_header)
			label(code_header, language)
			button(code_header, "Copiază cod", func() -> void: DisplayServer.clipboard_set(code))
			var editor = CodeEdit.new()
			editor.editable = false
			editor.text = code.strip_edges()
			editor.custom_minimum_size.y = clampf(code.count("\n") * 22 + 42, 64, 360)
			editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var colors = CodeHighlighter.new()
			for word in ["func", "var", "extends", "if", "else", "return", "class_name", "await", "for", "in", "const", "static", "signal"]: colors.add_keyword_color(word, Color("c4a4fc"))
			editor.syntax_highlighter = colors
			column.add_child(editor)
		else:
			last = RichTextLabel.new()
			last.fit_content = true
			last.scroll_active = false
			last.selection_enabled = true
			last.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.add_child(last)
			_markdown(last, block)
	if last == null:
		last = RichTextLabel.new()
		column.add_child(last)
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
	if role == "assistant" and metadata.has("id"):
		var row = HFlowContainer.new()
		column.add_child(row)
		for pair in [["Copiază", "copy"], ["Continuă", "retry"], ["Ramifică", "fork"], ["Modificări / Undo", "changes"]]:
			button(row, pair[0], func() -> void: action.emit(pair[1], {"message": metadata["id"], "turn": metadata.get("turn_id", "")}))
		if metadata.get("plan", false): button(row, "Aplică planul", func() -> void: action.emit("apply_plan", {"message": metadata["id"]}))
	_follow.call_deferred()
	return last

func _markdown(target: RichTextLabel, text: String) -> void:
	# Construct formatting without interpreting model-supplied BBCode or HTML.
	for line in text.split("\n"):
		var heading = line.begins_with("#")
		if heading: target.push_bold()
		var pieces = line.trim_prefix("### ").trim_prefix("## ").trim_prefix("# ").split("**")
		for index in range(pieces.size()):
			if index % 2: target.push_bold()
			target.add_text(pieces[index])
			if index % 2: target.pop()
		if heading: target.pop()
		target.add_text("\n")

func activity(text: String, details: String = "") -> void:
	var column = VBoxContainer.new()
	thread.add_child(column)
	var body = label(column, details.left(12000))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.hide()
	var toggle = button(column, "› " + text, func() -> void: body.visible = not body.visible)
	column.move_child(toggle, 0)
	_follow.call_deferred()

func _follow() -> void:
	if follow_bottom and is_instance_valid(scroll): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func _draw() -> void:
	if backdrop != null: draw_texture_rect(backdrop, Rect2(Vector2.ZERO, size), false)
