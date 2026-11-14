class_name ControlsPanel
extends ColorRect
## The controls over a dimmed screen: sections of key + short explanation, read from
## data/ui/controls.txt (see its header). Keys come from the Input Map, so they always
## match the project's bindings. Close or Esc hides it.

const CONTROLS_PATH: String = "res://data/ui/controls.txt"
const KEY_COLUMN_WIDTH: float = 150.0

var _close: Button


func _ready() -> void:
	color = Color(MenuTheme.SHADE, 0.75)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 560)
	center.add_child(panel)
	# nearly opaque, so the menu doesn't show through the text
	var style: StyleBox = panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var solid := (style as StyleBoxFlat).duplicate() as StyleBoxFlat
		solid.bg_color.a = 0.96
		panel.add_theme_stylebox_override("panel", solid)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	MenuTheme.add_title(box, "CONTROLS", 24)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	_fill(list)
	_close = Button.new()
	_close.text = "Close"
	_close.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close.custom_minimum_size.x = 110
	_close.pressed.connect(hide)
	box.add_child(_close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


func _fill(list: VBoxContainer) -> void:
	for line: String in FileAccess.get_file_as_string(CONTROLS_PATH).split("\n"):
		line = line.strip_edges()
		if line.is_empty() or (line.begins_with("#") and not line.begins_with("##")):
			continue
		if line.begins_with("##"):
			var heading := Label.new()
			heading.text = line.trim_prefix("##").strip_edges()
			heading.add_theme_font_size_override("font_size", 14)
			heading.add_theme_color_override("font_color", MenuTheme.ACCENT)
			if list.get_child_count() > 0:
				var gap := Control.new()
				gap.custom_minimum_size.y = 6
				list.add_child(gap)
			list.add_child(heading)
			continue
		var parts: PackedStringArray = line.split("|", true, 1)
		if parts.size() < 2:
			continue
		var actions: PackedStringArray = parts[0].strip_edges().split(",", false)
		list.add_child(_row(actions, expand(parts[1].strip_edges())))


func _row(actions: PackedStringArray, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var keys := Label.new()
	var names: PackedStringArray = []
	for action: String in actions:
		var k: String = key_of(action.strip_edges())
		if not k.is_empty() and not names.has(k):
			names.append(k)
	keys.text = " ".join(names) if names.size() == 4 else " / ".join(names)
	keys.custom_minimum_size.x = KEY_COLUMN_WIDTH
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.add_theme_font_size_override("font_size", 13)
	keys.add_theme_color_override("font_color", MenuTheme.TEXT)
	row.add_child(keys)
	var what := Label.new()
	what.text = text
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	what.add_theme_font_size_override("font_size", 12)
	what.add_theme_color_override("font_color", MenuTheme.MUTED)
	row.add_child(what)
	return row


## {action} -> its key.
## `{action}` in `text` -> that action's key (mouse buttons in lower case mid-sentence).
static func expand(text: String) -> String:
	var re := RegEx.create_from_string("\\{([a-z_0-9]+)\\}")
	var out: String = text
	for m: RegExMatch in re.search_all(text):
		var k: String = key_of(m.get_string(1))
		if k.contains(" "):   # mouse names mid-sentence: "left click"
			k = k.to_lower()
		out = out.replace(m.get_string(0), k)
	return out


## The first key or mouse button bound to an action, as the player would name it.
static func key_of(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code: Key = k.keycode
			if code == KEY_NONE and k.physical_keycode != KEY_NONE:
				code = DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
			if code == KEY_NONE:
				code = k.physical_keycode
			return OS.get_keycode_string(code)
		if ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					return "Left click"
				MOUSE_BUTTON_RIGHT:
					return "Right click"
				MOUSE_BUTTON_MIDDLE:
					return "Middle click"
				MOUSE_BUTTON_WHEEL_UP:
					return "Wheel up"
				MOUSE_BUTTON_WHEEL_DOWN:
					return "Wheel down"
				_:
					return "Mouse %d" % (ev as InputEventMouseButton).button_index
	return ""
