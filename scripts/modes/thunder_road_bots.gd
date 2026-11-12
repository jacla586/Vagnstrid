class_name ThunderRoadBots
extends Node
## Bots in ThunderRoad (ThunderRoadMode): fills both teams to MatchSettings.team_size and
## gives every BotController its orders. Attackers drive to a good spot inside the next
## checkpoint's radius; defenders take posts in their corridor between the next
## checkpoint's zone and the attackers, in the zone or just behind it (find_position,
## facing the attackers; ThunderRoadData.defender_post_*), move when the front moves or
## now and then, and send their squad to mine the road towards the attackers (it then
## lies in ambush by itself). A bot outside its corridor is sent
## back in. Fighting itself is the BotController's own.
##
## Attack (per team, in two phases; _update_assault): DEVELOP: scouts and harassers
## work the flanks, snipers look for firing spots on the known defenders
## (SNIPER_RANGE_*), the rest move up to a line DEVELOP_STANDOFF_M short of the zone
## in pairs that bound (one watches while the other drives a leg of
## TacticsData.bound_length_m to a covered spot), each pair in its own lane across the
## corridor, and fight from there. ASSAULT: with the upper hand (more of them near the
## checkpoint than known defenders + ASSAULT_MARGIN after DEVELOP_MIN_S, a run of
## knock-outs, or time short / overtime) they drive into the zone and the snipers move
## up (SNIPER_ASSAULT_RANGE_*); it ends when they lose the upper hand. A RESERVE
## (RESERVE_SHARE of the team, at least one) always stays back RESERVE_BACK_M short of
## the zone to save a failed assault, until time is short.

## An attacker's job now (_job_of).
enum Job { OUTSIDE, SNIPER, RESERVE, DEVELOP, ASSAULT }
## Bounding state of a developing attacker.
enum Bound { MOVE, WATCH, HOLD }

@export var mode: ThunderRoadMode

static var instance: ThunderRoadBots

## An attacker is "at" the checkpoint inside this share of its capture radius.
const AT_CHECKPOINT_SHARE: float = 0.8
## Bots leave their spawn one by one this far apart (s).
const DEPART_INTERVAL_S: float = 2.0
## Defender posts (shares in ThunderRoadData.defender_post_*): ahead of the zone from at
## least this far past the front up to this far before the zone (m); behind it up to
## this far past the zone (m); at most this share of the corridor's half width from the
## road, searched within this radius (m).
const POST_FRONT_CLEAR_M: float = 120.0
const POST_AHEAD_M: float = 250.0
const POST_BEHIND_M: float = 180.0
const POST_ACROSS_SHARE: float = 0.6
const POST_RADIUS_M: float = 80.0
## Across the corridor (shares of its half width): wide roles (axis_spread_deg from
## WIDE_SPREAD_DEG) out on their flank, the rest within NARROW_ACROSS of the road.
const WIDE_SPREAD_DEG: float = 50.0
const WIDE_ACROSS_MIN: float = 0.6
const WIDE_ACROSS_MAX: float = 0.9
const NARROW_ACROSS: float = 0.4
## Flank reserves wait up to this far behind the zone (m)...
const RESERVE_BEHIND_M: float = 80.0
## ...and counterattack from this far to the side of the attackers in it, replanning
## when those have moved this far (m).
const COUNTER_OFFSET_M: float = 150.0
const COUNTER_REPLAN_M: float = 60.0
## Breakers' posts start this far behind their brawler's (m; up to its follow_m).
const LEAD_GAP_MIN_M: float = 40.0
## Roles that mine first (BotRoleData.mines_first) start and think this much sooner.
const MINES_FIRST_SHARE: float = 0.4
## Defenders look this far back along the road (m), over this width (m).
const LOOK_BACK_M: float = 300.0
const LOOK_SPREAD_M: float = 400.0
## A defender sends its squad to mine after standing (at its post, or halted) this long
## (s), and
## thinks about mines again this often (s).
const MINE_AFTER_S: float = 3.0
const MINE_THINK_S: float = 4.0
## Slower than this (m/s) a defender counts as standing for mining.
const MINE_STILL_MPS: float = 1.5
## Mines go between the checkpoint's zone and the attackers this share of the time, else
## in the zone; this far off the road's middle at most (m).
const MINE_BEFORE_ZONE_SHARE: float = 0.65
const MINE_ACROSS_M: float = 6.0
## Soldiers walk slowly: a mine goes at most this far along the road from the tank (m).
const MINE_WALK_MAX_M: float = 240.0
## A bot outside its corridor this long (s) is ordered back in, at most this often (s).
const OUTSIDE_ORDER_S: float = 5.0
## Attack phases: assault when the attackers near the checkpoint (within
## TacticsData.near_zone_m of its zone) outnumber the known defenders there by this,
## having developed at least DEVELOP_MIN_S; it lasts at least ASSAULT_HOLD_S.
const ASSAULT_MARGIN: int = 2
const DEVELOP_MIN_S: float = 30.0
const ASSAULT_HOLD_S: float = 30.0
## The developing line: this far short of the zone's near edge (m, give or take
## DEVELOP_SPREAD_M), lanes across this share of the corridor's half width.
const DEVELOP_STANDOFF_M: float = 220.0
const DEVELOP_SPREAD_M: float = 40.0
const DEVELOP_LANES_SHARE: float = 0.75
## A developing bot this near its line spot holds there (m).
const DEVELOP_ARRIVED_M: float = 30.0
## The reserve: this share of the team (at least one, from three tanks), this far short
## of the zone's near edge (m).
const RESERVE_SHARE: float = 0.2
const RESERVE_BACK_M: float = 420.0
## Snipers fire from this far from the known defenders (m), from 20-50 degrees off the
## road towards their side; closer in the assault. A new spot after a hold time
## (role hold_min_s..hold_max_s) or when the enemies have moved SNIPER_REPLAN_M.
const SNIPER_RANGE_MIN_M: float = 450.0
const SNIPER_RANGE_MAX_M: float = 650.0
const SNIPER_ASSAULT_RANGE_MIN_M: float = 250.0
const SNIPER_ASSAULT_RANGE_MAX_M: float = 350.0
const SNIPER_OFF_ROAD_MIN_DEG: float = 20.0
const SNIPER_OFF_ROAD_MAX_DEG: float = 50.0
const SNIPER_REPLAN_M: float = 120.0
## Attackers' smoke (BotController.request_screen, which keeps each tank's last salvo):
## at an assault's start SCREENERS_PER_ASSAULT bots (SCREENERS_MANY_DEFENDERS when that
## many defenders are known) are picked, nearest the zone, and screen towards the known
## defenders once within SCREEN_RANGE_M of them (or SCREEN_RANGE_M short of the zone).
## Developing, a bot starting a bound with defenders known near screens first with
## BOUND_SCREEN_CHANCE, at most one such screen per team per SCREEN_TEAM_GAP_S.
const SCREENERS_PER_ASSAULT: int = 1
const SCREENERS_MANY: int = 2
const SCREENERS_MANY_DEFENDERS: int = 3
const SCREEN_RANGE_M: float = 350.0
const BOUND_SCREEN_CHANCE: float = 0.2
const SCREEN_TEAM_GAP_S: float = 20.0
## A bound is screened only within this of the known defenders (m); a new assault
## gets no screeners within this long of the last assault screen (s).
const BOUND_SCREEN_RANGE_M: float = 500.0
const ASSAULT_SCREEN_GAP_S: float = 45.0
## Defenders: this share of the zone's brawlers (every other one) post out on their
## flank for crossfire over the zone; other near-road posts keep at least
## POST_CENTRE_GAP of the half width off the road.
const CROSSFIRE_SHARE_EVERY: int = 2
const POST_CENTRE_GAP: float = 0.15
## Goals are kept this far inside the corridor's edges (m).
const INSIDE_MARGIN_M: float = 40.0
const OUTSIDE_REORDER_S: float = 10.0

