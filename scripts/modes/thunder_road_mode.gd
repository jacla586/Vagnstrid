class_name ThunderRoadMode
extends Node3D
## ThunderRoad (a gauntlet, ThunderRoadData): attackers clear a road checkpoint by
## checkpoint; defenders hold a corridor along it, ahead of the last checkpoint taken.
## Attackers get the same time for every checkpoint and a shared pool of lives and come
## back in waves; defenders come back a few checkpoints on. A checkpoint taken brings a
## fighting retreat (retreat_s, ThunderRoadData "Retreat"): the defenders' line jumps past
## the lost zone and those left behind make a marked last stand; the clock stands until
## the next one opens. (The old ceasefire, pause_*, is still in the data.)
## Outside its corridor a tank can't fire, shows on the other team's maps and is knocked
## out after outside_knockout_s. Points (stats column 5) for kills, assists, and more
## for taking and holding checkpoints. Two rounds, sides swap; more checkpoints wins
## (then more time left).
## Children: "Route" (Path3D along the road) and "Checkpoints" (Marker3Ds, projected
## onto the route). Runs offline and on the host; clients get its state
## (get_net_state / apply_net_state via NetGame) and run the clocks on in between.

## The next checkpoint fell (index, 0-based).
signal checkpoint_taken(index: int)
## A round began (1 or 2); the attackers are `attack_team`.
signal round_started(round_number: int, attack_team: int)
## The map was cleared for the next round (wrecks, mines, smoke gone; trees stand).
signal map_reset
## A round ended: how far the attackers got.
signal round_over(round_number: int, result: Dictionary)
## The match is over: the winning team (-1 = draw).
signal match_over(winner_team: int)
## A tank came back (start of a round, a wave or a defender's respawn).
signal tank_placed(tank: Tank)
## A checkpoint fell and the ceasefire began (index of the checkpoint taken): the
## attackers regroup, the defenders fall back to the next one.
signal pause_started(index: int)
## The ceasefire is over: checkpoint `index` (the next) is open.
signal pause_ended(index: int)
## Points went to `tank` (ThunderRoadData "Points"; host): kind is "kill", "assist",
## "capture", "hold".
signal points_scored(tank: Tank, points: float, kind: String)

enum Role { NONE, ATTACK, DEFEND }

static var instance: ThunderRoadMode

## Corridor checks run this often (s).
const CHECK_INTERVAL_S: float = 0.25
## Spawn slots: rows this far apart along the road, at these offsets across it (m).
const SLOT_ROW_M: float = 18.0
const SLOT_ROWS: int = 6
const SLOT_ACROSS_M: Array[float] = [0.0, 14.0, -14.0, 28.0, -28.0, 42.0, -42.0]
## A slot is taken with a tank this close (m).
const SLOT_CLEAR_M: float = 10.0
## A fallback slot (none fit) keeps this far from wrecks, so a tank never lands in one (m).
const WRECK_CLEAR_M: float = 6.0
## Spawns lift the tank (origin is mid-hull) so it doesn't start in the ground (m).
const SPAWN_LIFT_M: float = 1.5
## Client: the new round's map reset waits this long, so wrecks the puppets leave as
## they jump to the new spawns go too (s).
const NET_RESET_DELAY_S: float = 1.5
## How far the corridor drawing runs on past the road's end (the rule goes on forever).
const CORRIDOR_RUN_OUT_M: float = 3000.0

@export var data: ThunderRoadData

var _route: PackedVector3Array = PackedVector3Array()
var _along: PackedFloat32Array = PackedFloat32Array()   # metres along at each route point
var _cp_s: Array[float] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _started: bool = false
var _round: int = 0
var _attack_team: int = 0
var _next_cp: int = 0
var _front_s: float = 0.0
var _progress: float = 0.0
var _contested: bool = false
## Living attacker tanks in the next checkpoint's zone (host).
var _attackers_in: int = 0
## The time is up but attackers hold out in the zone: the round runs on.
var _overtime: bool = false
## Overtime: seconds left after the last attacker left the zone or fell.
var _overtime_grace: float = 0.0
var _time_left: float = 0.0
var _lives: int = 0
var _wave_left: float = 0.0
var _waiting: Array[Tank] = []           # knocked-out attackers waiting for the wave
var _def_respawn: Dictionary = {}        # Tank -> seconds to its respawn
var _outside: Dictionary = {}            # Tank -> seconds outside its corridor
var _mark_left: Dictionary = {}          # Tank -> seconds to its next map mark
var _check_left: float = 0.0
## New tanks and the capture are checked RULES_HZ times a second, with the time between
## (every tank against the zone each tick cost ~0.7 ms at 20 v 20; captures take seconds).
const RULES_HZ: float = 10.0
var _connect_clock := PackedFloat32Array([0.0])
var _capture_clock := PackedFloat32Array([0.0])
var _capture_dt: float = 0.0
## Seconds of ceasefire left after a capture (< 0: none).
var _pause_left: float = -1.0
var _connected: Dictionary = {}          # tank instance id -> true
var _results: Array[Dictionary] = []
var _break_left: float = -1.0
## The round already set up during the break before it (0: none).
var _prepared: int = 0
## Bot directors still filling the teams: the first round waits for them.
var _start_holds: int = 0
var _over: bool = false
var _winner: int = -1
## The match result is known (end of round 2), shown in the last break before _over.
var _decided: bool = false
## Tank instance id -> [name, team, knock-outs, losses, assists, points], over the whole match.
var _stats: Dictionary = {}
## Client: the host's stats rows and per-tank state (net_id -> [waiting, respawn, outside]).
var _net_stats: Array = []
## Stats rows waiting for a player's new tank (carry_stats), by its instance id.
var _carried: Dictionary = {}
var _net_tanks: Dictionary = {}
## Client: seconds until the new round's map reset (the old wrecks appear late here).
var _net_reset_left: float = -1.0


