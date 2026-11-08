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
## holding, a wide cone ahead when moving; enemies it makes out become marks for the
## team (Tank.report_squad_spot), again every mark_interval_s while in sight.
## Fighting (holding still only): rifle bursts at exposed commanders and enemy soldiers
## (low accuracy), AT rounds at tanks within at_range_m (they never knock a tank out).
## On the way to a position it halts for an enemy that comes within reach of its weapons
## and walks on when none is left (not for enemies it knew of when ordered, and not
## while withdrawing or recalled). Being shot at alone doesn't move it. Any hit puts a
## soldier down (one of them is "Wilhelm"), and with a man down it throws smoke and runs
## for cover or the tank, whichever is nearer. Mounted, the missing come back one by
## one; wiped out, a new squad is ready on the tank after wipe_cooldown_s. No friendly
## fire.
## Network: the host runs all this; on clients the squad is a puppet (net_puppet) shown
## from the host's state.

signal soldier_down(index: int, screamed: bool)
signal smoke_thrown(at: Vector3)
## A radio call to the own tank: RADIO_* kind and, for contacts, where the enemy is.
## Host/offline makes them; clients get them by RPC (net_radio).
signal radio(kind: int, at: Vector3)
## A round left a soldier's weapon (kind: SHOT_RIFLE / SHOT_AT), for the network.
signal fired_round(kind: int, from: Vector3, velocity: Vector3)
## Soldier `index` shoulders the AT launcher and aims at `point` (index -1: nobody
## aims any more), for the network.
signal at_aiming(index: int, point: Vector3)
## Host: a mine was laid (NetGame tells the clients).
signal mine_laid(mine: Mine)

enum State { MOUNTED, MOVING, HOLDING, RETURNING, WIPED }
const RADIO_UNDER_ATTACK: int = 0
const RADIO_RETURNING: int = 1
const RADIO_IN_POSITION: int = 2
const RADIO_ARMOUR: int = 3
const RADIO_INFANTRY: int = 4
## "Skott kommer! Klart bakåt!": an AT round is about to be fired.
const RADIO_AT_FIRE: int = 5
## "Avsittning!": the squad gets off the tank.
const RADIO_DISMOUNT: int = 6
## "Träff!" / "Miss!": how the AT round that was just fired landed.
const RADIO_AT_HIT: int = 7
const RADIO_AT_MISS: int = 8

## Orders in TankCommand.squad_order.
const ORDER_NONE: int = 0
const ORDER_MOVE: int = 1
const ORDER_RECALL: int = 2
## Walk to the point and lay a mine there (SquadData.mine).
const ORDER_MINE: int = 3
## The mine layer starts work this close to the spot (m), and lays it from this close.
const MINE_START_M: float = 15.0
const MINE_AT_M: float = 1.2
## A waypoint counts as reached this close (m).
const WAYPOINT_RADIUS_M: float = 3.0
## An AT round not landed this long after its expected flight time counts as a miss (s).
const AT_RESULT_MARGIN_S: float = 1.5
## Soldiers turn towards where they go this fast (radians/s).
const TURN_RATE: float = 4.0
## Re-plan the way back to a moving tank this often (s).
const RETURN_REPLAN_S: float = 3.0
## Points looked at on an enemy tank (above its origin, m).
const TANK_LOOK_HEIGHTS: Array[float] = [0.5, 1.9]
## Targets farther than the view range plus this (m) can't be seen at all, so their
## cover and sight lines aren't checked.
const VIEW_RANGE_MARGIN_M: float = 5.0
## Loaded at start, not preloaded: shell.gd refers back to Squad (a preload would cycle).
const SHELL_SCENE_PATH: String = "res://scenes/weapons/shell.tscn"
const LAUNCH_FLASH_SCENE: PackedScene = preload("res://scenes/effects/muzzle_flash.tscn")
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
const KNEEL_HITBOX_SHARE: float = 0.55
## Blocked ahead (too steep: a wall, a roof's edge), a soldier tries these turns off
## his way, towards his last good side first (degrees).
const DETOUR_ANGLES_DEG: Array[float] = [35.0, 70.0, 105.0]
## Slack on top of the climb limit for uneven ground within one step (m).
const CLIMB_SLACK_M: float = 0.05
## The squad's point re-plans its path after being blocked this long (s).
const BLOCKED_REPLAN_S: float = 1.5
## A man down, the way to cover is looked for at these shares of fallback_m and turns
## off straight away from the threat (degrees).
const COVER_RANGE_SHARES: Array[float] = [0.25, 0.5, 1.0]
const COVER_ANGLES_DEG: Array[float] = [0.0, 40.0, -40.0, 80.0, -80.0, 120.0, -120.0]
## Walls are looked for this high above the feet, this far beyond each step (m).
const WALL_CHECK_HEIGHT_M: float = 0.8
const WALL_CHECK_AHEAD_M: float = 0.3
## Walking, the ground is looked for from this high above the feet (below bridge decks).
const GROUND_PROBE_UP_M: float = 1.5
## Walking checks walls and ground only every few ticks: one probe covers this many
## ticks' worth of walking and the ticks after it move along the checked stretch
## (fewer rays; the stretch is a few dozen cm).
const PROBE_TICKS: int = 4
## A new probe comes early when the way the walker wants to go turns more than this.
const PROBE_KEEP_DEG: float = 20.0

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
## Per soldier: his model's AnimationPlayer (null for capsules) and what it plays.
var _players: Array[AnimationPlayer] = []
## Team look: [mesh instance, surface (-1 = whole mesh), friendly material] per uniform
## surface; [mesh instance, surface] painted blue on friends (helmets); and the TeamLook
## state they were last set for.
var _uniform_surfaces: Array = []
var _blue_surfaces: Array = []
var _look_version: int = -1
var _look_team: int = -2
## Per soldier: where he stood last frame (world), for his real speed (soldiers are
## children of the squad node, so they ride along when its point moves).
var _last_pos: Array[Vector3] = []
var _playing: Array[StringName] = []
const ANIM_LIBRARY: StringName = &"squad"
var _hitboxes: Array[SoldierHitbox] = []
var _alive: Array[bool] = []
var _down_time: Array[float] = []
var _wilhelm: int = 0
var _replan_timer: float = 0.0
var _map: TacticalMap
var _map_looked_up: bool = false
## Per soldier: 0 = standing, 1 = kneeling (eases between).
var _kneel: Array[float] = []
## Per soldier: his speed last frame (m/s), and how long he still shows after firing (s).
var _speed: Array[float] = []
var _revealed: Array[float] = []
## Per soldier: 0 = not lying, 1 = lying down (eases between).
var _prone: Array[float] = []
## Ambush: holding this long (s) the squad lies down; it holds fire beyond
## ambush_rifle_range_m until it has fired (sprung). Puppets get _lying from the host.
var _hold_time: float = 0.0
var _sprung: bool = false
var _lying: bool = false
# Mines: carried, laid (oldest first), where the ordered one goes (INF = none), the
# soldier laying it (-1) and his time left; refill on the tank; enemy mines looked at.
var _mines_carried: int = 0
var _laid: Array[Mine] = []
var _mine_goal: Vector3 = Vector3.INF
var _mine_layer: int = -1
var _lay_left: float = 0.0
var _mine_refill_timer: float = 0.0
var _mine_look: Dictionary = {}  # Mine -> seconds
var _net_mines_carried: int = 0
var _net_mines_out: int = 0
## Per soldier: his spot round the squad's point while holding (offset), his pace, his
## drift on the move (and its target).
var _spot: Array[Vector3] = []
var _pace: Array[float] = []
## Per soldier (and the squad's point, last): which way he went round something last
## (1 = left, -1 = right).
var _detour_side: Array[float] = [1.0]
## Per soldier (and the squad's point, last), like _detour_side: the end of the stretch
## checked by the last probe (INF = none), the way he wanted to go then, ticks left.
var _probe_end: Array[Vector3] = [Vector3.INF]
var _probe_dir: Array[Vector3] = [Vector3.ZERO]
var _probe_ticks: Array[int] = [0]
var _blocked_time: float = 0.0
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
## The AT gunner while he aims (-1 = none), his target and the time left to the shot.
var _at_gunner: int = -1
var _at_target: Tank
var _at_aim_left: float = 0.0
## Where the AT round goes: the target's track as last seen (INF: not yet seen).
var _at_aim_point: Vector3 = Vector3.INF
## The AT round in flight (its hit/miss call is still due) and the time left before it
## counts as a miss anyway.
var _at_shell: Shell
var _at_shell_left: float = 0.0
## Per soldier: where he aims the launcher (INF = he doesn't), how long he still holds
## it after the shot, his launcher and his rifle meshes (hidden while he has the tube).
var _aim_point: Array[Vector3] = []
var _launcher_hold: Array[float] = []
var _launchers: Array[Node3D] = []
var _rifles: Array = []
var _smoke_left: int = 0
var _withdraw_timer: float = 0.0
## Withdrawing: on the move to cover, no halts to fight.
var _retreating: bool = false
## Halted on the way to fight: where it was going (INF = no such halt), and how long it
## still waits with nothing in reach before walking on.
var _resume_goal: Vector3 = Vector3.INF
var _resume_wait: float = 0.0
## Enemies (Tank / Squad) in sight when the last move order came: the order was given
## knowing of them, so they don't stop the walk.
var _order_known: Dictionary = {}
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
	# Squads look round at different ticks: all at once makes one very slow frame.
	_scan_timer = _rng.randf() * data.scan_interval_s
	_at_left = data.at_rounds
	_smoke_left = data.smoke_grenades
	_mines_carried = data.mines_carried if data.mine != null else 0
	visible = false
	_set_hitboxes_active(false)
	if not net_puppet:
		_tactical_map()   # built now (half a second), not mid-match at the first order


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
func get_mines_carried() -> int:
	return _net_mines_carried if net_puppet else _mines_carried


