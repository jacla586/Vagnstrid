class_name NetSession
extends Node
## Network session (autoload "Net"; other scripts use NetSession.instance). Host-authoritative: the host runs the whole game,
## clients send their TankCommand and draw what the host sends. See NetGame for the
## game side, NetReplicator/NetPuppets for snapshots and NetInput for commands.
##
## Wire: ENet with three channels. Raw packets (SceneMultiplayer.send_bytes) for the
## frequent traffic: snapshots host -> client (unreliable, channel 0) and commands
## client -> host (unreliable, channel 1). Everything else is reliable RPCs on this node
## (channel 2), so the node path is the same on every peer.
##
## Command line (after --): --host [--map vidingsjo] [--bots] [--name N]
##                          --join <ip> [--name N]

signal status_changed(text: String)

const PORT: int = 24680
## Port in use: PORT, or --port N on the command line (several hosts on one machine).
var port: int = PORT
const MAX_CLIENTS: int = 39
const CHANNELS: int = 3
const CH_SNAPSHOT: int = 0
const CH_COMMAND: int = 1
const PACKET_SNAPSHOT: int = 1
const PACKET_COMMAND: int = 2
const PACKET_SQUADS: int = 3
const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const DEFAULT_MAP: String = "res://scenes/maps/vidingsjo.tscn"
## ENet drops a peer it hasn't heard from in this long (ms). Loading a big map (and the
## first frames' shader compiles) can stall a machine for many seconds.
const PEER_TIMEOUT_MIN_MS: int = 30000
const PEER_TIMEOUT_MAX_MS: int = 60000

## The running session (the autoload), for scripts that can't use the autoload name.
static var instance: NetSession

var player_name: String = "Player"
var map_path: String = ""
var bots: bool = false
## The running game in the loaded map (null in menus).
var game: NetGame
var status: String = ""

# statistics (bytes of our own packets and RPC payloads, per second)
var in_bps: float = 0.0
var out_bps: float = 0.0
var snapshots_per_s: float = 0.0
var _in_bytes: int = 0
var _out_bytes: int = 0
var _snapshots: int = 0
var _stat_time: float = 0.0
var _stats_label: Label


func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_stats_overlay()
	var smp := multiplayer as SceneMultiplayer
	smp.peer_packet.connect(_on_packet)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed.bind("connection failed"))
	multiplayer.server_disconnected.connect(_on_failed.bind("host left"))
	_parse_command_line.call_deferred()


func _parse_command_line() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var map: String = DEFAULT_MAP
	var join_ip: String = ""
	var do_host: bool = false
	var i: int = 0
	while i < args.size():
		match args[i]:
			"--host": do_host = true
			"--bots": bots = true
			"--map":
				i += 1
				map = _map_from_arg(args[i])
			"--join":
				i += 1
				join_ip = args[i]
			"--name":
				i += 1
				player_name = args[i]
			"--port":
				i += 1
				port = int(args[i])
		i += 1
	if do_host:
		host(map, bots)
	elif join_ip != "":
		join(join_ip)


static func _map_from_arg(a: String) -> String:
	if a.begins_with("res://"):
		return a
	for dir: String in ["res://scenes/maps/", "res://scenes/scenarios/"]:
		if ResourceLoader.exists(dir + a + ".tscn"):
			return dir + a + ".tscn"
	return DEFAULT_MAP


# --- Session --------------------------------------------------------------------------

