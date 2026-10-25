@tool
extends HBoxContainer
static var Common: GDScript
static var Providers: GDScript
static var Icons: GDScript
static var Markdown: GDScript
var file_registry: RefCounted
var file_scope = ""
signal action(name: String, args: Dictionary)
var sidebar: VBoxContainer
var chats: ItemList
var search: LineEdit
var archived: CheckBox
var history_buttons: Dictionary = {}
var navigation_buttons: Dictionary = {}
var history_requested = -1
var history_active = false
var history_working = false
var title: Label
var thread: VBoxContainer
var scroll: ScrollContainer
var composer: TextEdit
var provider_picker: OptionButton
var model_picker: OptionButton
var mode_picker: OptionButton
var effort_picker: OptionButton
var mode_buttons: Array = []
var plan_cards: Dictionary = {}
var change_cards: Dictionary = {}
var send_button: Button
var status: Label
var context_label: Label
var context_indicator: HBoxContainer
var context_gauge: Control
var context_ratio = -1.0
var context_key = ""
var reference_label: Label
var tasks_label: Label
var model_button: Button
var picker: Control
var drawer: PanelContainer
var drawer_title: Label
var drawer_hint: Label
var drawer_step: Label
var drawer_icon: TextureRect
var drawer_back: Button
var drawer_refresh: Button
var catalog_loading = ""
var drawer_stage = "providers"
var drawer_profile = ""
var pending_selection: Dictionary = {}
var drawer_return_focus: Control
var drawer_layout_pending = false
var picker_search: LineEdit
var picker_list: ItemList
var reasoning_button: Button
var selection_row: HBoxContainer
var composer_controls: HBoxContainer
var compose_column: VBoxContainer
var input_row: HBoxContainer
var controls_spacer: Control
var voice_button: Button
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
var workspace_expanded = false
var activity_group: VBoxContainer
var message_records: Array = []
var restoring = false
var motion_enabled = true
var icon_cache = {}
var status_revision = 0
var streaming_dirty: Array = []
var stream_clock = 0.0
var attachment_signature = ""
var activity_panel: PanelContainer
var activity_toggle: Button
var activity_counter: Label
var activity_chevron: Label
var activity_indicator: Control
var activity_details: ScrollContainer
var activity_rows: VBoxContainer
var activity_expanded = false
var work_turn = ""
var work_plan: Dictionary = {}
var work_operations: Dictionary = {}
var work_jobs: Array = []
var work_outcome = ""
var work_live = false
var work_message = ""
var work_notice_running = false
var activity_clock = 0.0
var activity_dirty = true

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
	var history_header = HBoxContainer.new()
	sidebar.add_child(history_header)
	_compact_button(icon_button(history_header, "Back", "Înapoi la chat", func() -> void: show_history(false)))
	var new_history = button(history_header, "Conversație nouă", func() -> void: action.emit("new", {}))
	new_history.icon = _icon("Add")
	new_history.clip_text = true
	new_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation_buttons["new_history"] = new_history
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
	for entry in [["Favorite", "Favorite", "favorite"], ["Rename", "Redenumește", "rename"], ["Archive", "Arhivează", "archive"], ["Export", "Exportă", "export"], ["Delete", "Șterge", "delete"]]:
		history_buttons[entry[2]] = icon_button(history_actions, entry[0], entry[1], func() -> void: action.emit(entry[2], {}))
	root_column = VBoxContainer.new()
	root_column.add_theme_constant_override("separation", int(6 * EditorInterface.get_editor_scale()))
	root_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(root_column)
	var header = HBoxContainer.new()
	root_column.add_child(header)
	var history_button = icon_button(header, "Menu", "Istoricul conversațiilor", func() -> void: show_history(not sidebar.visible))
	_compact_button(history_button)
	title = label(header, "Conversație nouă")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	navigation_buttons["new"] = icon_button(header, "Add", "Conversație nouă", func() -> void: action.emit("new", {}))
	_compact_button(navigation_buttons["new"])
	expand_button = icon_button(header, "Expand", "Extinde chatul și ascunde panourile", _toggle_expanded)
	expand_button.toggle_mode = true
	_compact_button(expand_button)
	navigation_buttons["settings"] = icon_button(header, "Settings", "Setări", func() -> void: action.emit("settings", {}))
	_compact_button(navigation_buttons["settings"])
	navigation_buttons["history"] = history_button
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
	_build_activity_panel()
	compose_panel = PanelContainer.new()
	var compose_style = style(Color("1d2130"), 18)
	compose_style.set_content_margin_all(8 * EditorInterface.get_editor_scale())
	compose_style.border_color = Color("35364c")
	compose_style.set_border_width_all(1)
	compose_panel.add_theme_stylebox_override("panel", compose_style)
	root_column.add_child(compose_panel)
	compose_column = VBoxContainer.new()
	compose_panel.add_child(compose_column)
	attachment_chips = HFlowContainer.new()
	attachment_chips.hide()
	compose_column.add_child(attachment_chips)
	input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", int(4 * EditorInterface.get_editor_scale()))
	compose_column.add_child(input_row)
	var attach_button = icon_button(input_row, "Attach", "Atașează o imagine sau un fișier", func() -> void: action.emit("attach", {}))
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
	composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(composer)
	voice_button = icon_button(input_row, "Microphone", "Dictare", func() -> void: action.emit("voice", {}))
	send_button = icon_button(input_row, "ArrowUp", "Trimite mesajul", func() -> void: action.emit("send", {}))
	stop_button = icon_button(input_row, "Stop", "Oprește agentul", func() -> void: action.emit("stop", {}))
	stop_button.hide()
	composer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and not event.shift_pressed and not OS.has_feature("android"):
			composer.accept_event()
			action.emit("send", {}))
	composer_controls = HBoxContainer.new()
	composer_controls.add_theme_constant_override("separation", int(4 * EditorInterface.get_editor_scale()))
	compose_column.add_child(composer_controls)
	selection_row = HBoxContainer.new()
	selection_row.add_theme_constant_override("separation", int(4 * EditorInterface.get_editor_scale()))
	composer_controls.add_child(selection_row)
	model_button = button(selection_row, "Alege un model", _open_picker)
	model_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	model_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	model_button.clip_text = true
	model_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	model_button.icon = _icon("Models")
	model_button.tooltip_text = "Alege furnizorul și modelul"
	model_button.add_theme_constant_override("icon_max_width", int(20 * EditorInterface.get_editor_scale()))
	reasoning_button = button(selection_row, "Auto", _open_reasoning)
	reasoning_button.icon = _icon("Reasoning")
	reasoning_button.clip_text = true
	reasoning_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	reasoning_button.custom_maximum_size.x = 150 * EditorInterface.get_editor_scale()
	reasoning_button.tooltip_text = "Nivel de raționament"
	reasoning_button.add_theme_constant_override("icon_max_width", int(20 * EditorInterface.get_editor_scale()))
	options_button = button(composer_controls, "Auto", _open_options)
	options_button.icon = _icon("Agent")
	options_button.tooltip_text = "Mod de lucru"
	options_button.add_theme_constant_override("icon_max_width", int(20 * EditorInterface.get_editor_scale()))
	options_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	options_button.clip_text = false
	controls_spacer = Control.new()
	controls_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composer_controls.add_child(controls_spacer)
	context_indicator = HBoxContainer.new()
	context_indicator.name = "ContextFilling"
	context_indicator.alignment = BoxContainer.ALIGNMENT_CENTER
	composer_controls.add_child(context_indicator)
	context_gauge = Control.new()
	context_gauge.custom_minimum_size = Vector2(18, 18) * EditorInterface.get_editor_scale()
	context_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	context_indicator.add_child(context_gauge)
	context_gauge.draw.connect(func() -> void:
		var scale = EditorInterface.get_editor_scale()
		var gauge_center = context_gauge.size / 2
		context_gauge.draw_arc(gauge_center, 6 * scale, -PI / 2, 3 * PI / 2, 40, Color("41485c"), 2 * scale, true)
		if context_ratio > 0:
			context_gauge.draw_arc(gauge_center, 6 * scale, -PI / 2, -PI / 2 + TAU * context_ratio, 40, Color("edb56b") if context_ratio >= 0.8 else Color("aa8be8"), 2 * scale, true))
	context_label = label(context_indicator, "—")
	context_label.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
	set_context(0, 0)
	send_button.add_theme_stylebox_override("normal", style(Color("7650c5")))
	for control in [model_button, reasoning_button, options_button, voice_button, send_button, stop_button, attach_button]:
		_compact_button(control)
	for control in [attach_button, voice_button, send_button, stop_button]: control.size_flags_vertical = Control.SIZE_SHRINK_END
	send_button.add_theme_stylebox_override("normal", _compact_style(Color("7650c5")))
	provider_picker = OptionButton.new()
	model_picker = OptionButton.new()
	effort_picker = OptionButton.new()
	for hidden in [provider_picker, model_picker, effort_picker]:
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
	for index in range(Common.MODES.size()): mode_picker.add_icon_item(_icon(Common.MODE_ICONS[index]), Common.MODES[index], Common.MODE_IDS[index])
	mode_picker.hide()
	options.add_child(mode_picker)
	var choices = HBoxContainer.new()
	options.add_child(choices)
	for index in range(Common.MODES.size()):
		var choice = button(choices, Common.MODES[index], func() -> void:
			mode_picker.select(index)
			mode_picker.item_selected.emit(index)
			runtime_options.hide())
		choice.icon = _icon(Common.MODE_ICONS[index])
		choice.toggle_mode = true
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_buttons.append(choice)
	effort_picker.item_selected.connect(func(_index: int) -> void: sync_selection())
	_build_drawer()
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree() and picker.visible: _close_drawer())
	root_column.resized.connect(func() -> void: _layout_composer.call_deferred())
	resized.connect(_resize)
	_resize()

