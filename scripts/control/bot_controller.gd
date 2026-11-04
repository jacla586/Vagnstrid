class_name BotController
extends TargetTankController
## A bot crew: patrols its waypoints (TargetTankController) until the commander spots
## an enemy tank, then stops, lays the gun and fires. Same rules as the player: it
## only knows what its commander has seen through Vision.has_line_of_sight(), from
## his eye, with the hatch open (all round, far, fast) or closed (periscope sector,
## shorter, slower). Drives the tank through TankCommand only.
##
## Gunnery: aims at the target's centre with lead and superelevation for its
## estimated range; the estimate starts off by up to range_error_start and improves
## with each shot. MGs go for an exposed enemy commander: the roof MG while its own
## hatch is open, else the coaxial MG while the main gun reloads.
## Hatch: open when calm; closed when a spotted enemy is close or after being hit,
## then reopened after a calm spell.
## Orders (BotGroup): order_move() replaces the patrol with a one-way route. With a
## target the bot keeps driving it and only halts for a shot when the gun is loaded
## and the target's hull is in sight (short halts).

## Emitted when this bot first spots an enemy, or is hit (`enemy` null, `at` a rough
## guess of where the shot came from).
signal contact(enemy: Tank, at: Vector3)

## Points on an enemy tank (its local space) that the commander tries to see: hull
## centre, turret top, front and rear of the hull. The more show, the faster he spots it.
const HULL_SAMPLE_POINTS: Array[Vector3] = [Vector3(0.0, 0.3, 0.0), Vector3(0.0, 1.5, 0.3),
		Vector3(0.0, 0.4, -2.9), Vector3(0.0, 0.4, 2.9)]
## Spotting time is divided by the share of points in sight, but never by less than this.
const MIN_SHOWN_SHARE: float = 0.2
## A shot from about this far away is assumed when guessing where a hit came from (m).
const HIT_ORIGIN_GUESS_M: float = 300.0
## How long the turret looks towards a reported or felt threat (s).
const ALERT_TIME_S: float = 10.0
## Stuck on an ordered route: try a point this far to the side (and a bit ahead) (m).
const DETOUR_SIDE_M: float = 25.0
const DETOUR_AHEAD_M: float = 10.0
## Cells remembered as blocked where this tank got stuck (planned round from then on).
const AVOID_MEMORY: int = 6
## The obstacle is taken to be this far ahead of the tank when it gets stuck (m).
const AVOID_AHEAD_M: float = 5.0
## Getting stuck again within this of the last place counts as the same spot (m).
const REPEAT_STUCK_RADIUS_M: float = 15.0
## Keep this gap to a tank ahead on the way (m): slow down from FOLLOW_GAP_M, stop at
## FOLLOW_STOP_M; after FOLLOW_PASS_S stopped behind it, go round.
const FOLLOW_GAP_M: float = 15.0
const FOLLOW_STOP_M: float = 8.0
const FOLLOW_PASS_S: float = 4.0
## A tank this far off our heading (degrees) isn't "ahead".
const FOLLOW_CONE_DEG: float = 40.0

@export var bot_data: BotData

