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

## Smoke screens (request_screen): fired when the turret bears within this of the
## point (deg), given up after this long (s); the last this many salvos are kept.
const SCREEN_BEAR_DEG: float = 25.0
const SCREEN_MAX_WAIT_S: float = 4.0
const SCREEN_KEEP_SALVOS: int = 1
## Points on an enemy tank (its local space) that the commander tries to see: hull
## centre, turret top, front and rear of the hull. The more show, the faster he spots it.
## Spotting time is divided by the share of points in sight, but never by less than this.
const MIN_SHOWN_SHARE: float = 0.2
## Targets farther than the view range plus this (m; spot points sit off the tank's
## origin) can't be seen at all, so their cover and sight lines aren't checked.
const VIEW_RANGE_MARGIN_M: float = 10.0
## A shot from about this far away is assumed when guessing where a hit came from (m).
const HIT_ORIGIN_GUESS_M: float = 300.0
## How long the turret looks towards a reported or felt threat (s).
const ALERT_TIME_S: float = 10.0
## Stuck on an ordered route: try a point this far to the side (and a bit ahead) (m).
const DETOUR_SIDE_M: float = 25.0
const DETOUR_AHEAD_M: float = 10.0
## Infantry: the bot thinks about its squad this often (s)...
const SQUAD_THINK_S: float = 3.0
## How often the crew thinks about which round to load (s).
const AMMO_THINK_S: float = 2.0
## A target's face counts as its front within this of straight ahead (deg), its rear
## within this of straight behind; between is its side (ammo choice).
const FRONT_ASPECT_DEG: float = 40.0
## An enemy whose gun points within this of us is laying on us (deg)...
const LAID_ON_DEG: float = 12.0
## ...within this range a role that avoids front duels slips away, at most this often (m, s).
const DODGE_RANGE_M: float = 900.0
const DODGE_COOLDOWN_S: float = 12.0
const REAR_ASPECT_DEG: float = 40.0
## Squads are shelled with HE within this (m).
const HE_SQUAD_RANGE_M: float = 800.0
## A known enemy mine within this (m) makes a bot on a planned path plan again.
const MINE_REPLAN_M: float = 250.0
## ...sends it to look about this far ahead / towards a threat (m)...
const SQUAD_LOOK_AHEAD_M: float = 150.0
## Enemy squads farther than this (m), other than the one being fought, are looked at
## every 2nd scan (the time in between counts towards spotting, as for far tanks).
const SQUAD_LOOK_EVERY_2ND_M: float = 150.0
## ...moves it on once the look point has moved this far (m)...
const SQUAD_MOVE_ON_M: float = 80.0
## ...and calls it back when the tank is this far from it (m), or has been driving on
## for SQUAD_RECALL_DRIVE_S (the squad rides along rather than run behind).
const SQUAD_RECALL_DISTANCE_M: float = 230.0
const SQUAD_RECALL_DRIVE_S: float = 5.0
## Faster than this counts as driving on (m/s).
const SQUAD_DRIVE_SPEED: float = 3.0
## The squad only goes out near the fight: a known enemy within this (m)...
const SQUAD_FIGHT_RANGE_M: float = 600.0
## ...(known within this long, s), an alert, or the fight focus (KothBots: the zone)
## within SQUAD_FOCUS_RANGE_M of the tank...
const SQUAD_ENEMY_MAX_AGE_S: float = 60.0
const SQUAD_FOCUS_RANGE_M: float = 450.0
## ...only once the tank has stood its role's squad_stand_s (not for short halts), and
## not again this soon after it was called back (s; times the role's share).
const SQUAD_RESEND_COOLDOWN_S: float = 45.0
## Bots whose tank has no BotRoleData play as this.
const DEFAULT_ROLE_PATH: String = "res://data/bots/roles/brawler.tres"
static var _default_role: BotRoleData
## Shoot and scoot: hidden backing out of sight, or returning to fire.
enum Scoot { NONE, HIDING, RETURNING }
## Hide spot candidates: angles off straight back from the target (degrees).
const HIDE_ANGLES_DEG: Array[float] = [0.0, 30.0, -30.0, 60.0, -60.0]
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
var _marked_at: Dictionary = {}  # Tank -> _clock when last marked for the team
var _cover: Dictionary = {}  # Tank -> cover at the last look
var _look_wait: Dictionary = {}  # Tank -> scans since it was last looked at (far tanks)
var _unseen_time: Dictionary = {}  # Tank -> seconds since last seen
var _hull_visible: Dictionary = {}  # Tank -> hull seen in the last scan
var _head_visible: Dictionary = {}  # Tank -> exposed commander seen in the last scan
## Tank -> clock time its commander may be fired on (seen since, plus a reaction time).
var _head_ready_at: Dictionary = {}
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
## Firing on the move: the way the extra laying error points (unit, picked per shot).
var _move_error_dir: Vector2 = Vector2.RIGHT
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
var _squad_think: float = 0.0
var _squad_look: Vector3 = Vector3.INF
var _driving_time: float = 0.0
var _standing_time: float = 0.0
## Seconds since the squad was last called back (INF = never).
var _since_squad_recall: float = INF
## Stuck for good: where the tank last made progress and how long it has tried since.
var _progress_at: Vector3 = Vector3.INF
var _no_progress_s: float = 0.0
## A smoke salvo wanted at the next physics frame (decided in a signal handler).
var _smoke_pending: bool = false
## A smoke screen asked for by the director (request_screen): towards this point, as
## soon as the turret bears on it; given up after SCREEN_MAX_WAIT_S. INF: none.
var _screen_at: Vector3 = Vector3.INF
var _screen_wait: float = 0.0
## Where the fighting is for this bot's squad (KothBots sets the zone); INF = none.
var fight_focus: Vector3 = Vector3.INF
## A role given for now instead of the tank's favourite (null: the favourite).
var role_override: BotRoleData
## The mode's limit on where the bot may go (Vector3 -> Vector3, e.g. ThunderRoad's
## corridor): every goal it drives to, ordered or its own (dash, relocation, hiding),
## goes through it. Empty: anywhere on the map.
var keep_goal: Callable
## Hit and run (BotRoleData.hit_and_run): rounds fired from this spot; when an enemy
## laying its gun on us last made us slip away.
var _visit_shots: int = 0
var _dodged_at: float = -INF
## A squad order from outside (a game mode's bot director), sent in the bot's next frame.
var _pending_squad_order: int = 0
var _pending_squad_target: Vector3 = Vector3.ZERO
## Enemy squads: seconds looked at, and the one being fired on.
var _squad_awareness: Dictionary = {}  # Squad -> seconds
## Squads beyond SQUAD_LOOK_EVERY_2ND_M: scans since the last look, and whether that look
## found it a target (spotted, in MG range), so it stays one in between.
var _squad_look_wait: Dictionary = {}  # Squad -> int
var _squad_ok: Dictionary = {}  # Squad -> bool
var _squad_target: Squad
var _scoot: Scoot = Scoot.NONE
var _scoot_point: Vector3 = Vector3.ZERO
var _peek_point: Vector3 = Vector3.ZERO
var _scoot_time: float = 0.0
## Recent gun rounds that hit or nearly missed: times (_clock).
var _hits: Array[float] = []
## Pulling back: true from the order until relocate_hold_s after arriving.
var _relocating: bool = false
## An order_path waiting for planning time ([goal, throttle, urgent, via]; TacticalMap.may_plan).
var _pending_plan: Array = []
# Close fight (TacticsData.close_fight_*): charging round a near enemy's flank.
var _close_fight: bool = false
# Ammo choice (_choose_ammo): seconds to the next look.
var _ammo_think: float = 0.0
var _relocate_hold: float = 0.0
var _clock: float = 0.0
## Grid cells where this tank got stuck on something (newest last).
var _avoid_cells: Array[Vector2i] = []
## Mine.version when the bot last looked at known enemy mines (re-plans on a change).
var _mine_version: int = -1
## Seconds since the last contact (enemy seen, reported or a hit).
var _since_contact: float = INF
## Enemies reported by the group: spotted in half the time (the crew knows where to look).
var _reported: Dictionary = {}
## Where enemies were last seen or reported: Tank -> [position, _clock then]. Kept
## after a target is forgotten, so the crew can go after it (KothBots hunting).
var _last_known: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	if bot_data != null and unstick_after_s <= 0.0:
		unstick_after_s = bot_data.unstick_after_s
		unstick_reverse_s = bot_data.unstick_reverse_s
	if bot_data != null:
		# Bots look round at different ticks: all at once makes one very slow frame.
		_scan_timer = _rng.randf() * bot_data.scan_interval_s
	if tank != null:
		tank.hit_taken.connect(_on_hit_taken)
		tank.fired.connect(_on_fired)
		tank.shell_threat.connect(_on_shell_threat)
		tank.squad_contact.connect(_on_squad_contact)
		tank.optics_dirtied.connect(func(_amount: float) -> void: _settle_time = 0.0)


