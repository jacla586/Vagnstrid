extends SceneTree
## Renders pictures of tanks from the garage presets (or every config given) from a few
## angles, for looking at models without starting the game. Needs a window:
##   godot --path . --script res://tools/render_tank_models.gd -- <out dir> [preset ...]
## Writes <out dir>/<preset>_<view>.png and <out dir>/lineup.png (all side by side).

const VIEWS: Dictionary = {
	"front34": Vector3(-1.0, 0.55, -1.15),
	"rear34": Vector3(1.1, 0.6, 1.0),
	"side": Vector3(-1.0, 0.12, 0.0),
	"top": Vector3(0.05, 1.0, 0.25),
}
const SIZE: Vector2i = Vector2i(900, 600)

var _vp: SubViewport
var _camera: Camera3D
var _root3d: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://tank_renders"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var names: PackedStringArray = args.slice(1)
	if names.is_empty():
		for f: String in DirAccess.get_files_at("res://data/configs"):
			if f.ends_with(".tres"):
				names.append(f.get_basename())
	_setup()
	var lineup: Array[Node3D] = []
	var x: float = 0.0
	for n: String in names:
		var cfg: TankConfig = load("res://data/configs/%s.tres" % n)
		var data: TankData = TankBuilder.build(cfg)
		var tank: Node3D = _make(data)
		for view: String in VIEWS:
			await _shoot(tank, data, VIEWS[view], "%s/%s_%s.png" % [out_dir, n, view])
		tank.position = Vector3(x, data.hull_size.y * 0.5, 0.0)
		x += data.hull_size.x + 2.5
		lineup.append(tank)
	# Lineup: all of them side by side, three-quarter view.
	var mid: float = x * 0.5 - 1.25
	_camera.position = Vector3(mid - x * 0.35, x * 0.32, -x * 0.75)
	_camera.look_at(Vector3(mid, 1.0, 0.0))
	await _frames()
	_vp.get_texture().get_image().save_png("%s/lineup.png" % out_dir)
	print("rendered %d tanks to %s" % [names.size(), ProjectSettings.globalize_path(out_dir)])
	quit()


func _setup() -> void:
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.7, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = true
	_vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.45, 0.33)
	plane.material = gm
	ground.mesh = plane
	_vp.add_child(ground)
	_root3d = Node3D.new()
	_vp.add_child(_root3d)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_vp.add_child(_camera)


## A tank's Visual (sized from its data, no physics), standing on the ground.
func _make(data: TankData) -> Node3D:
	var tank: Tank = (load("res://scenes/tank/tank.tscn") as PackedScene).instantiate()
	tank.data = data
	tank.apply_geometry()
	var visual: Node3D = tank.get_node("Visual")
	visual.get_node("Turret/Cupola/CommanderHitbox").free()
	tank.remove_child(visual)
	tank.free()
	_root3d.add_child(visual)
	visual.position = Vector3(0.0, data.hull_size.y * 0.5, 0.0)
	return visual


func _shoot(tank: Node3D, data: TankData, dir: Vector3, path: String) -> void:
	var others: Array[Node] = _root3d.get_children()
	for o: Node in others:
		(o as Node3D).visible = o == tank
	var size: float = maxf(data.hull_size.z + data.gun_length_m * 0.6, 4.0)
	var target: Vector3 = tank.global_position + Vector3(0.0, data.hull_size.y * 0.3, -0.4)
	_camera.position = target + dir.normalized() * size * 1.55
	_camera.look_at(target, Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.FORWARD)
	await _frames()
	_vp.get_texture().get_image().save_png(path)
	for o: Node in others:
		(o as Node3D).visible = true


func _frames() -> void:
	for i: int in 4:
		await process_frame