var _awareness: Dictionary = {}  # Tank -> seconds looked at while (partly) in sight
var _spotted: Dictionary = {}  # Tank -> true once spotted (until forgotten)
var _cover: Dictionary = {}  # Tank -> cover at the last look
var _unseen_time: Dictionary = {}  # Tank -> seconds since last seen
var _hull_visible: Dictionary = {}  # Tank -> hull seen in the last scan
var _head_visible: Dictionary = {}  # Tank -> exposed commander seen in the last scan
var _target: Tank = null
var _scan_timer: float = 0.0
var _range_error: float = 0.0
## Current laying error as (right, up) offsets in radians; shrinks with each shot.
var _lay_error: Vector2 = Vector2.ZERO
## Current misjudgement of the target's speed for the lead (share, ±).
var _lead_error: float = 0.0
var _gun_superelevation: float = 0.0
var _mg_superelevation: float = 0.0
var _settle_time: float = 0.0
var _mg_time: float = 0.0
var _hit_close_timer: float = 0.0
var _calm_time: float = 0.0
var _needs_calm: bool = false
var _alert_direction: Vector3 = Vector3.ZERO
var _alert_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _orders: Array[Vector3] = []
var _order_index: int = 0
var _order_throttle: float = 0.5
var _halting: bool = false
var _detour_side: float = 1.0
## Goal of the current path order (order_path), for replanning; INF = none.
var _path_goal: Vector3 = Vector3.INF
var _path_throttle: float = 0.5
var _tactical: TacticalMap
var _tactical_looked_up: bool = false
## Where the tank last got stuck, and how many times in a row near there.
var _last_stuck_at: Vector3 = Vector3.INF
var _stuck_repeats: int = 0
## Seconds stopped behind another tank (FOLLOW_PASS_S then go round).
var _yield_time: float = 0.0
## Scouting stops still ahead on the current path, and time left at the current one.
var _scout_points: Array[Vector3] = []
var _scout_wait: float = 0.0
## Grid cells where this tank got stuck on something (newest last).
var _avoid_cells: Array[Vector2i] = []
## Seconds since the last contact (enemy seen, reported or a hit).
var _since_contact: float = INF
## Enemies reported by the group: spotted in half the time (the crew knows where to look).
var _reported: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	if tank != null:
		tank.hit_taken.connect(_on_hit_taken)


## The enemy tank this bot is engaging, or null.
func get_target() -> Tank:
	return _target


func is_spotted(other: Tank) -> bool:
	return _spotted.has(other)


## Cover around `other` at the last look (0..1), for tests and debugging.
func get_cover_of(other: Tank) -> float:
	return float(_cover.get(other, 0.0))


## Drives `points` in order once, at `throttle`, then stops. Replaces the patrol.
func order_move(points: Array[Vector3], throttle: float) -> void:
	_orders = points.duplicate()
	_order_index = 0
	_order_throttle = throttle
	_path_goal = Vector3.INF


## Drives to `goal` along a path round houses, water and steep ground (the map's
## tactical grid), then stops. Without a baked grid: straight there, as order_move.
## `urgent` = no scouting stops on the way (the zone is closing, back from a respawn...).
func order_path(goal: Vector3, throttle: float, urgent: bool = false) -> void:
	var points: Array[Vector3] = _plan_path(goal)
	order_move(points, throttle)
	_path_goal = goal
	_path_throttle = throttle
	_scout_points.clear()
	_scout_wait = 0.0
	var map: TacticalMap = _tactical_map()
	if not urgent and map != null:
		var path := PackedVector3Array(points)
		_scout_points = map.scout_points(tank.global_position, path, _tactics())


func is_scouting() -> bool:
	return _scout_wait > 0.0


func _tactics() -> TacticsData:
	return bot_data.tactics if bot_data != null and bot_data.tactics != null \
			else TacticalMap.DEFAULT_TACTICS