var _bots: Array[BotController] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _template: BotController
var _template_scene: String = ""
var _template_data: TankData
var _template_xform: Transform3D
var _bot_parent: Node
var _bot_serial: int = 0
# Per bot
var _ordered_cp: Dictionary = {}     # attackers: checkpoint index ordered to
var _ordered_front: Dictionary = {}  # defenders: front (s) when the post was given
var _post_s: Dictionary = {}         # defenders: their post's place along the road
var _repost: Dictionary = {}         # defenders: seconds to a new post
var _standing: Dictionary = {}       # seconds at the post with no orders left
var _mine_think: Dictionary = {}     # seconds to the next look at mines
var _mine_front: Dictionary = {}     # front (s) when the last mine was sent
var _depart: Dictionary = {}         # seconds before it may leave
var _urgent: Dictionary = {}         # next order is urgent (respawned)
var _back_in: Dictionary = {}        # seconds since it was ordered back into the corridor
# Roles (BotRoleData) and each team's reading of the fight (TeamSituation).
var _situation: Dictionary = {}      # team -> TeamSituation
var _situation_wait: float = 0.0
var _kos := TeamSituation.KnockoutLog.new()
var _entering: Dictionary = {}       # outside roles: clock they last had the moment
var _ordered_out: Dictionary = {}    # attackers: the job they were last ordered for (Job)
var _assault: Dictionary = {}        # attacking team -> clock the assault began (absent: developing)
var _developing_since: float = 0.0   # clock the attack last went (back) to developing
var _phase_cp: int = -1              # checkpoint the phase was decided for
var _reserve: Dictionary = {}        # attackers kept back
var _lane: Dictionary = {}           # developing attackers: lane share across the corridor
var _lane_partner: Dictionary = {}   # developing attackers: bounding partner (or null)
var _line_goal: Dictionary = {}      # developing attackers: their spot on the line
var _bound: Dictionary = {}          # developing attackers: Bound state
var _bound_time: Dictionary = {}     # seconds in that state
var _sniper_aim: Dictionary = {}     # snipers: enemy point their spot was chosen for
var _screeners: Dictionary = {}      # attackers to lay a screen in this assault
var _last_screen: Dictionary = {}    # team -> clock of its last tactical screen
var _last_assault_screen: Dictionary = {}  # team -> clock of its last assault screen
var _post_across: Dictionary = {}    # defenders: across share of the post given
var _hold: Dictionary = {}           # attackers holding outside: seconds to a new spot
var _countering: Dictionary = {}     # flank reserves: counterattacking now
var _ordered_pushed: Dictionary = {} # defenders: pushed_back when the post was given


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	_rng.randomize()
	if NetRole.is_client() or mode == null:
		set_physics_process(false)
		return
	mode.hold_start()
	mode.tank_placed.connect(_on_tank_placed)
	mode.round_started.connect(func(_n: int, _team: int) -> void: _reset_all())
	_find_bots.call_deferred()


func _find_bots() -> void:
	if NetRole.is_host():
		# The map loads first, NetGame a frame or more later: it sorts the map's bots
		# into teams (or removes them), and must know of every bot added here.
		while NetSession.instance.game == null:
			await get_tree().process_frame
		await get_tree().process_frame   # the map's own PlayerRig (freed by NetGame) is gone
	_remember_template()
	_fill_teams()
	for node: Node in get_tree().current_scene.find_children("*", "", true, false):
		var bot := node as BotController
		if bot != null and bot.tank != null and not bot.is_queued_for_deletion():
			_adopt(bot)
	_reset_all()
	mode.release_start()


func _adopt(bot: BotController) -> void:
	if _bots.has(bot):
		return
	_bots.append(bot)
	bot.respawn_delay_s = 0.0   # the mode brings it back
	bot.keep_goal = _keep_inside.bind(bot)


# --- Teams (as KothBots) ---------------------------------------------------------------

func _remember_template() -> void:
	for node: Node in get_tree().current_scene.find_children("*", "", true, false):
		var bot := node as BotController
		if bot != null and bot.tank != null and not bot.is_queued_for_deletion():
			_template = bot.duplicate() as BotController
			_template_scene = bot.tank.scene_file_path
			_template_data = bot.tank.data
			_template_xform = bot.tank.global_transform
			_bot_parent = bot.tank.get_parent()
			return


func _team_tanks(team: int) -> Array[Tank]:
	var out: Array[Tank] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank != null and tank.team == team and not tank.is_queued_for_deletion():
			out.append(tank)
	return out


## Both teams to MatchSettings.team_size tanks (players included).
func _fill_teams() -> void:
	var size: int = _target_size()
	if size <= 0 or _template == null:
		return
	for team: int in [0, 1]:
		var tanks: Array[Tank] = _team_tanks(team)
		var extra: int = tanks.size() - size
		while extra > 0:
			var bot: BotController = _bot_of_team(team)
			if bot == null:
				break
			_remove_bot(bot)
			extra -= 1
		for i: int in range(-extra):
			_add_bot(team, tanks.size() + i)


func _bot_of_team(team: int) -> BotController:
	var pick: BotController = null
	for node: Node in get_tree().current_scene.find_children("*", "", true, false):
		var bot := node as BotController
		if bot != null and is_instance_valid(bot.tank) and bot.tank.team == team \
				and not bot.is_queued_for_deletion():
			pick = bot
	return pick


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
	tank.global_transform = _template_xform.translated(Vector3(index * 12.0 + 12.0, 2.0, 0.0))
	var bot: BotController = _template.duplicate() as BotController
	bot.name = tank.name + "Controller"
	bot.tank = tank
	bot.waypoints = []
	parent.add_child(bot)
	var game: NetGame = NetSession.instance.game if NetRole.is_host() else null
	if game != null:
		game.add_bot_tank(tank)


