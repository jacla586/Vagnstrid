class_name TankBuilder
extends RefCounted
## Turns a TankConfig (chassis + gun + armour package + camouflage) into TankData,
## using the builder catalogue's parts and rules (data/builder/). Copies the chassis'
## base TankData and sets what the parts change: mass, mobility, turret traverse,
## armour, ammunition, reload, recoil, gun sound, structure, size (hull, turret, gun),
## the module layout scaled to the hull, camouflage and cost. Built TankData is cached
## per config, so every machine builds the same tank from the same few ids.

const CATALOGUE_PATH: String = "res://data/builder/catalogue.tres"
const SPEC_PREFIX: String = "cfg:"

static var _catalogue: BuilderCatalogue
static var _cache: Dictionary = {}  # TankConfig.key() -> TankData


static func catalogue() -> BuilderCatalogue:
	if _catalogue == null:
		_catalogue = load(CATALOGUE_PATH)
	return _catalogue


## The TankData for `config`, or null if a part is unknown or doesn't fit the chassis.
static func build(config: TankConfig) -> TankData:
	if config == null:
		return null
	var key: String = config.key()
	if _cache.has(key):
		return _cache[key]
	var cat: BuilderCatalogue = catalogue()
	var chassis: ChassisData = cat.find_chassis(config.chassis)
	var gun: GunData = find_gun(chassis, config.gun)
	var pack: ArmourPackageData = find_armour(chassis, config.armour)
	if chassis == null or gun == null or pack == null:
		push_warning("TankBuilder: unknown or unfitting part in %s" % key)
		return null
	var r: BuilderRules = cat.rules
	var d: TankData = chassis.base.duplicate()
	d.display_name = "%s %s" % [chassis.display_name, gun.display_name]
	# Mass and mobility.
	var mass: float = chassis.base_mass_kg * (1.0 + pack.mass_fraction) + gun.mass_kg
	d.mass_kg = mass
	var kw_per_ton: float = chassis.engine_kw / (mass / 1000.0)
	var ratio: float = kw_per_ton / maxf(r.reference_kw_per_ton, 0.01)
	d.max_forward_speed_kmh = clampf(r.reference_top_speed_kmh * pow(ratio, r.speed_exponent),
			r.min_top_speed_kmh, r.max_top_speed_kmh)
	d.max_reverse_speed_kmh = d.max_forward_speed_kmh * r.reverse_share
	d.acceleration = clampf(r.reference_acceleration * ratio, r.min_acceleration, r.max_acceleration)
	d.max_turn_rate_deg = r.reference_turn_rate_deg * pow(r.reference_mass_kg / mass, r.turn_mass_exponent)
	d.turret_traverse_speed_deg = clampf(
			r.reference_traverse_deg * pow(r.reference_gun_mass_kg / gun.mass_kg, r.traverse_exponent),
			r.min_traverse_deg, r.max_traverse_deg)
	d.structure_hp = maxf(mass / 1000.0 * r.hp_per_ton, r.min_structure_hp)
	# Gun.
	d.ammo = gun.ammo.duplicate()
	d.reload_time_s = gun.reload_time_s
	d.recoil_impulse_ns = gun.recoil_impulse_ns
	if gun.fire_sound != null and d.sounds != null:
		var sounds: TankSoundData = d.sounds.duplicate()
		sounds.gun_fire = gun.fire_sound
		d.sounds = sounds
	# Armour.
	var a: ArmourData = chassis.armour.duplicate()
	a.hull_front_mm *= pack.front_factor
	a.turret_front_mm *= pack.front_factor
	a.hull_side_mm *= pack.side_factor
	a.turret_side_mm *= pack.side_factor
	a.hull_rear_mm *= pack.rear_factor
	a.turret_rear_mm *= pack.rear_factor
	a.hull_roof_mm *= pack.roof_factor
	a.turret_roof_mm *= pack.roof_factor
	d.armour = a
	# Size: the hull grows a little with thick armour; a big gun needs a big turret.
	var base_hull: Vector3 = chassis.base.hull_size
	d.hull_size = chassis.hull_size * pack.size_factor
	d.turret_radius_m = maxf(chassis.turret_radius_m, gun.min_turret_radius_m) * pack.size_factor
	d.turret_height_m = chassis.turret_height_m * pack.size_factor
	d.gun_length_m = gun.gun_length_m
	d.model_style = chassis.model_style
	d.turret_variant = gun.turret_variant
	d.muzzle_brake = gun.muzzle_brake
	d.armour_look = pack.id
	d.barrel_radius_m = gun.barrel_radius_m
	d.layout = _scaled_layout(chassis.base.layout, d.hull_size / base_hull,
			d.turret_radius_m / maxf(chassis.base.turret_radius_m, 0.01))
	# Camouflage and cost.
	d.camo_spot_factor = r.camo_spot_factor if config.camo else 1.0
	d.cost = chassis.cost + gun.cost + pack.cost + (r.camo_cost if config.camo else 0)
	_cache[key] = d
	return d


## What the network sends so every machine makes the same tank: "cfg:<key>" for a
## built tank, else the TankData's resource path.
static func spec_of(tank: Tank) -> String:
	if tank.config != null and build(tank.config) != null:
		return SPEC_PREFIX + tank.config.key()
	return tank.data.resource_path


## Sets up `tank` (before it enters the tree) from a spec made by spec_of().
static func apply_spec(tank: Tank, spec: String, fallback_path: String) -> void:
	if spec.begins_with(SPEC_PREFIX):
		var cfg: TankConfig = TankConfig.from_key(spec.trim_prefix(SPEC_PREFIX))
		if build(cfg) != null:
			tank.config = cfg
			tank.data = build(cfg)
			return
	tank.config = null
	tank.data = load(spec) if spec != "" and ResourceLoader.exists(spec) else load(fallback_path)


static func find_gun(chassis: ChassisData, id: StringName) -> GunData:
	if chassis == null:
		return null
	for g: GunData in chassis.guns:
		if g.id == id:
			return g
	return null


static func find_armour(chassis: ChassisData, id: StringName) -> ArmourPackageData:
	if chassis == null:
		return null
	for p: ArmourPackageData in chassis.armour_packages:
		if p.id == id:
			return p
	return null


## The base layout's modules moved and sized with the hull (hull modules) or turret.
static func _scaled_layout(base: ModuleLayoutData, hull_scale: Vector3, turret_scale: float) -> ModuleLayoutData:
	if base == null:
		return null
	var layout := ModuleLayoutData.new()
	for m: ModuleData in base.modules:
		var c: ModuleData = m.duplicate()
		var s: Vector3 = hull_scale if m.frame == &"hull" else Vector3.ONE * turret_scale
		c.center = m.center * s
		c.size = m.size * s
		layout.modules.append(c)
	return layout
