class_name FreeFight
extends Node
## Free fight: the players (team 0, co-op) against waves of bots. The players start at
## a random spot in a big circle round the map's centre. A wave (FreeFightData) spawns
## wave_distance_*_m away, in cover, preferably somewhere no player can see, and
## stands its ground (DEFEND; the players' maps show its circle) until one of its crews
## spots a player or is hit: then the whole wave hears of it and attacks (ATTACK), each
## bot driving to firing spots closer and closer to the nearest player it knows of.
## Beaten (every bot knocked out), the next wave comes after wave_gap_s: one bot more
## every second round, easy and hard crews in turn, all a bit better each round, more
## bots with more players. Knocked-out players come back when the wave is beaten,
## beside a living teammate; with every player out at once the match is over.
## Also the bot director for MatchLobby and NetGame (make_room / refill / spawn_for_new).
## Host/offline runs it; clients take its state (get_net_state / apply_net_state).

signal match_over(rounds_cleared: int)
signal wave_started(round: int)
signal wave_cleared(round: int)
signal wave_attacking

enum Phase { WAITING, DEFEND, ATTACK, GAP, OVER }

const TANK_SCENE_PATH: String = "res://scenes/tank/tank.tscn"
const BOT_TANK_DATA: String = "res://data/tanks/test_medium.tres"
## Before the first wave, once a player is in the map (s).
const FIRST_WAVE_DELAY_S: float = 5.0
## Spawn spots tried for the players' start and for a teammate beside a living player.
const START_TRIES: int = 40
const BESIDE_M: float = 14.0
## A wave bot's spot that isn't open ground (a roof, a stone, trees): look round it on
## this many rings, this far apart, in this many directions.
const OPEN_NEAR_RINGS: int = 4
const OPEN_NEAR_STEP_M: float = 10.0
const OPEN_NEAR_DIRECTIONS: int = 8
## A wave's centre counts as seen by a player if a ray from his eye gets this close to
## a point this high over it (m).
const SEEN_SLACK_M: float = 6.0
const SEEN_HEIGHT_M: float = 2.5
## Look spread of the defenders' positions round the players' centre (m).
const DEFEND_LOOK_SPREAD_M: float = 150.0
## An attacker replans when the player it goes for has moved this far (m).
const ATTACK_REPLAN_M: float = 60.0

@export var data: FreeFightData

static var instance: FreeFight

var _phase: Phase = Phase.WAITING
var _round: int = 0   # rounds started so far (the one going on is _round - 1)
var _cleared: int = 0
var _gap_left: float = -1.0
var _centre: Vector3 = Vector3.ZERO
var _hard: bool = false
var _start: Transform3D = Transform3D.IDENTITY
var _has_start: bool = false
var _wave: Array[BotController] = []
var _old: Array[BotController] = []   # beaten wave's bots, taken away at the next wave
var _range: Dictionary = {}   # BotController -> current attack range (m)
var _think: Dictionary = {}   # BotController -> seconds until the next look
var _planned: Dictionary = {}   # BotController -> the player position its order was for
var _last_seen: Dictionary = {}   # player Tank -> last position any wave crew knew of
var _stats: Dictionary = {}   # tank instance id -> [name, team, KO, lost, assists]
var _carried: Dictionary = {}
var _connected: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _serial: int = 0
# Client copies of the host's state.
var _net_alive: int = 0
var _net_stats: Array = []


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	_rng.randomize()
	# The map's own bots don't play here (before NetGame or the lobby look at them).
	var enemies: Node = get_parent().get_node_or_null("Enemies")
	# (The scene root is still adding children: empty the node instead of removing it.)
	if enemies != null:
		for child: Node in enemies.get_children():
			enemies.remove_child(child)
			child.queue_free()
	if NetRole.is_client():
		set_physics_process(false)
		return
	_start = _find_start()
	_has_start = true


# --- State for the HUD (host and clients) -------------------------------------------

func get_phase() -> Phase:
	return _phase


func is_over() -> bool:
	return _phase == Phase.OVER


## The wave going on (1 = the first), 0 before the first.
func get_wave_number() -> int:
	return _round


