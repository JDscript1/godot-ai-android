@tool
extends VBoxContainer
## Hosts the unmodified official web frontend inside a native Android view.
## Shares only the Ziva process model, never the assistant's harness or credentials.
var bridge: Node
var backend: RefCounted
var settings_panel: Control
var status: Label
var primary: Button
var stop: Button
var reload_ui: Button
var hint: Label
var body: Control
var last_embed: Dictionary = {}
var embedded = false
var error_text = ""

func configure(native_bridge: Node, model: RefCounted, panel: Control) -> void:
	bridge = native_bridge
	backend = model
	settings_panel = panel

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var bar = HFlowContainer.new()
	bar.name = "ZivaToolbar"
	add_child(bar)
	status = Label.new()
	status.text = "Ziva"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(status)
	primary = _button(bar, "Pornește Ziva", _start)
	primary.disabled = true
	stop = _button(bar, "Oprește", func() -> void: _action("stop"))
	reload_ui = _button(bar, "Reîncarcă", func() -> void: _sync_embed(true))
	_button(bar, "Configurare", _settings)
	_button(bar, "Verifică", func() -> void: backend.refresh())
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	body = Control.new()
	body.name = "OfficialZivaUI"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	visibility_changed.connect(_visibility_changed)
	_bind_backend()
	_refresh()

func _bind_backend() -> void:
	# Native hosts can construct this tab before the shared panel enters the tree.
	if backend == null and is_instance_valid(settings_panel): backend = settings_panel.get("ziva")
	if backend != null and not backend.changed.is_connected(_refresh):
		backend.changed.connect(_refresh)
		backend.refresh()

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _start() -> void:
	_action("start" if backend.state.get("installed", false) else "install")

func _action(action: String) -> void:
	var result: Dictionary = backend.request(action, backend.project_directory)
	error_text = "" if result.get("ok", false) else str(result.get("error", "Operația Ziva nu a pornit."))
	_refresh()

func _settings() -> void:
	_hide_embed()
	if bridge != null and bridge.has_method("open_settings"):
		bridge.call("open_settings", "ziva")
	elif settings_panel != null:
		settings_panel.call("open_settings", "ziva")

func _refresh() -> void:
	if status == null or backend == null: return
	var state: Dictionary = backend.state
	var enabled = state.get("ok", false) and state.get("enabled", false)
	var installed = bool(state.get("installed", false))
	var working = bool(state.get("busy", false))
	var project = not backend.project_directory.is_empty()
	var linux_ready = settings_panel != null and settings_panel.integrations != null and settings_panel.integrations.linux.available()
	status.text = backend.caption()
	primary.text = "Pornește Ziva" if installed else "Instalează Ziva + Godot"
	primary.visible = not working
	primary.disabled = not enabled or not linux_ready or (installed and not project) or (settings_panel != null and settings_panel.busy)
	stop.visible = working
	stop.disabled = not enabled
	reload_ui.disabled = not _can_embed()
	hint.text = "Ziva folosește interfața și autentificarea oficială. Editorul Linux separat lucrează pe fișierele proiectului; evită editările simultane."
	if not enabled: hint.text = "Disponibil în aplicația separată Godot AI Ziva."
	elif not linux_ready: hint.text = "Runtime Linux se pregătește. Poți verifica starea în Configurare → Integrări."
	elif working and not state.get("running", false): hint.text = str(state.get("message", "Pregătesc Ziva…"))
	elif not installed: hint.text = "Instalează pluginul oficial și Godot Linux ARM64 (~295 MB descărcați; aproximativ 1 GB necesar)."
	elif not project: hint.text = "Deschide un proiect pentru a folosi Ziva."
	elif state.get("running", false) and not state.get("same_project", false): hint.text = "Ziva rulează pentru alt proiect. Oprește sesiunea, apoi pornește proiectul curent."
	if not error_text.is_empty(): hint.text = error_text
	_sync_embed()

func _can_embed() -> bool:
	return backend != null and not backend.project_directory.is_empty() and backend.state.get("enabled", false) and backend.state.get("running", false) and backend.state.get("same_project", false) and int(backend.state.get("ui_port", 0)) > 0

func _process(_delta: float) -> void:
	if backend == null: _bind_backend()
	if backend == null or not is_visible_in_tree(): return
	if Time.get_ticks_msec() - backend.last_refresh > 1500: backend.refresh()
	_sync_embed()

func _visibility_changed() -> void:
	if not is_visible_in_tree(): _hide_embed()
	elif backend != null: backend.refresh()

func _has_popup() -> bool:
	for window in get_viewport().get_embedded_subwindows():
		if window.visible: return true
	return false

func _bounds() -> Rect2:
	var viewport_rect = get_viewport().get_visible_rect()
	if viewport_rect.size.x <= 0 or viewport_rect.size.y <= 0: return Rect2()
	var rect = body.get_global_rect()
	return Rect2((rect.position - viewport_rect.position) / viewport_rect.size, rect.size / viewport_rect.size)

func _sync_embed(force_reload: bool = false) -> void:
	if body == null or not is_inside_tree(): return
	var blocked = settings_panel != null and settings_panel.settings_window != null and settings_panel.settings_window.visible
	var active = is_visible_in_tree() and _can_embed() and not blocked and not _has_popup()
	if not active:
		_hide_embed()
		return
	var rect = _bounds()
	if rect.size.x <= 0 or rect.size.y <= 0: return
	var key = {"bounds": rect, "port": backend.state.get("ui_port", 0)}
	if key == last_embed and not force_reload: return
	var result: Dictionary = backend.embed(rect, true, force_reload)
	embedded = bool(result.get("ok", false))
	last_embed = key if embedded else {}
	if not embedded:
		# Keep a failed WebView attach visible instead of retrying every frame.
		error_text = str(result.get("error", "Interfața oficială nu s-a deschis."))
		hint.text = error_text
		last_embed = key

func _hide_embed() -> void:
	if embedded and backend != null: backend.embed(Rect2(), false)
	embedded = false
	last_embed = {}

func _exit_tree() -> void:
	_hide_embed()
	if backend != null and backend.changed.is_connected(_refresh): backend.changed.disconnect(_refresh)
