class_name Squad
extends Node3D
## An infantry squad riding on a tank (TankData.squad): one unit of a few soldiers.
## It never reads input: the tank passes on its command's squad orders (move to a
## point, recall). Mounted it rides along unseen; sent out it gets off behind the
## tank and runs along a path for walkers (TacticalMap with the squad's tactics:
## forest cheap, open ground dear), never further than max_distance_from_tank_m from
## the tank; recalled (or left behind by its tank) it runs back and mounts.
## Lives in the map next to its tank, not under it (the tank moves on).
##
## Soldiers move one by one: on the move each keeps a loose place of his own behind
## the squad's point (own pace, drifting a little); when the squad holds they spread out
## 4-9 m round it, each to a spot of his own (covered if there is one) facing outwards
## (hedgehog), and each kneels once he stands still. The leader is the first living
## soldier (the player can look through his eyes, PlayerViews squad view).
##
## Spotting: same rules as tank crews (sight lines, cover, stillness), all round when
## holding, a cone ahead when moving; enemies it makes out become marks for the team
## (Tank.report_squad_spot), again every mark_interval_s while in sight.
## Fighting (holding still only): rifle bursts at exposed commanders and enemy soldiers
## (low accuracy), AT rounds at tanks within at_range_m (they never knock a tank out).
## Any hit puts a soldier down; one of them is "Wilhelm". Fired on by a tank (a hit, or
## a shell landing close) it throws smoke and falls back towards its tank; losing a man
## to rifles it just falls back. Mounted, the missing come back one by one; wiped out,
## a new squad is ready on the tank after wipe_cooldown_s. No friendly fire.
## Network: the host runs all this; on clients the squad is a puppet (net_puppet) shown
## from the host's state.

signal soldier_down(index: int, screamed: bool)
signal smoke_thrown(at: Vector3)
## A round left a soldier's weapon (kind: SHOT_RIFLE / SHOT_AT), for the network.
signal fired_round(kind: int, from: Vector3, velocity: Vector3)

enum State { MOUNTED, MOVING, HOLDING, RETURNING, WIPED }

## Orders in TankCommand.squad_order.
const ORDER_NONE: int = 0
const ORDER_MOVE: int = 1
const ORDER_RECALL: int = 2
## A waypoint counts as reached this close (m).
const WAYPOINT_RADIUS_M: float = 3.0
## Soldiers turn towards where they go this fast (radians/s).
const TURN_RATE: float = 4.0
## Re-plan the way back to a moving tank this often (s).
const RETURN_REPLAN_S: float = 3.0
## Points looked at on an enemy tank (above its origin, m).
const TANK_LOOK_HEIGHTS: Array[float] = [0.5, 1.9]
## Loaded at start, not preloaded: shell.gd refers back to Squad (a preload would cycle).
const SHELL_SCENE_PATH: String = "res://scenes/weapons/shell.tscn"
const SHOT_RIFLE: int = 0
const SHOT_AT: int = 1
## Bytes in one squad's network state before the soldiers (write_net_state), and per
## soldier after them.
const NET_HEADER_BYTES: int = 31
const NET_SOLDIER_BYTES: int = 4
## Holding, soldiers spread this far from the squad's point (m)...
const SPREAD_MIN_M: float = 4.0
const SPREAD_MAX_M: float = 9.0
## ...trying this many spots each for one with cover.
const SPREAD_TRIES: int = 5
## Soldiers run this much faster than the squad's point, to catch up with their place.
const CATCH_UP_FACTOR: float = 1.25
## On the move each soldier drifts up to this far from his place in the formation (m)...
const DRIFT_M: float = 1.5
## ...picking a new drift this often (s).
const DRIFT_CHANGE_S: float = 3.0
## Slower than this a soldier counts as standing (m/s).
const STANDING_SPEED: float = 0.4
## Puppets slide to the host's position this fast (1/s).
const NET_FOLLOW_RATE: float = 10.0
## Kneeling soldiers' body height as a share of standing (hitbox).
const KNEEL_HITBOX_SHARE: float = 0.6

var tank: Tank
var data: SquadData
## Client side: shown from the host's state, no logic of its own.
var net_puppet: bool = false

