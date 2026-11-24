class_name DedicatedServer
extends Node
## The dedicated server (`--dedicated`, SERVER_PLAN.md): hosts with no player of its own,
## bots fill the teams (ServerData.team_size), and between matches the players vote
## freely among every scenario (most votes wins, a tie is drawn by lot; no votes: the next
## in the list after the current one). Nobody connected when a match ends: it waits on the
## finished match until someone comes, then loads the next one. Every match, vote, join
## and leave goes as one JSON line to <log dir>/server_log.jsonl (`--log-dir`, default
## user://). A child of NetSession, so it outlives map changes.
##
## Settings: data/server/server.tres are the defaults, `server.cfg` beside the log (or
## `--config <file>`) overrides them (ServerConfig); it is read again when a match ends and
## before every map load, so edits apply from the next match. `AdminLink` (child, TCP on
## 127.0.0.1, `--admin-port N`) lets the admin panel watch and steer the server.

const DATA_PATH: String = "res://data/server/server.tres"
const TICK_S: float = 0.5

enum Phase { PLAYING, RESULT, VOTE, IDLE }

## The settings in force (defaults + server.cfg + test overrides).
var data: ServerData
var log_dir: String = "user://"
## The settings file; "" = server.cfg in log_dir.
var config_path: String = ""
var admin: AdminLink
var scenarios: PackedStringArray = []
var phase: Phase = Phase.PLAYING
var current: String = ""

var _clock: float = 0.0
var _phase_left: float = 0.0
var _match_time: float = 0.0
var _votes: Dictionary = {}       # peer -> scenario index
var _tick: float = 0.0
var _defaults: ServerData
var _test_max_match_s: float = 0.0


func start(first: String) -> void:
	_defaults = load(DATA_PATH) as ServerData
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--max-match-s")   # testing: end matches sooner
	if at >= 0 and at + 1 < args.size():
		_test_max_match_s = float(args[at + 1])
	at = args.find("--config")
	if at >= 0 and at + 1 < args.size():
		config_path = args[at + 1]
	if config_path == "":
		config_path = log_dir.path_join("server.cfg")
	if not FileAccess.file_exists(config_path):
		ServerConfig.write(config_path, _defaults)   # every key, ready to edit
	_apply_settings()
	admin = AdminLink.new()
	admin.name = "AdminLink"
	admin.server = self
	at = args.find("--admin-port")
	if at >= 0 and at + 1 < args.size():
		admin.port = int(args[at + 1])
	add_child(admin)
	if first == "" or not ResourceLoader.exists(first):
		first = scenarios[0] if not scenarios.is_empty() else NetSession.DEFAULT_MAP
	var net: NetSession = NetSession.instance
	net.multiplayer.peer_connected.connect(func(id: int) -> void:
		log_event({"ev": "join", "peer": id, "players": _peer_count()})
		if phase == Phase.VOTE:
			_send_vote_open(id))
	Weather.resolve()
	print("dedicated server: %d scenarios, first %s, log %s, settings %s" % [scenarios.size(),
			first, ProjectSettings.globalize_path(log_dir.path_join("server_log.jsonl")),
			ProjectSettings.globalize_path(config_path)])
	if net.host(first, true) == OK:
		_begin_match(first)


func _process(delta: float) -> void:
	_clock += delta
	_tick += delta
	if phase == Phase.PLAYING:
		_match_time += delta
	if _tick < TICK_S:
		return
	var dt: float = _tick
	_tick = 0.0
	match phase:
		Phase.PLAYING:
			if _mode_over():
				_end_match("mode")
			elif _match_time >= data.max_match_s:
				_end_match("timeout")
		Phase.RESULT:
			_phase_left -= dt
			if _phase_left <= 0.0:
				if _peer_count() == 0:
					phase = Phase.IDLE
					print("dedicated server: nobody here, waiting")
				else:
					_open_vote()
		Phase.VOTE:
			_phase_left -= dt
			if _peer_count() == 0:
				phase = Phase.IDLE
			elif _phase_left <= 0.0:
				_close_vote()
		Phase.IDLE:
			if _peer_count() > 0:
				_load(_next_in_list())


# --- Match ---------------------------------------------------------------------------