func is_hard() -> bool:
	return _hard


## Waves beaten so far.
func get_cleared() -> int:
	return _cleared


## The wave's circle shows on the players' maps while it holds (DEFEND).
func is_defending() -> bool:
	return _phase == Phase.DEFEND


func get_centre() -> Vector3:
	return _centre


func get_radius() -> float:
	return data.wave_radius_m


## Seconds until the next wave (WAITING with a player in, GAP), else -1.
func get_gap_left() -> float:
	return _gap_left


## Bots of the wave still fighting.
func get_alive() -> int:
	if NetRole.is_client():
		return _net_alive
	var n: int = 0
	for bot: BotController in _wave:
		if is_instance_valid(bot) and is_instance_valid(bot.tank) and not bot.tank.is_knocked_out():
			n += 1
	return n


## Rows [name, team, KO, lost, assists] of the players (and bots).
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
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	return out


func get_net_state() -> Dictionary:
	return {"p": _phase, "r": _round, "h": _hard, "cl": _cleared, "g": _gap_left,
			"c": _centre, "a": get_alive(), "st": get_stats()}


## Client: takes over the host's state, with the same signals.
func apply_net_state(state: Dictionary) -> void:
	var phase: Phase = int(state.get("p", _phase)) as Phase
	var round_: int = state.get("r", _round)
	_hard = state.get("h", _hard)
	_cleared = state.get("cl", _cleared)
	_gap_left = state.get("g", _gap_left)
	_centre = state.get("c", _centre)
	_net_alive = state.get("a", 0)
	_net_stats = (state.get("st", []) as Array).duplicate(true)
	if round_ != _round:
		_round = round_
		wave_started.emit(_round)
	if phase != _phase:
		var was: Phase = _phase
		_phase = phase
		if phase == Phase.ATTACK:
			wave_attacking.emit()
		elif phase == Phase.GAP and (was == Phase.DEFEND or was == Phase.ATTACK):
			wave_cleared.emit(_round)
		elif phase == Phase.OVER:
			match_over.emit(_cleared)


# --- Director API (MatchLobby, NetGame) -------------------------------------------

## No bots ever make room for a player: the players' side has none.
func make_room(_team: int) -> Tank:
	return null


func refill() -> void:
	pass


## Where a new or returning player tank starts: beside a living teammate, else the
## match's random start.
func spawn_for_new(team: int, tank: Tank) -> Transform3D:
	for other: Tank in _players():
		if other != tank and other.team == team and not other.is_knocked_out():
			return _beside(other)
	if not _has_start:
		_start = _find_start()
		_has_start = true
	return _start


## A player's new tank (other type, TankSwitch / NetGame) keeps their stats.
func carry_stats(from: Tank, to: Tank) -> void:
	var id: int = from.get_instance_id()
	if _stats.has(id):
		_carried[to.get_instance_id()] = _stats[id]
		_stats.erase(id)


func count_loss(tank: Tank) -> void:
	var row: Array = _stats.get(tank.get_instance_id(), [])
	if not row.is_empty():
		row[3] = int(row[3]) + 1


# --- Match flow -----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_connect_new_tanks()
	_drop_freed()
	match _phase:
		Phase.WAITING:
			if _living_players().is_empty():
				return
			if _gap_left < 0.0:
				_gap_left = FIRST_WAVE_DELAY_S
			_gap_left -= delta
			if _gap_left <= 0.0:
				_start_wave()
		Phase.GAP:
			_gap_left -= delta
			if _gap_left <= 0.0:
				_start_wave()
		Phase.DEFEND, Phase.ATTACK:
			if _players().size() > 0 and _living_players().is_empty():
				_end_match()
				return
			if get_alive() == 0:
				_on_wave_beaten()
				return
			if _phase == Phase.ATTACK:
				_update_attack(delta)