func _enter_tree() -> void:
	instance = self
	_give_bots_configs()


func _exit_tree() -> void:
	if instance == self:
		instance = null


## Before any tank is ready: bots without a config get a random one (as KothMode does).
func _give_bots_configs() -> void:
	if data == null or data.bot_configs.is_empty() or get_parent() == null:
		return
	# Tanks aren't ready (nor in the "tanks" group) yet: count the scene's own per team.
	var tanks: Array[Tank] = []
	var size: Dictionary = {}
	for node: Node in get_parent().find_children("*", "", true, false):
		var tank := node as Tank
		if tank != null and not tank.is_node_ready():
			tanks.append(tank)
			size[tank.team] = int(size.get(tank.team, 0)) + 1
	MatchSettings.load_settings()
	var taken: Dictionary = {}   # team -> Array[TankConfig]
	for tank: Tank in tanks:
		if tank.config != null or tank.use_player_config:
			continue
		if not taken.has(tank.team):
			taken[tank.team] = [] as Array[TankConfig]
		var mine: Array[TankConfig] = taken[tank.team]
		tank.config = BotTankPick.pick(data.bot_configs, mine,
				maxi(MatchSettings.team_size, int(size[tank.team])))
		mine.append(tank.config)


func _ready() -> void:
	assert(data != null, "ThunderRoadMode needs ThunderRoadData")
	_rng.randomize()
	_read_route()
	set_physics_process(not NetRole.is_client())
	set_process(NetRole.is_client())


# --- Route ---------------------------------------------------------------------------

func _read_route() -> void:
	var path := get_node_or_null("Route") as Path3D
	if path == null or path.curve == null or path.curve.point_count < 2:
		push_error("ThunderRoad needs a Route (Path3D) with points")
		return
	var total: float = 0.0
	for i: int in path.curve.point_count:
		var p: Vector3 = path.to_global(path.curve.get_point_position(i))
		if not _route.is_empty():
			total += _flat(p - _route[_route.size() - 1]).length()
		_route.append(p)
		_along.append(total)
	var cps := get_node_or_null("Checkpoints")
	if cps != null:
		for child: Node in cps.get_children():
			if child is Node3D:
				_cp_s.append(minf(project((child as Node3D).global_position).x, get_length()))
	_cp_s.sort()
	if _cp_s.is_empty():
		_cp_s.append(total)


func get_length() -> float:
	return _along[_along.size() - 1] if not _along.is_empty() else 0.0