func _plan_path(goal: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var map: TacticalMap = _tactical_map()
	if map != null:
		for p: Vector3 in map.find_path(tank.global_position, goal, _avoid_cells):
			points.append(p)
	if points.is_empty():
		points.append(goal)
	return points


func _tactical_map() -> TacticalMap:
	if not _tactical_looked_up:
		_tactical_looked_up = true
		_tactical = TacticalMap.for_scene(get_tree().current_scene)
	return _tactical


func has_orders_left() -> bool:
	return _order_index < _orders.size()


## Radio report from the group: look towards `at`; `enemy` (if known) is spotted faster.
func share_contact(enemy: Tank, at: Vector3) -> void:
	if enemy != null:
		_reported[enemy] = true
	if _target == null:
		_alert_direction = at - tank.global_position
		_alert_timer = ALERT_TIME_S


func _physics_process(delta: float) -> void:
	if tank == null or bot_data == null:
		return
	if tank.is_knocked_out():
		_forget_all()
		_update_respawn(delta)
		return
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer += bot_data.scan_interval_s
		_scan(bot_data.scan_interval_s)
	_command.throttle = 0.0
	_command.steering = 0.0
	_command.fire = false
	_command.fire_mg = false
	_command.mg_use_roof = false
	_command.has_aim = false
	_alert_timer = maxf(_alert_timer - delta, 0.0)
	if _target != null or _alert_timer > 0.0 or _hit_close_timer > 0.0:
		_since_contact = 0.0
	else:
		_since_contact += delta
	_halting = false
	if _target != null and not is_instance_valid(_target):
		_target = null
	if _target != null:
		_engage(_target, delta)
	else:
		_settle_time = 0.0
		_mg_time = 0.0
		_look_ahead_or_at_threat()
	# Damaged and no enemy in sight: stand still and repair (same rules as players).
	var repairing: bool = _target == null and tank.needs_repair() and not tank.is_burning()
	if repairing:
		_command.throttle = 0.0
		_command.steering = 0.0
	elif not _orders.is_empty():
		if not _halting:
			_order_step(delta)
	elif _target == null:
		_patrol_step(delta)
	_update_hatch(delta)
	tank.set_command(_command)


# --- Spotting -------------------------------------------------------------------

func _spot_time() -> float:
	return bot_data.spot_time_open_s if tank.get_hatch_progress() >= 1.0 \
			else bot_data.spot_time_closed_s


func _spot_time_for(other: Tank) -> float:
	return _spot_time() * (0.5 if _reported.has(other) else 1.0)


func _scan(dt: float) -> void:
	_drop_freed()
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var other := node as Tank
		if other == null or not tank.is_enemy_of(other):
			continue
		if other.is_knocked_out():
			_forget(other)
			continue
		_look_at(other, dt)
	_pick_target()
	if _target != null:
		_update_superelevation(_target)


## One look at `other`: which of its sample points are in sight, how hard it is to
## make out (cover, movement, how much of it shows), and the spotting progress.
func _look_at(other: Tank, dt: float) -> void:
	var cover: float = 0.0
	var time_factor: float = 1.0
	var range_factor: float = 1.0
	var conceal: ConcealmentData = bot_data.concealment
	if conceal != null:
		cover = Concealment.cover(tank.get_world_3d(), other, conceal)
		time_factor = Concealment.spot_time_factor(cover, other.linear_velocity.length(), conceal)
		range_factor = Concealment.range_factor(cover, conceal)
	var seen_points: int = 0
	for local: Vector3 in HULL_SAMPLE_POINTS:
		if _can_see_point(other.to_global(local), other, range_factor):
			seen_points += 1
	var points: int = HULL_SAMPLE_POINTS.size()
	var head_seen: bool = false
	if other.is_commander_exposed():
		points += 1
		head_seen = _can_see_point(other.get_commander_hitbox_position(),
				other.get_commander_hitbox(), range_factor)
		if head_seen:
			seen_points += 1
	_hull_visible[other] = seen_points > (1 if head_seen else 0)
	_head_visible[other] = head_seen
	_cover[other] = cover
	var shown: float = float(seen_points) / float(points)
	var aware: float = float(_awareness.get(other, 0.0))
	if seen_points > 0:
		var needed: float = _spot_time_for(other) * time_factor / maxf(shown, MIN_SHOWN_SHARE)
		_unseen_time[other] = 0.0
		_awareness[other] = aware + dt
		if not _spotted.has(other) and aware + dt >= needed:
			_spotted[other] = true
			contact.emit(other, other.global_position)
	else:
		var unseen: float = float(_unseen_time.get(other, 0.0)) + dt
		_unseen_time[other] = unseen
		if not _spotted.has(other):
			_awareness[other] = maxf(aware - dt, 0.0)
		elif unseen >= bot_data.forget_after_s:
			_forget(other)


## Line of sight from this commander's eye to `point` on `collider`, within range
## and, with the hatch closed, within the periscope sector.
func _can_see_point(point: Vector3, collider: CollisionObject3D,
		range_factor: float = 1.0) -> bool:
	var eye: Vector3 = tank.get_commander_eye_position()
	var open: bool = tank.get_hatch_progress() >= 1.0
	var view_range: float = range_factor * (bot_data.view_range_open_m if open
			else bot_data.view_range_closed_m)
	if eye.distance_to(point) > view_range:
		return false
	if not open:
		var flat := Vector3(point.x - eye.x, 0.0, point.z - eye.z)
		var turret_forward := Vector3(sin(tank.get_turret_global_yaw()) * -1.0, 0.0,
				-cos(tank.get_turret_global_yaw()))
		if flat.angle_to(turret_forward) > deg_to_rad(bot_data.periscope_half_angle_deg):
			return false
	var exclude: Array[RID] = [tank.get_rid(), tank.get_commander_hitbox().get_rid()]
	return Vision.has_line_of_sight(tank.get_world_3d(), eye, point, collider, exclude)


func _pick_target() -> void:
	if _target != null and is_instance_valid(_target) and is_spotted(_target) \
			and not _target.is_knocked_out():
		return
	var previous: Tank = _target
	_target = null
	var best_distance: float = INF
	for other: Tank in _awareness.keys():
		if not is_instance_valid(other) or not is_spotted(other) or other.is_knocked_out():
			continue
		var distance: float = tank.global_position.distance_to(other.global_position)
		if distance < best_distance:
			best_distance = distance
			_target = other
	if _target != null and _target != previous:
		# New target: a fresh range estimate, off by up to range_error_start.
		_range_error = _rng.randf_range(-1.0, 1.0) * bot_data.range_error_start
		_lay_error = Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) \
				* bot_data.lay_error_mrad * 0.001
		_lead_error = _rng.randf_range(-1.0, 1.0) * bot_data.lead_error
		_settle_time = 0.0


