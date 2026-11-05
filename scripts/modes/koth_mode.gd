class_name KothMode
extends Node3D
## King of the Hill (rules in KothData). Place it in a scenario as "KothZone" and give
## it Marker3D children: the spots where zones may open (picked at random, never the
## same twice in a row). Without markers, zones open at random within
## fallback_half_extent_m of this node. Runs the match offline and on the host;
## clients only show it.
##
## Each zone opens at full size, holds zone_hold_s, then shrinks towards radius_end_m.
## It closes when it has paid out zone_point_budget points, or at zone_lifetime_s;
## the next spot is announced at once and opens zone_gap_s later. While a zone is open
## every team scores for each of its own tanks inside (horizontal distance, capped),
## the team with most tanks there gets the majority multiplier, and an in-zone
## knock-out from inside the zone gives a bonus (both paid from the zone's budget).
## Each new spot moves the spawns: the south team south of it, the others north.
## First to score_to_win wins (or the best score after zone_count zones, if set).

## Emitted when a new zone spot is chosen (announced; it may not be open yet).
signal zone_moved(center: Vector3)
## Emitted once when the match ends. winner_team = -1 for a draw.
signal match_over(winner_team: int)
## Emitted when a team earns an in-zone knock-out bonus.
signal kill_bonus(team: int, points: float)

## The running mode (null when the scene has none). The HUD and map read it.
static var instance: KothMode

## Below this the terrain counts as sea (m).
const SEA_LEVEL_LIMIT_M: float = 0.5
## Spawns put the tank's origin (mid-hull) this far above the ground, so it drops onto
## its suspension instead of starting inside the terrain (m).
const SPAWN_LIFT_M: float = 1.5
## Steepest ground a spawn may stand on (degrees).
const SPAWN_MAX_SLOPE_DEG: float = 15.0
## Slots tried beside a spawn (alternating right and left) for a free, clear one.
const SPAWN_SLOTS: int = 24
## A spawn spot needs this much room round it on the tactical grid (m; tanks ~6.5 m long).
const SPAWN_CLEARANCE_M: float = 5.0
## Spawn search: step back towards the zone by this much each try (m)...
const SPAWN_STEP_M: float = 50.0
## ...trying these sideways offsets at each distance (m).
const SPAWN_SIDE_OFFSETS: Array[float] = [0.0, 80.0, -80.0, 160.0, -160.0, 240.0, -240.0]

@export var data: KothData
## Without Marker3D children: zones open at random within this of the node (x, z; m).
@export var fallback_half_extent_m: Vector2 = Vector2(600.0, 400.0)

var _time: float = 0.0
var _tick_timer: float = 0.0
var _scores: Dictionary = {}  # team -> points
var _in_zone: Dictionary = {}  # team -> tanks in the zone at the last count (uncapped)
var _over: bool = false
var _winner: int = -1
var _connected: Dictionary = {}  # tank instance id -> true (shot_landed connected)
## Scoreboard: tank instance id -> [name, team, knock-outs, losses, points]. Clients get
## the host's list (as an Array) in the net state.
var _stats: Dictionary = {}
var _net_stats: Array = []
var _zone_tanks: Dictionary = {}  # team -> Array of tanks in the zone at the last count
## 0-based number of the open zone, or of the last closed one during a gap.
var _zone_index: int = 0
var _zone_open: bool = false
var _zone_started: float = 0.0
var _gap_ends: float = 0.0
var _budget_left: float = 0.0
var _center: Vector3 = Vector3.ZERO
var _last_spot: int = -1
var _spawns: Dictionary = {}  # side (+1 south, -1 north) -> Transform3D
var _started: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _enter_tree() -> void:
	instance = self
	_give_bots_configs()


## Before any tank is ready (the whole scene enters the tree first): every tank that
## isn't the player's and has no config gets a random one of KothData.bot_configs, so
## bots drive varied tanks.
func _give_bots_configs() -> void:
	if data == null or data.bot_configs.is_empty() or get_parent() == null:
		return
	for node: Node in get_parent().find_children("*", "", true, false):
		var tank := node as Tank
		if tank != null and not tank.is_node_ready() and tank.config == null \
				and not tank.use_player_config:
			tank.config = data.bot_configs[randi() % data.bot_configs.size()]


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	assert(data != null, "KothMode needs KothData")
	_rng.randomize()
	_center = global_position
	# Clients show the host's state (apply_net_state); they don't run the match, only
	# let the clock run on between updates so the countdowns stay smooth.
	set_physics_process(not NetRole.is_client())
	set_process(NetRole.is_client())