var _state: State = State.MOUNTED
var _path: Array[Vector3] = []
var _goal: Vector3 = Vector3.ZERO
var _heading: Vector3 = Vector3.FORWARD
var _soldiers: Array[Node3D] = []
## Each soldier's visible body (model or capsule), scaled when kneeling.
var _meshes: Array[Node3D] = []
## The body's height above the feet when standing (capsules sit on their middle).
var _body_offset: float = 0.0
var _hitboxes: Array[SoldierHitbox] = []
var _alive: Array[bool] = []
var _down_time: Array[float] = []
var _wilhelm: int = 0
var _replan_timer: float = 0.0
var _map: TacticalMap
var _map_looked_up: bool = false
## Per soldier: 0 = standing, 1 = kneeling (eases between).
var _kneel: Array[float] = []
## Per soldier: his spot round the squad's point while holding (offset), his pace, his
## drift on the move (and its target).
var _spot: Array[Vector3] = []
var _pace: Array[float] = []
var _drift: Array[Vector3] = []
var _drift_target: Array[Vector3] = []
var _drift_timer: float = 0.0
var _spots_chosen: bool = false
## Client: soldiers' offsets from the squad's point, from the host.
var _net_offsets: Array[Vector3] = []
var _clock: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _shell_scene: PackedScene
# Spotting
var _scan_timer: float = 0.0
var _awareness: Dictionary = {}  # target (Tank / SoldierHitbox) -> seconds looked at
var _spotted: Dictionary = {}  # target -> true
var _in_sight: Dictionary = {}  # target -> true at the last scan
var _marked_at: Dictionary = {}  # target -> clock of the last team mark
# Weapons
var _burst_timer: Array[float] = []
var _burst_left: Array[int] = []
var _shot_timer: Array[float] = []
var _at_left: int = 0
var _at_timer: float = 0.0
var _smoke_left: int = 0
var _withdraw_timer: float = 0.0
# Losses
var _refill_timer: float = 0.0
var _wipe_timer: float = 0.0
# Network puppet: the host's numbers
var _net_position: Vector3 = Vector3.ZERO
var _net_at: int = 0
var _net_smoke: int = 0
var _net_timer: float = 0.0


func _ready() -> void:
	add_to_group("squads")
	_rng.randomize()
	_shell_scene = load(SHELL_SCENE_PATH)
	for i: int in data.soldier_count:
		_add_soldier(i)
	_wilhelm = _rng.randi_range(0, data.soldier_count - 1)
	_at_left = data.at_rounds
	_smoke_left = data.smoke_grenades
	visible = false
	_set_hitboxes_active(false)


# --- Queries -----------------------------------------------------------------------

func get_state() -> State:
	return _state


func is_mounted() -> bool:
	return _state == State.MOUNTED


## Off the tank and with someone alive (can be seen, ordered, looked through).
func is_out() -> bool:
	return _state != State.MOUNTED and _state != State.WIPED


func get_team() -> int:
	return tank.team if is_instance_valid(tank) else -1


func get_heading() -> Vector3:
	return _heading


func get_alive_count() -> int:
	return _alive.count(true)


func is_soldier_alive(index: int) -> bool:
	return _alive[index]


## A soldier that can be hit: alive and off the tank.
func is_soldier_exposed(index: int) -> bool:
	return is_out() and _alive[index]


func get_hitboxes() -> Array[SoldierHitbox]:
	return _hitboxes


func get_at_rounds_left() -> int:
	return _net_at if net_puppet else _at_left


func get_smoke_left() -> int:
	return _net_smoke if net_puppet else _smoke_left


## Seconds until the next soldier is back on the tank (0 when full).
func get_refill_time_left() -> float:
	if get_alive_count() >= data.soldier_count or _state != State.MOUNTED:
		return 0.0
	if net_puppet:
		return _net_timer
	return maxf(data.refill_time_s - _refill_timer, 0.0)


## Seconds until a wiped-out squad is back (0 otherwise).
func get_wipe_time_left() -> float:
	if _state != State.WIPED:
		return 0.0
	return _net_timer if net_puppet else maxf(data.wipe_cooldown_s - _wipe_timer, 0.0)


## The leader: the first living soldier (null if none).
func get_leader() -> Node3D:
	for i: int in _soldiers.size():
		if _alive[i]:
			return _soldiers[i]
	return null


## The leader's eyes (world): lower when kneeling.
func get_leader_eye() -> Vector3:
	var leader: Node3D = get_leader()
	var at: Vector3 = leader.global_position if leader != null else global_position
	return at + Vector3.UP * _eye_height()


## The leader kneels (lower eyes).
func is_kneeling() -> bool:
	var i: int = _first_alive()
	return i >= 0 and _kneel[i] >= 0.5


## Where it is going (for the map), or its own position when holding.
func get_goal() -> Vector3:
	return _goal if _state == State.MOVING or _state == State.RETURNING else global_position


# --- Orders ------------------------------------------------------------------------

## From the tank, each physics frame its command carries an order.
func order(kind: int, target: Vector3) -> void:
	if net_puppet or not is_instance_valid(tank) or tank.is_knocked_out() or _state == State.WIPED:
		return
	match kind:
		ORDER_MOVE:
			if _state == State.MOUNTED:
				if get_alive_count() == 0:
					return
				_dismount()
			_move_to(_clamp_to_tank(target))
		ORDER_RECALL:
			if _state != State.MOUNTED:
				_start_return()