## The enemy tank this bot is engaging, or null.
func get_target() -> Tank:
	return _target


func is_spotted(other: Tank) -> bool:
	return _spotted.has(other)


## Cover around `other` at the last look (0..1), for tests and debugging.
func get_cover_of(other: Tank) -> float:
	return float(_cover.get(other, 0.0))


## Drives `points` in order once, at `throttle`, then stops. Replaces the patrol.
## How this bot uses its tank now: a role it was given (set_role, e.g. by a team's
## commander), else its tank's favourite (the chassis' BotRoleData; none: a brawler).
func get_role() -> BotRoleData:
	if role_override != null:
		return role_override
	if tank != null and tank.data != null and tank.data.bot_role != null:
		return tank.data.bot_role
	if _default_role == null:
		_default_role = load(DEFAULT_ROLE_PATH) as BotRoleData
		if _default_role == null:
			_default_role = BotRoleData.new()
	return _default_role


func order_move(points: Array[Vector3], throttle: float) -> void:
	_pending_plan = []
	_orders = points.duplicate()
	_order_index = 0
	_order_throttle = throttle
	_path_goal = Vector3.INF


## Drives to `goal` along a path round houses, water and steep ground (the map's
## tactical grid), then stops. Without a baked grid: straight there, as order_move.
## `urgent` = no scouting stops on the way (the zone is closing, back from a respawn...).
## `via` = go by this point first (a flank, so not every bot takes the same way).
func order_path(goal: Vector3, throttle: float, urgent: bool = false,
		via: Vector3 = Vector3.INF) -> void:
	if _tactical_map() != null and not TacticalMap.may_plan():
		# This tick's planning time is used up (several bots ordered at once): plan in a
		# later tick, standing meanwhile; counts as orders, so directors don't re-order.
		_pending_plan = [goal, throttle, urgent, via]
		return
	_visit_shots = 0   # a new place: hit and run counts afresh
	goal = _kept(goal)
	if via != Vector3.INF:
		via = _kept(via)
	var points: Array[Vector3] = []
	if via != Vector3.INF and _tactical_map() != null and not _tactical_map().is_blocked(via):
		points = _plan_path(via, tank.global_position)
		points.append_array(_plan_path(goal, via))
	else:
		points = _plan_path(goal)
	order_move(points, throttle)
	_path_goal = goal
	_path_throttle = throttle
	_scout_points.clear()
	_scout_wait = 0.0
	var map: TacticalMap = _tactical_map()
	if not urgent and map != null:
		var path := PackedVector3Array(points)
		_scout_points = map.scout_points(tank.global_position, path, _tactics())


## `goal` moved where the mode lets the bot go (keep_goal), else as it is.
func _kept(goal: Vector3) -> Vector3:
	return keep_goal.call(goal) if keep_goal.is_valid() else goal


## Where this crew believes the enemy is (flat direction from the tank), from what it
## knows itself: its target, a fresh alert (radio report or a hit), or the nearest
## enemy it has spotted. ZERO = no idea.
func get_threat_direction() -> Vector3:
	var at := Vector3.INF
	if _target != null and is_instance_valid(_target):
		at = _target.global_position
	elif _alert_timer > 0.0 and _alert_direction.length() > 0.01:
		return Vector3(_alert_direction.x, 0.0, _alert_direction.z).normalized()
	else:
		var best: float = INF
		for key: Variant in _spotted.keys():
			if not is_instance_valid(key):
				continue
			var other: Tank = key
			var d: float = tank.global_position.distance_to(other.global_position)
			if d < best:
				best = d
				at = other.global_position
	if at == Vector3.INF:
		return Vector3.ZERO
	var dir: Vector3 = at - tank.global_position
	dir.y = 0.0
	return dir.normalized() if dir.length() > 0.1 else Vector3.ZERO


## Seconds since the crew last had contact (an enemy seen, reported, or a hit).
func get_time_since_contact() -> float:
	return _since_contact


## Enemies this crew has seen or had reported within `max_age_s`: Tank -> last known
## position. Own knowledge only (same rules as a player's).
func get_known_enemies(max_age_s: float) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in _last_known.keys():
		if not is_instance_valid(key):
			continue
		var other: Tank = key
		var entry: Array = _last_known[key]
		if other.is_knocked_out() or _clock - float(entry[1]) > max_age_s:
			continue
		result[other] = entry[0]
	return result


## True while the current target's hull is in sight (the gun can work on it).
func has_target_in_sight() -> bool:
	return _target != null and is_instance_valid(_target) \
			and bool(_hull_visible.get(_target, false))


func is_scouting() -> bool:
	return _scout_wait > 0.0


## Pulling back after hits or near misses (KothBots leaves such a bot alone).
func is_relocating() -> bool:
	return _relocating


func _tactics() -> TacticsData:
	return bot_data.tactics if bot_data != null and bot_data.tactics != null \
			else TacticalMap.DEFAULT_TACTICS


func _plan_path(goal: Vector3, from: Vector3 = Vector3.INF) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var map: TacticalMap = _tactical_map()
	if from == Vector3.INF:
		from = tank.global_position
	if map != null:
		for p: Vector3 in map.find_path(from, goal, _avoid_cells + _known_mine_cells(map)):
			points.append(p)
	if points.is_empty():
		points.append(goal)
	return points


## Grid cells round enemy mines the team knows of (the mine's cell and its neighbours).
func _known_mine_cells(map: TacticalMap) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for node: Node in get_tree().get_nodes_in_group(Mine.GROUP):
		var mine := node as Mine
		if mine == null or mine.team == tank.team or not mine.is_known_by(tank.team):
			continue
		var c: Vector2i = map.grid.cell_of(mine.global_position)
		for dx: int in range(-1, 2):
			for dy: int in range(-1, 2):
				cells.append(c + Vector2i(dx, dy))
	return cells


## A mine was found or went: on a planned path with a known enemy mine near, plan again.
func _check_mines() -> void:
	if Mine.version == _mine_version:
		return
	_mine_version = Mine.version
	if _path_goal == Vector3.INF or _order_index >= _orders.size() or _tactical_map() == null:
		return
	for node: Node in get_tree().get_nodes_in_group(Mine.GROUP):
		var mine := node as Mine
		if mine != null and mine.team != tank.team and mine.is_known_by(tank.team) \
				and mine.global_position.distance_to(tank.global_position) <= MINE_REPLAN_M:
			order_path(_path_goal, _path_throttle, true)
			return


func _tactical_map() -> TacticalMap:
	if not _tactical_looked_up:
		_tactical_looked_up = true
		_tactical = TacticalMap.for_scene(get_tree().current_scene)
	return _tactical


func has_orders_left() -> bool:
	return not _pending_plan.is_empty() or _order_index < _orders.size()


## Marks a spotted enemy in sight for the team, through the command like a player's
## spot (same cooldown): the target first, else whoever was marked longest ago.
func _update_team_spot() -> void:
	_command.spot = false
	if tank.get_spot_cooldown_remaining() > 0.0:
		return
	var best: Tank = null
	var best_age: float = bot_data.spot_remark_s
	for key: Variant in _spotted.keys():
		var other := key as Tank
		if other == null or not is_instance_valid(other) or other.is_knocked_out() \
				or float(_unseen_time.get(other, 0.0)) > 0.0:
			continue
		var age: float = _clock - float(_marked_at.get(other, -INF))
		if age < bot_data.spot_remark_s:
			continue
		if other == _target:
			best = other
			break
		if age > best_age:
			best_age = age
			best = other
	if best != null:
		_marked_at[best] = _clock
		_command.spot = true
		_command.spot_point = best.global_position


## Radio report from the group: look towards `at`; `enemy` (if known) is spotted faster.
func share_contact(enemy: Tank, at: Vector3) -> void:
	if enemy != null:
		_reported[enemy] = true
		_last_known[enemy] = [at, _clock]
	if _target == null:
		_alert_direction = at - tank.global_position
		_alert_timer = ALERT_TIME_S


