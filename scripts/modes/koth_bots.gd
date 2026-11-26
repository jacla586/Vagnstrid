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
##
## New orders that come in a crowd (the zone moved or shrank, bounding ended) wait in a
## queue and go out one at a time (ORDER_INTERVAL_S), as do new bounding pairs: each
## costs a position search and path searches, which all at once freeze the game.
##
## Attack axes (KothData.bot_attack_axes): when a zone is announced each team splits
## onto three axes fanned round its own side (left, centre, right; axes with known
## enemies near them come last). Pairs on one axis first meet at an assembly point
## assembly_distance_m outside the zone (waiting at most assembly_wait_max_s for the
## partner), then bound in towards their axis' entry point, not the zone centre, and
## hold round it. support_per_team bots per team don't go in: they watch the zone from
## outside (kills of enemies in the zone pay from anywhere under those rules). The gap
## between zones isn't a hurry then: it is the time to get into place.

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
## One queued order or new bounding pair per this long (s). A bot's order costs ~15 ms.
const ORDER_INTERVAL_S: float = 0.05
## Attack axes: assembly and support spots are searched within this of the ideal (m).
const ASSEMBLY_SPOT_RADIUS_M: float = 80.0
const SUPPORT_SPOT_RADIUS_M: float = 100.0
## An axis' entry point lies this share of the radius out from the centre.
const ENTRY_SHARE: float = 0.5
## Bots round their entry point hold within this share of the radius of it.
const ENTRY_HOLD_SHARE: float = 0.35
## Known enemies within this of an axis' way in (assembly point to entry) count against it (m).
const AXIS_THREAT_M: float = 250.0
## How old known enemies may be for choosing axes (s).
const AXIS_MEMORY_S: float = 60.0
## A bot already this share of the assembly distance from the zone edge skips assembling.
const ASSEMBLY_SKIP_SHARE: float = 0.7
## Teams smaller than this have no support bot.
const SUPPORT_MIN_TEAM: int = 3   # (unused since roles: kept for old rule sets)
## Roles that keep moving (holds under HOLD_MIN_S) pick their next spot this far round
## their flank (deg).
const SCOUT_SWING_DEG: float = 25.0
## A follower's spot is looked for within this of the point behind its lead (m)...
const FOLLOW_SPOT_RADIUS_M: float = 50.0
## ...and a new one comes once the lead has moved this share of follow_m.
const FOLLOW_REORDER_SHARE: float = 0.6
## Mines (the zone's defence): a bot standing this long (s) within the zone radius +
## MINE_NEAR_ZONE_M sends its squad to lay what it carries, thinking again every
## MINE_THINK_S; roles that mine first (BotRoleData.mines_first) by MINES_FIRST_SHARE.
const MINE_AFTER_S: float = 6.0
const MINE_THINK_S: float = 6.0
const MINES_FIRST_SHARE: float = 0.5
const MINE_NEAR_ZONE_M: float = 300.0
const MINE_STILL_MPS: float = 1.0
## Where: on the enemy's side of the zone (within MINE_SPREAD_DEG of the threat), from
## MINE_INNER_SHARE of the radius to MINE_OUTSIDE_M beyond it; roads (the ways in)
## first; not within MINE_GAP_M of the team's mines; within the squad's reach.
const MINE_SPREAD_DEG: float = 70.0
const MINE_INNER_SHARE: float = 0.5
const MINE_OUTSIDE_M: float = 120.0
const MINE_GAP_M: float = 25.0
const MINE_CANDIDATES: int = 60
const MINE_ROAD_BONUS: float = 2.0

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
## Attack axes: axis per bot (-1 left, 0 centre, 1 right of its team's side), support
## bots, the axes' directions per team, and assembly state for the current zone.
var _axis: Dictionary = {}
var _support: Dictionary = {}
var _axis_dirs: Dictionary = {}  # team -> {axis: flat unit vector from the zone centre}
var _assembled: Dictionary = {}  # BotController -> true once it left its assembly point
var _assembly_wait: Dictionary = {}  # BotController -> seconds waited there (has = arrived)
var _no_wait: Dictionary = {}  # BotController -> true: don't wait for the partner (respawned)
var _mate: Dictionary = {}  # BotController -> its assembly partner (same axis), or absent
var _axes_assigned_once: bool = false  # the first zone: everyone assembles
## Bots waiting for a new order into the zone (they keep their old one until then).
# Roles (BotRoleData) and the team's reading of the fight (TeamSituation).
var _angle: Dictionary = {}  # BotController -> its way in, deg off its team's spawn direction
var _entering: Dictionary = {}  # BotController -> clock when an outside role last had the moment
var _lead_at: Dictionary = {}  # BotController (follower) -> where its lead was when ordered
var _situation: Dictionary = {}  # team -> TeamSituation
var _situation_wait: float = 0.0
var _kos := TeamSituation.KnockoutLog.new()
var _order_queue: Array[BotController] = []
var _order_wait: float = 0.0  # seconds until the next queued order or new pair
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Copy of the first placed bot's controller (outside the tree), its tank scene and
## data, and where bots live: for adding bots (_add_bot).
var _template: BotController
var _template_scene: String
var _template_data: TankData
var _template_xform: Transform3D
var _bot_parent: Node
var _bot_serial: int = 0
var _mine_stand: Dictionary = {}  # BotController -> seconds standing near the zone
var _mine_think: Dictionary = {}  # BotController -> seconds until it thinks about mines
var _mined_zone: Dictionary = {}  # BotController -> zone number its mines are out for
## Each team's commander (TeamCommander; none when MatchSettings.bot_commander is off).
var _commanders: Dictionary = {}  # team -> TeamCommander
var _ordered_threat: Dictionary = {}  # BotController -> the commander's threat lane at its last hold order
var _squad_task: Dictionary = {}  # BotController -> [point, clock]: its squad out in a commander ambush
## Only these teams get a commander when it is on (bit per team; tests: one side with, one without).
static var commander_teams: int = 3