# --- Frame -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_instance_valid(tank):
		queue_free()
		return
	if net_puppet:
		if is_out():
			global_position = global_position.lerp(_net_position, minf(delta * NET_FOLLOW_RATE, 1.0))
			_move_soldiers(delta)
		else:
			global_position = tank.global_position
		_update_bodies(delta)
		return
	_clock += delta
	match _state:
		State.MOUNTED:
			global_position = tank.global_position
			_refill(delta)
			return
		State.WIPED:
			_wipe_timer += delta
			_update_bodies(delta)
			if _wipe_timer >= data.wipe_cooldown_s:
				_restore_full()
			return
	if tank.is_knocked_out():
		_state = State.HOLDING   # its tank is gone: the squad stays put
	var to_tank: float = _flat(tank.global_position - global_position).length()
	if _state != State.RETURNING and not tank.is_knocked_out() \
			and to_tank > data.max_distance_from_tank_m + data.leash_margin_m:
		_start_return()
	if _state == State.RETURNING:
		if to_tank <= data.mount_distance_m:
			_mount()
			return
		_replan_timer -= delta
		if _replan_timer <= 0.0:
			_replan_timer = RETURN_REPLAN_S
			_path = _plan(tank.global_position)
	if _state == State.MOVING or _state == State.RETURNING:
		_walk(delta)
	_move_soldiers(delta)
	_update_bodies(delta)
	_withdraw_timer = maxf(_withdraw_timer - delta, 0.0)
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer += data.scan_interval_s
		_scan(data.scan_interval_s)
	if _state == State.HOLDING:
		_fight(delta)


# --- Moving, mounting --------------------------------------------------------------

func _dismount() -> void:
	var back: Vector3 = tank.global_basis.z
	back.y = 0.0
	global_position = tank.global_position + back.normalized() * data.dismount_behind_m
	_heading = -back.normalized()
	_state = State.HOLDING
	visible = true
	for i: int in _soldiers.size():
		_soldiers[i].visible = _alive[i]
	_set_hitboxes_active(true)
	global_position.y = _ground_height(global_position, global_position.y)
	_spots_chosen = false
	_snap_soldiers()


func _mount() -> void:
	_state = State.MOUNTED
	_path.clear()
	visible = false
	_set_hitboxes_active(false)
	_forget_all()


func _move_to(target: Vector3) -> void:
	_goal = target
	_path = _plan(target)
	_state = State.MOVING


func _start_return() -> void:
	_state = State.RETURNING
	_goal = tank.global_position
	_path = _plan(_goal)
	_replan_timer = RETURN_REPLAN_S


## Orders further than max_distance_from_tank_m from the tank are pulled in to it.
func _clamp_to_tank(target: Vector3) -> Vector3:
	var offset: Vector3 = _flat(target - tank.global_position)
	if offset.length() > data.max_distance_from_tank_m:
		offset = offset.normalized() * data.max_distance_from_tank_m
	return tank.global_position + offset