func _physics_process(delta: float) -> void:
	if tank == null or bot_data == null:
		return
	if tank.is_knocked_out():
		# The tank holds this command object: an abandon left set would bail the crew
		# out again the moment the game mode respawns the tank (a wreck per wave).
		_command.abandon = false
		_command.throttle = 0.0
		_command.steering = 0.0
		_progress_at = Vector3.INF
		_no_progress_s = 0.0
		_forget_all()
		# Nothing from this life carries over: a pull-back or old route would keep the
		# respawned tank from its new orders (the directors skip relocating bots).
		_relocating = false
		_scoot = Scoot.NONE
		_close_fight = false
		if not _orders.is_empty() or not _pending_plan.is_empty():
			var none: Array[Vector3] = []
			order_move(none, 0.0)
		_update_respawn(delta)
		return
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer += _scan_interval()
		_scan_waits = maxi(_scan_waits, 0) + 1   # due: a light frame does it (_process)
	if _scan_waits > Ticks.LIGHT_FRAME_WAIT_TICKS:
		_run_scan()   # no light frame came: here, in the tick
	elif _scan_waits > 0:
		_scan_waits += 1
	_command.throttle = 0.0
	_command.steering = 0.0
	_command.smoke = _smoke_pending
	_command.abandon = false
	_smoke_pending = false
	_command.fire = false
	_command.fire_mg = false
	_command.mg_use_roof = false
	_command.has_aim = false
	if tank.move_blocked:
		# Locked by the game mode (a countdown): stand and wait; no stuck or abandon checks.
		_update_hatch(delta)
		tank.set_command(_command)
		return
	_alert_timer = maxf(_alert_timer - delta, 0.0)
	if _target != null or _alert_timer > 0.0 or _hit_close_timer > 0.0:
		_since_contact = 0.0
	else:
		_since_contact += delta
	_halting = false
	_clock += delta
	if _relocating and not has_orders_left():
		_relocate_hold -= delta
		if _relocate_hold <= 0.0:
			_relocating = false
	if _target != null and not is_instance_valid(_target):
		_target = null
	if not _pending_plan.is_empty() and TacticalMap.may_plan():
		var p: Array = _pending_plan
		_pending_plan = []
		order_path(p[0], p[1], p[2], p[3])
	_update_close_fight()
	_choose_ammo(delta)
	if _target != null:
		_engage(_target, delta)
	elif _squad_target != null and is_instance_valid(_squad_target) and _squad_target.is_out():
		_settle_time = 0.0
		_engage_squad(_squad_target, delta)
	else:
		_settle_time = 0.0
		_mg_time = 0.0
		_look_ahead_or_at_threat()
	_update_screen(delta)
	_command.squad_order = Squad.ORDER_NONE
	_update_squad(delta)
	if _pending_squad_order != Squad.ORDER_NONE:
		_squad_order(_pending_squad_order, _pending_squad_target)
		_pending_squad_order = Squad.ORDER_NONE
	_update_team_spot()
	if _scoot != Scoot.NONE:
		_update_scoot(delta)
		_update_hatch(delta)
		tank.set_command(_command)
		return
	# Badly damaged and no enemy in sight: stand still and repair (same rules as players).
	var repairing: bool = _target == null and _wants_repair() and not tank.is_burning()
	if repairing:
		_command.throttle = 0.0
		_command.steering = 0.0
	elif _close_fight:
		_close_fight_step(delta)
	elif not _pending_plan.is_empty():
		pass   # waiting a tick or two for its path: stand
	elif not _orders.is_empty():
		if not _halting:
			_order_step(delta)
	elif _target == null:
		_patrol_step(delta)
	_update_hatch(delta)
	_update_abandon(delta, repairing)
	tank.set_command(_command)


## Trying to drive (orders, nothing broken; a target in sight too, when not halting to
## fire) but getting nowhere for
## BotData.abandon_stuck_s: hung on a rock or wedged in, so the crew abandons the tank.
func _update_abandon(delta: float, repairing: bool) -> void:
	var here: Vector3 = tank.global_position
	if _progress_at == Vector3.INF or here.distance_to(_progress_at) > bot_data.abandon_stuck_m:
		_progress_at = here
		_no_progress_s = 0.0
		return
	var trying: bool = has_orders_left() and not repairing and not _halting \
			and _scout_wait <= 0.0 and not tank.is_immobilised() and not tank.is_burning() \
			and absf(_command.throttle) > 0.05
	if not trying:
		_no_progress_s = maxf(_no_progress_s - delta, 0.0)
		return
	_no_progress_s += delta
	if _no_progress_s >= bot_data.abandon_stuck_s:
		_no_progress_s = 0.0
		_progress_at = Vector3.INF
		_command.abandon = true


# --- Spotting -------------------------------------------------------------------

func _spot_time() -> float:
	return bot_data.spot_time_open_s if tank.get_hatch_progress() >= 1.0 \
			else bot_data.spot_time_closed_s


func _spot_time_for(other: Tank) -> float:
	return _spot_time() * (0.5 if _reported.has(other) else 1.0) * _dirt_factor()


## Dirty optics (an HE burst near): spotting takes longer, up to
## TankData.optics_dirt_spot_factor times at full dirt.
func _dirt_factor() -> float:
	return lerpf(1.0, tank.data.optics_dirt_spot_factor, tank.get_optics_dirt())


## A due look round (BotController._physics_process), done on a light frame (Ticks).
var _scan_waits: int = 0

func _process(_delta: float) -> void:
	if _scan_waits > 0 and Ticks.light_frame():
		_run_scan()


func _run_scan() -> void:
	_scan_waits = 0
	if tank == null or bot_data == null or tank.is_knocked_out():
		return
	_scan(_scan_interval())


## The look-round interval, stretched in big battles (BotData.scan_reference_enemies):
## each look covers every enemy, so many enemies would cost the square of the count.
var _enemy_count: int = 0

func _scan_interval() -> float:
	var stretch: float = clampf(float(_enemy_count) / maxf(float(bot_data.scan_reference_enemies), 1.0),
			1.0, bot_data.scan_max_stretch)
	return bot_data.scan_interval_s * stretch


func _scan(dt: float) -> void:
	_drop_freed()
	_prefetch_sight()
	var enemies: int = 0
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var other := node as Tank
		if other == null or not tank.is_enemy_of(other):
			continue
		enemies += 1
		if other.is_knocked_out():
			_forget(other)
			_last_known.erase(other)
			continue
		var scans: int = int(_look_wait.get(other, 0)) + 1
		if other != _target and scans < _scans_per_look(other):
			_look_wait[other] = scans
			continue
		_look_wait.erase(other)
		_look_at(other, dt * scans)
	_enemy_count = enemies
	_scan_squads(dt)
	_sight.clear()
	_check_mines()
	_pick_target()
	if _target != null:
		_update_superelevation(_target)


## Sight lines of this look round, cast together on worker threads (SightRays) before
## it: point -> in sight. The look round then asks _can_see_point as always, which takes
## the answer from here after its own range and sector tests. Same points as the look
## round picks (the same skipping of far tanks and squads), less those out of range or
## sector whatever their cover.
var _sight: Dictionary = {}

func _prefetch_sight() -> void:
	_sight.clear()
	var eye: Vector3 = tank.get_commander_eye_position()
	var full: float = _view_range()
	var rays := SightRays.new(tank.get_world_3d().direct_space_state)
	var exclude: Array[RID] = [tank.get_rid(), tank.get_commander_hitbox().get_rid()]
	var points: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var other := node as Tank
		if other == null or not tank.is_enemy_of(other) or other.is_knocked_out():
			continue
		if other != _target and int(_look_wait.get(other, 0)) + 1 < _scans_per_look(other):
			continue
		if not _within_view_range(other.global_position):
			continue
		for local: Vector3 in other.get_spot_points():
			_want_sight(rays, points, eye, full, other.to_global(local), other, exclude)
		if other.is_commander_exposed():
			_want_sight(rays, points, eye, full, other.get_commander_hitbox_position(),
					other.get_commander_hitbox(), exclude)
	var mg_range: float = bot_data.mg_range_m
	for node: Node in get_tree().get_nodes_in_group("squads"):
		var enemy := node as Squad
		if enemy == null or not enemy.is_out() or enemy.get_team() == tank.team:
			continue
		var d: float = tank.global_position.distance_to(enemy.global_position)
		if d > mg_range + VIEW_RANGE_MARGIN_M:
			continue
		if enemy != _squad_target and d > SQUAD_LOOK_EVERY_2ND_M \
				and int(_squad_look_wait.get(enemy, 0)) + 1 < 2:
			continue
		for hb: SoldierHitbox in enemy.get_hitboxes():
			if enemy.is_soldier_exposed(hb.index):
				_want_sight(rays, points, eye, full, hb.get_aim_point(), hb, exclude)
	if points.is_empty():
		return
	rays.run()
	for i: int in points.size():
		_sight[points[i]] = rays.seen(i)