func _process(delta: float) -> void:
	if not _over:
		_time += delta


func _physics_process(delta: float) -> void:
	if _over:
		return
	if not _started:
		# First frame: the map's colliders and every tank are in place now.
		_started = true
		_choose_zone()
		_open_zone()
		_move_tanks_to_spawns()
	_time += delta
	_update_timeline()
	if _over:
		return
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	var dt: float = data.tick_interval_s - _tick_timer
	_tick_timer = data.tick_interval_s
	_connect_new_tanks()
	_score_zone(dt)
	if _zone_open and _budget_left <= 0.0:
		_close_zone()
	_check_score_win()


# --- Queries (HUD, map, bots, respawns) -----------------------------------------------

## Centre of the open zone, or of the announced next one during a gap.
func get_center() -> Vector3:
	return _center


func is_zone_open() -> bool:
	return not _over and _zone_open


## Current radius (the full radius during a gap: the next zone's size when it opens).
func get_radius() -> float:
	if not is_zone_open():
		return data.radius_start_m
	return lerpf(data.radius_start_m, data.radius_end_m, get_shrink_progress())


## 0 while the zone holds at full size, rising to 1 when it disappears.
func get_shrink_progress() -> float:
	var shrink_time: float = maxf(data.zone_lifetime_s - data.zone_hold_s, 0.01)
	return clampf((_zone_time() - data.zone_hold_s) / shrink_time, 0.0, 1.0)


## 1-based number of the open zone (or the next one during a gap).
func get_zone_number() -> int:
	return _zone_index + (1 if _zone_open else 2)


## Zones per match, 0 = no limit (until score_to_win).
func get_zone_count() -> int:
	return data.zone_count


## Points the open zone still has to give out.
func get_budget_left() -> float:
	return _budget_left


## Seconds until the next timed event: shrinking starts, the zone closes by time, or
## the next zone opens. (A zone also closes early when its budget runs out.)
func get_time_to_next_event() -> float:
	if not _zone_open:
		return maxf(_gap_ends - _time, 0.0)
	var t: float = _zone_time()
	if t < data.zone_hold_s:
		return data.zone_hold_s - t
	return maxf(data.zone_lifetime_s - t, 0.0)


func get_score(team: int) -> float:
	return float(_scores.get(team, 0.0))


## Highest score among teams other than `team`.
func get_best_other_score(team: int) -> float:
	var best: float = 0.0
	for t: int in _scores.keys():
		if t != team:
			best = maxf(best, float(_scores[t]))
	return best


## Tanks of `team` in the zone at the last count.
func get_tanks_in_zone(team: int) -> int:
	return int(_in_zone.get(team, 0))


func is_in_zone(point: Vector3) -> bool:
	if not is_zone_open():
		return false
	var flat := Vector2(point.x - _center.x, point.z - _center.z)
	return flat.length() <= get_radius()


func is_over() -> bool:
	return _over


func get_winner() -> int:
	return _winner


## True once the first zone is chosen (spawns are valid from then on).
func has_started() -> bool:
	return _started


# --- Network (host -> clients) ----------------------------------------------------------

## The match state for clients (small: sent twice a second and on changes).
func get_net_state() -> Dictionary:
	return {
		"t": _time, "zi": _zone_index, "open": _zone_open, "zs": _zone_started,
		"ge": _gap_ends, "b": _budget_left, "c": _center,
		"ss": _spawns.get(1, global_transform), "sn": _spawns.get(-1, global_transform),
		"sc": _scores, "over": _over, "w": _winner, "st": get_stats(),
	}


