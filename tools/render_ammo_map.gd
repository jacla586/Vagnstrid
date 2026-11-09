extends SceneTree
## Maps where a gun round sets off each tank's ammunition, from several directions.
## Fires a grid of test rounds (straight lines, no drop) at each garage preset through
## the game's own rules (Armour.resolve, TankDamage.apply_hit on a fresh damage state)
## and draws where each round landed, seen from the shooter: red = ammo explodes
## (knock-out), orange = penetrates without reaching the ammo, grey = stopped,
## blue = ricochet. A last panel shows the ammo box (red) through the tank. Needs a window:
##   godot --path . --script res://tools/render_ammo_map.gd -- <out dir> [shell] [preset ...]
## shell: a file in data/shells without .tres (default ap_75l, the Pz IV's AP).
## Writes <out dir>/<preset>.png (six panels) per preset.

const TANK_SCENE: String = "res://scenes/tank/tank.tscn"
const PANEL: Vector2i = Vector2i(800, 560)
const GRID_STEP_M: float = 0.08
const GRID_HALF_M: float = 5.0
## Shots come this much from above (degrees), as from a slightly higher shooter.
const DROP_DEG: float = 3.0
## Shooter's direction round the tank: name -> degrees from straight ahead (to the
## tank's left side positive).
const DIRECTIONS: Array = [["Front", 0.0], ["Front 30°", 30.0], ["Front 60°", 60.0],
		["Side", 90.0], ["Rear 45°", 135.0], ["Rear", 180.0]]
const COLORS: Dictionary = {
	"ammo": Color(1.0, 0.1, 0.1), "pen": Color(1.0, 0.65, 0.15),
	"stop": Color(0.35, 0.35, 0.35), "ric": Color(0.35, 0.6, 1.0),
}

var _camera: Camera3D
var _label: Label
var _dots: MultiMeshInstance3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://ammo_maps"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var shell_name: String = args[1] if args.size() > 1 else "ap_75l"
	var shell: ShellData = load("res://data/shells/%s.tres" % shell_name)
	var names: PackedStringArray = args.slice(2)
	if names.is_empty():
		for f: String in DirAccess.get_files_at("res://data/configs"):
			if f.ends_with(".tres"):
				names.append(f.get_basename())
	_setup()
	for n: String in names:
		await _map_tank(n, shell, "%s/%s.png" % [out_dir, n])
	print("ammo maps in ", ProjectSettings.globalize_path(out_dir))
	quit()


func _setup() -> void:
	root.size = PANEL
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.85, 0.87, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(_camera)
	_dots = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * GRID_STEP_M * 0.9
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true   # only first hits are drawn: show them over the mantlet
	quad.material = mat
	mm.mesh = quad
	_dots.multimesh = mm
	root.add_child(_dots)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_label = Label.new()
	_label.position = Vector2(14, 8)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color.BLACK)
	layer.add_child(_label)


func _map_tank(preset: String, shell: ShellData, path: String) -> void:
	var cfg: TankConfig = load("res://data/configs/%s.tres" % preset)
	var data: TankData = TankBuilder.build(cfg)
	var tank: Tank = (load(TANK_SCENE) as PackedScene).instantiate()
	tank.data = data
	tank.position = Vector3(0.0, 2.0, 0.0)
	root.add_child(tank)
	tank.freeze = true
	for i: int in 4:
		await physics_frame
	var ammo: ModuleData = null
	for m: ModuleData in data.layout.modules:
		if m.id == &"ammo":
			ammo = m
	var panels: Array[Image] = []
	var space: PhysicsDirectSpaceState3D = tank.get_world_3d().direct_space_state
	var centre: Vector3 = tank.global_position + Vector3(0.0, data.hull_size.y * 0.25, 0.0)
	for entry: Array in DIRECTIONS:
		var a: float = deg_to_rad(entry[1])
		var drop: float = deg_to_rad(DROP_DEG)
		# From the shooter towards the tank (the tank's forward is -Z).
		var from_dir := Vector3(-sin(a) * cos(drop), sin(drop), -cos(a) * cos(drop))
		var dir: Vector3 = -from_dir
		var counts: Dictionary = _fire_grid(tank, space, shell, centre, dir)
		_camera.size = maxf(data.hull_size.z + 1.5, 6.5)
		_camera.position = centre + from_dir * 30.0
		_camera.look_at(centre, Vector3.UP)
		_label.text = "%s – %s from %s\n%s\nammo %d%% of hits" % [
				cfg.display_name, shell.display_name, entry[0],
				"red ammo  orange pen  grey stopped  blue bounce",
				roundi(100.0 * counts["ammo"] / maxf(counts["hits"], 1.0))]
		await _frames()
		panels.append(root.get_texture().get_image())
	# X-ray: the ammo box through the tank, from the side and above.
	_dots.multimesh.instance_count = 0
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = ammo.size
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1, 0, 0, 0.75)
	red.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	red.no_depth_test = true
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = red
	box.mesh = bm
	(tank.get("_turret") as Node3D).add_child(box)
	box.position = ammo.center
	var xray_from := Vector3(-0.8, 0.9, 0.5).normalized()
	_camera.size = maxf(data.hull_size.z + 1.5, 6.5)
	_camera.position = centre + xray_from * 30.0
	_camera.look_at(centre, Vector3.UP)
	_label.text = "%s – ammo box (red), turret rear\nturret straight ahead; it turns with the turret" \
			% cfg.display_name
	await _frames()
	panels.append(root.get_texture().get_image())
	_save_sheet(panels, path)
	tank.queue_free()
	await _frames()