## Where `p` lies by the road: x = metres along it, y = distance from it (flat).
func project(p: Vector3) -> Vector2:
	var best := Vector2(0.0, INF)
	for i: int in _route.size() - 1:
		var a: Vector3 = _route[i]
		var ab: Vector3 = _flat(_route[i + 1] - a)
		var len2: float = ab.length_squared()
		var t: float = clampf(_flat(p - a).dot(ab) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
		if i == _route.size() - 2 and len2 > 0.0:
			# past the road's end it goes on straight (defenders spawn out there)
			t = maxf(t, _flat(p - a).dot(ab) / len2)
		var d: float = _flat(p - (a + ab * t)).length()
		if d < best.y:
			best = Vector2(_along[i] + (_along[i + 1] - _along[i]) * t, d)
	return best


## The road point `s` metres along, moved `across` metres to its right (left < 0).
func point_at(s: float, across: float = 0.0) -> Vector3:
	s = clampf(s, 0.0, get_length())
	var i: int = _segment_at(s)
	var seg: float = _along[i + 1] - _along[i]
	var t: float = (s - _along[i]) / seg if seg > 0.0 else 0.0
	var p: Vector3 = _route[i].lerp(_route[i + 1], t)
	if across == 0.0:
		return p
	return p + _segment_tangent(i).cross(Vector3.UP) * across


## Outline(s) of `role`'s corridor in world (x, z), the area is_inside allows: all within
## half_width of the road, cut square at the defender line (defenders) or at the
## attack limit (attackers), going on straight past the road's end like `project`.
## Clipper may return several polygons (holes where the road loops).
func corridor_outline(role: Role) -> Array[PackedVector2Array]:
	var line := PackedVector2Array()
	var from: float = maxf(get_defender_line_s(), 0.0) if role == Role.DEFEND else 0.0
	var to: float = get_length() + CORRIDOR_RUN_OUT_M if role == Role.DEFEND \
			else get_attack_limit_s()
	if _route.size() < 2 or from >= get_length() or to <= from:
		return []
	var p0: Vector3 = point_at(from)
	line.append(Vector2(p0.x, p0.z))
	for i: int in _route.size():
		if _along[i] > from and _along[i] < to:
			line.append(Vector2(_route[i].x, _route[i].z))
	var end: Vector3 = slot_point(to, 0.0)
	line.append(Vector2(end.x, end.z))
	return Geometry2D.offset_polyline(line, half_width(role), Geometry2D.JOIN_ROUND,
			Geometry2D.END_BUTT)


## The road's direction at `s` (flat unit vector, towards the end).
func tangent_at(s: float) -> Vector3:
	return _segment_tangent(_segment_at(clampf(s, 0.0, get_length())))


func _segment_tangent(i: int) -> Vector3:
	var d: Vector3 = _flat(_route[i + 1] - _route[i])
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## The first segment whose end lies at or beyond `s` (binary search: the minimap and
## the bots ask this hundreds of times a frame).
func _segment_at(s: float) -> int:
	return clampi(_along.bsearch(s, true) - 1, 0, maxi(_along.size() - 2, 0))


# --- Queries -------------------------------------------------------------------------

func has_started() -> bool:
	return _started


func role_of(team: int) -> Role:
	if _round == 0:
		return Role.NONE
	return Role.ATTACK if team == _attack_team else Role.DEFEND


func get_attack_team() -> int:
	return _attack_team


func get_round() -> int:
	return _round


func get_checkpoint_count() -> int:
	return _cp_s.size()


func get_checkpoint_s(index: int) -> float:
	return _cp_s[clampi(index, 0, _cp_s.size() - 1)]


func get_checkpoint_point(index: int) -> Vector3:
	return point_at(get_checkpoint_s(index))


## Index of the checkpoint the attackers go for (== count once all are taken).
func get_next_checkpoint() -> int:
	return _next_cp


func get_front_s() -> float:
	return _front_s


## Where the defenders' corridor begins (s): the front less defender_behind_front_m;
## in a ceasefire pause_defender_back_m past the checkpoint just taken (never past the
## near edge of the next one's zone).
func get_defender_line_s() -> float:
	if data.retreat_instead_of_pause:
		if _next_cp == 0:
			return _front_s - data.defender_behind_front_m
		var past: float = _front_s + data.retreat_line_past_m
		if _next_cp < _cp_s.size():
			past = minf(past, _cp_s[_next_cp] - data.capture_half_length_m)
		return past
	if is_paused():
		var line: float = _front_s + data.pause_defender_back_m
		if _next_cp < _cp_s.size():
			line = minf(line, _cp_s[_next_cp] - data.capture_half_length_m)
		return line
	return _front_s - data.defender_behind_front_m


## How far along the road attackers may go (s): attacker_ahead_of_checkpoint_m past the
## next checkpoint, in a ceasefire pause_attacker_ahead_m past the one just taken.
func get_attack_limit_s() -> float:
	if is_paused() and not data.retreat_instead_of_pause:
		return _front_s + data.pause_attacker_ahead_m
	if _next_cp >= _cp_s.size():
		return get_length() + CORRIDOR_RUN_OUT_M
	return _cp_s[_next_cp] + data.attacker_ahead_of_checkpoint_m


## A checkpoint just fell: nobody fires, the sides part, the next one isn't open yet.
func is_paused() -> bool:
	return _pause_left >= 0.0


func get_pause_left() -> float:
	return _pause_left


## The hand-over after a capture lasts this long (s): retreat_s or pause_s.
func transition_s() -> float:
	return data.retreat_s if data.retreat_instead_of_pause else data.pause_s


## A defender behind the line after a capture but within the corridor's width: its
## last stand (may fire, marked, out after retreat_s).
func is_left_behind(tank: Tank) -> bool:
	if not data.retreat_instead_of_pause or _next_cp == 0 or tank == null:
		return false
	if role_of(tank.team) != Role.DEFEND:
		return false
	var at: Vector2 = project(tank.global_position)
	return at.y <= half_width(Role.DEFEND) and at.x < get_defender_line_s()


func get_capture_progress() -> float:
	return _progress


func is_contested() -> bool:
	return _contested


## The time is up, but the round runs on while attackers are in the zone.
func is_overtime() -> bool:
	return _overtime


func get_time_left() -> float:
	return _time_left


func get_lives() -> int:
	return _lives


func get_wave_left() -> float:
	return _wave_left


func is_waiting_for_wave(tank: Tank) -> bool:
	if NetRole.is_client():
		return bool(_net_tank(tank)[0])
	return _waiting.has(tank)


func get_respawn_left(tank: Tank) -> float:
	if NetRole.is_client():
		return float(_net_tank(tank)[1])
	return float(_def_respawn.get(tank, 0.0))


## Seconds `tank` has been outside its corridor (0 = inside).
func outside_time(tank: Tank) -> float:
	if NetRole.is_client():
		return float(_net_tank(tank)[2])
	return float(_outside.get(tank, 0.0))


func _net_tank(tank: Tank) -> Array:
	var row: Array = _net_tanks.get(tank.net_id if tank != null else -1, [])
	return row if row.size() >= 3 else [false, 0.0, 0.0]


func half_width(role: Role) -> float:
	return data.attacker_half_width_m if role == Role.ATTACK else data.defender_half_width_m


func is_in_break() -> bool:
	return _break_left >= 0.0


func get_break_left() -> float:
	return _break_left


func get_results() -> Array[Dictionary]:
	return _results


## Round 2: checkpoints the attackers must take to win (round 1's count + 1), else -1.
func get_target() -> int:
	if _round < 2 or _results.is_empty():
		return -1
	return int(_results[0]["checkpoints"]) + 1


func is_over() -> bool:
	return _over


func get_winner() -> int:
	return _winner


## The match result is known (in the break after round 2, and once over).
func is_decided() -> bool:
	return _decided


## Every tank's [name, team, knock-outs, losses, assists, points], most points first.
func get_stats() -> Array:
	if NetRole.is_client():
		return _net_stats
	var out: Array = []
	for id: int in _stats:
		var tank := instance_from_id(id) as Tank
		if not is_instance_valid(tank):
			continue
		var row: Array = (_stats[id] as Array).duplicate()
		row[0] = tank.get_display_label()
		row[1] = tank.team
		out.append(row)
	out.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[5]) > float(b[5]) or (float(a[5]) == float(b[5]) and int(a[2]) > int(b[2])))
	return out


