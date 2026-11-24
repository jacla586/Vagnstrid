class_name MainMenu
extends Control
## Start menu: name, map, match settings, then Single player, Host (bots on/off)
## and Join (host's IP, e.g. a Tailscale address). Built in code over a picture of a
## fight (assets/ui/menu_background.jpg, made by tools/render_menu_background.gd).

const GARAGE_SCENE: String = "res://scenes/menu/garage.tscn"
## Only scenarios: every bare map (scenes/maps/) is the base of some.
const MAP_DIRS: Array[String] = ["res://scenes/scenarios/"]
const COLUMN_WIDTH: float = 330.0
const COLUMN_MARGIN: float = 44.0
const CREDITS_PATH: String = "res://data/ui/credits.txt"
## Map list headings, in this order; a scenario's group comes from its name
## (`<map>_koth`, `<map>_thunder[_variant]`, `<map>_free`; exported scenes can't be
## read as text).
const GROUPS: Array[String] = ["King of the Hill", "Thunder Road", "Free fight"]
const GROUP_TAGS: Array[String] = ["_koth", "_thunder", "_free"]
## Place names as shown (scene names have no å, ä, ö).
const PLACE_NAMES: Dictionary = {
	"vidingsjo": "Vidingsjö", "linghem": "Linghem", "campus": "Campus",
	"road_to_science": "Road to Science", "corson": "Corson",
	"peking": "Peking (Norrköping)", "vidingsjo_xl": "Vidingsjö XL",
}