## Takes a bot and its tank (and squad) out of the match (everywhere, when hosting).
func _remove_bot(bot: BotController) -> void:
	var tank: Tank = bot.tank
	_bots.erase(bot)
	_forget(bot)
	bot.queue_free()
	var game: NetGame = NetSession.instance.game if NetRole.is_host() else null
	if game != null:
		game.remove_tank(tank)
	else:
		tank.leave_wreck()
		if tank.squad != null and is_instance_valid(tank.squad):
			tank.squad.queue_free()
		tank.queue_free()


## Tanks per team: MatchSettings.team_size, or more if players crowd one team (the other
## team then gets bots to match).
func _target_size() -> int:
	MatchSettings.load_settings()
	var size: int = MatchSettings.team_size
	var game: NetGame = NetSession.instance.game if NetRole.is_host() else null
	if size > 0 and game != null:
		size = maxi(size, maxi(game.player_count(0), game.player_count(1)))
	return size


## Host: a player joins `team`. If the team is full a bot leaves to make room (a
## knocked-out one if any). Returns its tank, out of the bot lists and without its
## controller; the caller (NetGame) removes it from the game.
func make_room(team: int) -> Tank:
	var size: int = _target_size()
	if size <= 0 or _team_tanks(team).size() < size:
		return null
	var pick: BotController = null
	for bot: BotController in _bots:
		if not is_instance_valid(bot) or not is_instance_valid(bot.tank) or bot.tank.team != team:
			continue
		pick = bot
		if bot.tank.is_knocked_out():
			break
	if pick == null:
		return null
	var tank: Tank = pick.tank
	_bots.erase(pick)
	_forget(pick)
	pick.queue_free()
	return tank


## Host: a player left; bots fill the teams up again.
func refill() -> void:
	if _template == null:
		return
	var before: Array[BotController] = _bots.duplicate()
	_fill_teams()
	for node: Node in get_tree().current_scene.find_children("*", "", true, false):
		var bot := node as BotController
		if bot != null and bot.tank != null and not before.has(bot) and not bot.is_queued_for_deletion():
			_adopt(bot)
			_urgent[bot] = true


# --- Orders ------------------------------------------------------------------------------

func _reset_all() -> void:
	_assault.clear()
	_screeners.clear()
	_last_screen.clear()
	_last_assault_screen.clear()
	_phase_cp = -1
	var per_team: Dictionary = {}
	for bot: BotController in _bots:
		if not is_instance_valid(bot) or not is_instance_valid(bot.tank):
			continue
		_forget(bot)
		var n: int = int(per_team.get(bot.tank.team, 0))
		per_team[bot.tank.team] = n + 1
		_depart[bot] = n * DEPART_INTERVAL_S
		_urgent[bot] = true


func _forget(bot: BotController) -> void:
	for d: Dictionary in [_ordered_cp, _ordered_front, _post_s, _repost, _standing, _mine_think, _mine_front,
			_depart, _urgent, _back_in, _ordered_out, _hold, _countering, _ordered_pushed, _entering,
			_post_across, _reserve, _lane, _lane_partner, _line_goal, _bound, _bound_time, _sniper_aim,
			_screeners]:
		d.erase(bot)


func _on_tank_placed(tank: Tank) -> void:
	for bot: BotController in _bots:
		if is_instance_valid(bot) and bot.tank == tank:
			_forget(bot)
			_urgent[bot] = true
			_depart[bot] = _rng.randf_range(0.0, DEPART_INTERVAL_S)
			return


func _physics_process(delta: float) -> void:
	if not mode.has_started() or mode.is_in_break() or mode.is_over():
		return
	for i: int in range(_bots.size() - 1, -1, -1):
		if not is_instance_valid(_bots[i]) or not is_instance_valid(_bots[i].tank):
			_bots.remove_at(i)
	var next: int = mode.get_next_checkpoint()
	var focus: Vector3 = mode.get_checkpoint_point(next)
	_update_situation(delta, next)
	for bot: BotController in _bots:
		if bot.tank.is_knocked_out():
			continue
		bot.fight_focus = focus
		if _depart.has(bot):
			_depart[bot] = float(_depart[bot]) - delta
			if float(_depart[bot]) > 0.0:
				continue
			_depart.erase(bot)
		if bot.is_relocating():
			continue   # pulling back after hits: its own order first
		var role: ThunderRoadMode.Role = mode.role_of(bot.tank.team)
		if _update_outside(bot, role, delta):
			continue
		if role == ThunderRoadMode.Role.ATTACK:
			_update_attacker(bot, next, delta)
		else:
			_update_defender(bot, delta)


## Outside its corridor a while: back to the nearest place well inside. True if it did.
func _update_outside(bot: BotController, role: ThunderRoadMode.Role, delta: float) -> bool:
	_back_in[bot] = float(_back_in.get(bot, OUTSIDE_REORDER_S)) + delta
	if mode.outside_time(bot.tank) < OUTSIDE_ORDER_S or float(_back_in[bot]) < OUTSIDE_REORDER_S:
		return false
	_back_in[bot] = 0.0
	var at: Vector2 = mode.project(bot.tank.global_position)
	var s: float = at.x
	if role == ThunderRoadMode.Role.DEFEND:
		s = maxf(s, mode.get_front_s() + 50.0)   # back in well ahead of the line
	var goal: Vector3 = mode.point_at(s, _side_of(bot.tank.global_position, at.x)
			* minf(at.y, mode.half_width(role) * 0.5))
	bot.order_path(goal, _travel_throttle(bot), true)
	_forget_post(bot)
	return true


func _forget_post(bot: BotController) -> void:
	_ordered_cp.erase(bot)
	_ordered_front.erase(bot)
	_ordered_out.erase(bot)
	_countering.erase(bot)


# --- Situation and roles -----------------------------------------------------------

func _tactics_of(bot: BotController) -> TacticsData:
	return bot.bot_data.tactics if bot.bot_data != null and bot.bot_data.tactics != null \
			else TacticalMap.DEFAULT_TACTICS


## Each team reads the fight round the next checkpoint (TeamSituation); scouts become
## harassers while the fight is on, and get new orders when they change.
func _update_situation(delta: float, next: int) -> void:
	var t: TacticsData = TacticalMap.DEFAULT_TACTICS
	for bot: BotController in _bots:
		t = _tactics_of(bot)
		break
	_kos.update(get_tree(), delta, t.momentum_window_s)
	_situation_wait -= delta
	if _situation_wait > 0.0 or next >= mode.get_checkpoint_count():
		return
	_situation_wait = t.situation_interval_s
	var centre: Vector3 = mode.get_checkpoint_point(next)
	var short: bool = mode.get_time_left() < t.pressure_time_s
	for team: int in [0, 1]:
		var attacking: bool = mode.role_of(team) == ThunderRoadMode.Role.ATTACK
		_situation[team] = TeamSituation.assess(team, _bots, get_tree(),
				func(p: Vector3) -> bool: return mode.is_in_checkpoint(p, next), centre,
				mode.data.capture_half_length_m, _kos.entries, _kos.clock,
				attacking and short, false, attacking and short, t)
	TeamSituation.ensure_spearhead(_bots, _kos, _entering, t)
	for bot: BotController in TeamSituation.apply_contact_roles(_bots, _situation):
		_forget_post(bot)
		_repost[bot] = 0.0
	_update_assault(next, short, t)


