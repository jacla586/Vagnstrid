class_name KothBots
extends Node
## King of the Hill orders for every BotController in the scene: drive to a random
## point inside the zone (or the announced next zone during a gap), hold there a
## while, then pick a new point so bots don't sit still forever; re-order when the zone
## moves or shrinks past them. Knocked-out bots come back at their team's current spawn
## after KothData.bot_respawn_delay_s, instead of being repaired where they died.
## Bots still spot and fight by their own rules on the way. Host/offline only.
##
## Bounding: near the zone (TacticsData.bound_start_m from its edge) or after contact,
## the bots of a team pair up and move in turns: one holds and watches while the other
## drives to the next good position (find_position) at most bound_length_m ahead, then
## they swap (the watcher goes anyway after overwatch_max_s). A bot without a partner
## alternates a short halt and a move. Not while hurrying (between zones, just
## respawned). Inside the zone the usual spot-and-hold orders take over.
##
## Hunting (TacticsData.hunt_*): an enemy the crew has seen or had reported lately
## (bots radio their spots to the team) is gone after: the bot drives to a firing spot
## about hunt_engage_m from where it was last known, replanning as new sightings come
## in, and closer each time it arrives. Enemies in the open zone come first, at any
## range and without a time limit, until they are knocked out or lost; others only
## when in reach near the zone, for at most hunt_max_s, and not while hurrying.

## Points are picked within this share of the radius, so bots end up well inside.
const INNER_SHARE: float = 0.6
## A bot holding its point picks a new one after a random time in this range (s).
const HOLD_MIN_S: float = 15.0
const HOLD_MAX_S: float = 35.0
## Hunting: think this often (s); replan when the enemy's last known position has
## moved this far (m); firing spots are looked for within this of the ideal one (m).
const HUNT_THINK_S: float = 2.0
const HUNT_REPLAN_M: float = 60.0
const HUNT_SPOT_RADIUS_M: float = 60.0
## After giving a hunt up, no new one for this long (s).
const HUNT_GIVE_UP_PAUSE_S: float = 20.0
## Enemies in the zone are preferred as if those outside were this much further (m).
const HUNT_OUTSIDE_PENALTY_M: float = 10000.0
## Pressing in, a hunter stops closing at this range (m).
const HUNT_MIN_RANGE_M: float = 50.0
## Bots side by side at a spawn leave one after another this far apart (s), so they
## don't all turn into each other at once.
const DEPART_INTERVAL_S: float = 2.5
## The zone closing within this long counts as hurry: no scouting stops (s).
const HURRY_BEFORE_CLOSE_S: float = 60.0
## Positions in the zone watch this share of the radius out from the centre, towards
## the enemy: the zone's far edge, where they come in.
const LOOK_SHARE: float = 0.8
## Bounding roles.
const MOVER: int = 1
const WATCHER: int = 2
## A bound must bring the tank at least this share of bound_length_m closer to the zone.
const BOUND_MIN_PROGRESS: float = 0.4
## A bot in the zone only starts bounding again this far outside its inner part (m).
const BOUND_REENTER_M: float = 40.0
## Long drives (further than this, m) go by a flank point: left, centre or right of the
## straight line, FLANK_OFFSET_MIN/MAX_M aside, FLANK_ALONG of the way. Teammates
## prefer different flanks, so the team doesn't all use one way the enemy can watch.
const FLANK_MIN_DRIVE_M: float = 400.0
const FLANK_OFFSET_MIN_M: float = 150.0
const FLANK_OFFSET_MAX_M: float = 250.0
const FLANK_ALONG: float = 0.4

@export var mode: KothMode

static var instance: KothBots

var _bots: Array[BotController] = []
var _hold: Dictionary = {}  # BotController -> seconds left at the current point
var _respawn: Dictionary = {}  # BotController -> seconds until back at the spawn
var _ordered_radius: Dictionary = {}  # BotController -> zone radius when last ordered
var _depart: Dictionary = {}  # BotController -> seconds until it leaves the spawn
var _goals: Dictionary = {}  # BotController -> where it was last sent
var _respawned: Dictionary = {}  # BotController -> true until its first order after a respawn
## Bounding: role per bot (MOVER/WATCHER), its partner (or null), seconds in the role.
var _role: Dictionary = {}
var _partner: Dictionary = {}
var _role_time: Dictionary = {}
var _flank: Dictionary = {}  # BotController -> -1 left, 0 centre, 1 right (last long drive)
## Hunting: BotController -> {"enemy": Tank, "at": Vector3 planned for, "time": s}.
var _hunt: Dictionary = {}
var _hunt_think: Dictionary = {}  # BotController -> seconds until the next look
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Copy of the first placed bot's controller (outside the tree), its tank scene and
## data, and where bots live: for adding bots (_add_bot).
var _template: BotController
var _template_scene: String
var _template_data: TankData
var _template_xform: Transform3D
var _bot_parent: Node
var _bot_serial: int = 0