func _resize() -> void:
	if sidebar == null: return
	var scale = EditorInterface.get_editor_scale()
	var wide = size.x / scale >= 900
	sidebar.visible = wide if history_requested < 0 else history_requested == 1
	sidebar.custom_minimum_size.x = minf(220 * scale, size.x)
	sidebar.size_flags_horizontal = Control.SIZE_FILL if wide else Control.SIZE_EXPAND_FILL
	root_column.visible = wide or not sidebar.visible
	_size_messages.call_deferred()
	_layout_composer.call_deferred()
	_layout_drawer.call_deferred()

func show_history(visible: bool) -> void:
	history_requested = 1 if visible else 0
	_close_drawer()
	_resize()

func close_mobile_history() -> void:
	if size.x / EditorInterface.get_editor_scale() < 900: show_history(false)

func _layout_composer() -> void:
	if selection_row == null: return
	composer.placeholder_text = "Mesaj…" if root_column.size.x < 280 * EditorInterface.get_editor_scale() else "Scrie un mesaj…"
	voice_button.visible = not stop_button.visible
	_size_selection_chips()
	_layout_drawer()
	_layout_activity.call_deferred()

func _build_activity_panel() -> void:
	var scale = EditorInterface.get_editor_scale()
	activity_panel = PanelContainer.new()
	activity_panel.name = "AgentActivity"
	var surface = style(Color("1a1d2a"), 10)
	surface.set_content_margin_all(0)
	surface.border_color = Color("39364b")
	surface.set_border_width_all(1)
	activity_panel.add_theme_stylebox_override("panel", surface)
	root_column.add_child(activity_panel)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	activity_panel.add_child(body)
	activity_toggle = button(body, "", _toggle_activity)
	activity_toggle.name = "ActivityToggle"
	activity_toggle.toggle_mode = true
	activity_toggle.custom_minimum_size.y = 34 * scale
	activity_toggle.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT))
	activity_toggle.add_theme_stylebox_override("pressed", _compact_style(Color("252536")))
	activity_toggle.add_theme_stylebox_override("hover", _compact_style(Color("29283b")))
	var inset = MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	activity_toggle.add_child(inset)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.offset_left = 10 * scale
	inset.offset_right = -10 * scale
	var header = HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", int(8 * scale))
	inset.add_child(header)
	activity_indicator = Control.new()
	activity_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	activity_indicator.custom_minimum_size = Vector2(14, 14) * scale
	activity_indicator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(activity_indicator)
	activity_indicator.draw.connect(func() -> void:
		var center = activity_indicator.size / 2
		var running = _work_running()
		var ink = Color("b29ae9") if running else (Color("98c9a8") if work_outcome == "completed" else Color("9ba7bf"))
		if work_outcome in ["failed", "limited"]: ink = Color("e4979f")
		elif work_outcome in ["blocked", "cancelled"] or work_plan.get("phase") in ["paused", "blocked"]: ink = Color("d8b47a")
		if running:
			var angle = float(Time.get_ticks_msec()) / 700.0 if motion_enabled else -PI / 2
			activity_indicator.draw_arc(center, 4.5 * scale, angle, angle + PI * 1.4, 20, ink, 1.7 * scale, true)
		else: activity_indicator.draw_circle(center, 3 * scale, ink, true, -1, true))
	status = label(header, "")
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_theme_font_size_override("font_size", int(12 * scale))
	status.add_theme_color_override("font_color", Color("c5cbda"))
	activity_counter = label(header, "")
	activity_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	activity_counter.add_theme_font_size_override("font_size", int(11 * scale))
	activity_counter.add_theme_color_override("font_color", Color("bda6e9"))
	activity_chevron = label(header, "▾")
	activity_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	activity_chevron.add_theme_font_size_override("font_size", int(12 * scale))
	activity_details = ScrollContainer.new()
	activity_details.name = "ActivityDetails"
	activity_details.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	activity_details.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(activity_details)
	activity_rows = VBoxContainer.new()
	activity_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	activity_rows.add_theme_constant_override("separation", int(6 * scale))
	var details_inset = MarginContainer.new()
	details_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right"]: details_inset.add_theme_constant_override("margin_" + edge, int(10 * scale))
	details_inset.add_theme_constant_override("margin_bottom", int(8 * scale))
	activity_details.add_child(details_inset)
	details_inset.add_child(activity_rows)
	activity_rows.resized.connect(func() -> void: _layout_activity.call_deferred())
	activity_toggle.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and activity_expanded:
			_toggle_activity()
			activity_toggle.accept_event())
	activity_panel.hide()
	activity_details.hide()
	status.hide()

func _toggle_activity() -> void:
	activity_expanded = not activity_expanded
	activity_toggle.set_pressed_no_signal(activity_expanded)
	_refresh_activity()

func reset_work() -> void:
	status_revision += 1
	work_turn = ""
	work_plan = {}
	work_operations.clear()
	work_jobs = []
	work_outcome = ""
	work_message = ""
	work_live = false
	work_notice_running = false
	activity_expanded = false
	if activity_toggle != null: activity_toggle.set_pressed_no_signal(false)
	_refresh_activity()

func begin_work(turn: String, snapshot: Dictionary = {}, resuming: bool = false) -> void:
	if not resuming or work_turn != turn: reset_work()
	work_turn = turn
	work_live = true
	work_outcome = ""
	work_plan = snapshot.duplicate(true)
	_refresh_activity(true)

func finish_work(turn: String, outcome: String) -> void:
	if work_turn != turn: return
	work_live = false
	work_notice_running = false
	work_outcome = outcome
	work_message = ""
	for operation in work_operations.values():
		if operation.state == "in_progress": operation.state = "blocked" if outcome == "blocked" else "cancelled"
	_refresh_activity(true)

func show_work_plan(snapshot: Dictionary) -> void:
	var turn = str(snapshot.get("turn", ""))
	if not work_turn.is_empty() and work_turn != turn: return
	work_turn = turn
	work_plan = snapshot.duplicate(true)
	_refresh_activity(true)

func start_operation(id: String, title_text: String, detail: String = "") -> void:
	work_operations[id] = {"id": id, "title": title_text.trim_suffix("…"), "detail": detail, "state": "in_progress"}
	_refresh_activity(true)

func finish_operation(id: String, title_text: String, detail: String, result: Dictionary, replayed: bool = false) -> void:
	var state = "completed" if result.get("ok", false) else "failed"
	if result.get("code") in ["permission_denied", "plan_required", "plan_read_only"]: state = "blocked"
	elif result.get("code") in ["cancelled", "redirected"]: state = "cancelled"
	work_operations[id] = {"id": id, "title": title_text.trim_suffix("…"), "detail": detail, "state": state, "replayed": replayed, "error": str(result.get("error", "")).left(600)}
	_refresh_activity(true)

