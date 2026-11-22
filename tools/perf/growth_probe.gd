extends SceneTree
## What grows during a match (PRESTANDA_PLAN.md): plays a scenario and every SAMPLE_S prints
## the physics time per tick, engine monitors (nodes, objects, active bodies, contact pairs)
## and node counts per script class / engine class, then which counts grew the most.
##   godot --headless --fixed-fps 30 --path . --script res://tools/perf/growth_probe.gd -- [scenario] [size=N] [secs=N] [ab|ab=<kind>] [classes]
## Always prints SPLIT at the end: per tick before the scripts (engine sync and query flush),
## the scripts, the physics step, and the frame's _process.
## `ab` / `ab=<kind>`: an A/B switch (_set_ab: "soldiers" = soldier_look_rounds, "contacts" = the tanks'
## contact_monitor) off and on every AB_S (A = off, B = on); the tick time of each is summed
## (with --fixed-fps 30: one tick a frame, as in a slow windowed match).
## `classes`: _physics_process time per class (CLASS_BANDS), each run in its own priority band.
## (default vidingsjo_thunder_red, 20 a side, 240 s). Headless: no draw calls, the tick only.

const SAMPLE_S: float = 20.0
const AB_S: float = 10.0

var _ab: bool = false
var _ab_on: bool = true
var _ab_next: float = AB_S
var _ab_us: Array[int] = [0, 0]
var _ab_ticks: Array[int] = [0, 0]
var _bunch_default: Dictionary = {}
## What `ab` switches: "soldiers" (soldier_look_rounds 1 <-> default), "threads" (ScanBatch
## looks on threads <-> all on the main thread), "contacts" (the
## tanks' contact_monitor off <-> on). The split (SPLIT line) is summed per side too.
var _ab_kind: String = "soldiers"
var _ab_split: Array[int] = [0, 0]
var _ab_frame: Array[int] = [0, 0]   # the frame's _process (the previous frame's, summed per side)

var _t: float = 0.0
var _next: float = SAMPLE_S
var _end_s: float = 240.0
var _phys_us: int = 0
var _phys_start: int = -1
var _ticks: int = 0
var _first: Dictionary = {}
## Where a tick's time goes (run with --fixed-fps 30, one tick a frame): before the scripts
## (the engine's sync and query flush: area/body callbacks), the scripts' _physics_process
## (to a last-priority node), the physics step after them, and the frame's _process.
var _split_us: Array[int] = [0, 0, 0, 0]
var _split_ticks: int = 0
## `classes`: _physics_process time per class, by running each class in its own physics
## priority band with a stamp after it (changes the order scripts run in; a profile, not play).
const CLASS_BANDS: Array[String] = ["Tank", "BotController", "Squad", "ThunderRoadMode", "ThunderRoadBots", "TankLooks"]
var _by_class: bool = false
var _band_stamps: Array[int] = []
var _band_us: Array[int] = []
var _band_ticks: int = 0
var _proc_end: int = -1
var _scripts_end: int = -1
var _proc_start: int = -1


## Stamps the time when every other node has run (lowest priority = last).
class Stamp extends Node:
	var on_physics: Callable
	var on_process: Callable
	func _ready() -> void:
		process_physics_priority = 2147483647
		process_priority = 2147483647
	func _physics_process(_d: float) -> void:
		on_physics.call()
	func _process(_d: float) -> void:
		on_process.call()
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
		elif a == "classes":
			_by_class = true
		elif a == "ab":
			_ab = true
		elif a.begins_with("ab="):
			_ab = true
			_ab_kind = a.substr(3)
		else:
			scene_path = "res://scenes/scenarios/%s.tscn" % a
	print("growth probe: ", scene_path, " size ", MatchSettings.team_size)
	var root: Node = (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)
	current_scene = root
	process_frame.connect(_frame)
	var stamp := Stamp.new()
	stamp.on_physics = func() -> void: _scripts_end = Time.get_ticks_usec()
	stamp.on_process = func() -> void: _proc_end = Time.get_ticks_usec()
	get_root().add_child.call_deferred(stamp)
	if _by_class:
		_band_stamps.resize(CLASS_BANDS.size() + 1)
		_band_us.resize(CLASS_BANDS.size() + 1)
		_band_us.fill(0)
		for i: int in CLASS_BANDS.size() + 1:
			var band := Stamp.new()
			var at: int = i
			band.on_physics = func() -> void: _band_stamps[at] = Time.get_ticks_usec()
			band.on_process = func() -> void: pass
			band.ready.connect(func() -> void: band.process_physics_priority = 100 * at + 50)
			get_root().add_child.call_deferred(band)
	physics_frame.connect(_on_physics)


var _ticks_this_frame: int = 0

