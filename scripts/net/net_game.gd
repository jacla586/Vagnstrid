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
## Client: puppets for every tank (NetPuppets), its own inside a PlayerRig with turret
## prediction; sends its commands (NetInput).

const TANK_SCENE: PackedScene = preload("res://scenes/tank/tank.tscn")
const RIG_SCENE: PackedScene = preload("res://scenes/player/player_rig.tscn")
const PLAYER_DATA: String = "res://data/tanks/player_medium.tres"
const RESPAWN_DELAY_S: float = 10.0
const BOT_TEAM: int = 2
## Fallback start for team 1 if the map has no enemy tank: this far from team 0 (m).
const FALLBACK_SPAWN_DISTANCE_M: float = 300.0
## With bots on, team 1 starts this far beside the first bot (which keeps its place).
const BOT_SPAWN_OFFSET_M: float = 15.0
## King of the Hill state to clients this often (s), and at once on zone changes.
const KOTH_SEND_INTERVAL_S: float = 0.5
## Infantry squads to clients every this many physics ticks (6 = 10 Hz, unreliable).
const SQUAD_SEND_TICKS: int = 6

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
var _squad_tick: int = 0
var _koth_hooked: KothMode


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
		teams[1] = 0
		_spawn_player(1)
	else:
		_puppets = NetPuppets.new()
		add_child(_puppets)
		_input = NetInput.new()
		_input.process_physics_priority = 100   # after PlayerController has set the command
		add_child(_input)
		NetSession.instance.rpc_id(1, "rpc_ready")


func _exit_tree() -> void:
	if NetSession.instance.game == self:
		NetSession.instance.game = null


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
			var bot_count: int = 0
			for child: Node in enemies.get_children():
				if child is Tank:
					_register(child as Tank, 0)
					(child as Tank).team = (1 - bot_count % 2) if koth else BOT_TEAM
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
	tank.wreck_left.connect(func(at: Transform3D, yaw: float, pitch: float) -> void:
		_wrecks.append([TankBuilder.spec_of(tank), at, yaw, pitch])
		if _wrecks.size() > Tank.MAX_WRECKS:
			_wrecks.pop_front())
	tank.struck.connect(func(outcome: int, direction: Vector3) -> void:
		var owner_id: int = int(owners.get(net_id, 0))
		if owner_id > 1 and multiplayer.get_peers().has(owner_id):
			NetSession.instance.rpc_id(owner_id, "rpc_struck", outcome, direction))
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
		squad.fired_round.connect(func(kind: int, from: Vector3, velocity: Vector3) -> void:
			if not multiplayer.get_peers().is_empty():
				NetSession.instance.rpc("rpc_squad_shot", net_id, kind, from, velocity)
				NetSession.instance.count_out(32))
	if owner_peer != 0:
		tank.knocked_out.connect(func() -> void: _respawn_timers[net_id] = RESPAWN_DELAY_S)
	return net_id


## Host: creates the tank for a player (the host's own in a PlayerRig).
func _spawn_player(peer: int) -> void:
	var team: int = teams.get(peer, 1)
	var xform: Transform3D = _spawn_for(team, null)
	var tank: Tank
	if peer == 1:
		_my_rig = RIG_SCENE.instantiate()
		tank = _my_rig.get_node("Tank")
		tank.config = TankConfigs.get_selected()
		tank.display_label = NetSession.instance.player_name
		tank.team = team
		_map.add_child(_my_rig)
	else:
		tank = TANK_SCENE.instantiate()
		tank.data = load(PLAYER_DATA)
		tank.config = _configs.get(peer)
		tank.display_label = _names.get(peer, "Player %d" % peer)
		tank.team = team
		var rc := RemoteController.new()
		rc.name = "RemoteController"
		rc.tank = tank
		tank.add_child(rc)
		_map.add_child(tank)
	tank.global_transform = xform
	var net_id: int = _register(tank, peer)
	for p: int in multiplayer.get_peers():
		_send_spawn(p, net_id)