func _forget(other: Tank) -> void:
	_awareness.erase(other)
	_spotted.erase(other)
	_cover.erase(other)
	_unseen_time.erase(other)
	_hull_visible.erase(other)
	_head_visible.erase(other)
	if other == _target:
		_target = null


## Forgets tanks that no longer exist (removed from the map, e.g. the map's own
## player tank when a network game spawns the players). Keys are checked untyped:
## a freed tank can't even be assigned to a Tank variable.
func _drop_freed() -> void:
	if _target != null and not is_instance_valid(_target):
		_target = null
	for memory: Dictionary in [_awareness, _spotted, _cover, _unseen_time, _hull_visible,
			_head_visible, _reported]:
		for key: Variant in memory.keys():
			if not is_instance_valid(key):
				memory.erase(key)


func _forget_all() -> void:
	_awareness.clear()
	_spotted.clear()
	_cover.clear()
	_unseen_time.clear()
	_hull_visible.clear()
	_head_visible.clear()
	_target = null


# --- Gunnery --------------------------------------------------------------------

func _update_superelevation(target: Tank) -> void:
	var range_m: float = _horizontal_distance(tank.get_muzzle_transform().origin,
			target.global_position)
	var shell: ShellData = tank.get_loaded_shell()
	if shell != null:
		_gun_superelevation = Ballistics.superelevation_for_range(shell,
				range_m * (1.0 + _range_error))
	var mg: MachineGunData = tank.get_active_mg(tank.can_use_roof_mg())
	if mg != null and mg.bullet != null:
		_mg_superelevation = Ballistics.superelevation_for_range(mg.bullet, range_m)


func _engage(target: Tank, delta: float) -> void:
	var muzzle: Transform3D = tank.get_muzzle_transform()
	var hull_seen: bool = bool(_hull_visible.get(target, false))
	var head_seen: bool = bool(_head_visible.get(target, false))
	var distance: float = muzzle.origin.distance_to(target.global_position)
	var use_mg: bool = head_seen and distance <= bot_data.mg_range_m
	var roof: bool = use_mg and tank.can_use_roof_mg()
	var coax_turn: bool = use_mg and not roof and not tank.is_loaded()

	# Main gun (or coax while reloading): the turret follows the chosen aim.
	var gun_aim: Vector3
	if coax_turn:
		gun_aim = _aim_point(target.get_commander_hitbox_position(), target,
				tank.get_coax_muzzle_transform().origin, _mg_superelevation,
				tank.get_active_mg(false).bullet)
	else:
		gun_aim = _aim_point(target.global_position + target.global_basis.y * 0.3, target,
				muzzle.origin, _gun_superelevation, tank.get_loaded_shell())
		gun_aim = _with_lay_error(gun_aim, muzzle.origin)
	_command.aim_point = gun_aim
	_command.has_aim = true

	# Short halt: stop for the shot only when it's ready and the hull is in sight.
	_halting = tank.is_loaded() and hull_seen and not coax_turn
	var still: bool = tank.linear_velocity.length() * 3.6 <= bot_data.max_fire_speed_kmh
	var gun_error: float = (-muzzle.basis.z).angle_to(gun_aim - muzzle.origin)
	if not coax_turn and hull_seen and still \
			and gun_error <= deg_to_rad(bot_data.aim_tolerance_deg):
		_settle_time += delta
	else:
		_settle_time = 0.0
	if _settle_time >= bot_data.aim_settle_s and tank.is_loaded():
		_command.fire = true
		_settle_time = 0.0
		_range_error *= bot_data.range_error_correction
		_lay_error *= bot_data.range_error_correction
		_lead_error *= bot_data.range_error_correction

	if not roof and not coax_turn:
		_mg_time = 0.0
		return
	var mg_muzzle: Transform3D = tank.get_roof_mg_muzzle_transform() if roof \
			else tank.get_coax_muzzle_transform()
	var mg_aim: Vector3 = gun_aim
	if roof:
		mg_aim = _aim_point(target.get_commander_hitbox_position(), target, mg_muzzle.origin,
				_mg_superelevation, tank.get_active_mg(true).bullet)
		_command.mg_aim_point = mg_aim
		_command.mg_use_roof = true
	var mg_error: float = (-mg_muzzle.basis.z).angle_to(mg_aim - mg_muzzle.origin)
	if mg_error > deg_to_rad(bot_data.mg_aim_tolerance_deg):
		return
	_mg_time += delta
	_command.fire_mg = fmod(_mg_time, bot_data.mg_burst_s + bot_data.mg_pause_s) \
			< bot_data.mg_burst_s