func _want_sight(rays: SightRays, points: Array[Vector3], eye: Vector3, full: float,
		point: Vector3, collider: Object, exclude: Array[RID]) -> void:
	if eye.distance_to(point) > full or not _in_sector(eye, point):
		return
	rays.add(eye, point, collider, exclude)
	points.append(point)


## Far tanks are looked at less often (BotData.look_every_*_beyond_m).
func _scans_per_look(other: Tank) -> int:
	var d: float = tank.global_position.distance_to(other.global_position)
	if d > bot_data.look_every_4th_beyond_m:
		return 4
	if d > bot_data.look_every_2nd_beyond_m:
		return 2
	return 1


## One look at `other`: which of its sample points are in sight, how hard it is to
## make out (cover, movement, how much of it shows), and the spotting progress.
func _look_at(other: Tank, dt: float) -> void:
	var cover: float = float(_cover.get(other, 0.0))
	var time_factor: float = 1.0
	var range_factor: float = 1.0
	var samples: Array[Vector3] = other.get_spot_points()
	var seen_points: int = 0
	var points: int = samples.size()
	var head_seen: bool = false
	if other.is_commander_exposed():
		points += 1
	if _within_view_range(other.global_position):
		var conceal: ConcealmentData = bot_data.concealment
		if conceal != null:
			cover = Concealment.tank_cover(tank.get_world_3d(), other, conceal)
			time_factor = Concealment.tank_spot_time_factor(other, cover, conceal)
			range_factor = Concealment.range_factor(cover, conceal)
		time_factor *= other.data.camo_spot_factor
		for local: Vector3 in samples:
			if _can_see_point(other.to_global(local), other, range_factor):
				seen_points += 1
		if other.is_commander_exposed():
			head_seen = _can_see_point(other.get_commander_hitbox_position(),
					other.get_commander_hitbox(), range_factor)
			if head_seen:
				seen_points += 1
	_hull_visible[other] = seen_points > (1 if head_seen else 0)
	_head_visible[other] = head_seen
	if not head_seen:
		_head_ready_at.erase(other)
	elif not _head_ready_at.has(other):
		_head_ready_at[other] = _clock + _rng.randf_range(bot_data.head_reaction_min_s,
				bot_data.head_reaction_max_s)
	_cover[other] = cover
	var shown: float = float(seen_points) / float(points)
	var aware: float = float(_awareness.get(other, 0.0))
	if seen_points > 0:
		var needed: float = _spot_time_for(other) * time_factor / maxf(shown, MIN_SHOWN_SHARE)
		_unseen_time[other] = 0.0
		_awareness[other] = aware + dt
		if not _spotted.has(other) and aware + dt >= needed:
			_spotted[other] = true
		if _spotted.has(other):
			_last_known[other] = [other.global_position, _clock]
			contact.emit(other, other.global_position)
	else:
		var unseen: float = float(_unseen_time.get(other, 0.0)) + dt
		_unseen_time[other] = unseen
		if not _spotted.has(other):
			_awareness[other] = maxf(aware - dt, 0.0)
		elif unseen >= bot_data.forget_after_s:
			_forget(other)


## False when `point` lies beyond the commander's current view range (plus margin),
## whatever cover or camouflage: cover only ever shortens the range.
func _within_view_range(point: Vector3) -> bool:
	var open: bool = tank.get_hatch_progress() >= 1.0
	var view_range: float = Weather.view_range(bot_data.view_range_open_m if open
			else bot_data.view_range_closed_m)
	if tank.is_burning():
		view_range *= tank.data.fire_view_range_factor   # smoke from the own fire
	return tank.get_commander_eye_position().distance_to(point) <= view_range + VIEW_RANGE_MARGIN_M


## Line of sight from this commander's eye to `point` on `collider`, within range
## and, with the hatch closed, within the periscope sector.
func _can_see_point(point: Vector3, collider: CollisionObject3D,
		range_factor: float = 1.0) -> bool:
	var eye: Vector3 = tank.get_commander_eye_position()
	var open: bool = tank.get_hatch_progress() >= 1.0
	var view_range: float = range_factor * Weather.view_range(bot_data.view_range_open_m
			if open else bot_data.view_range_closed_m)
	if eye.distance_to(point) > view_range:
		return false
	if not open:
		var flat := Vector3(point.x - eye.x, 0.0, point.z - eye.z)
		var turret_forward := Vector3(sin(tank.get_turret_global_yaw()) * -1.0, 0.0,
				-cos(tank.get_turret_global_yaw()))
		if flat.angle_to(turret_forward) > deg_to_rad(bot_data.periscope_half_angle_deg):
			return false
	if _sight.has(point):
		return bool(_sight[point])   # cast before the look round (_prefetch_sight)
	var exclude: Array[RID] = [tank.get_rid(), tank.get_commander_hitbox().get_rid()]
	return Vision.has_line_of_sight(tank.get_world_3d(), eye, point, collider, exclude)


func _pick_target() -> void:
	var nearest: Tank = null
	var best_distance: float = INF
	for other: Tank in _awareness.keys():
		if not is_instance_valid(other) or not is_spotted(other) or other.is_knocked_out():
			continue
		var distance: float = tank.global_position.distance_to(other.global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = other
	var previous: Tank = _target
	var keep: bool = _target != null and is_instance_valid(_target) and is_spotted(_target) \
			and not _target.is_knocked_out()
	# Keep the target, unless another enemy is close (the close fight comes first).
	if keep and (nearest == _target or best_distance > _tactics().close_fight_range_m):
		return
	_target = nearest
	if _target != null and _target != previous:
		# New target: a fresh range estimate, off by up to range_error_start.
		_range_error = _rng.randf_range(-1.0, 1.0) * bot_data.range_error_start
		_lay_error = Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) \
				* bot_data.lay_error_mrad * 0.001
		_lead_error = _rng.randf_range(-1.0, 1.0) * bot_data.lead_error
		_settle_time = 0.0


## Which round to load, like a crew would: AP for a tank whose facing plate it can get
## through, HE for one it can't (blast, modules, dirt on its optics) and for infantry.
## Only with a round in the breech (a change costs a reload), every AMMO_THINK_S.
func _choose_ammo(delta: float) -> void:
	_ammo_think -= delta
	if _ammo_think > 0.0 or not tank.is_loaded():
		return
	_ammo_think = AMMO_THINK_S
	var ap: int = -1
	var he: int = -1
	for i: int in tank.data.ammo.size():
		var s: ShellData = tank.data.ammo[i]
		if s == null:
			continue
		if s.is_explosive():
			he = i if he < 0 else he
		elif ap < 0:
			ap = i
	var want: int = -1
	if _target != null and he >= 0 and get_role().track_he:
		want = he   # at the tracks: slows them down for the others
	elif _target != null:
		want = ap if ap >= 0 and (he < 0 or _can_penetrate(_target, tank.data.ammo[ap])) else he
	elif _squad_target != null and is_instance_valid(_squad_target) and _squad_target.is_out() \
			and tank.global_position.distance_to(_squad_target.global_position) <= HE_SQUAD_RANGE_M:
		want = he
	if want >= 0 and want != tank.get_ammo_index():
		_command.ammo_select = want


## Does `shell` (at muzzle speed, a little lost on the way) get through the plate of
## `target`'s hull that faces this tank (front, side or rear; the chassis' slope)?
func _can_penetrate(target: Tank, shell: ShellData) -> bool:
	var a: ArmourData = target.data.armour
	if a == null:
		return true
	var to_me: Vector3 = tank.global_position - target.global_position
	var fwd: Vector3 = -target.global_basis.z
	to_me.y = 0.0
	fwd.y = 0.0
	var aspect: float = rad_to_deg(fwd.angle_to(to_me)) if to_me.length() > 0.1 else 0.0
	var slopes: Array = TankModel.SLOPES.get(target.data.model_style, [0.0, 0.0, 0.0])
	var mm: float = a.hull_side_mm / cos(deg_to_rad(float(slopes[1])))
	if aspect <= FRONT_ASPECT_DEG:
		mm = a.hull_front_mm / cos(deg_to_rad(float(slopes[0])))
	elif aspect >= 180.0 - REAR_ASPECT_DEG:
		mm = a.hull_rear_mm
	var lost: float = clampf(to_me.length() / 2000.0, 0.0, 0.3)   # rough speed loss
	return shell.penetration_mm * (1.0 - lost) >= mm