## Client: takes over the host's state.
func apply_net_state(state: Dictionary) -> void:
	_started = true
	_time = state.get("t", _time)
	_zone_index = state.get("zi", _zone_index)
	_zone_open = state.get("open", _zone_open)
	_zone_started = state.get("zs", _zone_started)
	_gap_ends = state.get("ge", _gap_ends)
	_budget_left = state.get("b", _budget_left)
	var center: Vector3 = state.get("c", _center)
	if center != _center:
		_center = center
		zone_moved.emit(_center)
	_spawns[1] = state.get("ss", global_transform)
	_spawns[-1] = state.get("sn", global_transform)
	_scores = (state.get("sc", {}) as Dictionary).duplicate()
	_net_stats = (state.get("st", []) as Array).duplicate(true)
	var over: bool = state.get("over", false)
	_winner = state.get("w", -1)
	if over and not _over:
		_over = true
		match_over.emit(_winner)


## Where `team` spawns for the current zone, facing it. `slot` spreads several tanks
## side by side (0, 1, 2 ... alternate right and left).
func get_spawn(team: int, slot: int = 0) -> Transform3D:
	var side: int = _side_of(team)
	var xform: Transform3D = _spawns.get(side, global_transform)
	if slot == 0:
		return xform
	var offset: float = ceilf(slot / 2.0) * data.spawn_spacing_m * (1.0 if slot % 2 == 1 else -1.0)
	var p: Vector3 = xform.origin + xform.basis.x * offset
	var hit: Dictionary = ground_hit(get_world_3d(), p)
	if not hit.is_empty():
		p.y = (hit["position"] as Vector3).y + SPAWN_LIFT_M
	xform.origin = p
	return xform


## The first spawn slot of `team` with no other tank on it (respawns).
func get_free_spawn(team: int, exclude: Tank = null) -> Transform3D:
	var clear: float = data.spawn_spacing_m * 0.7
	for slot: int in SPAWN_SLOTS:
		var xform: Transform3D = get_spawn(team, slot)
		if not _spot_clear(xform.origin):
			continue
		var taken: bool = false
		for node: Node in get_tree().get_nodes_in_group("tanks"):
			var other := node as Tank
			if other != null and other != exclude \
					and other.global_position.distance_to(xform.origin) < clear:
				taken = true
				break
		if not taken:
			return xform
	return get_spawn(team)


## +1 = south of the zone, -1 = north.
func _side_of(team: int) -> int:
	return 1 if team == data.south_team else -1


## Ray straight down at (x, z): the ground hit (world layer), or empty.
static func ground_hit(world: World3D, point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 2000.0, point.z),
			Vector3(point.x, -500.0, point.z))
	query.collision_mask = 1
	return world.direct_space_state.intersect_ray(query)


# --- Zones and spawns -----------------------------------------------------------------

func _zone_time() -> float:
	return _time - _zone_started


func _open_zone() -> void:
	_zone_open = true
	_zone_started = _time
	_budget_left = data.zone_point_budget


## Closes the open zone and announces the next spot (or ends the match after the last).
func _close_zone() -> void:
	_zone_open = false
	_in_zone.clear()
	if data.zone_count > 0 and _zone_index + 1 >= data.zone_count:
		_end_by_score()
		return
	_gap_ends = _time + data.zone_gap_s
	_choose_zone()


func _update_timeline() -> void:
	if _zone_open:
		if _zone_time() >= data.zone_lifetime_s:
			_close_zone()
	elif _time >= _gap_ends:
		_zone_index += 1
		_open_zone()


func _spots() -> Array[Marker3D]:
	var spots: Array[Marker3D] = []
	for child: Node in get_children():
		if child is Marker3D:
			spots.append(child)
	return spots


func _choose_zone() -> void:
	var spots: Array[Marker3D] = _spots()
	if spots.is_empty():
		var o := Vector2(_rng.randf_range(-1.0, 1.0) * fallback_half_extent_m.x,
				_rng.randf_range(-1.0, 1.0) * fallback_half_extent_m.y)
		_center = global_position + Vector3(o.x, 0.0, o.y)
	else:
		var pick: int = _rng.randi_range(0, spots.size() - 1)
		if spots.size() > 1 and pick == _last_spot:
			pick = (pick + 1 + _rng.randi_range(0, spots.size() - 2)) % spots.size()
		_last_spot = pick
		_center = spots[pick].global_position
	var hit: Dictionary = ground_hit(get_world_3d(), _center)
	if not hit.is_empty():
		_center.y = (hit["position"] as Vector3).y
	_spawns[1] = _find_spawn(1)
	_spawns[-1] = _find_spawn(-1)
	zone_moved.emit(_center)