## Left (-1) or right (1) of the road for this bot, fixed per bot so a team's wide roles
## end up on both sides.
func _side(bot: BotController) -> float:
	return 1.0 if bot.get_instance_id() % 2 == 0 else -1.0


## The nearest living brawler of `bot`'s team (followers keep behind it), or null.
func _lead_of(bot: BotController) -> BotController:
	if bot.get_role().enters != BotRoleData.Enter.WITH_LEAD \
			and bot.get_role().post != BotRoleData.Post.BEHIND_LEAD:
		return null
	var best: BotController = null
	var best_d: float = INF
	for other: BotController in _bots:
		if other == bot or not is_instance_valid(other.tank) or other.tank.team != bot.tank.team \
				or other.tank.is_knocked_out() or other.get_role().enters != BotRoleData.Enter.ALWAYS:
			continue
		var d: float = other.tank.global_position.distance_to(bot.tank.global_position)
		if d < best_d:
			best = other
			best_d = d
	return best


## Attackers: by job (_job_of). Scouts, harassers and outside roles: their own spot
## short of the checkpoint (wide ones on their flank) or off the enemy's flank;
## snipers: a firing spot on the known defenders; the reserve: well back; developing:
## up to their lane on the line in bounds; in the assault: into the checkpoint
## (breakers behind a brawler). New orders when the job or the checkpoint changes.
func _update_attacker(bot: BotController, next: int, delta: float) -> void:
	if next >= mode.get_checkpoint_count():
		return
	var job: Job = _job_of(bot)
	var stamp_same: bool = int(_ordered_cp.get(bot, -1)) == next and int(_ordered_out.get(bot, -1)) == job
	if not stamp_same:
		_ordered_cp[bot] = next
		_ordered_out[bot] = job
		_hold[bot] = 0.0
		_bound.erase(bot)
		_sniper_aim.erase(bot)
	match job:
		Job.DEVELOP:
			_develop_step(bot, next, delta, not stamp_same)
		Job.SNIPER:
			_sniper_step(bot, next, delta)
		Job.RESERVE:
			if not stamp_same:
				_order_reserve(bot, next)
		Job.OUTSIDE:
			_hold[bot] = float(_hold.get(bot, 0.0)) - delta
			if not stamp_same or (not bot.has_orders_left() and float(_hold[bot]) <= 0.0):
				_order_outside(bot, next)
		Job.ASSAULT:
			if _screeners.has(bot):
				_try_assault_screen(bot, next)
			var lead: BotController = _lead_of(bot)
			if stamp_same and bot.has_orders_left():
				return
			if stamp_same:
				if lead != null:
					_hold[bot] = float(_hold.get(bot, 0.0)) - delta
					if float(_hold[bot]) > 0.0:
						return
				elif mode.is_in_checkpoint(bot.tank.global_position, next):
					return
			_order_assault(bot, next, lead)


## What `bot` does now: scouts and harassers (and roles that never go in) work outside,
## snipers snipe, the reserve stays back (not when time is short), the rest develop
## or, in the assault, go in.
func _job_of(bot: BotController) -> Job:
	var role: BotRoleData = bot.get_role()
	if role.enters == BotRoleData.Enter.NEVER:
		return Job.OUTSIDE
	if role.kind == BotRoleData.Kind.SNIPER:
		return Job.SNIPER
	if _reserve.has(bot):
		return Job.RESERVE
	return Job.ASSAULT if _assault.has(bot.tank.team) else Job.DEVELOP


## The attack's phase, its reserve and its developing lanes (every situation update).
func _update_assault(next: int, short: bool, t: TacticsData) -> void:
	var team: int = mode.get_attack_team()
	if next >= mode.get_checkpoint_count():
		return
	if next != _phase_cp:
		# A new checkpoint (or round): develop against it first.
		_phase_cp = next
		_assault.clear()
		_developing_since = _kos.clock
	var cp_s: float = mode.get_checkpoint_s(next)
	var near_from: float = cp_s - mode.data.capture_half_length_m - t.near_zone_m
	var sit: TeamSituation = _situation.get(team)
	var near: int = 0
	for tank: Tank in _team_tanks(team):
		if not tank.is_knocked_out() and mode.project(tank.global_position).x >= near_from:
			near += 1
	var defenders: int = sit.enemies_near if sit != null else 0
	var momentum: bool = sit != null and sit.kills - sit.losses >= t.momentum_advantage
	var upper: bool = near >= defenders + ASSAULT_MARGIN \
			and _kos.clock - _developing_since >= DEVELOP_MIN_S
	var must: bool = short or mode.is_overtime()
	if _assault.has(team):
		var held: bool = _kos.clock - float(_assault[team]) < ASSAULT_HOLD_S
		if not must and not held and not momentum and near < defenders + 1:
			_assault.erase(team)   # lost the upper hand: back to developing
			_developing_since = _kos.clock
	elif must or upper or momentum:
		_assault[team] = _kos.clock
		_pick_screeners(team, next, defenders)
	if not _assault.has(team):
		_screeners.clear()
	_choose_reserve(team, next, short)
	_assign_lanes(team)


## The reserve: RESERVE_SHARE of the attackers that would develop (at least one from
## three tanks), those furthest back; it keeps its members while they live. None when
## time is short: everything goes.
func _choose_reserve(team: int, next: int, short: bool) -> void:
	for bot: BotController in _reserve.keys():
		if not is_instance_valid(bot) or not is_instance_valid(bot.tank) or bot.tank.is_knocked_out() \
				or bot.tank.team != team:
			_reserve.erase(bot)
	if short or mode.is_overtime():
		_reserve.clear()
		return
	var candidates: Array[BotController] = []
	var all: int = 0
	for bot: BotController in _bots:
		if not is_instance_valid(bot.tank) or bot.tank.team != team or bot.tank.is_knocked_out():
			continue
		all += 1
		var role: BotRoleData = bot.get_role()
		if role.enters != BotRoleData.Enter.NEVER and role.kind != BotRoleData.Kind.SNIPER \
				and not _reserve.has(bot):
			candidates.append(bot)
	var want: int = maxi(floori(all * RESERVE_SHARE), 1) if all >= 3 else 0
	if _reserve.size() >= want or candidates.is_empty():
		return
	candidates.sort_custom(func(a: BotController, b: BotController) -> bool:
		return mode.project(a.tank.global_position).x < mode.project(b.tank.global_position).x)
	for i: int in mini(want - _reserve.size(), candidates.size()):
		_reserve[candidates[i]] = true


