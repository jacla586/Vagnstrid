extends SceneTree
## Before/after pictures for graphics work: renders fixed camera views of a map
## (tools/render_views.json) in one or more weather presets, and measures each view.
##   godot --path . --disable-vsync --script res://tools/render_views.gd -- <map> <label> [weather,...]
##   e.g. -- vidingsjo before clear,dusk
## Needs a real window (not --headless). Loads res://scenes/maps/<map>.tscn with its
## PlayerRig (WeatherView dresses the map), removes the bots, hides the HUD and looks
## through its own camera. Writes renders/views/<label>/<weather>_<view>.png and
## renders/views/<label>/results.txt (frame, render CPU/GPU ms, draw calls, triangles).
## Compare two labels with tools/compare_views.py.

const VIEWS_PATH: String = "res://tools/render_views.json"
const OUT_DIR: String = "res://renders/views"
const WINDOW_SIZE: Vector2i = Vector2i(1920, 1080)
## Frames after loading a map (terrain, tree chunks, WeatherView, shader compiles).
const LOAD_FRAMES: int = 240
## Frames after moving the camera before measuring (terrain LOD, shadows, streaming).
const SETTLE_FRAMES: int = 90
## Frames measured per view.
const MEASURE_FRAMES: int = 120
const RAY_TOP_M: float = 1000.0

var _map: String = "vidingsjo"
var _label: String = "current"
var _weathers: PackedStringArray = ["clear"]
var _views: Array = []
var _camera: Camera3D
var _weather_index: int = 0
var _view_index: int = -1
var _frame: int = 0
var _wall_us: int = 0
var _sum_wall: float = 0.0
var _sum_cpu: float = 0.0
var _sum_gpu: float = 0.0
var _count: int = 0
var _lines: PackedStringArray = []
var _loading: bool = true


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1:
		_map = args[0]
	if args.size() >= 2:
		_label = args[1]
	if args.size() >= 3:
		_weathers = args[2].split(",", false)
	var all: Variant = JSON.parse_string(FileAccess.get_file_as_string(VIEWS_PATH))
	if not (all is Dictionary) or not (all as Dictionary).has(_map):
		push_error("no views for map '%s' in %s" % [_map, VIEWS_PATH])
		quit(1)
		return
	_views = (all as Dictionary)[_map]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir()))
	DisplayServer.window_set_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	_lines.append("map %s  label %s  window %dx%d  %s" % [_map, _label, WINDOW_SIZE.x, WINDOW_SIZE.y,
			Time.get_datetime_string_from_system()])
	_lines.append("%-24s %8s %8s %8s %7s %9s" % ["view", "frame ms", "cpu ms", "gpu ms", "draws", "tris (k)"])
	_load_weather()


func _out_dir() -> String:
	return OUT_DIR + "/" + _label


func _load_weather() -> void:
	Weather.set_current(Weather.load_preset(_weathers[_weather_index]))
	change_scene_to_file("res://scenes/maps/%s.tscn" % _map)
	_loading = true
	_frame = 0
	_view_index = -1


func _process(_delta: float) -> bool:
	_frame += 1
	if _loading:
		if _frame == 2:
			_strip_scene()
		if _frame < LOAD_FRAMES:
			return false
		_loading = false
		_next_view()
		return false
	var vp: RID = root.get_viewport_rid()
	var now: int = Time.get_ticks_usec()
	if _frame > SETTLE_FRAMES:
		_sum_wall += (now - _wall_us) / 1000.0
		_sum_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		_sum_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		_count += 1
	_wall_us = now
	if _count < MEASURE_FRAMES:
		return false
	_finish_view()
	return _next_view()


## The bots go (they would wander into the pictures), the HUD hides, our camera looks.
func _strip_scene() -> void:
	var scene: Node = current_scene
	var enemies: Node = scene.get_node_or_null("Enemies")
	if enemies != null:
		enemies.queue_free()
	for layer: Node in scene.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_camera = Camera3D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.far = 4000.0
	scene.add_child(_camera)
	_camera.current = true
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)


## Moves the camera to the next view; after the last one, the next weather or the end.
func _next_view() -> bool:
	_view_index += 1
	if _view_index >= _views.size():
		_weather_index += 1
		if _weather_index >= _weathers.size():
			_write_results()
			return true
		_load_weather()
		return false
	var v: Dictionary = _views[_view_index]
	var at: Array = v["at"]
	var target: Array = v["look_at"]
	var eye := Vector3(float(at[0]), 0.0, float(at[1]))
	eye.y = _ground(eye) + float(v.get("height_m", 2.0))
	var look := Vector3(float(target[0]), 0.0, float(target[1]))
	look.y = _ground(look) + float(v.get("look_height_m", 0.0))
	_camera.fov = float(v.get("fov", 60.0))
	_camera.global_transform = Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
	_frame = 0
	_count = 0
	_sum_wall = 0.0
	_sum_cpu = 0.0
	_sum_gpu = 0.0
	_wall_us = Time.get_ticks_usec()
	return false


func _finish_view() -> void:
	var v: Dictionary = _views[_view_index]
	var weather: String = _weathers[_weather_index]
	var file: String = "%s_%s.png" % [weather, String(v["name"])]
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(_out_dir() + "/" + file))
	var line: String = "%-24s %8.2f %8.2f %8.2f %7d %9.0f" % ["%s_%s" % [weather, v["name"]],
			_sum_wall / _count, _sum_cpu / _count, _sum_gpu / _count,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0]
	_lines.append(line)
	print(line)


func _write_results() -> void:
	var f := FileAccess.open(_out_dir() + "/results.txt", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("wrote %s" % ProjectSettings.globalize_path(_out_dir()))


## Ground height under (x, z): terrain, houses, bridges (world layer).
func _ground(p: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = root.world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, RAY_TOP_M, p.z),
			Vector3(p.x, -RAY_TOP_M, p.z), 1)
	var hit: Dictionary = space.intersect_ray(query)
	return float(hit["position"].y) if not hit.is_empty() else 0.0