var _name: LineEdit
var _map: OptionButton
var _bots: CheckButton
var _ip: LineEdit
var _status: Label
var _maps: PackedStringArray = []
var _team_size: SpinBox
var _allies: SpinBox
var _weather: OptionButton
var _credits: Control
var _controls: ControlsPanel
var _settings: SettingsPanel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuTheme.get_theme()
	MenuTheme.add_backdrop(self, true)
	# A fixed column on the left over the darkened side of the picture (no scrolling).
	var margin := MarginContainer.new()
	margin.anchor_bottom = 1.0
	margin.offset_right = COLUMN_WIDTH + 2.0 * COLUMN_MARGIN
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, COLUMN_MARGIN)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)
	_add_title(box)

	_name = LineEdit.new()
	_name.text = NetSession.instance.player_name
	_name.placeholder_text = "Name"
	_name.text_changed.connect(func(t: String) -> void:
		MatchSettings.set_player_name(t)
		if not t.strip_edges().is_empty():
			NetSession.instance.player_name = t.strip_edges())
	box.add_child(_field("Name", _name))

	var garage: Button = _button("Garage", func() -> void:
		get_tree().change_scene_to_file(GARAGE_SCENE))
	box.add_child(garage)
	# The tutorial: highlighted until it has been played through once.
	var tutorial: Button = _button("Tutorial", func() -> void:
		NetSession.instance.player_name = _name.text
		Weather.resolve()
		NetSession.instance.play_offline(NetSession.TUTORIAL_MAP))
	if not TutorialMode.is_done():
		MenuTheme.make_primary(tutorial)
		tutorial.text = "New here? Tutorial"
	box.add_child(tutorial)
	var help_row := HBoxContainer.new()
	help_row.add_theme_constant_override("separation", 12)
	for b: Button in [_button("Controls", _show_controls), _button("Settings", _show_settings)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		help_row.add_child(b)
	box.add_child(help_row)

	_map = OptionButton.new()
	_maps = find_maps()
	var map_field: Control = _field("Map", _map)
	var map_caption: Label = map_field.get_child(0)
	var by_group: Array[PackedStringArray] = []
	for g: String in GROUPS:
		by_group.append(PackedStringArray())
	for path: String in _maps:
		by_group[group_of(path)].append(path)
	for g: int in GROUPS.size():
		if by_group[g].is_empty():
			continue
		_map.add_separator(GROUPS[g])
		for path: String in by_group[g]:
			_map.add_item(map_title(path))
			var i: int = _map.item_count - 1
			_map.set_item_metadata(i, path)
			_map.set_item_tooltip(i, GROUPS[g])
			if path == NetSession.DEFAULT_MAP or _map.selected < 0:
				_map.select(i)
	box.add_child(map_field)

	# 0 = the map's own number; bots fill empty places.
	_team_size = SpinBox.new()
	_team_size.min_value = 0
	_team_size.max_value = MatchSettings.MAX_TEAM_SIZE
	_team_size.step = 1
	_team_size.rounded = true
	_team_size.update_on_text_changed = true
	MatchSettings.load_settings()
	_team_size.value = MatchSettings.team_size
	_team_size.value_changed.connect(func(v: float) -> void: MatchSettings.set_team_size(roundi(v)))
	_team_size.tooltip_text = "0 = map default"
	_weather = OptionButton.new()
	var ids: PackedStringArray = [Weather.RANDOM]
	ids.append_array(Weather.PRESETS)
	for i: int in ids.size():
		var preset: WeatherData = Weather.load_preset(ids[i]) if ids[i] != Weather.RANDOM else null
		_weather.add_item(preset.display_name if preset != null else "Random", i)
		_weather.set_item_metadata(i, ids[i])
		if ids[i] == MatchSettings.weather:
			_weather.select(i)
	_weather.item_selected.connect(func(i: int) -> void:
		MatchSettings.set_weather(str(_weather.get_item_metadata(i))))
	var match_row := HBoxContainer.new()
	match_row.add_theme_constant_override("separation", 12)
	var size_field: Control = _field("Tanks per team", _team_size)
	# Free fight has no team size: bot tanks on the players' side instead.
	_allies = SpinBox.new()
	_allies.min_value = 0
	_allies.max_value = MatchSettings.MAX_FREE_ALLIES
	_allies.step = 1
	_allies.rounded = true
	_allies.update_on_text_changed = true
	_allies.value = MatchSettings.free_allies
	_allies.value_changed.connect(func(v: float) -> void: MatchSettings.set_free_allies(roundi(v)))
	_allies.tooltip_text = "Bot tanks fighting on your side"
	var allies_field: Control = _field("Bot allies", _allies)
	var weather_field: Control = _field("Weather", _weather)
	size_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	allies_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weather_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match_row.add_child(size_field)
	match_row.add_child(allies_field)
	match_row.add_child(weather_field)
	box.add_child(match_row)
	var free_group: int = GROUP_TAGS.find("_free")
	var show_group: Callable = func(i: int) -> void:
		map_caption.text = "Map – " + _map.get_item_tooltip(i) if i >= 0 else "Map"
		var free: bool = i >= 0 and group_of(str(_map.get_item_metadata(i))) == free_group
		size_field.visible = not free
		allies_field.visible = free
	_map.item_selected.connect(show_group)
	show_group.call(_map.selected)

	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	var single: Button = _button("Single player", _on_single)
	MenuTheme.make_primary(single)
	box.add_child(single)

	var host_row := HBoxContainer.new()
	host_row.add_theme_constant_override("separation", 12)
	var host: Button = _button("Host game", _on_host)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_row.add_child(host)
	_bots = CheckButton.new()
	_bots.text = "Bots"
	host_row.add_child(_bots)
	box.add_child(host_row)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_ip = LineEdit.new()
	_ip.text = "127.0.0.1"
	_ip.placeholder_text = "Host address"
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip)
	var join: Button = _button("Join game", _on_join)
	join.custom_minimum_size.x = 104
	join_row.add_child(join)
	box.add_child(join_row)

	_status = MenuTheme.caption("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = NetSession.instance.status
	box.add_child(_status)
	NetSession.instance.status_changed.connect(func(t: String) -> void:
		if is_instance_valid(_status):
			_status.text = t)
	var credits: Button = _button("Credits", _show_credits)
	credits.flat = true
	credits.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	credits.add_theme_color_override("font_color", MenuTheme.MUTED)
	credits.add_theme_font_size_override("font_size", 12)
	box.add_child(credits)

	# Quit in the bottom right corner, away from the column (overlays added later cover it).
	var quit: Button = _button("Quit", func() -> void: get_tree().quit())
	quit.custom_minimum_size.x = 110
	quit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	quit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	quit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(quit)


func _unhandled_input(event: InputEvent) -> void:
	if _credits != null and _credits.visible and event.is_action_pressed("ui_cancel"):
		_credits.hide()
		get_viewport().set_input_as_handled()


## Keys and what they do (ControlsPanel, data/ui/controls.txt).
func _show_controls() -> void:
	if _controls == null:
		_controls = ControlsPanel.new()
		add_child(_controls)
	_controls.show()


## Mouse, sound, graphics and display (SettingsPanel, GameSettings).
func _show_settings() -> void:
	if _settings == null:
		_settings = SettingsPanel.new()
		add_child(_settings)
	_settings.show()


## Who made what (data/ui/credits.txt) over a dimmed menu; Close or Esc hides it.
func _show_credits() -> void:
	if _credits != null:
		_credits.show()
		return
	_credits = ColorRect.new()
	(_credits as ColorRect).color = Color(MenuTheme.SHADE, 0.75)
	_credits.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_credits)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 500)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	MenuTheme.add_title(box, "CREDITS", 24)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var text := Label.new()
	text.text = FileAccess.get_file_as_string(CREDITS_PATH)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 12)
	text.add_theme_color_override("font_color", MenuTheme.TEXT)
	scroll.add_child(text)
	var close: Button = _button("Close", func() -> void: _credits.hide())
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.custom_minimum_size.x = 110
	box.add_child(close)


