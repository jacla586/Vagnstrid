extends SceneTree
## The main menu's background picture, made in the game itself: a tank drives across a
## field on a map, a squad runs beside it and an HE round lands next to the soldiers.
##   godot --path . --disable-vsync --fixed-fps 60 --script res://tools/render_menu_background.gd -- [map] [weather] [look]
##   look: friend (olive, UN blue) or enemy (camouflage); default enemy.
## Needs a window. Writes renders/menu/<weather>_<look>_<ms>.jpg at a few moments after
## the burst; copy the best one to assets/ui/menu_background.jpg.
## Times count in frames (--fixed-fps 60), as saving a picture takes longer than a frame.

const OUT_DIR: String = "res://renders/menu"
const WINDOW_SIZE: Vector2i = Vector2i(1920, 1080)
const TANK_CONFIG: String = "res://data/configs/2_t34.tres"
const SQUAD_DATA: String = "res://data/squads/rifle_squad.tres"
## Where the tank is at the burst (x, z on the map) and the way it drives (degrees, 0 = -z).
const SCENE_AT: Vector2 = Vector2(440.0, 590.0)
const HEADING_DEG: float = 200.0
const TANK_SPEED_MPS: float = 7.0
const SOLDIER_SPEED_MPS: float = 5.5
## Seconds of driving before the burst (dust trails build up).
const LEAD_IN_S: float = 3.0
## Soldiers beside the tank (side metres, metres ahead of the tank's centre).
const SOLDIERS: Array[Vector2] = [Vector2(5.5, 1.0), Vector2(7.0, -2.5), Vector2(4.8, -5.0), Vector2(8.2, 3.2)]
## The burst, relative to the tank (side, ahead), and its size (calibre / 75).
const BURST_AT: Vector2 = Vector2(9.5, -4.0)
const BURST_SCALE: float = 1.7
## Camera relative to the tank (side, ahead, height) and the point it looks at
## (side, ahead, height); the action sits right of the middle for the menu on the left.
const CAMERA_AT: Vector3 = Vector3(9.0, 15.0, 2.0)
const LOOK_AT: Vector3 = Vector3(7.0, -3.0, 2.8)
const FOV_DEG: float = 54.0
const SHOTS_MS: Array[int] = [60, 120, 200, 300, 450]
const LOAD_FRAMES: int = 240

var _map: String = "vidingsjo"
var _weather: String = "clear"
var _friend: bool = false
var _frame: int = 0
var _camera: Camera3D
var _tank: Tank
var _soldiers: Array[Node3D] = []
var _clock_s: float = 0.0
var _burst_frame: int = -1
var _shot: int = 0
var _forward: Vector3
var _side: Vector3


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1:
		_map = args[0]
	if args.size() >= 2:
		_weather = args[1]
	if args.size() >= 3:
		_friend = args[2] == "friend"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DisplayServer.window_set_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	Weather.set_current(Weather.load_preset(_weather))
	change_scene_to_file("res://scenes/maps/%s.tscn" % _map)
	var h: float = deg_to_rad(HEADING_DEG)
	_forward = Vector3(sin(h), 0.0, -cos(h))
	_side = _forward.cross(Vector3.UP)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var scene: Node = current_scene
		var enemies: Node = scene.get_node_or_null("Enemies")
		if enemies != null:
			enemies.queue_free()
		for layer: Node in scene.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
		_camera = Camera3D.new()
		_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		scene.add_child(_camera)
		_camera.current = true
		_camera.fov = FOV_DEG
		EffectFx.prewarm(scene)
	if _frame == LOAD_FRAMES:
		_make_actors()
	if _frame <= LOAD_FRAMES:
		return false
	_clock_s += 1.0 / 60.0
	_place_actors()
	if _burst_frame < 0 and _clock_s >= LEAD_IN_S:
		var fx: EffectsSetData = load("res://data/effects/effects.tres")
		var at: Vector3 = _ground_point(_tank_centre() + _side * BURST_AT.x + _forward * BURST_AT.y)
		EffectFx.play(fx.impact_ground, current_scene, at, Vector3.UP, BURST_SCALE)
		EffectFx.play(fx.explosion, current_scene, at, Vector3.UP, BURST_SCALE)
		EffectFx.play(_dirt_fountain(), current_scene, at, Vector3.UP, 1.0)
		_burst_frame = _frame
	if _burst_frame < 0:
		return false
	var age_ms: int = (_frame - _burst_frame) * 1000 / 60
	if _shot < SHOTS_MS.size() and age_ms >= SHOTS_MS[_shot]:
		var file: String = "%s/%s_%s_%04d.jpg" % [OUT_DIR, _weather,
				"friend" if _friend else "enemy", SHOTS_MS[_shot]]
		root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path(file), 0.92)
		print("saved ", file)
		_shot += 1
	return _shot >= SHOTS_MS.size()


func _make_actors() -> void:
	TeamLook.viewer_team = 0
	_tank = (load("res://scenes/tank/tank.tscn") as PackedScene).instantiate()
	_tank.config = load(TANK_CONFIG)
	_tank.team = 0 if _friend else 1
	current_scene.add_child(_tank)
	_tank.set_net_puppet(false)
	var squad: SquadData = load(SQUAD_DATA)
	var anims: AnimationLibrary = squad.model_animations
	for i: int in SOLDIERS.size():
		var body: Node3D = squad.model.instantiate()
		body.scale = Vector3.ONE * squad.model_scale
		current_scene.add_child(body)
		_paint_soldier(body, squad)
		var player: AnimationPlayer = body.find_children("*", "AnimationPlayer", true, false)[0]
		player.add_animation_library(&"s", anims)
		player.play(&"s/sprint")
		player.seek(0.17 * i, true)
		player.speed_scale = 0.95 + 0.07 * i
		_soldiers.append(body)
	_place_actors()