func _ready() -> void:
	if NetRole.is_client() or mode == null:
		set_physics_process(false)
		return
	_rng.randomize()
	var commander: CommanderData = TeamCommander.data_for_setting()
	if commander != null:
		for team: int in [0, 1]:
			if commander_teams & (1 << team):
				_commanders[team] = TeamCommander.new(team, commander)
	mode.zone_moved.connect(func(_c: Vector3) -> void:
		_release_squads()
		for c: TeamCommander in _commanders.values():
			c.reset()
		_update_commanders(0.0)   # a first picture round the new zone, for the axes
		if _axes_on():
			_assign_axes()
		_order_all())
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
		await get_tree().process_frame   # the map's own PlayerRig (freed by NetGame) is gone
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
	if _axes_on() and mode.has_started():
		_assign_axes()   # the first zone was announced before the bots were found


## Starts looking after a bot: respawns, contacts, orders.
func _adopt(bot: BotController) -> void:
	if _bots.has(bot):
		return
	_bots.append(bot)
	# Out of every list the moment it leaves the tree, whoever frees it (NetGame removes
	# bots for joining players): a freed bot in a list crashed the release server.
	bot.tree_exiting.connect(_forget_bot.bind(bot))
	bot.tank.tree_exiting.connect(_forget_bot.bind(bot))
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
	var size: int = _target_size()
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


## Tanks per team: MatchSettings.team_size, or more if players crowd one team (the other
## team then gets bots to match).
func _target_size() -> int:
	MatchSettings.load_settings()
	var size: int = MatchSettings.team_size
	var game: NetGame = NetSession.instance.game if NetRole.is_host() else null
	if size > 0 and game != null:
		size = maxi(size, maxi(game.player_count(0), game.player_count(1)))
	return size


## Host: a player joins `team`. If the team is already full, a bot leaves to make room
## (one that is knocked out, if any). Returns the bot's tank, already out of the bot
## lists and without its controller; the caller removes it from the game.
func make_room(team: int) -> Tank:
	var size: int = _target_size()
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
	_order_queue.erase(bot)
	for d: Dictionary in [_hold, _respawn, _ordered_radius, _depart, _goals, _respawned,
			_role, _partner, _role_time, _flank, _hunt, _hunt_think, _axis, _support,
			_assembled, _assembly_wait, _no_wait, _mate, _mine_stand, _mine_think, _mined_zone,
			_ordered_threat, _squad_task]:
		d.erase(bot)
	if is_instance_valid(bot):
		bot.squad_held = false
	for other: Variant in _partner.keys():
		if _partner[other] == bot:
			_partner[other] = null
	for other: Variant in _mate.keys():
		if _mate[other] == bot:
			_mate.erase(other)


func _add_bot(team: int, index: int) -> void:
	var tank: Tank = (load(_template_scene) as PackedScene).instantiate()
	_bot_serial += 1
	tank.name = "Team%dBot%d" % [team, _bot_serial]
	tank.team = team
	tank.data = _template_data
	var pool: Array[TankConfig] = mode.data.bot_configs
	if not pool.is_empty():
		tank.config = BotTankPick.pick(pool, BotTankPick.team_bot_configs(get_tree(), team),
				maxi(_target_size(), BotTankPick.team_count(get_tree(), team) + 1), _rng)
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
	for i: int in range(_order_queue.size() - 1, -1, -1):
		if not is_instance_valid(_order_queue[i]):
			_order_queue.remove_at(i)
	_order_wait -= delta
	_update_situation(delta)
	_update_commanders(delta)
	_update_order_queue()
	_update_bounding(delta)
	for bot_v: Variant in _bots:
		var bot: BotController = (bot_v as BotController) if is_instance_valid(bot_v) else null
		if not is_instance_valid(bot) or not is_instance_valid(bot.tank):
			continue
		if _respawn.has(bot):
			_update_respawn(bot, delta)
			continue
		if bot.tank.is_knocked_out():
			continue
		bot.fight_focus = mode.get_center()   # the squad looks out near the zone
		_update_mines(bot, delta)
		if _depart.has(bot):
			_depart[bot] = float(_depart[bot]) - delta
			if float(_depart[bot]) > 0.0:
				continue
			_depart.erase(bot)
			_order_into_zone(bot)
			continue
		if _order_queue.has(bot):
			continue   # a new order is on its way
		if bot.is_relocating():
			continue   # pulling back after hits: its own order runs first
		if _support.has(bot):
			_update_support(bot, delta)
			continue
		if _update_hunt(bot, delta):
			continue
		if _update_follow(bot, delta):
			continue
		if _axes_on() and not _assembled.has(bot):
			_update_assembly(bot, delta)
			continue
		if _role.has(bot):
			continue   # moving up in turns (_update_bounding)
		var radius: float = mode.get_radius()
		var shrunk: bool = float(_ordered_radius.get(bot, radius)) > radius / INNER_SHARE
		if bot.has_orders_left():
			if shrunk:
				_queue_order(bot)
			continue
		if not _is_inside(bot.tank.global_position, radius):
			_queue_order(bot)
			continue
		var cmd: TeamCommander = _commanders.get(bot.tank.team)
		if cmd != null and cmd.data.threat_shift_share > 0.0 and _ordered_threat.has(bot) \
				and int(_ordered_threat[bot]) != cmd.threat_lane:
			_queue_order(bot)   # the threat moved round: shift (TeamCommander)
			continue
		_hold[bot] = float(_hold.get(bot, HOLD_MAX_S)) - delta
		if float(_hold[bot]) <= 0.0:
			_queue_order(bot)