func _add_title(box: Container) -> void:
	MenuTheme.add_title(box, "VAGNSTRID", 40)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	box.add_child(gap)


## A small caption above a control.
func _field(caption: String, control: Control) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(MenuTheme.caption(caption))
	v.add_child(control)
	return v


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b


## Scenarios left out of the map list and the server vote while they're being worked on
## (file names without .tscn; the scenes stay, `--map` still starts them).
const HIDDEN_SCENARIOS: PackedStringArray = ["peking_thunder"]


static func find_maps() -> PackedStringArray:
	var out: PackedStringArray = []
	for dir: String in MAP_DIRS:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f: String in d.get_files():
			var name_: String = f.trim_suffix(".remap")
			if name_.ends_with(".tscn") and not name_.get_basename().ends_with(NetSession.TUTORIAL_TAG) \
					and not HIDDEN_SCENARIOS.has(name_.get_basename()):
				out.append(dir + name_)
	return out


## Index into GROUPS by the scene's name tag (no tag: the last group).
static func group_of(path: String) -> int:
	var name_: String = path.get_file().get_basename()
	for g: int in GROUP_TAGS.size():
		if name_.find(GROUP_TAGS[g]) > 0:
			return g
	return GROUPS.size() - 1


## "vidingsjo_thunder_red" -> "Vidingsjö – Red", "campus_koth" -> "Campus".
static func map_title(path: String) -> String:
	var name_: String = path.get_file().get_basename()
	var variant: String = ""
	for tag: String in GROUP_TAGS:
		var at: int = name_.find(tag)
		if at > 0:
			variant = name_.substr(at + tag.length()).trim_prefix("_")
			name_ = name_.left(at)
			break
	var title: String = PLACE_NAMES.get(name_, name_.capitalize())
	return title + (" – " + variant.capitalize() if variant != "" else "")


func _selected_map() -> String:
	if _map.selected < 0:
		return NetSession.DEFAULT_MAP
	return str(_map.get_item_metadata(_map.selected))


func _on_host() -> void:
	NetSession.instance.player_name = _name.text
	Weather.resolve()
	NetSession.instance.host(_selected_map(), _bots.button_pressed)


func _on_join() -> void:
	NetSession.instance.player_name = _name.text
	NetSession.instance.join(_ip.text.strip_edges())


func _on_single() -> void:
	Weather.resolve()
	NetSession.instance.play_offline(_selected_map())


## "King of the Hill: Campus" (the dedicated server's vote list).
static func scenario_label(path: String) -> String:
	return "%s: %s" % [GROUPS[group_of(path)], map_title(path)]