## Inside checkpoint `index`'s zone: a rectangle square to the road at the checkpoint,
## capture_half_width_m across it and capture_half_length_m along it.
func is_in_checkpoint(p: Vector3, index: int) -> bool:
	var s: float = get_checkpoint_s(index)
	var d: Vector3 = _flat(p - point_at(s))
	var along: Vector3 = tangent_at(s)
	return absf(d.dot(along)) <= data.capture_half_length_m \
			and absf(d.dot(along.cross(Vector3.UP))) <= data.capture_half_width_m


## The zone's corners (for the maps), going round.
func get_checkpoint_corners(index: int) -> PackedVector3Array:
	var s: float = get_checkpoint_s(index)
	var c: Vector3 = point_at(s)
	var along: Vector3 = tangent_at(s) * data.capture_half_length_m
	var across: Vector3 = tangent_at(s).cross(Vector3.UP) * data.capture_half_width_m
	return PackedVector3Array([c + along + across, c + along - across, c - along - across,
			c - along + across])


## Inside `role`'s corridor: near the road, for defenders ahead of get_defender_line_s
## (a little behind the front), for attackers short of get_attack_limit_s.
func is_inside(p: Vector3, role: Role) -> bool:
	var at: Vector2 = project(p)
	if at.y > half_width(role):
		return false
	if role == Role.DEFEND:
		return at.x >= get_defender_line_s()
	return at.x <= get_attack_limit_s()


# --- Network -------------------------------------------------------------------------

## Host: everything clients show (panel, maps, scoreboard).
func get_net_state() -> Dictionary:
	var per_tank: Dictionary = {}
	for tank: Tank in _team_tanks(0) + _team_tanks(1):
		if tank.net_id <= 0:
			continue
		var row: Array = [_waiting.has(tank), float(_def_respawn.get(tank, 0.0)),
				float(_outside.get(tank, 0.0))]
		if row[0] or row[1] > 0.0 or row[2] > 0.0:
			per_tank[tank.net_id] = row
	return {
		"go": _started, "r": _round, "at": _attack_team, "cp": _next_cp, "f": _front_s,
		"p": _progress, "c": _contested, "ot": _overtime, "t": _time_left, "l": _lives, "w": _wave_left,
		"b": _break_left, "res": _results, "over": _over, "win": _winner, "dec": _decided,
		"pz": _pause_left,
		"st": get_stats(), "tk": per_tank,
	}


## Client: takes over the host's state, with the same signals as on the host.
func apply_net_state(state: Dictionary) -> void:
	_started = state.get("go", _started)
	var round_number: int = state.get("r", _round)
	var next_cp: int = state.get("cp", _next_cp)
	var break_left: float = state.get("b", _break_left)
	var results: Array = state.get("res", [])
	_attack_team = state.get("at", _attack_team)
	_front_s = state.get("f", _front_s)
	_progress = state.get("p", _progress)
	_contested = state.get("c", _contested)
	_overtime = state.get("ot", _overtime)
	_time_left = state.get("t", _time_left)
	_lives = state.get("l", _lives)
	_wave_left = state.get("w", _wave_left)
	var pause_left: float = state.get("pz", _pause_left)
	_decided = state.get("dec", _decided)
	_winner = state.get("win", _winner)
	_net_stats = (state.get("st", []) as Array).duplicate(true)
	_net_tanks = (state.get("tk", {}) as Dictionary).duplicate(true)
	if round_number != _round:
		_round = round_number
		_next_cp = next_cp
		_results.clear()
		for r: Variant in results:
			_results.append(r as Dictionary)
		_break_left = break_left
		round_started.emit(_round, _attack_team)
		return
	while _next_cp < next_cp:
		checkpoint_taken.emit(_next_cp)
		_next_cp += 1
	_next_cp = next_cp
	var was_paused: bool = _pause_left >= 0.0
	_pause_left = pause_left
	if pause_left >= 0.0 and not was_paused:
		pause_started.emit(_next_cp - 1)
	elif pause_left < 0.0 and was_paused:
		pause_ended.emit(_next_cp)
	var finished: bool = results.size() > _results.size()
	_results.clear()
	for r: Variant in results:
		_results.append(r as Dictionary)
	_break_left = break_left
	if finished:
		round_over.emit(_round, _results[_results.size() - 1])
		if not _decided:
			_net_reset_left = NET_RESET_DELAY_S   # the host cleared its map for the next round
	var over: bool = state.get("over", false)
	if over and not _over:
		_over = true
		match_over.emit(_winner)


## Client: the clocks run on between the host's packets.
func _process(delta: float) -> void:
	if _net_reset_left >= 0.0:
		_net_reset_left -= delta
		if _net_reset_left < 0.0:
			_reset_map()
	if not _started or _over:
		return
	if _break_left >= 0.0:
		_break_left = maxf(_break_left - delta, 0.0)
		return
	if _pause_left >= 0.0:
		_pause_left = maxf(_pause_left - delta, 0.0)
	else:
		_time_left = maxf(_time_left - delta, 0.0)
		_wave_left = maxf(_wave_left - delta, 0.0)
	for id: Variant in _net_tanks:
		var row: Array = _net_tanks[id]
		row[1] = maxf(float(row[1]) - delta, 0.0)
		if float(row[2]) > 0.0:
			row[2] = float(row[2]) + delta


