class_name Garage
extends Control
## The garage: pick chassis, gun, armour package and camouflage, see what the tank
## becomes (stats with bars, a turning 3D preview), save your own configs and choose
## which tank to drive. Built in code like the main menu.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const TANK_SCENE: PackedScene = preload("res://scenes/tank/tank.tscn")
const PREVIEW_TURN_DEG_S: float = 20.0

## [label, getter, unit, format, higher is better]
var _stat_defs: Array = [
	["Top speed", func(d: TankData) -> float: return d.max_forward_speed_kmh, "km/h", "%.0f", true],
	["Acceleration", func(d: TankData) -> float: return d.acceleration, "", "%.2f", true],
	["Turn rate", func(d: TankData) -> float: return d.max_turn_rate_deg, "°/s", "%.0f", true],
	["Turret traverse", func(d: TankData) -> float: return d.turret_traverse_speed_deg, "°/s", "%.0f", true],
	["Hull front", func(d: TankData) -> float: return d.armour.hull_front_mm, "mm", "%.0f", true],
	["Hull side", func(d: TankData) -> float: return d.armour.hull_side_mm, "mm", "%.0f", true],
	["Hull rear", func(d: TankData) -> float: return d.armour.hull_rear_mm, "mm", "%.0f", true],
	["Turret front", func(d: TankData) -> float: return d.armour.turret_front_mm, "mm", "%.0f", true],
	["AP penetration", func(d: TankData) -> float: return d.ammo[0].penetration_mm, "mm", "%.0f", true],
	["AP damage", func(d: TankData) -> float: return d.ammo[0].damage_hp, "hp", "%.0f", true],
	["Muzzle velocity", func(d: TankData) -> float: return d.ammo[0].muzzle_velocity_mps, "m/s", "%.0f", true],
	["Reload", func(d: TankData) -> float: return d.reload_time_s, "s", "%.1f", false],
	["Structure", func(d: TankData) -> float: return d.structure_hp, "hp", "%.0f", true],
	["Mass", func(d: TankData) -> float: return d.mass_kg / 1000.0, "t", "%.1f", false],
	["Spotting time", func(d: TankData) -> float: return d.camo_spot_factor, "×", "%.2f", false],
]

var _cat: BuilderCatalogue
var _cfg: TankConfig = TankConfig.new()
var _configs: Array[TankConfig] = []
var _max: Array[float] = []
var _list: ItemList
var _name: LineEdit
var _chassis: OptionButton
var _gun: OptionButton
var _armour: OptionButton
var _camo: CheckBox
var _cost: Label
var _status: Label
var _bars: Array[ProgressBar] = []
var _values: Array[Label] = []
var _preview_root: Node3D
var _preview_tank: Node3D
var _camera: Camera3D
var _updating: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_cat = TankBuilder.catalogue()
	_compute_maxima()
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)
	var title := Label.new()
	title.text = "GARAGE"
	title.add_theme_font_size_override("font_size", 32)
	outer.add_child(title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 24)
	outer.add_child(row)
	row.add_child(_build_list())
	row.add_child(_build_parts())
	row.add_child(_build_stats())
	row.add_child(_build_preview())
	_refresh_list()
	var chosen: TankConfig = TankConfigs.get_selected()
	_load_config(chosen if chosen != null else _first_preset())


func _process(delta: float) -> void:
	if _preview_root != null:
		_preview_root.rotate_y(deg_to_rad(PREVIEW_TURN_DEG_S) * delta)


# --- Layout -----------------------------------------------------------------------

