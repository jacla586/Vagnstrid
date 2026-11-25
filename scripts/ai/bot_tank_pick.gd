class_name BotTankPick
extends RefCounted
## Picks a bot's tank from a pool at random, keeping each chassis within its
## ChassisData.bot_max_share of the team (KV-2s: 20 %, so 2 in a team of 10).
## Only bots count and are limited; players drive what they like.


## A random config of `pool` whose chassis still has room among `taken` (the configs of
## the team's other bots) in a team of `team_size` tanks; null for an empty pool, the
## whole pool if every chassis in it is full.
static func pick(pool: Array[TankConfig], taken: Array[TankConfig], team_size: int,
		rng: RandomNumberGenerator = null) -> TankConfig:
	if pool.is_empty():
		return null
	var counts: Dictionary = {}
	for c: TankConfig in taken:
		if c != null:
			counts[c.chassis] = int(counts.get(c.chassis, 0)) + 1
	var open: Array[TankConfig] = []
	for c: TankConfig in pool:
		if int(counts.get(c.chassis, 0)) < allowed(c.chassis, team_size):
			open.append(c)
	if open.is_empty():
		open = pool
	return open[rng.randi() % open.size() if rng != null else randi() % open.size()]


## How many bots of a team of `team_size` may drive `chassis`.
static func allowed(chassis: StringName, team_size: int) -> int:
	var data: ChassisData = TankBuilder.catalogue().find_chassis(chassis)
	if data == null or data.bot_max_share >= 1.0:
		return 1 << 30
	return maxi(1, roundi(maxi(team_size, 1) * data.bot_max_share))


## The configs of the bots (not players' tanks) on `team` now in the tree.
static func team_bot_configs(tree: SceneTree, team: int) -> Array[TankConfig]:
	var human: Dictionary = {}
	for n: Node in tree.get_nodes_in_group(Relevance.GROUP):
		var t: Variant = n.get("tank")
		if t is Tank:
			human[t] = true
	var out: Array[TankConfig] = []
	for n: Node in tree.get_nodes_in_group("tanks"):
		var tank := n as Tank
		if tank != null and tank.team == team and not human.has(tank) and not tank.use_player_config \
				and not tank.wreck_only and not tank.is_queued_for_deletion():
			out.append(tank.config)
	return out


## Tanks in the tree on `team` (players too), for the team size.
static func team_count(tree: SceneTree, team: int) -> int:
	var n: int = 0
	for node: Node in tree.get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank != null and tank.team == team and not tank.wreck_only and not tank.is_queued_for_deletion():
			n += 1
	return n
