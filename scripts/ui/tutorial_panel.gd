class_name TutorialPanel
extends Control
## The tutorial's HUD (made by TutorialMode): "TRAINING · STEP 3 OF 9 · BINOCULARS" and the
## instruction at the top, a tick when a stage is done, short hints under it, and bottom
## right "HOLD <key> TO SKIP STEP" with a ring that fills while the key is held. At the end
## a TRAINING COMPLETE card with Bot hunt and Main menu.

const TOP_Y: float = 56.0
const WIDTH: float = 640.0
const RING_RADIUS: float = 11.0
const HINT_S: float = 4.0
const DONE_COLOR: Color = Color(0.45, 0.85, 0.45)

var _heading: Label
var _text: Label
var _hint: Label
var _skip: Label
var _skip_progress: float = 0.0
var _hint_left: float = 0.0
var _end_shown: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MenuTheme.get_theme()
	_heading = _label(13, MenuTheme.ACCENT, TOP_Y)
	_text = _label(19, MenuTheme.TEXT, TOP_Y + 22.0)
	_hint = _label(15, MenuTheme.ACCENT_HOVER, TOP_Y + 84.0)
	_skip = Label.new()
	_skip.add_theme_font_size_override("font_size", 12)
	_skip.add_theme_color_override("font_color", MenuTheme.MUTED)
	_skip.add_theme_color_override("font_outline_color", Color.BLACK)
	_skip.add_theme_constant_override("outline_size", 4)
	_skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.offset_left = -330.0
	_skip.offset_right = -48.0
	_skip.offset_top = -170.0
	_skip.offset_bottom = -150.0
	var key: String = ControlsPanel.key_of("skip_tutorial_step")
	_skip.text = "HOLD %s TO SKIP STEP" % (key.to_upper() if key != "" else "BACKSPACE")
	add_child(_skip)


func _label(size: int, color: Color, y: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.offset_left = -WIDTH * 0.5
	l.offset_right = WIDTH * 0.5
	l.offset_top = y
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func show_step(lesson: int, lessons: int, title: String, text: String) -> void:
	_heading.text = "TRAINING  ·  STEP %d OF %d  ·  %s" % [lesson, lessons, title.to_upper()]
	_heading.add_theme_color_override("font_color", MenuTheme.ACCENT)
	_text.text = text


func show_done() -> void:
	_heading.text = "✓  DONE"
	_heading.add_theme_color_override("font_color", DONE_COLOR)


func show_hint(text: String) -> void:
	_hint.text = text
	_hint_left = HINT_S


func set_skip_progress(share: float) -> void:
	share = clampf(share, 0.0, 1.0)
	if is_equal_approx(share, _skip_progress):
		return
	_skip_progress = share
	_skip.add_theme_color_override("font_color", MenuTheme.TEXT if share > 0.0 else MenuTheme.MUTED)
	queue_redraw()


func _process(delta: float) -> void:
	if _hint_left > 0.0:
		_hint_left -= delta
		if _hint_left <= 0.0:
			_hint.text = ""


func _draw() -> void:
	var centre := Vector2(size.x - 48.0 + RING_RADIUS + 8.0, size.y - 160.0)
	draw_arc(centre, RING_RADIUS, 0.0, TAU, 32, Color(1, 1, 1, 0.25), 3.0, true)
	if _skip_progress > 0.0:
		draw_arc(centre, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * _skip_progress, 32,
				MenuTheme.ACCENT, 3.0, true)


## The end card: title, text and the way on (frees the mouse).
func show_end(title: String, text: String, next_scenario: String) -> void:
	_heading.text = ""
	_text.text = ""
	_skip.visible = false
	_skip_progress = 0.0
	queue_redraw()
	var shade := ColorRect.new()
	shade.color = Color(MenuTheme.SHADE, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	MenuTheme.add_title(box, title, 26)
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", MenuTheme.TEXT)
	box.add_child(body)
	var hunt := Button.new()
	hunt.text = "Bot hunt"
	MenuTheme.make_primary(hunt)
	hunt.pressed.connect(func() -> void:
		Weather.resolve()
		NetSession.instance.play_offline(next_scenario))
	box.add_child(hunt)
	var menu := Button.new()
	menu.text = "Main menu"
	menu.pressed.connect(func() -> void: NetSession.instance.leave())
	box.add_child(menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)
	_end_shown = true



func _input(_event: InputEvent) -> void:
	if _end_shown and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