func _plan(target: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var map: TacticalMap = _tactical_map()
	if map != null:
		for p: Vector3 in map.find_path(global_position, target):
			points.append(p)
	if points.is_empty():
		points.append(target)
	return points


func _tactical_map() -> TacticalMap:
	if not _map_looked_up:
		_map_looked_up = true
		_map = TacticalMap.for_scene(get_tree().current_scene, data.tactics)
	return _map


func _walk(delta: float) -> void:
	if _path.is_empty():
		if _state == State.MOVING:
			_state = State.HOLDING
		return
	var to_next: Vector3 = _flat(_path[0] - global_position)
	if to_next.length() <= WAYPOINT_RADIUS_M:
		_path.remove_at(0)
		return
	var dir: Vector3 = to_next.normalized()
	_heading = _heading.slerp(dir, minf(delta * TURN_RATE, 1.0)).normalized()
	var p: Vector3 = global_position + dir * minf(data.run_speed_mps * delta, to_next.length())
	p.y = _ground_height(p, global_position.y)
	global_position = p


func _is_moving() -> bool:
	if net_puppet:
		return _state == State.MOVING or _state == State.RETURNING
	return (_state == State.MOVING or _state == State.RETURNING) and not _path.is_empty()


## Each living soldier heads for his own place: a loose spot in the formation behind
## the squad's point on the move, his own spot round it when holding; he walks there at
## his own pace, faces where he goes (outwards when standing) and kneels once still.
func _move_soldiers(delta: float) -> void:
	var moving_squad: bool = _is_moving()
	if moving_squad:
		_spots_chosen = false
		_update_drift(delta)
	elif not _spots_chosen and not net_puppet:
		_choose_spots()
	var side: Vector3 = _heading.cross(Vector3.UP).normalized()
	for i: int in _soldiers.size():
		if not _alive[i]:
			continue   # the fallen stay where they fell
		var target: Vector3 = _place_of(i, moving_squad, side)
		var soldier: Node3D = _soldiers[i]
		var pos: Vector3 = soldier.global_position
		var to: Vector3 = _flat(target - pos)
		var step: float = minf(to.length(), data.run_speed_mps * CATCH_UP_FACTOR * _pace[i] * delta)
		var walking: bool = delta > 0.0 and step / delta > STANDING_SPEED
		if step > 0.001:
			pos += to.normalized() * step
		pos.y = _ground_height(pos, global_position.y)
		soldier.global_position = pos
		var facing: Vector3 = to.normalized() if walking else _flat(pos - global_position)
		if facing.length() < 0.1:
			facing = _heading
		soldier.look_at(pos + facing.normalized(), Vector3.UP)
		var was: bool = _kneel[i] >= 0.5
		_kneel[i] = move_toward(_kneel[i], 0.0 if walking else 1.0,
				delta / maxf(data.stance_change_s, 0.01))
		if (_kneel[i] >= 0.5) != was:
			_size_hitbox(i)
		var height_scale: float = lerpf(1.0, data.kneel_height_share, _kneel[i])
		_meshes[i].rotation = Vector3(0.0, _body_yaw(), 0.0)
		_meshes[i].scale = _body_scale() * Vector3(1.0, height_scale, 1.0)
		_meshes[i].position = Vector3(0.0, _body_offset * height_scale, 0.0)


## Where soldier `i` is heading now (world, flat).
func _place_of(i: int, moving_squad: bool, side: Vector3) -> Vector3:
	if net_puppet and i < _net_offsets.size():
		return global_position + _net_offsets[i]
	if not moving_squad:
		return global_position + _spot[i]
	var row: int = (i + 1) >> 1
	var lateral: float = row * (1.0 if i % 2 == 1 else -1.0)
	return global_position - _heading * row * data.spacing_m + side * lateral * data.spacing_m \
			+ _drift[i]


## Everyone straight to his place (getting off the tank).
func _snap_soldiers() -> void:
	var side: Vector3 = _heading.cross(Vector3.UP).normalized()
	for i: int in _soldiers.size():
		if _alive[i]:
			var p: Vector3 = _place_of(i, true, side)
			p.y = _ground_height(p, global_position.y)
			_soldiers[i].global_position = p
			_kneel[i] = 0.0
			_size_hitbox(i)
	_move_soldiers(0.0)


## Each soldier gets his own spot round the squad's point: spread out all round,
## covered (bushes, trees, a wall) if one of a few tries finds it, never in a house.
func _choose_spots() -> void:
	_spots_chosen = true
	var map: TacticalMap = _tactical_map()
	var base: float = atan2(_heading.x, _heading.z)
	var n: int = maxi(_soldiers.size(), 1)
	for i: int in _soldiers.size():
		var best := Vector3.ZERO
		var found_open: bool = false
		for k: int in SPREAD_TRIES:
			var angle: float = base + TAU * i / n + _rng.randf_range(-0.4, 0.4)
			var offset := Vector3(sin(angle), 0.0, cos(angle)) * _rng.randf_range(SPREAD_MIN_M, SPREAD_MAX_M)
			var p: Vector3 = global_position + offset
			if map != null and map.is_blocked(p):
				continue
			if not found_open:
				best = offset
				found_open = true
			if map == null or map.is_covered(p):
				best = offset
				break
		_spot[i] = best


## On the move each soldier drifts slowly round his place in the formation.
func _update_drift(delta: float) -> void:
	_drift_timer -= delta
	if _drift_timer <= 0.0:
		_drift_timer = DRIFT_CHANGE_S
		for i: int in _drift_target.size():
			var v: Vector2 = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * DRIFT_M
			_drift_target[i] = Vector3(v.x, 0.0, v.y)
	for i: int in _drift.size():
		_drift[i] = _drift[i].move_toward(_drift_target[i], delta * 0.5)


func _eye_height() -> float:
	var i: int = _first_alive()
	var k: float = _kneel[i] if i >= 0 else 0.0
	return lerpf(data.eye_height_standing_m, data.eye_height_kneeling_m, k)


## Ground (terrain, a bridge deck...) under `p`; tree trunks and tanks don't count.
func _ground_height(p: Vector3, fallback: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 30.0, p.z),
			Vector3(p.x, p.y - 60.0, p.z))
	query.collision_mask = 1
	var exclude: Array[RID] = []
	for i: int in 4:
		query.exclude = exclude
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return fallback
		var collider: Object = hit["collider"]
		if collider is TreeField or collider is Tank:
			exclude.append(hit["rid"])
			continue
		return (hit["position"] as Vector3).y
	return fallback


# --- Spotting ----------------------------------------------------------------------