## Close fight on or off: a target within close_fight_range_m (let go past the release
## share), the tank able to drive. Ending it, the bot takes up its orders again by a
## fresh path from where the fight left it.
func _update_close_fight() -> void:
	var t: TacticsData = _tactics()
	var was: bool = _close_fight
	_close_fight = false
	if t.close_fight_range_m > 0.0 and _target != null and not _target.is_knocked_out() \
			and not tank.is_immobilised() and tank.get_speed_factor() > 0.0:
		var reach: float = t.close_fight_range_m * (t.close_fight_release_share if was else 1.0)
		_close_fight = tank.global_position.distance_to(_target.global_position) <= reach
	if _close_fight and not was:
		_scoot = Scoot.NONE   # no backing off to reload at this range
		_relocating = false
	elif was and not _close_fight and has_orders_left() and _path_goal != Vector3.INF:
		order_path(_path_goal, _path_throttle, true)


## Drives round to the target's side or rear (the nearer side), close_fight_flank_m off
## its hull, so the gun meets side armour and the turret rear; the turret is _engage's.
func _close_fight_step(delta: float) -> void:
	if _reverse_time > 0.0:
		_reverse_time -= delta
		_command.throttle = -1.0
		return
	var t: TacticsData = _tactics()
	var enemy_at: Vector3 = _target.global_position
	var their_fwd: Vector3 = -_target.global_basis.z
	their_fwd.y = 0.0
	their_fwd = their_fwd.normalized() if their_fwd.length() > 0.01 else Vector3.FORWARD
	var their_right: Vector3 = their_fwd.cross(Vector3.UP)
	var side: float = 1.0 if (tank.global_position - enemy_at).dot(their_right) >= 0.0 else -1.0
	var goal: Vector3 = enemy_at + their_right * side * t.close_fight_flank_m \
			- their_fwd * t.close_fight_flank_m * 0.6
	if _steer_towards(goal, t.close_fight_throttle):
		return   # at its flank: stand and shoot
	_update_stuck(delta)


func _forget(other: Tank) -> void:
	_awareness.erase(other)
	_spotted.erase(other)
	_cover.erase(other)
	_unseen_time.erase(other)
	_look_wait.erase(other)
	_hull_visible.erase(other)
	_head_ready_at.erase(other)
	_head_visible.erase(other)
	if other == _target:
		_target = null


## Forgets tanks that no longer exist (removed from the map, e.g. the map's own
## player tank when a network game spawns the players). Keys are checked untyped:
## a freed tank can't even be assigned to a Tank variable.
func _drop_freed() -> void:
	if _target != null and not is_instance_valid(_target):
		_target = null
	for memory: Dictionary in [_awareness, _spotted, _cover, _unseen_time, _look_wait,
			_hull_visible, _head_visible, _reported, _last_known, _squad_awareness,
			_squad_look_wait, _squad_ok]:
		for key: Variant in memory.keys():
			if not is_instance_valid(key):
				memory.erase(key)


func _forget_all() -> void:
	_awareness.clear()
	_spotted.clear()
	_cover.clear()
	_unseen_time.clear()
	_look_wait.clear()
	_hull_visible.clear()
	_head_ready_at.clear()
	_head_visible.clear()
	_last_known.clear()
	_target = null


## Stops to repair only when it matters: a destroyed module, a thrown track, or hp
## below BotData.repair_stop_hp_fraction. Light damage is repaired while holding.
func _wants_repair() -> bool:
	if not tank.needs_repair():
		return false
	return tank.is_immobilised() or tank.has_destroyed_module() \
			or tank.get_hp_fraction() < bot_data.repair_stop_hp_fraction


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
	_check_dodge(target)
	var muzzle: Transform3D = tank.get_muzzle_transform()
	var hull_seen: bool = bool(_hull_visible.get(target, false))
	var head_seen: bool = bool(_head_visible.get(target, false))
	var distance: float = muzzle.origin.distance_to(target.global_position)
	var use_mg: bool = head_seen and distance <= bot_data.mg_range_m \
			and _clock >= float(_head_ready_at.get(target, INF))
	var roof: bool = use_mg and tank.can_use_roof_mg()
	var coax_turn: bool = use_mg and not roof and not tank.is_loaded()

	# Main gun (or coax while reloading): the turret follows the chosen aim.
	var gun_aim: Vector3
	if coax_turn:
		gun_aim = _aim_point(target.get_commander_hitbox_position(), target,
				tank.get_coax_muzzle_transform().origin, _mg_superelevation,
				tank.get_active_mg(false).bullet)
	else:
		var loaded: ShellData = tank.get_loaded_shell()
		var point: Vector3 = target.global_position + target.global_basis.y * 0.3
		if get_role().track_he and loaded != null and loaded.is_explosive():
			point = _track_point(target, muzzle.origin)
		gun_aim = _aim_point(point, target, muzzle.origin, _gun_superelevation, loaded)
		gun_aim = _with_lay_error(gun_aim, muzzle.origin)

	# How to shoot. Holding a spot: halt and fire. On the way somewhere: a short halt
	# only beside cover and within transit_fire_range_m; in the open, fire on the move
	# when close enough (BotData.move_fire_*), else hold fire and drive on to a better
	# place.
	var on_the_way: bool = has_orders_left() or _close_fight
	var halt_ok: bool = not _close_fight and (not on_the_way
			or (distance <= _tactics().transit_fire_range_m and _is_covered_here()))
	var fire_moving: bool = on_the_way and not halt_ok and distance <= bot_data.move_fire_range_m
	if fire_moving and not coax_turn:
		var extra: float = tank.linear_velocity.length() * bot_data.move_lay_error_mrad_per_mps * 0.001 \
				* (1.0 - tank.data.gun_stabiliser)
		var to_aim: Vector3 = gun_aim - muzzle.origin
		var right: Vector3 = to_aim.cross(Vector3.UP).normalized()
		gun_aim += (right * _move_error_dir.x + Vector3.UP * _move_error_dir.y) * extra * to_aim.length()
	_command.aim_point = gun_aim
	_command.has_aim = true

	_halting = tank.is_loaded() and hull_seen and not coax_turn and halt_ok
	var still: bool = tank.linear_velocity.length() * 3.6 <= bot_data.max_fire_speed_kmh
	var gun_error: float = (-muzzle.basis.z).angle_to(gun_aim - muzzle.origin)
	var tolerance: float = bot_data.move_aim_tolerance_deg if fire_moving else bot_data.aim_tolerance_deg
	var settle_needed: float = bot_data.move_aim_settle_s if fire_moving else bot_data.aim_settle_s
	var on_target: bool = gun_error <= deg_to_rad(tolerance) \
			or (distance <= bot_data.barrel_ray_range_m and _barrel_hits(target, muzzle))
	if not coax_turn and hull_seen and (still or fire_moving) and on_target:
		_settle_time += delta
	else:
		_settle_time = 0.0
	if _settle_time >= settle_needed and tank.is_loaded():
		_command.fire = true
		_settle_time = 0.0
		_move_error_dir = Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf())
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


## True when a ray along the barrel (from the muzzle, a little past the target) hits
## `target` first: the round would strike it, however far off the aim angle is.
func _barrel_hits(target: Tank, muzzle: Transform3D) -> bool:
	var from: Vector3 = muzzle.origin
	var reach: float = from.distance_to(target.global_position) + 10.0
	var query := PhysicsRayQueryParameters3D.create(from, from - muzzle.basis.z.normalized() * reach,
			Vision.SHOT_MASK, [tank.get_rid()])
	var hit: Dictionary = tank.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == target


## Beside cover (bushes, trees, tree line, houses) by the tactical grid: a fair place
## for a firing halt. True without a grid (no way to tell).
func _is_covered_here() -> bool:
	var map: TacticalMap = _tactical_map()
	return map == null or map.is_covered(tank.global_position)


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

## A smoke screen towards `point` (world): the salvo lands ahead of the turret, so the
## turret turns there first (unless it is on a target) and fires it once it bears
## within SCREEN_BEAR_DEG. Refused (false) while it has fewer than SCREEN_KEEP_SALVOS + 1
## salvos (the last is kept for its own escape) or smoke is cooling down.
func request_screen(point: Vector3) -> bool:
	if tank.get_smoke_left() <= SCREEN_KEEP_SALVOS or tank.get_smoke_cooldown() > 0.0 \
			or _screen_at != Vector3.INF or tank.is_knocked_out():
		return false
	_screen_at = point
	_screen_wait = SCREEN_MAX_WAIT_S
	return true