## Its mines out in the field.
func get_mines_out() -> int:
	return _net_mines_out if net_puppet else _laid.size()


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
	var at: Vector3 = leader.get_global_transform_interpolated().origin if leader != null \
			else global_position
	var eye: Vector3 = at + Vector3.UP * _eye_height()
	var i: int = _first_alive()
	if leader != null and i >= 0 and _prone[i] > 0.0:
		# Lying, his head is ahead of his feet.
		var ahead: Vector3 = -leader.global_basis.z
		eye += _flat(ahead).normalized() * data.prone_eye_forward_m * _prone[i]
	return eye


## How many times longer than a soldier in plain view soldier `index` takes to make out
## from `viewer`, with the viewer's `conceal` rules (null: no cover rule): cover,
## movement, stance, uniform and distance. One who just fired shows (reveal_*).
## Multiply by data.soldier_spot_factor and the viewer's base spot time.
func soldier_spot_time_factor(index: int, viewer: Vector3, conceal: ConcealmentData) -> float:
	if _revealed[index] > 0.0:
		return data.reveal_spot_factor
	var factor: float = data.camo_spot_factor * Weather.current().spot_time_factor
	if conceal != null:
		# Cover as for tanks; still as for tanks, but a running man is no tank at speed.
		var cover: float = Concealment.cover(get_world_3d(), _hitboxes[index], conceal)
		factor *= 1.0 + cover * conceal.cover_spot_time_factor
		factor *= conceal.stationary_spot_time_factor if _speed[index] <= conceal.stationary_speed_mps \
				else data.moving_spot_factor
	if _prone[index] >= 0.5:
		factor *= data.prone_spot_factor
	elif _kneel[index] >= 0.5:
		factor *= data.kneel_spot_factor
	var beyond: float = viewer.distance_to(_soldiers[index].global_position) - data.soldier_easy_range_m
	if beyond > 0.0:
		factor *= 1.0 + beyond / 100.0 * data.soldier_spot_per_100m
	return factor


## Share of the viewer's range at which soldier `index` can be made out at all (cover).
func soldier_spot_range_factor(index: int, conceal: ConcealmentData) -> float:
	if conceal == null or _revealed[index] > 0.0:
		return 1.0
	return Concealment.range_factor(Concealment.cover(get_world_3d(), _hitboxes[index], conceal),
			conceal)


## The leader kneels or lies (lower eyes).
func is_kneeling() -> bool:
	var i: int = _first_alive()
	return i >= 0 and (_kneel[i] >= 0.5 or _prone[i] >= 0.5)


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
			_order_known.clear()
			for seen: Node3D in _targets_in_sight():
				_order_known[_enemy_of(seen)] = true
			_cancel_mine()
			_move_to(_clamp_to_tank(target))
		ORDER_MINE:
			if _mines_carried <= 0 or data.mine == null:
				return
			if _state == State.MOUNTED:
				if get_alive_count() == 0:
					return
				_dismount()
			_order_known.clear()
			for seen: Node3D in _targets_in_sight():
				_order_known[_enemy_of(seen)] = true
			_cancel_mine()
			_mine_goal = _clamp_to_tank(target)
			_mine_goal.y = _ground_height(_mine_goal, global_position.y, 200.0)
			_move_to(_mine_goal)
		ORDER_RECALL:
			if _state != State.MOUNTED:
				_cancel_mine()
				_start_return()


