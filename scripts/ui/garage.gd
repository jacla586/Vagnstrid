class_name Garage
extends Control
## The garage: look at the tanks (the presets) before a match: a turning 3D preview,
## the strengths and weaknesses in short (TankSummary) and the numbers with bars. The
## tank itself is chosen in the match (DeployScreen). Built in code in MenuTheme's look.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
## Layout in the 1152x648 canvas (the window scales it).
const MARGIN: int = 32
const GAP: int = 24
const LIST_WIDTH: float = 200.0
const SUMMARY_WIDTH: float = 290.0

## [label, getter, unit, format, higher is better]
var _stat_defs: Array = [
	["Top speed", func(d: TankData) -> float: return d.max_forward_speed_kmh, "km/h", "%.0f", true],
	["Reverse speed", func(d: TankData) -> float: return d.max_reverse_speed_kmh, "km/h", "%.0f", true],
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

var _configs: Array[TankConfig] = []
var _max: Array[float] = []
var _list: ItemList
var _title: Label
var _summary: VBoxContainer
var _bars: Array[ProgressBar] = []
var _values: Array[Label] = []
var _preview: TankPreview


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuTheme.get_theme()
	_configs = TankConfigs.presets()
	_compute_maxima()
	MenuTheme.add_backdrop(self, false, 0.82)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)
	margin.add_child(row)
	row.add_child(_build_list())
	row.add_child(_build_centre())
	row.add_child(_build_summary())
	var chosen: TankConfig = TankConfigs.get_selected()
	var first: int = 0
	for i: int in _configs.size():
		if chosen != null and _configs[i].resource_path == chosen.resource_path:
			first = i
	if not _configs.is_empty():
		_list.select(first)
		_show(_configs[first])


# --- Layout -----------------------------------------------------------------------

## Left: title, the tanks, back.
func _build_list() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	box.add_theme_constant_override("separation", 9)
	MenuTheme.add_title(box, "GARAGE", 30)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	box.add_child(MenuTheme.caption("Tanks"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for c: TankConfig in _configs:
		_list.add_item(c.display_name)
	_list.item_selected.connect(func(i: int) -> void: _show(_configs[i]))
	box.add_child(_list)
	var caption := MenuTheme.caption("You choose your tank in the match.")
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(caption)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	box.add_child(back)
	return box


## Middle: the turning tank with its name, the stats under it.
func _build_centre() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_preview = TankPreview.new()
	frame.add_child(_preview)
	var head_margin := MarginContainer.new()
	head_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top"]:
		head_margin.add_theme_constant_override("margin_" + side, 14)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	_title.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head_margin.add_child(_title)
	frame.add_child(head_margin)
	box.add_child(frame)
	box.add_child(_build_stats())
	return box


## Right: strengths and weaknesses in short.
func _build_summary() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
	box.add_theme_constant_override("separation", 9)
	var gap := Control.new()
	gap.custom_minimum_size.y = 50
	box.add_child(gap)
	box.add_child(MenuTheme.caption("In short"))
	_summary = VBoxContainer.new()
	_summary.add_theme_constant_override("separation", 10)
	box.add_child(_summary)
	return box


## Two columns of stats: name and value on a line, a thin bar under.
func _build_stats() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 7)
	var half: int = ceili(_stat_defs.size() / 2.0)
	# Filled column by column: the first half on the left.
	var order: Array[int] = []
	for r: int in half:
		order.append(r)
		if r + half < _stat_defs.size():
			order.append(r + half)
	_bars.resize(_stat_defs.size())
	_values.resize(_stat_defs.size())
	for i: int in order:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 2)
		var line := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = _stat_defs[i][0]
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", MenuTheme.MUTED)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var value := Label.new()
		value.add_theme_font_size_override("font_size", 12)
		line.add_child(value)
		cell.add_child(line)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 3)
		bar.show_percentage = false
		bar.max_value = 1.0
		cell.add_child(bar)
		grid.add_child(cell)
		_bars[i] = bar
		_values[i] = value
	return grid


# --- Behaviour ----------------------------------------------------------------------

func _show(cfg: TankConfig) -> void:
	var d: TankData = TankBuilder.build(cfg)
	if d == null:
		return
	_title.text = cfg.display_name
	for i: int in _stat_defs.size():
		var def: Array = _stat_defs[i]
		var v: float = (def[1] as Callable).call(d)
		_bars[i].value = v / maxf(_max[i], 0.001)
		_values[i].text = (def[3] as String) % v + " " + def[2] + _effective_note(d, String(def[0]), v)
	TankSummary.fill(_summary, cfg)
	_preview.show_tank(d)


## Sloped plates: the effective thickness straight on, e.g. " (90)".
func _effective_note(d: TankData, stat: String, mm: float) -> String:
	var slopes: Array = TankModel.SLOPES.get(d.model_style, [])
	var index: int = ["Hull front", "Hull side", "Turret front"].find(stat)
	if slopes.is_empty() or index < 0 or float(slopes[index]) < 1.0:
		return ""
	return " (%d)" % roundi(mm / cos(deg_to_rad(float(slopes[index]))))


## Each stat's largest value over the tanks shown (bars are shares of it).
func _compute_maxima() -> void:
	_max.resize(_stat_defs.size())
	_max.fill(0.0)
	for c: TankConfig in _configs:
		var d: TankData = TankBuilder.build(c)
		if d == null:
			continue
		for i: int in _stat_defs.size():
			_max[i] = maxf(_max[i], (_stat_defs[i][1] as Callable).call(d))