func show_work_jobs(jobs: Array) -> void:
	if work_jobs == jobs: return
	work_jobs = jobs.duplicate(true)
	_refresh_activity(true)

func restore_work(turn: String, snapshot: Dictionary, operations: Array, outcome: String, running: bool = false) -> void:
	reset_work()
	work_turn = turn
	work_plan = snapshot.duplicate(true)
	work_outcome = outcome
	work_live = running
	if not running and work_plan.get("phase") in ["planning", "executing", "verifying"]:
		work_plan["phase"] = "paused"
	for item in operations: work_operations[str(item.id)] = item.duplicate(true)
	_refresh_activity(true)

func _work_running() -> bool:
	return work_live or work_notice_running or work_jobs.any(func(job: Dictionary) -> bool: return job.get("status") == "running")

func _refresh_activity(rebuild: bool = false) -> void:
	if activity_panel == null: return
	var steps: Array = work_plan.get("steps", [])
	var details = not steps.is_empty() or not work_operations.is_empty() or not work_jobs.is_empty() or work_message.length() > 100
	activity_panel.visible = details or _work_running() or not work_message.is_empty()
	status.visible = activity_panel.visible
	var heading = work_message
	var active = steps.filter(func(step: Dictionary) -> bool: return step.get("status") == "in_progress")
	if heading.is_empty() or " · lucrează" in heading or " · continuă pașii" in heading:
		if work_outcome == "blocked" or work_plan.get("phase") == "blocked": heading = "Sarcină blocată"
		elif work_outcome in ["failed", "limited"]: heading = "Necesită verificare"
		elif work_outcome == "cancelled" or work_plan.get("phase") == "paused": heading = "Sarcină întreruptă"
		elif work_outcome == "completed": heading = "Plan pregătit" if work_plan.get("intent") == "propose" else "Finalizat"
		elif not active.is_empty(): heading = str(active[0].get("step", ""))
		else: heading = "Agentul lucrează…" if _work_running() else "Activitate"
	status.text = heading
	status.tooltip_text = heading
	var done = steps.filter(func(step: Dictionary) -> bool: return step.get("status") == "completed").size()
	activity_counter.text = "%s/%s" % [done, steps.size()] if not steps.is_empty() else ("%s operații" % work_operations.size() if not work_operations.is_empty() else ("%s sarcini" % work_jobs.size() if not work_jobs.is_empty() else ""))
	activity_counter.visible = not activity_counter.text.is_empty()
	activity_counter.tooltip_text = "%s din %s pași finalizați" % [done, steps.size()] if not steps.is_empty() else "Operațiile și sarcinile acestei cereri"
	activity_chevron.visible = details
	activity_chevron.text = "▴" if activity_expanded else "▾"
	activity_toggle.disabled = not details
	activity_toggle.tooltip_text = ("Restrânge activitatea" if activity_expanded else "Vezi pașii și operațiile") if details else heading
	activity_toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if details else Control.CURSOR_ARROW
	activity_details.visible = activity_expanded and details
	activity_indicator.queue_redraw()
	activity_dirty = activity_dirty or rebuild
	if activity_expanded and activity_dirty:
		_rebuild_activity()
		activity_dirty = false
	_layout_activity.call_deferred()

func _activity_heading(text: String) -> void:
	var heading = label(activity_rows, text)
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
	heading.add_theme_color_override("font_color", Color("9ca6bc"))

func _activity_row(title_text: String, state: String, detail: String = "", replayed: bool = false) -> void:
	var scale = EditorInterface.get_editor_scale()
	var row = HBoxContainer.new()
	row.set_meta("state", state)
	row.add_theme_constant_override("separation", int(8 * scale))
	activity_rows.add_child(row)
	var mark = label(row, str({"completed": "✓", "in_progress": "›", "pending": "○", "blocked": "!", "failed": "!", "cancelled": "Ⅱ"}.get(state, "○")))
	mark.custom_minimum_size.x = 14 * scale
	mark.add_theme_color_override("font_color", Color("9dd0ad") if state == "completed" else (Color("dcb57d") if state in ["blocked", "failed", "cancelled"] else Color("bca1ed")))
	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	row.add_child(body)
	var title_text_label = label(body, title_text)
	title_text_label.add_theme_font_size_override("font_size", int(12 * scale))
	title_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_text_label.max_lines_visible = 2
	title_text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_text_label.tooltip_text = title_text + ("\n" + detail if not detail.is_empty() else "")
	var state_text = "Recuperat" if replayed else str({"completed": "Finalizat", "in_progress": "În lucru", "pending": "De făcut", "blocked": "Blocat", "failed": "Eșuat", "cancelled": "Întrerupt"}.get(state, "De făcut"))
	var caption = label(body, state_text + (" · " + detail.get_slice("\n", 0).left(100) if not detail.is_empty() else ""))
	caption.add_theme_font_size_override("font_size", int(10 * scale))
	caption.add_theme_color_override("font_color", Color("96a2b9"))
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.tooltip_text = state_text + ("\n" + detail if not detail.is_empty() else "")
	if detail.is_empty():
		body.remove_child(caption)
		row.add_child(caption)
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		caption.size_flags_horizontal = Control.SIZE_SHRINK_END
		caption.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if state in ["failed", "blocked"] and "\n" in detail:
		var error = label(body, detail.substr(detail.find("\n") + 1))
		error.add_theme_font_size_override("font_size", int(11 * scale))
		error.add_theme_color_override("font_color", Color("d8b47a"))
		error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		error.max_lines_visible = 2
		error.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		error.tooltip_text = error.text

func _rebuild_activity() -> void:
	for child in activity_rows.get_children():
		activity_rows.remove_child(child)
		child.queue_free()
	var steps: Array = work_plan.get("steps", [])
	if not steps.is_empty():
		_activity_heading("Pași")
		for item in steps: _activity_row(str(item.get("step", "")), str(item.get("status", "pending")))
		if work_plan.get("phase") in ["blocked", "paused"] and not str(work_plan.get("explanation", "")).is_empty():
			var reason = label(activity_rows, str(work_plan["explanation"]))
			reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			reason.max_lines_visible = 3
			reason.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			reason.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
			reason.tooltip_text = reason.text
	if not work_jobs.is_empty():
		_activity_heading("Sarcini secundare")
		for job in work_jobs: _activity_row(str(job.get("task", "Sarcină")), "in_progress" if job.get("status") == "running" else str(job.get("status", "pending")), str(job.get("kind", "")))
	if not work_operations.is_empty():
		_activity_heading("Operații" + (" · ultimele 24 din %s" % work_operations.size() if work_operations.size() > 24 else ""))
		for item in work_operations.values().slice(-24): _activity_row(str(item.title), str(item.state), str(item.get("detail", "")) + ("\n" + str(item.error) if not str(item.get("error", "")).is_empty() else ""), bool(item.get("replayed", false)))
	if work_message.length() > 100:
		var notice = label(activity_rows, work_message)
		notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notice.add_theme_font_size_override("font_size", int(12 * EditorInterface.get_editor_scale()))

func _layout_activity() -> void:
	if activity_details == null or not activity_details.visible: return
	var scale = EditorInterface.get_editor_scale()
	for row in activity_rows.get_children():
		if not row.has_meta("state"): continue
		var title_text_label: Label = row.get_child(1).get_child(0)
		var text_width = title_text_label.get_theme_font("font").get_string_size(title_text_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_text_label.get_theme_font_size("font_size")).x
		title_text_label.max_lines_visible = 2 if text_width > maxf(60 * scale, title_text_label.get_parent().size.x) else 1
	var cap = maxf(48 * scale, minf(200 * scale, root_column.size.y * 0.30))
	activity_details.custom_minimum_size.y = minf(cap, activity_rows.get_combined_minimum_size().y + 8 * scale)
	activity_details.custom_maximum_size.y = cap

func _compact_style(color: Color) -> StyleBoxFlat:
	var box = style(color, 8)
	var scale = EditorInterface.get_editor_scale()
	box.content_margin_left = 8 * scale
	box.content_margin_right = 8 * scale
	box.content_margin_top = 5 * scale
	box.content_margin_bottom = 5 * scale
	return box

