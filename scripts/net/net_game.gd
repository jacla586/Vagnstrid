class_name NetGame
extends Node
## The networked game in a loaded map (added by Net). The map scene is used as it is:
## its PlayerRig gives team 0's start, its first enemy tank team 1's start. Both are
## removed (and the enemies too, unless bots are on: then they stay on the host as
## team 2 and are replicated like any tank; with King of the Hill they fill teams 1
## and 0 alternately instead).
##
## Host: spawns a tank per player (its own in a PlayerRig, remote ones driven by a
## RemoteController), replicates them (NetReplicator), respawns knocked-out players,
## and forwards events: shells and ricochets, hit results to the shooter, spots to the
## shooter's team, felled trees. With King of the Hill in the map, players spawn at
## its zone spawns and its state goes to the clients (twice a second and on changes).
## ThunderRoad likewise: its state goes to the clients, and it alone brings tanks back
## (waves, defender respawns); NetGame starts no respawn timers then.
## Client: puppets for every tank (NetPuppets), its own inside a PlayerRig with turret
## prediction; sends its commands (NetInput).
##
## Joining: nobody gets a tank on arrival. MatchLobby (added here, on every machine)
## shows the mode, the teams and the tanks; the player picks a team (pick_team: the
## roster shows them "choosing a tank") and then a tank (request_deploy): the host spawns
## them at the team's spawn, a bot of that team making room (the director's make_room)
## and the director refilling so the teams stay even. The roster (every tank and
## choosing player) goes to everyone twice a second when it changes.
##
## Team swaps and tank changes (Esc menu): the player's tank goes and a new one comes
## (respawn_player). A switch takes a bot's place on the other team (or a free place);
## with only players there, the player picks one to ask, who accepts or declines in
## their Esc menu. A new tank type is a respawn at the team's spawn, at once (a loss
## unless fresh from a spawn, TankSwitch); a knocked-out tank gets it at its respawn
## (Tank.repaired).

## The Esc menu has something new to show (swap choices or offers).
signal menu_changed
## The roster (who is on which team) changed.
signal roster_changed

const TANK_SCENE: PackedScene = preload("res://scenes/tank/tank.tscn")
## Loaded when needed, not preloaded: the rig's EscMenu refers to NetGame (a cycle).
const RIG_SCENE_PATH: String = "res://scenes/player/player_rig.tscn"
const PLAYER_DATA: String = "res://data/tanks/player_medium.tres"
const RESPAWN_DELAY_S: float = 10.0
const BOT_TEAM: int = 2
## Fallback start for team 1 if the map has no enemy tank: this far from team 0 (m).
const FALLBACK_SPAWN_DISTANCE_M: float = 300.0
## With bots on, team 1 starts this far beside the first bot (which keeps its place).
const BOT_SPAWN_OFFSET_M: float = 15.0
## King of the Hill state to clients this often (s), and at once on zone changes.
const KOTH_SEND_INTERVAL_S: float = 0.5
## Infantry squads to clients this often (unreliable).
const SQUAD_SEND_HZ: float = 10.0
## Pushed wrecks: moved ones go to the clients this often (Wreck.collect_moves).
const WRECK_SEND_HZ: float = 5.0
## A team swap request stays open this long (s).
const SWAP_OFFER_S: float = 60.0
## The roster goes to everyone this often when it changed.
const ROSTER_HZ: float = 2.0

## net_id -> Tank (every replicated tank)
var tanks: Dictionary = {}
## net_id -> owning peer (1 = host, 0 = bot)
var owners: Dictionary = {}
## peer -> team
var teams: Dictionary = {}
## team -> start transform
var spawns: Dictionary = {}

var _next_id: int = 1
## [field path, index, direction] of every felled tree, for late joiners
var _felled: Array = []
## [tank spec, transform, turret yaw, gun pitch] of every wreck, for late joiners
var _wrecks: Array = []
var _respawn_timers: Dictionary = {}
## peer -> TankConfig the player chose in the garage (missing = PLAYER_DATA)
var _configs: Dictionary = {}
var _names: Dictionary = {}  # peer -> player name (scoreboard)
var _replicator: NetReplicator
var _puppets: NetPuppets
var _input: NetInput
var _my_rig: Node
var _map: Node
var _koth_timer: float = 0.0
var _squad_clock := PackedFloat32Array([0.0])
var _wreck_clock := PackedFloat32Array([0.0])
var _koth_hooked: KothMode
var _thunder_timer: float = 0.0
var _thunder_hooked: ThunderRoadMode
var _free_timer: float = 0.0
var _free_hooked: FreeFight
## Host: peer -> peers who asked it to swap teams.
var _offers: Dictionary = {}
## Players of the other team this player may ask to swap ([[peer, name], ...]; filled
## when the other team has no bot to give up its place).
var swap_choices: Array = []
## Players who asked this player to swap teams: [[peer, name, Time.get_ticks_msec()], ...].
var swap_offers: Array = []
## Who is on which team: [[team, name, kind (DeployScreen.Kind), tank type, peer], ...]
## (host: made here; clients: the host's).
var roster: Array = []
var _roster_clock := PackedFloat32Array([0.0])


func _ready() -> void:
	NetSession.instance.game = self
	_map = get_parent()
	_take_spawns_and_clean()
	if NetRole.is_host():
		_replicator = NetReplicator.new()
		_replicator.game = self
		add_child(_replicator)
		for field: TreeField in _tree_fields():
			field.tree_index_felled.connect(_on_tree_felled.bind(_map.get_path_to(field)))
		if NetSession.instance.server == null:
			_names[1] = NetSession.instance.player_name
		# Players already here (a map change on the dedicated server) and those ready
		# while this map loaded.
		for peer: Variant in NetSession.instance.known_peers:
			var row: Array = NetSession.instance.known_peers[peer]
			on_client_hello(int(peer), str(row[0]), str(row[1]))
		_ready_pending.call_deferred()
	else:
		_puppets = NetPuppets.new()
		add_child(_puppets)
		_input = NetInput.new()
		_input.process_physics_priority = 100   # after PlayerController has set the command
		add_child(_input)
		NetSession.instance.rpc_id(1, "rpc_ready")
	if NetRole.is_host() and NetSession.instance.server != null:
		return   # the dedicated server plays nobody: no lobby, no rig
	var lobby := MatchLobby.new()
	lobby.name = "MatchLobby"
	_map.add_child.call_deferred(lobby)


