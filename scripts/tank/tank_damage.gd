class_name TankDamage
extends RefCounted
## A tank's damage state: structure hp, modules, local armour wear, fire and repair.
## Pure logic (no scene), owned by Tank; Tank turns shell hits into calls here and
## reads the effects (speed, track and traverse factors) back.
##
## Penetration: takes ShellData.damage_hp, then damages every module box the shell's
## path passes within module_reach_m. Ammo = knocked out at once; fuel = fire.
## No penetration: wears the hit cell of the plate (ArmourData wear settings).
## External modules (tracks) are damaged by any shell landing in them and by HE fragments.
## Repair: standing still for repair_time_s (no fire, no penetration by a gun round, no
## AT round; MG fire, fragments and bounced shells don't disturb the crew) repairs every
## module (a module with its own repair time, e.g. a thrown track, takes that long);
## after that structure hp creeps back up to repair_hp_max_fraction.
## A destroyed track can immobilise the tank (TankData.broken_track_immobilises); a
## damaged one slows it and makes it turn worse. A burning tank stands still. A damaged
## engine halves the speed, a destroyed one stops the tank; the turret ring slows the
## traverse (damaged / destroyed shares in TankData).

enum State { OK, DAMAGED, DESTROYED }

## Emitted when a module changes state.
signal module_changed(id: StringName, state: State)

var data: TankData
var hp: float = 0.0
var knocked_out: bool = false
var fire_left: float = 0.0
var repair_time: float = 0.0
## id -> remaining module hp
var _module_hp: Dictionary = {}
## id -> ModuleData
var _modules: Dictionary = {}
## "part:face:side:i:j" -> worn mm
var _wear: Dictionary = {}
## id -> standing-still time its repair needs (s), rolled when it broke
var _repair_needed: Dictionary = {}
## id -> repair_time when it broke: what breaks during a repair takes its full time.
var _repair_started: Dictionary = {}
## Client puppets: repair time left and total from the host (s); total < 0 = not set.
var _net_repair_left: float = 0.0
var _net_repair_total: float = -1.0
var _rng := RandomNumberGenerator.new()


func _init(tank_data: TankData) -> void:
	data = tank_data
	_rng.randomize()
	if data.layout != null:
		for m: ModuleData in data.layout.modules:
			_modules[m.id] = m
	reset()


func reset() -> void:
	hp = data.structure_hp
	knocked_out = false
	fire_left = 0.0
	_restart_repair()
	_wear.clear()
	_repair_needed.clear()
	_net_repair_total = -1.0
	for id: StringName in _modules:
		_module_hp[id] = (_modules[id] as ModuleData).hp


func get_modules() -> Array[ModuleData]:
	var out: Array[ModuleData] = []
	for m: ModuleData in _modules.values():
		out.append(m)
	return out


func has_module(id: StringName) -> bool:
	return _modules.has(id)


func state(id: StringName) -> State:
	if not _modules.has(id):
		return State.OK
	var m: ModuleData = _modules[id]
	var left: float = _module_hp[id]
	if left <= 0.0:
		return State.DESTROYED
	if left < m.hp * m.damaged_below:
		return State.DAMAGED
	return State.OK


func hp_fraction() -> float:
	return clampf(hp / maxf(data.structure_hp, 0.001), 0.0, 1.0)


func is_burning() -> bool:
	return fire_left > 0.0


func needs_repair() -> bool:
	for id: StringName in _modules:
		if state(id) != State.OK:
			return true
	return hp < data.structure_hp * data.repair_hp_max_fraction - 0.01


## Standing-still time the current repair needs in all (s): the slowest broken module,
## or the tank's repair_time_s when only hp is low.
func repair_total() -> float:
	if _net_repair_total >= 0.0:
		return _net_repair_total
	var total: float = 0.0
	for id: StringName in _modules:
		if state(id) != State.OK:
			total = maxf(total, _repair_done_at(id))
	return total if total > 0.0 else data.repair_time_s


## Value of repair_time at which this module is repaired.
func _repair_done_at(id: StringName) -> float:
	return float(_repair_started.get(id, 0.0)) + float(_repair_needed.get(id, data.repair_time_s))


func _restart_repair() -> void:
	repair_time = 0.0
	_repair_started.clear()


## Seconds of standing still left until the modules are repaired.
func repair_time_left() -> float:
	if _net_repair_total >= 0.0:
		return _net_repair_left
	return maxf(repair_total() - repair_time, 0.0)


## 0..1 towards the module repair (1 = modules repaired, hp may still be creeping up).
func repair_progress() -> float:
	var total: float = repair_total()
	return clampf(1.0 - repair_time_left() / maxf(total, 0.001), 0.0, 1.0)


## A destroyed track holds the tank in place (if the data says so).
func is_immobilised() -> bool:
	return data.broken_track_immobilises \
			and (state(&"track_left") == State.DESTROYED or state(&"track_right") == State.DESTROYED)