## Host (NetGame): where a tank joining now first goes: its side's spawn in a running
## round, else the start of the road for its team (the round start places it anyway).
func spawn_for_new(team: int, tank: Tank) -> Transform3D:
	if _round == 0 or _over:
		var s: float = maxf(data.start_front_m - data.attacker_spawn_back_m, 30.0)
		if team != 0:
			return _defender_start(tank)
		return _free_slot(s, tangent_at(s), tank)
	if team == _attack_team:
		return _attacker_spawn(tank)
	return _defender_spawn(tank)


## ThunderRoadBots: the first round waits until release_start() (teams being filled).
func hold_start() -> void:
	_start_holds += 1


func release_start() -> void:
	_start_holds = maxi(_start_holds - 1, 0)


# --- Match ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _route.size() < 2:
		return
	if Ticks.due(_connect_clock, delta, RULES_HZ) or not _started:
		_connect_new_tanks()
	if not _started:
		if _start_holds > 0:
			return
		_started = true
		_start_round(1)
		return
	if _break_left >= 0.0:
		_break_left -= delta
		if _break_left < 0.0 and not _over:
			if _round == 1:
				_start_round(2)
			else:
				_end_match()
		return
	if _over:
		return
	var paused: bool = _update_pause(delta)
	if not paused:
		_time_left = maxf(_time_left - delta, 0.0)
		_capture_dt += delta
		if Ticks.due(_capture_clock, delta, RULES_HZ):
			_update_capture(_capture_dt)
			_capture_dt = 0.0
		_update_waves(delta)
	_update_defender_respawns(delta)
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_INTERVAL_S
		_check_corridors(CHECK_INTERVAL_S)
	if _next_cp >= _cp_s.size():
		_end_round()
	# is_paused() again: a capture this tick starts the pause, and the old clock (0 in
	# overtime) must not switch overtime back on (it stayed on the HUD, 2026-11-19).
	elif not is_paused() and _time_left <= 0.0 and _overtime_over(delta):
		_award_hold()
		_end_round()
	elif _lives <= 0 and _alive_count(_attack_team) == 0:
		_award_hold()
		_end_round()


## The ceasefire after a capture: counts down, then the next checkpoint opens with a
## full clock. True while it lasts.
func _update_pause(delta: float) -> bool:
	if _pause_left < 0.0:
		return false
	_pause_left -= delta
	if _pause_left >= 0.0:
		return true
	_pause_left = -1.0
	_time_left = data.checkpoint_time_s
	_wave_left = data.wave_interval_s
	_overtime = false
	for tank: Tank in _team_tanks(0) + _team_tanks(1):
		if not tank.is_knocked_out() and is_inside(tank.global_position, role_of(tank.team)):
			tank.fire_blocked = false
	pause_ended.emit(_next_cp)
	return false


## Starts round `number`: sets it up (unless the break before it already did) and lets
## the tanks go.
func _start_round(number: int) -> void:
	if _prepared != number:
		_setup_round(number)
	_prepared = 0
	_break_left = -1.0
	_round = number
	for tank: Tank in _team_tanks(0) + _team_tanks(1):
		tank.move_blocked = false
		if tank.is_knocked_out():   # abandoned during the countdown
			_place(tank, _attacker_spawn(tank) if tank.team == _attack_team else _defender_spawn(tank))
	round_started.emit(number, _attack_team)


## Round `number`'s state, the tanks at their sides' starts (repaired) and, after round
## 1, a fresh map. Between the rounds this runs as the break starts, so the countdown
## is spent at the new start, standing still (Tank.move_blocked).
func _setup_round(number: int) -> void:
	_prepared = number
	_attack_team = 0 if number == 1 else 1
	_next_cp = 0
	_front_s = data.start_front_m
	_progress = 0.0
	_contested = false
	_attackers_in = 0
	_overtime = false
	_pause_left = -1.0
	_time_left = data.checkpoint_time_s
	_lives = data.start_lives_per_tank * _team_tanks(_attack_team).size() + data.start_lives_extra
	_wave_left = data.wave_interval_s
	_waiting.clear()
	_def_respawn.clear()
	_outside.clear()
	_mark_left.clear()
	for tank: Tank in _team_tanks(_attack_team):
		_place(tank, _attacker_spawn(tank))
	for tank: Tank in _team_tanks(1 - _attack_team):
		_place(tank, _defender_start(tank))
	if number > 1:
		_reset_map()   # after the tanks left their wrecks


## A fresh map for the next round: wrecks (thrown turrets too), mines and smoke go,
## felled trees stand again.
func _reset_map() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"wrecks"):
		node.queue_free()
	for node: Node in get_tree().get_nodes_in_group(Mine.GROUP):
		(node as Mine).remove()
	for node: Node in get_tree().get_nodes_in_group(SmokeCloud.GROUP):
		node.queue_free()
	var root: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	var fields: Array[TreeField] = []
	for node: Node in root.find_children("*", "", true, false):
		if node is TreeField:
			fields.append(node)
	for field: TreeField in fields:   # restoring frees falling trees: not while listing
		field.restore_all()
	map_reset.emit()