func _build_list() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(220, 0)
	box.add_child(_label("Tanks"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: _load_config(_configs[i]))
	box.add_child(_list)
	_button(box, "Drive this tank", _on_use)
	_button(box, "Back", _on_back)
	return box


func _build_parts() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(240, 0)
	box.add_theme_constant_override("separation", 8)
	box.add_child(_label("Name"))
	_name = LineEdit.new()
	box.add_child(_name)
	box.add_child(_label("Chassis"))
	_chassis = OptionButton.new()
	for c: ChassisData in _cat.chassis:
		_chassis.add_item(c.display_name)
	_chassis.item_selected.connect(func(_i: int) -> void: _on_parts_changed(true))
	box.add_child(_chassis)
	box.add_child(_label("Gun"))
	_gun = OptionButton.new()
	_gun.item_selected.connect(func(_i: int) -> void: _on_parts_changed(false))
	box.add_child(_gun)
	box.add_child(_label("Armour"))
	_armour = OptionButton.new()
	_armour.item_selected.connect(func(_i: int) -> void: _on_parts_changed(false))
	box.add_child(_armour)
	_camo = CheckBox.new()
	_camo.text = "Camouflage"
	_camo.toggled.connect(func(_on: bool) -> void: _on_parts_changed(false))
	box.add_child(_camo)
	_cost = _label("")
	_cost.add_theme_font_size_override("font_size", 22)
	box.add_child(_cost)
	_button(box, "Save", _on_save)
	_button(box, "Delete", _on_delete)
	_status = _label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)
	return box


func _build_stats() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.custom_minimum_size = Vector2(380, 0)
	grid.add_theme_constant_override("h_separation", 10)
	for def: Array in _stat_defs:
		grid.add_child(_label(def[0]))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(150, 16)
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
		_bars.append(bar)
		var value := _label("")
		value.custom_minimum_size = Vector2(90, 0)
		grid.add_child(value)
		_values.append(value)
	return grid


func _build_preview() -> Control:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(320, 320)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	container.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.19, 0.17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.6)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	vp.add_child(ground)
	_preview_root = Node3D.new()
	vp.add_child(_preview_root)
	_camera = Camera3D.new()
	vp.add_child(_camera)
	return container


# --- Behaviour ----------------------------------------------------------------------

func _refresh_list() -> void:
	_configs = TankConfigs.all()
	_list.clear()
	var chosen: TankConfig = TankConfigs.get_selected()
	for c: TankConfig in _configs:
		var text: String = c.display_name
		if TankConfigs.is_preset(c):
			text += "  (preset)"
		if chosen != null and c.resource_path == chosen.resource_path:
			text = "▶ " + text
		_list.add_item(text)


func _first_preset() -> TankConfig:
	var p: Array[TankConfig] = TankConfigs.presets()
	for c: TankConfig in p:
		if c.key() == TankConfig.new().key():  # today's medium tank
			return c
	return p[0] if not p.is_empty() else TankConfig.new()


func _load_config(cfg: TankConfig) -> void:
	_cfg = cfg.duplicate()
	_updating = true
	_name.text = _cfg.display_name
	for i: int in _cat.chassis.size():
		if _cat.chassis[i].id == _cfg.chassis:
			_chassis.select(i)
	_fill_part_lists()
	_camo.button_pressed = _cfg.camo
	_updating = false
	_on_parts_changed(false)


func _current_chassis() -> ChassisData:
	return _cat.chassis[maxi(_chassis.selected, 0)]


## Gun and armour lists for the chosen chassis; keeps the config's part if it fits.
func _fill_part_lists() -> void:
	var ch: ChassisData = _current_chassis()
	_gun.clear()
	var gun_index: int = 0
	for i: int in ch.guns.size():
		_gun.add_item(ch.guns[i].display_name)
		if ch.guns[i].id == _cfg.gun:
			gun_index = i
	_gun.select(gun_index)
	_armour.clear()
	var armour_index: int = 0
	for i: int in ch.armour_packages.size():
		_armour.add_item(ch.armour_packages[i].display_name)
		if ch.armour_packages[i].id == _cfg.armour:
			armour_index = i
	_armour.select(armour_index)