func _compact_button(control: Button) -> void:
	var scale = EditorInterface.get_editor_scale()
	control.custom_minimum_size = Vector2(32 if control.text.is_empty() else 0, 32) * scale
	control.add_theme_font_size_override("font_size", int(12 * scale))
	control.add_theme_constant_override("icon_max_width", int(16 * scale))
	control.add_theme_constant_override("h_separation", int(4 * scale))
	control.add_theme_stylebox_override("normal", _compact_style(Color.TRANSPARENT if control.text.is_empty() else Color("252939")))
	control.add_theme_stylebox_override("hover", _compact_style(Color("393456")))
	control.add_theme_stylebox_override("pressed", _compact_style(Color("59458c")))

func _size_selection_chips() -> void:
	if reasoning_button == null: return
	var scale = EditorInterface.get_editor_scale()
	var width = minf(size.x, root_column.size.x) / scale - 20.0
	var very_narrow = width < 230.0
	var compact_reasoning = width < 340.0
	reasoning_button.visible = not very_narrow and not reasoning_button.disabled
	var effort = str(_current_selection().get("effort", ""))
	reasoning_button.text = "" if compact_reasoning else ("Implicit" if effort.is_empty() else effort_label(effort))
	reasoning_button.tooltip_text = "Raționament · " + effort_label(str(_current_selection().get("effort", ""))) + " · schimbă nivelul"
	var effort_width = (32.0 if compact_reasoning else minf(104.0, 34.0 + reasoning_button.get_theme_font("font").get_string_size(reasoning_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, reasoning_button.get_theme_font_size("font_size")).x)) if reasoning_button.visible else 0.0
	reasoning_button.custom_minimum_size.x = effort_width * scale
	reasoning_button.custom_maximum_size.x = effort_width * scale
	var reserved = options_button.get_combined_minimum_size().x / scale + context_indicator.get_combined_minimum_size().x / scale + 16.0 + (effort_width + 4.0 if reasoning_button.visible else 0.0)
	var model_width = clampf(width - reserved, 62.0, 150.0) * scale
	model_button.custom_minimum_size.x = model_width
	model_button.custom_maximum_size.x = model_width

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
	for type in ["Label", "Button", "LineEdit", "TextEdit", "CodeEdit", "OptionButton", "CheckBox", "RichTextLabel", "ItemList", "PopupMenu"]:
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
	skin.set_stylebox("panel", "PopupMenu", style(Color("191e2c"), 12))
	skin.set_stylebox("hover", "PopupMenu", style(Color("393150"), 8))
	skin.set_color("font_separator_color", "PopupMenu", Color("a9b5cb"))
	skin.set_stylebox("selected", "ItemList", style(Color("393150"), 8))
	var plain = StyleBoxEmpty.new()
	var focus = style(Color.TRANSPARENT, 8)
	focus.border_color = Color("9b80d1")
	focus.set_border_width_all(1)
	for type in ["Button", "OptionButton", "LineEdit", "ItemList"]: skin.set_stylebox("focus", type, focus)
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
	pending_selection.clear()
	drawer_profile = ""
	_show_drawer("providers")

func _build_drawer() -> void:
	# A native control overlay stays inside the chat, including embedded Android editors.
	picker = Control.new()
	picker.name = "ModelDrawer"
	picker.set_as_top_level(true)
	picker.z_index = 10
	add_child(picker)
	picker.hide()
	var scrim = ColorRect.new()
	scrim.color = Color(0.025, 0.035, 0.06, 0.72)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picker.add_child(scrim)
	scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _close_drawer())
	drawer = PanelContainer.new()
	var surface = style(Color("1b2030"), 20)
	surface.border_color = Color("514369")
	surface.set_border_width_all(1)
	drawer.add_theme_stylebox_override("panel", surface)
	picker.add_child(drawer)
	drawer.minimum_size_changed.connect(_queue_drawer_layout)
	var body = VBoxContainer.new()
	body.add_theme_constant_override("separation", int(8 * EditorInterface.get_editor_scale()))
	drawer.add_child(body)
	var handle = ColorRect.new()
	handle.color = Color("625771")
	handle.custom_minimum_size = Vector2(32, 3) * EditorInterface.get_editor_scale()
	handle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(handle)
	var header = HBoxContainer.new()
	body.add_child(header)
	drawer_icon = TextureRect.new()
	drawer_icon.custom_minimum_size = Vector2(24, 24) * EditorInterface.get_editor_scale()
	drawer_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drawer_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(drawer_icon)
	drawer_title = label(header, "Furnizori")
	drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	drawer_title.add_theme_font_size_override("font_size", int(18 * EditorInterface.get_editor_scale()))
	icon_button(header, "Close", "Închide fără a schimba modelul", _close_drawer)
	drawer_step = label(body, "")
	drawer_step.add_theme_color_override("font_color", Color("b5a4d9"))
	picker_search = LineEdit.new()
	picker_search.custom_minimum_size.y = 44 * EditorInterface.get_editor_scale()
	picker_search.right_icon = _icon("Search")
	body.add_child(picker_search)
	picker_search.text_changed.connect(func(_text: String) -> void: _filter_models())
	drawer_hint = label(body, "")
	drawer_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drawer_hint.add_theme_color_override("font_color", Color("aab5cb"))
	picker_list = ItemList.new()
	picker_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_list.custom_minimum_size.y = 88 * EditorInterface.get_editor_scale()
	picker_list.fixed_icon_size = Vector2i(24, 24) * EditorInterface.get_editor_scale()
	picker_list.add_theme_constant_override("icon_margin", int(12 * EditorInterface.get_editor_scale()))
	picker_list.add_theme_constant_override("v_separation", int(20 * EditorInterface.get_editor_scale()))
	body.add_child(picker_list)
	# One tap advances. No double-click/confirmation is needed on touchscreens.
	picker_list.item_selected.connect(_pick_model)
	var footer = HBoxContainer.new()
	body.add_child(footer)
	drawer_back = button(footer, "Înapoi", _drawer_back)
	drawer_back.icon = _icon("Back")
	drawer_refresh = button(footer, "Actualizează", func() -> void: action.emit("models_refresh", {"profile": drawer_profile}))
	drawer_refresh.icon = _icon("Retry")
	drawer_refresh.tooltip_text = "Caută modelele folosind cheia salvată"
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var manage = button(footer, "Furnizori", func() -> void:
		_close_drawer()
		action.emit("settings", {"section": "providers"}))
	manage.icon = _icon("Settings")
	manage.tooltip_text = "Adaugă un furnizor sau actualizează modelele"

func _show_drawer(stage: String) -> void:
	runtime_options.hide()
	if not picker.visible:
		drawer_return_focus = get_viewport().gui_get_focus_owner()
		picker.show()
	drawer_stage = stage
	picker_search.text = ""
	picker_search.visible = stage != "reasoning"
	drawer_back.visible = stage != "providers"
	drawer_step.text = {"providers": "1 / 3 · Furnizor", "models": "2 / 3 · Model", "reasoning": "3 / 3 · Reasoning"}[stage]
	var profile = _drawer_profile_data()
	drawer_refresh.visible = stage == "models" and profile.get("kind") not in ["siwc", "companion"]
	drawer_title.text = {"providers": "Alege furnizorul", "models": str(profile.get("name", "Modele")), "reasoning": "Nivel de raționament"}[stage]
	drawer_icon.texture = _icon("Providers") if stage == "providers" else (provider_icon(profile) if stage == "models" else _icon("Reasoning"))
	picker_search.placeholder_text = "Caută un furnizor sau profil…" if stage == "providers" else "Caută un model la acest furnizor…"
	var model = _model_data(profile, str(pending_selection.get("model", "")))
	drawer_hint.text = "API, abonamente și modele locale, în grupuri separate." if stage == "providers" else ("Alege modelul, apoi nivelul de reasoning." if stage == "models" else str(profile.get("name", "")) + " · " + str(model.get("name", model.get("id", ""))))
	_filter_models()
	_layout_drawer()
	_queue_drawer_layout()
	picker_list.grab_focus()

func _queue_drawer_layout() -> void:
	if drawer_layout_pending: return
	drawer_layout_pending = true
	_layout_drawer.call_deferred()

