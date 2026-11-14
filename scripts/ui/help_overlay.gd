class_name HelpOverlay
extends Control
## Player rig HUD: F1 (show_help) shows the controls (ControlsPanel) over the match, the
## mouse freed meanwhile and captured again after. The first time a player is in a match
## (the mouse captured) a short card of tips (data/ui/intro.txt) shows for intro_s; seen
## once per install (user://settings.cfg, "help" / "intro_seen").

const INTRO_PATH: String = "res://data/ui/intro.txt"
const SETTINGS_PATH: String = "user://settings.cfg"
const KEY_COLUMN_WIDTH: float = 120.0

## The tips card stays this long (s), fading over the last second.
@export var intro_s: float = 25.0
@export var intro_top_share: float = 0.16

var _controls: ControlsPanel
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _intro: PanelContainer
var _intro_left: float = 0.0
var _intro_done: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_intro_done = bool(cfg.get_value("help", "intro_seen", false))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("show_help"):
		_toggle_controls()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _intro_done and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_show_intro()
	if _intro != null:
		_intro_left -= delta
		_intro.modulate.a = clampf(_intro_left, 0.0, 1.0)
		if _intro_left <= 0.0:
			_intro.queue_free()
			_intro = null


func _toggle_controls() -> void:
	if _intro != null:
		_intro_left = minf(_intro_left, 0.0)
	if _controls == null:
		_controls = ControlsPanel.new()
		_controls.theme = MenuTheme.get_theme()
		_controls.visible = false
		add_child(_controls)
		_controls.hidden.connect(func() -> void:
			if _mouse_before == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	if _controls.visible:
		_controls.hide()
		return
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_controls.show()


func _show_intro() -> void:
	_intro_done = true
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("help", "intro_seen", true)
	cfg.save(SETTINGS_PATH)
	var lines: PackedStringArray = []
	for line: String in FileAccess.get_file_as_string(INTRO_PATH).split("\n"):
		line = line.strip_edges()
		if not line.is_empty() and not line.begins_with("# "):
			lines.append(line)
	if lines.is_empty():
		return
	_intro = PanelContainer.new()
	_intro.theme = MenuTheme.get_theme()
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_intro.anchor_top = intro_top_share
	_intro.anchor_bottom = intro_top_share
	_intro.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_intro)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_intro.add_child(box)
	MenuTheme.add_title(box, lines[0], 18)
	for i: int in range(1, lines.size()):
		var parts: PackedStringArray = lines[i].split("|", true, 1)
		if parts.size() < 2:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var key := Label.new()
		key.text = ControlsPanel.key_of(parts[0].strip_edges())
		key.custom_minimum_size.x = KEY_COLUMN_WIDTH
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.add_theme_color_override("font_color", MenuTheme.ACCENT)
		row.add_child(key)
		var text := Label.new()
		text.text = ControlsPanel.expand(parts[1].strip_edges())
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = 440
		text.add_theme_color_override("font_color", MenuTheme.TEXT)
		row.add_child(text)
		box.add_child(row)
	_intro_left = intro_s