# --- Frame -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_instance_valid(tank):
		queue_free()
		return
	if _look_version != TeamLook.version or _look_team != get_team():
		_apply_look()
	if net_puppet:
		if is_out():
			global_position = global_position.lerp(_net_position, minf(delta * NET_FOLLOW_RATE, 1.0))
			_move_soldiers(delta)
		else:
			global_position = tank.global_position
		_update_bodies(delta)
		return
	_clock += delta
	for i: int in _revealed.size():
		_revealed[i] = maxf(_revealed[i] - delta, 0.0)
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
		_update_contact_halt(data.scan_interval_s)
	_update_at_aim(delta)
	_update_ambush(delta)
	if _state == State.HOLDING:
		_update_mine_laying(delta)
		_fight(delta)


## Automatic ambush: holding ambush_after_s the squad lies down and holds fire beyond
## ambush_rifle_range_m until it has fired or lost a man (sprung). Moving ends it.
func _update_ambush(delta: float) -> void:
	if _state == State.HOLDING:
		_hold_time += delta
	else:
		_hold_time = 0.0
		_sprung = false
	_lying = _state == State.HOLDING and _hold_time >= data.ambush_after_s


func is_lying() -> bool:
	return _lying


# --- Mines -------------------------------------------------------------------------

## At the ordered spot one soldier (the nearest) goes to it, kneels and lays the mine
## in mine_lay_time_s; then the squad holds there. A third mine out removes the oldest.
func _update_mine_laying(delta: float) -> void:
	if _mine_goal == Vector3.INF or _flat(_mine_goal - global_position).length() > MINE_START_M:
		return
	if _mine_layer < 0 or not _alive[_mine_layer]:
		_mine_layer = -1
		var best: float = INF
		for i: int in _soldiers.size():
			var d: float = _flat(_soldiers[i].global_position - _mine_goal).length()
			if _alive[i] and i != _at_gunner and d < best:
				best = d
				_mine_layer = i
		if _mine_layer < 0:
			return
		_lay_left = data.mine_lay_time_s
	_spot[_mine_layer] = _flat(_mine_goal - global_position)
	if _flat(_soldiers[_mine_layer].global_position - _mine_goal).length() > MINE_AT_M:
		return
	_lay_left -= delta
	if _lay_left > 0.0:
		return
	var at: Vector3 = _mine_goal
	at.y = _ground_height(_soldiers[_mine_layer].global_position, _soldiers[_mine_layer].global_position.y, 2.0)
	_mine_goal = Vector3.INF
	_mine_layer = -1
	_place_mine(at)


func _place_mine(at: Vector3) -> void:
	while _laid.size() >= data.max_mines_out:
		var oldest: Mine = _laid.pop_front()
		if is_instance_valid(oldest):
			oldest.remove()
	var mine: Mine = Mine.lay(get_parent(), data.mine, get_team(), at)
	_laid.append(mine)
	mine.gone.connect(func(_exploded: bool) -> void: _laid.erase(mine))
	_mines_carried -= 1
	mine_laid.emit(mine)


func _cancel_mine() -> void:
	_mine_goal = Vector3.INF
	_mine_layer = -1


func is_laying_mine(i: int) -> bool:
	return i == _mine_layer and _mine_goal != Vector3.INF


## Enemy mines near the leader, in sight: looked at a while, then marked for the team.
func _look_for_mines(eye: Vector3, dt: float) -> void:
	if _mine_look.size() > 32:
		_mine_look.clear()
	for node: Node in get_tree().get_nodes_in_group(Mine.GROUP):
		var mine := node as Mine
		if mine == null or mine.is_known_by(get_team()):
			continue
		if eye.distance_to(mine.global_position) > mine.data.spot_range_m \
				or not _sees_ground_point(eye, mine.global_position):
			_mine_look.erase(mine)
			continue
		var looked: float = float(_mine_look.get(mine, 0.0)) + dt
		if looked >= mine.data.spot_time_s:
			_mine_look.erase(mine)
			mine.mark_known(get_team())
		else:
			_mine_look[mine] = looked


## Nothing solid between `eye` and a point on the ground (bushes don't hide it this close).
func _sees_ground_point(eye: Vector3, point: Vector3) -> bool:
	var target: Vector3 = point + Vector3.UP * 0.1
	var query := PhysicsRayQueryParameters3D.create(eye, target)
	query.collision_mask = 1
	query.exclude = _own_rids()
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(target) < 0.6


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
	radio.emit(RADIO_DISMOUNT, Vector3.ZERO)


func _mount() -> void:
	_cancel_at_aim()
	_cancel_mine()
	for i: int in _aim_point.size():
		_launcher_hold[i] = 0.0
		_set_aim(i, Vector3.INF)
	_state = State.MOUNTED
	_path.clear()
	_resume_goal = Vector3.INF
	visible = false
	_set_hitboxes_active(false)
	_forget_all()


## `retreat`: withdrawing, so it doesn't halt to fight on the way.
func _move_to(target: Vector3, retreat: bool = false) -> void:
	_goal = target
	_path = _plan(target)
	_state = State.MOVING
	_retreating = retreat
	_resume_goal = Vector3.INF


func _start_return(announce: bool = true) -> void:
	if _state != State.RETURNING and announce:
		radio.emit(RADIO_RETURNING, Vector3.ZERO)
	_state = State.RETURNING
	_resume_goal = Vector3.INF
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
			radio.emit(RADIO_IN_POSITION, Vector3.ZERO)
		return
	var to_next: Vector3 = _flat(_path[0] - global_position)
	if to_next.length() <= WAYPOINT_RADIUS_M:
		_path.remove_at(0)
		return
	var dir: Vector3 = to_next.normalized()
	_heading = _heading.slerp(dir, minf(delta * TURN_RATE, 1.0)).normalized()
	var stride: float = data.run_speed_mps * delta
	var p: Vector3 = _probed_step(global_position, dir, minf(stride, to_next.length()),
			minf(stride * PROBE_TICKS, to_next.length()), _detour_side.size() - 1)
	if p == global_position and delta > 0.0:
		_blocked_time += delta
		if _blocked_time >= BLOCKED_REPLAN_S:
			_blocked_time = 0.0
			_path = _plan(_path[_path.size() - 1])
	else:
		_blocked_time = 0.0
	global_position = p


