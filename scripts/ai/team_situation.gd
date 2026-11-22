class_name TeamSituation
extends RefCounted
## How one team reads the fight round an objective (the KotH zone, the next ThunderRoad
## checkpoint), from what it may know: its own tanks (exact), enemies its bots have seen
## or had reported (BotController.get_known_enemies), knock-outs both ways lately (the
## kill feed is public) and the score race the HUD shows. Bot directors make one per
## team every TacticsData.situation_interval_s; BotRoleData says who acts on what.

var friends_in: int = 0
var enemies_in: int = 0
var enemies_near: int = 0
var kills: int = 0
var losses: int = 0
## More own tanks in the zone than known enemies, or a run of knock-outs.
var advantage: bool = false
## The zone must be taken: behind with time short, or few known defenders there while
## behind or short of time.
var pressure: bool = false
## No known enemy near the zone and a knock-out lately: they fell back.
var pushed_back: bool = false
## Where the known enemies in and near the objective are on average (INF: none).
var enemy_centre: Vector3 = Vector3.INF


## `team`'s view. `inside`(point) -> bool: in the objective; `near_m`: how far out counts
## as near it (from `centre`, with `radius`); `ko_log`: [[time_s, team, killer team], ...];
## `now_s`; `behind`/`ahead` on score; `time_short`: little time or points left.
static func assess(team: int, bots: Array[BotController], tree: SceneTree, inside: Callable,
		centre: Vector3, radius: float, ko_log: Array, now_s: float, behind: bool, ahead: bool,
		time_short: bool, t: TacticsData) -> TeamSituation:
	var s := TeamSituation.new()
	for node: Node in tree.get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank != null and tank.team == team and not tank.is_knocked_out() and not tank.wreck_only \
				and bool(inside.call(tank.global_position)):
			s.friends_in += 1
	var known: Dictionary = {}
	for bot: BotController in bots:
		if not is_instance_valid(bot) or not is_instance_valid(bot.tank) or bot.tank.team != team:
			continue
		var seen: Dictionary = bot.get_known_enemies(t.situation_memory_s)
		for enemy: Variant in seen:
			if is_instance_valid(enemy) and not (enemy as Tank).is_knocked_out():
				known[enemy] = seen[enemy]
	var sum := Vector3.ZERO
	var n: int = 0
	for enemy: Variant in known:
		var at: Vector3 = known[enemy]
		var d: float = Vector2(at.x - centre.x, at.z - centre.z).length()
		if bool(inside.call(at)):
			s.enemies_in += 1
		if d <= radius + t.near_zone_m:
			s.enemies_near += 1
			sum += at
			n += 1
	if n > 0:
		s.enemy_centre = sum / n
	for entry: Array in ko_log:
		if now_s - float(entry[0]) > t.momentum_window_s:
			continue
		if int(entry[1]) == team:
			s.losses += 1
		elif int(entry[2]) == team:
			s.kills += 1
	s.advantage = s.friends_in >= s.enemies_in + t.advantage_margin \
			or s.kills - s.losses >= t.momentum_advantage
	s.pressure = (behind and time_short) \
			or (s.enemies_in <= t.pressure_few_defenders and (behind or time_short) and not ahead)
	s.pushed_back = s.enemies_near == 0 and s.kills > 0
	return s


func describe() -> String:
	return "in %d v %d, near %d, ko %d/%d%s%s%s" % [friends_in, enemies_in, enemies_near, kills, losses,
			" ADV" if advantage else "", " PRESS" if pressure else "", " PUSHED" if pushed_back else ""]


## Contact roles (BotRoleData.contact_role): bots of a team in contact play it, the rest
## their favourite. Returns the bots whose role changed (they need new orders).
static func apply_contact_roles(bots: Array[BotController], situations: Dictionary) -> Array[BotController]:
	var changed: Array[BotController] = []
	for bot: BotController in bots:
		if not is_instance_valid(bot) or not is_instance_valid(bot.tank):
			continue
		var favourite: BotRoleData = bot.tank.data.bot_role if bot.tank.data != null else null
		if favourite == null or favourite.contact_role == null:
			continue
		var sit: TeamSituation = situations.get(bot.tank.team)
		var want: BotRoleData = favourite.contact_role if sit != null and sit.in_contact() else null
		if bot.role_override != want:
			bot.role_override = want
			changed.append(bot)
	return changed