## Enemy tanks and enemy soldiers in range and sight; spotting time as for tank crews
## (cover, stillness, how much shows), longer for small soldiers.
func _scan(dt: float) -> void:
	var eye: Vector3 = get_leader_eye()
	var seen_now: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var other := node as Tank
		if other == null or other.is_knocked_out() or other.team == get_team():
			continue
		var points: Array = []
		for h: float in TANK_LOOK_HEIGHTS:
			points.append([other.global_position + Vector3.UP * h, other])
		if other.is_commander_exposed():
			points.append([other.get_commander_hitbox_position(), other.get_commander_hitbox()])
		_look(other, eye, points, 1.0, dt, seen_now)
	for node: Node in get_tree().get_nodes_in_group("squads"):
		var enemy := node as Squad
		if enemy == null or enemy == self or not enemy.is_out() or enemy.get_team() == get_team():
			continue
		for hb: SoldierHitbox in enemy.get_hitboxes():
			if enemy.is_soldier_exposed(hb.index):
				_look(hb, eye, [[hb.get_aim_point(), hb]], data.soldier_spot_factor, dt, seen_now)
	for target: Variant in _awareness.keys():
		if is_instance_valid(target) and seen_now.has(target):
			continue
		_in_sight.erase(target)
		var left: float = float(_awareness[target]) - dt
		if not is_instance_valid(target) or left <= 0.0:
			_awareness.erase(target)
			_spotted.erase(target)
		else:
			_awareness[target] = left


## One look at `target` through its `points` ([world point, collider] pairs).
func _look(target: Node3D, eye: Vector3, points: Array, size_factor: float, dt: float,
		seen_now: Dictionary) -> void:
	var time_factor: float = 1.0
	var range_factor: float = 1.0
	if data.concealment != null:
		var cover: float = Concealment.cover(get_world_3d(), target, data.concealment)
		var speed: float = (target as Tank).linear_velocity.length() if target is Tank else 0.0
		time_factor = Concealment.spot_time_factor(cover, speed, data.concealment)
		range_factor = Concealment.range_factor(cover, data.concealment)
	var view_range: float = data.view_range_m * range_factor
	var seen: int = 0
	for pair: Array in points:
		var p: Vector3 = pair[0]
		if eye.distance_to(p) > view_range or not _in_view_cone(p):
			continue
		if Vision.has_line_of_sight(get_world_3d(), eye, p, pair[1], _own_rids()):
			seen += 1
	if seen == 0:
		return
	seen_now[target] = true
	_in_sight[target] = true
	var shown: float = float(seen) / float(points.size())
	var needed: float = data.spot_time_s * size_factor * time_factor / maxf(shown, 0.2)
	var aware: float = float(_awareness.get(target, 0.0)) + dt
	_awareness[target] = aware
	if aware < needed:
		return
	_spotted[target] = true
	if not _marked_at.has(target) or _clock - float(_marked_at[target]) >= data.mark_interval_s:
		_marked_at[target] = _clock
		var enemy: Node3D = target if target is Tank else (target as SoldierHitbox).squad
		tank.report_squad_spot(enemy, target.global_position)


## All round while holding; a cone ahead while on the move.
func _in_view_cone(p: Vector3) -> bool:
	if not _is_moving():
		return true
	var to_p: Vector3 = _flat(p - global_position)
	return to_p.length() < 1.0 \
			or _heading.angle_to(to_p.normalized()) <= deg_to_rad(data.moving_view_cone_deg * 0.5)


func _forget_all() -> void:
	_awareness.clear()
	_spotted.clear()
	_in_sight.clear()


func _own_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for hb: SoldierHitbox in _hitboxes:
		rids.append(hb.get_rid())
	return rids


## Spotted targets in sight right now (Tank or SoldierHitbox), nearest first.
func _targets_in_sight() -> Array[Node3D]:
	var list: Array[Node3D] = []
	for target: Variant in _in_sight.keys():
		if is_instance_valid(target) and _spotted.has(target):
			list.append(target)
	list.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return global_position.distance_to(a.global_position) \
				< global_position.distance_to(b.global_position))
	return list


# --- Fighting ----------------------------------------------------------------------

func _fight(delta: float) -> void:
	_at_timer = maxf(_at_timer - delta, 0.0)
	var targets: Array[Node3D] = _targets_in_sight()
	if targets.is_empty():
		return
	_try_at_round(targets)
	var rifle_target: Node3D = null
	var rifle_aim := Vector3.ZERO
	for target: Node3D in targets:
		var aim: Vector3 = _rifle_aim(target)
		if aim != Vector3.INF and global_position.distance_to(aim) <= data.rifle_range_m:
			rifle_target = target
			rifle_aim = aim
			break
	for i: int in _soldiers.size():
		if not _alive[i]:
			continue
		_burst_timer[i] -= delta
		if _burst_left[i] > 0:
			_shot_timer[i] -= delta
			if _shot_timer[i] <= 0.0 and rifle_target != null:
				_shot_timer[i] = data.rifle_shot_gap_s
				_burst_left[i] -= 1
				_fire(i, data.rifle_bullet, rifle_aim, rifle_target, data.rifle_dispersion_mrad,
						data.rifle_sound)
		elif _burst_timer[i] <= 0.0 and rifle_target != null:
			_burst_left[i] = data.rifle_burst_shots
			_shot_timer[i] = 0.0
			_burst_timer[i] = data.rifle_burst_interval_s * _rng.randf_range(0.8, 1.3)