## Where a player of `team` (re)spawns: the King of the Hill spawn for the current zone
## if there is one, else the map's start for the team.
func _spawn_for(team: int, tank: Tank) -> Transform3D:
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
	var cfg: TankConfig = TankConfig.from_key(config_key)
	if cfg != null and TankBuilder.build(cfg) != null:
		_configs[peer] = cfg
	# Teams alternate between 0 and 1 as players join.
	var counts: Array[int] = [0, 0]
	for p: int in teams:
		if teams[p] < 2:
			counts[teams[p]] += 1
	teams[peer] = 0 if counts[0] <= counts[1] else 1


func on_client_ready(peer: int) -> void:
	# A team filled up with bots: one leaves to make room for the player.
	if KothBots.instance != null:
		var bot_tank: Tank = KothBots.instance.make_room(int(teams.get(peer, 1)))
		if bot_tank != null:
			remove_tank(bot_tank)
	for net_id: int in tanks:
		_send_spawn(peer, net_id)
	for f: Array in _felled:
		NetSession.instance.rpc_id(peer, "rpc_tree_felled", f[0], f[1], f[2])
	for w: Array in _wrecks:
		NetSession.instance.rpc_id(peer, "rpc_wreck", w[0], w[1], w[2], w[3])
	_spawn_player(peer)


func on_client_left(peer: int) -> void:
	teams.erase(peer)
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
	if KothBots.instance != null:
		KothBots.instance.refill.call_deferred()


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
	if owner_peer > 1 and result != null:
		var text: String = result.describe()
		if result.outcome == HitResult.Outcome.COMMANDER_HIT and result.target == tank:
			text = "OWN COMMANDER HIT"
		NetSession.instance.rpc_id(owner_peer, "rpc_shot_result", text, result.outcome)
		NetSession.instance.count_out(text.length() + 8)


func _on_spotted(point: Vector3, tank: Tank) -> void:
	for peer: int in teams:
		if peer > 1 and teams[peer] == tank.team:
			NetSession.instance.rpc_id(peer, "rpc_team_spot", point)
	# The host's own marks: its SpotMarks listens to its own tank; teammates' spots too.
	if teams.get(1, -1) == tank.team and owners.get(tank.net_id, 0) != 1:
		on_team_spot(point)


func _on_tree_felled(index: int, direction: Vector3, field: NodePath) -> void:
	_felled.append([field, index, direction])
	if not multiplayer.get_peers().is_empty():
		NetSession.instance.rpc("rpc_tree_felled", field, index, direction)


func _physics_process(delta: float) -> void:
	if not NetRole.is_host():
		return
	_update_koth(delta)
	_send_squads()
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


func _send_koth_state(mode: KothMode) -> void:
	if multiplayer.get_peers().is_empty() or not mode.has_started():
		return
	NetSession.instance.rpc("rpc_koth_state", mode.get_net_state())
	NetSession.instance.count_out(160)


## Host: every registered tank's squad to every client (10 Hz, one unreliable packet).
func _send_squads() -> void:
	_squad_tick += 1
	if _squad_tick % SQUAD_SEND_TICKS != 0 or multiplayer.get_peers().is_empty():
		return
	var buf := StreamPeerBuffer.new()
	buf.put_u8(NetSession.PACKET_SQUADS)
	var count_at: int = buf.get_position()
	buf.put_u8(0)
	var count: int = 0
	for net_id: int in tanks:
		var tank: Tank = tanks[net_id]
		if not is_instance_valid(tank) or tank.squad == null or not is_instance_valid(tank.squad):
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
		_my_rig = RIG_SCENE.instantiate()
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


## Client: a gun round hit the own tank (shake, ping, driving keys cancelled).
func on_struck(outcome: int, direction: Vector3) -> void:
	var tank: Tank = _my_rig.get_node_or_null("Tank") as Tank if _my_rig != null else null
	if tank != null:
		tank.net_struck(outcome, direction)


func on_team_spot(point: Vector3) -> void:
	var marks: SpotMarks = _my_rig.get_node_or_null("SpotMarks") as SpotMarks if _my_rig != null else null
	if marks != null:
		marks.add_mark(point)


func on_tree_felled(field: NodePath, index: int, direction: Vector3) -> void:
	var tf := _map.get_node_or_null(field) as TreeField
	if tf != null and not tf.is_tree_felled(index):
		tf.fell_tree(index, direction)