func _on_parts_changed(chassis_changed: bool) -> void:
	if _updating:
		return
	var ch: ChassisData = _current_chassis()
	_cfg.chassis = ch.id
	if chassis_changed:
		_updating = true
		_fill_part_lists()
		_updating = false
	_cfg.gun = ch.guns[maxi(_gun.selected, 0)].id
	_cfg.armour = ch.armour_packages[maxi(_armour.selected, 0)].id
	_cfg.camo = _camo.button_pressed
	var d: TankData = TankBuilder.build(_cfg)
	if d == null:
		return
	for i: int in _stat_defs.size():
		var def: Array = _stat_defs[i]
		var v: float = (def[1] as Callable).call(d)
		_bars[i].value = v / maxf(_max[i], 0.001)
		_values[i].text = (def[3] as String) % v + " " + def[2]
	_cost.text = "Cost: %d" % d.cost
	_show_preview(d)


func _show_preview(d: TankData) -> void:
	if _preview_tank != null:
		_preview_tank.queue_free()
	var tank: Tank = TANK_SCENE.instantiate()
	tank.data = d
	tank.apply_geometry()
	var visual: Node3D = tank.get_node("Visual")
	visual.get_node("Turret/Cupola/CommanderHitbox").free()
	tank.remove_child(visual)
	tank.free()
	_preview_root.add_child(visual)
	visual.position = Vector3(0.0, d.hull_size.y * 0.5 + 0.2, 0.0)
	_preview_tank = visual
	var size: float = maxf(d.hull_size.z, d.gun_length_m + d.turret_radius_m * 2.0)
	_camera.position = Vector3(0.0, size * 0.55, size * 1.25)
	_camera.look_at(Vector3(0.0, d.hull_size.y * 0.5, 0.0))


func _on_save() -> void:
	_cfg.display_name = _name.text.strip_edges()
	if _cfg.display_name == "":
		_status.text = "Give the tank a name."
		return
	var saved: TankConfig = TankConfigs.save(_cfg)
	if saved == null:
		_status.text = "Could not save."
		return
	_status.text = "Saved \"%s\"." % saved.display_name
	_refresh_list()


func _on_delete() -> void:
	for c: TankConfig in _configs:
		if not TankConfigs.is_preset(c) and c.display_name == _name.text.strip_edges():
			TankConfigs.remove(c)
			_status.text = "Deleted \"%s\"." % c.display_name
			_refresh_list()
			return
	_status.text = "Only your own saved tanks can be deleted."


## Drives the tank as shown: saves it first unless it is an unchanged preset.
func _on_use() -> void:
	_cfg.display_name = _name.text.strip_edges()
	var chosen: TankConfig = null
	for c: TankConfig in _configs:
		if c.key() == _cfg.key() and c.display_name == _cfg.display_name:
			chosen = c
	if chosen == null:
		if _cfg.display_name == "":
			_cfg.display_name = "My tank"
		chosen = TankConfigs.save(_cfg)
	if chosen == null:
		_status.text = "Could not save."
		return
	TankConfigs.select(chosen)
	_status.text = "You drive \"%s\"." % chosen.display_name
	_refresh_list()


func _on_back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## Each stat's largest value over every buildable tank (bars are shares of it).
func _compute_maxima() -> void:
	_max.resize(_stat_defs.size())
	_max.fill(0.0)
	for ch: ChassisData in _cat.chassis:
		for g: GunData in ch.guns:
			for p: ArmourPackageData in ch.armour_packages:
				for camo: bool in [false, true]:
					var c := TankConfig.new()
					c.chassis = ch.id
					c.gun = g.id
					c.armour = p.id
					c.camo = camo
					var d: TankData = TankBuilder.build(c)
					if d == null:
						continue
					for i: int in _stat_defs.size():
						_max[i] = maxf(_max[i], (_stat_defs[i][1] as Callable).call(d))


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _button(box: Container, t: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	box.add_child(b)