func _ready_pending() -> void:
	await get_tree().create_timer(0.5).timeout
	for peer: int in NetSession.instance.take_pending_ready():
		if peer in multiplayer.get_peers():
			on_client_ready(peer)


func _exit_tree() -> void:
	if NetSession.instance.game == self:
		NetSession.instance.game = null


## True once this machine's player has a tank (the lobby is done).
func has_own_tank() -> bool:
	return is_instance_valid(_my_rig)


func tank_of_peer(peer: int) -> Tank:
	for net_id: int in owners:
		if owners[net_id] == peer and is_instance_valid(tanks.get(net_id)):
			return tanks[net_id]
	return null


# --- Map ---------------------------------------------------------------------------

func _take_spawns_and_clean() -> void:
	var rig: Node = _map.get_node_or_null("PlayerRig")
	var rig_tank: Tank = rig.get_node_or_null("Tank") as Tank if rig != null else null
	spawns[0] = rig_tank.global_transform if rig_tank != null else Transform3D(Basis(), Vector3(0, 50, 0))
	var enemies: Node = _map.get_node_or_null("Enemies")
	var first_enemy: Tank = null
	if enemies != null:
		for child: Node in enemies.get_children():
			if child is Tank:
				first_enemy = child
				break
	if first_enemy != null:
		spawns[1] = first_enemy.global_transform
		if NetSession.instance.bots:   # the bot stays there: start beside it
			spawns[1].origin += first_enemy.global_basis.x * BOT_SPAWN_OFFSET_M
	else:
		var t: Transform3D = spawns[0]
		t.origin += Vector3(1, 0, 1).normalized() * FALLBACK_SPAWN_DISTANCE_M
		spawns[1] = t
	if rig != null:
		rig.queue_free()
	for n: String in ["PlayerRespawn"]:
		var node: Node = _map.get_node_or_null(n)
		if node != null:
			node.queue_free()
	if enemies != null:
		if NetRole.is_host() and NetSession.instance.bots:
			# King of the Hill has two sides (south/north): bots fill both, alternating,
			# instead of being a third team that fights everyone at a shared spawn.
			var koth: bool = _map.find_children("*", "", true, false).any(
					func(n: Node) -> bool: return n is KothMode)
			var two_sided: bool = koth or _map.find_children("*", "", true, false).any(
					func(n: Node) -> bool: return n is ThunderRoadMode)
			var bot_count: int = 0
			for child: Node in enemies.get_children():
				if child is Tank:
					_register(child as Tank, 0)
					(child as Tank).team = (1 - bot_count % 2) if two_sided else BOT_TEAM
					bot_count += 1
					# If the mode already put the tanks at their spawns, redo it for the
					# bot's new team (otherwise the mode does it on its first frame).
					var mode: KothMode = KothMode.instance
					if koth and mode != null and mode.has_started():
						KothMode.place_tank(child as Tank, mode.get_free_spawn((child as Tank).team, child as Tank))
		else:
			enemies.queue_free()


func _tree_fields() -> Array[TreeField]:
	var out: Array[TreeField] = []
	for n: Node in _map.find_children("*", "", true, false):
		if n is TreeField:
			out.append(n)
	return out


# --- Host ----------------------------------------------------------------------------

func _register(tank: Tank, owner_peer: int) -> int:
	var net_id: int = _next_id
	_next_id += 1
	tank.net_id = net_id
	tanks[net_id] = tank
	owners[net_id] = owner_peer
	tank.fired.connect(_on_fired.bind(tank))
	tank.shot_landed.connect(_on_shot_landed.bind(tank))
	tank.spotted.connect(_on_spotted.bind(tank))
	tank.eliminated.connect(func(killer: Tank, _assists: Array[Tank]) -> void:
		if killer != null and is_instance_valid(killer) and not multiplayer.get_peers().is_empty():
			NetSession.instance.rpc("rpc_kill_feed", KillFeed.entry_of(killer, tank)))
	var server: DedicatedServer = NetSession.instance.server
	if server != null:   # statistics for the server log
		tank.eliminated.connect(func(killer: Tank, assists: Array[Tank]) -> void:
			server.on_knockout(tank, killer, assists))
		if owner_peer > 0:
			tank.fired.connect(func(_shell: Shell) -> void: server.on_shot(tank))
			tank.shot_landed.connect(func(result: HitResult) -> void: server.on_shot_landed(tank, result))
	tank.wreck_left.connect(func(at: Transform3D, yaw: float, pitch: float) -> void:
		_wrecks.append([TankBuilder.spec_of(tank), at, yaw, pitch])
		if _wrecks.size() > Tank.MAX_WRECKS:
			_wrecks.pop_front())
	# Before rpc_struck on the same channel, so the client hears the mine call first.
	tank.mine_hit.connect(func() -> void:
		var owner_id: int = int(owners.get(net_id, 0))
		if owner_id > 1 and multiplayer.get_peers().has(owner_id):
			NetSession.instance.rpc_id(owner_id, "rpc_mine_hit"))
	tank.struck.connect(func(outcome: int, direction: Vector3) -> void:
		var owner_id: int = int(owners.get(net_id, 0))
		if owner_id > 1 and multiplayer.get_peers().has(owner_id):
			NetSession.instance.rpc_id(owner_id, "rpc_struck", outcome, direction))
	tank.hit_recorded.connect(func(record: HitRecord) -> void:
		var owner_id: int = int(owners.get(net_id, 0))
		if owner_id > 1 and multiplayer.get_peers().has(owner_id):
			NetSession.instance.rpc_id(owner_id, "rpc_hit_record", record.to_array()))
	tank.near_missed.connect(func(direction: Vector3) -> void:
		var owner_id: int = int(owners.get(net_id, 0))
		if owner_id > 1 and multiplayer.get_peers().has(owner_id):
			NetSession.instance.rpc_id(owner_id, "rpc_near_miss", direction))
	tank.optics_dirtied.connect(func(amount: float) -> void:
		var owner_id: int = int(owners.get(net_id, 0))
		if owner_id > 1 and multiplayer.get_peers().has(owner_id):
			NetSession.instance.rpc_id(owner_id, "rpc_optics_dirt", amount))
	tank.smoke_launched.connect(func(points: PackedVector3Array) -> void:
		if not multiplayer.get_peers().is_empty():
			NetSession.instance.rpc("rpc_tank_smoke", net_id, points))
	tank.turret_tossed.connect(func(velocity: Vector3, spin: Vector3) -> void:
		if not multiplayer.get_peers().is_empty():
			NetSession.instance.rpc("rpc_turret_toss", net_id, velocity, spin))
	if tank.squad != null:
		var squad: Squad = tank.squad
		squad.soldier_down.connect(func(index: int, screamed: bool) -> void:
			if not multiplayer.get_peers().is_empty():
				NetSession.instance.rpc("rpc_squad_down", net_id, index, screamed))
		squad.smoke_thrown.connect(func(at: Vector3) -> void:
			if not multiplayer.get_peers().is_empty():
				NetSession.instance.rpc("rpc_squad_smoke", net_id, at))
		squad.radio.connect(func(kind: int, at: Vector3) -> void:
			var owner_id: int = int(owners.get(net_id, 0))
			if owner_id > 1 and multiplayer.get_peers().has(owner_id):
				NetSession.instance.rpc_id(owner_id, "rpc_squad_radio", net_id, kind, at))
		squad.at_aiming.connect(func(index: int, point: Vector3) -> void:
			if not multiplayer.get_peers().is_empty():
				NetSession.instance.rpc("rpc_squad_aim", net_id, index, point))
		squad.mine_laid.connect(_on_mine_laid)
		squad.fired_round.connect(func(kind: int, from: Vector3, velocity: Vector3) -> void:
			if not multiplayer.get_peers().is_empty():
				NetSession.instance.rpc("rpc_squad_shot", net_id, kind, from, velocity)
				NetSession.instance.count_out(32))
	if owner_peer != 0:
		# Back from a knock-out with another tank type picked meanwhile: that one now.
		tank.repaired.connect(func() -> void:
			var peer: int = int(owners.get(net_id, 0))
			if peer != 0 and TankSwitch.wants_other(tank, _config_of(peer)):
				respawn_player.call_deferred(peer))
		tank.knocked_out.connect(func() -> void:
			# ThunderRoad and free fight bring tanks back themselves.
			if ThunderRoadMode.instance == null and FreeFight.instance == null:
				_respawn_timers[net_id] = RESPAWN_DELAY_S)
	return net_id