## Where to point a barrel at `from` to hit `point` on `target`: leads its motion over
## the flight time and raises the aim by `superelevation` (radians).
func _aim_point(point: Vector3, target: Tank, from: Vector3, superelevation: float,
		projectile: ShellData) -> Vector3:
	var speed: float = projectile.muzzle_velocity_mps if projectile != null else 500.0
	var flight_time: float = from.distance_to(point) / maxf(speed * 0.9, 1.0)
	var predicted: Vector3 = point + target.linear_velocity * (1.0 + _lead_error) * flight_time
	var horizontal: float = _horizontal_distance(from, predicted)
	return predicted + Vector3.UP * tan(superelevation) * horizontal


## Shifts `aim` sideways and up by the current laying error, as seen from `from`.
func _with_lay_error(aim: Vector3, from: Vector3) -> Vector3:
	var to_aim: Vector3 = aim - from
	var right: Vector3 = to_aim.cross(Vector3.UP).normalized()
	return aim + (right * _lay_error.x + Vector3.UP * _lay_error.y) * to_aim.length()


static func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


# --- Turret and hatch out of combat --------------------------------------------

## No target: point the turret where the last hit came from, else along the hull.
func _look_ahead_or_at_threat() -> void:
	var eye: Vector3 = tank.get_commander_eye_position()
	var direction: Vector3 = _alert_direction if _alert_timer > 0.0 else -tank.global_basis.z
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	_command.aim_point = eye + direction.normalized() * 200.0
	_command.has_aim = true


func _on_hit_taken(direction: Vector3) -> void:
	_hit_close_timer = bot_data.close_hatch_after_hit_s if bot_data != null else 0.0
	_alert_direction = -direction
	_alert_timer = ALERT_TIME_S
	contact.emit(null, tank.global_position - direction.normalized() * HIT_ORIGIN_GUESS_M)


## Stuck on an ordered route: go round via a point to the side, alternating sides.
func _on_stuck() -> void:
	if _order_index >= _orders.size():
		return
	var here: Vector3 = tank.global_position
	if _last_stuck_at != Vector3.INF and here.distance_to(_last_stuck_at) < REPEAT_STUCK_RADIUS_M:
		_stuck_repeats += 1
	else:
		_stuck_repeats = 0
	_last_stuck_at = here
	if _path_goal != Vector3.INF and _tactical_map() != null:
		# Remember what we hit (just ahead of us) and plan round it from now on.
		var forward: Vector3 = -tank.global_basis.z
		forward.y = 0.0
		var ahead: Vector2i = _tactical_map().grid.cell_of(tank.global_position
				+ forward.normalized() * AVOID_AHEAD_M)
		if not _avoid_cells.has(ahead):
			_avoid_cells.append(ahead)
			if _avoid_cells.size() > AVOID_MEMORY:
				_avoid_cells.remove_at(0)
		# On a planned path: plan again from here (after backing off). Stuck again at
		# the same place (another tank, something the grid doesn't know): step aside
		# first, then plan from there.
		var goal: Vector3 = _path_goal
		var detour: Array[Vector3] = []
		if _stuck_repeats > 0:
			detour.append(_detour_point(_orders[_order_index]))
		_orders = detour + _plan_path(goal)
		_order_index = 0
		return
	_orders.insert(_order_index, _detour_point(_orders[_order_index]))