## Developing attackers get lanes across the corridor (left to right by where they
## are) and a partner each: neighbours in lane order, two by two.
func _assign_lanes(team: int) -> void:
	var group: Array[BotController] = []
	for bot: BotController in _bots:
		if is_instance_valid(bot.tank) and bot.tank.team == team and not bot.tank.is_knocked_out() \
				and _job_of(bot) == Job.DEVELOP:
			group.append(bot)
	group.sort_custom(func(a: BotController, b: BotController) -> bool:
		return _signed_across(a.tank.global_position) < _signed_across(b.tank.global_position))
	var n: int = group.size()
	for i: int in n:
		var bot: BotController = group[i]
		var lane: float = 0.0 if n == 1 else lerpf(-DEVELOP_LANES_SHARE, DEVELOP_LANES_SHARE, float(i) / (n - 1))
		# Lanes keep their bots unless they shift a lot (no new line spot per update).
		if not _lane.has(bot) or absf(float(_lane[bot]) - lane) > 0.3:
			_lane[bot] = lane
			_line_goal.erase(bot)
		var partner: BotController = null
		if i % 2 == 0 and i + 1 < n:
			partner = group[i + 1]
		elif i % 2 == 1:
			partner = group[i - 1]
		_lane_partner[bot] = partner


## Distance from the road, right positive.
func _signed_across(p: Vector3) -> float:
	var at: Vector2 = mode.project(p)
	return _side_of(p, minf(at.x, mode.get_length())) * at.y


## Developing: bound up to the own spot on the line, then hold and fight there.
func _develop_step(bot: BotController, next: int, delta: float, fresh: bool) -> void:
	var cp: Vector3 = mode.get_checkpoint_point(next)
	if fresh or not _line_goal.has(bot):
		var s: float = mode.get_checkpoint_s(next) - mode.data.capture_half_length_m - DEVELOP_STANDOFF_M \
				+ _rng.randf_range(-DEVELOP_SPREAD_M, DEVELOP_SPREAD_M)
		var here_s: float = mode.project(bot.tank.global_position).x
		var half_w: float = mode.half_width(ThunderRoadMode.Role.ATTACK)
		var center: Vector3 = mode.point_at(maxf(s, 0.0), float(_lane.get(bot, 0.0)) * half_w)
		if here_s > s + DEVELOP_SPREAD_M:
			center = bot.tank.global_position   # already past the line: hold near here
		_line_goal[bot] = _spot(bot, center, POST_RADIUS_M * 0.6, mode.tangent_at(s), cp, Vector3.ZERO)
		var partner: Variant = _lane_partner.get(bot)
		# Of a pair the one with the lower id leads off; the other watches first.
		var leads: bool = partner == null or not is_instance_valid(partner) \
				or bot.get_instance_id() < (partner as BotController).get_instance_id()
		_bound[bot] = Bound.WATCH
		_bound_time[bot] = INF if leads else 0.0
	var t: TacticsData = _tactics_of(bot)
	_bound_time[bot] = float(_bound_time.get(bot, 0.0)) + delta
	match int(_bound[bot]):
		Bound.MOVE:
			if not bot.has_orders_left():
				var arrived: bool = Squad._flat(bot.tank.global_position - (_line_goal[bot] as Vector3)).length() \
						< DEVELOP_ARRIVED_M
				_bound[bot] = Bound.HOLD if arrived else Bound.WATCH
				_bound_time[bot] = 0.0
		Bound.WATCH:
			var partner: Variant = _lane_partner.get(bot)
			var alone: bool = partner == null or not is_instance_valid(partner) \
					or not _bound.has(partner) or int(_bound[partner]) == Bound.HOLD
			var partner_still: bool = alone or int(_bound[partner]) != Bound.MOVE
			var waited: float = float(_bound_time[bot])
			var my_turn: bool = alone or waited >= float(_bound_time.get(partner, 0.0))
			if (partner_still and my_turn and waited >= t.solo_halt_s) or waited >= t.overwatch_max_s:
				_start_leg(bot, cp, t)


## One bound: a leg of bound_length_m towards the line spot (to a covered spot that
## gets closer), or the spot itself when that is nearer.
func _start_leg(bot: BotController, cp: Vector3, t: TacticsData) -> void:
	var goal: Vector3 = _line_goal[bot]
	var p: Vector3 = bot.tank.global_position
	var to := Vector3(goal.x - p.x, 0.0, goal.z - p.z)
	if to.length() > t.bound_length_m:
		var leg: Vector3 = p + to.normalized() * t.bound_length_m * 0.8
		goal = _spot(bot, leg, t.bound_length_m * 0.35, to.normalized(), cp, _line_goal[bot])
	_bound[bot] = Bound.MOVE
	_bound_time[bot] = 0.0
	var sit: TeamSituation = _situation.get(bot.tank.team)
	if sit != null and sit.enemies_near > 0 and sit.enemy_centre != Vector3.INF \
			and Squad._flat(sit.enemy_centre - bot.tank.global_position).length() < BOUND_SCREEN_RANGE_M \
			and _rng.randf() < BOUND_SCREEN_CHANCE:
		_screen(bot, sit.enemy_centre)   # cover the dash across
	bot.order_path(goal, _travel_throttle(bot), true)
	_urgent.erase(bot)


## An assault's screeners: the bots nearest the zone that have smoke to spare.
func _pick_screeners(team: int, next: int, defenders: int) -> void:
	_screeners.clear()
	if _last_assault_screen.has(team) and _kos.clock - float(_last_assault_screen[team]) < ASSAULT_SCREEN_GAP_S:
		return   # the last assault's smoke still hangs there
	var want: int = SCREENERS_MANY if defenders >= SCREENERS_MANY_DEFENDERS else SCREENERS_PER_ASSAULT
	var cp: Vector3 = mode.get_checkpoint_point(next)
	var group: Array[BotController] = []
	for bot: BotController in _bots:
		if is_instance_valid(bot.tank) and bot.tank.team == team and not bot.tank.is_knocked_out() \
				and _job_of(bot) == Job.ASSAULT \
				and bot.tank.get_smoke_left() > BotController.SCREEN_KEEP_SALVOS:
			group.append(bot)
	group.sort_custom(func(a: BotController, b: BotController) -> bool:
		return a.tank.global_position.distance_to(cp) < b.tank.global_position.distance_to(cp))
	for i: int in mini(want, group.size()):
		_screeners[group[i]] = true


## A screener lays its screen once near enough: within SCREEN_RANGE_M of the known
## defenders (or of the zone's near edge, none known), towards them (or the zone).
func _try_assault_screen(bot: BotController, next: int) -> void:
	var sit: TeamSituation = _situation.get(bot.tank.team)
	var known: bool = sit != null and sit.enemy_centre != Vector3.INF
	var at: Vector3 = sit.enemy_centre if known else mode.get_checkpoint_point(next)
	var reach: float = SCREEN_RANGE_M if known else SCREEN_RANGE_M + mode.data.capture_half_length_m
	if Squad._flat(at - bot.tank.global_position).length() > reach:
		return
	if _screen(bot, at, true):
		_screeners.erase(bot)
		_last_assault_screen[bot.tank.team] = _kos.clock


