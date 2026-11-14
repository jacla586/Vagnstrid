class_name DedicatedServer
extends Node
## The dedicated server (`--dedicated`, SERVER_PLAN.md): hosts with no player of its own,
## bots fill the teams (ServerData.team_size), and between matches the players vote
## freely among every scenario (most votes wins, a tie is drawn by lot; no votes: the next
## in the list after the current one). Nobody connected when a match ends: it waits on the
## finished match until someone comes, then loads the next one. Every match, vote, join
## and leave goes as one JSON line to <log dir>/server_log.jsonl (`--log-dir`, default
## user://). A child of NetSession, so it outlives map changes.

const DATA_PATH: String = "res://data/server/server.tres"
const TICK_S: float = 0.5

enum Phase { PLAYING, RESULT, VOTE, IDLE }

var data: ServerData
var log_dir: String = "user://"
var scenarios: PackedStringArray = []
var phase: Phase = Phase.PLAYING
var current: String = ""

var _clock: float = 0.0
var _phase_left: float = 0.0
var _match_time: float = 0.0
var _votes: Dictionary = {}       # peer -> scenario index
var _tick: float = 0.0


func start(first: String) -> void:
	data = load(DATA_PATH) as ServerData
	scenarios = data.scenarios if not data.scenarios.is_empty() else MainMenu.find_maps()
	scenarios.sort()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var at: int = args.find("--max-match-s")   # testing: end matches sooner
	if at >= 0 and at + 1 < args.size():
		data = data.duplicate() as ServerData
		data.max_match_s = float(args[at + 1])
		data.result_s = minf(data.result_s, 3.0)
		data.vote_s = minf(data.vote_s, 6.0)
	MatchSettings.team_size = data.team_size
	MatchSettings.weather = data.weather
	if first == "" or not ResourceLoader.exists(first):
		first = scenarios[0] if not scenarios.is_empty() else NetSession.DEFAULT_MAP
	var net: NetSession = NetSession.instance
	net.multiplayer.peer_connected.connect(func(id: int) -> void:
		log_event({"ev": "join", "peer": id, "players": _peer_count()})
		if phase == Phase.VOTE:
			_send_vote_open(id))
	Weather.resolve()
	print("dedicated server: %d scenarios, first %s, log %s" % [scenarios.size(), first,
			ProjectSettings.globalize_path(log_dir.path_join("server_log.jsonl"))])
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
			if _mode_over() or _match_time >= data.max_match_s:
				_end_match(_match_time >= data.max_match_s and not _mode_over())
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


func _end_match(timed_out: bool) -> void:
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
			"length_s": roundi(_match_time), "timed_out": timed_out, "winner": winner,
			"players": _peer_count(), "humans": humans})
	phase = Phase.RESULT
	_phase_left = data.result_s


func _load(path: String) -> void:
	_votes.clear()
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
