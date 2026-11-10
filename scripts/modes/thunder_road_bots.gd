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
	MatchSettings.load_settings()
	var size: int = MatchSettings.team_size
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


## Host: a player joins `team`. If the team is full a bot leaves to make room (a
## knocked-out one if any). Returns its tank, out of the bot lists and without its
## controller; the caller (NetGame) removes it from the game.
func make_room(team: int) -> Tank:
	MatchSettings.load_settings()
	var size: int = MatchSettings.team_size
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
			_depart, _urgent, _back_in]:
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
			_update_attacker(bot, next)
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


## Attackers: to a spot inside the next checkpoint's radius, again when it changes or
## when the bot finds itself away from it with nothing left to drive.
func _update_attacker(bot: BotController, next: int) -> void:
	if next >= mode.get_checkpoint_count():
		return
	var cp: Vector3 = mode.get_checkpoint_point(next)
	var near: bool = mode.is_in_checkpoint(bot.tank.global_position, next)
	if int(_ordered_cp.get(bot, -1)) == next and (bot.has_orders_left() or near):
		return
	_ordered_cp[bot] = next
	var s: float = mode.get_checkpoint_s(next)
	var forward: Vector3 = mode.tangent_at(s)
	# Somewhere across the long zone (attackers spread out), well inside it.
	var across: float = randf_range(-1.0, 1.0) * mode.data.capture_half_width_m * AT_CHECKPOINT_SHARE \
			* 0.6
	var goal: Vector3 = _spot(bot, cp + forward.cross(Vector3.UP) * across,
			mode.data.capture_half_length_m * 0.6, forward,
			mode.point_at(s + LOOK_BACK_M), cp)
	bot.order_path(goal, _travel_throttle(bot), _urgent.has(bot))
	_urgent.erase(bot)


## Defenders: a post ahead of the front, new when the front moves or after a while;
## standing there, the squad goes to mine the road towards the attackers.
func _update_defender(bot: BotController, delta: float) -> void:
	var front: float = mode.get_front_s()
	var moved: bool = float(_ordered_front.get(bot, -1.0)) != front
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
	if float(_standing[bot]) < MINE_AFTER_S:
		return
	_mine_think[bot] = float(_mine_think.get(bot, 0.0)) - delta
	if float(_mine_think[bot]) <= 0.0:
		_mine_think[bot] = MINE_THINK_S
		_mine_step(bot, front)


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
	var roll: float = _rng.randf()
	var ahead_lo: float = maxf(front + POST_FRONT_CLEAR_M, cp_s - half - POST_AHEAD_M)
	var ahead_hi: float = cp_s - half - 10.0
	if roll < mode.data.defender_post_ahead_share and ahead_hi > ahead_lo + 20.0:
		lo = ahead_lo
		hi = ahead_hi
	elif roll >= mode.data.defender_post_ahead_share + mode.data.defender_post_zone_share:
		lo = cp_s + half
		hi = cp_s + half + POST_BEHIND_M
	hi = minf(hi, mode.get_length() - 20.0)
	lo = minf(lo, hi)
	var role := ThunderRoadMode.Role.DEFEND
	var goal := Vector3.INF
	var post_s: float = lo
	for attempt: int in 4:
		post_s = _rng.randf_range(lo, maxf(hi, lo))
		var across: float = _rng.randf_range(-1.0, 1.0) * mode.half_width(role) * POST_ACROSS_SHARE
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


## Which side of the road `p` is on (1 right, -1 left), at `s` metres along.
func _side_of(p: Vector3, s: float) -> float:
	var road: Vector3 = mode.point_at(s)
	var right: Vector3 = mode.tangent_at(s).cross(Vector3.UP)
	return 1.0 if (p - road).dot(right) >= 0.0 else -1.0