## A tactical screen by `bot` towards `at`, if the tank can spare it and (unless
## `assault`: an assault's screeners go together) the team hasn't laid one lately.
## True if asked for.
func _screen(bot: BotController, at: Vector3, assault: bool = false) -> bool:
	var team: int = bot.tank.team
	if not assault and _last_screen.has(team) and _kos.clock - float(_last_screen[team]) < SCREEN_TEAM_GAP_S:
		return false
	if not bot.request_screen(at):
		return false
	_last_screen[team] = _kos.clock
	return true


## Snipers: a spot SNIPER_RANGE_* (closer in the assault) from the known defenders near
## the checkpoint, off the road towards its side, facing them; a new one after its hold
## time or when they have moved. No known defenders: as far from the checkpoint.
func _sniper_step(bot: BotController, next: int, delta: float) -> void:
	var sit: TeamSituation = _situation.get(bot.tank.team)
	var enemy: Vector3 = sit.enemy_centre if sit != null and sit.enemy_centre != Vector3.INF \
			else mode.get_checkpoint_point(next)
	_hold[bot] = float(_hold.get(bot, 0.0)) - delta
	var moved: bool = not _sniper_aim.has(bot) \
			or (_sniper_aim[bot] as Vector3).distance_to(enemy) > SNIPER_REPLAN_M
	if not moved and (bot.has_orders_left() or float(_hold[bot]) > 0.0):
		return
	_sniper_aim[bot] = enemy
	var role: BotRoleData = bot.get_role()
	_hold[bot] = _rng.randf_range(role.hold_min_s, role.hold_max_s)
	var assault: bool = _assault.has(bot.tank.team)
	var dist: float = _rng.randf_range(SNIPER_ASSAULT_RANGE_MIN_M, SNIPER_ASSAULT_RANGE_MAX_M) if assault \
			else _rng.randf_range(SNIPER_RANGE_MIN_M, SNIPER_RANGE_MAX_M)
	var back: Vector3 = -mode.tangent_at(mode.project(enemy).x)
	var off: float = deg_to_rad(_rng.randf_range(SNIPER_OFF_ROAD_MIN_DEG, SNIPER_OFF_ROAD_MAX_DEG)) * _side(bot)
	var ideal: Vector3 = enemy + back.rotated(Vector3.UP, off) * dist
	var facing := Vector3(enemy.x - ideal.x, 0.0, enemy.z - ideal.z).normalized()
	bot.order_path(_spot(bot, ideal, POST_RADIUS_M, facing, enemy, Vector3.ZERO),
			_travel_throttle(bot), true)
	_urgent.erase(bot)


## The reserve: a covered spot on the road RESERVE_BACK_M short of the zone, watching it.
func _order_reserve(bot: BotController, next: int) -> void:
	var s: float = mode.get_checkpoint_s(next) - mode.data.capture_half_length_m - RESERVE_BACK_M
	var cp: Vector3 = mode.get_checkpoint_point(next)
	var center: Vector3 = mode.point_at(maxf(s, 0.0), _rng.randf_range(-NARROW_ACROSS, NARROW_ACROSS)
			* mode.half_width(ThunderRoadMode.Role.ATTACK) * 0.5)
	bot.order_path(_spot(bot, center, POST_RADIUS_M, mode.tangent_at(s), cp, Vector3.ZERO),
			_travel_throttle(bot), true)
	_urgent.erase(bot)


## Scouts, harassers (and roles that never go in): off the enemy's flank in contact,
## else their own spot short of the checkpoint, wide on their flank for the wide roles.
func _order_outside(bot: BotController, next: int) -> void:
	var role: BotRoleData = bot.get_role()
	_hold[bot] = _rng.randf_range(role.hold_min_s, role.hold_max_s)
	var s: float = mode.get_checkpoint_s(next)
	var cp: Vector3 = mode.get_checkpoint_point(next)
	var forward: Vector3 = mode.tangent_at(s)
	var sit: TeamSituation = _situation.get(bot.tank.team)
	var goal: Vector3
	if role.hit_and_run and sit != null and sit.enemy_centre != Vector3.INF:
		goal = _harass_spot(bot, sit.enemy_centre, ThunderRoadMode.Role.ATTACK)
	else:
		var half_w: float = mode.half_width(ThunderRoadMode.Role.ATTACK)
		var back: float = _rng.randf_range(role.standoff_min_m, maxf(role.standoff_max_m, role.standoff_min_m))
		var hold_s: float = s - mode.data.capture_half_length_m - back
		var wide: bool = role.axis_spread_deg >= WIDE_SPREAD_DEG
		var across: float = (_side(bot) * _rng.randf_range(WIDE_ACROSS_MIN, WIDE_ACROSS_MAX) if wide
				else _rng.randf_range(-NARROW_ACROSS, NARROW_ACROSS)) * half_w
		goal = _spot(bot, mode.point_at(hold_s, across), POST_RADIUS_M, forward, cp, cp)
	bot.order_path(goal, _travel_throttle(bot), _urgent.has(bot))
	_urgent.erase(bot)


## The assault: into the checkpoint (somewhere across its long zone, well inside it),
## breakers behind their brawler.
func _order_assault(bot: BotController, next: int, lead: BotController) -> void:
	var role: BotRoleData = bot.get_role()
	_hold[bot] = _rng.randf_range(role.hold_min_s, role.hold_max_s)
	var s: float = mode.get_checkpoint_s(next)
	var cp: Vector3 = mode.get_checkpoint_point(next)
	var forward: Vector3 = mode.tangent_at(s)
	var goal: Vector3
	if lead != null:
		goal = _spot(bot, lead.tank.global_position - forward * role.follow_m, POST_RADIUS_M * 0.6,
				forward, cp, cp)
	else:
		var across: float = randf_range(-1.0, 1.0) * mode.data.capture_half_width_m * AT_CHECKPOINT_SHARE * 0.6
		goal = _spot(bot, cp + forward.cross(Vector3.UP) * across, mode.data.capture_half_length_m * 0.6,
				forward, mode.point_at(s + LOOK_BACK_M), cp)
	bot.order_path(goal, _travel_throttle(bot), true)
	_urgent.erase(bot)


## A harasser comes up off the flank of the known enemies, `role`'s corridor permitting,
## at its harass range, facing them.
func _harass_spot(bot: BotController, enemies: Vector3, side_role: ThunderRoadMode.Role) -> Vector3:
	var role: BotRoleData = bot.get_role()
	var at: Vector2 = mode.project(enemies)
	var right: Vector3 = mode.tangent_at(at.x).cross(Vector3.UP)
	var ideal: Vector3 = enemies + right * _side(bot) * role.pick_harass_range(_rng)
	var p: Vector2 = mode.project(ideal)
	var half_w: float = mode.half_width(side_role) * WIDE_ACROSS_MAX
	if absf(p.y) > half_w:
		ideal = mode.point_at(p.x, signf(p.y) * half_w)
	var threat := Vector3(enemies.x - ideal.x, 0.0, enemies.z - ideal.z).normalized()
	return _spot(bot, ideal, POST_RADIUS_M, threat, enemies, Vector3.ZERO)