func _layout_drawer() -> void:
	drawer_layout_pending = false
	if picker == null or not picker.visible: return
	var scale = EditorInterface.get_editor_scale()
	picker.global_position = root_column.global_position
	picker.size = root_column.size
	var compact = picker.size.y < 340 * scale
	drawer_step.visible = not compact
	drawer_hint.visible = picker.size.y >= 360 * scale
	picker_list.custom_minimum_size.y = (44 if compact else 88) * scale
	var body: VBoxContainer = drawer.get_child(0)
	var separation = int((4 if compact else 8) * scale)
	if body.get_theme_constant("separation") != separation: body.add_theme_constant_override("separation", separation)
	body.get_child(0).visible = not compact
	var list_padding = picker_list.get_theme_stylebox("panel").get_minimum_size().y
	var font_height = picker_list.get_theme_font("font").get_height(picker_list.get_theme_font_size("font_size"))
	var row_height = ceilf(maxf(picker_list.fixed_icon_size.y, font_height)) + picker_list.get_theme_constant("v_separation") + 1
	var content_height = drawer.get_combined_minimum_size().y + maxf(0, mini(picker_list.item_count, 7) * row_height + list_padding - picker_list.custom_minimum_size.y)
	var wanted = Vector2(minf(560 * scale, picker.size.x - 16 * scale), minf(minf(510 * scale, content_height), picker.size.y - 16 * scale))
	drawer.size = wanted
	drawer.position = Vector2((picker.size.x - drawer.size.x) / 2, picker.size.y - drawer.size.y - 8 * scale)

func _close_drawer() -> void:
	if picker == null or not picker.visible: return
	picker.hide()
	pending_selection.clear()
	if is_instance_valid(drawer_return_focus) and drawer_return_focus.is_visible_in_tree(): drawer_return_focus.grab_focus()

func _input(event: InputEvent) -> void:
	if picker != null and picker.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_drawer()
		get_viewport().set_input_as_handled()

func _drawer_back() -> void:
	_show_drawer("models" if drawer_stage == "reasoning" else "providers")

func _drawer_profile_data() -> Dictionary:
	for profile in catalog:
		if str(profile["id"]) == drawer_profile: return profile
	return {}

func _model_data(profile: Dictionary, id: String) -> Dictionary:
	for model in profile.get("models", []):
		if str(model["id"]) == id: return model
	return {}

func _current_selection() -> Dictionary:
	return {"profile": provider_picker.get_item_metadata(provider_picker.selected) if provider_picker.selected >= 0 else "", "model": model_picker.get_item_metadata(model_picker.selected) if model_picker.selected >= 0 else "", "effort": effort_picker.get_item_metadata(effort_picker.selected) if effort_picker.selected >= 0 else ""}

func _open_reasoning() -> void:
	pending_selection = _current_selection()
	if str(pending_selection["model"]).is_empty():
		_open_picker()
		return
	drawer_profile = str(pending_selection["profile"])
	_show_drawer("reasoning")

func sync_selection() -> void:
	var key = str(provider_picker.get_selected_metadata()) + ":" + str(model_picker.get_selected_metadata()) if provider_picker.selected >= 0 and model_picker.selected >= 0 else ""
	if key != context_key:
		context_key = key
		set_context(0, 0)
	var selection = _current_selection()
	var profile: Dictionary = {}
	for entry in catalog:
		if entry["id"] == selection["profile"]: profile = entry
	var model = _model_data(profile, str(selection["model"]))
	model_button.text = str(model.get("name", model.get("id", "Alege un model"))) + "  ▾"
	model_button.icon = provider_icon(profile)
	model_button.tooltip_text = (str(profile.get("name", "Furnizor")) + " · " + str(selection["model"]) + "\nSchimbă furnizorul sau modelul") if not model.is_empty() else "Adaugă un furnizor și alege un model"
	reasoning_button.text = effort_label(str(selection["effort"]))
	reasoning_button.disabled = model.is_empty()
	_size_selection_chips()
	if not model.is_empty(): model_button.tooltip_text += "\nRaționament: " + effort_label(str(selection["effort"]))

func effort_label(effort: String) -> String:
	return str({"": "Auto", "none": "Fără", "minimal": "Minim", "low": "Redus", "medium": "Mediu", "high": "Ridicat", "xhigh": "Foarte ridicat", "max": "Maxim"}.get(effort, effort))

func _filter_models() -> void:
	picker_list.clear()
	var query = picker_search.text.to_lower()
	if drawer_stage == "providers":
		for group in ["API cloud", "Abonamente", "Modele locale"]:
			var heading = false
			for profile in catalog:
				var category = "Abonamente" if profile.get("kind") in ["siwc", "companion"] else ("Modele locale" if Providers.hosting(profile) == "local" else "API cloud")
				if category != group or (not query.is_empty() and not query in (str(profile["name"]) + " " + str(profile.get("issuer", ""))).to_lower()): continue
				if not heading:
					label_once(group)
					picker_list.set_item_icon(picker_list.item_count - 1, _icon({"API cloud": "Cloud", "Abonamente": "Accounts", "Modele locale": "Local"}[group]))
					heading = true
				var count = profile.get("models", []).size()
				picker_list.add_item(str(profile["name"]) + " · %s %s" % [count, "model" if count == 1 else "modele"], provider_icon(profile))
				picker_list.set_item_metadata(picker_list.item_count - 1, {"profile": profile["id"]})
	elif drawer_stage == "models":
		var current = _current_selection()
		var profile = _drawer_profile_data()
		if catalog_loading == drawer_profile: drawer_hint.text = "Se încarcă modelele…"
		elif not str(profile.get("model_catalog_error", "")).is_empty(): drawer_hint.text = str(profile["model_catalog_error"])
		else: drawer_hint.text = "Alege modelul, apoi nivelul de reasoning."
		for model in profile.get("models", []):
			var text = str(model.get("name", model["id"]))
			if not query.is_empty() and not query in (text + " " + str(model["id"])).to_lower(): continue
			var active = current["profile"] == drawer_profile and current["model"] == model["id"]
			picker_list.add_item(text, _icon("Check" if active else "Models"))
			picker_list.set_item_tooltip(picker_list.item_count - 1, str(model["id"]))
			picker_list.set_item_metadata(picker_list.item_count - 1, {"profile": drawer_profile, "model": model["id"]})
	else:
		var efforts: Array = _model_data(_drawer_profile_data(), str(pending_selection.get("model", ""))).get("efforts", [])
		var current = _current_selection()
		var selected_effort = str(current["effort"]) if current["profile"] == pending_selection.get("profile") and current["model"] == pending_selection.get("model") else ""
		picker_list.add_item("Automat · lasă furnizorul să decidă", _icon("Check" if selected_effort.is_empty() else "Auto"))
		picker_list.set_item_metadata(0, {"effort": ""})
		for effort in efforts:
			if str(effort).is_empty(): continue
			picker_list.add_item(effort_label(str(effort)), _icon("Check" if selected_effort == str(effort) else "Reasoning"))
			picker_list.set_item_metadata(picker_list.item_count - 1, {"effort": str(effort)})
		if efforts.is_empty(): drawer_hint.text += "\nNu sunt disponibile niveluri configurabile pentru acest model."
	if picker_list.item_count == 0:
		if drawer_stage == "models" and query.is_empty():
			label_once("Se încarcă modelele…" if catalog_loading == drawer_profile else "Lista este goală. Apasă Actualizează pentru a căuta modelele.")
		else: label_once("Niciun rezultat pentru căutarea ta.")

func label_once(text: String) -> void:
	picker_list.add_item(text)
	picker_list.set_item_disabled(picker_list.item_count - 1, true)

func _pick_model(index: int) -> void:
	if index < 0 or index >= picker_list.item_count: return
	var selected: Variant = picker_list.get_item_metadata(index)
	if not selected is Dictionary: return
	if drawer_stage == "providers":
		drawer_profile = str(selected["profile"])
		_show_drawer("models")
		var profile = _drawer_profile_data()
		if profile.get("models", []).is_empty() and profile.get("kind") not in ["siwc", "companion"]: action.emit("models_refresh", {"profile": drawer_profile})
	elif drawer_stage == "models":
		pending_selection = selected.duplicate()
		_show_drawer("reasoning")
	else:
		pending_selection["effort"] = selected["effort"]
		action.emit("model", pending_selection.duplicate())
		_close_drawer()