func _update_screen(delta: float) -> void:
	if _screen_at == Vector3.INF:
		return
	_screen_wait -= delta
	var to := Vector3(_screen_at.x - tank.global_position.x, 0.0, _screen_at.z - tank.global_position.z)
	if _screen_wait <= 0.0 or to.length() < 1.0:
		_screen_at = Vector3.INF
		return
	if _target == null:
		_command.aim_point = tank.get_commander_eye_position() + to.normalized() * 200.0
		_command.has_aim = true
	var yaw: float = tank.get_turret_global_yaw()
	var turret := Vector3(-sin(yaw), 0.0, -cos(yaw))
	if rad_to_deg(turret.angle_to(to.normalized())) <= SCREEN_BEAR_DEG:
		_command.smoke = true
		_screen_at = Vector3.INF


## No target: point the turret where the last hit came from, else along the hull.
func _look_ahead_or_at_threat() -> void:
	var eye: Vector3 = tank.get_commander_eye_position()
	var direction: Vector3 = _alert_direction if _alert_timer > 0.0 else -tank.global_basis.z
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	_command.aim_point = eye + direction.normalized() * 200.0
	_command.has_aim = true


# --- Infantry ----------------------------------------------------------------------

## Enemy squads: the same sight rules as for tanks, on the soldiers (small: slow to make
## out; Squad.soldier_spot_time_factor adds cover, stance, distance and firing). The nearest spotted one in MG range is fired on when there is no tank target.
func _scan_squads(dt: float) -> void:
	var best: Squad = null
	var best_d: float = INF
	var mg_range: float = bot_data.mg_range_m
	var eye: Vector3 = tank.get_commander_eye_position()
	var full_range: float = _view_range()
	for node: Node in get_tree().get_nodes_in_group("squads"):
		var enemy := node as Squad
		if enemy == null or not enemy.is_out() or enemy.get_team() == tank.team:
			_forget_squad(enemy)
			continue
		var d: float = tank.global_position.distance_to(enemy.global_position)
		if d > mg_range + VIEW_RANGE_MARGIN_M:
			# Only squads in MG range become targets: don't trace sight lines to the rest.
			_forget_squad(enemy)
			continue
		var scans: int = int(_squad_look_wait.get(enemy, 0)) + 1
		if enemy != _squad_target and d > SQUAD_LOOK_EVERY_2ND_M and scans < 2:
			_squad_look_wait[enemy] = scans
			if bool(_squad_ok.get(enemy, false)) and d <= mg_range and d < best_d:
				best = enemy
				best_d = d
			continue
		_squad_look_wait.erase(enemy)
		var look_dt: float = dt * scans
		var seen: int = 0
		var total: int = 0
		# The easiest of the soldiers in sight decides (cover, stance, distance, firing).
		var easiest: float = INF
		for hb: SoldierHitbox in enemy.get_hitboxes():
			if not enemy.is_soldier_exposed(hb.index):
				continue
			total += 1
			var point: Vector3 = hb.get_aim_point()
			# Cheap tests first (out of range or the periscope's sector whatever his cover:
			# cover only ever shortens the range), then cover and the sight line.
			if eye.distance_to(point) > full_range or not _in_sector(eye, point):
				continue
			var range_factor: float = enemy.soldier_spot_range_factor(hb.index, bot_data.concealment, eye)
			if _can_see_point(point, hb, range_factor):
				seen += 1
				easiest = minf(easiest,
						enemy.soldier_spot_time_factor(hb.index, eye, bot_data.concealment))
		var aware: float = float(_squad_awareness.get(enemy, 0.0))
		if seen == 0:
			aware = maxf(aware - look_dt, 0.0)
		else:
			aware += look_dt
		_squad_awareness[enemy] = aware
		var needed: float = _spot_time() * enemy.data.soldier_spot_factor * easiest \
				/ maxf(float(seen) / maxf(total, 1), MIN_SHOWN_SHARE)
		var ok: bool = seen > 0 and aware >= needed
		_squad_ok[enemy] = ok
		if ok and d <= mg_range and d < best_d:
			best = enemy
			best_d = d
	_squad_target = best


func _forget_squad(enemy: Squad) -> void:
	_squad_awareness.erase(enemy)
	_squad_look_wait.erase(enemy)
	_squad_ok.erase(enemy)


## The commander's view range (m) as _can_see_point takes it: hatch open or periscope,
## and the weather.
func _view_range() -> float:
	var open: bool = tank.get_hatch_progress() >= 1.0
	return Weather.view_range(bot_data.view_range_open_m if open else bot_data.view_range_closed_m)


## With the hatch closed, `point` is within the periscope sector round the turret.
func _in_sector(eye: Vector3, point: Vector3) -> bool:
	if tank.get_hatch_progress() >= 1.0:
		return true
	var flat := Vector3(point.x - eye.x, 0.0, point.z - eye.z)
	var turret_forward := Vector3(sin(tank.get_turret_global_yaw()) * -1.0, 0.0,
			-cos(tank.get_turret_global_yaw()))
	return flat.angle_to(turret_forward) <= deg_to_rad(bot_data.periscope_half_angle_deg)

## MG bursts at the nearest exposed soldier of `enemy` (roof MG with the hatch open,
## else the coax, which needs the turret on him).
func _engage_squad(enemy: Squad, delta: float) -> void:
	var aim := Vector3.INF
	var best: float = INF
	for hb: SoldierHitbox in enemy.get_hitboxes():
		if enemy.is_soldier_exposed(hb.index):
			var d: float = tank.global_position.distance_to(hb.global_position)
			if d < best:
				best = d
				aim = hb.get_aim_point()
	if aim == Vector3.INF:
		return
	var roof: bool = tank.can_use_roof_mg()
	_command.aim_point = aim
	_command.has_aim = true
	var muzzle: Transform3D = tank.get_roof_mg_muzzle_transform() if roof else tank.get_coax_muzzle_transform()
	if roof:
		_command.mg_aim_point = aim
		_command.mg_use_roof = true
	_fire_he_at_squad(aim, delta)
	if (-muzzle.basis.z).angle_to(aim - muzzle.origin) > deg_to_rad(bot_data.mg_aim_tolerance_deg):
		return
	_mg_time += delta
	_command.fire_mg = fmod(_mg_time, bot_data.mg_burst_s + bot_data.mg_pause_s) < bot_data.mg_burst_s


## With HE in the breech, the main gun goes at the soldier too (at his feet, allowing for
## drop), once laid and steady like any shot.
func _fire_he_at_squad(soldier: Vector3, delta: float) -> void:
	var shell: ShellData = tank.get_loaded_shell()
	if shell == null or not shell.is_explosive() or not tank.is_loaded():
		_settle_time = 0.0
		return
	var muzzle: Transform3D = tank.get_muzzle_transform()
	var feet: Vector3 = soldier - Vector3.UP * 0.6
	var horizontal: float = _horizontal_distance(muzzle.origin, feet)
	if horizontal > HE_SQUAD_RANGE_M:
		return
	var gun_aim: Vector3 = _with_lay_error(feet + Vector3.UP * horizontal
			* tan(Ballistics.superelevation_for_range(shell, horizontal * (1.0 + _range_error))),
			muzzle.origin)
	_command.aim_point = gun_aim
	_command.has_aim = true
	var still: bool = tank.linear_velocity.length() * 3.6 <= bot_data.max_fire_speed_kmh
	if still and (-muzzle.basis.z).angle_to(gun_aim - muzzle.origin) <= deg_to_rad(bot_data.aim_tolerance_deg):
		_settle_time += delta
	else:
		_settle_time = 0.0
	if _settle_time >= bot_data.aim_settle_s:
		_command.fire = true
		_settle_time = 0.0
		_range_error *= bot_data.range_error_correction
		_lay_error *= bot_data.range_error_correction


## The own squad saw an enemy: a radio contact for this crew.
func _on_squad_contact(enemy: Node3D, at: Vector3) -> void:
	share_contact(enemy as Tank, at)