func _start_wave() -> void:
	_gap_left = -1.0
	for bot: BotController in _old:
		_remove_bot(bot)
	_old.clear()
	_hard = _round % 2 == 1
	var players: int = maxi(_players().size(), 1)
	var count: int = ceili((data.start_count + _round / 2) * (1.0 + data.extra_player_share * (players - 1)))
	var crew: BotData = _crew_for(_round, _hard)
	var pool: Array[TankConfig] = data.hard_configs if _hard else data.easy_configs
	_centre = _find_wave_centre()
	var toward: Vector3 = _players_centre() - _centre
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 1.0 else Vector3.FORWARD
	var placed := PackedVector3Array()
	for i: int in count:
		var spot: Vector3 = _defend_spot(toward, placed)
		placed.append(spot)
		_add_bot(spot, toward, crew, pool)
	_round += 1
	_phase = Phase.DEFEND
	_last_seen.clear()
	wave_started.emit(_round)


func _on_wave_beaten() -> void:
	_cleared += 1
	_phase = Phase.GAP
	_gap_left = data.wave_gap_s
	_old.append_array(_wave)
	_wave.clear()
	_range.clear()
	_think.clear()
	_planned.clear()
	# Fallen players come back now, beside one who made it.
	for tank: Tank in _players():
		if tank.is_knocked_out():
			KothMode.place_tank(tank, spawn_for_new(tank.team, tank))
			tank.repair()
	wave_cleared.emit(_round)


func _end_match() -> void:
	_phase = Phase.OVER
	_gap_left = -1.0
	for bot: BotController in _wave:
		if is_instance_valid(bot):
			var none: Array[Vector3] = []
			bot.order_move(none, 0.0)
	match_over.emit(_cleared)


## A crew of `round_`: the easy or hard BotData with spot times and gun errors scaled
## down by creep_per_round per round (not below creep_floor).
func _crew_for(round_: int, hard: bool) -> BotData:
	var base: BotData = data.hard_bot if hard else data.easy_bot
	var crew: BotData = base.duplicate() as BotData
	var f: float = maxf(pow(data.creep_per_round, round_), data.creep_floor)
	crew.spot_time_open_s = base.spot_time_open_s * f
	crew.spot_time_closed_s = base.spot_time_closed_s * f
	crew.lay_error_mrad = base.lay_error_mrad * f
	crew.range_error_start = base.range_error_start * f
	crew.lead_error = base.lead_error * f
	crew.aim_settle_s = base.aim_settle_s * f
	return crew


# --- Bots --------------------------------------------------------------------------

func _add_bot(at: Vector3, toward: Vector3, crew: BotData, pool: Array[TankConfig]) -> void:
	var tank: Tank = (load(TANK_SCENE_PATH) as PackedScene).instantiate()
	_serial += 1
	tank.name = "WaveBot%d" % _serial
	tank.team = data.bot_team
	tank.data = load(BOT_TANK_DATA)
	if not pool.is_empty():
		tank.config = pool[_rng.randi() % pool.size()]
	var parent: Node = get_parent()
	parent.add_child(tank)
	KothMode.place_tank(tank, Transform3D(Basis.looking_at(toward, Vector3.UP), at))
	var bot := BotController.new()
	bot.name = tank.name + "Controller"
	bot.bot_data = crew
	bot.tank = tank
	bot.respawn_delay_s = 0.0   # beaten is beaten: no repair on the spot
	parent.add_child(bot)
	bot.contact.connect(_on_contact.bind(bot))
	_wave.append(bot)
	var game: NetGame = NetSession.instance.game if NetRole.is_host() else null
	if game != null:
		game.add_bot_tank(tank)


## Takes a bot and its tank (and squad) out of the match; its wreck stays.
func _remove_bot(bot: BotController) -> void:
	if not is_instance_valid(bot):
		return
	var tank: Tank = bot.tank
	bot.queue_free()
	if not is_instance_valid(tank):
		return
	var game: NetGame = NetSession.instance.game if NetRole.is_host() else null
	if game != null:
		game.remove_tank(tank)
	else:
		tank.leave_wreck()
		if tank.squad != null and is_instance_valid(tank.squad):
			tank.squad.queue_free()
		tank.queue_free()


func _drop_freed() -> void:
	for i: int in range(_wave.size() - 1, -1, -1):
		if not is_instance_valid(_wave[i]) or not is_instance_valid(_wave[i].tank):
			_wave.remove_at(i)