## Client: a knock-out for the kill feed (KillFeed entry from the host).
func on_kill_feed(entry: Array) -> void:
	KillFeed.add_all(get_tree(), entry)


## Host: creates the tank for a player (the host's own in a PlayerRig).
func _spawn_player(peer: int) -> Tank:
	var team: int = teams.get(peer, 1)
	var xform: Transform3D = _spawn_for(team, null)
	var tank: Tank
	if peer == 1:
		_my_rig = (load(RIG_SCENE_PATH) as PackedScene).instantiate()
		tank = _my_rig.get_node("Tank")
		tank.config = _config_of(1)
		tank.display_label = NetSession.instance.player_name
		tank.team = team
		_map.add_child(_my_rig)
	else:
		tank = TANK_SCENE.instantiate()
		tank.data = load(PLAYER_DATA)
		tank.config = _config_of(peer)
		tank.display_label = _names.get(peer, "Player %d" % peer)
		tank.team = team
		var rc := RemoteController.new()
		rc.name = "RemoteController"
		rc.tank = tank
		tank.add_child(rc)
		_map.add_child(tank)
	tank.global_transform = xform
	tank.reset_physics_interpolation()
	tank.face_forward()
	var net_id: int = _register(tank, peer)
	for p: int in multiplayer.get_peers():
		_send_spawn(p, net_id)
	return tank


## The tank config `peer` drives (the host's from its garage; null = PLAYER_DATA).
func _config_of(peer: int) -> TankConfig:
	return TankConfigs.get_selected() if peer == 1 else _configs.get(peer)


## Host: `peer`'s tank goes (a knocked-out one leaves its wreck) and a new one comes at
## the spawn of its team in teams, of the type it chose. Stats go with it.
func respawn_player(peer: int) -> void:
	if not teams.has(peer):
		return
	var old: Tank = tank_of_peer(peer)
	if old != null:
		remove_tank(old)
	if peer == 1 and is_instance_valid(_my_rig):
		_my_rig.name = "PlayerRigOld"
		_my_rig.queue_free()
		_my_rig = null
	var tank: Tank = _spawn_player(peer)
	if old != null:
		TankSwitch.carry_stats(old, tank)


## Tanks on `team` (players and bots).
func _team_count(team: int) -> int:
	var n: int = 0
	for net_id: int in tanks:
		var t: Tank = tanks[net_id]
		if is_instance_valid(t) and not t.is_queued_for_deletion() and t.team == team:
			n += 1
	return n


func _name_of(peer: int) -> String:
	return str(_names.get(peer, "Player %d" % peer))


## Host: a message to `peer` (the host itself handled here).
func _send_to(peer: int, method: String, args: Array) -> void:
	if peer == 1:
		callv("on_" + method.trim_prefix("rpc_"), args)
	elif multiplayer.get_peers().has(peer):
		NetSession.instance.callv("rpc_id", [peer, method] + args)


func _notify(peer: int, text: String) -> void:
	_send_to(peer, "rpc_notice", [text, 4.0])


# --- Team swap and tank change (Esc menu) --------------------------------------------

## Any machine: ask to switch team (with_peer 0: take a bot's or a free place, else
## get the list of players to ask) or ask the player `with_peer` to swap.
func request_team_switch(with_peer: int) -> void:
	if NetRole.is_host():
		on_team_switch(1, with_peer)
	else:
		NetSession.instance.rpc_id(1, "rpc_team_switch", with_peer)


## Any machine: answer `from_peer`'s swap request.
func answer_swap(from_peer: int, accept: bool) -> void:
	swap_offers = swap_offers.filter(func(o: Array) -> bool: return int(o[0]) != from_peer)
	menu_changed.emit()
	if NetRole.is_host():
		on_swap_answer(1, from_peer, accept)
	else:
		NetSession.instance.rpc_id(1, "rpc_swap_answer", from_peer, accept)