func _begin_match(path: String) -> void:
	current = path
	phase = Phase.PLAYING
	_match_time = 0.0
	log_event({"ev": "match_start", "scenario": path.get_file().get_basename(),
			"weather": Weather.current().resource_path.get_file().get_basename(),
			"players": _peer_count(), "names": _names()})


func _mode_over() -> bool:
	if KothMode.instance != null and is_instance_valid(KothMode.instance):
		return KothMode.instance.is_over()
	if ThunderRoadMode.instance != null and is_instance_valid(ThunderRoadMode.instance):
		return ThunderRoadMode.instance.is_over()
	if FreeFight.instance != null and is_instance_valid(FreeFight.instance):
		return FreeFight.instance.is_over()
	return false


## `reason`: "mode" (its own end), "timeout" (max_match_s) or "admin".
func _end_match(reason: String) -> void:
	var stats: Array = []
	var winner: int = -2
	if KothMode.instance != null and is_instance_valid(KothMode.instance):
		stats = KothMode.instance.get_stats()
		winner = KothMode.instance.get_winner()
	elif ThunderRoadMode.instance != null and is_instance_valid(ThunderRoadMode.instance):
		stats = ThunderRoadMode.instance.get_stats()
		winner = ThunderRoadMode.instance.get_winner()
	elif FreeFight.instance != null and is_instance_valid(FreeFight.instance):
		stats = FreeFight.instance.get_stats()
	var humans: Array = []
	var names: Array = _names()
	for row: Variant in stats:
		if row is Array and (row as Array).size() > 0 and names.has(str(row[0])):
			humans.append(row)
	log_event({"ev": "match_end", "scenario": current.get_file().get_basename(),
			"length_s": roundi(_match_time), "timed_out": reason == "timeout", "reason": reason,
			"winner": winner, "players": _peer_count(), "humans": humans})
	phase = Phase.RESULT
	_apply_settings()   # the vote and the next match see edits made meanwhile
	_phase_left = data.result_s


func _load(path: String) -> void:
	_votes.clear()
	_apply_settings()
	Weather.resolve()
	NetSession.instance.change_map(path)
	_begin_match(path)


func _next_in_list() -> String:
	var i: int = scenarios.find(current)
	return scenarios[(i + 1) % scenarios.size()] if not scenarios.is_empty() else current


# --- Vote ----------------------------------------------------------------------------

func _labels() -> Array:
	var out: Array = []
	for path: String in scenarios:
		out.append(MainMenu.scenario_label(path))
	return out


func _counts() -> Array:
	var counts: Array = []
	counts.resize(scenarios.size())
	counts.fill(0)
	for peer: Variant in _votes:
		var i: int = int(_votes[peer])
		if i >= 0 and i < counts.size():
			counts[i] = int(counts[i]) + 1
	return counts


func _open_vote() -> void:
	phase = Phase.VOTE
	_phase_left = data.vote_s
	_votes.clear()
	for peer: int in NetSession.instance.multiplayer.get_peers():
		_send_vote_open(peer)


func _send_vote_open(peer: int) -> void:
	NetSession.instance.rpc_id(peer, "rpc_vote_open", _labels(), _phase_left, _counts(),
			scenarios.find(current))


func _send_counts() -> void:
	NetSession.instance.rpc("rpc_vote_state", _counts())


## NetSession, before it forgets the player.
func on_peer_left(id: int) -> void:
	_votes.erase(id)
	log_event({"ev": "leave", "peer": id, "name": _name_of(id), "players": _peer_count()})
	if phase == Phase.VOTE:
		_send_counts()


## NetSession: a player's vote (they may change it until the vote closes).
func on_vote(peer: int, index: int) -> void:
	if phase != Phase.VOTE or index < 0 or index >= scenarios.size():
		return
	_votes[peer] = index
	_send_counts()


func _close_vote() -> void:
	var counts: Array = _counts()
	var best: int = 0
	for c: Variant in counts:
		best = maxi(best, int(c))
	var path: String
	var tie: bool = false
	if best == 0:
		path = _next_in_list()
	else:
		var top: Array[int] = []
		for i: int in counts.size():
			if int(counts[i]) == best:
				top.append(i)
		tie = top.size() > 1
		path = scenarios[top[randi() % top.size()]]
	var by_name: Dictionary = {}
	for i: int in counts.size():
		if int(counts[i]) > 0:
			by_name[scenarios[i].get_file().get_basename()] = counts[i]
	log_event({"ev": "vote", "votes": by_name, "voters": _votes.size(), "players": _peer_count(),
			"winner": path.get_file().get_basename(), "tie": tie, "no_votes": best == 0})
	NetSession.instance.rpc("rpc_vote_close", MainMenu.scenario_label(path))
	_load(path)