## This tick's `step` (m) from `from` towards `dir`, along a stretch checked by _step at
## most every PROBE_TICKS ticks. A probe checks `reach` (m, >= step) ahead. A new probe
## comes when the stretch is used up, the wanted way turns, or `from` is no longer on
## it (the walker was moved or his place came closer). `who`: index in _detour_side.
func _probed_step(from: Vector3, dir: Vector3, step: float, reach: float, who: int) -> Vector3:
	var end: Vector3 = _probe_end[who]
	var left: float = _flat(end - from).length() if end != Vector3.INF else 0.0
	var fresh: bool = end == Vector3.INF or _probe_ticks[who] <= 0 or left <= 0.001 \
			or left > reach + 0.05 or dir.dot(_probe_dir[who]) < cos(deg_to_rad(PROBE_KEEP_DEG))
	if fresh:
		end = _step(from, dir, reach, who)
		left = _flat(end - from).length()
		if left <= 0.001:
			_probe_end[who] = Vector3.INF
			return from   # blocked every way
		_probe_end[who] = end
		_probe_dir[who] = dir
		# A little random, so soldiers and squads don't all probe on the same tick.
		_probe_ticks[who] = PROBE_TICKS + _rng.randi_range(-1, 1)
	_probe_ticks[who] -= 1
	if left <= step:
		_probe_end[who] = Vector3.INF
		return end
	return from.lerp(end, step / left)


## Forgets the probed stretches (after the squad or its soldiers were put somewhere).
func _clear_probes() -> void:
	_probe_end.fill(Vector3.INF)


## One step of `length` from `from` along `dir` on the ground, no steeper uphill than
## SquadData.max_climb_deg. Blocked straight ahead, it tries turning off to the side
## that worked last (going round a house corner), then the other. Returns `from` if
## every way is blocked. `who`: index in _detour_side.
func _step(from: Vector3, dir: Vector3, length: float, who: int) -> Vector3:
	if length <= 0.0001:
		return from
	var climb: float = tan(deg_to_rad(data.max_climb_deg))
	var p: Vector3 = _try_step(from, dir, length, climb)
	if p != Vector3.INF:
		return p
	var side: float = _detour_side[who]
	for angle: float in DETOUR_ANGLES_DEG:
		for s: float in [side, -side]:
			p = _try_step(from, dir.rotated(Vector3.UP, deg_to_rad(angle) * s), length, climb)
			if p != Vector3.INF:
				_detour_side[who] = s
				return p
	return from


## Where a step lands, or Vector3.INF if a wall stands in the way (ray at knee height)
## or the ground rises steeper than `climb` (rise per metre). Ground is looked for from
## head height down, so bridge decks overhead don't count.
func _try_step(from: Vector3, dir: Vector3, length: float, climb: float) -> Vector3:
	var knee := Vector3.UP * WALL_CHECK_HEIGHT_M
	if _solid_between(from + knee, from + knee + dir * (length + WALL_CHECK_AHEAD_M)):
		return Vector3.INF
	var p: Vector3 = from + dir * length
	p.y = _ground_height(p, from.y, GROUND_PROBE_UP_M)
	if p.y - from.y > length * climb + CLIMB_SLACK_M:
		return Vector3.INF
	return p


## Something solid (a house wall, a stone, the ground) between two points; trees and
## tanks don't count.
func _solid_between(a: Vector3, b: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(a, b)
	query.collision_mask = 1
	var exclude: Array[RID] = []
	for i: int in 4:
		query.exclude = exclude
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider: Object = hit["collider"]
		if collider is TreeField or collider is Tank:
			exclude.append(hit["rid"])
			continue
		return true
	return false


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
		var pos: Vector3 = _last_pos[i]
		var to: Vector3 = _flat(target - pos)
		var stride: float = data.run_speed_mps * CATCH_UP_FACTOR * _pace[i] * delta
		var step: float = minf(to.length(), stride)
		if net_puppet:
			# The host already kept them off roofs: just follow its positions.
			if step > 0.001:
				pos += to.normalized() * step
			pos.y = _ground_height(pos, global_position.y)
		elif step > 0.001:
			# The probe reaches a full stretch ahead even when his place is close: places
			# move with the squad, so he keeps walking that way.
			pos = _probed_step(pos, to.normalized(), step, stride * PROBE_TICKS, i)
		var speed: float = _flat(pos - _last_pos[i]).length() / delta if delta > 0.0 else 0.0
		var walking: bool = speed > STANDING_SPEED
		_speed[i] = speed
		soldier.global_position = pos
		_last_pos[i] = pos
		var aiming: bool = _aim_point[i] != Vector3.INF and not walking
		var laying: bool = not walking and is_laying_mine(i)
		var facing: Vector3 = to.normalized() if walking else _flat(pos - global_position)
		if aiming:
			facing = _flat(_aim_point[i] - pos)
		if facing.length() < 0.1:
			facing = _heading
		soldier.look_at(pos + facing.normalized(), Vector3.UP)
		var was: bool = _kneel[i] >= 0.5
		var was_prone: bool = _prone[i] >= 0.5
		_kneel[i] = move_toward(_kneel[i], 0.0 if walking or aiming else 1.0,
				delta / maxf(data.stance_change_s, 0.01))
		_prone[i] = move_toward(_prone[i], 1.0 if _lying and not walking and not aiming
				and not laying else 0.0,
				delta / maxf(data.prone_change_s, 0.01))
		if (_kneel[i] >= 0.5) != was or (_prone[i] >= 0.5) != was_prone:
			_size_hitbox(i)
		if _players[i] != null:
			var anim: StringName = data.anim_move if walking \
					else (data.anim_at_aim if aiming
					else (data.anim_lay_mine if laying
					else (data.anim_prone if _prone[i] >= 0.5 else data.anim_hold)))
			_animate(i, anim, speed / maxf(data.anim_move_speed_mps, 0.1) if walking else 1.0)
		# Animated soldiers crouch by themselves; placeholders are squashed. Lying down the
		# body tips forward round his feet (no prone animation: a pose tipped over).
		var height_scale: float = 1.0 if _players[i] != null \
				else lerpf(1.0, data.kneel_height_share, _kneel[i] * (1.0 - _prone[i]))
		var tip := Basis(Vector3.RIGHT, -deg_to_rad(data.prone_pitch_deg) * _prone[i])
		_meshes[i].basis = tip * Basis(Vector3.UP, _body_yaw()) \
				* Basis.from_scale(_body_scale() * Vector3(1.0, height_scale, 1.0))
		_meshes[i].position = Vector3.UP * data.prone_lift_m * _prone[i] \
				+ tip * Vector3(0.0, _body_offset * height_scale, 0.0)


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
	_clear_probes()
	var side: Vector3 = _heading.cross(Vector3.UP).normalized()
	for i: int in _soldiers.size():
		if _alive[i]:
			var p: Vector3 = _place_of(i, true, side)
			p.y = _ground_height(p, global_position.y)
			_soldiers[i].global_position = p
			_last_pos[i] = p
			_kneel[i] = 0.0
			_prone[i] = 0.0
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
	var p: float = _prone[i] if i >= 0 else 0.0
	return lerpf(lerpf(data.eye_height_standing_m, data.eye_height_kneeling_m, k),
			data.eye_height_prone_m, p)


## Ground (terrain, a bridge deck...) under `p`; tree trunks and tanks don't count.
func _ground_height(p: Vector3, fallback: float, probe_up: float = 30.0) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + probe_up, p.z),
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
				_look(hb, eye, [[hb.get_aim_point(), hb]], enemy.data.soldier_spot_factor, dt,
						seen_now)
	_look_for_mines(eye, dt)
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
	if eye.distance_to(target.global_position) > Weather.view_range(data.view_range_m) \
			+ VIEW_RANGE_MARGIN_M:
		return   # cover only ever shortens the range
	var time_factor: float = 1.0
	var range_factor: float = 1.0
	var soldier := target as SoldierHitbox
	if soldier != null:
		time_factor = soldier.squad.soldier_spot_time_factor(soldier.index, eye, data.concealment)
		range_factor = soldier.squad.soldier_spot_range_factor(soldier.index, data.concealment)
	elif data.concealment != null:
		var cover: float
		if target is Tank:
			cover = Concealment.tank_cover(get_world_3d(), target as Tank, data.concealment)
			time_factor = Concealment.tank_spot_time_factor(target as Tank, cover,
					data.concealment)
		else:
			cover = Concealment.cover(get_world_3d(), target, data.concealment)
			time_factor = Concealment.spot_time_factor(cover, 0.0, data.concealment)
		range_factor = Concealment.range_factor(cover, data.concealment)
	if target is Tank:
		time_factor *= (target as Tank).data.camo_spot_factor
	var view_range: float = Weather.view_range(data.view_range_m) * range_factor
	var seen: int = 0
	for pair: Array in points:
		var p: Vector3 = pair[0]
		if eye.distance_to(p) > view_range or not _in_view_cone(p):
			continue
		if Vision.has_line_of_sight_through(get_world_3d(), eye, p, pair[1],
				_layers_seen_through(eye.distance_to(p)), _own_rids()):
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
	if not _spotted.has(target):
		radio.emit(RADIO_ARMOUR if target is Tank else RADIO_INFANTRY, target.global_position)
	_spotted[target] = true
	if not _marked_at.has(target) or _clock - float(_marked_at[target]) >= data.mark_interval_s:
		_marked_at[target] = _clock
		var enemy: Node3D = target if target is Tank else (target as SoldierHitbox).squad
		tank.report_squad_spot(enemy, target.global_position)