## A heavier throw of earth than the game's own burst, for the picture only: clods and
## a dark spray thrown high.
func _dirt_fountain() -> EffectData:
	var clods := BurstData.new()
	clods.amount = 340
	clods.lifetime_s = 2.2
	clods.spread_deg = 32.0
	clods.speed_min_mps = 7.0
	clods.speed_max_mps = 21.0
	clods.emission_radius_m = 0.8
	clods.size_start_m = 0.16
	clods.size_end_m = 0.13
	clods.size_randomness = 0.7
	clods.color_start = Color(0.06, 0.045, 0.03)
	clods.color_end = Color(0.06, 0.045, 0.03)
	clods.soft = false
	var spray := BurstData.new()
	spray.amount = 40
	spray.lifetime_s = 2.0
	spray.spread_deg = 18.0
	spray.speed_min_mps = 9.0
	spray.speed_max_mps = 17.0
	spray.gravity = Vector3(0.0, -4.0, 0.0)
	spray.damping = 1.5
	spray.emission_radius_m = 0.6
	spray.size_start_m = 0.8
	spray.size_end_m = 2.6
	spray.color_start = Color(0.3, 0.24, 0.17, 0.9)
	spray.color_end = Color(0.42, 0.36, 0.28, 0.0)
	var e := EffectData.new()
	e.bursts = [clods, spray]
	return e


## Uniform shades and, for friends, the UN-blue helmet; enemies wear camouflage (as Squad).
func _paint_soldier(body: Node3D, squad: SquadData) -> void:
	var shades: Array[Color] = [squad.uniform_color.lightened(0.12), squad.uniform_color.darkened(0.15)]
	var camo: Material = TeamLook.camo(squad.camo_pattern_per_m * squad.model_scale)
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for s: int in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(s)
			var mat_name: String = mat.resource_name if mat != null else ""
			var k: int = squad.uniform_materials.find(mat_name)
			if k >= 0 and mat is StandardMaterial3D:
				if _friend:
					var paint := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					paint.albedo_color = shades[mini(k, shades.size() - 1)]
					mi.set_surface_override_material(s, paint)
				else:
					mi.set_surface_override_material(s, camo)
			elif _friend and squad.friend_blue_materials.has(mat_name):
				mi.set_surface_override_material(s, TeamLook.blue())


## Where the tank's centre is now (on the map plane; it reaches SCENE_AT at the burst).
func _tank_centre() -> Vector3:
	return Vector3(SCENE_AT.x, 0.0, SCENE_AT.y) + _forward * TANK_SPEED_MPS * (_clock_s - LEAD_IN_S)


func _place_actors() -> void:
	var c: Vector3 = _tank_centre()
	var data: TankData = _tank.data
	var half_l: float = data.hull_size.z * 0.4
	var half_w: float = data.hull_size.x * 0.4
	var front: Vector3 = _ground_point(c + _forward * half_l)
	var rear_l: Vector3 = _ground_point(c - _forward * half_l - _side * half_w)
	var rear_r: Vector3 = _ground_point(c - _forward * half_l + _side * half_w)
	var rear: Vector3 = (rear_l + rear_r) * 0.5
	var z_axis: Vector3 = (rear - front).normalized()   # the tank's back (forward is -z)
	var x_axis: Vector3 = (rear_r - rear_l).normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	x_axis = y_axis.cross(z_axis).normalized()
	var origin: Vector3 = (front + rear) * 0.5 + y_axis * data.hull_size.y * 0.5
	var xform := Transform3D(Basis(x_axis, y_axis, z_axis), origin)
	_tank.net_set_pose(xform, deg_to_rad(-8.0), deg_to_rad(3.0), 1.0, 0.0, 0.0,
			-z_axis * TANK_SPEED_MPS)
	for i: int in _soldiers.size():
		var off: Vector2 = SOLDIERS[i]
		var run: float = (SOLDIER_SPEED_MPS - TANK_SPEED_MPS) * (_clock_s - LEAD_IN_S)
		var p: Vector3 = _ground_point(c + _side * off.x + _forward * (off.y + run))
		var body: Node3D = _soldiers[i]
		body.global_position = p
		# The model faces +z; turn it to run along the tank's way, a little out.
		var yaw: float = atan2(_forward.x, _forward.z) + deg_to_rad(4.0 * (i - 1.5))
		body.rotation = Vector3(0.0, yaw, 0.0)
	var eye: Vector3 = c + _side * CAMERA_AT.x + _forward * CAMERA_AT.y
	eye.y = _ground_point(eye).y + CAMERA_AT.z
	var look: Vector3 = c + _side * LOOK_AT.x + _forward * LOOK_AT.y
	look.y = _ground_point(look).y + LOOK_AT.z
	_camera.global_transform = Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


func _ground_point(p: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 1000.0, p.z), Vector3(p.x, -1000.0, p.z), 1)
	if _tank != null:
		query.exclude = [_tank.get_rid()]
	var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
	return Vector3(p.x, float(hit["position"].y) if not hit.is_empty() else 0.0, p.z)
