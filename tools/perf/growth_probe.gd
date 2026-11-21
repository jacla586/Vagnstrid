extends SceneTree
## What grows during a match (PRESTANDA_PLAN.md): plays a scenario and every SAMPLE_S prints
## the physics time per tick, engine monitors (nodes, objects, active bodies, contact pairs)
## and node counts per script class / engine class, then which counts grew the most.
##   godot --headless --path . --script res://tools/perf/growth_probe.gd -- [scenario] [size=N] [secs=N]
## (default vidingsjo_thunder_red, 20 a side, 240 s). Headless: no draw calls, the tick only.

const SAMPLE_S: float = 20.0

var _t: float = 0.0
var _next: float = SAMPLE_S
var _end_s: float = 240.0
var _phys_us: int = 0
var _phys_start: int = -1
var _ticks: int = 0
var _first: Dictionary = {}
var _last: Dictionary = {}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = "res://scenes/scenarios/vidingsjo_thunder_red.tscn"
	MatchSettings.load_settings()
	MatchSettings.team_size = 20
	for a: String in args:
		if a.begins_with("size="):
			MatchSettings.team_size = int(a.substr(5))
		elif a.begins_with("secs="):
			_end_s = float(a.substr(5))
		else:
			scene_path = "res://scenes/scenarios/%s.tscn" % a
	print("growth probe: ", scene_path, " size ", MatchSettings.team_size)
	var root: Node = (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)
	current_scene = root
	process_frame.connect(_frame)
	physics_frame.connect(_on_physics)


func _on_physics() -> void:
	if _phys_start < 0:
		_phys_start = Time.get_ticks_usec()
	_ticks += 1


func _frame() -> void:
	if _phys_start >= 0:
		_phys_us += Time.get_ticks_usec() - _phys_start
		_phys_start = -1
	_t += get_root().get_process_delta_time()
	if _t < _next:
		return
	_next += SAMPLE_S
	var counts: Dictionary = _count()
	var tick_ms: float = float(_phys_us) / 1000.0 / maxf(float(_ticks), 1.0)
	_phys_us = 0
	_ticks = 0
	print("t=%3d s  tick %5.1f ms  nodes %d  objects %d  orphans %d  active bodies %d  pairs %d  islands %d" % [
		int(_t), tick_ms,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)])
	if _first.is_empty():
		_first = counts
	_last = counts
	if _t >= _end_s:
		_report()
		quit()


## Nodes per script class name (else engine class), plus a few groups.
func _count() -> Dictionary:
	var out: Dictionary = {}
	var stack: Array[Node] = [get_root()]
	var total: int = 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		total += 1
		var key: String = n.get_class()
		var sc: Script = n.get_script()
		if sc != null and String(sc.get_global_name()) != "":
			key = String(sc.get_global_name())
		elif sc != null:
			key += "+" + sc.resource_path.get_file()
		out[key] = int(out.get(key, 0)) + 1
		stack.append_array(n.get_children(true))   # internal children too
	print("  walked %d nodes" % total)
	for g: String in ["tanks", "squads", "wrecks", "tree_fields"]:
		out["group:" + g] = get_nodes_in_group(g).size()
	return out


func _report() -> void:
	var rows: Array = []
	for key: String in _last.keys():
		var grew: int = int(_last[key]) - int(_first.get(key, 0))
		if grew != 0:
			rows.append([grew, key])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return absi(a[0]) > absi(b[0]))
	print("GROWTH from the first sample to the last (count: first -> last):")
	for r: Array in rows.slice(0, 40):
		print("  %+6d  %-32s %d -> %d" % [r[0], r[1], int(_first.get(r[1], 0)), int(_last[r[1]])])
