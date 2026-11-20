extends SceneTree
## Frame-time measurement of a real match (PRESTANDA_PLAN.md). Plays a scenario in a
## 1920x1080 window with this machine's graphics settings and measures phases after a
## warm-up: frame, process, physics per tick (first physics step of a frame to its
## process step, divided by the ticks), render CPU/GPU, draw calls; with "vsync" also
## fps and the share of frames over 18 ms.
##   godot --path . --script res://tools/perf/perf_match.gd -- <weather> [scenario] [size=N] [vsync]
## e.g. `-- clear size=20 vsync` (default scenario vidingsjo_thunder_orange). Uncapped by
## default (vsync and the fps cap off), so the times are the real cost.
## Phases (PHASES): names starting with "wait" are not reported; a phase named in OFF
## switches _physics_process off for those classes while it lasts (the marginal cost),
## "scan/2" doubles the bots' look-round interval, "sqscan/4" quadruples the squads', and
## "sun"/"away" turn the commander's view to or from the sun. Needs a window, not --headless.

const WARMUP_S: float = 14.0
const PHASES: Array = [["t14", 8.0], ["wait1", 32.0], ["t54", 10.0], ["wait2", 26.0], ["t90", 10.0]]
const OFF: Dictionary = {"-shells": ["Shell"], "-bots": ["BotController"], "-squads": ["Squad"], "-looks": ["TankLooks"], "-trees": ["TreeField", "PropBreak"], "-mode": ["ThunderRoadMode", "ThunderRoadBots"], "-tanks": ["Tank"], "-all": ["BotController", "Squad", "TankLooks", "TreeField", "PropBreak", "ThunderRoadMode", "ThunderRoadBots", "Tank", "Shell", "Mine", "Wreck"]}
var _off: Array[Node] = []

var _t: float = 0.0
var _phase: int = -1
var _phase_t: float = 0.0
var _samples: Dictionary = {}
var _views: PlayerViews
var _sun: DirectionalLight3D
var _weather: String = "clear"
var _vsync: bool = false

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_weather = args[0]
	var scene_path: String = "res://scenes/scenarios/vidingsjo_thunder_orange.tscn"
	_vsync = args.has("vsync")
	if args.size() > 1 and args[1] != "vsync" and not args[1].begins_with("size="):
		scene_path = "res://scenes/scenarios/%s.tscn" % args[1]
	Weather.set_current(Weather.load_preset(_weather))
	MatchSettings.load_settings()
	for a: String in args:
		if a.begins_with("size="):
			MatchSettings.team_size = int(a.substr(5))
	print("team size ", MatchSettings.team_size)
	get_root().size = Vector2i(1920, 1080)
	var root: Node = (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)
	current_scene = root
	RenderingServer.viewport_set_measure_render_time(get_root().get_viewport_rid(), true)
	process_frame.connect(_tick)
	physics_frame.connect(_on_physics)

var _phys_start: int = -1
var _phys_us: float = 0.0
var _ticks: int = 0

func _on_physics() -> void:
	if _phys_start < 0:
		_phys_start = Time.get_ticks_usec()
	_ticks += 1

func _tick() -> void:
	var dt: float = get_root().get_process_delta_time()
	_t += dt
	_phys_us = float(Time.get_ticks_usec() - _phys_start) if _phys_start >= 0 else 0.0
	var ticks: int = _ticks
	_phys_start = -1
	_ticks = 0
	if not _vsync and (Engine.max_fps != 0 or DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED):
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if _views == null:
		var found: Array[Node] = current_scene.find_children("*", "PlayerViews", true, false)
		if not found.is_empty():
			_views = found[0]
		var lights: Array[Node] = current_scene.find_children("*", "DirectionalLight3D", true, false)
		if not lights.is_empty():
			_sun = lights[0]
	if _t < WARMUP_S:
		return
	if _phase < 0 or _phase_t >= float(PHASES[_phase][1]):
		_phase += 1
		_phase_t = 0.0
		if _phase >= PHASES.size():
			_report()
			quit()
			return
		_switch(String(PHASES[_phase][0]))
	_phase_t += dt
	if _phase_t < 0.5:
		return   # let the view settle
	var vp: RID = get_root().get_viewport_rid()
	var name: String = PHASES[_phase][0]
	if not _samples.has(name):
		_samples[name] = []
	(_samples[name] as Array).append([dt * 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			_phys_us / 1000.0 / maxf(ticks, 1) if ticks > 0 else -1.0,
			RenderingServer.viewport_get_measured_render_time_cpu(vp),
			RenderingServer.viewport_get_measured_render_time_gpu(vp),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])