## A crew of the wave spotted a player (or was hit): the whole wave hears of it and,
## if it was holding, attacks.
func _on_contact(enemy: Tank, at: Vector3, from: BotController) -> void:
	if _phase != Phase.DEFEND and _phase != Phase.ATTACK:
		return
	if enemy != null:
		_last_seen[enemy] = at
	for bot: BotController in _wave:
		if bot != from and is_instance_valid(bot):
			bot.share_contact(enemy, at)
	if _phase == Phase.DEFEND:
		_phase = Phase.ATTACK
		for bot: BotController in _wave:
			_range[bot] = data.attack_range_m
			_think[bot] = _rng.randf_range(0.0, 1.0)   # not all searching on one frame
		wave_attacking.emit()


## Each attacker now and then: to a firing spot attack range from the nearest player
## it knows of (or the wave heard of last), closer each time it gets there.
func _update_attack(delta: float) -> void:
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	for bot: BotController in _wave:
		if not is_instance_valid(bot) or bot.tank.is_knocked_out() or bot.is_relocating():
			continue
		_think[bot] = float(_think.get(bot, 0.0)) - delta
		if float(_think[bot]) > 0.0:
			continue
		_think[bot] = data.attack_think_s
		var here: Vector3 = bot.tank.global_position
		var prey_at := Vector3.INF
		var best: float = INF
		var known: Dictionary = bot.get_known_enemies(data.attack_memory_s)
		for key: Variant in _last_seen:
			if is_instance_valid(key) and not known.has(key) and not (key as Tank).is_knocked_out():
				known[key] = _last_seen[key]
		for other: Variant in known:
			var d: float = here.distance_to(known[other])
			if d < best:
				best = d
				prey_at = known[other]
		if prey_at == Vector3.INF:
			continue
		var r: float = float(_range.get(bot, data.attack_range_m))
		if bot.has_target_in_sight() and best <= r * 1.2:
			continue   # in reach and in sight: it halts and fires on its own
		var planned: Variant = _planned.get(bot)
		var arrived: bool = not bot.has_orders_left()
		if planned != null and (planned as Vector3).distance_to(prey_at) < ATTACK_REPLAN_M and not arrived:
			continue
		if arrived and planned != null:
			r = maxf(r - data.attack_step_m, data.attack_min_m)
			_range[bot] = r
		var away: Vector3 = here - prey_at
		away.y = 0.0
		away = away.normalized() if away.length() > 1.0 else Vector3.FORWARD
		var ideal: Vector3 = prey_at + away * minf(r, best)
		var spot: Vector3 = ideal
		if map != null:
			spot = map.find_position(get_viewport().world_3d, ideal, data.attack_spot_radius_m,
					-away, prey_at, 50.0, here, _wave_positions(bot), bot.bot_data.tactics, _rng,
					_tank_rids())
		_planned[bot] = prey_at
		bot.order_path(spot, bot.bot_data.tactics.travel_throttle, true)


func _wave_positions(except: BotController) -> PackedVector3Array:
	var out := PackedVector3Array()
	for bot: BotController in _wave:
		if bot != except and is_instance_valid(bot) and not bot.tank.is_knocked_out():
			out.append(bot.tank.global_position)
	return out


func _tank_rids() -> Array[RID]:
	var out: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		out.append((node as Tank).get_rid())
	return out


# --- Places ------------------------------------------------------------------------

## A random spot in the circle round the map's centre (spawn_edge_margin_m inside the
## edge at its narrowest), on open dry ground, facing the centre.
func _find_start() -> Transform3D:
	var rect: Rect2 = MapEdge.inner_rect(get_tree())
	var centre := Vector2.ZERO
	var radius: float = 0.0
	if rect.has_area():
		centre = rect.get_center()
		radius = maxf(minf(rect.size.x, rect.size.y) * 0.5 - data.spawn_edge_margin_m, 50.0)
	var fallback := Vector3(centre.x, 0.0, centre.y)
	for i: int in START_TRIES:
		var off: Vector2 = Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * radius
		var p := Vector3(centre.x + off.x, 0.0, centre.y + off.y)
		var ground: Vector3 = _open_ground(p)
		if ground != Vector3.INF:
			return _facing(ground, Vector3(centre.x, ground.y, centre.y))
	var g: Vector3 = _open_ground(fallback)
	fallback.y = g.y if g != Vector3.INF else 100.0
	return _facing(fallback, fallback + Vector3.FORWARD)