## A spawn on open, dry, fairly flat terrain inside the map, `side` of the zone
## (+1 south = +z), as far as spawn_distance_m, facing the zone.
func _find_spawn(side: int) -> Transform3D:
	var map_rect: Rect2 = Rect2()
	var map_image: MapImageData = MapImageData.find_for_scene(get_tree().current_scene)
	if map_image != null:
		map_rect = map_image.world_rect.grow(-50.0)
	var distance: float = data.spawn_distance_m
	while distance >= data.spawn_min_distance_m:
		for side_offset: float in SPAWN_SIDE_OFFSETS:
			var p := Vector3(_center.x + side_offset, 0.0, _center.z + side * distance)
			if map_rect.has_area() and not map_rect.has_point(Vector2(p.x, p.z)):
				continue
			var hit: Dictionary = ground_hit(get_world_3d(), p)
			if hit.is_empty() or not _is_open_ground(hit):
				continue
			return _facing_zone((hit["position"] as Vector3) + Vector3.UP * SPAWN_LIFT_M)
		distance -= SPAWN_STEP_M
	push_warning("KothMode: no good spawn %s of the zone; using the minimum distance" %
			("south" if side > 0 else "north"))
	var fallback := Vector3(_center.x, _center.y, _center.z + side * data.spawn_min_distance_m)
	var h: Dictionary = ground_hit(get_world_3d(), fallback)
	if not h.is_empty():
		fallback.y = (h["position"] as Vector3).y + SPAWN_LIFT_M
	return _facing_zone(fallback)


## Terrain (not a house, bridge or tank), above the sea, not too steep.
func _is_open_ground(hit: Dictionary) -> bool:
	var collider: Object = hit["collider"]
	if not (collider is Terrain3D):
		return false
	if (hit["position"] as Vector3).y <= SEA_LEVEL_LIMIT_M:
		return false
	if (hit["normal"] as Vector3).angle_to(Vector3.UP) > deg_to_rad(SPAWN_MAX_SLOPE_DEG):
		return false
	return _spot_clear(hit["position"])