## How many vegetation layers the soldiers see through at `distance` (m).
func _layers_seen_through(distance: float) -> int:
	var layers: int = 0
	for k: int in data.see_through_ranges_m.size():
		if distance <= data.see_through_ranges_m[k]:
			layers = k + 1
	return layers


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
	_order_known.clear()


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

## The Tank or Squad behind a target (Tank / SoldierHitbox).
func _enemy_of(target: Node3D) -> Node3D:
	return (target as SoldierHitbox).squad if target is SoldierHitbox else target


## The squad's weapons can do something to `target` from here.
func _in_reach(target: Node3D) -> bool:
	if target is Tank and _at_left > 0 and data.at_round != null \
			and global_position.distance_to(target.global_position) <= data.at_range_m:
		return true
	var aim: Vector3 = _rifle_aim(target)
	return aim != Vector3.INF and global_position.distance_to(aim) <= data.rifle_range_m


## On the way to a position: halts when an enemy comes within reach (holding, it fights,
## spreads out and sees all round). Halted: walks on when none has been left a while.
func _update_contact_halt(dt: float) -> void:
	if _state == State.MOVING and _retreating:
		return
	if _state != State.MOVING and _resume_goal == Vector3.INF:
		return
	if tank.is_knocked_out():
		_resume_goal = Vector3.INF
		return
	var contact: bool = false
	for target: Node3D in _targets_in_sight():
		if not _order_known.has(_enemy_of(target)) and _in_reach(target):
			contact = true
			break
	if _state == State.MOVING:
		if contact:
			_resume_goal = _goal
			_resume_wait = data.contact_resume_s
			_path.clear()
			_state = State.HOLDING
	elif contact:
		_resume_wait = data.contact_resume_s
	else:
		_resume_wait -= dt
		if _resume_wait <= 0.0:
			_move_to(_resume_goal)


func _fight(delta: float) -> void:
	_at_timer = maxf(_at_timer - delta, 0.0)
	var targets: Array[Node3D] = _targets_in_sight()
	if targets.is_empty():
		return
	_try_at_round(targets)
	var rifle_target: Node3D = null
	var rifle_aim := Vector3.ZERO
	# In ambush the rifles wait for close targets (the AT round has its own short range).
	var rifle_range: float = data.ambush_rifle_range_m if _lying and not _sprung \
			else data.rifle_range_m
	for target: Node3D in targets:
		var aim: Vector3 = _rifle_aim(target)
		if aim != Vector3.INF and global_position.distance_to(aim) <= rifle_range:
			rifle_target = target
			rifle_aim = aim
			break
	for i: int in _soldiers.size():
		if not _alive[i] or i == _at_gunner or _launcher_hold[i] > 0.0:
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


## Picks a tank for an AT round: the gunner stands up, shoulders the launcher, calls
## "Skott kommer! Klart bakåt!" and fires at_aim_time_s later (_update_at_aim).
## Not while the last round is still in the air (its "Träff!"/"Miss!" comes first).
func _try_at_round(targets: Array[Node3D]) -> void:
	if _at_left <= 0 or _at_timer > 0.0 or data.at_round == null or _at_gunner >= 0 \
			or _at_shell != null:
		return
	for target: Node3D in targets:
		var other := target as Tank
		if other == null or global_position.distance_to(other.global_position) > data.at_range_m:
			continue
		var gunner: int = 1 if _soldiers.size() > 1 and _alive[1] else _first_alive()
		if gunner < 0:
			return
		_at_gunner = gunner
		_at_target = other
		_at_aim_left = data.at_aim_time_s
		_at_aim_point = _at_aim(other, _soldiers[gunner].global_position)
		_set_aim(gunner, other.global_position)
		radio.emit(RADIO_AT_FIRE, other.global_position)
		return