func _ready() -> void:
	if NetRole.is_client() or mode == null:
		set_physics_process(false)
		return
	_rng.randomize()
	mode.zone_moved.connect(func(_c: Vector3) -> void: _order_all())
	_find_bots.call_deferred()


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if _template != null:
		_template.free()
		_template = null


func _find_bots() -> void:
	if NetRole.is_host():
		# The map loads first, NetGame a frame or more later: it sorts the map's bots
		# into teams (or removes them), and must know of every bot added here.
		while NetSession.instance.game == null:
			await get_tree().process_frame
	_remember_template()
	_fill_teams()
	var per_team: Dictionary = {}
	for node: Node in get_tree().current_scene.find_children("*", "", true, false):
		var bot := node as BotController
		if bot == null or bot.tank == null or bot.is_queued_for_deletion():
			continue
		_adopt(bot)
		var n: int = int(per_team.get(bot.tank.team, 0))
		per_team[bot.tank.team] = n + 1
		_depart_later(bot, n * DEPART_INTERVAL_S)


## Starts looking after a bot: respawns, contacts, orders.
func _adopt(bot: BotController) -> void:
	if _bots.has(bot):
		return
	_bots.append(bot)
	bot.respawn_delay_s = 0.0   # no repair on the spot: we bring it back at the spawn
	bot.tank.knocked_out.connect(_on_knocked_out.bind(bot))
	bot.tank.squad_contact.connect(_on_squad_contact.bind(bot))
	bot.contact.connect(_on_bot_contact.bind(bot))


## Keeps a copy of the first bot (its controller settings, tank scene and data), so
## bots can still be added after every placed one has made room for a player.
func _remember_template() -> void:
	if _template != null:
		return
	for node: Node in get_tree().current_scene.find_children("*", "", true, false):
		var bot := node as BotController
		if bot != null and bot.tank != null and not bot.is_queued_for_deletion():
			_template = bot.duplicate() as BotController
			_template_scene = bot.tank.scene_file_path
			_template_data = bot.tank.data
			_template_xform = bot.tank.global_transform
			_bot_parent = bot.tank.get_parent()
			return


## Tanks of `team` in the match (players and bots), not counting ones on their way out.
func _team_tanks(team: int) -> Array[Tank]:
	var out: Array[Tank] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank != null and tank.team == team and not tank.is_queued_for_deletion():
			out.append(tank)
	return out


## Brings both teams to MatchSettings.team_size tanks, players included: bots (the
## template's settings, a random KothData bot config) are added, extra bots removed.
## Offline and on the host (with bots on). At the start it runs before the match's
## first frame, so KothMode puts the new tanks at the spawns with the rest; later
## (a player left) new bots go straight to their spawn.
func _fill_teams() -> void:
	MatchSettings.load_settings()
	var size: int = MatchSettings.team_size
	if size <= 0 or _template == null:
		return
	for team: int in [0, 1]:
		var tanks: Array[Tank] = _team_tanks(team)
		var extra: int = tanks.size() - size
		while extra > 0:
			var bot: BotController = _bot_to_remove(team)
			if bot == null:
				break
			_remove_bot(bot)
			extra -= 1
		for i: int in range(-extra):
			_add_bot(team, tanks.size() + i)


## Host: a player joins `team`. If the team is already full, a bot leaves to make room
## (one that is knocked out, if any). Returns the bot's tank, already out of the bot
## lists and without its controller; the caller removes it from the game.
func make_room(team: int) -> Tank:
	var size: int = MatchSettings.team_size
	if size <= 0 or _team_tanks(team).size() < size:
		return null
	var bot: BotController = _bot_to_remove(team)
	if bot == null:
		return null
	var tank: Tank = bot.tank
	_forget_bot(bot)
	bot.queue_free()
	return tank