func _end_round() -> void:
	_overtime = false
	_pause_left = -1.0
	var result := {
		"attack_team": _attack_team,
		"checkpoints": _next_cp,
		"all": _next_cp >= _cp_s.size(),
		"time_left": _time_left,
	}
	_results.append(result)
	if _round >= 2:
		_decide_winner()
	# A pause to read the result: nobody fires until the next round places the tanks.
	for tank: Tank in _team_tanks(0) + _team_tanks(1):
		tank.fire_blocked = true
	round_over.emit(_round, result)
	_break_left = data.round_break_s
	if not _decided:
		# Sides swap now: everyone to the next round's start, locked for the countdown.
		_setup_round(_round + 1)
		for tank: Tank in _team_tanks(0) + _team_tanks(1):
			tank.move_blocked = true
			tank.fire_blocked = true


func _end_match() -> void:
	_over = true
	if not _decided:
		_decide_winner()
	match_over.emit(_winner)


func _decide_winner() -> void:
	_decided = true
	_winner = -1
	if _results.size() >= 2:
		var a: Dictionary = _results[0]
		var b: Dictionary = _results[1]
		if int(a["checkpoints"]) != int(b["checkpoints"]):
			_winner = int(a["attack_team"]) if int(a["checkpoints"]) > int(b["checkpoints"]) \
					else int(b["attack_team"])
		elif bool(a["all"]) and float(a["time_left"]) != float(b["time_left"]):
			_winner = int(a["attack_team"]) if float(a["time_left"]) > float(b["time_left"]) \
					else int(b["attack_team"])


func _update_capture(delta: float) -> void:
	if _next_cp >= _cp_s.size():
		return
	var in_attack: Array[Tank] = []
	var in_defence: Array[Tank] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or tank.is_knocked_out() or (tank.team != 0 and tank.team != 1):
			continue
		if not is_in_checkpoint(tank.global_position, _next_cp):
			continue
		if tank.team == _attack_team:
			in_attack.append(tank)
		else:
			in_defence.append(tank)
	var attackers: int = in_attack.size()
	var defenders: int = in_defence.size()
	# Teamwork pays: attackers pushing the capture, defenders standing in the way.
	if attackers > defenders:
		for tank: Tank in in_attack:
			_points_add(tank, data.capture_points_per_s * delta, "")
	if attackers > 0:
		for tank: Tank in in_defence:
			_points_add(tank, data.defend_points_per_s * delta, "")
	# More attackers than defenders there take it, the faster the bigger the edge.
	_attackers_in = attackers
	_contested = defenders > 0 and attackers > 0 and attackers <= defenders
	var rate: float = 1.0 / maxf(data.capture_time_s, 0.1)
	if attackers > defenders:
		_progress += rate * minf(float(attackers - defenders), data.capture_speed_max) * delta
	elif attackers == 0:
		_progress = maxf(_progress - rate * data.capture_decay_factor * delta, 0.0)
	if _progress >= 1.0:
		for tank: Tank in in_attack:
			_points_add(tank, data.capture_points, "capture")
		_take_checkpoint()


func _take_checkpoint() -> void:
	var index: int = _next_cp
	_front_s = _cp_s[index]
	_next_cp += 1
	_progress = 0.0
	_contested = false
	_overtime = false
	_attackers_in = 0
	_lives += data.lives_per_capture
	checkpoint_taken.emit(index)
	if _next_cp < _cp_s.size():
		_wave()
		if transition_s() > 0.0:
			_pause_left = transition_s()
			_check_corridors(0.0)   # the shrunk corridors apply at once
			pause_started.emit(index)
		else:
			_time_left = data.checkpoint_time_s


## The attackers ran out of time or lives short of the checkpoint: every living
## defender gets hold_points.
func _award_hold() -> void:
	if _next_cp >= _cp_s.size():
		return
	for tank: Tank in _team_tanks(1 - _attack_team):
		if not tank.is_knocked_out():
			_points_add(tank, data.hold_points, "hold")


## The time is up: true when the round may end. While a living attacker is in the
## zone it runs on (overtime), and ends overtime_grace_s after the last one is gone.
func _overtime_over(delta: float) -> bool:
	if _attackers_in > 0 and _next_cp < _cp_s.size():
		_overtime = true
		_overtime_grace = data.overtime_grace_s
		return false
	if _overtime and _overtime_grace > 0.0:
		_overtime_grace -= delta
		return false
	return true


func _update_waves(delta: float) -> void:
	_wave_left -= delta
	if _wave_left <= 0.0:
		_wave()


## Knocked-out attackers come back together, a life each, while lives last.
func _wave() -> void:
	_wave_left = data.wave_interval_s
	for tank: Tank in _waiting.duplicate():
		if _lives <= 0:
			break
		if not is_instance_valid(tank):
			_waiting.erase(tank)
			continue
		_lives -= 1
		_waiting.erase(tank)
		_place(tank, _attacker_spawn(tank))


func _update_defender_respawns(delta: float) -> void:
	for tank: Variant in _def_respawn.keys():
		if not is_instance_valid(tank):
			_def_respawn.erase(tank)
			continue
		var left: float = float(_def_respawn[tank]) - delta
		if left > 0.0:
			_def_respawn[tank] = left
			continue
		_def_respawn.erase(tank)
		_place(tank, _defender_spawn(tank))