# --- Settings ------------------------------------------------------------------------

## Reads server.cfg over the defaults and puts team size and weather where the modes
## read them (MatchSettings; they only read them when a match starts or fills teams, so
## this runs between matches).
func _apply_settings() -> void:
	data = ServerConfig.read(config_path, _defaults)
	if _test_max_match_s > 0.0:
		data.max_match_s = _test_max_match_s
		data.result_s = minf(data.result_s, 3.0)
		data.vote_s = minf(data.vote_s, 6.0)
	scenarios = data.scenarios if not data.scenarios.is_empty() else MainMenu.find_maps()
	scenarios.sort()
	MatchSettings.team_size = data.team_size
	MatchSettings.weather = data.weather


## The settings the file holds now (what the next match gets).
func file_settings() -> ServerData:
	return ServerConfig.read(config_path, _defaults)


## AdminLink: changes `values` in server.cfg (from the next match). Returns refused keys
## with why; nothing is written if any is refused.
func set_config(values: Dictionary) -> Dictionary:
	var next: ServerData = file_settings()
	var refused: Dictionary = ServerConfig.apply(next, values)
	if not refused.is_empty():
		return refused
	var err: Error = ServerConfig.write(config_path, next)
	if err != OK:
		return {"file": "can't write %s (%s)" % [config_path, error_string(err)]}
	log_event({"ev": "admin_config", "values": values})
	return {}


# --- Admin commands (AdminLink) -----------------------------------------------------

## Loads `path` now; a running match is logged as ended by the admin.
func admin_change_map(path: String) -> void:
	if phase == Phase.PLAYING:
		_end_match("admin")
	log_event({"ev": "admin_change_map", "scenario": path.get_file().get_basename()})
	if phase == Phase.VOTE:
		NetSession.instance.rpc("rpc_vote_close", MainMenu.scenario_label(path))
	_load(path)


## Ends the running match: result, then the vote, as if it had ended by itself.
func admin_end_match() -> bool:
	if phase != Phase.PLAYING:
		return false
	_end_match("admin")
	return true


## Cuts the result short (the vote opens) or closes the vote now.
func admin_close_vote() -> bool:
	if phase == Phase.VOTE:
		_close_vote()
		return true
	if phase == Phase.RESULT:
		_phase_left = 0.0
		return true
	return false


func admin_kick(peer: int, reason: String) -> bool:
	var net: NetSession = NetSession.instance
	if not net.multiplayer.get_peers().has(peer):
		return false
	log_event({"ev": "kick", "peer": peer, "name": _name_of(peer), "reason": reason})
	net.rpc_id(peer, "rpc_notice", "Kicked by the server" + (": " + reason if reason != "" else ""), 6.0)
	get_tree().create_timer(0.5).timeout.connect(func() -> void:   # let the notice go first
		if net.multiplayer.get_peers().has(peer):
			(net.multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer))
	return true


## A line on every player's screen (MatchNotice).
func admin_say(text: String) -> void:
	text = text.left(200)
	log_event({"ev": "say", "text": text})
	NetSession.instance.rpc("rpc_notice", "[Server] " + text, 8.0)


## Stops the server (systemd's Restart=always brings it back: a restart).
func admin_quit() -> void:
	log_event({"ev": "admin_quit", "players": _peer_count()})
	get_tree().create_timer(0.3).timeout.connect(func() -> void: get_tree().quit())