## The zone's defence: a bot standing near the open zone sends its squad to mine the
## ways in on the enemy's side (roads first). With all its mines out for this zone it
## lays no more until the zone moves; out of mines while out, the squad is recalled to
## refill (SquadData.kit_refill_s a man).
func _update_mines(bot: BotController, delta: float) -> void:
	if _squad_task.has(bot):
		return   # its squad is out in an ambush (TeamCommander)
	var squad: Squad = bot.tank.squad
	if squad == null or not is_instance_valid(squad) or squad.data.mine == null \
			or not mode.is_zone_open() or squad.get_state() == Squad.State.WIPED \
			or squad.get_state() == Squad.State.RETURNING or squad.is_mine_job():
		return
	var flat := Vector2(bot.tank.global_position.x - mode.get_center().x,
			bot.tank.global_position.z - mode.get_center().z)
	if flat.length() > mode.get_radius() + MINE_NEAR_ZONE_M \
			or bot.tank.linear_velocity.length() > MINE_STILL_MPS:
		_mine_stand[bot] = 0.0
		return
	_mine_stand[bot] = float(_mine_stand.get(bot, 0.0)) + delta
	var eager: float = MINES_FIRST_SHARE if bot.get_role().mines_first else 1.0
	if float(_mine_stand[bot]) < MINE_AFTER_S * eager:
		return
	_mine_think[bot] = float(_mine_think.get(bot, 0.0)) - delta
	if float(_mine_think[bot]) > 0.0:
		return
	_mine_think[bot] = MINE_THINK_S * eager
	var all_out: bool = squad.get_mines_out() >= squad.data.max_mines_out
	if squad.get_mines_carried() > 0:
		if all_out and int(_mined_zone.get(bot, -1)) == mode.get_zone_number():
			return
		var spot: Vector3 = _mine_spot(bot, squad)
		if spot != Vector3.INF:
			bot.order_squad(Squad.ORDER_MINE, spot)
			if squad.get_mines_out() + 1 >= squad.data.max_mines_out:
				_mined_zone[bot] = mode.get_zone_number()
	elif squad.is_out() and not all_out:
		bot.order_squad(Squad.ORDER_RECALL, Vector3.ZERO)


## A place for the next mine (see _update_mines), or INF if none will do.
func _mine_spot(bot: BotController, squad: Squad) -> Vector3:
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	var centre: Vector3 = mode.get_center()
	var threat: Vector3 = bot.get_threat_direction()
	if threat == Vector3.ZERO:
		threat = -mode.get_spawn_direction(bot.tank.team)   # the other team's side
	threat.y = 0.0
	threat = threat.normalized() if threat.length() > 0.01 else Vector3.FORWARD
	var own_mines: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group(Mine.GROUP):
		var m := node as Mine
		if m != null and m.get_team() == bot.tank.team:
			own_mines.append(m.global_position)
	var reach: float = squad.data.max_distance_from_tank_m - 30.0
	var radius: float = mode.get_radius()
	var best := Vector3.INF
	var best_score: float = -INF
	for i: int in MINE_CANDIDATES:
		var dir: Vector3 = threat.rotated(Vector3.UP,
				deg_to_rad(_rng.randf_range(-MINE_SPREAD_DEG, MINE_SPREAD_DEG)))
		var p: Vector3 = centre + dir * _rng.randf_range(radius * MINE_INNER_SHARE,
				radius + MINE_OUTSIDE_M)
		if Squad._flat(p - bot.tank.global_position).length() > reach \
				or not MapEdge.contains(get_tree(), p):
			continue
		if map != null and map.is_blocked(p):
			continue
		var near_own: bool = false
		for m: Vector3 in own_mines:
			if Squad._flat(m - p).length() < MINE_GAP_M:
				near_own = true
				break
		if near_own:
			continue
		# Roads first; then near the tank, so the squad gets there before the fight does.
		var score: float = _rng.randf() - Squad._flat(p - bot.tank.global_position).length() / reach
		if map != null and map.is_road(p):
			score += MINE_ROAD_BONUS
		if score > best_score:
			best_score = score
			best = p
	return best


## The zone moved: every bot gets a new order, in random order so no team goes first.
func _order_all() -> void:
	_hunt.clear()
	_order_queue.clear()
	for bot: BotController in _bots:
		if _can_be_ordered(bot):
			_order_queue.append(bot)
	_order_queue.shuffle()


func _can_be_ordered(bot: BotController) -> bool:
	return is_instance_valid(bot) and is_instance_valid(bot.tank) and not bot.tank.is_knocked_out() \
			and not _depart.has(bot) and not _respawn.has(bot)


func _queue_order(bot: BotController) -> void:
	if not _order_queue.has(bot):
		_order_queue.append(bot)


## Gives the next bot in the queue its order, when one is due. Bots that have since been
## knocked out or are about to leave a spawn drop out without using the turn.
func _update_order_queue() -> void:
	if _order_wait > 0.0:
		return
	while not _order_queue.is_empty():
		var bot: BotController = _order_queue.pop_front()
		if _can_be_ordered(bot):
			_order_into_zone(bot)
			_order_wait = ORDER_INTERVAL_S
			return