## Host: a player left; bring the teams back up to size with bots.
func refill() -> void:
	if _template == null:
		return
	var before: Array[BotController] = _bots.duplicate()
	_fill_teams()
	for node: Node in get_tree().current_scene.find_children("*", "", true, false):
		var bot := node as BotController
		if bot != null and bot.tank != null and not before.has(bot) and not bot.is_queued_for_deletion():
			_adopt(bot)
			_respawned[bot] = true   # hurry to the zone
			_depart_later(bot, _rng.randf_range(0.0, DEPART_INTERVAL_S))


## Which of `team`'s bots goes: a knocked-out one first, else the last one.
func _bot_to_remove(team: int) -> BotController:
	var pick: BotController = null
	for node: Node in get_tree().current_scene.find_children("*", "", true, false):
		var bot := node as BotController
		if bot == null or not is_instance_valid(bot.tank) or bot.tank.team != team \
				or bot.is_queued_for_deletion():
			continue
		if bot.tank.is_knocked_out():
			return bot
		pick = bot
	return pick


## Takes a bot and its tank (and squad) out of the match. A knocked-out tank leaves
## its wreck.
func _remove_bot(bot: BotController) -> void:
	var tank: Tank = bot.tank
	_forget_bot(bot)
	bot.queue_free()
	var game: NetGame = NetSession.instance.game if NetRole.is_host() else null
	if game != null:
		game.remove_tank(tank)
	else:
		tank.leave_wreck()
		if tank.squad != null and is_instance_valid(tank.squad):
			tank.squad.queue_free()
		tank.queue_free()


## Drops a bot from every list (and from its partner's).
func _forget_bot(bot: BotController) -> void:
	_bots.erase(bot)
	for d: Dictionary in [_hold, _respawn, _ordered_radius, _depart, _goals, _respawned,
			_role, _partner, _role_time, _flank, _hunt, _hunt_think]:
		d.erase(bot)
	for other: Variant in _partner.keys():
		if _partner[other] == bot:
			_partner[other] = null


func _add_bot(team: int, index: int) -> void:
	var tank: Tank = (load(_template_scene) as PackedScene).instantiate()
	_bot_serial += 1
	tank.name = "Team%dBot%d" % [team, _bot_serial]
	tank.team = team
	tank.data = _template_data
	var pool: Array[TankConfig] = mode.data.bot_configs
	if not pool.is_empty():
		tank.config = pool[_rng.randi() % pool.size()]
	var parent: Node = _bot_parent if is_instance_valid(_bot_parent) else get_tree().current_scene
	parent.add_child(tank)
	# Beside the first placed bot until KothMode moves everyone to the spawns.
	tank.global_transform = _template_xform.translated(Vector3(index * 12.0 + 12.0, 2.0, 0.0))
	if mode.has_started():
		KothMode.place_tank(tank, mode.get_free_spawn(team, tank))
	var bot: BotController = _template.duplicate() as BotController
	bot.name = tank.name + "Controller"
	bot.tank = tank
	bot.waypoints = []
	parent.add_child(bot)
	var game: NetGame = NetSession.instance.game if NetRole.is_host() else null
	if game != null:
		game.add_bot_tank(tank)


func _physics_process(delta: float) -> void:
	# Bots removed by others (NetGame without bots) drop out of every list.
	for i: int in range(_bots.size() - 1, -1, -1):
		if not is_instance_valid(_bots[i]) or not is_instance_valid(_bots[i].tank):
			_bots.remove_at(i)
	_update_bounding(delta)
	for bot: BotController in _bots:
		if not is_instance_valid(bot) or not is_instance_valid(bot.tank):
			continue
		if _respawn.has(bot):
			_update_respawn(bot, delta)
			continue
		if bot.tank.is_knocked_out():
			continue
		if _depart.has(bot):
			_depart[bot] = float(_depart[bot]) - delta
			if float(_depart[bot]) > 0.0:
				continue
			_depart.erase(bot)
			_order_into_zone(bot)
			continue
		if bot.is_relocating():
			continue   # pulling back after hits: its own order runs first
		if _update_hunt(bot, delta):
			continue
		if _role.has(bot):
			continue   # moving up in turns (_update_bounding)
		var radius: float = mode.get_radius()
		var shrunk: bool = float(_ordered_radius.get(bot, radius)) > radius / INNER_SHARE
		if bot.has_orders_left():
			if shrunk:
				_order_into_zone(bot)
			continue
		if not _is_inside(bot.tank.global_position, radius):
			_order_into_zone(bot)
			continue
		_hold[bot] = float(_hold.get(bot, HOLD_MAX_S)) - delta
		if float(_hold[bot]) <= 0.0:
			_order_into_zone(bot)