func refresh_history(entries: Array, active: String) -> void:
	chats.clear()
	history_active = false
	for entry in entries:
		chats.add_item(("★ " if entry.get("favorite", false) else "") + str(entry["title"]))
		chats.set_item_metadata(chats.item_count - 1, entry["id"])
		if entry["id"] == active:
			chats.select(chats.item_count - 1)
			history_active = true
			history_buttons["favorite"].tooltip_text = "Elimină din favorite" if entry.get("favorite", false) else "Adaugă la favorite"
			history_buttons["archive"].tooltip_text = "Dezarhivează conversația" if entry.get("archived", false) else "Arhivează conversația"
	history_buttons["export"].tooltip_text = "Exportă conversația în Markdown…"
	_update_history_controls()

func _update_history_controls() -> void:
	for control in history_buttons.values(): control.disabled = history_working or not history_active
	for key in ["new", "new_history"]: navigation_buttons[key].disabled = history_working

func clear_messages() -> void:
	reset_work()
	change_cards.clear()
	plan_cards.clear()
	message_records.clear()
	streaming_dirty.clear()
	activity_group = null
	for child in thread.get_children():
		thread.remove_child(child)
		child.queue_free()

func show_plan(snapshot: Dictionary) -> void:
	var id = str(snapshot.get("turn", ""))
	var phase = str(snapshot.get("phase", "planning"))
	var proposal = snapshot.get("intent") == "propose"
	var entries: Array = snapshot.get("steps", [])
	if entries.is_empty(): return
	if not restoring: show_work_plan(snapshot)
	if not plan_cards.has(id) or not is_instance_valid(plan_cards[id]["node"]):
		var panel = PanelContainer.new()
		var surface = style(Color("1c2030"), 12)
		surface.border_color = Color("49415d")
		surface.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", surface)
		thread.add_child(panel)
		var body = VBoxContainer.new()
		panel.add_child(body)
		var rows = VBoxContainer.new()
		var summary = Label.new()
		var toggle = button(body, "", func() -> void:
			rows.visible = not rows.visible
			summary.visible = not rows.visible and panel.get_meta("phase", "") != "completed" and not summary.text.is_empty()
			panel.set_meta("expanded_by_user", rows.visible))
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle.clip_text = true
		toggle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		toggle.icon = _icon("Plan")
		_compact_button(toggle)
		var reason = label(body, "")
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.max_lines_visible = 2
		reason.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		reason.add_theme_color_override("font_color", Color("aab5c9"))
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.max_lines_visible = 2
		summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		summary.add_theme_font_size_override("font_size", int(13 * EditorInterface.get_editor_scale()))
		body.add_child(summary)
		body.add_child(rows)
		plan_cards[id] = {"node": panel, "toggle": toggle, "rows": rows, "reason": reason, "summary": summary}
	var card: Dictionary = plan_cards[id]
	card["node"].set_meta("phase", phase)
	for row in card["rows"].get_children():
		card["rows"].remove_child(row)
		row.queue_free()
	var done = 0
	for index in range(entries.size()):
		var item: Dictionary = entries[index]
		var state = str(item.get("status", "pending"))
		if state == "completed": done += 1
		var row = HBoxContainer.new()
		card["rows"].add_child(row)
		var mark = label(row, "✓" if state == "completed" else ("›" if state == "in_progress" else str(index + 1) + "."))
		mark.custom_minimum_size.x = 20 * EditorInterface.get_editor_scale()
		mark.add_theme_color_override("font_color", Color("9cd2ad") if state == "completed" else Color("c1a8f2"))
		var text = label(row, str(item.get("step", "")))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if state == "pending": text.add_theme_color_override("font_color", Color("aab5c9"))
	var heading = {"planning": "Pregătește planul", "executing": "Plan în lucru", "verifying": "Verifică rezultatele", "completed": "Plan propus" if proposal else "Plan finalizat", "paused": "Plan întrerupt", "blocked": "Plan blocat"}.get(phase, "Plan")
	card["toggle"].text = str(heading) + (" · %s pași" % entries.size() if proposal else " · %s/%s" % [done, entries.size()])
	card["reason"].text = str(snapshot.get("explanation", ""))
	card["reason"].tooltip_text = card["reason"].text
	card["reason"].visible = not card["reason"].text.is_empty()
	card["rows"].visible = card["node"].get_meta("expanded_by_user", proposal or phase in ["planning", "blocked"])
	var active_step = ""
	for item in entries:
		if item.get("status") == "in_progress": active_step = str(item.get("step", "")); break
	if active_step.is_empty():
		for item in entries:
			if item.get("status") == "pending": active_step = str(item.get("step", "")); break
	card["summary"].text = active_step
	card["summary"].tooltip_text = active_step
	card["summary"].visible = not card["rows"].visible and phase != "completed" and not active_step.is_empty()
	_follow.call_deferred()

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
		var identity = HBoxContainer.new()
		column.add_child(identity)
		var mark = TextureRect.new()
		mark.custom_minimum_size = Vector2(16, 16) * EditorInterface.get_editor_scale()
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.texture = _icon("Agent")
		for profile in catalog:
			if profile["id"] == metadata.get("profile_id"): mark.texture = provider_icon(profile)
		identity.add_child(mark)
		var heading = label(identity, str(metadata.get("origin_label", "Godot AI")))
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.tooltip_text = heading.text
		heading.add_theme_font_size_override("font_size", int(12 * EditorInterface.get_editor_scale()))
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
	for file_id in metadata.get("files", []): _file_card(column, str(file_id))
	if role == "assistant": _message_actions(record)
	activity_group = null
	if motion_enabled and not restoring and is_visible_in_tree():
		row.modulate.a = 0.0
		create_tween().tween_property(row, "modulate:a", 1.0, 0.12)
	_follow.call_deferred()
	return anchor

func _markdown(target: RichTextLabel, text: String) -> void:
	Markdown.render(target, text, EditorInterface.get_editor_scale())

func _size_user(record: Dictionary) -> void:
	var scale = EditorInterface.get_editor_scale()
	var available = maxf(thread.size.x, thread.custom_minimum_size.x)
	var font = get_theme_font("font", "Label")
	var width = 0.0
	for line in str(record["text"]).split("\n"):
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size", "Label")).x)
	var wanted = minf(maxf(64 * scale, width + 30 * scale), available * 0.74)
	if not record["metadata"].get("attachments", []).is_empty() or not record["metadata"].get("files", []).is_empty(): wanted = minf(320 * scale, available * 0.74)
	record["card"].custom_minimum_size.x = wanted
	record["card"].custom_maximum_size.x = wanted

func _render_content(record: Dictionary) -> void:
	var pieces = str(record["text"]).split("```") if record["rich"] else PackedStringArray([record["text"]])
	var blocks: Array = record["blocks"]
	for index in range(pieces.size()):
		var code_block = index % 2 == 1
		if index >= blocks.size():
			if code_block:
				var panel = PanelContainer.new()
				var surface = style(Color("0d1320"), 12)
				surface.set_content_margin_all(8 * EditorInterface.get_editor_scale())
				panel.add_theme_stylebox_override("panel", surface)
				record["body"].add_child(panel)
				var box = VBoxContainer.new()
				panel.add_child(box)
				var header = HBoxContainer.new()
				box.add_child(header)
				var language = label(header, "GDScript")
				language.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				language.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				language.add_theme_color_override("font_color", Color("9faac0"))
				var editor = CodeEdit.new()
				editor.editable = false
				editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
				editor.scroll_fit_content_height = true
				editor.custom_minimum_size.y = 54 * EditorInterface.get_editor_scale()
				editor.custom_maximum_size.y = 360 * EditorInterface.get_editor_scale()
				editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				editor.add_theme_font_size_override("font_size", int(13 * EditorInterface.get_editor_scale()))
				var colors = CodeHighlighter.new()
				for word in ["func", "var", "extends", "if", "else", "return", "class_name", "await", "for", "in", "const", "static", "signal", "true", "false", "null"]: colors.add_keyword_color(word, Color("c4a4fc"))
				colors.number_color = Color("91c9eb")
				colors.symbol_color = Color("b5bfd4")
				colors.function_color = Color("91c9eb")
				colors.member_variable_color = Color("e7eaf4")
				colors.add_color_region("\"", "\"", Color("b4d6a3"))
				colors.add_color_region("#", "", Color("7e8ba0"), true)
				editor.syntax_highlighter = colors
				var copy = icon_button(header, "Copy", "Copiază codul", func() -> void: DisplayServer.clipboard_set(editor.text))
				_compact_button(copy)
				box.add_child(editor)
				blocks.append({"node": panel, "editor": editor, "language": language, "copy": copy})
			else:
				var text = RichTextLabel.new()
				text.fit_content = true
				text.scroll_active = false
				text.selection_enabled = true
				text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				text.add_theme_constant_override("line_separation", int(4 * EditorInterface.get_editor_scale()))
				text.add_theme_constant_override("table_h_separation", int(12 * EditorInterface.get_editor_scale()))
				text.add_theme_constant_override("table_v_separation", int(7 * EditorInterface.get_editor_scale()))
				text.meta_clicked.connect(func(value: Variant) -> void:
					if Common.parse_url(str(value), true).get("ok", false): OS.shell_open(str(value)))
				record["body"].add_child(text)
				blocks.append({"node": text})
		var block: Dictionary = blocks[index]
		if code_block:
			var source = pieces[index]
			var language = source.get_slice("\n", 0).strip_edges().left(40) if "\n" in source else "Cod"
			block["language"].text = {"gdscript": "GDScript", "gd": "GDScript", "python": "Python", "json": "JSON", "csharp": "C#", "bash": "Shell", "": "Cod"}.get(language, language)
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
	_refresh_message_controls(record)

