class_name MainMenu
extends Control
## Start menu: name, Host (map, bots on/off), Join (host's IP, e.g. a Tailscale address)
## and Single player (any map or scenario, offline as before). Built in code.

const GARAGE_SCENE: String = "res://scenes/menu/garage.tscn"
const MAP_DIRS: Array[String] = ["res://scenes/scenarios/", "res://scenes/maps/"]

var _name: LineEdit
var _map: OptionButton
var _bots: CheckBox
var _ip: LineEdit
var _status: Label
var _maps: PackedStringArray = []
var _tank: OptionButton
var _team_size: SpinBox
var _tank_configs: Array[TankConfig] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Centred, scrolling if the window is too low for everything.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)
	var title := Label.new()
	title.text = "STRIDSVAGN"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_name = _field(box, "Name", NetSession.instance.player_name)
	box.add_child(_label("Map"))
	_map = OptionButton.new()
	box.add_child(_map)
	_maps = _find_maps()
	for i: int in _maps.size():
		_map.add_item(_maps[i].get_file().get_basename(), i)
		if _maps[i] == NetSession.DEFAULT_MAP:
			_map.select(i)
	box.add_child(_label("Tank"))
	_tank = OptionButton.new()
	box.add_child(_tank)
	_fill_tanks()
	_tank.item_selected.connect(func(i: int) -> void:
		TankConfigs.select(_tank_configs[i - 1] if i > 0 else null))
	_button(box, "Garage", func() -> void: get_tree().change_scene_to_file(GARAGE_SCENE))
	box.add_child(_label("Tanks per team, King of the Hill (5 = 5 vs 5, bots fill empty places; 0 = map default)"))
	_team_size = SpinBox.new()
	_team_size.min_value = 0
	_team_size.max_value = MatchSettings.MAX_TEAM_SIZE
	_team_size.step = 1
	_team_size.rounded = true
	_team_size.update_on_text_changed = true
	MatchSettings.load_settings()
	_team_size.value = MatchSettings.team_size
	_team_size.value_changed.connect(func(v: float) -> void: MatchSettings.set_team_size(roundi(v)))
	box.add_child(_team_size)
	_bots = CheckBox.new()
	_bots.text = "Bots (host)"
	box.add_child(_bots)
	_button(box, "Host game", _on_host)
	_ip = _field(box, "Host address", "127.0.0.1")
	_button(box, "Join game", _on_join)
	_button(box, "Single player", _on_single)
	_status = _label(NetSession.instance.status)
	box.add_child(_status)
	NetSession.instance.status_changed.connect(func(t: String) -> void:
		if is_instance_valid(_status):
			_status.text = t)


## The tank list: the map's own tank first, then saved configs and presets.
func _fill_tanks() -> void:
	_tank_configs = TankConfigs.all()
	_tank.clear()
	_tank.add_item("Map default")
	var chosen: TankConfig = TankConfigs.get_selected()
	_tank.select(0)
	for i: int in _tank_configs.size():
		var c: TankConfig = _tank_configs[i]
		_tank.add_item(c.display_name + ("  (preset)" if TankConfigs.is_preset(c) else ""))
		if chosen != null and c.resource_path == chosen.resource_path:
			_tank.select(i + 1)


func _field(box: Container, caption: String, value: String) -> LineEdit:
	box.add_child(_label(caption))
	var e := LineEdit.new()
	e.text = value
	box.add_child(e)
	return e


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _button(box: Container, t: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	box.add_child(b)


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
	NetSession.instance.host(_selected_map(), _bots.button_pressed)


func _on_join() -> void:
	NetSession.instance.player_name = _name.text
	NetSession.instance.join(_ip.text.strip_edges())


func _on_single() -> void:
	get_tree().change_scene_to_file(_selected_map())