## Where rifles aim at `target`: an exposed commander's head or a soldier; INF if the
## target isn't something rifles can hurt (a tank with its hatch shut).
func _rifle_aim(target: Node3D) -> Vector3:
	if target is SoldierHitbox:
		return (target as SoldierHitbox).get_aim_point()
	var other := target as Tank
	if other != null and other.is_commander_exposed():
		return other.get_commander_hitbox_position()
	return Vector3.INF


func _try_at_round(targets: Array[Node3D]) -> void:
	if _at_left <= 0 or _at_timer > 0.0 or data.at_round == null:
		return
	for target: Node3D in targets:
		var other := target as Tank
		if other == null or global_position.distance_to(other.global_position) > data.at_range_m:
			continue
		var gunner: int = 1 if _soldiers.size() > 1 and _alive[1] else _first_alive()
		if gunner < 0:
			return
		var spread: float = data.at_dispersion_mrad
		if other.linear_velocity.length() * 3.6 > data.at_fast_target_kmh:
			spread *= data.at_moving_factor
		_fire(gunner, data.at_round, other.global_position + Vector3.UP * 0.6, other, spread,
				data.at_sound)
		_at_left -= 1
		_at_timer = data.at_interval_s
		return


## One round from soldier `i` at `aim` (led for a moving tank), with random spread.
func _fire(i: int, shell_data: ShellData, aim: Vector3, target: Node3D, spread_mrad: float,
		sound: SoundSetData) -> void:
	var from: Vector3 = _soldiers[i].global_position + Vector3.UP \
			* lerpf(data.eye_height_standing_m, data.eye_height_kneeling_m, _kneel[i])
	var moving: Tank = target as Tank
	if moving != null:
		var flight: float = from.distance_to(aim) / maxf(shell_data.muzzle_velocity_mps, 1.0)
		aim += moving.linear_velocity * flight
	var dir: Vector3 = (aim - from).normalized()
	var side: Vector3 = dir.cross(Vector3.UP).normalized()
	var up: Vector3 = side.cross(dir).normalized()
	var r: float = sqrt(_rng.randf()) * spread_mrad * 0.001
	var a: float = _rng.randf() * TAU
	dir = (dir + side * cos(a) * r + up * sin(a) * r).normalized()
	var shell := _shell_scene.instantiate() as Shell
	get_parent().add_child(shell)
	shell.launch(shell_data, from, dir * shell_data.muzzle_velocity_mps, _hitboxes[i])
	SoundFx.play_at(self, sound, from)
	fired_round.emit(SHOT_AT if shell_data == data.at_round else SHOT_RIFLE, from,
			dir * shell_data.muzzle_velocity_mps)


func _first_alive() -> int:
	for i: int in _alive.size():
		if _alive[i]:
			return i
	return -1


# --- Being hit ---------------------------------------------------------------------

## A shell, bullet or fragment hit soldier `index`: he goes down.
func soldier_hit(index: int, shell_data: ShellData) -> HitResult:
	if net_puppet or not is_soldier_exposed(index):
		return null
	var screamed: bool = index == _wilhelm and _rng.randf() < data.scream_chance
	_put_down(index, screamed)
	var result := HitResult.new()
	result.note = "SOLDIER DOWN"
	if get_alive_count() == 0:
		_wipe()
	elif shell_data != null and shell_data.infantry:
		_withdraw(false, Vector3.INF)
	else:
		_withdraw(true, Vector3.INF)
	return result


## Soldier `index` falls (host or, from the host's news, a client).
func _put_down(index: int, screamed: bool) -> void:
	_alive[index] = false
	_down_time[index] = 0.0
	_hitboxes[index].set_active(false)
	_meshes[index].rotation = Vector3(deg_to_rad(90.0), _body_yaw(), 0.0)
	_meshes[index].position = Vector3(0.0, data.soldier_radius_m, 0.0)
	if screamed:
		SoundFx.play_at(self, data.scream_sound, _soldiers[index].global_position + Vector3.UP)
	soldier_down.emit(index, screamed)


## A tank's shell landed near the squad (`point`): smoke and fall back.
func on_near_miss(point: Vector3) -> void:
	if not net_puppet and is_out():
		_withdraw(true, point)


## Shells on the host: tell squads near the impact (not infantry fire, not the
## shooter's own team: no friendly fire).
static func notify_impact(tree: SceneTree, point: Vector3, shell_data: ShellData,
		shooter: Object) -> void:
	if shell_data.infantry:
		return
	for node: Node in tree.get_nodes_in_group("squads"):
		var squad := node as Squad
		if squad == null or not squad.is_out() or Tank.is_friendly(shooter, squad):
			continue
		if squad.global_position.distance_to(point) > squad.data.near_miss_m + squad.data.spacing_m * 3.0:
			continue
		for hb: SoldierHitbox in squad.get_hitboxes():
			if squad.is_soldier_exposed(hb.index) \
					and hb.global_position.distance_to(point) <= squad.data.near_miss_m:
				squad.on_near_miss(point)
				break


