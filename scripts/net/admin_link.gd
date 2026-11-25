class_name AdminLink
extends Node
## The dedicated server's admin socket (a child of DedicatedServer): TCP on 127.0.0.1 only
## (`--admin-port N`, default ADMIN_PORT; 0 = off), one JSON object per line each way.
## Meant for the admin panel running beside the server (tools/server/), which is what
## faces the network; nothing here checks who is asking, so it never listens elsewhere.
##
## Request:  {"id": any, "cmd": "<name>", ...args}
## Reply:    {"id": same, "ok": true, ...} or {"id": same, "ok": false, "error": "..."}
## Pushed to subscribers: {"ev": "status", ...status} every STATUS_S, {"ev": "log", "event": {...}}
## for every server log line.
##
## Commands: status, subscribe, unsubscribe, config_get, config_set {values: {...}},
## change_map {scenario}, end_match, close_vote, kick {peer, reason?}, say {text}, quit.
## Changed settings (team size, weather, scenarios, times) take effect from the next match.

const ADMIN_PORT: int = 24681
const BIND: String = "127.0.0.1"
const MAX_CLIENTS: int = 8
const MAX_LINE_BYTES: int = 65536
const STATUS_S: float = 1.0

var server: DedicatedServer
var port: int = ADMIN_PORT

var _tcp := TCPServer.new()
var _clients: Array[Client] = []
var _status_clock: float = 0.0
var _started_ms: int = 0
# worst frame/physics times since the last status push
var _worst_process_ms: float = 0.0
var _worst_physics_ms: float = 0.0
## The last HISTORY_S of [unix time, physics ms, players], one per STATUS_S, sent with a
## subscribe so the panel's chart is full at once.
var _history: Array = []
const HISTORY_S: float = 300.0


class Client:
	var peer: StreamPeerTCP
	var buffer: PackedByteArray = []
	var subscribed: bool = false

	func _init(p: StreamPeerTCP) -> void:
		peer = p

	func send(msg: Dictionary) -> void:
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.put_data((JSON.stringify(msg) + "\n").to_utf8_buffer())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_ms = Time.get_ticks_msec()
	if port <= 0:
		set_process(false)
		return
	var err: Error = _tcp.listen(port, BIND)
	if err != OK:
		push_warning("admin: can't listen on %s:%d (%s)" % [BIND, port, error_string(err)])
		set_process(false)
		return
	print("admin: listening on %s:%d" % [BIND, port])


func _exit_tree() -> void:
	for c: Client in _clients:
		c.peer.disconnect_from_host()
	_tcp.stop()