## Any machine: drive `cfg` (a respawn now; knocked out: at the respawn).
func change_tank(cfg: TankConfig) -> void:
	TankConfigs.select(cfg)
	if NetRole.is_host():
		on_change_tank(1, cfg.key(), cfg.display_name)
	else:
		NetSession.instance.rpc_id(1, "rpc_change_tank", cfg.key(), cfg.display_name)


## Host: `peer` wants the other team. A bot there gives up its place (or the other team
## is smaller): at once. Otherwise with with_peer 0 the player gets the other team's
## players to choose from; with a player's peer, that player is asked.
func on_team_switch(peer: int, with_peer: int) -> void:
	var tank: Tank = tank_of_peer(peer)
	var from_team: int = int(teams.get(peer, -1))
	if tank == null or from_team < 0 or from_team > 1:
		return
	var to_team: int = 1 - from_team
	if with_peer > 0:
		if int(teams.get(with_peer, -1)) != to_team or tank_of_peer(with_peer) == null:
			_notify(peer, "%s is not on the other team any more" % _name_of(with_peer))
			return
		var asked: Array = _offers.get(with_peer, [])
		if not asked.has(peer):
			asked.append(peer)
		_offers[with_peer] = asked
		_send_to(with_peer, "rpc_swap_offer", [peer, _name_of(peer)])
		_notify(peer, "Asked %s to swap teams" % _name_of(with_peer))
		return
	var director: Node = _bots_director()
	var bot_tank: Tank = director.make_room(to_team) if director != null else null
	if bot_tank != null or _team_count(to_team) < _team_count(from_team):
		if bot_tank != null:
			remove_tank(bot_tank)
		teams[peer] = to_team
		respawn_player(peer)
		if director != null:
			director.refill.call_deferred()   # a bot takes the place left behind
		_notify(peer, "Switched team")
		return
	var choices: Array = []
	for p: int in teams:
		if p != peer and int(teams[p]) == to_team and tank_of_peer(p) != null:
			choices.append([p, _name_of(p)])
	if choices.is_empty():
		_notify(peer, "No place on the other team")
		return
	_send_to(peer, "rpc_team_choices", [choices])


## Host: `peer` answered `from_peer`'s swap request. Accepted, both change teams at once.
func on_swap_answer(peer: int, from_peer: int, accept: bool) -> void:
	var asked: Array = _offers.get(peer, [])
	if not asked.has(from_peer):
		return
	asked.erase(from_peer)
	if not accept:
		_notify(from_peer, "%s declined the team swap" % _name_of(peer))
		return
	var a: int = int(teams.get(peer, -1))
	var b: int = int(teams.get(from_peer, -1))
	if a < 0 or b < 0 or a > 1 or b > 1 or a == b or tank_of_peer(peer) == null \
			or tank_of_peer(from_peer) == null:
		_notify(peer, "The team swap is no longer possible")
		return
	teams[peer] = b
	teams[from_peer] = a
	_offers.erase(peer)
	_offers.erase(from_peer)
	respawn_player(peer)
	respawn_player(from_peer)
	_notify(peer, "Swapped teams with %s" % _name_of(from_peer))
	_notify(from_peer, "Swapped teams with %s" % _name_of(peer))


## Host: `peer` picked another tank type.
func on_change_tank(peer: int, config_key: String, _tank_name: String) -> void:
	var cfg: TankConfig = TankConfigs.preset_of_key(config_key)
	if cfg == null:
		return
	if peer != 1:
		_configs[peer] = cfg   # the host's own is its garage choice (TankConfigs)
	var tank: Tank = tank_of_peer(peer)
	if tank == null or not TankSwitch.wants_other(tank, cfg):
		return
	if tank.is_knocked_out():
		_notify(peer, "%s at the respawn" % cfg.display_name)
		return
	TankSwitch.count_change(tank)
	respawn_player(peer)
	_notify(peer, "Now driving %s" % cfg.display_name)


# --- Lobby: team, tank, roster ---------------------------------------------------------

## Any machine: this player wants `team` (before it has a tank).
func pick_team(team: int) -> void:
	if NetRole.is_host():
		on_pick_team(1, team)
	else:
		NetSession.instance.rpc_id(1, "rpc_pick_team", team)


## Any machine: this player is ready, in `cfg` (a preset).
func request_deploy(cfg: TankConfig) -> void:
	if NetRole.is_host():
		on_deploy(1, cfg.key())
	else:
		NetSession.instance.rpc_id(1, "rpc_deploy", cfg.key())


## Host: `peer` (without a tank) picked a team.
func on_pick_team(peer: int, team: int) -> void:
	if team < 0 or team > 1 or tank_of_peer(peer) != null:
		return
	teams[peer] = team
	_push_roster()


## Host: `peer` chose its tank: it spawns on its team, a bot there making room.
func on_deploy(peer: int, config_key: String) -> void:
	if not teams.has(peer) or tank_of_peer(peer) != null:
		return
	var cfg: TankConfig = TankConfigs.preset_of_key(config_key)
	if cfg == null:
		cfg = load(TankConfigs.DEFAULT_PRESET) as TankConfig
	if peer != 1:
		_configs[peer] = cfg   # the host's own is its TankConfigs choice (the lobby set it)
	var director: Node = _bots_director()
	if director != null:
		var bot_tank: Tank = director.make_room(int(teams[peer]))
		if bot_tank != null:
			remove_tank(bot_tank)
	_spawn_player(peer)
	if NetSession.instance.server != null:
		NetSession.instance.server.on_deploy(peer, int(teams[peer]), cfg.display_name)
	if director != null:
		director.refill.call_deferred()   # a team over full: the other side gets a bot
	_push_roster()


## Player tanks (not bots) on `team`.
func player_count(team: int) -> int:
	var n: int = 0
	for net_id: int in tanks:
		var t: Tank = tanks[net_id]
		if int(owners.get(net_id, 0)) > 0 and is_instance_valid(t) and not t.is_queued_for_deletion() \
				and t.team == team:
			n += 1
	return n