func _on_knocked_out(tank: Tank) -> void:
	if _round == 0 or _over or _break_left >= 0.0:
		return
	_stat_add(tank, 3)
	_outside.erase(tank)
	if tank.team == _attack_team:
		if not _waiting.has(tank):
			_waiting.append(tank)
	else:
		_def_respawn[tank] = data.defender_respawn_s


## A knock-out counts for the killer (fire and ammo included), an assist for every other
## enemy that damaged the tank this life.
func _on_eliminated(killer: Tank, assists: Array[Tank]) -> void:
	if _round == 0 or _over or _break_left >= 0.0:
		return
	if killer != null and is_instance_valid(killer):
		_stat_add(killer, 2)
		_points_add(killer, data.kill_points, "kill")
	for t: Tank in assists:
		if is_instance_valid(t):
			_stat_add(t, 4)
			_points_add(t, data.assist_points, "assist")


func _stat_add(tank: Tank, field: int) -> void:
	var row: Array = _stats.get(tank.get_instance_id(), [])
	if not row.is_empty():
		row[field] = int(row[field]) + 1


## Points for `tank` (stats column 5); `kind` "" = a trickle (capture or defence time),
## not announced.
func _points_add(tank: Tank, points: float, kind: String) -> void:
	var row: Array = _stats.get(tank.get_instance_id(), [])
	if row.is_empty() or points <= 0.0:
		return
	row[5] = float(row[5]) + points
	if kind != "":
		points_scored.emit(tank, points, kind)


## Outside the corridor: no fire at once, a mark on the other team's maps every
## outside_mark_s, knocked out (nobody's kill) after outside_knockout_s; a defender left
## behind after a capture (is_left_behind) may fire, is marked every retreat_mark_s and
## goes after retreat_s. In a pause
## nobody fires if `pause_blocks_fire`.
func _check_corridors(dt: float) -> void:
	var paused: bool = _pause_blocks_fire()
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or (tank.team != 0 and tank.team != 1):
			continue
		if tank.is_knocked_out():
			tank.fire_blocked = false
			continue
		var role: Role = role_of(tank.team)
		if is_inside(tank.global_position, role):
			_outside.erase(tank)
			_mark_left.erase(tank)
			tank.fire_blocked = paused
			continue
		var last_stand: bool = is_left_behind(tank)
		tank.fire_blocked = paused if last_stand else true
		var out: float = float(_outside.get(tank, 0.0)) + dt
		_outside[tank] = out
		var mark: float = float(_mark_left.get(tank, 0.0)) - dt
		if mark <= 0.0:
			mark = data.retreat_mark_s if last_stand else data.outside_mark_s
			_mark_for_enemies(tank)
		_mark_left[tank] = mark
		if out >= (data.retreat_s if last_stand else data.outside_knockout_s):
			_outside.erase(tank)
			tank.knock_out_by_rule()


## Shows `tank` on the other team's maps: a spot mark from one of its living tanks.
func _mark_for_enemies(tank: Tank) -> void:
	for other: Tank in _team_tanks(1 - tank.team):
		if not other.is_knocked_out():
			other.spotted.emit(tank, tank.global_position)
			return


# --- Spawns --------------------------------------------------------------------------

func _attacker_spawn(tank: Tank) -> Transform3D:
	var s: float = maxf(_front_s - data.attacker_spawn_back_m, 30.0)
	return _free_slot(s, tangent_at(s), tank)


## Past the next checkpoint by `ahead` checkpoints (-1: defender_spawn_checkpoints).
func _defender_spawn(tank: Tank, ahead: int = -1) -> Transform3D:
	if ahead < 0:
		ahead = data.defender_spawn_checkpoints
	var index: int = mini(_next_cp + ahead, _cp_s.size() - 1)
	var s: float = maxf(_cp_s[index] + data.defender_spawn_beyond_m,
			_cp_s[mini(_next_cp, _cp_s.size() - 1)] + data.defender_spawn_min_ahead_m)
	return _free_slot(s, -tangent_at(s), tank)


## Round start: in the first checkpoint's zone (defender_start_in_zone), else a
## respawn's spawn.
func _defender_start(tank: Tank) -> Transform3D:
	if not data.defender_start_in_zone or _cp_s.is_empty():
		return _defender_spawn(tank)
	# Slots go in rows away from the attackers from here: the zone's near half and on.
	var s: float = _cp_s[0] - data.capture_half_length_m * 0.5
	return _free_slot(s, -tangent_at(s), tank)


## A free, flat slot near the road at `s` (rows going back along `facing`), facing it.
## Fallback spawn: rows tried further back along the road when no row had open ground.
const FALLBACK_STEPS: int = 20
## Rows tried forward of `s` when none behind it fit (a route starting outside the map edge).
const FORWARD_ROWS: int = 8