func host(map: String, with_bots: bool) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_CLIENTS, CHANNELS)
	if err != OK:
		_set_status("could not host on port %d (%s)" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	NetRole.role = NetRole.Role.HOST
	map_path = map
	bots = with_bots
	_set_status("hosting on port %d" % port)
	_load_map(map)
	return OK


func join(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port, CHANNELS)
	if err != OK:
		_set_status("could not connect (%s)" % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	NetRole.role = NetRole.Role.CLIENT
	_set_status("connecting to %s ..." % ip)
	return OK


## Back to the menu, closing the connection.
func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetRole.role = NetRole.Role.OFFLINE
	game = null
	get_tree().change_scene_to_file(MENU_SCENE)


func my_id() -> int:
	return multiplayer.get_unique_id()


## Loads the map on a thread (so the connection keeps being serviced), then adds NetGame.
func _load_map(path: String) -> void:
	_set_status("loading %s ..." % path.get_file().get_basename())
	ResourceLoader.load_threaded_request(path)
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null:
		_set_status("could not load %s" % path)
		return
	get_tree().change_scene_to_packed(packed)
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != path:
		await get_tree().process_frame
	var g := NetGame.new()
	g.name = "NetGame"
	get_tree().current_scene.add_child(g)


func _set_peer_timeout(id: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var p: ENetPacketPeer = peer.get_peer(id) if peer != null else null
	if p != null:
		p.set_timeout(0, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)


func _on_peer_connected(id: int) -> void:
	if NetRole.is_host():   # clients only have a direct link to the host (id 1)
		_set_peer_timeout(id)
	if NetRole.is_host():
		_set_status("player %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	if NetRole.is_host() and game != null:
		game.on_client_left(id)


func _on_connected() -> void:
	_set_peer_timeout(1)
	_set_status("connected, loading map ...")
	var cfg: TankConfig = TankConfigs.get_selected()
	rpc_id(1, "rpc_hello", player_name, cfg.key() if cfg != null else "")


func _on_failed(reason: String) -> void:
	_set_status(reason)
	if NetRole.is_client():
		leave.call_deferred()   # not inside the peer's own signal


func _set_status(text: String) -> void:
	status = text
	print("net: ", text)
	status_changed.emit(text)


# --- Raw packets ------------------------------------------------------------------------

func send_raw(bytes: PackedByteArray, to: int, channel: int) -> void:
	(multiplayer as SceneMultiplayer).send_bytes(bytes, to,
			MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, channel)
	_out_bytes += bytes.size()


func _on_packet(id: int, packet: PackedByteArray) -> void:
	_in_bytes += packet.size()
	if game == null or packet.is_empty():
		return
	var buf := StreamPeerBuffer.new()
	buf.data_array = packet
	var kind: int = buf.get_u8()
	if kind == PACKET_SNAPSHOT and NetRole.is_client() and id == 1:
		_snapshots += 1
		game.on_snapshot(buf)
	elif kind == PACKET_COMMAND and NetRole.is_host():
		game.on_command(id, buf)
	elif kind == PACKET_SQUADS and NetRole.is_client() and id == 1:
		game.on_squads(buf)


# --- RPCs (all reliable; the game logic is in NetGame) --------------------------------

@rpc("any_peer", "call_remote", "reliable", 2)
func rpc_hello(name_: String, config_key: String) -> void:
	if NetRole.is_host():
		rpc_id(multiplayer.get_remote_sender_id(), "rpc_welcome", map_path, bots)
		if game != null:
			game.on_client_hello(multiplayer.get_remote_sender_id(), name_, config_key)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_welcome(map: String, with_bots: bool) -> void:
	map_path = map
	bots = with_bots
	_load_map(map)


@rpc("any_peer", "call_remote", "reliable", 2)
func rpc_ready() -> void:
	if NetRole.is_host() and game != null:
		game.on_client_ready(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable", 2)
func rpc_spawn_tank(net_id: int, owner_id: int, team: int, data_path: String, xform: Transform3D) -> void:
	print_verbose("net: rpc_spawn_tank %d (game %s)" % [net_id, game != null])
	if game != null:
		game.on_spawn_tank(net_id, owner_id, team, data_path, xform)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_despawn_tank(net_id: int) -> void:
	if game != null:
		game.on_despawn_tank(net_id)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_shell(net_id: int, shell_index: int, from: Vector3, velocity: Vector3, flash: bool) -> void:
	if game != null:
		game.on_shell(net_id, shell_index, from, velocity, flash)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_shot_result(text: String, outcome: int) -> void:
	if game != null:
		game.on_shot_result(text, outcome)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_team_spot(point: Vector3) -> void:
	if game != null:
		game.on_team_spot(point)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_tree_felled(field: NodePath, index: int, direction: Vector3) -> void:
	if game != null:
		game.on_tree_felled(field, index, direction)


@rpc("any_peer", "call_remote", "reliable", 2)
func rpc_squad_order(kind: int, target: Vector3) -> void:
	if NetRole.is_host() and game != null:
		game.on_squad_order(multiplayer.get_remote_sender_id(), kind, target)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_squad_down(net_id: int, index: int, screamed: bool) -> void:
	if game != null:
		game.on_squad_down(net_id, index, screamed)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_squad_smoke(net_id: int, at: Vector3) -> void:
	if game != null:
		game.on_squad_smoke(net_id, at)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_squad_shot(net_id: int, kind: int, from: Vector3, velocity: Vector3) -> void:
	if game != null:
		game.on_squad_shot(net_id, kind, from, velocity)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_koth_state(state: Dictionary) -> void:
	if game != null:
		game.on_koth_state(state)


@rpc("authority", "call_remote", "reliable", 2)
func rpc_koth_bonus(team: int, points: float) -> void:
	if game != null:
		game.on_koth_bonus(team, points)


## Counts an RPC's payload for the statistics (approximate: arguments only).
func count_out(bytes: int) -> void:
	_out_bytes += bytes


# --- Statistics overlay (F3) ------------------------------------------------------------

func _make_stats_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_stats_label = Label.new()
	_stats_label.position = Vector2(12.0, 12.0)
	_stats_label.add_theme_font_size_override("font_size", 16)
	_stats_label.add_theme_constant_override("outline_size", 5)
	_stats_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_stats_label.visible = false
	layer.add_child(_stats_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("net_stats"):
		_stats_label.visible = not _stats_label.visible


func _process(delta: float) -> void:
	_stat_time += delta
	if _stat_time >= 1.0:
		in_bps = _in_bytes / _stat_time
		out_bps = _out_bytes / _stat_time
		snapshots_per_s = _snapshots / _stat_time
		_in_bytes = 0
		_out_bytes = 0
		_snapshots = 0
		_stat_time = 0.0
	if _stats_label.visible:
		_stats_label.text = _stats_text()


func _stats_text() -> String:
	var role: String = ["offline", "host", "client"][NetRole.role]
	var lines: PackedStringArray = ["NET %s  id %d  peers %d" % [role, my_id() if NetRole.is_online() else 0,
			multiplayer.get_peers().size() if NetRole.is_online() else 0]]
	lines.append("in %.1f kB/s  out %.1f kB/s" % [in_bps / 1024.0, out_bps / 1024.0])
	if NetRole.is_client():
		lines.append("snapshots %.0f/s  ping %d ms" % [snapshots_per_s, ping_ms()])
	if game != null:
		lines.append("tanks %d" % game.tanks.size())
	lines.append(status)
	return "\n".join(lines)


## Round-trip time to the host in ms (client), 0 if unknown.
func ping_ms() -> int:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or not NetRole.is_client():
		return 0
	var host_peer: ENetPacketPeer = peer.get_peer(1)
	return int(host_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if host_peer != null else 0