## Hold at the spawn for a moment, then go (staggered per team).
func _depart_later(bot: BotController, delay: float) -> void:
	bot.order_move([bot.tank.global_position], 0.0)
	_depart[bot] = delay


# --- Bounding ------------------------------------------------------------------------

func _update_bounding(delta: float) -> void:
	if not _order_queue.is_empty():
		return   # pairs form once the bots have their orders, or they'd re-pair per bot
	var teams: Dictionary = {}  # team -> bots that should bound
	for bot: BotController in _bots:
		if _wants_bounding(bot):
			# With attack axes, pairs are formed per axis (key: team and axis).
			var key: int = bot.tank.team * 10 + (_axis_of(bot) + 1 if _axes_on() else 0)   # per side
			if not teams.has(key):
				teams[key] = []
			(teams[key] as Array).append(bot)
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
			or _hunt.has(bot) or bot.is_relocating() or _support.has(bot) \
			or (_axes_on() and _lead_of(bot) != null):
		return false
	if _axes_on() and not _assembled.has(bot):
		return false   # on its way to (or waiting at) its assembly point
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
		if _order_wait > 0.0:
			return   # one new pair at a time: its move is as dear as an order
		_order_wait = ORDER_INTERVAL_S
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
		_queue_order(bot)


## The next position for a bound: a good spot (cover, hull down, sight towards the
## enemy) about bound_length_m towards the zone, or in the zone if that is closer.
func _bound_spot(bot: BotController) -> Vector3:
	var t: TacticsData = _tactics_of(bot)
	var c: Vector3 = mode.get_center()
	var p: Vector3 = bot.tank.global_position
	var inner: float = mode.get_radius() * INNER_SHARE
	if _axes_on():
		# Towards the own axis' entry point, not the zone centre.
		var entry: Vector3 = _entry_point(bot)
		var to_entry := Vector3(entry.x - p.x, 0.0, entry.z - p.z)
		if to_entry.length() <= t.bound_length_m:
			return _choose_spot(bot, mode.get_radius() * ENTRY_HOLD_SHARE, entry)
		return _choose_spot(bot, t.bound_length_m * 0.35,
				p + to_entry.normalized() * t.bound_length_m * 0.8,
				t.bound_length_m * BOUND_MIN_PROGRESS)
	var to_zone := Vector3(c.x - p.x, 0.0, c.z - p.z)
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
		return not _axes_on()   # with attack axes the gap is for getting into place
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
	var role: BotRoleData = bot.get_role()
	if _axes_on():
		_order_on_axis(bot, urgent)
		_ordered_radius[bot] = radius
		_hold[bot] = _rng.randf_range(role.hold_min_s, role.hold_max_s)
		return
	var goal: Vector3 = _choose_spot(bot, radius * INNER_SHARE)
	_goals[bot] = goal
	bot.order_path(goal, _tactics_of(bot).travel_throttle, urgent, _flank_point(bot, goal))
	_ordered_radius[bot] = radius
	_hold[bot] = _rng.randf_range(role.hold_min_s, role.hold_max_s)


# --- Attack axes, assembly and support ------------------------------------------------

func _axes_on() -> bool:
	return mode.data.bot_attack_axes


## A new zone: every bot gets its own way in, its role's axis_spread_deg off its team's
## side, left and right in turn (the widest roles first, so scouts and flankers end up on
## both flanks); roles that hold outside (BotRoleData.enters ON_ADVANTAGE / NEVER) watch
## from there until the moment comes (_update_situation); the rest pair up per side and
## assemble, unless they are already near the zone.
func _assign_axes() -> void:
	_assembled.clear()
	_assembly_wait.clear()
	_no_wait.clear()
	_axis.clear()
	_angle.clear()
	_support.clear()
	_entering.clear()
	_mate.clear()
	_axis_dirs.clear()
	var c: Vector3 = mode.get_center()
	var teams: Dictionary = {}  # team -> bots
	for bot_v: Variant in _bots:
		var bot: BotController = (bot_v as BotController) if is_instance_valid(bot_v) else null
		if is_instance_valid(bot) and is_instance_valid(bot.tank):
			if not teams.has(bot.tank.team):
				teams[bot.tank.team] = []
			(teams[bot.tank.team] as Array).append(bot)
	var first: bool = not _axes_assigned_once
	for team: int in teams:
		var group: Array = teams[team]
		group.shuffle()
		group.sort_custom(func(x: BotController, y: BotController) -> bool:
			return x.get_role().axis_spread_deg > y.get_role().axis_spread_deg)
		var side: int = 1 if _rng.randf() < 0.5 else -1
		var last_on_side: Dictionary = {}  # side -> last unpaired bot going in
		# The commander's main effort: koth_main_share of those going in take its side.
		var cmd: TeamCommander = _commanders.get(team)
		var going: int = 0
		for bot: BotController in group:
			if not _holds_outside(bot):
				going += 1
		var main_n: int = roundi(going * cmd.data.koth_main_share) if cmd != null and cmd.main_lane >= 0 and going >= 3 else 0
		for bot: BotController in group:
			_set_angle(bot, side)
			side = -side
			if _holds_outside(bot):
				_support[bot] = true
				continue
			if main_n > 0:
				main_n -= 1
				_set_main_angle(bot, cmd.main_lane - 1)
			var my_side: int = int(_axis[bot])
			var other: BotController = last_on_side.get(my_side)
			if other != null:
				_mate[bot] = other
				_mate[other] = bot
				last_on_side.erase(my_side)
			else:
				last_on_side[my_side] = bot
			var flat := Vector2(bot.tank.global_position.x - c.x, bot.tank.global_position.z - c.z)
			if not first and flat.length() - mode.get_radius() \
					< mode.data.assembly_distance_m * ASSEMBLY_SKIP_SHARE:
				_assembled[bot] = true   # already close: no going back out to assemble
	_axes_assigned_once = true