## Fires the grid along `dir` and fills the dots. Returns counts: hits, ammo.
func _fire_grid(tank: Tank, space: PhysicsDirectSpaceState3D, shell: ShellData,
		centre: Vector3, dir: Vector3) -> Dictionary:
	var right: Vector3 = dir.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(dir).normalized()
	var dmg := TankDamage.new(tank.data)
	var turret: Node3D = tank.get("_turret")
	var turret_shapes: Array = tank.get("_turret_shapes")
	var turret_shape: Node = tank.get("_turret_shape")
	var speed: float = shell.muzzle_velocity_mps * 0.9
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var counts: Dictionary = {"hits": 0, "ammo": 0}
	var n: int = int(GRID_HALF_M / GRID_STEP_M)
	for iu: int in range(-n, n + 1):
		for iv: int in range(-n, n + 1):
			var start: Vector3 = centre - dir * 30.0 + right * (iu * GRID_STEP_M) + up * (iv * GRID_STEP_M)
			var q := PhysicsRayQueryParameters3D.create(start, start + dir * 60.0, 1)
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty() or hit["collider"] != tank:
				continue
			var point: Vector3 = hit["position"]
			var normal: Vector3 = hit["normal"]
			var node: Node = tank.call("_shape_node", int(hit["shape"]))
			var part: String = "hull"
			var frame: Node3D = tank
			if node == turret_shape or turret_shapes.has(node):
				part = "turret"
				frame = turret
			var face: String = tank.call("_face_for_normal",
					frame.global_basis.orthonormalized().inverse() * normal)
			var local_point: Vector3 = frame.to_local(point)
			dmg.reset()
			var plate: float = dmg.armour_mm(part, face, local_point)
			var velocity: Vector3 = dir * speed
			var result: HitResult = Armour.resolve(shell, speed, plate,
					Armour.impact_angle(velocity, normal),
					Armour.ricochet_angle(tank.data.armour, shell.caliber_mm, plate))
			dmg.apply_hit(shell, result, part, face, local_point, tank.to_local(point),
					tank.global_basis.orthonormalized().inverse() * dir, turret.to_local(point),
					turret.global_basis.orthonormalized().inverse() * dir)
			var kind: String = "stop"
			if result.outcome == HitResult.Outcome.RICOCHET:
				kind = "ric"
			elif result.outcome == HitResult.Outcome.PENETRATION:
				kind = "ammo" if result.modules.has("ammo") else "pen"
			counts["hits"] += 1
			if kind == "ammo":
				counts["ammo"] += 1
			xforms.append(Transform3D(Basis(), point - dir * 0.3))
			colors.append(COLORS[kind])
	var mm: MultiMesh = _dots.multimesh
	mm.instance_count = 0
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, Color(colors[i], 0.8))
	return counts


func _save_sheet(panels: Array[Image], path: String) -> void:
	var cols: int = 4
	var rows: int = ceili(panels.size() / float(cols))
	var w: int = panels[0].get_width()
	var h: int = panels[0].get_height()
	var sheet := Image.create(w * cols, h * rows, false, panels[0].get_format())
	sheet.fill(Color(0.85, 0.87, 0.9))
	for i: int in panels.size():
		sheet.blit_rect(panels[i], Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(path)


func _frames() -> void:
	for i: int in 4:
		await process_frame