var _prof_from: int = 0

func _switch(phase: String) -> void:
	_prof_from = Engine.get_physics_frames()
	for n: Node in _off:
		if is_instance_valid(n):
			n.set_physics_process(true)
	_off.clear()
	for n: Node in current_scene.find_children("*", "BotController", true, false):
		pass
	_scan_scale(2.0 if phase == "scan/2" else 1.0)
	_sq_scale(4.0 if phase == "sqscan/4" else 1.0)
	var classes: Array = OFF.get(phase, [])
	if classes.is_empty():
		return
	for n: Node in current_scene.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		while sc != null:
			if classes.has(String(sc.get_global_name())):
				if n.is_physics_processing():
					n.set_physics_process(false)
					_off.append(n)
				break
			sc = sc.get_base_script()


func _aim(phase: String) -> void:
	if _views == null or _sun == null:
		return
	var cam: CommanderCamera = _views.commander_camera
	var to_sun: Vector3 = _sun.global_basis.z   # light travels along -z
	var yaw: float = atan2(-to_sun.x, -to_sun.z)
	var pitch: float = asin(clampf(to_sun.y, -1.0, 1.0))
	if phase == "sun":
		cam.set_target_view(yaw + PI, pitch)
	elif phase == "away":
		cam.set_target_view(yaw, 0.0)
	print("phase %s  sun elevation %.0f°" % [phase, rad_to_deg(asin(clampf(-_sun.global_basis.z.y, -1, 1)))])

func _report() -> void:
	print("RESULT weather=%s  (ms: avg / p95)" % _weather)
	print("%-6s %-14s %-14s %-14s %-14s %-14s %6s" % ["phase", "frame", "process", "physics/tick", "render cpu", "gpu", "draws"])
	for name: String in _samples:
		if name.begins_with("wait"):
			continue
		var rows: Array = _samples[name]
		var cols: Array[String] = []
		for c: int in 5:
			var v: Array[float] = []
			for r: Array in rows:
				if float(r[c]) >= 0.0:
					v.append(float(r[c]))
			v.sort()
			var avg: float = 0.0
			for x: float in v:
				avg += x
			avg /= maxf(v.size(), 1)
			cols.append("%5.1f / %5.1f" % [avg, v[int(v.size() * 0.95)]])
			if c == 0:
				var slow: int = 0
				for x: float in v:
					if x > 18.0:
						slow += 1
				print("  %s: %.0f fps, %.0f %% of frames over 18 ms" % [name, 1000.0 / avg, 100.0 * slow / maxf(v.size(), 1)])
		print("%-6s %-14s %-14s %-14s %-14s %-14s %6d" % [name, cols[0], cols[1], cols[2], cols[3], cols[4], int(rows[rows.size() / 2][5])])


var _scan_scaled: float = 1.0

func _scan_scale(k: float) -> void:
	if is_equal_approx(k, _scan_scaled):
		return
	var done: Dictionary = {}
	for n: Node in current_scene.find_children("*", "", true, false):
		if n is BotController:
			var bd: BotData = (n as BotController).bot_data
			if bd != null and not done.has(bd):
				done[bd] = true
				bd.scan_interval_s *= k / _scan_scaled
	_scan_scaled = k


var _sq_scaled: float = 1.0

func _sq_scale(k: float) -> void:
	if is_equal_approx(k, _sq_scaled):
		return
	var done: Dictionary = {}
	for n: Node in current_scene.find_children("*", "", true, false):
		if n is Squad:
			var d: SquadData = (n as Squad).data
			if d != null and not done.has(d):
				done[d] = true
				d.scan_interval_s *= k / _sq_scaled
	_sq_scaled = k