## Its way in on `side` (-1 left, 1 right): its role's spread, a little varied.
func _set_angle(bot: BotController, side: int) -> void:
	_axis[bot] = side
	_angle[bot] = float(side) * bot.get_role().axis_spread_deg * _rng.randf_range(0.8, 1.2)


## Its way in on the commander's main effort: its side (`main_side` -1 left, 1 right, along
## the lateral the commander's lanes use) at its role's spread, or near straight in (0).
func _set_main_angle(bot: BotController, main_side: int) -> void:
	var spread: float = bot.get_role().axis_spread_deg
	if main_side == 0:
		_angle[bot] = float(_axis[bot]) * spread * _rng.randf_range(0.1, 0.3)
	else:
		_axis[bot] = main_side
		_angle[bot] = float(main_side) * spread * _rng.randf_range(0.8, 1.2)


## A role that watches from outside the zone and isn't going in now (TeamSituation).
func _holds_outside(bot: BotController) -> bool:
	return TeamSituation.holds_outside(bot, _situation.get(bot.tank.team), _kos, _entering,
			_tactics_of(bot))


## This bot's side (-1 left, 1 right); a bot that came later takes the side of its
## team with fewer bots.
func _axis_of(bot: BotController) -> int:
	if _axis.has(bot):
		return int(_axis[bot])
	var count: Dictionary = {-1: 0, 1: 0}
	for other_v: Variant in _axis:
		var other: BotController = (other_v as BotController) if is_instance_valid(other_v) else null
		if is_instance_valid(other) and is_instance_valid(other.tank) \
				and other.tank.team == bot.tank.team:
			count[int(_axis[other])] = int(count[int(_axis[other])]) + 1
	var side: int = -1 if int(count[-1]) < int(count[1]) else 1
	_set_angle(bot, side)
	if _holds_outside(bot):
		_support[bot] = true
	return side


## Flat unit vector from the zone centre out along this bot's way in.
func _axis_dir(bot: BotController) -> Vector3:
	_axis_of(bot)
	return mode.get_spawn_direction(bot.tank.team).rotated(Vector3.UP,
			deg_to_rad(float(_angle.get(bot, 0.0))))


func _entry_point(bot: BotController) -> Vector3:
	return mode.get_center() + _axis_dir(bot) * mode.get_radius() * ENTRY_SHARE


## Orders a bot along its axis: to its assembly point first, then to a spot round its
## entry point (bounding takes it in when near), or to its support position.
func _order_on_axis(bot: BotController, urgent: bool) -> void:
	var c: Vector3 = mode.get_center()
	var dir: Vector3 = _axis_dir(bot)
	var goal: Vector3
	var role: BotRoleData = bot.get_role()
	var lead: BotController = _lead_of(bot)
	var sit: TeamSituation = _situation.get(bot.tank.team)
	if _support.has(bot) and role.hit_and_run and sit != null and sit.enemy_centre != Vector3.INF:
		goal = _harass_spot(bot, sit.enemy_centre)
	elif _support.has(bot):
		var lo: float = role.standoff_min_m if role.standoff_max_m > 0.0 else mode.data.support_distance_min_m
		var hi: float = role.standoff_max_m if role.standoff_max_m > 0.0 else mode.data.support_distance_max_m
		var out: float = mode.get_radius() + _rng.randf_range(lo, hi)
		# Roles that keep moving (short holds) take a new spot along their flank each time.
		var swing: float = SCOUT_SWING_DEG if role.hold_max_s < HOLD_MIN_S else 0.0
		var around: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(_rng.randf_range(-swing, swing)))
		goal = _outside_spot(bot, c + around * out, SUPPORT_SPOT_RADIUS_M)
	elif lead != null:
		goal = _choose_spot(bot, FOLLOW_SPOT_RADIUS_M, _behind_lead(bot, lead))
		_lead_at[bot] = lead.tank.global_position
	elif not _assembled.has(bot):
		_assembly_wait.erase(bot)
		goal = _outside_spot(bot, c + dir * (mode.get_radius() + mode.data.assembly_distance_m),
				ASSEMBLY_SPOT_RADIUS_M)
	else:
		goal = _choose_spot(bot, mode.get_radius() * ENTRY_HOLD_SHARE, _hold_point(bot))
	_goals[bot] = goal
	bot.order_path(goal, _tactics_of(bot).travel_throttle, urgent)


## A harasser comes up off the flank of the known enemies (on its own side), at its
## role's harass range from them, facing them: a new place each time.
func _harass_spot(bot: BotController, enemies: Vector3) -> Vector3:
	var role: BotRoleData = bot.get_role()
	var c: Vector3 = mode.get_center()
	var their_way := Vector3(enemies.x - c.x, 0.0, enemies.z - c.z)
	if their_way.length() < 1.0:
		their_way = -mode.get_spawn_direction(bot.tank.team)
	var side: float = float(_axis_of(bot))
	var lateral: Vector3 = their_way.normalized().cross(Vector3.UP) * side
	var swing: float = deg_to_rad(_rng.randf_range(-SCOUT_SWING_DEG, SCOUT_SWING_DEG))
	var ideal: Vector3 = enemies + lateral.rotated(Vector3.UP, swing) \
			* role.pick_harass_range(_rng)
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	if map == null:
		return ideal
	var threat := Vector3(enemies.x - ideal.x, 0.0, enemies.z - ideal.z).normalized()
	var friends := PackedVector3Array()
	var exclude: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		exclude.append((node as Tank).get_rid())
	return map.find_position(mode.get_world_3d(), ideal, SUPPORT_SPOT_RADIUS_M, threat, enemies,
			role.harass_range_max_m, bot.tank.global_position, friends, _tactics_of(bot), _rng, exclude)