func _order_all() -> void:
	_hunt.clear()
	for bot: BotController in _bots:
		if is_instance_valid(bot) and is_instance_valid(bot.tank) and not bot.tank.is_knocked_out() \
				and not _depart.has(bot):
			_order_into_zone(bot)


## Hold at the spawn for a moment, then go (staggered per team).
func _depart_later(bot: BotController, delay: float) -> void:
	bot.order_move([bot.tank.global_position], 0.0)
	_depart[bot] = delay


# --- Bounding ------------------------------------------------------------------------

func _update_bounding(delta: float) -> void:
	var teams: Dictionary = {}  # team -> bots that should bound
	for bot: BotController in _bots:
		if _wants_bounding(bot):
			if not teams.has(bot.tank.team):
				teams[bot.tank.team] = []
			(teams[bot.tank.team] as Array).append(bot)
		elif _role.has(bot):
			_leave_bounding(bot)
	for team: int in teams:
		var group: Array = teams[team]
		group.sort_custom(func(a: BotController, b: BotController) -> bool:
				return a.get_instance_id() < b.get_instance_id())
		var i: int = 0
		while i < group.size():
			var a: BotController = group[i]
			var b: BotController = group[i + 1] if i + 1 < group.size() else null
			_step_pair(a, b, delta)
			i += 2


func _wants_bounding(bot: BotController) -> bool:
	if not is_instance_valid(bot) or not is_instance_valid(bot.tank) or bot.tank.is_knocked_out():
		return false
	if _respawn.has(bot) or _depart.has(bot) or _respawned.has(bot) or _hurry() \
			or _hunt.has(bot) or bot.is_relocating():
		return false
	var c: Vector3 = mode.get_center()
	var to_edge: float = Vector2(bot.tank.global_position.x - c.x,
			bot.tank.global_position.z - c.z).length() - mode.get_radius() * INNER_SHARE
	if to_edge <= 0.0:
		return false   # in the zone: the usual spot-and-hold orders
	if not _role.has(bot) and to_edge < BOUND_REENTER_M:
		return false   # just outside (e.g. the zone shrank past it): no flip-flopping
	var t: TacticsData = _tactics_of(bot)
	return to_edge < t.bound_start_m or bot.get_time_since_contact() < t.bound_after_contact_s


## One pair (b may be null: a bot on its own) moving up in turns.
func _step_pair(a: BotController, b: BotController, delta: float) -> void:
	if _partner.get(a, a) != b or not _role.has(a) or (b != null and not _role.has(b)):
		# New pair (or partner changed): a moves first, b watches.
		_partner[a] = b
		_start_move(a)
		if b != null:
			_partner[b] = a
			_start_watch(b)
	for bot: BotController in [a, b]:
		if bot != null:
			_role_time[bot] = float(_role_time.get(bot, 0.0)) + delta
	var t: TacticsData = _tactics_of(a)
	if b == null:
		# Alone: move, then a short halt, then move again.
		if int(_role[a]) == MOVER and not a.has_orders_left():
			_start_watch(a)
		elif int(_role[a]) == WATCHER and float(_role_time[a]) >= t.solo_halt_s:
			_start_move(a)
		return
	# Each bot: move to its spot, then watch. A watcher goes when its partner has
	# arrived (and starts watching), or after overwatch_max_s even if the partner is
	# still on its way: a move is never cut short.
	for pair: Array in [[a, b], [b, a]]:
		var bot: BotController = pair[0]
		var other: BotController = pair[1]
		if int(_role[bot]) == MOVER and not bot.has_orders_left():
			_start_watch(bot)
			if int(_role[other]) == WATCHER and float(_role_time[other]) > 0.0:
				_start_move(other)
	for bot: BotController in [a, b]:
		if int(_role[bot]) == WATCHER and float(_role_time[bot]) >= t.overwatch_max_s:
			_start_move(bot)


func _start_move(bot: BotController) -> void:
	_role[bot] = MOVER
	_role_time[bot] = 0.0
	var goal: Vector3 = _bound_spot(bot)
	_goals[bot] = goal
	bot.order_path(goal, _tactics_of(bot).travel_throttle, true)


