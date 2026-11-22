class_name TankSummary
extends RefCounted
## A tank's strengths and weaknesses in four short lines (speed, gun, armour, special)
## for the tank picker and the garage. Everything comes from the built TankData and its
## chassis' character, measured against the middle preset (DeployData.margin_share), so
## retuning a preset changes its text by itself.

const DATA_PATH: String = "res://data/ui/deploy.tres"
const GOOD: Color = Color(0.55, 0.85, 0.45)
const WEAK: Color = Color(0.95, 0.45, 0.38)

static var _data: DeployData
## stat name -> the middle value over the presets
static var _median: Dictionary = {}


static func data() -> DeployData:
	if _data == null:
		_data = load(DATA_PATH) as DeployData
		if _data == null:
			_data = DeployData.new()
	return _data


## The four lines: [[label, [[text, verdict], ...]], ...]; verdict 1 strength,
## -1 weakness, 0 neither.
static func lines(cfg: TankConfig) -> Array:
	var d: TankData = TankBuilder.build(cfg)
	if d == null:
		return []
	_ensure_ranges()
	var out: Array = []
	var speed: int = _verdict(&"speed", d.max_forward_speed_kmh, true)
	out.append(["Speed", [["%.0f km/h, %s" % [d.max_forward_speed_kmh,
			["slow", "average", "fast"][speed + 1]], speed],
			["reverse %.0f km/h" % d.max_reverse_speed_kmh, 0]]])
	var shot: ShellData = d.ammo[0]
	var gun: Array = [
		["%.0f mm, %.0f mm penetration" % [shot.caliber_mm, shot.penetration_mm],
			_verdict(&"pen", shot.penetration_mm, true)],
		["%.1f s reload" % d.reload_time_s, _verdict(&"reload", d.reload_time_s, false)],
	]
	var he: ShellData = _he_of(d)
	if he != null and he.damage_hp >= data().strong_he_hp:
		gun.append(["strong HE", 1])
	out.append(["Gun", gun])
	out.append(["Armour", [
		["front %.0f mm" % _front_mm(d), _verdict(&"front", _front_mm(d), true)],
		["side %.0f mm" % d.armour.hull_side_mm, _verdict(&"side", d.armour.hull_side_mm, true)],
		["%.0f hp" % d.structure_hp, _verdict(&"hp", d.structure_hp, true)],
	]])
	out.append(["Special", _specials(cfg, d)])
	return out


## Fills `box` with the lines: a muted caption, then the parts coloured by verdict.
static func fill(box: Container, cfg: TankConfig, font_size: int = 14) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for line: Array in lines(cfg):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var caption := Label.new()
		caption.text = str(line[0])
		caption.custom_minimum_size.x = font_size * 5.5
		caption.add_theme_font_size_override("font_size", font_size)
		caption.add_theme_color_override("font_color", MenuTheme.MUTED)
		row.add_child(caption)
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.scroll_active = false
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("normal_font_size", font_size)
		text.add_theme_color_override("default_color", MenuTheme.TEXT)
		var parts: PackedStringArray = []
		for part: Array in line[1]:
			var v: int = int(part[1])
			var t: String = str(part[0])
			if v != 0:
				t = "[color=#%s]%s[/color]" % [(GOOD if v > 0 else WEAK).to_html(false), t]
			parts.append(t)
		text.text = " · ".join(parts) if not parts.is_empty() else "–"
		row.add_child(text)
		box.add_child(row)


## The chassis' character beyond the numbers.
static func _specials(cfg: TankConfig, d: TankData) -> Array:
	var out: Array = []
	var chassis: ChassisData = TankBuilder.catalogue().find_chassis(cfg.chassis)
	var base: TankData = chassis.base if chassis != null else null
	if d.gun_stabiliser > 0.0:
		out.append(["gun stabiliser: steady on the move", 1])
	var traverse: int = _verdict(&"traverse", d.turret_traverse_speed_deg, true)
	if traverse != 0:
		out.append(["fast turret" if traverse > 0 else "slow turret", traverse])
	if base != null:
		if d.max_climb_deg > base.max_climb_deg:
			out.append(["climbs steep slopes", 1])
		if d.ford_slow_share < base.ford_slow_share:
			out.append(["fords water well", 1])
		if d.smoke_salvos > base.smoke_salvos:
			out.append(["%d smoke salvos" % d.smoke_salvos, 1])
		if _narrowest(d.gunner_sight_fov_deg) < _narrowest(base.gunner_sight_fov_deg):
			out.append(["strong gun sight", 1])
		elif _narrowest(d.gunner_sight_fov_deg) > _narrowest(base.gunner_sight_fov_deg):
			out.append(["weak gun sight", -1])
	if chassis != null and chassis.signature_spot_factor < 1.0:
		out.append(["tall: spotted sooner", -1])
	if cfg.camo:
		out.append(["camouflage", 1])
	return out


## -1, 0 or 1: `v` against the middle preset's value of `stat`.
static func _verdict(stat: StringName, v: float, higher_better: bool) -> int:
	var mid: float = float(_median.get(stat, v))
	if mid <= 0.0:
		return 0
	var ratio: float = v / mid if higher_better else mid / maxf(v, 0.001)
	if ratio >= 1.0 + data().margin_share:
		return 1
	if ratio <= 1.0 - data().margin_share:
		return -1
	return 0


static func _ensure_ranges() -> void:
	if not _median.is_empty():
		return
	var all: Dictionary = {}
	for cfg: TankConfig in TankConfigs.presets():
		var d: TankData = TankBuilder.build(cfg)
		if d == null:
			continue
		var values: Dictionary = {
			&"speed": d.max_forward_speed_kmh, &"pen": d.ammo[0].penetration_mm,
			&"reload": d.reload_time_s, &"front": _front_mm(d), &"side": d.armour.hull_side_mm,
			&"hp": d.structure_hp, &"traverse": d.turret_traverse_speed_deg,
		}
		for k: StringName in values:
			if not all.has(k):
				all[k] = []
			(all[k] as Array).append(float(values[k]))
	for k: StringName in all:
		var list: Array = all[k]
		list.sort()
		_median[k] = list[list.size() / 2]


## Hull front thickness straight on (sloped plates count for more, TankModel.SLOPES).
static func _front_mm(d: TankData) -> float:
	var slopes: Array = TankModel.SLOPES.get(d.model_style, [])
	var mm: float = d.armour.hull_front_mm
	if slopes.is_empty() or float(slopes[0]) < 1.0:
		return mm
	return mm / cos(deg_to_rad(float(slopes[0])))


static func _he_of(d: TankData) -> ShellData:
	for s: ShellData in d.ammo:
		if s.blast_hp > 0.0:
			return s
	return null


static func _narrowest(fovs: PackedFloat32Array) -> float:
	var m: float = INF
	for f: float in fovs:
		m = minf(m, f)
	return m