## The brawler a follower (BotRoleData.Enter.WITH_LEAD) keeps behind: the nearest
## living one of its team; null if none (it goes in as a brawler then) or not a follower.
func _lead_of(bot: BotController) -> BotController:
	if bot.get_role().enters != BotRoleData.Enter.WITH_LEAD:
		return null
	var best: BotController = null
	var best_d: float = INF
	for other_v: Variant in _bots:
		var other: BotController = (other_v as BotController) if is_instance_valid(other_v) else null
		if other == bot or not is_instance_valid(other) or not is_instance_valid(other.tank) \
				or other.tank.team != bot.tank.team or other.tank.is_knocked_out() \
				or _respawn.has(other) or other.get_role().enters != BotRoleData.Enter.ALWAYS:
			continue
		var d: float = other.tank.global_position.distance_to(bot.tank.global_position)
		if d < best_d:
			best = other
			best_d = d
	return best


## follow_m behind `lead`, seen from the enemy.
func _behind_lead(bot: BotController, lead: BotController) -> Vector3:
	var threat: Vector3 = lead.get_threat_direction()
	if threat == Vector3.ZERO:
		threat = -mode.get_spawn_direction(bot.tank.team)
	return lead.tank.global_position - Vector3(threat.x, 0.0, threat.z).normalized() \
			* bot.get_role().follow_m


## A follower: a new spot behind its lead when the lead has moved on or after a while.
## True while it follows (the zone orders wait).
func _update_follow(bot: BotController, delta: float) -> bool:
	if not _axes_on():
		return false
	var lead: BotController = _lead_of(bot)
	if lead == null:
		_lead_at.erase(bot)
		return false
	if not _lead_at.has(bot):
		_queue_order(bot)
		return true
	if bot.has_orders_left():
		return true
	_hold[bot] = float(_hold.get(bot, HOLD_MAX_S)) - delta
	var moved: float = (_lead_at[bot] as Vector3).distance_to(lead.tank.global_position)
	if moved > bot.get_role().follow_m * FOLLOW_REORDER_SHARE or float(_hold[bot]) <= 0.0:
		_queue_order(bot)
	return true


# --- Situation -----------------------------------------------------------------------

## Knock-outs go in the log (the kill feed: public); every situation_interval_s each
## team reads the fight (TeamSituation), and outside roles whose moment came or went
## get new orders.
func _update_situation(delta: float) -> void:
	var t: TacticsData = TacticalMap.DEFAULT_TACTICS
	for bot_v: Variant in _bots:
		var bot: BotController = (bot_v as BotController) if is_instance_valid(bot_v) else null
		if is_instance_valid(bot):
			t = _tactics_of(bot)
			break
	_kos.update(get_tree(), delta, t.momentum_window_s)
	_situation_wait -= delta
	if _situation_wait > 0.0:
		return
	_situation_wait = t.situation_interval_s
	var budget_share: float = mode.get_budget_left() / maxf(mode.data.zone_point_budget, 1.0)
	# Short of time: the zone shrinks towards its close, or its points run out.
	var time_short: bool = mode.is_zone_open() and ((mode.get_shrink_progress() > 0.0
			and mode.get_time_to_next_event() < t.pressure_time_s) or budget_share < t.pressure_budget_share)
	for team: int in [0, 1]:
		var mine: float = mode.get_score(team)
		var theirs: float = mode.get_best_other_score(team)
		_situation[team] = TeamSituation.assess(team, _bots, get_tree(),
				func(p: Vector3) -> bool: return _is_in_open_zone(p), mode.get_center(),
				mode.get_radius(), _kos.entries, _kos.clock, mine < theirs, mine > theirs, time_short, t)
	TeamSituation.ensure_spearhead(_bots, _kos, _entering, t)
	# Scouts turn harassers once the fight is on (and back): new orders for them.
	for bot: BotController in TeamSituation.apply_contact_roles(_bots, _situation):
		if not _respawn.has(bot) and not _depart.has(bot) and not bot.tank.is_knocked_out():
			_hunt.erase(bot)
			_queue_order(bot)
	if not _axes_on():
		return
	for bot_v: Variant in _bots:
		var bot: BotController = (bot_v as BotController) if is_instance_valid(bot_v) else null
		if not is_instance_valid(bot) or not is_instance_valid(bot.tank) or bot.tank.is_knocked_out() \
				or _respawn.has(bot) or _depart.has(bot):
			continue
		var outside: bool = _holds_outside(bot)
		if outside == _support.has(bot):
			continue
		if outside:
			_support[bot] = true
			_hunt.erase(bot)
		else:
			_support.erase(bot)
			_assembled[bot] = true   # going in from where it watched: no assembling
		_queue_order(bot)


## The team's reading of the fight (null before the first).
func get_situation(team: int) -> TeamSituation:
	return _situation.get(team)