## Fall back towards the own tank (fired on by a tank: smoke first, towards the threat).
func _withdraw(smoke: bool, threat_point: Vector3) -> void:
	if _withdraw_timer > 0.0 or not is_instance_valid(tank):
		return
	_withdraw_timer = data.withdraw_cooldown_s
	if smoke and _smoke_left > 0:
		_smoke_left -= 1
		throw_smoke(global_position + _threat_direction(threat_point) * data.smoke_ahead_m)
	var back: Vector3 = _flat(tank.global_position - global_position)
	if back.length() < 1.0:
		return
	_move_to(global_position + back.normalized() * minf(data.fallback_m, back.length()))


## Towards the nearest enemy tank in sight, else the impact, else away from the own tank.
func _threat_direction(threat_point: Vector3) -> Vector3:
	for target: Node3D in _targets_in_sight():
		if target is Tank:
			return _flat(target.global_position - global_position).normalized()
	if threat_point != Vector3.INF and _flat(threat_point - global_position).length() > 1.0:
		return _flat(threat_point - global_position).normalized()
	var away: Vector3 = _flat(global_position - tank.global_position)
	return away.normalized() if away.length() > 1.0 else _heading


func throw_smoke(at: Vector3) -> void:
	var cloud := SmokeCloud.new()
	cloud.radius_m = data.smoke_radius_m
	cloud.lifetime_s = data.smoke_lifetime_s
	get_parent().add_child(cloud)
	cloud.global_position = Vector3(at.x, _ground_height(at, global_position.y), at.z)
	smoke_thrown.emit(cloud.global_position)


func _wipe() -> void:
	_state = State.WIPED
	_wipe_timer = 0.0
	_path.clear()
	_forget_all()


## Fallen soldiers vanish after body_time_s.
func _update_bodies(delta: float) -> void:
	for i: int in _soldiers.size():
		if not _alive[i] and _soldiers[i].visible:
			_down_time[i] += delta
			if _down_time[i] >= data.body_time_s:
				_soldiers[i].visible = false


# --- Refilling ---------------------------------------------------------------------

## On the tank: the missing come back one at a time; full again, ammo and smoke too.
func _refill(delta: float) -> void:
	if get_alive_count() >= data.soldier_count:
		_at_left = data.at_rounds
		_smoke_left = data.smoke_grenades
		_refill_timer = 0.0
		return
	_refill_timer += delta
	if _refill_timer >= data.refill_time_s:
		_refill_timer = 0.0
		_alive[_alive.find(false)] = true


func _restore_full() -> void:
	for i: int in _alive.size():
		_alive[i] = true
	_at_left = data.at_rounds
	_smoke_left = data.smoke_grenades
	_mount()


# --- Network ---------------------------------------------------------------------

## Host: this squad's state for the clients (NET_HEADER_BYTES, then the soldiers).
func write_net_state(buf: StreamPeerBuffer) -> void:
	var mask: int = 0
	for i: int in mini(_alive.size(), 8):
		if _alive[i]:
			mask |= 1 << i
	buf.put_u8(_state)
	buf.put_u8(mask)
	buf.put_u8(0)   # (unused: soldiers kneel by themselves)
	buf.put_float(global_position.x)
	buf.put_float(global_position.y)
	buf.put_float(global_position.z)
	buf.put_float(atan2(_heading.x, _heading.z))
	var goal: Vector3 = get_goal()
	buf.put_float(goal.x)
	buf.put_float(goal.z)
	buf.put_u8(_at_left)
	buf.put_u8(_smoke_left)
	var timer: float = get_wipe_time_left() if _state == State.WIPED else get_refill_time_left()
	buf.put_u16(clampi(roundi(timer * 10.0), 0, 65535))
	# Each soldier's place relative to the squad's point (decimetres), so clients see
	# them where the host's hitboxes are.
	buf.put_u8(_soldiers.size())
	for soldier: Node3D in _soldiers:
		var o: Vector3 = _flat(soldier.global_position - global_position)
		buf.put_16(clampi(roundi(o.x * 10.0), -32767, 32767))
		buf.put_16(clampi(roundi(o.z * 10.0), -32767, 32767))