## Defenders: a post ahead of the front, new when the front moves or after a while;
## standing there, the squad goes to mine the road towards the attackers.
func _update_defender(bot: BotController, delta: float) -> void:
	var front: float = mode.get_front_s()
	var role: BotRoleData = bot.get_role()
	var sit: TeamSituation = _situation.get(bot.tank.team)
	if role.post == BotRoleData.Post.FLANK_RESERVE and _update_counter(bot, sit):
		return
	var pushed: bool = sit != null and sit.pushed_back
	var moved: bool = float(_ordered_front.get(bot, -1.0)) != front \
			or (role.post == BotRoleData.Post.BEHIND_ZONE and bool(_ordered_pushed.get(bot, false)) != pushed)
	_repost[bot] = float(_repost.get(bot, 0.0)) - delta
	if moved or (float(_repost[bot]) <= 0.0 and not bot.has_orders_left()):
		if moved:
			_mine_step(bot, front)   # the squad sets off before the tank drives away
		_give_post(bot, front)
		return
	# Standing = hardly moving (a bot halted to fight still has orders left).
	if bot.has_orders_left() and bot.tank.linear_velocity.length() > MINE_STILL_MPS:
		_standing[bot] = 0.0
		return
	_standing[bot] = float(_standing.get(bot, 0.0)) + delta
	# Scouts' squads mine first: sooner and more often.
	var eager: float = MINES_FIRST_SHARE if role.mines_first else 1.0
	if float(_standing[bot]) < MINE_AFTER_S * eager:
		return
	_mine_think[bot] = float(_mine_think.get(bot, 0.0)) - delta
	if float(_mine_think[bot]) <= 0.0:
		_mine_think[bot] = MINE_THINK_S * eager
		_mine_step(bot, front)


## A flank reserve: attackers known in the checkpoint's zone: it drives at them from its
## side (a counterattack into their flank); they're out of it: back to a post. True
## while it counterattacks.
func _update_counter(bot: BotController, sit: TeamSituation) -> bool:
	var attack: bool = sit != null and sit.enemies_in > 0 and sit.enemy_centre != Vector3.INF
	if not attack:
		if _countering.has(bot):
			_countering.erase(bot)
			_repost[bot] = 0.0
		return false
	var at: Vector3 = sit.enemy_centre
	if _countering.has(bot) and (_countering[bot] as Vector3).distance_to(at) < COUNTER_REPLAN_M \
			and bot.has_orders_left():
		return true
	_countering[bot] = at
	var s: float = mode.project(at).x
	var right: Vector3 = mode.tangent_at(s).cross(Vector3.UP)
	var from_side: Vector3 = at + right * _side(bot) * COUNTER_OFFSET_M
	var threat := Vector3(at.x - from_side.x, 0.0, at.z - from_side.z).normalized()
	bot.order_path(_spot(bot, from_side, POST_RADIUS_M * 0.6, threat, at, Vector3.ZERO),
			_travel_throttle(bot), true)
	return true


## Defenders mine all they can: a carried mine goes out (unless all are out and the
## front hasn't moved since the last one); with none left the squad comes back to the
## tank to refill (SquadData.mine_refill_s), then goes again.
func _mine_step(bot: BotController, front: float) -> void:
	var squad: Squad = bot.tank.squad
	if squad == null or not is_instance_valid(squad) or squad.data.mine == null \
			or squad.get_state() == Squad.State.WIPED or squad.get_state() == Squad.State.RETURNING \
			or squad.is_mine_job():
		return
	var all_out: bool = squad.get_mines_out() >= squad.data.max_mines_out
	if squad.get_mines_carried() > 0:
		if all_out and float(_mine_front.get(bot, -1.0)) == front:
			return
		if _send_mine(bot):
			_mine_front[bot] = front
	elif squad.is_out() and not all_out:
		bot.order_squad(Squad.ORDER_RECALL, Vector3.ZERO)


func _give_post(bot: BotController, front: float) -> void:
	_ordered_front[bot] = front
	_repost[bot] = _rng.randf_range(mode.data.defender_repost_min_s, mode.data.defender_repost_max_s)
	_standing.erase(bot)
	var next: int = mode.get_next_checkpoint()
	var cp_s: float = mode.get_checkpoint_s(next)
	var half: float = mode.data.capture_half_length_m
	# A defence starts between the enemy and the objective: mostly ahead of the zone,
	# some in it, the rest watching it from just behind.
	var lo: float = cp_s - half
	var hi: float = cp_s + half
	var ahead_lo: float = maxf(front + POST_FRONT_CLEAR_M, cp_s - half - POST_AHEAD_M)
	var ahead_hi: float = cp_s - half - 10.0
	var bot_role: BotRoleData = bot.get_role()
	var sit: TeamSituation = _situation.get(bot.tank.team)
	var pushed: bool = sit != null and sit.pushed_back
	_ordered_pushed[bot] = pushed
	var role := ThunderRoadMode.Role.DEFEND
	# Where across the corridor: wide roles out on their flank, the rest near the road.
	var across_lo: float = -POST_ACROSS_SHARE
	var across_hi: float = POST_ACROSS_SHARE
	match bot_role.post:
		BotRoleData.Post.FORWARD:
			if ahead_hi > ahead_lo + 20.0:
				lo = ahead_lo
				hi = ahead_hi
			across_lo = WIDE_ACROSS_MIN
			across_hi = WIDE_ACROSS_MAX
		BotRoleData.Post.ZONE_FRONT:
			hi = cp_s
			across_lo = -NARROW_ACROSS
			across_hi = NARROW_ACROSS
			if _zone_front_index(bot) % CROSSFIRE_SHARE_EVERY == 0:
				# Crossfire: out on its flank beside the zone, not in front of it.
				across_lo = WIDE_ACROSS_MIN
				across_hi = WIDE_ACROSS_MAX
		BotRoleData.Post.BEHIND_ZONE:
			if pushed:   # they fell back: from the zone's front, pushing them further
				hi = cp_s
			else:
				lo = cp_s + half
				hi = cp_s + half + POST_BEHIND_M
		BotRoleData.Post.FLANK_RESERVE:
			lo = cp_s
			hi = cp_s + half + RESERVE_BEHIND_M
			across_lo = WIDE_ACROSS_MIN
			across_hi = WIDE_ACROSS_MAX
		BotRoleData.Post.BEHIND_LEAD:
			var lead: BotController = _lead_of(bot)
			if lead != null and _post_s.has(lead):
				lo = float(_post_s[lead]) + LEAD_GAP_MIN_M
				hi = float(_post_s[lead]) + bot_role.follow_m
				# Behind the lead on its side of the road (a flank lead keeps its breaker).
				var lead_across: float = float(_post_across.get(lead, 0.0))
				across_lo = lead_across - NARROW_ACROSS * 0.5
				across_hi = lead_across + NARROW_ACROSS * 0.5
	if bot_role.hit_and_run and sit != null and sit.enemy_centre != Vector3.INF:
		# A harasser in contact: off the attackers' flank.
		_post_s[bot] = mode.project(sit.enemy_centre).x
		bot.order_path(_harass_spot(bot, sit.enemy_centre, role), _travel_throttle(bot), true)
		_urgent.erase(bot)
		return
	var wide: bool = across_lo > 0.0 and bot_role.post != BotRoleData.Post.BEHIND_LEAD
	var centred: bool = across_lo < 0.0 and across_hi > 0.0   # astride the road
	hi = minf(hi, mode.get_length() - 20.0)
	lo = minf(lo, hi)
	var goal := Vector3.INF
	var post_s: float = lo
	for attempt: int in 4:
		post_s = _rng.randf_range(lo, maxf(hi, lo))
		var share: float = _rng.randf_range(across_lo, across_hi)
		if centred:
			# Off the road's middle, either side.
			share = signf(share if share != 0.0 else 1.0) * lerpf(POST_CENTRE_GAP, across_hi, absf(share) / across_hi)
		if wide:
			share *= _side(bot)
		_post_across[bot] = share
		var across: float = share * mode.half_width(role)
		var center: Vector3 = mode.point_at(post_s, across)
		var back: Vector3 = -mode.tangent_at(post_s)
		var spot: Vector3 = _spot(bot, center, POST_RADIUS_M, back,
				mode.point_at(post_s - LOOK_BACK_M), Vector3.ZERO)
		if mode.is_inside(spot, role):
			goal = spot
			break
	if goal == Vector3.INF:
		goal = mode.point_at(post_s)
	_post_s[bot] = post_s
	# Always urgent: scouting stops are for the side going forward, not for posts.
	bot.order_path(goal, _travel_throttle(bot), true)
	_urgent.erase(bot)


