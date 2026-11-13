extends SceneTree
## Scratch: runs a ThunderRoad scenario with bots only, fast, and logs the mode's events.
var _mode: ThunderRoadMode
var _t: float = 0.0
var _last_print: float = 0.0
var _hooked: bool = false
var _shots: Dictionary = {}   # type -> {outcome: n}
var _seen: Dictionary = {}

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene: String = args[0] if args.size() > 0 else "road_to_science_thunder"
	change_scene_to_file("res://scenes/scenarios/%s.tscn" % scene)
	physics_frame.connect(_tick)

func _tick() -> void:
	_t += 1.0 / 30.0
	if _mode == null:
		_mode = ThunderRoadMode.instance
		return
	if not _hooked:
		_hooked = true
		# no player: drop the map's rig so only bots fight
		for n: Node in current_scene.find_children("*", "", true, false):
			if n is PlayerController:
				var tank := n.get_parent() as Tank
				if tank != null:
					tank.queue_free()
		_mode.checkpoint_taken.connect(func(i: int) -> void: print("[%5.0f] CP %d taken" % [_t, i]))
		_mode.pause_started.connect(func(i: int) -> void: print("[%5.0f] PAUSE after %d" % [_t, i]))
		_mode.pause_ended.connect(func(i: int) -> void: print("[%5.0f] OPEN %d time %.0f" % [_t, i, _mode.get_time_left()]))
		_mode.points_scored.connect(func(tank: Tank, p: float, k: String) -> void:
			print("[%5.0f] +%d %s %s(t%d)" % [_t, p, k, tank.get_type_name(), tank.team]))
		_mode.round_over.connect(func(n: int, r: Dictionary) -> void:
			print("[%5.0f] ROUND %d OVER %s" % [_t, n, r])
			_dump()
			if n >= 2:
				quit())
	for node: Node in get_nodes_in_group("tanks"):
		var tk := node as Tank
		if tk != null and not _seen.has(tk):
			_seen[tk] = true
			tk.shot_landed.connect(func(r: HitResult) -> void:
				var key: String = "%s t%d" % [tk.get_type_name(), tk.team]
				var d: Dictionary = _shots.get(key, {})
				var o: String = "none" if r == null else ("bullet" if r.bullet else HitResult.Outcome.keys()[r.outcome] + ("+mod" if not r.modules.is_empty() else ""))
				d[o] = int(d.get(o, 0)) + 1
				_shots[key] = d)
	if _t - _last_print > 60.0:
		_last_print = _t
		var fired: int = 0
		var outside: int = 0
		for node: Node in get_nodes_in_group("tanks"):
			var tank := node as Tank
			if tank != null and tank.fire_blocked and not tank.is_knocked_out():
				fired += 1
			if tank != null and _mode.outside_time(tank) > 0.0:
				outside += 1
		print("[%5.0f] next %d paused %s time %.0f lives %d blocked %d outside %d" % [_t, _mode.get_next_checkpoint(),
				_mode.is_paused(), _mode.get_time_left(), _mode.get_lives(), fired, outside])
	if _t > 2400.0:
		_dump()
		quit()

func _dump() -> void:
	for k: String in _shots:
		print("  shots ", k, " ", _shots[k])
	for row: Array in _mode.get_stats():
		print("  ", row)