## Client: takes the host's state (a puppet shows it; no logic of its own).
func read_net_state(buf: StreamPeerBuffer) -> void:
	var state: State = buf.get_u8() as State
	var mask: int = buf.get_u8()
	buf.get_u8()
	_net_position = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	var yaw: float = buf.get_float()
	_heading = Vector3(sin(yaw), 0.0, cos(yaw))
	_goal = Vector3(buf.get_float(), _net_position.y, buf.get_float())
	_net_at = buf.get_u8()
	_net_smoke = buf.get_u8()
	_net_timer = buf.get_u16() / 10.0
	var count: int = buf.get_u8()
	_net_offsets.resize(count)
	for i: int in count:
		_net_offsets[i] = Vector3(buf.get_16() / 10.0, 0.0, buf.get_16() / 10.0)
	var was_out: bool = is_out()
	_state = state
	if is_out() and not was_out:
		global_position = _net_position   # just got off: no sliding from the tank
		_snap_soldiers()
	for i: int in _alive.size():
		var alive: bool = (mask >> i) & 1 == 1
		if alive and not _alive[i]:
			_alive[i] = true
			_soldiers[i].visible = true
		elif not alive and _alive[i]:
			_put_down(i, false)   # screams come as their own event
	visible = is_out() or _state == State.WIPED
	_set_hitboxes_active(false)


## Client: skips one squad's state (its tank isn't known here yet).
static func skip_net_state(buf: StreamPeerBuffer) -> void:
	buf.seek(buf.get_position() + NET_HEADER_BYTES)
	var count: int = buf.get_u8()
	buf.seek(buf.get_position() + count * NET_SOLDIER_BYTES)


## Client: the host says soldier `index` fell (and whether he screamed).
func net_soldier_down(index: int, screamed: bool) -> void:
	if index >= 0 and index < _alive.size() and _alive[index]:
		_put_down(index, screamed)
	elif screamed:
		SoundFx.play_at(self, data.scream_sound, _soldiers[index].global_position + Vector3.UP)


## Client: a round the host's squad fired, shown here without effect.
func net_show_shot(kind: int, from: Vector3, velocity: Vector3) -> void:
	var shell_data: ShellData = data.at_round if kind == SHOT_AT else data.rifle_bullet
	var shell := _shell_scene.instantiate() as Shell
	get_parent().add_child(shell)
	shell.launch(shell_data, from, velocity, null, true)
	SoundFx.play_at(self, data.at_sound if kind == SHOT_AT else data.rifle_sound, from)


# --- Soldiers ----------------------------------------------------------------------

func _add_soldier(i: int) -> void:
	var root := Node3D.new()
	root.name = "Soldier%d" % i
	var mesh: Node3D = _make_body()
	mesh.position = Vector3(0.0, _body_offset, 0.0)
	root.add_child(mesh)
	var hitbox := SoldierHitbox.new()
	hitbox.squad = self
	hitbox.index = i
	root.add_child(hitbox)
	add_child(root)
	_soldiers.append(root)
	_meshes.append(mesh)
	_hitboxes.append(hitbox)
	_alive.append(true)
	_down_time.append(0.0)
	_kneel.append(0.0)
	_spot.append(Vector3.ZERO)
	_pace.append(_rng.randf_range(0.9, 1.1))
	_drift.append(Vector3.ZERO)
	_drift_target.append(Vector3.ZERO)
	_burst_timer.append(_rng.randf_range(0.0, data.rifle_burst_interval_s))
	_burst_left.append(0)
	_shot_timer.append(0.0)
	_size_hitbox(i)


## The soldier model in the uniform colour, or a capsule without a model.
func _make_body() -> Node3D:
	if data.model == null:
		_body_offset = data.soldier_height_m * 0.5
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.height = data.soldier_height_m
		capsule.radius = data.soldier_radius_m
		mesh.mesh = capsule
		var material := StandardMaterial3D.new()
		material.albedo_color = data.uniform_color
		material.roughness = 0.9
		mesh.material_override = material
		return mesh
	_body_offset = 0.0
	var body: Node3D = data.model.instantiate()
	body.scale = _body_scale()
	body.rotation = Vector3(0.0, _body_yaw(), 0.0)
	var shades: Array[Color] = [data.uniform_color.lightened(0.12), data.uniform_color.darkened(0.15)]
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s: int in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(s)
			var k: int = data.uniform_materials.find(mat.resource_name if mat != null else "")
			if k >= 0 and mat is StandardMaterial3D:
				var paint := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				paint.albedo_color = shades[mini(k, shades.size() - 1)]
				mi.set_surface_override_material(s, paint)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if data.model_animation != &"":
		for node: Node in body.find_children("*", "AnimationPlayer", true, false):
			var player := node as AnimationPlayer
			if player.has_animation(data.model_animation):
				player.play(data.model_animation)
	return body


func _body_scale() -> Vector3:
	return Vector3.ONE * (data.model_scale if data.model != null else 1.0)


func _body_yaw() -> float:
	return deg_to_rad(data.model_yaw_deg) if data.model != null else 0.0


## Soldier `i`'s hitbox: shorter while he kneels.
func _size_hitbox(i: int) -> void:
	var h: float = data.soldier_height_m * (KNEEL_HITBOX_SHARE if _kneel[i] >= 0.5 else 1.0)
	_hitboxes[i].set_size(h, data.soldier_radius_m)


func _set_hitboxes_active(on: bool) -> void:
	for i: int in _hitboxes.size():
		_hitboxes[i].set_active(on and _alive[i])


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