## Uses the own squad like a player would (orders via the command), sparingly: only
## when the tank has stood a while near the fight (a known enemy, an alert, the fight
## focus) does it go out, to look over the ground towards the fight that the tank
## can't see; it is called back when hurt, left behind, or the tank drives on (not
## while it is out to lay a mine), and
## then stays on the tank for SQUAD_RESEND_COOLDOWN_S (the role's share of it).
func _update_squad(delta: float) -> void:
	var squad: Squad = tank.squad
	if squad == null or not is_instance_valid(squad) or squad.net_puppet:
		return
	_since_squad_recall += delta
	if tank.linear_velocity.length() > SQUAD_DRIVE_SPEED:
		_driving_time += delta
		_standing_time = 0.0
	else:
		_driving_time = 0.0
		_standing_time += delta
	_squad_think -= delta
	if _squad_think > 0.0:
		return
	_squad_think = SQUAD_THINK_S
	if squad.is_out():
		var lost_half: bool = squad.get_alive_count() * 2 <= squad.data.soldier_count
		var left_behind: bool = Squad._flat(squad.global_position - tank.global_position).length() \
				> SQUAD_RECALL_DISTANCE_M
		var driving_on: bool = _driving_time >= SQUAD_RECALL_DRIVE_S
		# Sent to lay a mine, it finishes the job (Squad keeps it within its reach of
		# the tank) even if the tank drives off to its post meanwhile.
		if squad.is_mine_job():
			left_behind = false
			driving_on = false
		if lost_half or left_behind or driving_on:
			_squad_order(Squad.ORDER_RECALL, Vector3.ZERO)
			_squad_look = Vector3.INF
			_since_squad_recall = 0.0
			return
		if squad.is_mine_job():
			return   # a move towards the fight would cancel the mine (KotH: the fight is at the zone)
	elif not squad.is_mounted() or squad.get_alive_count() < squad.data.soldier_count:
		return   # wiped out, or refilling on the tank
	elif _standing_time < get_role().squad_stand_s \
			or _since_squad_recall < SQUAD_RESEND_COOLDOWN_S * get_role().squad_cooldown_share \
			or is_scouting():
		return   # mounted: out only for a proper stop, not every halt
	if _driving_time > 0.0:
		return   # out (or moved on) only while the tank stands
	if not TacticalMap.may_plan():
		_squad_think = 0.0   # the tick's planning time is spent: the next tick
		return
	var fight: Vector3 = _squad_fight_point()
	if fight == Vector3.INF:
		return   # nothing going on near here: the squad stays on
	var look: Vector3 = _squad_look_point(fight)
	if look == Vector3.INF:
		return
	if _squad_look != Vector3.INF and Squad._flat(look - _squad_look).length() < SQUAD_MOVE_ON_M:
		return
	_squad_look = look
	_squad_order(Squad.ORDER_MOVE, look)


## Orders the own squad (via the command, like a player) in the next frame.
func order_squad(kind: int, target: Vector3) -> void:
	_pending_squad_order = kind
	_pending_squad_target = target


func _squad_order(kind: int, target: Vector3) -> void:
	_command.squad_order = kind
	_command.squad_target = target


## Where the fight is that the squad should look towards: the nearest enemy the crew
## knows of within SQUAD_FIGHT_RANGE_M, a fresh alert, or the fight focus when the tank
## is near it. INF = no fight near here.
func _squad_fight_point() -> Vector3:
	var here: Vector3 = tank.global_position
	var best := Vector3.INF
	var best_d: float = SQUAD_FIGHT_RANGE_M
	var known: Dictionary = get_known_enemies(SQUAD_ENEMY_MAX_AGE_S)
	for key: Variant in known:
		var at: Vector3 = known[key]
		var d: float = Squad._flat(at - here).length()
		if d < best_d:
			best_d = d
			best = at
	if best != Vector3.INF:
		return best
	if _alert_timer > 0.0 and _alert_direction.length() > 0.01:
		return here + Squad._flat(_alert_direction).normalized() * HIT_ORIGIN_GUESS_M
	if fight_focus != Vector3.INF and Squad._flat(fight_focus - here).length() <= SQUAD_FOCUS_RANGE_M:
		# At the zone: look out the way the enemy comes from.
		var threat: Vector3 = get_threat_direction()
		return here + threat * SQUAD_LOOK_AHEAD_M if threat != Vector3.ZERO else fight_focus
	return Vector3.INF


## Where the squad should look from: a covered spot with a view towards `fight`, at
## most SQUAD_LOOK_AHEAD_M from the tank (well short of the enemy itself).
func _squad_look_point(fight: Vector3) -> Vector3:
	var here: Vector3 = tank.global_position
	var flat: Vector3 = Squad._flat(fight - here)
	if flat.length() < 1.0:
		return Vector3.INF
	var toward: Vector3 = flat.normalized()
	var point: Vector3 = here + toward * minf(SQUAD_LOOK_AHEAD_M, flat.length() * 0.5)
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene, tank.squad.data.tactics)
	if map == null:
		return point
	return map.find_position(tank.get_world_3d(), point, 50.0, toward, point + toward * 200.0,
			200.0, here, PackedVector3Array(), tank.squad.data.tactics, _rng, [tank.get_rid()])


# --- Shoot and scoot, relocation ----------------------------------------------------

## After a shot at a tank: back into a spot the target can't see while reloading.
## Hit and run: after shots_per_visit rounds, a long dash sideways instead.
func _on_fired(_shell: Shell) -> void:
	var t: TacticsData = _tactics()
	var role: BotRoleData = get_role()
	if role.hit_and_run and _target != null and is_instance_valid(_target) and not _close_fight:
		_visit_shots += 1
		if _visit_shots >= role.shots_per_visit:
			_dash(_target)
		return
	if not t.shoot_and_scoot or _target == null or not is_instance_valid(_target) or _scoot != Scoot.NONE \
			or _close_fight:
		return
	if _rng.randf() >= t.scoot_chance:
		return   # stays up and keeps fighting
	var map: TacticalMap = _tactical_map()
	if map == null:
		return
	var away: Vector3 = tank.global_position - _target.global_position
	away.y = 0.0
	if away.length() < 1.0:
		return
	away = away.normalized()
	var spot: Vector3 = _find_hide_spot(away, _target.get_commander_eye_position())
	if spot != Vector3.INF:
		_start_hiding(spot, away)
	# Nowhere to hide nearby: stay and fight.


## The middle of `target`'s track on the side facing `from` (HE there throws it).
func _track_point(target: Tank, from: Vector3) -> Vector3:
	var best := Vector3.INF
	if target.data.layout != null:
		for m: ModuleData in target.data.layout.modules:
			if m.frame != &"hull" or not (m.id == &"track_left" or m.id == &"track_right"):
				continue
			var outer: Vector3 = m.center + Vector3(signf(m.center.x) * m.size.x * 0.5, 0.0, 0.0)
			var p: Vector3 = target.to_global(outer)
			if best == Vector3.INF or from.distance_to(p) < from.distance_to(best):
				best = p
	return best if best != Vector3.INF else target.global_position


## Hit and run: off to the side of `from_target` (and a little back), dash_min_m..
## dash_max_m away, to a spot facing it; held there dash_hold_s, then the director's
## orders again. The shots from the old spot are forgotten.
func _dash(from_target: Tank) -> void:
	_visit_shots = 0
	var map: TacticalMap = _tactical_map()
	if map == null:
		return
	var role: BotRoleData = get_role()
	var t: TacticsData = _tactics()
	var here: Vector3 = tank.global_position
	var to_them := Vector3(from_target.global_position.x - here.x, 0.0, from_target.global_position.z - here.z)
	if to_them.length() < 1.0:
		return
	to_them = to_them.normalized()
	var dist: float = _rng.randf_range(role.dash_min_m, role.dash_max_m)
	var side: Vector3 = to_them.cross(Vector3.UP) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var center: Vector3 = here + side * dist * 0.85 - to_them * dist * 0.35
	if map.is_blocked(center):
		center = here - side * dist * 0.85 - to_them * dist * 0.35
	var friends := PackedVector3Array()
	var spot: Vector3 = map.find_position(tank.get_world_3d(), center, dist * 0.3, to_them,
			from_target.global_position, role.harass_range_max_m, here, friends, t, _rng, [tank.get_rid()])
	_scoot = Scoot.NONE
	order_path(spot, 1.0, true)
	_relocating = true
	_relocate_hold = role.dash_hold_s