func _make_roster() -> Array:
	var rows: Array = []
	for net_id: int in tanks:
		var t: Tank = tanks[net_id]
		if not is_instance_valid(t) or t.is_queued_for_deletion():
			continue
		var peer: int = int(owners.get(net_id, 0))
		rows.append([t.team, _name_of(peer) if peer > 0 else "Bot",
				DeployScreen.Kind.PLAYER if peer > 0 else DeployScreen.Kind.BOT, t.get_type_name(), peer])
	for peer: int in teams:
		if tank_of_peer(peer) == null:
			rows.append([int(teams[peer]), _name_of(peer), DeployScreen.Kind.CHOOSING, "", peer])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return int(a[0]) < int(b[0])
		if a[2] != b[2]:
			return int(a[2]) < int(b[2])
		return str(a[1]) < str(b[1]))
	return rows


## Host: the roster to everyone if it changed.
func _push_roster() -> void:
	var rows: Array = _make_roster()
	if rows == roster:
		return
	roster = rows
	roster_changed.emit()
	if not multiplayer.get_peers().is_empty():
		NetSession.instance.rpc("rpc_roster", rows)


## Client: the host's roster.
func on_roster(rows: Array) -> void:
	roster = rows
	roster_changed.emit()


## Where a player of `team` (re)spawns: the King of the Hill spawn for the current zone
## if there is one, else the map's start for the team.
func _spawn_for(team: int, tank: Tank) -> Transform3D:
	if ThunderRoadMode.instance != null:
		return ThunderRoadMode.instance.spawn_for_new(team, tank)
	if FreeFight.instance != null:
		return FreeFight.instance.spawn_for_new(team, tank)
	var mode: KothMode = KothMode.instance
	if mode != null and mode.has_started():
		return mode.get_free_spawn(team, tank)
	return spawns.get(team, spawns[0])


func _send_spawn(peer: int, net_id: int) -> void:
	var tank: Tank = tanks[net_id]
	NetSession.instance.rpc_id(peer, "rpc_spawn_tank", net_id, owners[net_id], tank.team, TankBuilder.spec_of(tank),
			tank.global_transform)


func on_client_hello(peer: int, player_name: String, config_key: String) -> void:
	_names[peer] = player_name.strip_edges().left(20)
	var cfg: TankConfig = TankConfigs.preset_of_key(config_key)
	if cfg != null:
		_configs[peer] = cfg
	# No team yet: the player picks one in the lobby (on_pick_team).


func on_client_ready(peer: int) -> void:
	for net_id: int in tanks:
		_send_spawn(peer, net_id)
	for f: Array in _felled:
		NetSession.instance.rpc_id(peer, "rpc_tree_felled", f[0], f[1], f[2])
	for w: Array in _wrecks:
		NetSession.instance.rpc_id(peer, "rpc_wreck", w[0], w[1], w[2], w[3])
	# Wrecks pushed before the peer came: where they are now.
	var keys := PackedVector3Array()
	var poses: Array[Transform3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"wrecks"):
		var wreck := node as Wreck
		if wreck != null and not wreck.is_queued_for_deletion():
			keys.append(wreck.made_at)
			poses.append(wreck.global_transform)
	if not keys.is_empty():
		NetSession.instance.rpc_id(peer, "rpc_wreck_moves", keys, poses)
	for node: Node in get_tree().get_nodes_in_group(Mine.GROUP):
		var mine := node as Mine
		if mine != null and not mine.is_queued_for_deletion():
			NetSession.instance.rpc_id(peer, "rpc_mine_laid", mine.net_id, mine.data.resource_path,
					mine.global_position, mine.team, mine.get_known_teams())
	# No tank yet: the player chooses team and tank in the lobby first.
	_push_roster()
	NetSession.instance.rpc_id(peer, "rpc_roster", roster)


func on_client_left(peer: int) -> void:
	teams.erase(peer)
	_offers.erase(peer)
	for p: Variant in _offers:
		(_offers[p] as Array).erase(peer)
	_configs.erase(peer)
	_names.erase(peer)
	for net_id: int in owners.keys():
		if owners[net_id] == peer:
			var tank: Tank = tanks[net_id]
			tanks.erase(net_id)
			owners.erase(net_id)
			if is_instance_valid(tank):
				tank.leave_wreck()
				tank.queue_free()
			NetSession.instance.rpc("rpc_despawn_tank", net_id)
	# Bots take the empty place again.
	var director: Node = _bots_director()
	if director != null:
		director.refill.call_deferred()
	_push_roster()


## The mode's bot director (KothBots or ThunderRoadBots: make_room, refill), or null.
func _bots_director() -> Node:
	if KothBots.instance != null:
		return KothBots.instance
	if FreeFight.instance != null:
		return FreeFight.instance
	return ThunderRoadBots.instance


## Host: a bot tank KothBots added during the match: replicate it like the rest.
func add_bot_tank(tank: Tank) -> void:
	var net_id: int = _register(tank, 0)
	for p: int in multiplayer.get_peers():
		_send_spawn(p, net_id)


## Host: takes a tank (a bot making room, or an extra bot) out of the game everywhere;
## a knocked-out one leaves its wreck.
func remove_tank(tank: Tank) -> void:
	var net_id: int = tank.net_id
	tanks.erase(net_id)
	owners.erase(net_id)
	_respawn_timers.erase(net_id)
	tank.leave_wreck()
	if tank.squad != null and is_instance_valid(tank.squad):
		tank.squad.queue_free()
	tank.queue_free()
	if not multiplayer.get_peers().is_empty():
		NetSession.instance.rpc("rpc_despawn_tank", net_id)


func on_command(peer: int, buf: StreamPeerBuffer) -> void:
	var tank: Tank = tank_of_peer(peer)
	if tank == null:
		return
	var rc := tank.get_node_or_null("RemoteController") as RemoteController
	if rc != null:
		rc.receive(buf)


func _on_fired(shell: Shell, tank: Tank) -> void:
	if not multiplayer.get_peers().is_empty():
		var v: Vector3 = shell.get_velocity()
		NetSession.instance.rpc("rpc_shell", tank.net_id, tank.get_ammo_index(), shell.global_position, v, true)
		NetSession.instance.count_out(40)
	shell.ricocheted.connect(func(from: Vector3, velocity: Vector3) -> void:
		if is_instance_valid(tank) and not multiplayer.get_peers().is_empty():
			NetSession.instance.rpc("rpc_shell", tank.net_id, tank.get_ammo_index(), from, velocity, false))