## A spot outside the zone near `ideal`, watching the zone (cover, hull down, sight).
func _outside_spot(bot: BotController, ideal: Vector3, radius: float) -> Vector3:
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	if map == null:
		return ideal
	var c: Vector3 = mode.get_center()
	var threat := Vector3(c.x - ideal.x, 0.0, c.z - ideal.z).normalized()
	var friends := PackedVector3Array()
	for other_v: Variant in _bots:
		var other: BotController = (other_v as BotController) if is_instance_valid(other_v) else null
		if other != bot and is_instance_valid(other) and is_instance_valid(other.tank) \
				and other.tank.team == bot.tank.team and _goals.has(other):
			friends.append(_goals[other])
	var exclude: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		exclude.append((node as Tank).get_rid())
	return map.find_position(mode.get_world_3d(), ideal, radius, threat, c,
			mode.get_radius(), bot.tank.global_position, friends, _tactics_of(bot), _rng, exclude)


## A bot on its way to, or waiting at, its assembly point. It goes on when its partner
## (the other bot on its axis) is there too, or has gone on, or is out, or after
## assembly_wait_max_s; a respawned bot doesn't wait.
func _update_assembly(bot: BotController, delta: float) -> void:
	if bot.has_orders_left():
		return
	if not _goals.has(bot):
		_queue_order(bot)   # e.g. added after the axes were chosen
		return
	_assembly_wait[bot] = float(_assembly_wait.get(bot, 0.0)) + delta
	var partner_v: Variant = _mate.get(bot)
	var partner: BotController = (partner_v as BotController) if is_instance_valid(partner_v) else null
	if partner != null and (not is_instance_valid(partner) or not is_instance_valid(partner.tank)):
		partner = null
	var ready: bool = partner == null or partner.tank.is_knocked_out() or _respawn.has(partner) \
			or _assembled.has(partner) or _assembly_wait.has(partner)
	if ready or _no_wait.has(bot) or float(_assembly_wait[bot]) >= mode.data.assembly_wait_max_s:
		_assembled[bot] = true
		_no_wait.erase(bot)
		_queue_order(bot)


## A support bot: holds its watching spot outside the zone, a new one now and then
## (and when the zone shrank). It fights from there on its own; it doesn't hunt.
func _update_support(bot: BotController, delta: float) -> void:
	if bot.has_orders_left():
		return
	var radius: float = mode.get_radius()
	var shrunk: bool = float(_ordered_radius.get(bot, radius)) > radius / INNER_SHARE
	_hold[bot] = float(_hold.get(bot, HOLD_MAX_S)) - delta
	if shrunk or float(_hold[bot]) <= 0.0 or not _goals.has(bot):
		_queue_order(bot)


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
			and best - HUNT_OUTSIDE_PENALTY_M <= _engage_m(bot) * 1.2:
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


## How far this bot likes to fight from (its role's hunt_engage_m, else the tactics').
func _engage_m(bot: BotController) -> float:
	var role: BotRoleData = bot.get_role()
	return role.hunt_engage_m if role.hunt_engage_m > 0.0 else _tactics_of(bot).hunt_engage_m


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
			minf(_engage_m(bot), dist * 0.8)))
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
	for other_v: Variant in _bots:
		var other: BotController = (other_v as BotController) if is_instance_valid(other_v) else null
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
	for other_v: Variant in _bots:
		var other: BotController = (other_v as BotController) if is_instance_valid(other_v) else null
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
		threat = -mode.get_spawn_direction(bot.tank.team)
	var friends := PackedVector3Array()
	var exclude: Array[RID] = []
	for other_v: Variant in _bots:
		var other: BotController = (other_v as BotController) if is_instance_valid(other_v) else null
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
	for other_v: Variant in _bots:
		var other: BotController = (other_v as BotController) if is_instance_valid(other_v) else null
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
	if _axes_on() and not _support.has(bot):
		_assembled.erase(bot)   # back along its axis: via the assembly point, no waiting
		_no_wait[bot] = true
	_depart_later(bot, _rng.randf_range(0.0, DEPART_INTERVAL_S))


# --- The commander (TeamCommander) ----------------------------------------------------

## The commanders' picture of the fight round the zone. Lanes across the team's way in:
## the lateral off the zone centre (positive = the side its axes' positive angles take),
## the middle third within half the radius.
func _update_commanders(delta: float) -> void:
	if _commanders.is_empty() or not mode.has_started():
		return
	var centre: Vector3 = mode.get_center()
	var radius: float = maxf(mode.get_radius(), 1.0)
	for team: int in _commanders:
		var c: TeamCommander = _commanders[team]
		var spawn: Vector3 = mode.get_spawn_direction(team)
		var facing: Vector3 = -spawn
		var lateral: Vector3 = spawn.rotated(Vector3.UP, PI * 0.5)
		var reach: float = c.data.picture_reach_m
		var own_tanks := PackedVector3Array()
		for tank: Tank in _team_tanks(team):
			if not tank.is_knocked_out() and Squad._flat(tank.global_position - centre).length() <= reach:
				own_tanks.append(tank.global_position)
		var seen: Dictionary = {}
		for bot_v: Variant in _bots:
			var bot: BotController = (bot_v as BotController) if is_instance_valid(bot_v) else null
			if is_instance_valid(bot) and is_instance_valid(bot.tank) and bot.tank.team == team:
				var k: Dictionary = bot.get_known_enemies(c.data.memory_s)
				for enemy: Variant in k:
					seen[enemy] = k[enemy]
		var known := PackedVector3Array()
		for enemy: Variant in seen:
			var at: Vector3 = seen[enemy]
			if Squad._flat(at - centre).length() <= reach:
				known.append(at)
		if c.think(delta, _kos.clock, own_tanks, known, _kos,
				func(p: Vector3) -> int:
					var across: float = Squad._flat(p - centre).dot(lateral) / radius
					return 0 if across < -0.5 else (2 if across > 0.5 else 1),
				func(p: Vector3) -> float: return Squad._flat(p - centre).dot(facing)):
			_give_squad_tasks(team, c)