func _process(delta: float) -> void:
	activity_clock += delta
	if activity_clock >= 0.08:
		activity_clock = 0.0
		if activity_indicator != null and motion_enabled and _work_running(): activity_indicator.queue_redraw()
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
	for pair in [["Copy", "Copiază răspunsul", "copy"], ["Retry", "Reia sarcina întreruptă", "retry"], ["Changes", "Modificări / Undo", "changes"]]:
		var control = icon_button(actions, pair[0], pair[1], func() -> void: _message_action(record, pair[2]))
		control.set_meta("message_action", pair[2])
		_compact_button(control)
		control.disabled = record["streaming"]
		record["actions"].append(control)
	if record["metadata"].get("plan", false):
		var apply = button(actions, "Aplică planul", func() -> void: _message_action(record, "apply_plan"))
		apply.icon = _icon("Play")
		_compact_button(apply)
		apply.disabled = record["streaming"]
		record["actions"].append(apply)
	var more = MenuButton.new()
	more.icon = _icon("More")
	more.tooltip_text = "Mai multe acțiuni"
	more.custom_minimum_size = Vector2(32, 32) * EditorInterface.get_editor_scale()
	more.add_theme_constant_override("icon_max_width", int(16 * EditorInterface.get_editor_scale()))
	more.get_popup().add_item("Ramifică de aici", 0)
	more.get_popup().id_pressed.connect(func(id: int) -> void: _message_action(record, "fork" if id == 0 else "apply_plan"))
	more.disabled = record["streaming"]
	record["actions"].append(more)
	actions.add_child(more)
	_refresh_message_controls(record)

func _refresh_message_controls(record: Dictionary) -> void:
	for control in record.get("actions", []):
		var name = str(control.get_meta("message_action", ""))
		control.disabled = record["streaming"] or (name == "copy" and str(record["text"]).is_empty()) or (name == "changes" and not change_cards.has(str(record["metadata"].get("turn_id", ""))) and record["metadata"].get("changes", []).is_empty())
		if name == "changes": control.visible = not control.disabled
		if name == "retry":
			control.disabled = control.disabled or record["metadata"].get("run_status") == "completed"
			control.visible = record["metadata"].get("run_status") != "completed"

func set_turn_outcome(turn: String, status: String) -> void:
	for record in message_records:
		if record["metadata"].get("turn_id") != turn: continue
		record["metadata"]["run_status"] = status
		_refresh_message_controls(record)

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
		_compact_button(toggle)
		toggle.custom_minimum_size.y = 28 * EditorInterface.get_editor_scale()
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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
	activity_group.get_meta("toggle").text = "Activitate · %s  ▾" % entries.get_child_count()
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
	var svg = str(Icons.DATA.get(name, Icons.DATA["More"]))
	# Preserve upstream artwork and brand colors. Mono assets inherit the dark UI ink.
	svg = svg.replace("currentColor", "#dce1ef")
	var image = Image.new()
	if image.load_svg_from_string(svg, EditorInterface.get_editor_scale()) != OK: return null
	icon_cache[name] = ImageTexture.create_from_image(image)
	return icon_cache[name]

func provider_icon(profile: Dictionary) -> Texture2D:
	var issuer = str(profile.get("issuer", "custom"))
	if issuer == "qwen-cn": issuer = "qwen"
	if profile.get("kind") == "siwc": issuer = "openai"
	if profile.get("kind") == "companion":
		var service = (str(profile.get("account", "")) + " " + str(profile.get("name", ""))).to_lower()
		if "claude" in service: issuer = "anthropic"
		elif "gemini" in service: issuer = "gemini"
		elif "chatgpt" in service or "codex" in service: issuer = "openai"
		elif "kimi" in service: issuer = "kimi"
		elif "copilot" in service: return _icon("Provider_copilot")
		else: return _icon("Accounts")
	if not issuer in ["openai", "anthropic", "gemini", "deepseek", "openrouter", "qwen", "kimi", "mistral", "groq", "xai", "zai", "minimax", "nvidia", "siliconflow", "ollama", "lmstudio", "llamacpp"]: issuer = "custom"
	return _icon("Provider_" + issuer)

func section_icon(section: String) -> Texture2D:
	return _icon({"general": "Settings", "providers": "Providers", "accounts": "Accounts", "generation": "Generation", "mcp": "MCP", "integrations": "Integrations", "skills": "Skills", "automations": "Plan", "journal": "Journal", "agent": "File", "voice": "Microphone", "playtesting": "Play"}.get(section, "Settings"))

func set_workspace_expanded(value: bool) -> void:
	workspace_expanded = value
	if expand_button == null: return
	expand_button.icon = _icon("Collapse" if value else "Expand")
	expand_button.tooltip_text = "Restaurează panourile" if value else "Extinde chatul și ascunde panourile"
	expand_button.set_pressed_no_signal(value)

func _toggle_expanded() -> void:
	action.emit("expand", {})

func show_status(message: String, working: bool = false) -> void:
	status_revision += 1
	var revision = status_revision
	var changed = work_message != message
	work_message = message
	work_notice_running = working
	_refresh_activity(changed)
	if working or message.is_empty(): return
	await get_tree().create_timer(4.0).timeout
	if revision == status_revision:
		work_message = ""
		_refresh_activity(true)

func show_attachments(images: Array, references: Array, file_ids: Array = []) -> void:
	var signature = JSON.stringify(images.map(func(item: Dictionary) -> String: return str(item.get("name", "")) + str(str(item.get("data", "")).length()))) + JSON.stringify(references) + JSON.stringify(file_ids) + file_scope
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
	show_file_mentions(file_ids)
	attachment_chips.visible = attachment_chips.get_child_count() > 0

func set_context(used: int, limit: int, output: int = 0, estimated: bool = false) -> void:
	context_ratio = clampf(float(used) / limit, 0, 1) if limit > 0 and used > 0 else -1.0
	context_label.text = ("≈" if estimated else "") + str(roundi(context_ratio * 100)) + "%" if context_ratio >= 0 else "—"
	var detail = "Context: " + (str(used) if used > 0 else "necunoscut") + (" / %s tokeni" % limit if limit > 0 else " · limită necunoscută")
	if output > 0: detail += "\nIeșire: %s tokeni" % output
	if estimated: detail += "\nValoare estimată"
	for control in [context_indicator, context_label, context_gauge]: control.tooltip_text = detail
	context_gauge.queue_redraw()

func _open_options() -> void:
	_close_drawer()
	var wanted = Vector2i(310, 84) * EditorInterface.get_editor_scale()
	wanted.y = maxi(wanted.y, int(runtime_options.get_child(0).get_combined_minimum_size().y + 24 * EditorInterface.get_editor_scale()))
	var window = get_window()
	runtime_options.size = Vector2i(mini(wanted.x, window.size.x - 32), mini(wanted.y, window.size.y - 32))
	var origin = Vector2i(options_button.get_global_rect().position) + window.position
	runtime_options.position = Vector2i(clampi(origin.x, window.position.x + 12, window.position.x + window.size.x - runtime_options.size.x - 12), maxi(window.position.y + 12, origin.y - runtime_options.size.y - 8))
	runtime_options.popup()