## Beside `other` (to its right, else left, else behind), on open ground.
func _beside(other: Tank) -> Transform3D:
	var at: Vector3 = other.global_position
	for d: Vector3 in [other.global_basis.x, -other.global_basis.x, other.global_basis.z]:
		for step: float in [1.0, 2.0]:
			var ground: Vector3 = _open_ground(at + d * BESIDE_M * step)
			if ground != Vector3.INF:
				return _facing(ground, ground - other.global_basis.z * 10.0)
	return other.global_transform.translated(Vector3.UP * KothMode.SPAWN_LIFT_M)


## A wave's centre wave_distance_*_m from the living players, inside the map's edge,
## on drivable ground; one no player can see if there is one.
func _find_wave_centre() -> Vector3:
	var from: Vector3 = _players_centre()
	var rect: Rect2 = MapEdge.inner_rect(get_tree())
	if rect.has_area():
		rect = rect.grow(-data.wave_edge_inset_m)
	var first_ok := Vector3.INF
	for i: int in data.wave_tries * 2:
		var dist: float = _rng.randf_range(data.wave_distance_min_m, data.wave_distance_max_m)
		var p: Vector3 = from + Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU) * dist
		if rect.has_area() and not rect.has_point(Vector2(p.x, p.z)):
			continue
		var ground: Vector3 = _open_ground(p)
		if ground == Vector3.INF:
			continue
		p = ground - Vector3.UP * KothMode.SPAWN_LIFT_M
		if first_ok == Vector3.INF:
			first_ok = p
		if not _seen_by_players(p) or i >= data.wave_tries:
			return p
	if first_ok != Vector3.INF:
		return first_ok
	return MapEdge.clamp_point(get_tree(), from + Vector3.FORWARD * data.wave_distance_min_m,
			data.wave_edge_inset_m)


## A defender's spot round the wave's centre: cover and hull down towards the
## players (find_position), apart from the ones placed.
func _defend_spot(toward: Vector3, placed: PackedVector3Array) -> Vector3:
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	var world: World3D = get_viewport().world_3d
	var players: Vector3 = _players_centre()
	for attempt: int in 6:
		var p: Vector3
		if map != null:
			p = map.find_position(world, _centre, data.wave_radius_m, toward, players,
					DEFEND_LOOK_SPREAD_M, _centre, placed, data.hard_bot.tactics, _rng, _tank_rids())
		else:
			var off: Vector2 = Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * data.wave_radius_m
			p = _centre + Vector3(off.x, 0.0, off.y)
		var close: bool = false
		for q: Vector3 in placed:
			if Vector2(p.x - q.x, p.z - q.z).length() < data.bot_spacing_m:
				close = true
				break
		if close and attempt < 5:
			continue
		# On the ground, never on a roof, a stone or in a tree (find_position's grid
		# misses small houses): the spot itself, else the nearest open ground round it.
		var ground: Vector3 = _open_near(p)
		if ground == Vector3.INF and attempt < 5:
			continue
		if ground != Vector3.INF:
			return ground
	var at_centre: Vector3 = _open_near(_centre)
	return at_centre if at_centre != Vector3.INF else _centre + Vector3.UP * KothMode.SPAWN_LIFT_M


## _open_ground at `p` or, if not, the nearest found on rings round it; INF if none.
func _open_near(p: Vector3) -> Vector3:
	var ground: Vector3 = _open_ground(p)
	if ground != Vector3.INF:
		return ground
	for ring: int in range(1, OPEN_NEAR_RINGS + 1):
		for k: int in OPEN_NEAR_DIRECTIONS:
			var d: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, TAU * (k + 0.5 * (ring % 2)) / OPEN_NEAR_DIRECTIONS)
			ground = _open_ground(p + d * OPEN_NEAR_STEP_M * ring)
			if ground != Vector3.INF:
				return ground
	return Vector3.INF