## No house, stone, water or steep cell on the bots' tactical grid at `p` or round it
## (always true on maps without a baked grid).
func _spot_clear(p: Vector3) -> bool:
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	if map == null:
		return true
	var r: float = SPAWN_CLEARANCE_M
	for d: Vector3 in [Vector3.ZERO, Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
		if map.is_blocked(p + d):
			return false
	return true


func _facing_zone(at: Vector3) -> Transform3D:
	var to_zone := Vector3(_center.x - at.x, 0.0, _center.z - at.z)
	if to_zone.length() < 0.1:
		return Transform3D(Basis(), at)
	return Transform3D(Basis.looking_at(to_zone.normalized(), Vector3.UP), at)


## Match start: every tank to its team's spawn, so both sides start equally far away.
func _move_tanks_to_spawns() -> void:
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank != null:
			place_tank(tank, get_free_spawn(tank.team, tank))


## Moves a tank to `xform` at rest (spawns and respawns).
static func place_tank(tank: Tank, xform: Transform3D) -> void:
	tank.leave_wreck()   # a knocked-out tank leaves its wreck where it burnt out
	tank.global_transform = xform
	tank.linear_velocity = Vector3.ZERO
	tank.angular_velocity = Vector3.ZERO


# --- Scoring --------------------------------------------------------------------------

func _score_zone(dt: float) -> void:
	_in_zone.clear()
	_zone_tanks.clear()
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or tank.is_knocked_out():
			continue
		if not _scores.has(tank.team):
			_scores[tank.team] = 0.0
		if is_in_zone(tank.global_position):
			_in_zone[tank.team] = int(_in_zone.get(tank.team, 0)) + 1
			if not _zone_tanks.has(tank.team):
				_zone_tanks[tank.team] = []
			(_zone_tanks[tank.team] as Array).append(tank)
	if not is_zone_open():
		return
	var majority_team: int = _majority_team()
	var rate: float = lerpf(data.points_per_tank_start, data.points_per_tank_end,
			get_shrink_progress())
	var earned: Dictionary = {}
	var total: float = 0.0
	for team: int in _in_zone.keys():
		var counted: int = mini(int(_in_zone[team]), data.max_counted_tanks)
		var points: float = rate * counted * dt
		if team == majority_team:
			points *= data.majority_multiplier
		earned[team] = points
		total += points
	# The last points of the budget are shared in the same proportions.
	var scale: float = minf(1.0, _budget_left / total) if total > 0.0 else 0.0
	for team: int in earned.keys():
		_scores[team] = get_score(team) + float(earned[team]) * scale
		var tanks_here: Array = _zone_tanks.get(team, [])
		for t: Tank in tanks_here:
			_stat_add(t, 4, float(earned[team]) * scale / tanks_here.size())
	_budget_left = maxf(_budget_left - total * scale, 0.0)


## The team with the most tanks in the zone, or -1 if none or tied.
func _majority_team() -> int:
	var best_team: int = -1
	var best: int = 0
	var tied: bool = false
	for team: int in _in_zone.keys():
		var n: int = int(_in_zone[team])
		if n > best:
			best = n
			best_team = team
			tied = false
		elif n == best:
			tied = true
	return -1 if tied else best_team


## Every tank's [name, team, knock-outs, losses, points], best first (the host's list
## on clients).
func get_stats() -> Array:
	if NetRole.is_client():
		return _net_stats
	var out: Array = []
	for id: int in _stats:
		var row: Array = (_stats[id] as Array).duplicate()
		var tank := instance_from_id(id) as Tank
		if not is_instance_valid(tank):
			continue   # removed (extra bots, players who left)
		row[0] = tank.get_display_label()
		row[1] = tank.team   # NetGame sorts the map's bots into teams after they are counted
		row[4] = roundi(float(row[4]))
		out.append(row)
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[4]) > int(b[4]))
	return out


func _stat_add(tank: Tank, field: int, amount: float) -> void:
	var row: Array = _stats.get(tank.get_instance_id(), [])
	if not row.is_empty():
		row[field] = row[field] + amount


## Tanks come and go (respawns, network spawns): hook up new ones for the kill bonus.
func _connect_new_tanks() -> void:
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or _connected.has(tank.get_instance_id()):
			continue
		_connected[tank.get_instance_id()] = true
		tank.shot_landed.connect(_on_shot_landed.bind(tank))
		_stats[tank.get_instance_id()] = [tank.get_display_label(), tank.team, 0, 0, 0.0]
		tank.knocked_out.connect(func() -> void:
			if not _over:
				_stat_add(tank, 3, 1))


func _on_shot_landed(result: HitResult, shooter: Tank) -> void:
	if _over or result == null or not result.knocked_out or not is_instance_valid(shooter):
		return
	var victim := result.target as Tank
	if victim == null or not shooter.is_enemy_of(victim):
		return
	_stat_add(shooter, 2, 1)
	if not is_in_zone(shooter.global_position) or not is_in_zone(victim.global_position):
		return
	var factor: float = lerpf(data.kill_bonus_factor_start, data.kill_bonus_factor_end,
			get_shrink_progress())
	var points: float = minf(data.kill_bonus_points * factor, _budget_left)
	if points <= 0.0:
		return
	_budget_left -= points
	_scores[shooter.team] = get_score(shooter.team) + points
	_stat_add(shooter, 4, points)
	kill_bonus.emit(shooter.team, points)


func _check_score_win() -> void:
	for team: int in _scores.keys():
		if float(_scores[team]) >= data.score_to_win:
			_end_by_score()
			return


func _end_by_score() -> void:
	var leader: int = -1
	var best: float = -1.0
	var tied: bool = false
	for team: int in _scores.keys():
		var s: float = float(_scores[team])
		if s > best:
			best = s
			leader = team
			tied = false
		elif s == best:
			tied = true
	_over = true
	_winner = -1 if tied else leader
	match_over.emit(_winner)