func set_working(working: bool) -> void:
	if history_working != working:
		history_working = working
		_update_history_controls()
		if not working and not work_live: work_notice_running = false
		_refresh_activity()
	if stop_button != null and stop_button.visible != working:
		stop_button.visible = working
		_layout_composer()
	if options_button != null and mode_picker != null and mode_picker.selected >= 0:
		options_button.text = Common.MODES[mode_picker.selected]
		options_button.icon = _icon(Common.MODE_ICONS[mode_picker.selected])
		mode_picker.disabled = working
		for index in range(mode_buttons.size()):
			mode_buttons[index].disabled = working
			mode_buttons[index].set_pressed_no_signal(index == mode_picker.selected)

func show_welcome() -> void:
	thread.alignment = BoxContainer.ALIGNMENT_CENTER
	var heading = label(thread, "Ce construim astăzi?")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", int(24 * EditorInterface.get_editor_scale()))
	var hint = label(thread, "Trimite un mesaj sau atașează un fișier din proiect.")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("abb5c9"))

func _file_card(parent: Node, id: String) -> Control:
	if file_registry == null: return null
	var item = file_registry.describe(id, file_scope)
	if item.is_empty(): return null
	var card = PanelContainer.new()
	card.name = "File_" + id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", style(Color("202638"), 10))
	parent.add_child(card)
	var column = VBoxContainer.new()
	card.add_child(column)
	if not str(item.get("preview", "")).is_empty() and FileAccess.file_exists(item["preview"]):
		var texture = ImageTexture.create_from_image(Image.load_from_file(item["preview"]))
		var picture = TextureRect.new()
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size.y = 130 * EditorInterface.get_editor_scale()
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(picture)
	var heading = label(column, str(item["name"]))
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.tooltip_text = str(item["source"])
	var origin = label(column, "%s · %s · %s" % [str(item["kind"]).to_upper(), String.humanize_size(int(item["bytes"])), Time.get_datetime_string_from_unix_time(int(item["modified"])).replace("T", " ")])
	origin.add_theme_font_size_override("font_size", int(11 * EditorInterface.get_editor_scale()))
	origin.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var actions = HBoxContainer.new()
	column.add_child(actions)
	for spec in [["Inspect", "Deschide", "file_open"], ["Attach", "Menționează", "file_mention"], ["ArrowUp", "Trimite referința", "file_send"], ["Pin", "Fixează / eliberează", "file_pin"], ["Compare", "Compară", "file_compare"]]:
		var entry = icon_button(actions, spec[0], spec[1], func() -> void: action.emit(spec[2], {"id": id}))
		_compact_button(entry)
		if spec[2] == "file_pin":
			entry.toggle_mode = true
			entry.set_meta("file_pin_id", id)
			entry.set_pressed_no_signal(item.get("pinned", false))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var gesture = {"pressed": false, "start": Vector2.ZERO, "delta": Vector2.ZERO, "mentioned": false, "started": 0}
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event.device == -1: return
		if event is InputEventScreenTouch or event is InputEventMouseButton:
			if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT: return
			if event.pressed:
				gesture["pressed"] = true
				gesture["start"] = event.position
				gesture["delta"] = Vector2.ZERO
				gesture["mentioned"] = false
				gesture["started"] = Time.get_ticks_msec()
				_file_long_press(card, id, gesture, gesture["started"])
			elif gesture["pressed"]:
				gesture["pressed"] = false
				if not gesture["mentioned"] and Vector2(gesture["delta"]).length() < 10: action.emit("file_open", {"id": id})
		elif gesture["pressed"] and (event is InputEventScreenDrag or event is InputEventMouseMotion):
			gesture["delta"] = event.position - Vector2(gesture["start"])
			var delta: Vector2 = gesture["delta"]
			if not gesture["mentioned"] and delta.x > 48 * EditorInterface.get_editor_scale() and delta.x > absf(delta.y) * 2:
				gesture["mentioned"] = true
				action.emit("file_mention", {"id": id})
				card.accept_event()
				card.self_modulate = Color("c1a8f2")
				card.create_tween().tween_property(card, "self_modulate", Color.WHITE, 0.25))
	return card

func show_file_mentions(ids: Array) -> void:
	for id in ids:
		if file_registry == null: continue
		var item = file_registry.describe(str(id), file_scope)
		if item.is_empty(): continue
		var chip = button(attachment_chips, str(item["name"]).left(22) + " ×", func() -> void: action.emit("file_unmention", {"id": id}))
		_compact_button(chip)
		chip.tooltip_text = str(item["source"]) + " · referință trimisă la următorul mesaj"
		chip.icon = _icon("Models" if item["kind"] == "mesh" else ("Generation" if item["kind"] == "image" else "File"))
	attachment_chips.visible = attachment_chips.get_child_count() > 0

func show_changes(turn: String, changes: Array) -> void:
	if changes.is_empty(): return
	if not change_cards.has(turn) or not is_instance_valid(change_cards[turn]):
		var card = VBoxContainer.new()
		thread.add_child(card)
		change_cards[turn] = card
	var card: VBoxContainer = change_cards[turn]
	for child in card.get_children(): card.remove_child(child); child.queue_free()
	var heading = label(card, ("Propunere · " if turn.ends_with("-proposal") else "Modificări · ") + str(changes.size()))
	heading.add_theme_font_size_override("font_size", int(12 * EditorInterface.get_editor_scale()))
	for item in changes:
		var counts = "%s operații Undo" % item.get("operations", 0) if item.get("kind") == "scene" else ("+%s  −%s" % [item.get("added", 0), item.get("removed", 0)] if item.get("exact", false) else "binar / mare")
		var row = button(card, str(item["path"]).trim_prefix("res://") + "    " + counts + "    " + str(item["state"]), func() -> void: action.emit("changes", {"turn": turn, "path": item["path"]}))
		_compact_button(row)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for record in message_records:
		if record["metadata"].get("turn_id") == turn: _refresh_message_controls(record)

func show_store(items: Array) -> void:
	for item in items:
		var card = VBoxContainer.new()
		thread.add_child(card)
		var title = label(card, str(item.get("name", "Addon")))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label(card, str(item.get("publisher", "")) + " · " + str(item.get("license", "")))
		var actions = HFlowContainer.new()
		card.add_child(actions)
		var id = str(item["id"])
		var inspect = button(actions, "Detalii", func() -> void: action.emit("store_request", {"text": "Inspectează addonul Store cu ID " + JSON.stringify(id) + " și arată versiunile compatibile."}))
		_compact_button(inspect)
		for release in item.get("releases", []).slice(0, 3):
			var version = str(release.get("version", ""))
			var install = button(actions, "Instalează " + version, func() -> void: action.emit("store_request", {"text": "Instalează addonul Store cu ID " + JSON.stringify(id) + " versiunea " + JSON.stringify(version) + ". Verifică rezultatul înainte de activare."}))
			_compact_button(install)

func _file_long_press(card: Control, id: String, gesture: Dictionary, started: int) -> void:
	await get_tree().create_timer(0.55).timeout
	if not is_instance_valid(card) or not gesture["pressed"] or gesture["started"] != started or Vector2(gesture["delta"]).length() > 10 or gesture["mentioned"]: return
	gesture["mentioned"] = true
	var popup = PopupMenu.new()
	popup.theme = theme
	add_child(popup)
	var entries = [["Deschide", "file_open"], ["Menționează", "file_mention"], ["Trimite referința", "file_send"], ["Fixează / eliberează", "file_pin"], ["Compară", "file_compare"]]
	for entry in entries: popup.add_item(entry[0])
	popup.id_pressed.connect(func(index: int) -> void: action.emit(entries[index][1], {"id": id}))
	popup.popup_hide.connect(popup.queue_free)
	var origin = card.get_global_rect().position + Vector2(get_window().position)
	popup.position = Vector2i(origin)
	popup.popup()

func sync_file_pins(id: String) -> void:
	var item = file_registry.describe(id, file_scope)
	for button in thread.find_children("*", "Button", true, false):
		if button.get_meta("file_pin_id", "") == id: button.set_pressed_no_signal(item.get("pinned", false))