## Is it `bot`'s moment to go in (outside roles, BotRoleData.Enter.ON_ADVANTAGE): the team
## has the upper hand (or must take the objective, for roles that go in on pressure), or
## it knocked an enemy out lately. Once it goes it keeps at it for enter_hold_s
## (`entering`: bot -> clock it last had the moment).
static func has_moment(bot: BotController, sit: TeamSituation, kos: KnockoutLog,
		entering: Dictionary, t: TacticsData) -> bool:
	var role: BotRoleData = bot.get_role()
	var moment: bool = sit != null and (sit.advantage or (role.enters_on_pressure and sit.pressure))
	if kos.since_kill(bot.tank) < t.own_kill_moment_s:
		moment = true
	if moment:
		entering[bot] = kos.clock
	return entering.has(bot) and kos.clock - float(entering[bot]) < t.enter_hold_s


## Every team keeps a spearhead: at least min_spearhead_share of its living bots go in.
## Short of brawlers and followers, outside roles that may go in (ON_ADVANTAGE) are sent
## as if it were their moment, flankers first, then snipers.
static func ensure_spearhead(bots: Array[BotController], kos: KnockoutLog, entering: Dictionary,
		t: TacticsData) -> void:
	var teams: Dictionary = {}
	for bot: BotController in bots:
		if is_instance_valid(bot) and is_instance_valid(bot.tank) and not bot.tank.is_knocked_out():
			if not teams.has(bot.tank.team):
				teams[bot.tank.team] = []
			(teams[bot.tank.team] as Array).append(bot)
	for team: int in teams:
		var group: Array = teams[team]
		var going: int = 0
		var spare: Array = []
		for bot: BotController in group:
			var enters: BotRoleData.Enter = bot.get_role().enters
			var active: bool = entering.has(bot) and kos.clock - float(entering[bot]) < t.enter_hold_s
			if enters == BotRoleData.Enter.ALWAYS or enters == BotRoleData.Enter.WITH_LEAD or active:
				going += 1
			elif enters == BotRoleData.Enter.ON_ADVANTAGE:
				spare.append(bot)
		spare.sort_custom(func(a: BotController, b: BotController) -> bool:
			var fa: bool = a.get_role().kind == BotRoleData.Kind.FLANKER
			var fb: bool = b.get_role().kind == BotRoleData.Kind.FLANKER
			return fa and not fb if fa != fb else a.get_instance_id() < b.get_instance_id())
		var need: int = ceili(group.size() * t.min_spearhead_share) - going
		for i: int in mini(need, spare.size()):
			entering[spare[i]] = kos.clock


## Does `bot` stay outside the objective now (its role holds outside, no moment)?
static func holds_outside(bot: BotController, sit: TeamSituation, kos: KnockoutLog,
		entering: Dictionary, t: TacticsData) -> bool:
	match bot.get_role().enters:
		BotRoleData.Enter.NEVER:
			return true
		BotRoleData.Enter.ON_ADVANTAGE:
			return not has_moment(bot, sit, kos, entering, t)
	return false


## Known enemies near the objective (the fight is on).
func in_contact() -> bool:
	return enemies_near > 0


## The kill feed as bot directors keep it: every knock-out of a tank in the scene with
## when, the victim's team and the killer's (-1: nobody), where the victim stood and where
## the killer was if the victim's team knew of him (`known_check`(team, killer) -> bool;
## else Vector3.INF), and each killer's last one.
class KnockoutLog:
	var entries: Array = []  # [clock, victim team, killer team, victim position, killer position]
	var known_check: Callable = Callable()
	var last_kill_of: Dictionary = {}  # Tank -> clock
	var clock: float = 0.0
	var _hooked: Dictionary = {}

	## Hooks tanks that came since the last call and ages the log.
	func update(tree: SceneTree, delta: float, keep_s: float) -> void:
		clock += delta
		for node: Node in tree.get_nodes_in_group("tanks"):
			var tank := node as Tank
			if tank == null or _hooked.has(tank.get_instance_id()):
				continue
			_hooked[tank.get_instance_id()] = true
			tank.eliminated.connect(func(killer: Tank, _assists: Array[Tank]) -> void:
				var valid: bool = killer != null and is_instance_valid(killer)
				var by: Vector3 = Vector3.INF
				if valid and known_check.is_valid() and bool(known_check.call(tank.team, killer)):
					by = killer.global_position
				entries.append([clock, tank.team, killer.team if valid else -1, tank.global_position, by])
				if valid:
					last_kill_of[killer] = clock)
		while not entries.is_empty() and clock - float(entries[0][0]) > keep_s:
			entries.pop_front()

	## Seconds since `tank` last knocked an enemy out (INF: never).
	func since_kill(tank: Tank) -> float:
		return clock - float(last_kill_of[tank]) if last_kill_of.has(tank) else INF
