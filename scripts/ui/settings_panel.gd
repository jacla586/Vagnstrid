class_name SettingsPanel
extends ColorRect
## The settings over a dimmed screen (main menu and Esc menu): controls, sound,
## graphics (a preset or each setting, "Custom" once one is changed), display. Every
## change is saved and applied at once (GameSettings.changed); grass range at the next
## map load. Close or Esc hides it.

const ROW_LABEL_WIDTH: float = 230.0
const CONTROL_WIDTH: float = 260.0

var _rows: VBoxContainer
## Graphics controls, refreshed when a preset sets them all.
var _preset: OptionButton
var _scale: HSlider
var _scale_value: Label
var _shadows: OptionButton
var _ssao: CheckButton
var _glow: CheckButton
var _aa: OptionButton
var _grass: OptionButton
var _detail: OptionButton
var _refreshing: bool = false


func _ready() -> void:
	GameSettings.load_settings()
	theme = MenuTheme.get_theme()
	color = Color(MenuTheme.SHADE, 0.75)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 560)
	center.add_child(panel)
	var style: StyleBox = panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var solid := (style as StyleBoxFlat).duplicate() as StyleBoxFlat
		solid.bg_color.a = 0.96
		panel.add_theme_stylebox_override("panel", solid)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	MenuTheme.add_title(box, "SETTINGS", 24)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	_build()
	var close := Button.new()
	close.text = "Close"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.custom_minimum_size.x = 110
	close.pressed.connect(hide)
	box.add_child(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("release_mouse")):
		hide()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var d: SettingsData = GameSettings.data()
	_heading("Controls")
	_slider("Mouse sensitivity", d.mouse_factor_min, d.mouse_factor_max, 0.05,
			GameSettings.mouse_factor, "%.2f×", func(v: float) -> void: GameSettings.mouse_factor = v)
	_check("Invert mouse up/down", GameSettings.invert_y,
			func(on: bool) -> void: GameSettings.invert_y = on)
	_heading("Sound")
	_slider("Master volume", 0.0, 100.0, 1.0, GameSettings.volume_master, "%d %%",
			func(v: float) -> void: GameSettings.volume_master = v)
	_slider("Effects", 0.0, 100.0, 1.0, GameSettings.volume_effects, "%d %%",
			func(v: float) -> void: GameSettings.volume_effects = v)
	_slider("Voices (radio, crew)", 0.0, 100.0, 1.0, GameSettings.volume_voice, "%d %%",
			func(v: float) -> void: GameSettings.volume_voice = v)
	_heading("Graphics")
	var presets := PackedStringArray(d.preset_names)
	presets.append("Custom")
	_preset = _choice("Quality", presets, _preset_index(), func(i: int) -> void:
		if i < d.preset_names.size():
			GameSettings.set_preset_values(i)
			_refresh_graphics()
		else:
			GameSettings.preset = GameSettings.CUSTOM)
	var scale_row: Array = _slider_row("Render resolution", 0.5, 1.0, 0.01, GameSettings.render_scale,
			"%d %%", func(v: float) -> void: GameSettings.render_scale = v, true)
	_scale = scale_row[0]
	_scale_value = scale_row[1]
	_shadows = _choice("Shadows", d.shadow_names, GameSettings.shadows,
			func(i: int) -> void: GameSettings.shadows = i, true)
	_ssao = _check("Ambient occlusion", GameSettings.ssao,
			func(on: bool) -> void: GameSettings.ssao = on, true)
	_glow = _check("Glow", GameSettings.glow, func(on: bool) -> void: GameSettings.glow = on, true)
	_aa = _choice("Anti-aliasing", d.aa_names, GameSettings.aa,
			func(i: int) -> void: GameSettings.aa = i, true)
	_grass = _choice("Grass range (next map)", d.grass_names, GameSettings.grass,
			func(i: int) -> void: GameSettings.grass = i, true)
	_detail = _choice("Mesh detail", d.detail_names, GameSettings.detail,
			func(i: int) -> void: GameSettings.detail = i, true)
	_heading("Display")
	_choice("Window", d.window_names, GameSettings.window_mode,
			func(i: int) -> void: GameSettings.window_mode = i)
	_check("V-sync", GameSettings.vsync, func(on: bool) -> void: GameSettings.vsync = on)
	var caps := PackedStringArray()
	var cap_index: int = 0
	for i: int in d.fps_caps.size():
		caps.append("No limit" if d.fps_caps[i] == 0 else str(d.fps_caps[i]))
		if d.fps_caps[i] == GameSettings.fps_cap:
			cap_index = i
	_choice("Frame rate limit", caps, cap_index,
			func(i: int) -> void: GameSettings.fps_cap = d.fps_caps[i])