## The gunner follows his target and fires when the aim time is up. Once he has called
## "Skott kommer!" the round always goes: out of sight he fires at where he last saw
## the track, and if the squad has to move (or withdraw) he fires at once. Only his fall
## or the target's knock-out stops it (the round kept). Then he reports the result.
func _update_at_aim(delta: float) -> void:
	for i: int in _launcher_hold.size():
		if _launcher_hold[i] > 0.0:
			_launcher_hold[i] -= delta
			if _launcher_hold[i] <= 0.0 and i != _at_gunner:
				_set_aim(i, Vector3.INF)
	if _at_shell != null:
		_at_shell_left -= delta
		if _at_shell_left <= 0.0:
			_on_at_round_done([] as Array[Tank], _at_shell)
	if _at_gunner < 0:
		return
	var i: int = _at_gunner
	var other: Tank = _at_target
	if not _alive[i] or not is_instance_valid(other) or other.is_knocked_out():
		_cancel_at_aim()
		return
	var seen: bool = _in_sight.has(other)
	if seen:
		_at_aim_point = _at_aim(other, _soldiers[i].global_position)
	_set_aim(i, _at_aim_point)
	_at_aim_left -= delta
	if _at_aim_left > 0.0 and _state == State.HOLDING:
		return
	var spread: float = data.at_dispersion_mrad
	if other.linear_velocity.length() * 3.6 > data.at_fast_target_kmh:
		spread *= data.at_moving_factor
	var shell: Shell = _fire(i, data.at_round, _at_aim_point, other if seen else null, spread,
			data.at_sound)
	_at_shell = shell
	_at_shell_left = _soldiers[i].global_position.distance_to(_at_aim_point) \
			/ maxf(data.at_round.muzzle_velocity_mps, 1.0) + AT_RESULT_MARGIN_S
	shell.finished.connect(_on_at_round_done.bind(shell))
	_at_left -= 1
	_at_timer = data.at_interval_s
	_at_gunner = -1
	_at_target = null
	_launcher_hold[i] = data.at_hold_after_s


## The AT round `shell` landed (or flew on too long): "Träff!" if it struck a tank.
func _on_at_round_done(struck: Array[Tank], shell: Shell) -> void:
	if shell != _at_shell:
		return
	_at_shell = null
	if _first_alive() >= 0:
		radio.emit(RADIO_AT_MISS if struck.is_empty() else RADIO_AT_HIT, Vector3.ZERO)


func _cancel_at_aim() -> void:
	if _at_gunner >= 0:
		_set_aim(_at_gunner, Vector3.INF)
		# No new aim (and call) at once: nobody else had shouldered it.
		_at_timer = maxf(_at_timer, data.at_interval_s * 0.5)
	_at_gunner = -1
	_at_target = null


## Soldier `i` aims the launcher at `point` (INF: puts it away).
func _set_aim(i: int, point: Vector3) -> void:
	var was: bool = _aim_point[i] != Vector3.INF
	_aim_point[i] = point
	var on: bool = point != Vector3.INF
	_launchers[i].visible = on
	for rifle: Node3D in _rifles[i]:
		rifle.visible = not on
	if on != was and not net_puppet:
		at_aiming.emit(i if on else -1, point if on else Vector3.ZERO)


## Back blast and muzzle flash at both ends of soldier `i`'s launcher.
func _launcher_blast(i: int) -> void:
	var tube: Node3D = _launchers[i]
	if not tube.is_inside_tree():
		return
	var half: float = data.at_launcher_length_m * 0.5
	for end: float in [-half, half]:
		var flash: Node3D = LAUNCH_FLASH_SCENE.instantiate()
		get_parent().add_child(flash)
		flash.global_position = tube.to_global(Vector3(0.0, end, 0.0))
		flash.scale = Vector3.ONE * (0.6 if end < 0.0 else 0.4)


## AT rounds go for the tracks: the middle of the track on the side facing the
## shooter (a thrown track holds the tank for its repair). Without a track module,
## the hull.
func _at_aim(other: Tank, from: Vector3) -> Vector3:
	var best := Vector3.INF
	if other.data.layout != null:
		for m: ModuleData in other.data.layout.modules:
			if m.frame != &"hull" or not (m.id == &"track_left" or m.id == &"track_right"):
				continue
			var outer: Vector3 = m.center + Vector3(signf(m.center.x) * m.size.x * 0.5, 0.0, 0.0)
			var p: Vector3 = other.to_global(outer)
			if best == Vector3.INF or from.distance_to(p) < from.distance_to(best):
				best = p
	return best if best != Vector3.INF else other.global_position + Vector3.UP * 0.6


## One round from soldier `i` at `aim` (led for a moving tank), with random spread.
func _fire(i: int, shell_data: ShellData, aim: Vector3, target: Node3D, spread_mrad: float,
		sound: SoundSetData) -> Shell:
	_sprung = true
	var from: Vector3 = _eye_of(i)
	if shell_data == data.at_round and _launchers[i].visible and _launchers[i].is_inside_tree():
		from = _launchers[i].to_global(Vector3(0.0, data.at_launcher_length_m * 0.5, 0.0))
		_launcher_blast(i)
	var moving: Tank = target as Tank
	if moving != null:
		var flight: float = from.distance_to(aim) / maxf(shell_data.muzzle_velocity_mps, 1.0)
		aim += moving.linear_velocity * flight
	var dir: Vector3 = (aim - from).normalized()
	var side: Vector3 = dir.cross(Vector3.UP).normalized()
	# Held a little high for the drop over the range (soldiers know their weapons).
	dir = dir.rotated(side, Ballistics.superelevation_for_range(shell_data, _flat(aim - from).length()))
	var up: Vector3 = side.cross(dir).normalized()
	var r: float = sqrt(_rng.randf()) * spread_mrad * 0.001
	var a: float = _rng.randf() * TAU
	dir = (dir + side * cos(a) * r + up * sin(a) * r).normalized()
	var shell := _shell_scene.instantiate() as Shell
	get_parent().add_child(shell)
	shell.launch(shell_data, from, dir * shell_data.muzzle_velocity_mps, _hitboxes[i])
	SoundFx.play_at(self, sound, from)
	_revealed[i] = maxf(_revealed[i], data.reveal_at_s if shell_data == data.at_round
			else data.reveal_rifle_s)
	fired_round.emit(SHOT_AT if shell_data == data.at_round else SHOT_RIFLE, from,
			dir * shell_data.muzzle_velocity_mps)
	return shell