# --- Effects read by Tank -------------------------------------------------------

## Top speed share: engine (damaged = data share, destroyed = 0), fire (the crew
## fights it standing still), a damaged track.
func speed_factor() -> float:
	if is_burning() and data.fire_immobilises:
		return 0.0
	var f: float = 1.0
	match state(&"engine"):
		State.DAMAGED: f = data.engine_damaged_speed_factor
		State.DESTROYED: return 0.0
	if has_damaged_track():
		f *= data.track_damaged_speed_factor
	return f


## Turn rate share: a damaged track turns worse.
func turn_factor() -> float:
	return data.track_damaged_turn_factor if has_damaged_track() else 1.0


func has_damaged_track() -> bool:
	return state(&"track_left") == State.DAMAGED or state(&"track_right") == State.DAMAGED


## Drive force factor for one side (-1 = left, 1 = right): a destroyed track gives none.
func track_factor(side: int) -> float:
	var id: StringName = &"track_left" if side < 0 else &"track_right"
	return 0.0 if state(id) == State.DESTROYED else 1.0


func traverse_factor() -> float:
	match state(&"turret_ring"):
		State.DAMAGED: return data.ring_damaged_traverse_factor
		State.DESTROYED: return data.ring_destroyed_traverse_factor
	return 1.0


# --- Armour wear -----------------------------------------------------------------

## Plate thickness at a hit, after wear. local_point is in the part's own space.
func armour_mm(part: String, face: String, local_point: Vector3) -> float:
	var plate: float = data.armour.thickness_mm(part, face)
	var worn: float = float(_wear.get(_cell_key(part, face, local_point, 0, 0), 0.0))
	return maxf(plate - worn, plate * data.armour.wear_min_fraction)


func _cell_key(part: String, face: String, p: Vector3, di: int, dj: int) -> String:
	var c: float = maxf(data.armour.wear_cell_m, 0.05)
	var a: float
	var b: float
	var side: String = ""
	match face:
		"front", "rear":
			a = p.x; b = p.y
		"side":
			a = p.z; b = p.y
			side = "l" if p.x < 0.0 else "r"
		_:
			a = p.x; b = p.z
	return "%s:%s:%s:%d:%d" % [part, face, side, floori(a / c) + di, floori(b / c) + dj]


func _wear_at(part: String, face: String, local_point: Vector3, mm: float) -> void:
	for di: int in range(-1, 2):
		for dj: int in range(-1, 2):
			var share: float = 1.0 if di == 0 and dj == 0 else data.armour.wear_neighbour_share
			var key: String = _cell_key(part, face, local_point, di, dj)
			_wear[key] = float(_wear.get(key, 0.0)) + mm * share


# --- Hits ------------------------------------------------------------------------

## Applies a resolved shell hit. hull_from/hull_dir: the shell's position and flight
## direction in hull space; turret_from/turret_dir the same in turret space.
## Fills result.modules / result.knocked_out. Returns true if the tank was knocked out now.
func apply_hit(shell: ShellData, result: HitResult, part: String, face: String,
		local_point: Vector3, hull_from: Vector3, hull_dir: Vector3,
		turret_from: Vector3, turret_dir: Vector3) -> bool:
	if knocked_out:
		return false
	if shell.stops_repair_on_hit or (result.outcome == HitResult.Outcome.PENETRATION
			and shell.caliber_mm >= Tank.THREAT_MIN_CALIBER_MM):
		_restart_repair()
	var hit: Array[StringName] = []
	# External modules (tracks) take any gun round that lands in them: HE (and AT
	# rounds) break a track, other rounds damage it (bullets do nothing).
	for m: ModuleData in _modules.values():
		if m.external and m.frame == &"hull" and _in_box(m, hull_from, 0.15) \
				and maxf(shell.module_damage, shell.damage_hp) > 0.0:
			var left: float = _module_hp[m.id]
			if shell.breaks_tracks:
				_damage_module(m.id, left)
			else:
				_damage_module(m.id, maxf(left - m.hp * m.damaged_below * 0.5, 0.0))
			hit.append(m.id)
	if result.outcome == HitResult.Outcome.NO_PENETRATION:
		_wear_at(part, face, local_point, shell.wear_mm)
	elif result.outcome == HitResult.Outcome.PENETRATION:
		hp -= shell.damage_hp
		if shell.cannot_knock_out:
			hp = maxf(hp, 1.0)
		for m: ModuleData in _modules.values():
			if m.external or hit.has(m.id):
				continue
			var from: Vector3 = turret_from if m.frame == &"turret" else hull_from
			var dir: Vector3 = turret_dir if m.frame == &"turret" else hull_dir
			if _segment_hits_box(m, from, dir, shell.module_reach_m):
				_damage_module(m.id, shell.module_damage)
				hit.append(m.id)
				if m.id == &"ammo" and not shell.cannot_knock_out:
					knocked_out = true
				elif m.id == &"fuel" and state(&"fuel") != State.OK:
					fire_left = data.fire_duration_s
	if hp <= 0.0:
		knocked_out = true
	hit.sort_custom(func(a: StringName, b: StringName) -> bool: return _rank(a) < _rank(b))
	for id: StringName in hit:
		result.modules.append(String(id))
	result.knocked_out = knocked_out
	return knocked_out