func _free_slot(s: float, facing: Vector3, tank: Tank) -> Transform3D:
	var back: float = -signf(facing.dot(tangent_at(s)))
	var first := Transform3D()
	var found_first: bool = false
	var first_free: bool = false
	# Rows back from `s`, then (a start outside the map edge, every row blocked) rows
	# forward from it.
	var offsets: Array[float] = []
	for row: int in SLOT_ROWS:
		offsets.append(back * row * SLOT_ROW_M)
	for row: int in range(1, FORWARD_ROWS + 1):
		offsets.append(-back * row * SLOT_ROW_M)
	for offset: float in offsets:
		for across: float in SLOT_ACROSS_M:
			var p: Vector3 = slot_point(s + offset, across)
			var hit: Dictionary = KothMode.ground_hit(get_world_3d(), p)
			if hit.is_empty() or not (hit["collider"] is Terrain3D):
				continue   # nothing there, or a roof, a bridge, a stone: never spawn on top of it
			var at: Vector3 = (hit["position"] as Vector3) + Vector3.UP * SPAWN_LIFT_M
			var xform := Transform3D(Basis.looking_at(facing, Vector3.UP), at)
			# Nothing fit: at least not inside a wreck, and never inside another tank
			# (ten tanks in one spot blew apart at 48 m/s, Orange 2026-11-19).
			var free: bool = not _tank_near(at, tank)
			if not _wreck_near(at) and (not found_first or (free and not first_free)):
				first = xform
				found_first = true
				first_free = free
			if _slot_ok(hit, tank):
				return xform
	if not found_first:
		# No open ground in the rows: walk back towards the fight along the road until
		# there is terrain (off the map past the road's end, or houses all round).
		var at: Vector3 = point_at(minf(s, get_length()), 0.0)
		for step: int in FALLBACK_STEPS:
			var hit: Dictionary = KothMode.ground_hit(get_world_3d(),
					slot_point(s - back * (step + 1) * SLOT_ROW_M, 0.0))
			if not hit.is_empty() and hit["collider"] is Terrain3D:
				at = hit["position"]
				break
		first = Transform3D(Basis.looking_at(facing, Vector3.UP), at + Vector3.UP * SPAWN_LIFT_M)
	return first


## point_at, but past the road's ends it goes on straight along the end's direction.
func slot_point(s: float, across: float) -> Vector3:
	var length: float = get_length()
	if s <= length:
		return point_at(s, across)
	var t: Vector3 = tangent_at(length)
	return point_at(length, 0.0) + t * (s - length) + t.cross(Vector3.UP) * across


func _wreck_near(at: Vector3) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"wrecks"):
		var wreck := node as Node3D
		if wreck != null and wreck.global_position.distance_to(at) < WRECK_CLEAR_M:
			return true
	return false


func _tank_near(at: Vector3, tank: Tank) -> bool:
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var other := node as Tank
		if other != null and other != tank and other.global_position.distance_to(at) < SLOT_CLEAR_M:
			return true
	return false


func _slot_ok(hit: Dictionary, tank: Tank) -> bool:
	var at: Vector3 = hit["position"]
	if (hit["normal"] as Vector3).angle_to(Vector3.UP) > deg_to_rad(KothMode.SPAWN_MAX_SLOPE_DEG):
		return false
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	if map != null and map.is_blocked(at):
		return false
	if _tank_near(at, tank):
		return false
	var box := BoxShape3D.new()
	box.size = KothMode.SPAWN_BOX_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = 1
	query.transform = Transform3D(Basis(), at + Vector3.UP * (KothMode.SPAWN_BOX_M.y * 0.5
			+ KothMode.SPAWN_BOX_CLEARANCE_M))
	if tank != null:
		query.exclude = [tank.get_rid()]
	for h: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var collider: Object = h["collider"]
		if not (collider is Terrain3D) and not (collider is Tank and collider == tank):
			return false
	return true


func _place(tank: Tank, xform: Transform3D) -> void:
	KothMode.place_tank(tank, xform)
	tank.repair()
	tank.fire_blocked = _pause_blocks_fire()
	tank_placed.emit(tank)


func _pause_blocks_fire() -> bool:
	return is_paused() and data.pause_blocks_fire and not data.retreat_instead_of_pause


# --- Helpers -------------------------------------------------------------------------

func _connect_new_tanks() -> void:
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or _connected.has(tank.get_instance_id()):
			continue
		_connected[tank.get_instance_id()] = true
		_stats[tank.get_instance_id()] = _carried.get(tank.get_instance_id(),
				[tank.get_display_label(), tank.team, 0, 0, 0, 0.0])
		_carried.erase(tank.get_instance_id())
		tank.knocked_out.connect(_on_knocked_out.bind(tank))
		tank.eliminated.connect(_on_eliminated)
		# A tank added mid-round (a bot filling a team) waits for its side's respawn.
		if _round > 0 and _break_left < 0.0 and not _over:
			if tank.team == _attack_team:
				_place(tank, _attacker_spawn(tank))
			else:
				_place(tank, _defender_spawn(tank))


## A player left a live tank for another type mid-fight (TankSwitch): a loss, like
## abandoning it; nobody scores.
func count_loss(tank: Tank) -> void:
	var row: Array = _stats.get(tank.get_instance_id(), [])
	if not row.is_empty():
		row[3] = int(row[3]) + 1


## A player's new tank (other type or team, TankSwitch / NetGame) keeps their stats.
## Call before the new tank's first physics frame.
func carry_stats(from: Tank, to: Tank) -> void:
	var id: int = from.get_instance_id()
	if _stats.has(id):
		var row: Array = _stats[id]
		while row.size() < 6:
			row.append(0.0)
		_carried[to.get_instance_id()] = row
		_stats.erase(id)


func _team_tanks(team: int) -> Array[Tank]:
	var out: Array[Tank] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank != null and tank.team == team and not tank.is_queued_for_deletion():
			out.append(tank)
	return out


func _alive_count(team: int) -> int:
	var n: int = 0
	for tank: Tank in _team_tanks(team):
		if not tank.is_knocked_out():
			n += 1
	return n


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
