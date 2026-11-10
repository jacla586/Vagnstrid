class_name MainMenu
extends Control
## Start menu: name, tank, map, match settings, then Single player, Host (bots on/off)
## and Join (host's IP, e.g. a Tailscale address). Built in code over a picture of a
## fight (assets/ui/menu_background.jpg, made by tools/render_menu_background.gd).

const GARAGE_SCENE: String = "res://scenes/menu/garage.tscn"
const MAP_DIRS: Array[String] = ["res://scenes/scenarios/", "res://scenes/maps/"]
const COLUMN_WIDTH: float = 330.0
const COLUMN_MARGIN: float = 44.0

var _name: LineEdit
var _map: OptionButton
var _bots: CheckButton
var _ip: LineEdit
var _status: Label
var _maps: PackedStringArray = []
var _tank: OptionButton
var _team_size: SpinBox
var _weather: OptionButton
var _tank_configs: Array[TankConfig] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuTheme.get_theme()
	MenuTheme.add_backdrop(self, true)
	# A column on the left over the darkened side of the picture, scrolling if the
	# window is too low for everything.
	var scroll := ScrollContainer.new()
	scroll.anchor_bottom = 1.0
	scroll.offset_right = COLUMN_WIDTH + 2.0 * COLUMN_MARGIN
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, COLUMN_MARGIN)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)
	_add_title(box)

	_name = LineEdit.new()
	_name.text = NetSession.instance.player_name
	_name.placeholder_text = "Name"
	box.add_child(_field("Name", _name))

	_tank = OptionButton.new()
	_fill_tanks()
	_tank.item_selected.connect(func(i: int) -> void:
		TankConfigs.select(_tank_configs[i]))
	var tank_row := HBoxContainer.new()
	tank_row.add_theme_constant_override("separation", 8)
	_tank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tank_row.add_child(_tank)
	tank_row.add_child(_button("Garage", func() -> void: get_tree().change_scene_to_file(GARAGE_SCENE)))
	box.add_child(_field("Tank", tank_row))

	_map = OptionButton.new()
	_maps = _find_maps()
	for i: int in _maps.size():
		_map.add_item(_maps[i].get_file().get_basename().capitalize(), i)
		if _maps[i] == NetSession.DEFAULT_MAP:
			_map.select(i)
	box.add_child(_field("Map", _map))

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
	var weather_field: Control = _field("Weather", _weather)
	size_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weather_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match_row.add_child(size_field)
	match_row.add_child(weather_field)
	box.add_child(match_row)

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


func _add_title(box: Container) -> void:
	MenuTheme.add_title(box, "VAGNSTRID", 40)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	box.add_child(gap)


## The tank list: the presets, then the player's own garage configs.
func _fill_tanks() -> void:
	_tank_configs = TankConfigs.presets()
	_tank_configs.append_array(TankConfigs.saved())
	_tank.clear()
	var chosen: TankConfig = TankConfigs.get_selected()
	for i: int in _tank_configs.size():
		var c: TankConfig = _tank_configs[i]
		_tank.add_item(c.display_name)
		if chosen != null and c.resource_path == chosen.resource_path:
			_tank.select(i)


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


func _find_maps() -> PackedStringArray:
	var out: PackedStringArray = []
	for dir: String in MAP_DIRS:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f: String in d.get_files():
			var name_: String = f.trim_suffix(".remap")
			if name_.ends_with(".tscn"):
				out.append(dir + name_)
	return out


func _selected_map() -> String:
	return _maps[_map.selected] if _map.selected >= 0 else NetSession.DEFAULT_MAP


func _on_host() -> void:
	NetSession.instance.player_name = _name.text
	Weather.resolve()
	NetSession.instance.host(_selected_map(), _bots.button_pressed)


func _on_join() -> void:
	NetSession.instance.player_name = _name.text
	NetSession.instance.join(_ip.text.strip_edges())


func _on_single() -> void:
	Weather.resolve()
	get_tree().change_scene_to_file(_selected_map())