## Flat unit vector from the zone centre towards the commander's lane `lane` on the
## enemy's side (the middle: straight at them).
func _lane_dir(team: int, lane: int) -> Vector3:
	var spawn: Vector3 = mode.get_spawn_direction(team)
	var lateral: Vector3 = spawn.rotated(Vector3.UP, PI * 0.5)
	return (-spawn * LANE_FORWARD + lateral * float(lane - 1)).normalized()


## Where a bot holds in the zone: round its way in, or (TeamCommander, threat_shift_share
## of the orders) towards the side the most known enemies come from.
func _hold_point(bot: BotController) -> Vector3:
	var c: TeamCommander = _commanders.get(bot.tank.team)
	if c == null:
		return _entry_point(bot)
	_ordered_threat[bot] = c.threat_lane
	if c.threat_lane < 0 or _rng.randf() >= c.data.threat_shift_share:
		return _entry_point(bot)
	return mode.get_center() + _lane_dir(bot.tank.team, c.threat_lane) * mode.get_radius() * ENTRY_SHARE


## Commander ambushes (CommanderData.koth_ambush_squads): squads of bots near the zone go to
## covered spots ambush_ahead_m outside its edge on the threatened side, and hold there
## (not mining). A task ends when the threat moves, the squad lost half its men or is back
## on the tank, or the zone moves.
func _give_squad_tasks(team: int, c: TeamCommander) -> void:
	var want: int = c.data.koth_ambush_squads if c.threat_lane >= 0 and mode.is_zone_open() else 0
	var point := Vector3.INF
	if want > 0:
		point = mode.get_center() + _lane_dir(team, c.threat_lane) * (mode.get_radius() + c.data.ambush_ahead_m)
	var have: int = 0
	for bot_v: Variant in _squad_task.keys():
		var bot: BotController = (bot_v as BotController) if is_instance_valid(bot_v) else null
		if not is_instance_valid(bot) or not is_instance_valid(bot.tank):
			_squad_task.erase(bot_v)
			continue
		if bot.tank.team != team:
			continue
		var squad: Squad = bot.tank.squad
		var task: Array = _squad_task[bot]
		var done: bool = want <= 0 or bot.tank.is_knocked_out() or squad == null or not is_instance_valid(squad) \
				or squad.get_alive_count() * 2 <= squad.data.soldier_count \
				or (task[0] as Vector3).distance_to(point) > SQUAD_TASK_MOVED_M \
				or (squad.is_mounted() and _kos.clock - float(task[1]) > SQUAD_TASK_BACK_S)
		if done:
			_squad_task.erase(bot)
			bot.squad_held = false
		else:
			have += 1
	if have >= want or not TacticalMap.may_plan():
		return
	var candidates: Array[BotController] = []
	for bot_v: Variant in _bots:
		var bot: BotController = (bot_v as BotController) if is_instance_valid(bot_v) else null
		if not is_instance_valid(bot) or not is_instance_valid(bot.tank) or bot.tank.team != team \
				or bot.tank.is_knocked_out() or _respawn.has(bot) or _squad_task.has(bot):
			continue
		var squad: Squad = bot.tank.squad
		if squad == null or not is_instance_valid(squad) or squad.get_state() == Squad.State.WIPED \
				or squad.get_state() == Squad.State.RETURNING \
				or squad.get_alive_count() < squad.data.soldier_count \
				or Squad._flat(bot.tank.global_position - point).length() \
						> squad.data.max_distance_from_tank_m * SQUAD_TASK_REACH_SHARE:
			continue
		candidates.append(bot)
	candidates.sort_custom(func(a: BotController, b: BotController) -> bool:
		return a.tank.global_position.distance_to(point) < b.tank.global_position.distance_to(point))
	var facing: Vector3 = Squad._flat(point - mode.get_center()).normalized()
	for i: int in mini(want - have, candidates.size()):
		var bot: BotController = candidates[i]
		var squad: Squad = bot.tank.squad
		var spot: Vector3 = point
		var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene, squad.data.tactics)
		if map != null:
			spot = map.find_position(mode.get_world_3d(), point, SQUAD_TASK_RADIUS_M, facing,
					point + facing * 200.0, 200.0, bot.tank.global_position, PackedVector3Array(),
					squad.data.tactics, _rng, [bot.tank.get_rid()])
		_squad_task[bot] = [point, _kos.clock]
		bot.squad_held = true
		bot.order_squad(Squad.ORDER_MOVE, spot)
		if c.data.log_decisions:
			print("CMD team %d t=%.0f squad ambush %s" % [team, _kos.clock, TeamCommander.LANE_NAMES[c.threat_lane]])


func _release_squads() -> void:
	for bot_v: Variant in _squad_task:
		var bot: BotController = (bot_v as BotController) if is_instance_valid(bot_v) else null
		if is_instance_valid(bot):
			bot.squad_held = false
	_squad_task.clear()


## A lane's direction: this much towards the enemy for each unit to the side.
const LANE_FORWARD: float = 1.0
## Squad ambushes: as ThunderRoadBots.SQUAD_TASK_*.
const SQUAD_TASK_REACH_SHARE: float = 0.9
const SQUAD_TASK_MOVED_M: float = 80.0
const SQUAD_TASK_BACK_S: float = 20.0
const SQUAD_TASK_RADIUS_M: float = 50.0