func _start_watch(bot: BotController) -> void:
	_role[bot] = WATCHER
	_role_time[bot] = 0.0
	bot.order_move([bot.tank.global_position], 0.0)


func _leave_bounding(bot: BotController) -> void:
	var partner: Variant = _partner.get(bot)
	_role.erase(bot)
	_partner.erase(bot)
	_role_time.erase(bot)
	if partner != null and is_instance_valid(partner) and _partner.get(partner) == bot:
		_partner[partner] = null   # re-paired on the next update
	if is_instance_valid(bot) and is_instance_valid(bot.tank) and not bot.tank.is_knocked_out() \
			and not _hunt.has(bot) and not bot.is_relocating():
		_order_into_zone(bot)


## The next position for a bound: a good spot (cover, hull down, sight towards the
## enemy) about bound_length_m towards the zone, or in the zone if that is closer.
func _bound_spot(bot: BotController) -> Vector3:
	var t: TacticsData = _tactics_of(bot)
	var c: Vector3 = mode.get_center()
	var p: Vector3 = bot.tank.global_position
	var to_zone := Vector3(c.x - p.x, 0.0, c.z - p.z)
	var inner: float = mode.get_radius() * INNER_SHARE
	if to_zone.length() - inner <= t.bound_length_m:
		return _choose_spot(bot, inner)
	var leg_center: Vector3 = p + to_zone.normalized() * t.bound_length_m * 0.8
	var spot: Vector3 = _choose_spot(bot, t.bound_length_m * 0.35, leg_center,
			t.bound_length_m * BOUND_MIN_PROGRESS)
	return spot


func _tactics_of(bot: BotController) -> TacticsData:
	return bot.bot_data.tactics if bot.bot_data != null and bot.bot_data.tactics != null \
			else TacticalMap.DEFAULT_TACTICS


## No time for scouting stops: racing to the next zone, or the open one closes soon.
func _hurry() -> bool:
	if not mode.is_zone_open():
		return true
	return mode.get_shrink_progress() > 0.0 and mode.get_time_to_next_event() < HURRY_BEFORE_CLOSE_S


## Inside the open zone (not just announced).
func _is_in_open_zone(point: Vector3) -> bool:
	return mode.is_zone_open() and _is_inside(point, mode.get_radius())


## Inside the zone's circle (open or announced).
func _is_inside(point: Vector3, radius: float) -> bool:
	var c: Vector3 = mode.get_center()
	return Vector2(point.x - c.x, point.z - c.z).length() <= radius


func _order_into_zone(bot: BotController) -> void:
	var radius: float = mode.get_radius()
	var urgent: bool = _respawned.has(bot) or _hurry()
	_respawned.erase(bot)
	var goal: Vector3 = _choose_spot(bot, radius * INNER_SHARE)
	_goals[bot] = goal
	bot.order_path(goal, _tactics_of(bot).travel_throttle, urgent, _flank_point(bot, goal))
	_ordered_radius[bot] = radius
	_hold[bot] = _rng.randf_range(HOLD_MIN_S, HOLD_MAX_S)


# --- Hunting ---------------------------------------------------------------------