func _on_physics() -> void:
	if _phys_start < 0:
		_phys_start = Time.get_ticks_usec()
		if _proc_end >= 0 and _proc_start >= 0 and _scripts_end >= 0 and _t > 20.0:
			_split_us[3] += _proc_end - _proc_start
			_split_us[0] += _phys_start - _proc_end
			if _ab:
				_ab_split[int(_ab_on)] += _phys_start - _proc_end
			_split_ticks += 1
	_ticks += 1
	_ticks_this_frame += 1


## The A/B switch: soldier looks spread over rounds (BotData/SquadData.soldier_look_rounds) or not.
func _set_bunching(on: bool) -> void:
	var stack: Array[Node] = [current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var res: Resource = null
		if n is BotController:
			res = (n as BotController).bot_data
		elif n is Squad:
			res = (n as Squad).data
		if res == null:
			continue
		if not _bunch_default.has(res):
			_bunch_default[res] = int(res.get("soldier_look_rounds"))
		res.set("soldier_look_rounds", int(_bunch_default[res]) if on else 1)


func _set_ab(on: bool) -> void:
	if _ab_kind == "threads":
		ScanBatch.threaded = on
	elif _ab_kind == "contacts":
		for t: Node in get_nodes_in_group("tanks"):
			(t as RigidBody3D).contact_monitor = on
	else:
		_set_bunching(on)


func _frame() -> void:
	if _phys_start >= 0:
		var now: int = Time.get_ticks_usec()
		var us: int = now - _phys_start
		if _scripts_end >= _phys_start and _t > 20.0:
			_split_us[1] += _scripts_end - _phys_start
			_split_us[2] += now - _scripts_end
		var prev_proc: int = _proc_end - _proc_start if _proc_start >= 0 and _proc_end > _proc_start else 0
		_proc_start = now
		if _by_class and _t > 20.0 and _band_stamps[0] >= _phys_start:
			var prev: int = _phys_start
			for i: int in _band_stamps.size():
				_band_us[i] += _band_stamps[i] - prev
				prev = _band_stamps[i]
			_band_ticks += 1
		_phys_us += us
		if _ab and _t > 20.0:   # after the start's spawning
			_ab_us[int(_ab_on)] += us
			_ab_frame[int(_ab_on)] += prev_proc
			_ab_ticks[int(_ab_on)] += _ticks_this_frame
		_phys_start = -1
	_ticks_this_frame = 0
	_t += get_root().get_process_delta_time()
	if _ab and _t >= _ab_next:
		_ab_next += AB_S
		_ab_on = not _ab_on
		_set_ab(_ab_on)
	if _t < _next:
		return
	_next += SAMPLE_S
	if _by_class:
		_assign_bands()
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


func _assign_bands() -> void:
	var stack: Array[Node] = [current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children(true))
		var sc: Script = n.get_script()
		while sc != null:
			var at: int = CLASS_BANDS.find(String(sc.get_global_name()))
			if at >= 0:
				n.process_physics_priority = 100 * (at + 1)
				break
			sc = sc.get_base_script()


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
	if _ab:
		print("A/B: off %.2f ms per tick (%d ticks), on %.2f ms per tick (%d ticks)" % [
			_ab_us[0] / 1000.0 / maxf(_ab_ticks[0], 1), _ab_ticks[0],
			_ab_us[1] / 1000.0 / maxf(_ab_ticks[1], 1), _ab_ticks[1]])
		print("A/B frame _process: off %.2f ms, on %.2f" % [
			_ab_frame[0] / 1000.0 / maxf(_ab_ticks[0], 1), _ab_frame[1] / 1000.0 / maxf(_ab_ticks[1], 1)])
		print("A/B before scripts: off %.2f ms, on %.2f" % [
			_ab_split[0] / 1000.0 / maxf(_ab_ticks[0], 1), _ab_split[1] / 1000.0 / maxf(_ab_ticks[1], 1)])
	var n: float = maxf(_split_ticks, 1) * 1000.0
	print("SPLIT per tick (after 20 s): before scripts %.2f ms, scripts %.2f, physics step %.2f; frame _process %.2f" % [
		_split_us[0] / n, _split_us[1] / n, _split_us[2] / n, _split_us[3] / n])
	if _by_class:
		var m: float = maxf(_band_ticks, 1) * 1000.0
		var line: String = "CLASSES per tick: other %.2f ms" % (_band_us[0] / m)
		for i: int in CLASS_BANDS.size():
			line += ", %s %.2f" % [CLASS_BANDS[i], _band_us[i + 1] / m]
		print(line)
	var rows: Array = []
	for key: String in _last.keys():
		var grew: int = int(_last[key]) - int(_first.get(key, 0))
		if grew != 0:
			rows.append([grew, key])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return absi(a[0]) > absi(b[0]))
	print("GROWTH from the first sample to the last (count: first -> last):")
	for r: Array in rows.slice(0, 40):
		print("  %+6d  %-32s %d -> %d" % [r[0], r[1], int(_first.get(r[1], 0)), int(_last[r[1]])])