## Ground at (x, z) of `p` that a tank can start on (terrain, dry, not too steep, no house
## or water on the grid, nothing solid in a tank-sized box over it, inside the edge),
## lifted for a spawn; INF if not.
func _open_ground(p: Vector3) -> Vector3:
	if not MapEdge.contains(get_tree(), p):
		return Vector3.INF
	var hit: Dictionary = KothMode.ground_hit(get_viewport().world_3d, p)
	if hit.is_empty() or not (hit["collider"] is Terrain3D):
		return Vector3.INF
	var g: Vector3 = hit["position"]
	if g.y <= KothMode.SEA_LEVEL_LIMIT_M \
			or (hit["normal"] as Vector3).angle_to(Vector3.UP) > deg_to_rad(KothMode.SPAWN_MAX_SLOPE_DEG):
		return Vector3.INF
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	if map != null and map.is_blocked(g):
		return Vector3.INF
	if not KothMode.box_clear(get_viewport().world_3d, g):
		return Vector3.INF
	return g + Vector3.UP * KothMode.SPAWN_LIFT_M


func _facing(at: Vector3, look: Vector3) -> Transform3D:
	var dir: Vector3 = look - at
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = Vector3.FORWARD
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), at)


## True if a living player's commander could see a point over `p` (terrain, houses,
## trees and bushes block; tanks don't).
func _seen_by_players(p: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var target: Vector3 = p + Vector3.UP * SEEN_HEIGHT_M
	for tank: Tank in _living_players():
		var eye: Vector3 = tank.get_commander_eye_position()
		var query := PhysicsRayQueryParameters3D.create(eye, target, 1 | Vision.LAYER_VISION_BLOCKER)
		query.collide_with_areas = true
		query.exclude = _tank_rids()
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() or (hit["position"] as Vector3).distance_to(target) < SEEN_SLACK_M:
			return true
	return false


# --- Players --------------------------------------------------------------------------

## The players' tanks (every tank not on the bots' team).
func _players() -> Array[Tank]:
	var out: Array[Tank] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank != null and tank.team != data.bot_team and not tank.is_queued_for_deletion():
			out.append(tank)
	return out


func _living_players() -> Array[Tank]:
	return _players().filter(func(t: Tank) -> bool: return not t.is_knocked_out())


func _players_centre() -> Vector3:
	var players: Array[Tank] = _living_players()
	if players.is_empty():
		players = _players()
	if players.is_empty():
		return _start.origin
	var sum := Vector3.ZERO
	for t: Tank in players:
		sum += t.global_position
	return sum / players.size()


# --- Stats ---------------------------------------------------------------------------

func _connect_new_tanks() -> void:
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or _connected.has(tank.get_instance_id()):
			continue
		_connected[tank.get_instance_id()] = true
		if tank.team == data.bot_team:
			continue   # only the players' rows show
		_stats[tank.get_instance_id()] = _carried.get(tank.get_instance_id(),
				[tank.get_display_label(), tank.team, 0, 0, 0])
		_carried.erase(tank.get_instance_id())
		tank.knocked_out.connect(func() -> void: _stat_add(tank, 3))
	# Kills are counted from the bots' side: a knock-out of a bot credits its killer.
	for bot: BotController in _wave:
		if is_instance_valid(bot) and not _connected.has(-bot.tank.get_instance_id()):
			_connected[-bot.tank.get_instance_id()] = true
			bot.tank.eliminated.connect(_on_bot_eliminated)


func _on_bot_eliminated(killer: Tank, assists: Array[Tank]) -> void:
	if killer != null and is_instance_valid(killer):
		_stat_add(killer, 2)
	for t: Tank in assists:
		if is_instance_valid(t):
			_stat_add(t, 4)


func _stat_add(tank: Tank, field: int) -> void:
	var row: Array = _stats.get(tank.get_instance_id(), [])
	if not row.is_empty():
		row[field] = int(row[field]) + 1