## AdminLink's status: phase, match, mode state, players and vote.
func status() -> Dictionary:
	var left: float = maxf(0.0, _phase_left) if phase != Phase.PLAYING \
			else maxf(0.0, data.max_match_s - _match_time)
	var s: Dictionary = {
		"phase": (Phase.keys()[phase] as String).to_lower(),
		"scenario": current.get_file().get_basename(),
		"label": MainMenu.scenario_label(current) if current != "" else "",
		"match_s": roundi(_match_time),
		"phase_left_s": roundi(left),
		"max_match_s": data.max_match_s,
		"weather": Weather.current().resource_path.get_file().get_basename(),
		"team_size": data.team_size,
		"port": NetSession.instance.port,
		"players": _players(),
		"mode": _mode_status(),
	}
	var bots: Array = [0, 0]
	var game: NetGame = NetSession.instance.game
	if game != null and is_instance_valid(game):
		for row: Array in game.roster:
			if int(row[2]) == DeployScreen.Kind.BOT and int(row[0]) >= 0 and int(row[0]) < 2:
				bots[int(row[0])] = int(bots[int(row[0])]) + 1
	s["bots"] = bots
	if phase == Phase.VOTE:
		var counts: Array = _counts()
		var rows: Array = []
		for i: int in scenarios.size():
			rows.append({"name": scenarios[i].get_file().get_basename(), "votes": counts[i]})
		s["vote"] = rows
	return s


func _players() -> Array:
	var net: NetSession = NetSession.instance
	var by_peer: Dictionary = {}
	var game: NetGame = net.game
	if game != null and is_instance_valid(game):
		for row: Array in game.roster:
			if int(row[4]) > 0:
				by_peer[int(row[4])] = row
	var enet := net.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var out: Array = []
	for peer: int in net.multiplayer.get_peers():
		var row: Array = by_peer.get(peer, [])
		var ping: int = -1
		if enet != null:
			var p: ENetPacketPeer = enet.get_peer(peer)
			if p != null:
				ping = roundi(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
		out.append({"peer": peer, "name": _name_of(peer),
				"team": int(row[0]) if not row.is_empty() else -1,
				"tank": str(row[3]) if not row.is_empty() else "",
				"choosing": not row.is_empty() and int(row[2]) == DeployScreen.Kind.CHOOSING,
				"ping_ms": ping})
	return out


func _mode_status() -> Dictionary:
	if KothMode.instance != null and is_instance_valid(KothMode.instance):
		var k: KothMode = KothMode.instance
		return {"kind": "koth", "score": [roundi(k.get_score(0)), roundi(k.get_score(1))],
				"zone": k.get_zone_number(), "zones": k.get_zone_count(),
				"columns": ["name", "team", "ko", "lost", "points", "assists"], "stats": k.get_stats()}
	if ThunderRoadMode.instance != null and is_instance_valid(ThunderRoadMode.instance):
		var t: ThunderRoadMode = ThunderRoadMode.instance
		return {"kind": "thunder", "round": t.get_round(), "attackers": t.get_attack_team(),
				"next_checkpoint": t.get_next_checkpoint(), "checkpoints": t.get_checkpoint_count(),
				"time_left_s": roundi(t.get_time_left()), "lives": t.get_lives(),
				"overtime": t.is_overtime(), "paused": t.is_paused(),
				"columns": ["name", "team", "ko", "lost", "assists", "points"], "stats": t.get_stats()}
	if FreeFight.instance != null and is_instance_valid(FreeFight.instance):
		var f: FreeFight = FreeFight.instance
		return {"kind": "free", "wave": f.get_wave_number(), "alive": f.get_alive(),
				"columns": ["name", "team", "ko", "lost", "assists"], "stats": f.get_stats()}
	return {"kind": "none"}


# --- Helpers -------------------------------------------------------------------------

func _peer_count() -> int:
	return NetSession.instance.multiplayer.get_peers().size()


func _name_of(peer: int) -> String:
	var row: Array = NetSession.instance.known_peers.get(peer, [])
	return str(row[0]) if not row.is_empty() else ""


func _names() -> Array:
	var out: Array = []
	for peer: Variant in NetSession.instance.known_peers:
		out.append(_name_of(int(peer)))
	return out


func log_event(event: Dictionary) -> void:
	event["t"] = Time.get_datetime_string_from_system(true) + "Z"
	var path: String = log_dir.path_join("server_log.jsonl")
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		push_warning("dedicated server: can't write %s" % path)
		return
	f.seek_end()
	f.store_line(JSON.stringify(event))
	print("server: ", JSON.stringify(event))
	if admin != null:
		admin.push_log(event)