## Starts, steers and ends this bot's hunt. True while it is hunting (other orders wait).
func _update_hunt(bot: BotController, delta: float) -> bool:
	var t: TacticsData = _tactics_of(bot)
	if _hunt.has(bot):
		var h: Dictionary = _hunt[bot]
		h["time"] = float(h["time"]) + delta
		var enemy: Variant = h["enemy"]
		var gone: bool = not is_instance_valid(enemy) or (enemy as Tank).is_knocked_out()
		var in_zone: bool = _is_in_open_zone(h["at"])
		var timed_out: bool = not in_zone and float(h["time"]) >= t.hunt_max_s
		if gone or timed_out or (_hurry() and not in_zone):
			_end_hunt(bot)
			if not gone:
				_hunt_think[bot] = HUNT_GIVE_UP_PAUSE_S   # back to the zone for a while
			return false
	_hunt_think[bot] = float(_hunt_think.get(bot, 0.0)) - delta
	if float(_hunt_think[bot]) > 0.0:
		return _hunt.has(bot)
	_hunt_think[bot] = HUNT_THINK_S
	if t.hunt_range_m <= 0.0:
		return _hunt.has(bot)
	# Enemies known to be in the open zone come first, at any range (they score there
	# and kills there pay); then others in reach near the zone (not while hurrying).
	var prey: Tank = null
	var prey_at := Vector3.ZERO
	var best: float = INF
	var here: Vector3 = bot.tank.global_position
	var known: Dictionary = bot.get_known_enemies(t.hunt_memory_s)
	for other: Tank in known.keys():
		var at: Vector3 = known[other]
		var d: float = here.distance_to(at)
		if not _is_in_open_zone(at):
			if _hurry() or d > t.hunt_range_m \
					or not _is_inside(at, mode.get_radius() + t.hunt_zone_margin_m):
				continue
			d += HUNT_OUTSIDE_PENALTY_M
		if d < best:
			best = d
			prey = other
			prey_at = at
	if prey == null:
		if _hunt.has(bot):
			_end_hunt(bot)
		return false
	# Outside the zone, close enough and in sight: no new drive (the bot halts to fire
	# on its own). An enemy in the zone is pressed until it is out.
	if not _is_in_open_zone(prey_at) and bot.has_target_in_sight() \
			and best - HUNT_OUTSIDE_PENALTY_M <= t.hunt_engage_m * 1.2:
		return _hunt.has(bot)
	if _hunt.has(bot):
		var h: Dictionary = _hunt[bot]
		var same: bool = h["enemy"] == prey \
				and (h["at"] as Vector3).distance_to(prey_at) < HUNT_REPLAN_M
		if same and bot.has_orders_left():
			return true
		if h["enemy"] != prey:
			h["time"] = 0.0
		h["enemy"] = prey
		h["at"] = prey_at
	else:
		_hunt[bot] = {"enemy": prey, "at": prey_at, "time": 0.0}
		if _role.has(bot):
			_leave_bounding(bot)
	var spot: Vector3 = _hunt_spot(bot, prey_at)
	_goals[bot] = spot
	bot.order_path(spot, t.travel_throttle, true)
	return true


func _end_hunt(bot: BotController) -> void:
	_hunt.erase(bot)
	if is_instance_valid(bot.tank) and not bot.tank.is_knocked_out():
		_order_into_zone(bot)


## A firing spot about hunt_engage_m from `enemy_at`, on this bot's side of it, with
## sight towards it (cover and hull down where the grid offers them).
func _hunt_spot(bot: BotController, enemy_at: Vector3) -> Vector3:
	var t: TacticsData = _tactics_of(bot)
	var here: Vector3 = bot.tank.global_position
	var back := Vector3(here.x - enemy_at.x, 0.0, here.z - enemy_at.z)
	var dist: float = back.length()
	if dist < 1.0:
		return enemy_at
	back /= dist
	var ideal: Vector3 = enemy_at + back * minf(dist, maxf(HUNT_MIN_RANGE_M,
			minf(t.hunt_engage_m, dist * 0.8)))
	# An enemy in the zone is fought from inside it (kills only pay from there, and
	# the hunter scores meanwhile).
	var inner: float = mode.get_radius() * INNER_SHARE
	var c: Vector3 = mode.get_center()
	var off := Vector3(ideal.x - c.x, 0.0, ideal.z - c.z)
	if _is_inside(enemy_at, mode.get_radius()) and off.length() > inner:
		ideal = Vector3(c.x, ideal.y, c.z) + off.normalized() * inner
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	if map == null:
		return ideal
	var friends := PackedVector3Array()
	for other: BotController in _bots:
		if other != bot and is_instance_valid(other) and is_instance_valid(other.tank) \
				and other.tank.team == bot.tank.team and _goals.has(other):
			friends.append(_goals[other])
	var exclude: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		exclude.append((node as Tank).get_rid())
	return map.find_position(mode.get_world_3d(), ideal, HUNT_SPOT_RADIUS_M, -back, enemy_at,
			40.0, here, friends, t, _rng, exclude)


## A point to drive by on a long way to `goal` (a random flank, preferring one no
## teammate took), or INF for a straight path.
func _flank_point(bot: BotController, goal: Vector3) -> Vector3:
	var from: Vector3 = bot.tank.global_position
	var line := Vector3(goal.x - from.x, 0.0, goal.z - from.z)
	if line.length() < FLANK_MIN_DRIVE_M:
		return Vector3.INF
	var taken: Array[int] = []
	for other: BotController in _bots:
		if other != bot and is_instance_valid(other) and is_instance_valid(other.tank) \
				and other.tank.team == bot.tank.team and _flank.has(other):
			taken.append(int(_flank[other]))
	var choices: Array[int] = []
	for f: int in [-1, 0, 1]:
		if not taken.has(f):
			choices.append(f)
	if choices.is_empty():
		choices = [-1, 0, 1]
	var flank: int = choices[_rng.randi_range(0, choices.size() - 1)]
	_flank[bot] = flank
	if flank == 0:
		return Vector3.INF
	var side: Vector3 = line.normalized().cross(Vector3.UP) * float(flank)
	var via: Vector3 = from + line * FLANK_ALONG \
			+ side * _rng.randf_range(FLANK_OFFSET_MIN_M, FLANK_OFFSET_MAX_M)
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	if map != null and map.is_blocked(via):
		return Vector3.INF
	return via