func _preset_index() -> int:
	return GameSettings.preset if GameSettings.preset >= 0 else GameSettings.data().preset_names.size()


## After a preset: every graphics control shows its new value (without counting as a
## change of its own, which would make the preset "Custom").
func _refresh_graphics() -> void:
	_refreshing = true
	_preset.select(_preset_index())
	_scale.value = GameSettings.render_scale
	_scale_value.text = "%d %%" % roundi(GameSettings.render_scale * 100.0)
	_shadows.select(GameSettings.shadows)
	_ssao.button_pressed = GameSettings.ssao
	_glow.button_pressed = GameSettings.glow
	_aa.select(GameSettings.aa)
	_grass.select(GameSettings.grass)
	_detail.select(GameSettings.detail)
	_refreshing = false


## A setting changed: graphics ones make the preset Custom; then save and apply.
func _changed(graphics: bool) -> void:
	if _refreshing:
		return
	if graphics:
		GameSettings.preset = GameSettings.CUSTOM
		_refreshing = true
		_preset.select(_preset_index())
		_refreshing = false
	GameSettings.changed(get_tree())


# --- Rows ---------------------------------------------------------------------------

func _heading(text: String) -> void:
	var heading := Label.new()
	heading.text = text
	heading.add_theme_font_size_override("font_size", 14)
	heading.add_theme_color_override("font_color", MenuTheme.ACCENT)
	if _rows.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		_rows.add_child(gap)
	_rows.add_child(heading)


func _row(caption: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = ROW_LABEL_WIDTH
	label.add_theme_color_override("font_color", MenuTheme.TEXT)
	row.add_child(label)
	control.custom_minimum_size.x = CONTROL_WIDTH
	row.add_child(control)
	_rows.add_child(row)


func _slider(caption: String, lo: float, hi: float, step: float, value: float, fmt: String,
		set_value: Callable, graphics: bool = false) -> HSlider:
	return _slider_row(caption, lo, hi, step, value, fmt, set_value, graphics)[0]


## [slider, value label]: `fmt` shows the value (percent formats take 0..1 sliders × 100
## when hi <= 1).
func _slider_row(caption: String, lo: float, hi: float, step: float, value: float, fmt: String,
		set_value: Callable, graphics: bool = false) -> Array:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var shown := Label.new()
	shown.custom_minimum_size.x = 56
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shown.add_theme_color_override("font_color", MenuTheme.MUTED)
	var show: Callable = func(v: float) -> void:
		var x: float = v * 100.0 if hi <= 1.0 and fmt.contains("%%") else v
		shown.text = fmt % (roundi(x) if fmt.contains("%d") else x)
	show.call(value)
	slider.value_changed.connect(func(v: float) -> void:
		show.call(v)
		if _refreshing:
			return
		set_value.call(v)
		_changed(graphics))
	h.add_child(slider)
	h.add_child(shown)
	_row(caption, h)
	return [slider, shown]


func _check(caption: String, on: bool, set_value: Callable, graphics: bool = false) -> CheckButton:
	var b := CheckButton.new()
	b.button_pressed = on
	b.toggled.connect(func(v: bool) -> void:
		if _refreshing:
			return
		set_value.call(v)
		_changed(graphics))
	_row(caption, b)
	return b


func _choice(caption: String, items: PackedStringArray, selected: int, set_value: Callable,
		graphics: bool = false) -> OptionButton:
	var o := OptionButton.new()
	for item: String in items:
		o.add_item(item)
	o.select(clampi(selected, 0, items.size() - 1))
	o.item_selected.connect(func(i: int) -> void:
		if _refreshing:
			return
		set_value.call(i)
		_changed(graphics))
	_row(caption, o)
	return o