## `bot`'s place among its team's living ZONE_FRONT defenders (every other one posts
## out for crossfire).
func _zone_front_index(bot: BotController) -> int:
	var i: int = 0
	for other: BotController in _bots:
		if other == bot:
			return i
		if is_instance_valid(other.tank) and other.tank.team == bot.tank.team \
				and other.get_role().post == BotRoleData.Post.ZONE_FRONT:
			i += 1
	return i


## The squad (on the tank or out) lays its mine on the road where the attackers must
## come: mostly between the next checkpoint's zone and the front, else in the zone,
## within MINE_WALK_MAX_M along the road from the tank (as near the attackers as that
## allows). False if it can't now.
func _send_mine(bot: BotController) -> bool:
	var squad: Squad = bot.tank.squad
	if squad == null or not is_instance_valid(squad) or squad.get_mines_carried() <= 0 \
			or squad.get_state() == Squad.State.WIPED or squad.get_state() == Squad.State.RETURNING:
		return false
	var front: float = mode.get_front_s()
	var cp_s: float = mode.get_checkpoint_s(mode.get_next_checkpoint())
	var half: float = mode.data.capture_half_length_m
	var here: Vector3 = bot.tank.global_position
	var tank_s: float = mode.project(here).x
	# The stretch the squad can reach, and of it the parts before the zone and in it.
	var lo: float = maxf(front + 25.0, tank_s - MINE_WALK_MAX_M)
	var hi: float = minf(cp_s + half, tank_s + MINE_WALK_MAX_M * 0.5)
	if hi <= lo:
		return false
	var before_hi: float = minf(cp_s - half, hi)
	var s: float
	if before_hi > lo + 10.0 and _rng.randf() < MINE_BEFORE_ZONE_SHARE:
		s = _rng.randf_range(lo, before_hi)
	else:
		s = _rng.randf_range(maxf(lo, cp_s - half), hi) if hi > maxf(lo, cp_s - half) \
				else _rng.randf_range(lo, hi)
	var target: Vector3 = mode.point_at(s, _rng.randf_range(-MINE_ACROSS_M, MINE_ACROSS_M))
	if Squad._flat(target - here).length() > squad.data.max_distance_from_tank_m - 30.0:
		return false
	bot.order_squad(Squad.ORDER_MINE, target)
	return true


## A good spot (TacticalMap.find_position) round `center`, facing `threat`.
func _spot(bot: BotController, center: Vector3, radius: float, threat: Vector3,
		look_at: Vector3, progress_to: Vector3) -> Vector3:
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	if map == null:
		return center
	var friends := PackedVector3Array()
	var exclude: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		exclude.append(tank.get_rid())
		if tank != bot.tank and tank.team == bot.tank.team and not tank.is_knocked_out():
			friends.append(tank.global_position)
	var tactics: TacticsData = bot.bot_data.tactics if bot.bot_data != null and bot.bot_data.tactics != null \
			else TacticalMap.DEFAULT_TACTICS
	return map.find_position(mode.get_world_3d(), center, radius, threat, look_at, LOOK_SPREAD_M,
			bot.tank.global_position, friends, tactics, _rng, exclude,
			progress_to if progress_to != Vector3.ZERO else center, 0.0)


func _travel_throttle(bot: BotController) -> float:
	var tactics: TacticsData = bot.bot_data.tactics if bot.bot_data != null and bot.bot_data.tactics != null \
			else TacticalMap.DEFAULT_TACTICS
	return tactics.travel_throttle


## `goal` moved into `bot`'s corridor, INSIDE_MARGIN_M from its edges (across, and for
## defenders from the line behind the front), so a bot never stands where its guns
## are silent. BotController.keep_goal: every goal it drives to.
func _keep_inside(goal: Vector3, bot: BotController) -> Vector3:
	if not is_instance_valid(bot) or not is_instance_valid(bot.tank) or goal == Vector3.INF:
		return goal
	var role: ThunderRoadMode.Role = mode.role_of(bot.tank.team)
	var at: Vector2 = mode.project(goal)
	var s: float = at.x
	if role == ThunderRoadMode.Role.DEFEND:
		s = maxf(s, mode.get_defender_line_s() + INSIDE_MARGIN_M)
	var w: float = maxf(mode.half_width(role) - INSIDE_MARGIN_M, 0.0)
	if s == at.x and at.y <= w:
		return goal
	var across: float = _side_of(goal, minf(at.x, mode.get_length())) * minf(at.y, w)
	return mode.slot_point(s, across)   # past the road's end the corridor goes on straight


## Which side of the road `p` is on (1 right, -1 left), at `s` metres along.
func _side_of(p: Vector3, s: float) -> float:
	var road: Vector3 = mode.point_at(s)
	var right: Vector3 = mode.tangent_at(s).cross(Vector3.UP)
	return 1.0 if (p - road).dot(right) >= 0.0 else -1.0