## A good spot in the zone (cover, hull down, sight towards the enemy, apart from
## teammates) with the tactical grid; a random point without one.
## `min_progress` > 0: the spot must be at least that much closer to the zone.
func _choose_spot(bot: BotController, radius: float, around: Vector3 = Vector3.INF,
		min_progress: float = 0.0) -> Vector3:
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	if map == null:
		return _random_point(radius)
	var zone_center: Vector3 = mode.get_center()
	var center: Vector3 = zone_center if around == Vector3.INF else around
	var threat: Vector3 = bot.get_threat_direction()
	if threat == Vector3.ZERO:
		# Nothing known: the enemy comes from its own side of the zone.
		threat = Vector3.FORWARD if bot.tank.team == mode.data.south_team else Vector3.BACK
	var friends := PackedVector3Array()
	var exclude: Array[RID] = []
	for other: BotController in _bots:
		if other == bot or not is_instance_valid(other) or not is_instance_valid(other.tank):
			continue
		if other.tank.team == bot.tank.team and not other.tank.is_knocked_out():
			friends.append(other.tank.global_position)
			if _goals.has(other):
				friends.append(_goals[other])
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		exclude.append((node as Tank).get_rid())
	var look_at: Vector3 = zone_center + threat * mode.get_radius() * LOOK_SHARE
	var tactics: TacticsData = _tactics_of(bot)
	return map.find_position(mode.get_world_3d(), center, radius, threat, look_at,
			mode.get_radius() * 1.5, bot.tank.global_position, friends, tactics, _rng, exclude,
			zone_center, min_progress)


## Random point inside `radius` of the zone centre, on land, at ground height.
func _random_point(radius: float) -> Vector3:
	var center: Vector3 = mode.get_center()
	var offset: Vector2 = Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * radius
	var point := Vector3(center.x + offset.x, center.y, center.z + offset.y)
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	for i: int in 8:
		var hit: Dictionary = KothMode.ground_hit(mode.get_world_3d(), point)
		var dry: bool = not hit.is_empty() \
				and (hit["position"] as Vector3).y > KothMode.SEA_LEVEL_LIMIT_M
		if dry and (map == null or not map.is_blocked(hit["position"])):
			point.y = (hit["position"] as Vector3).y
			return point
		# Try another random point, a bit closer to the centre each time.
		offset = Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * radius * (1.0 - i / 8.0)
		point = Vector3(center.x + offset.x, center.y, center.z + offset.y)
	return center


## A bot spotted an enemy tank: the radio tells the rest of its team (as a player's
## spot marks do), so they can go after it.
func _on_bot_contact(enemy: Tank, at: Vector3, from: BotController) -> void:
	if enemy != null:
		_on_squad_contact(enemy, at, from)


## A bot's squad saw an enemy: the radio tells the rest of its team.
func _on_squad_contact(enemy: Node3D, at: Vector3, from: BotController) -> void:
	for other: BotController in _bots:
		if other != from and is_instance_valid(other) and is_instance_valid(other.tank) \
				and other.tank.team == from.tank.team and not other.tank.is_knocked_out():
			other.share_contact(enemy as Tank, at)


func _on_knocked_out(bot: BotController) -> void:
	_hunt.erase(bot)
	_respawn[bot] = mode.data.bot_respawn_delay_s


func _update_respawn(bot: BotController, delta: float) -> void:
	_respawn[bot] = float(_respawn[bot]) - delta
	if float(_respawn[bot]) > 0.0:
		return
	_respawn.erase(bot)
	KothMode.place_tank(bot.tank, mode.get_free_spawn(bot.tank.team, bot.tank))
	bot.tank.repair()
	_respawned[bot] = true
	_depart_later(bot, _rng.randf_range(0.0, DEPART_INTERVAL_S))
