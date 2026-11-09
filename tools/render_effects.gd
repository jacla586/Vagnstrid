extends SceneTree
## Pictures of the visual effects (data/effects) for tuning: plays each one in front of a
## fixed camera on a map and saves frames at a few moments.
##   godot --path . --disable-vsync --fixed-fps 60 --script res://tools/render_effects.gd -- [map] [label]
## Times are counted in frames (--fixed-fps 60), as saving a picture takes longer than a frame.
## Needs a window. Writes renders/effects/<label>/<effect>_<ms>.png.

const OUT_DIR: String = "res://renders/effects"
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
## Camera place (x, z on the map) and the spot it looks at, 30 m ahead.
const CAMERA_AT: Vector2 = Vector2(400.0, 560.0)
const TARGET_AT: Vector2 = Vector2(426.0, 575.0)
const SHOTS_MS: Array[int] = [40, 150, 500, 1500, 3500]

var _map: String = "vidingsjo"
var _label: String = "current"
var _frame: int = 0
var _queue: Array = []
var _current: Array = []
var _started_frame: int = 0
var _shot: int = 0
var _camera: Camera3D
var _target: Vector3
var _mover: Node3D


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1:
		_map = args[0]
	if args.size() >= 2:
		_label = args[1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "/" + _label))
	DisplayServer.window_set_size(WINDOW_SIZE)
	root.size = WINDOW_SIZE
	Weather.set_current(Weather.load_preset("clear"))
	change_scene_to_file("res://scenes/maps/%s.tscn" % _map)
	var fx: EffectsSetData = load("res://data/effects/effects.tres")
	# [name, effect, scale, out, height above ground, extra effect]
	_queue = [
		["ground_75", fx.impact_ground, 1.0, Vector3.UP, 0.0, null],
		["armour_75", fx.impact_armour, 1.0, Vector3(-1, 0.3, -0.5), 1.5, null],
		["building_75", fx.impact_building, 1.0, Vector3(-1, 0.2, -0.5), 1.5, null],
		["wood_75", fx.impact_wood, 1.0, Vector3(-1, 0.2, -0.5), 2.0, null],
		["he_75", fx.impact_ground, 1.0, Vector3.UP, 0.0, fx.explosion],
		["he_152", fx.impact_ground, 2.03, Vector3.UP, 0.0, fx.explosion],
		["muzzle_75", fx.muzzle_flash, 1.0, Vector3(0, 0.05, 1), 2.0, fx.muzzle_blast_dust],
		["bullets", fx.bullet_ground, 1.0, Vector3.UP, 0.0, fx.bullet_armour],
		["dust_drive", null, 1.0, Vector3.UP, 0.0, null],
		["fire", null, 1.0, Vector3.UP, 0.0, null],
	]


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
		EffectFx.prewarm(scene)
	if _frame < 200:
		return false
	if _frame == 200:
		var eye := Vector3(CAMERA_AT.x, 0.0, CAMERA_AT.y)
		eye.y = _ground(eye) + 2.5
		_target = Vector3(TARGET_AT.x, 0.0, TARGET_AT.y)
		_target.y = _ground(_target)
		_camera.global_transform = Transform3D(Basis.looking_at(_target + Vector3.UP * 2.0 - eye, Vector3.UP), eye)
		_camera.fov = 55.0
		return false
	if _current.is_empty():
		if _queue.is_empty():
			return true
		_current = _queue.pop_front()
		var at: Vector3 = _target + Vector3.UP * float(_current[4])
		if _current[0] == "dust_drive":
			# Two emitters driving across at 9 m/s, like a tank's tracks.
			_mover = Node3D.new()
			current_scene.add_child(_mover)
			_mover.global_position = at + Vector3(-12.0, 0.2, 0.0)
			_mover.basis = Basis(Vector3.UP, -PI * 0.5)
			for side: float in [-1.4, 1.4]:
				var e: GPUParticles3D = EffectFx.emitter(fx_set().track_dust, 1.0)
				e.position = Vector3(side, 0.0, 3.0)
				_mover.add_child(e)
				e.emitting = true
		elif _current[0] == "fire":
			var fire: Node3D = load("res://scenes/effects/burning.tscn").instantiate()
			current_scene.add_child(fire)
			fire.global_position = at + Vector3.UP * 0.8
		else:
			EffectFx.play(_current[1], current_scene, at, _current[3], _current[2])
		if _current[5] != null:
			var out2: Vector3 = Vector3.UP if _current[0] != "bullets" else Vector3(-1, 0.3, -0.5)
			var at2: Vector3 = _target if _current[0] == "muzzle_75" else at + (Vector3.UP * 1.5 if _current[0] == "bullets" else Vector3.ZERO)
			EffectFx.play(_current[5], current_scene, at2, out2, _current[2])
		_started_frame = _frame
		_shot = 0
		return false
	var age: int = (_frame - _started_frame) * 1000 / 60
	if _mover != null and is_instance_valid(_mover):
		_mover.global_position += Vector3(9.0 / 60.0, 0.0, 0.0)
	if _shot < SHOTS_MS.size() and age >= SHOTS_MS[_shot]:
		var file: String = "%s/%s/%s_%04d.png" % [OUT_DIR, _label, _current[0], SHOTS_MS[_shot]]
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(file))
		_shot += 1
	if _shot >= SHOTS_MS.size() and age > 6000:
		_current = []
		if _mover != null:
			_mover.queue_free()
			_mover = null
	return false


func fx_set() -> EffectsSetData:
	return load("res://data/effects/effects.tres")


func _ground(p: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 1000.0, p.z), Vector3(p.x, -1000.0, p.z), 1)
	var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
	return float(hit["position"].y) if not hit.is_empty() else 0.0