func _on_shot_landed(result: HitResult, tank: Tank) -> void:
	var owner_peer: int = owners.get(tank.net_id, 0)
	if owner_peer > 1 and result != null and not result.bullet:
		var text: String = result.describe()
		if result.outcome == HitResult.Outcome.COMMANDER_HIT and result.target == tank:
			text = "OWN COMMANDER HIT"
		NetSession.instance.rpc_id(owner_peer, "rpc_shot_result", text, result.outcome)
		NetSession.instance.count_out(text.length() + 8)


func _on_spotted(target: Node3D, point: Vector3, tank: Tank) -> void:
	var key: int = SpotMarks.key_of(target)
	if key == 0:
		return
	for peer: int in teams:
		if peer > 1 and teams[peer] == tank.team:
			NetSession.instance.rpc_id(peer, "rpc_team_spot", key, point)
	# The host's own marks: its SpotMarks listens to its own tank; teammates' spots too.
	if teams.get(1, -1) == tank.team and owners.get(tank.net_id, 0) != 1:
		on_team_spot(key, point)


func _on_tree_felled(index: int, direction: Vector3, field: NodePath) -> void:
	_felled.append([field, index, direction])
	if not multiplayer.get_peers().is_empty():
		NetSession.instance.rpc("rpc_tree_felled", field, index, direction)


func _physics_process(delta: float) -> void:
	if not NetRole.is_host():
		return
	_update_koth(delta)
	_update_thunder(delta)
	_update_free(delta)
	if Ticks.due(_roster_clock, delta, ROSTER_HZ):
		_push_roster()
	_send_squads()
	_send_wreck_moves()
	for net_id: int in _respawn_timers.keys():
		_respawn_timers[net_id] -= delta
		if _respawn_timers[net_id] > 0.0:
			continue
		_respawn_timers.erase(net_id)
		var tank: Tank = tanks.get(net_id)
		if not is_instance_valid(tank):
			continue
		var team: int = teams.get(owners.get(net_id, 0), tank.team)
		KothMode.place_tank(tank, _spawn_for(team, tank))
		tank.repair()


## Host: King of the Hill state to every client, regularly and when the zone moves or
## the match ends; kill bonuses as they happen.
func _update_koth(delta: float) -> void:
	var mode: KothMode = KothMode.instance
	if mode == null:
		return
	if mode != _koth_hooked:
		_koth_hooked = mode
		mode.zone_moved.connect(func(_c: Vector3) -> void: _koth_timer = 0.0)
		mode.match_over.connect(func(_w: int) -> void: _send_koth_state(mode))
		mode.kill_bonus.connect(func(team: int, points: float) -> void:
			if not multiplayer.get_peers().is_empty():
				NetSession.instance.rpc("rpc_koth_bonus", team, points))
	_koth_timer -= delta
	if _koth_timer <= 0.0:
		_koth_timer = KOTH_SEND_INTERVAL_S
		_send_koth_state(mode)


## Host: ThunderRoad state to every client, twice a second and at once on checkpoints,
## rounds and the end. A new round also empties the late-joiner lists of round 1.
func _update_thunder(delta: float) -> void:
	var mode: ThunderRoadMode = ThunderRoadMode.instance
	if mode == null:
		return
	if mode != _thunder_hooked:
		_thunder_hooked = mode
		mode.checkpoint_taken.connect(func(_i: int) -> void: _thunder_timer = 0.0)
		mode.pause_ended.connect(func(_i: int) -> void: _thunder_timer = 0.0)
		mode.round_over.connect(func(_n: int, _r: Dictionary) -> void: _thunder_timer = 0.0)
		mode.match_over.connect(func(_w: int) -> void: _send_thunder_state(mode))
		mode.round_started.connect(func(_n: int, _t: int) -> void: _thunder_timer = 0.0)
		mode.map_reset.connect(func() -> void:
			_felled.clear()   # trees stand, wrecks are gone
			_wrecks.clear())
	_thunder_timer -= delta
	if _thunder_timer <= 0.0:
		_thunder_timer = KOTH_SEND_INTERVAL_S
		_send_thunder_state(mode)


## Host: free fight state to every client, twice a second and at once on its events.
func _update_free(delta: float) -> void:
	var mode: FreeFight = FreeFight.instance
	if mode == null:
		return
	if mode != _free_hooked:
		_free_hooked = mode
		mode.wave_started.connect(func(_r: int) -> void: _free_timer = 0.0)
		mode.wave_attacking.connect(func() -> void: _free_timer = 0.0)
		mode.wave_cleared.connect(func(_r: int) -> void: _free_timer = 0.0)
		mode.match_over.connect(func(_c: int) -> void: _free_timer = 0.0)
	_free_timer -= delta
	if _free_timer <= 0.0:
		_free_timer = KOTH_SEND_INTERVAL_S
		if not multiplayer.get_peers().is_empty():
			NetSession.instance.rpc("rpc_free_state", mode.get_net_state())
			NetSession.instance.count_out(120)


func _send_thunder_state(mode: ThunderRoadMode) -> void:
	if multiplayer.get_peers().is_empty() or not mode.has_started():
		return
	NetSession.instance.rpc("rpc_thunder_state", mode.get_net_state())
	NetSession.instance.count_out(220)


func _send_koth_state(mode: KothMode) -> void:
	if multiplayer.get_peers().is_empty() or not mode.has_started():
		return
	NetSession.instance.rpc("rpc_koth_state", mode.get_net_state())
	NetSession.instance.count_out(160)


## Host: wrecks pushed since the last send (keyed by where they were made).
func _send_wreck_moves() -> void:
	if not Ticks.due(_wreck_clock, get_physics_process_delta_time(), WRECK_SEND_HZ) \
			or multiplayer.get_peers().is_empty():
		return
	var moves: Array = Wreck.collect_moves(get_tree())
	if (moves[0] as PackedVector3Array).is_empty():
		return
	NetSession.instance.rpc("rpc_wreck_moves", moves[0], moves[1])
	NetSession.instance.count_out((moves[0] as PackedVector3Array).size() * 60)