## A point beside the way to `next` (alternating left and right each time).
func _detour_point(next: Vector3) -> Vector3:
	var to_next: Vector3 = next - tank.global_position
	to_next.y = 0.0
	var forward: Vector3 = to_next.normalized() if to_next.length() > 0.1 else -tank.global_basis.z
	var side: Vector3 = forward.cross(Vector3.UP) * _detour_side
	_detour_side = -_detour_side
	return tank.global_position + side * DETOUR_SIDE_M + forward * DETOUR_AHEAD_M


## One frame along the ordered route (with the base class' pivot turns and unsticking).
func _order_step(delta: float) -> void:
	if _order_index >= _orders.size():
		return
	if _update_scouting(delta):
		return
	if _reverse_time > 0.0:
		_reverse_time -= delta
		_command.throttle = -_order_throttle
		return
	if _steer_towards(_orders[_order_index], _order_throttle):
		_order_index += 1
		return
	_keep_gap(delta)
	_update_stuck(delta)


## Stops briefly at the next scouting point (hatch open when calm: same eyes as a
## player's). Skipped after recent contact: then the tank just crosses. True while
## stopped.
func _update_scouting(delta: float) -> bool:
	if _scout_wait > 0.0:
		_scout_wait -= delta
		_command.throttle = 0.0
		_command.steering = 0.0
		return _scout_wait > 0.0
	if _scout_points.is_empty():
		return false
	var to_point: Vector3 = _scout_points[0] - tank.global_position
	to_point.y = 0.0
	if to_point.length() > WAYPOINT_RADIUS:
		return false
	_scout_points.remove_at(0)
	if _since_contact < _tactics().scout_skip_after_contact_s:
		return false
	_scout_wait = _tactics().scout_time_s
	_command.throttle = 0.0
	return true


## Slows down behind a tank ahead on the way (no ramming teammates on a shared path);
## stopped behind it too long, steps round it.
func _keep_gap(delta: float) -> void:
	var forward: Vector3 = -tank.global_basis.z
	forward.y = 0.0
	var nearest: float = INF
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var other := node as Tank
		if other == null or other == tank or other.is_knocked_out():
			continue
		var to_other: Vector3 = other.global_position - tank.global_position
		to_other.y = 0.0
		var d: float = to_other.length()
		if d < FOLLOW_GAP_M and d > 0.1 \
				and forward.angle_to(to_other) < deg_to_rad(FOLLOW_CONE_DEG):
			nearest = minf(nearest, d)
	if nearest == INF:
		_yield_time = 0.0
		return
	_command.throttle *= clampf((nearest - FOLLOW_STOP_M) / (FOLLOW_GAP_M - FOLLOW_STOP_M), 0.0, 1.0)
	if _command.throttle > 0.05:
		_yield_time = 0.0
		return
	_yield_time += delta
	if _yield_time >= FOLLOW_PASS_S:
		_yield_time = 0.0
		_orders.insert(_order_index, _detour_point(_orders[_order_index]))


func _update_hatch(delta: float) -> void:
	_hit_close_timer = maxf(_hit_close_timer - delta, 0.0)
	var close_contact: bool = _target != null \
			and tank.global_position.distance_to(_target.global_position) \
			<= bot_data.close_hatch_within_m
	var threatened: bool = close_contact or _hit_close_timer > 0.0 \
			or tank.is_commander_wounded()
	if threatened:
		_needs_calm = true
	if threatened or _target != null:
		_calm_time = 0.0
	else:
		_calm_time += delta
		if _calm_time >= bot_data.reopen_calm_s:
			_needs_calm = false
	_command.hatch_open = bot_data.hatch_open_when_calm and not threatened and not _needs_calm