func _process(delta: float) -> void:
	_worst_process_ms = maxf(_worst_process_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_worst_physics_ms = maxf(_worst_physics_ms,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	while _tcp.is_connection_available():
		var p: StreamPeerTCP = _tcp.take_connection()
		if _clients.size() >= MAX_CLIENTS:
			p.disconnect_from_host()
		else:
			_clients.append(Client.new(p))
	for c: Client in _clients.duplicate():
		c.peer.poll()
		var st: int = c.peer.get_status()
		if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
			_clients.erase(c)
			continue
		if st != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var n: int = c.peer.get_available_bytes()
		if n > 0:
			var got: Array = c.peer.get_partial_data(n)
			if int(got[0]) == OK:
				c.buffer.append_array(got[1] as PackedByteArray)
		_read_lines(c)
	_status_clock += delta
	if _status_clock >= STATUS_S:
		_status_clock = 0.0
		_history.append([Time.get_unix_time_from_system(),
				snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
				NetSession.instance.multiplayer.get_peers().size()])
		while _history.size() > int(HISTORY_S / STATUS_S):
			_history.pop_front()
		var subs: Array[Client] = _clients.filter(func(c: Client) -> bool: return c.subscribed)
		if not subs.is_empty():
			var msg: Dictionary = status()
			msg["ev"] = "status"
			for c: Client in subs:
				c.send(msg)
		_worst_process_ms = 0.0
		_worst_physics_ms = 0.0


func _read_lines(c: Client) -> void:
	while true:
		var at: int = c.buffer.find(10)   # "\n"
		if at < 0:
			if c.buffer.size() > MAX_LINE_BYTES:
				c.send({"ok": false, "error": "line too long"})
				c.peer.disconnect_from_host()
				_clients.erase(c)
			return
		var line: String = c.buffer.slice(0, at).get_string_from_utf8().strip_edges()
		c.buffer = c.buffer.slice(at + 1)
		if line == "":
			continue
		var json := JSON.new()   # JSON.parse_string would print an engine error for bad input
		var req: Variant = json.data if json.parse(line) == OK else null
		if not req is Dictionary:
			c.send({"ok": false, "error": "not a JSON object"})
			continue
		var reply: Dictionary = _handle(c, req as Dictionary)
		if (req as Dictionary).has("id"):
			reply["id"] = (req as Dictionary)["id"]
		c.send(reply)


## Server log lines go to every subscriber too (DedicatedServer.log_event).
func push_log(event: Dictionary) -> void:
	for c: Client in _clients:
		if c.subscribed:
			c.send({"ev": "log", "event": event})


# --- Commands ------------------------------------------------------------------------

func _handle(c: Client, req: Dictionary) -> Dictionary:
	var cmd: String = str(req.get("cmd", ""))
	match cmd:
		"status":
			return _ok(status())
		"subscribe":
			c.subscribed = true
			var first: Dictionary = status()
			first["history"] = _history   # [unix time, physics ms, players]
			return _ok(first)
		"unsubscribe":
			c.subscribed = false
			return _ok({})
		"config_get":
			return _ok(_config())
		"config_set":
			var values: Variant = req.get("values", {})
			if not values is Dictionary:
				return _err("values must be an object")
			var refused: Dictionary = server.set_config(values as Dictionary)
			if not refused.is_empty():
				return {"ok": false, "error": "refused", "refused": refused}
			return _ok(_config())
		"change_map":
			var path: String = ServerConfig.scenario_path(str(req.get("scenario", "")))
			if path == "":
				return _err("unknown scenario")
			server.admin_change_map(path)
			return _ok({"scenario": path.get_file().get_basename()})
		"end_match":
			if not server.admin_end_match():
				return _err("no match running")
			return _ok({})
		"close_vote":
			if not server.admin_close_vote():
				return _err("no vote or result showing")
			return _ok({})
		"kick":
			var peer: int = int(req.get("peer", 0))
			if not server.admin_kick(peer, str(req.get("reason", ""))):
				return _err("no such player")
			return _ok({})
		"say":
			var text: String = str(req.get("text", "")).strip_edges()
			if text == "":
				return _err("empty text")
			server.admin_say(text)
			return _ok({})
		"quit":
			server.admin_quit()
			return _ok({})
		"":
			return _err("no cmd")
	return _err("unknown cmd '%s'" % cmd)


func _ok(fields: Dictionary) -> Dictionary:
	fields["ok"] = true
	return fields


func _err(text: String) -> Dictionary:
	return {"ok": false, "error": text}


func _config() -> Dictionary:
	var all: Array = []
	for p: String in MainMenu.find_maps():
		all.append({"name": p.get_file().get_basename(), "label": MainMenu.scenario_label(p)})
	return {"config": ServerConfig.to_dict(server.file_settings()), "path": server.config_path,
			"scenarios_available": all, "weathers": [Weather.RANDOM] + Array(Weather.PRESETS),
			"max_team_size": MatchSettings.MAX_TEAM_SIZE,
			"note": "changes take effect from the next match"}


# --- Status --------------------------------------------------------------------------

## What the panel shows: the match, the players, the vote and how the machine keeps up.
func status() -> Dictionary:
	var s: Dictionary = server.status()
	s["perf"] = {
		"fps": Engine.get_frames_per_second(),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"worst_process_ms": snappedf(_worst_process_ms, 0.01),
		"worst_physics_ms": snappedf(_worst_physics_ms, 0.01),
		"physics_hz": Engine.physics_ticks_per_second,
		"memory_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"net_in_bps": roundi(NetSession.instance.in_bps),
		"net_out_bps": roundi(NetSession.instance.out_bps),
	}
	s["uptime_s"] = (Time.get_ticks_msec() - _started_ms) / 1000
	s["admin_clients"] = _clients.size()
	return s