## Client: the host pushed these wrecks (made at `keys`) to `poses`.
func on_wreck_moves(keys: PackedVector3Array, poses: Array) -> void:
	for i: int in mini(keys.size(), poses.size()):
		Wreck.apply_move(get_tree(), keys[i], poses[i])


## Host: every registered tank's squad to every client (10 Hz, one unreliable packet).
func _send_squads() -> void:
	if not Ticks.due(_squad_clock, get_physics_process_delta_time(), SQUAD_SEND_HZ) \
			or multiplayer.get_peers().is_empty():
		return
	var buf := StreamPeerBuffer.new()
	buf.put_u8(NetSession.PACKET_SQUADS)
	var count_at: int = buf.get_position()
	buf.put_u8(0)
	var count: int = 0
	for net_id: int in tanks:
		var tank: Tank = tanks[net_id]
		if not is_instance_valid(tank) or tank.squad == null or not is_instance_valid(tank.squad) \
				or not tank.squad.is_inside_tree():   # a new tank's squad comes in a frame late
			continue
		buf.put_u16(net_id)
		tank.squad.write_net_state(buf)
		count += 1
		if count == 255:
			break
	var bytes: PackedByteArray = buf.data_array
	bytes[count_at] = count
	for peer: int in multiplayer.get_peers():
		NetSession.instance.send_raw(bytes, peer, NetSession.CH_SNAPSHOT)


## Host: a client sent its squad (via its own tank).
func on_tank_action(peer: int, kind: int) -> void:
	var tank: Tank = tank_of_peer(peer)
	var rc := tank.get_node_or_null("RemoteController") as RemoteController if tank != null else null
	if rc != null:
		rc.request_action(kind)


## Host: a squad laid a mine: clients get it, and its finding and removal later.
func _on_mine_laid(mine: Mine) -> void:
	mine.known.connect(func(team: int) -> void:
		if not multiplayer.get_peers().is_empty():
			NetSession.instance.rpc("rpc_mine_known", mine.net_id, team))
	mine.gone.connect(func(exploded: bool) -> void:
		if not multiplayer.get_peers().is_empty():
			NetSession.instance.rpc("rpc_mine_gone", mine.net_id, exploded))
	if not multiplayer.get_peers().is_empty():
		NetSession.instance.rpc("rpc_mine_laid", mine.net_id, mine.data.resource_path,
				mine.global_position, mine.team, mine.get_known_teams())


func on_squad_order(peer: int, kind: int, target: Vector3) -> void:
	var tank: Tank = tank_of_peer(peer)
	if tank != null and tank.squad != null and is_instance_valid(tank.squad):
		tank.squad.order(kind, target)


# --- Client ------------------------------------------------------------------------------

func on_squads(buf: StreamPeerBuffer) -> void:
	var count: int = buf.get_u8()
	for i: int in count:
		var net_id: int = buf.get_u16()
		var tank: Tank = tanks.get(net_id)
		if tank != null and is_instance_valid(tank) and tank.squad != null and is_instance_valid(tank.squad) \
				and tank.squad.is_inside_tree():
			tank.squad.read_net_state(buf)
		else:
			Squad.skip_net_state(buf)


func _squad_of(net_id: int) -> Squad:
	var tank: Tank = tanks.get(net_id)
	if tank == null or not is_instance_valid(tank) or tank.squad == null or not is_instance_valid(tank.squad):
		return null
	return tank.squad


func on_squad_radio(net_id: int, kind: int, at: Vector3) -> void:
	var squad: Squad = _squad_of(net_id)
	if squad != null:
		squad.radio.emit(kind, at)


func on_squad_down(net_id: int, index: int, screamed: bool) -> void:
	var squad: Squad = _squad_of(net_id)
	if squad != null:
		squad.net_soldier_down(index, screamed)


func on_mine_laid(id: int, data_path: String, at: Vector3, team: int,
		known_by: PackedInt32Array) -> void:
	if Mine.find(get_tree(), id) != null:
		return
	var mine_data := load(data_path) as MineData
	if mine_data == null:
		return
	var mine: Mine = Mine.make_puppet(get_tree().current_scene, mine_data, team, at, id)
	for t: int in known_by:
		mine.mark_known(t)


func on_mine_known(id: int, team: int) -> void:
	var mine: Mine = Mine.find(get_tree(), id)
	if mine != null:
		mine.mark_known(team)


func on_mine_gone(id: int, exploded: bool) -> void:
	var mine: Mine = Mine.find(get_tree(), id)
	if mine == null:
		return
	if exploded:
		mine.blow_up()
	else:
		mine.remove()


func on_squad_smoke(net_id: int, at: Vector3) -> void:
	var squad: Squad = _squad_of(net_id)
	if squad != null:
		squad.throw_smoke(at)


func on_squad_aim(net_id: int, index: int, point: Vector3) -> void:
	var squad: Squad = _squad_of(net_id)
	if squad != null:
		squad.net_at_aiming(index, point)


func on_squad_shot(net_id: int, kind: int, from: Vector3, velocity: Vector3) -> void:
	var squad: Squad = _squad_of(net_id)
	if squad != null:
		squad.net_show_shot(kind, from, velocity)

func on_koth_state(state: Dictionary) -> void:
	if KothMode.instance != null:
		KothMode.instance.apply_net_state(state)


func on_free_state(state: Dictionary) -> void:
	if FreeFight.instance != null:
		FreeFight.instance.apply_net_state(state)


func on_thunder_state(state: Dictionary) -> void:
	if ThunderRoadMode.instance != null:
		ThunderRoadMode.instance.apply_net_state(state)


func on_koth_bonus(team: int, points: float) -> void:
	if KothMode.instance != null:
		KothMode.instance.kill_bonus.emit(team, points)


func on_snapshot(buf: StreamPeerBuffer) -> void:
	if _puppets != null:
		_puppets.receive(buf)