## A role that avoids front duels slips away (a dash) when an enemy within
## DODGE_RANGE_M lays its gun on it and our gun can't get through its front.
func _check_dodge(target: Tank) -> void:
	var role: BotRoleData = get_role()
	if not role.avoid_front_duels or _relocating or _close_fight or _clock - _dodged_at < DODGE_COOLDOWN_S:
		return
	var here: Vector3 = tank.global_position
	if here.distance_to(target.global_position) > DODGE_RANGE_M:
		return
	var their_gun: Vector3 = -target.get_muzzle_transform().basis.z
	if their_gun.angle_to(here - target.get_muzzle_transform().origin) > deg_to_rad(LAID_ON_DEG):
		return
	for s: ShellData in tank.data.ammo:
		if s != null and not s.is_explosive() and _can_penetrate(target, s):
			return   # we can answer: no running from it
	_dodged_at = _clock
	_dash(target)


## A spot close behind the tank (along `away`) hidden from an eye at `their_eye`, or INF.
func _find_hide_spot(away: Vector3, their_eye: Vector3) -> Vector3:
	var t: TacticsData = _tactics()
	var map: TacticalMap = _tactical_map()
	var exclude: Array[RID] = [tank.get_rid()]
	if _target != null and is_instance_valid(_target):
		exclude.append(_target.get_rid())
	for dist: float in [t.hide_distance_min_m, (t.hide_distance_min_m + t.hide_distance_max_m) * 0.5,
			t.hide_distance_max_m]:
		for angle: float in HIDE_ANGLES_DEG:
			var dir: Vector3 = away.rotated(Vector3.UP, deg_to_rad(angle))
			var p: Vector3 = tank.global_position + dir * dist
			if map.is_blocked(p):
				continue
			p.y = map._height_at(p)
			# Hidden: the target's commander can't see where our commander's head would be.
			if not TacticalMap._sight_clear(tank.get_world_3d(), their_eye,
					p + Vector3.UP * TacticalMap.EYE_HEIGHT_M, exclude):
				return p
	return Vector3.INF


## Backs to `spot`, then comes up again to the side (_update_scoot).
func _start_hiding(spot: Vector3, away: Vector3) -> void:
	var t: TacticsData = _tactics()
	var side: Vector3 = away.cross(Vector3.UP) * (1.0 if _rng.randf() < 0.5 else -1.0)
	var peek: Vector3 = tank.global_position + side * _rng.randf_range(t.peek_side_min_m, t.peek_side_max_m)
	_peek_point = tank.global_position if _tactical_map().is_blocked(peek) else _kept(peek)
	_scoot_point = _kept(spot)
	_scoot = Scoot.HIDING
	_scoot_time = 0.0


## Backs to the hide spot (gun still on the target), waits for the reload, then drives
## up to the new firing spot; there the normal halt-and-fire takes over again.
func _update_scoot(delta: float) -> void:
	var t: TacticsData = _tactics()
	_scoot_time += delta
	_command.fire = false
	if _target == null or not is_instance_valid(_target) or _target.is_knocked_out():
		_scoot = Scoot.NONE
		return
	match _scoot:
		Scoot.HIDING:
			var reloaded: bool = tank.is_loaded() and _scoot_time >= tank.data.reload_time_s + t.hide_extra_s
			if reloaded or _scoot_time >= t.hide_max_s:
				_scoot = Scoot.RETURNING
				_scoot_time = 0.0
				return
			_reverse_towards(_scoot_point)
		Scoot.RETURNING:
			if _steer_towards(_peek_point, 0.5) or _scoot_time >= t.hide_max_s:
				_scoot = Scoot.NONE


## Backs towards `point` (stops when there). Steering turns the hull the same way in
## reverse, so the rear is steered like a nose.
func _reverse_towards(point: Vector3) -> void:
	var to_point: Vector3 = point - tank.global_position
	to_point.y = 0.0
	if to_point.length() < WAYPOINT_RADIUS * 0.5:
		_command.throttle = 0.0
		_command.steering = 0.0
		return
	var back: Vector3 = tank.global_basis.z
	back.y = 0.0
	var error: float = back.signed_angle_to(to_point, Vector3.UP)
	_command.steering = clampf(-error / FULL_STEER_ERROR, -1.0, 1.0)
	_command.throttle = -1.0 * clampf(1.0 - absf(error) / PI * 1.5, 0.3, 1.0)


## A gun round hit or nearly missed: maybe leave, the more likely the more rounds came
## in a row (relocate_chance_by_hits). A crew that can answer the shooter soon stays
## and fights; one with a hide spot close by backs into it; only one with neither is
## too exposed, and smokes and moves to a new position away from the threat.
func _check_relocation(from_dir: Vector3) -> void:
	var t: TacticsData = _tactics()
	if t.relocate_chance_by_hits.is_empty() or _tactical_map() == null or _relocating or _close_fight:
		return
	if not _hits.is_empty() and _clock - _hits[_hits.size() - 1] > t.relocate_window_s:
		_hits.clear()
	_hits.append(_clock)
	var chances: Array[float] = t.relocate_chance_by_hits
	if _rng.randf() >= chances[mini(_hits.size(), chances.size()) - 1]:
		return
	if _scoot == Scoot.HIDING or (_hits.size() < t.exposed_hits and _can_answer(from_dir)):
		return   # already on the way into cover, or shooting back first
	_hits.clear()
	_scoot = Scoot.NONE
	if tank.is_immobilised():
		_smoke_pending = true
		return
	var shooter_known: bool = _target_is_shooter(from_dir)
	var cover: Vector3 = _find_hide_spot(-from_dir, _threat_eye(from_dir, shooter_known))
	if cover != Vector3.INF:
		if shooter_known:
			_start_hiding(cover, -from_dir)   # gun on the target, back up after the reload
		else:
			order_path(cover, 0.8, true)
			_relocating = true
			_relocate_hold = t.relocate_hold_s
		return
	_smoke_pending = true
	var here: Vector3 = tank.global_position
	var center: Vector3 = here - from_dir * t.relocate_distance_m * 0.6
	var friends := PackedVector3Array()
	var spot: Vector3 = _tactical_map().find_position(tank.get_world_3d(), center,
			t.relocate_distance_m * 0.5, from_dir, here + from_dir * 200.0, 150.0, here,
			friends, t, _rng, [tank.get_rid()])
	order_path(spot, 0.8, true)
	_relocating = true
	_relocate_hold = t.relocate_hold_s


## The bot's target stands about where a round came from (`from_dir`, flat).
func _target_is_shooter(from_dir: Vector3) -> bool:
	if _target == null or not is_instance_valid(_target) or _target.is_knocked_out():
		return false
	var to_target: Vector3 = Squad._flat(_target.global_position - tank.global_position)
	return to_target.length() > 1.0 and to_target.normalized().dot(from_dir) \
			>= cos(deg_to_rad(_tactics().answer_cone_deg))


## The gun can fire at the shooter within answer_time_s: in sight, reloaded and laid.
func _can_answer(from_dir: Vector3) -> bool:
	if not _target_is_shooter(from_dir) or not bool(_hull_visible.get(_target, false)):
		return false
	var gun: Vector3 = Squad._flat(-tank.get_muzzle_transform().basis.z)
	var to_target: Vector3 = Squad._flat(_target.global_position - tank.global_position)
	var lay_s: float = gun.angle_to(to_target) / deg_to_rad(tank.data.turret_traverse_speed_deg)
	return tank.get_reload_remaining() + lay_s <= _tactics().answer_time_s


## Where the shooter's eye is, as far as the crew can tell.
func _threat_eye(from_dir: Vector3, shooter_known: bool) -> Vector3:
	if shooter_known:
		return _target.get_commander_eye_position()
	var p: Vector3 = tank.global_position + from_dir * HIT_ORIGIN_GUESS_M
	p.y = _tactical_map()._height_at(p) + TacticalMap.EYE_HEIGHT_M
	return p


func _on_hit_taken(direction: Vector3) -> void:
	_hit_close_timer = bot_data.close_hatch_after_hit_s if bot_data != null else 0.0
	_alert_direction = -direction
	_alert_timer = ALERT_TIME_S
	contact.emit(null, tank.global_position - direction.normalized() * HIT_ORIGIN_GUESS_M)


## A gun round hit (also in _on_hit_taken) or nearly missed: look that way (a near
## miss also shuts the hatch for a while) and maybe pull back.
func _on_shell_threat(direction: Vector3, hit: bool) -> void:
	if tank.is_knocked_out():
		return
	if not hit:
		_hit_close_timer = bot_data.close_hatch_after_hit_s if bot_data != null else 0.0
		if _target == null:
			_alert_direction = -direction
			_alert_timer = ALERT_TIME_S
	var from_dir := Vector3(-direction.x, 0.0, -direction.z)
	if from_dir.length() > 0.01:
		_check_relocation(from_dir.normalized())


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