## Soldier `i`'s eyes (and muzzle): standing, kneeling or lying (head ahead of his feet).
func _eye_of(i: int) -> Vector3:
	var soldier: Node3D = _soldiers[i]
	var h: float = lerpf(lerpf(data.eye_height_standing_m, data.eye_height_kneeling_m, _kneel[i]),
			data.eye_height_prone_m, _prone[i])
	return soldier.global_position + Vector3.UP * h \
			+ _flat(-soldier.global_basis.z).normalized() * data.prone_eye_forward_m * _prone[i]


func _first_alive() -> int:
	for i: int in _alive.size():
		if _alive[i]:
			return i
	return -1


# --- Being hit ---------------------------------------------------------------------

## A shell, bullet or fragment hit soldier `index`: he goes down.
func soldier_hit(index: int) -> HitResult:
	if net_puppet or not is_soldier_exposed(index):
		return null
	var screamed: bool = index == _wilhelm and _rng.randf() < data.scream_chance
	_sprung = true
	_put_down(index, screamed)
	var result := HitResult.new()
	result.note = "SOLDIER DOWN"
	if get_alive_count() == 0:
		_wipe()
	else:
		_withdraw()
	return result


## Soldier `index` falls (host or, from the host's news, a client).
func _put_down(index: int, screamed: bool) -> void:
	_alive[index] = false
	if index == _at_gunner:
		_cancel_at_aim()
	_launcher_hold[index] = 0.0
	_set_aim(index, Vector3.INF)
	_down_time[index] = 0.0
	_hitboxes[index].set_active(false)
	if _players[index] != null:
		_animate(index, data.anim_death, 1.0)
	else:
		_meshes[index].rotation = Vector3(deg_to_rad(90.0), _body_yaw(), 0.0)
		_meshes[index].position = Vector3(0.0, data.soldier_radius_m, 0.0)
	if screamed:
		SoundFx.play_at(self, data.scream_sound, _soldiers[index].global_position + Vector3.UP)
	soldier_down.emit(index, screamed)


## A man down: smoke towards the threat, then run for cover, or to the tank if that is
## nearer or there is no cover.
func _withdraw() -> void:
	if _withdraw_timer > 0.0 or not is_instance_valid(tank):
		return
	_withdraw_timer = data.withdraw_cooldown_s
	radio.emit(RADIO_UNDER_ATTACK, Vector3.ZERO)
	var threat: Vector3 = _threat_direction()
	if _smoke_left > 0:
		_smoke_left -= 1
		throw_smoke(global_position + threat * data.smoke_ahead_m)
	if _state == State.RETURNING or tank.is_knocked_out():
		return
	_cancel_mine()
	var cover: Vector3 = _find_cover(threat)
	var to_tank: float = _flat(tank.global_position - global_position).length()
	if cover == Vector3.INF or to_tank <= _flat(cover - global_position).length():
		_start_return(false)
	else:
		_move_to(cover, true)


## Towards the nearest enemy in sight, else away from the own tank.
func _threat_direction() -> Vector3:
	var targets: Array[Node3D] = _targets_in_sight()
	if not targets.is_empty():
		var to_enemy: Vector3 = _flat(targets[0].global_position - global_position)
		if to_enemy.length() > 1.0:
			return to_enemy.normalized()
	var away: Vector3 = _flat(global_position - tank.global_position)
	return away.normalized() if away.length() > 1.0 else _heading


## The nearest covered spot within fallback_m, away from `threat` and not past the
## squad's leash; INF if none.
func _find_cover(threat: Vector3) -> Vector3:
	var map: TacticalMap = _tactical_map()
	if map == null:
		return Vector3.INF
	for share: float in COVER_RANGE_SHARES:
		for angle: float in COVER_ANGLES_DEG:
			var p: Vector3 = global_position \
					- threat.rotated(Vector3.UP, deg_to_rad(angle)) * data.fallback_m * share
			if not map.is_blocked(p) and map.is_covered(p) \
					and _flat(p - tank.global_position).length() <= data.max_distance_from_tank_m:
				return p
	return Vector3.INF


func throw_smoke(at: Vector3) -> void:
	var cloud := SmokeCloud.new()
	cloud.radius_m = data.smoke_radius_m
	cloud.height_m = data.smoke_height_m
	cloud.lifetime_s = data.smoke_lifetime_s
	get_parent().add_child(cloud)
	cloud.global_position = Vector3(at.x, _ground_height(at, global_position.y), at.z)
	smoke_thrown.emit(cloud.global_position)


func _wipe() -> void:
	_state = State.WIPED
	_wipe_timer = 0.0
	_path.clear()
	_forget_all()


## Fallen soldiers stay where they fell (the squad's point moves on) while they drop,
## then vanish after body_time_s.
func _update_bodies(delta: float) -> void:
	for i: int in _soldiers.size():
		if not _alive[i] and _soldiers[i].visible:
			_down_time[i] += delta
			_soldiers[i].global_position = _last_pos[i]
			if _down_time[i] >= data.body_time_s:
				_soldiers[i].visible = false


# --- Refilling ---------------------------------------------------------------------

## On the tank: the missing come back one at a time; full again, ammo and smoke too.
func _refill(delta: float) -> void:
	if data.mine != null and _mines_carried < data.mines_carried:
		_mine_refill_timer += delta
		if _mine_refill_timer >= data.mine_refill_s:
			_mine_refill_timer = 0.0
			_mines_carried += 1
	if get_alive_count() >= data.soldier_count:
		_at_left = data.at_rounds
		_smoke_left = data.smoke_grenades
		_refill_timer = 0.0
		return
	_refill_timer += delta
	if _refill_timer >= data.refill_time_s:
		_refill_timer = 0.0
		_alive[_alive.find(false)] = true


## The tank respawned: the squad is full and on it again, wherever it was.
func restore_on_tank() -> void:
	if net_puppet:
		return
	_cancel_at_aim()
	_path.clear()
	_withdraw_timer = 0.0
	_refill_timer = 0.0
	_wipe_timer = 0.0
	for i: int in _soldiers.size():
		_soldiers[i].visible = false
	_restore_full()