## HE fragments reaching an external module.
func apply_fragment(id: StringName, shell: ShellData) -> void:
	if knocked_out or not _modules.has(id):
		return
	_damage_module(id, shell.fragment_module_damage)


func _rank(id: StringName) -> int:
	return [&"ammo", &"fuel", &"engine", &"turret_ring", &"track_left", &"track_right"].find(id)


func _damage_module(id: StringName, amount: float) -> void:
	if amount <= 0.0:
		return
	var before: State = state(id)
	_module_hp[id] = maxf(float(_module_hp[id]) - amount, 0.0)
	var after: State = state(id)
	if after != before:
		var m: ModuleData = _modules[id]
		var needed: float = data.repair_time_s
		if after == State.DESTROYED and m.repair_time_max_s > 0.0:
			needed = _rng.randf_range(m.repair_time_min_s, maxf(m.repair_time_max_s, m.repair_time_min_s))
		_repair_needed[id] = maxf(float(_repair_needed.get(id, 0.0)), needed)
		_repair_started[id] = repair_time
		module_changed.emit(id, after)


func point_in_module(id: StringName, local_point: Vector3, margin: float) -> bool:
	return _modules.has(id) and _in_box(_modules[id], local_point, margin)


func _in_box(m: ModuleData, p: Vector3, margin: float) -> bool:
	var d: Vector3 = (p - m.center).abs()
	var half: Vector3 = m.size * 0.5 + Vector3.ONE * margin
	return d.x <= half.x and d.y <= half.y and d.z <= half.z


## Slab test: does the segment from `from` along `dir` (unit) for `reach` m cross the box?
func _segment_hits_box(m: ModuleData, from: Vector3, dir: Vector3, reach: float) -> bool:
	var lo: Vector3 = m.center - m.size * 0.5
	var hi: Vector3 = m.center + m.size * 0.5
	var t0: float = 0.0
	var t1: float = reach
	for axis: int in 3:
		var o: float = from[axis]
		var d: float = dir[axis]
		if absf(d) < 1e-6:
			if o < lo[axis] or o > hi[axis]:
				return false
			continue
		var ta: float = (lo[axis] - o) / d
		var tb: float = (hi[axis] - o) / d
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true


# --- Network (client puppets) --------------------------------------------------------

## Mirrors the host's state for the own tank's HUD. states in TankNetState.MODULES order.
func set_net(hp_frac: float, states: PackedInt32Array, burning: bool, repair_left: float,
		repair_total_s: float) -> void:
	hp = hp_frac * data.structure_hp
	fire_left = 1.0 if burning else 0.0
	_net_repair_left = repair_left
	_net_repair_total = maxf(repair_total_s, 0.0)
	repair_time = maxf(repair_total_s - repair_left, 0.0)
	for i: int in TankNetState.MODULES.size():
		var id: StringName = TankNetState.MODULES[i]
		if not _modules.has(id) or i >= states.size():
			continue
		var m: ModuleData = _modules[id]
		var before: State = state(id)
		match states[i]:
			State.OK: _module_hp[id] = m.hp
			State.DAMAGED: _module_hp[id] = m.hp * m.damaged_below * 0.5
			_: _module_hp[id] = 0.0
		if state(id) != before:
			module_changed.emit(id, state(id))


func set_net_burning(burning: bool) -> void:
	fire_left = 1.0 if burning else 0.0


# --- Time --------------------------------------------------------------------------

## still: the tank stands still (slow, no throttle or steering). Firing doesn't count.
func tick(delta: float, still: bool) -> void:
	if knocked_out:
		return
	if fire_left > 0.0:
		fire_left = maxf(fire_left - delta, 0.0)
		hp -= data.fire_hp_per_s * delta
		_restart_repair()
		if hp <= 0.0:
			knocked_out = true
		return
	if not still or not needs_repair():
		_restart_repair()
		return
	repair_time += delta
	var all_ok: bool = true
	for id: StringName in _modules:
		if state(id) == State.OK:
			continue
		if repair_time < _repair_done_at(id):
			all_ok = false
			continue
		_module_hp[id] = (_modules[id] as ModuleData).hp
		_repair_needed.erase(id)
		_repair_started.erase(id)
		module_changed.emit(id, State.OK)
	if not all_ok or repair_time < data.repair_time_s:
		return
	var cap: float = data.structure_hp * data.repair_hp_max_fraction
	if hp < cap:
		hp = minf(hp + data.repair_hp_per_s * delta, cap)