func on_spawn_tank(net_id: int, owner_peer: int, team: int, data_path: String, xform: Transform3D) -> void:
	print_verbose("net: spawn tank %d owner %d team %d" % [net_id, owner_peer, team])
	if tanks.has(net_id):
		return
	var tank: Tank
	if owner_peer == NetSession.instance.my_id():
		_my_rig = (load(RIG_SCENE_PATH) as PackedScene).instantiate()
		tank = _my_rig.get_node("Tank")
		TankBuilder.apply_spec(tank, data_path, PLAYER_DATA)
		tank.set_net_puppet(true)
		tank.team = team
		tank.net_id = net_id
		_map.add_child(_my_rig)
		_input.tank = tank
	else:
		tank = TANK_SCENE.instantiate()
		if data_path == "":
			push_warning("spawn without data path for net_id %d" % net_id)
		TankBuilder.apply_spec(tank, data_path, PLAYER_DATA)
		tank.team = team
		tank.net_id = net_id
		tank.set_net_puppet(false)
		_map.add_child(tank)
	tank.global_transform = xform
	tank.reset_physics_interpolation()
	tank.face_forward()
	tanks[net_id] = tank
	owners[net_id] = owner_peer
	_puppets.register(tank)
	print_verbose("net: tanks now %s" % [tanks.keys()])


## Client (joined late): a wreck left before we came. Built from a throw-away tank of the
## same kind, so it looks like the ones made here.
func on_wreck(spec: String, at: Transform3D, turret_yaw: float, gun_pitch: float) -> void:
	var tank: Tank = TANK_SCENE.instantiate()
	TankBuilder.apply_spec(tank, spec, PLAYER_DATA)
	tank.wreck_only = true
	tank.set_net_puppet(false)
	_map.add_child(tank)
	tank.global_transform = at
	tank.make_wreck_here(turret_yaw, gun_pitch)


func on_despawn_tank(net_id: int) -> void:
	print_verbose("net: despawn tank %d" % net_id)
	var tank: Tank = tanks.get(net_id)
	# The own tank (team swap, other tank type): its rig goes too; the new one follows.
	if int(owners.get(net_id, 0)) == NetSession.instance.my_id() and is_instance_valid(_my_rig):
		_my_rig.name = "PlayerRigOld"
		_my_rig.queue_free()
		_my_rig = null
	tanks.erase(net_id)
	owners.erase(net_id)
	if _puppets != null:
		_puppets.unregister(net_id)
	if is_instance_valid(tank):
		tank.leave_wreck()
		if tank.squad != null and is_instance_valid(tank.squad):
			tank.squad.queue_free()
		tank.queue_free()


func on_shell(net_id: int, shell_index: int, from: Vector3, velocity: Vector3, flash: bool) -> void:
	var tank: Tank = tanks.get(net_id)
	if is_instance_valid(tank):
		tank.net_show_shell(shell_index, from, velocity, flash)


func on_shot_result(text: String, outcome: int) -> void:
	var fb: HitFeedback = _my_rig.get_node_or_null("HUD/HitFeedback") as HitFeedback if _my_rig != null else null
	if fb != null:
		fb.show_text(text, outcome)


## Client: an ammo explosion threw a tank's turret.
func on_turret_toss(net_id: int, velocity: Vector3, spin: Vector3) -> void:
	var tank: Tank = tanks.get(net_id)
	if is_instance_valid(tank):
		tank.toss_turret(velocity, spin)


## Client: a tank (any) fired smoke.
func on_tank_smoke(net_id: int, points: PackedVector3Array) -> void:
	var tank: Tank = tanks.get(net_id)
	if is_instance_valid(tank):
		tank.net_show_smoke(points)


## Client: a gun round landed close to the own tank (the crew shouts).
## Client: dirt on the own tank's optics (an HE burst near it on the host).
func on_optics_dirt(amount: float) -> void:
	var tank: Tank = _my_rig.get_node_or_null("Tank") as Tank if _my_rig != null else null
	if tank != null:
		tank.add_optics_dirt(amount)


func on_near_miss(direction: Vector3) -> void:
	var tank: Tank = _my_rig.get_node_or_null("Tank") as Tank if _my_rig != null else null
	if tank != null:
		tank.net_near_miss(direction)


## Client: the host's record of a gun round on the own tank (killcam, hit picture).
func on_hit_record(data: Array) -> void:
	var tank: Tank = _my_rig.get_node_or_null("Tank") as Tank if _my_rig != null else null
	if tank != null:
		tank.net_hit_record(HitRecord.from_array(data))


## Client: a gun round hit the own tank (shake, ping, driving keys cancelled).
func on_mine_hit() -> void:
	var tank: Tank = _my_rig.get_node_or_null("Tank") as Tank if _my_rig != null else null
	if tank != null:
		tank.net_mine_hit()


func on_struck(outcome: int, direction: Vector3) -> void:
	var tank: Tank = _my_rig.get_node_or_null("Tank") as Tank if _my_rig != null else null
	if tank != null:
		tank.net_struck(outcome, direction)


func on_team_spot(key: int, point: Vector3) -> void:
	var marks: SpotMarks = _my_rig.get_node_or_null("SpotMarks") as SpotMarks if _my_rig != null else null
	if marks != null:
		marks.add_mark(key, point)


## The other team's players to ask for a swap (no bot there to give up its place).
func on_team_choices(choices: Array) -> void:
	swap_choices = choices
	menu_changed.emit()


## `from_peer` asks to swap teams with this player.
func on_swap_offer(from_peer: int, from_name: String) -> void:
	swap_offers = swap_offers.filter(func(o: Array) -> bool: return int(o[0]) != from_peer)
	swap_offers.append([from_peer, from_name, Time.get_ticks_msec()])
	on_notice("%s wants to swap teams with you, esc to respond" % from_name, SWAP_OFFER_S)
	menu_changed.emit()


## Swap requests still open (older than SWAP_OFFER_S are dropped).
func get_swap_offers() -> Array:
	var now: int = Time.get_ticks_msec()
	swap_offers = swap_offers.filter(func(o: Array) -> bool:
		return now - int(o[2]) < int(SWAP_OFFER_S * 1000.0))
	return swap_offers


func on_notice(text: String, seconds: float) -> void:
	var notice: MatchNotice = _my_rig.get_node_or_null("HUD/MatchNotice") as MatchNotice \
			if is_instance_valid(_my_rig) else null
	if notice != null:
		notice.show_text(text, seconds)


func on_tree_felled(field: NodePath, index: int, direction: Vector3) -> void:
	var tf := _map.get_node_or_null(field) as TreeField
	if tf != null and not tf.is_tree_felled(index):
		tf.fell_tree(index, direction)