func _restore_full() -> void:
	for i: int in _alive.size():
		_alive[i] = true
		_revealed[i] = 0.0
		_prone[i] = 0.0
	_at_left = data.at_rounds
	_smoke_left = data.smoke_grenades
	_mines_carried = data.mines_carried if data.mine != null else 0
	_mine_refill_timer = 0.0
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
	# Flags: bit 0 lying in ambush (they kneel by themselves), bits 1-2 mines carried,
	# bits 3-5 mines out.
	buf.put_u8((1 if _lying else 0) | (mini(_mines_carried, 3) << 1) | (mini(_laid.size(), 7) << 3))
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
	var flags: int = buf.get_u8()
	_lying = flags & 1 == 1
	_net_mines_carried = (flags >> 1) & 3
	_net_mines_out = (flags >> 3) & 7
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


## Client: the host's soldier `index` aims the launcher at `point` (-1: nobody).
func net_at_aiming(index: int, point: Vector3) -> void:
	for i: int in _aim_point.size():
		if i != index and _aim_point[i] != Vector3.INF:
			_set_aim(i, Vector3.INF)
	if index >= 0 and index < _aim_point.size() and _alive[index]:
		_set_aim(index, point)


## Client: a round the host's squad fired, shown here without effect.
func net_show_shot(kind: int, from: Vector3, velocity: Vector3) -> void:
	if kind == SHOT_AT:
		for i: int in _aim_point.size():
			if _aim_point[i] != Vector3.INF:
				_launcher_blast(i)
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
	var player: AnimationPlayer = null
	if data.model != null and data.model_animations != null:
		var found: Array[Node] = mesh.find_children("*", "AnimationPlayer", true, false)
		if not found.is_empty():
			player = found[0]
			player.add_animation_library(ANIM_LIBRARY, data.model_animations)
	_players.append(player)
	_last_pos.append(Vector3.ZERO)
	_playing.append(&"")
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
	_speed.append(0.0)
	_revealed.append(0.0)
	_prone.append(0.0)
	_spot.append(Vector3.ZERO)
	_pace.append(_rng.randf_range(0.9, 1.1))
	_detour_side.insert(_detour_side.size() - 1, 1.0 if _rng.randf() < 0.5 else -1.0)
	_probe_end.insert(_probe_end.size() - 1, Vector3.INF)
	_probe_dir.insert(_probe_dir.size() - 1, Vector3.ZERO)
	_probe_ticks.insert(_probe_ticks.size() - 1, 0)
	_drift.append(Vector3.ZERO)
	_drift_target.append(Vector3.ZERO)
	_burst_timer.append(_rng.randf_range(0.0, data.rifle_burst_interval_s))
	_burst_left.append(0)
	_aim_point.append(Vector3.INF)
	_launcher_hold.append(0.0)
	_launchers.append(_make_launcher(root))
	var rifles: Array[Node3D] = []
	if data.rifle_mesh_pattern != "":
		for node: Node in mesh.find_children(data.rifle_mesh_pattern, "MeshInstance3D", true, false):
			rifles.append(node as Node3D)
	_rifles.append(rifles)
	_shot_timer.append(0.0)
	_size_hitbox(i)


## The AT launcher: a plain tube on the right shoulder (hidden until he aims).
func _make_launcher(root: Node3D) -> Node3D:
	var tube := MeshInstance3D.new()
	tube.name = "Launcher"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = data.at_launcher_radius_m
	cylinder.bottom_radius = data.at_launcher_radius_m
	cylinder.height = data.at_launcher_length_m
	cylinder.radial_segments = 10
	cylinder.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = data.at_launcher_color
	material.roughness = 0.8
	cylinder.material = material
	tube.mesh = cylinder
	# The cylinder runs along its Y: tipped forward so +Y points along -Z (the
	# soldier's forward): +Y is the muzzle, -Y the back blast end.
	tube.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	tube.position = data.at_launcher_offset
	tube.visible = false
	root.add_child(tube)
	return tube


## Friend or foe as seen by this machine's player (TeamLook): friends wear the
## uniform colour and a UN-blue helmet, enemies a camouflage uniform.
func _apply_look() -> void:
	_look_version = TeamLook.version
	_look_team = get_team()
	var friend: bool = TeamLook.is_friend(_look_team)
	var camo: Material = TeamLook.camo(data.camo_pattern_per_m * (data.model_scale if data.model != null else 1.0))
	for entry: Array in _uniform_surfaces:
		var mi: MeshInstance3D = entry[0]
		if not is_instance_valid(mi):
			continue
		if entry[1] < 0:
			mi.material_override = entry[2] if friend else camo
		else:
			mi.set_surface_override_material(entry[1], entry[2] if friend else camo)
	for entry: Array in _blue_surfaces:
		var mi: MeshInstance3D = entry[0]
		if is_instance_valid(mi):
			mi.set_surface_override_material(entry[1], TeamLook.blue() if friend else null)


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
		_uniform_surfaces.append([mesh, -1, material])
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
				_uniform_surfaces.append([mi, s, paint])
			elif data.friend_blue_materials.has(mat.resource_name if mat != null else ""):
				_blue_surfaces.append([mi, s])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if data.model_animation != &"" and data.model_animations == null:
		for node: Node in body.find_children("*", "AnimationPlayer", true, false):
			var player := node as AnimationPlayer
			if player.has_animation(data.model_animation):
				player.play(data.model_animation)
	return body


## Plays `anim` (from the squad library) on soldier `i`, blending, unless it already is.
func _animate(i: int, anim: StringName, speed: float) -> void:
	var player: AnimationPlayer = _players[i]
	var full := StringName("%s/%s" % [ANIM_LIBRARY, anim])
	if _playing[i] != anim:
		_playing[i] = anim
		if player.has_animation(full):
			player.play(full, data.anim_blend_s)
	player.speed_scale = clampf(speed, 0.5, 2.0)


func _body_scale() -> Vector3:
	return Vector3.ONE * (data.model_scale if data.model != null else 1.0)


func _body_yaw() -> float:
	return deg_to_rad(data.model_yaw_deg) if data.model != null else 0.0


## Soldier `i`'s hitbox: shorter while he kneels, flat along the ground when he lies.
func _size_hitbox(i: int) -> void:
	if _prone[i] >= 0.5:
		_hitboxes[i].set_lying(data.soldier_height_m, data.prone_height_m * 0.5)
		return
	var h: float = data.soldier_height_m * (KNEEL_HITBOX_SHARE if _kneel[i] >= 0.5 else 1.0)
	_hitboxes[i].set_size(h, data.soldier_radius_m)


func _set_hitboxes_active(on: bool) -> void:
	for i: int in _hitboxes.size():
		_hitboxes[i].set_active(on and _alive[i])


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
