extends SceneTree
## Renders the squad soldier in baked animations (soldier_anims.res) at a few moments
## each, side by side, for looking at poses without starting the game. Needs a window:
##   godot --path . --script res://tools/render_soldier_poses.gd -- <out dir> [clip ...]
## Writes <out dir>/<clip>.png (front three-quarter view), <clip>_side.png and
## <clip>_top.png (forward is up in the picture). With
## "--ref <fbx>" a second row shows the source clip on its own model (Mixamo's Y Bot).

const SOLDIER: String = "res://assets/models/soldier/soldier.glb"
const ANIMS: String = "res://assets/models/soldier/soldier_anims.res"
const SCALE: float = 0.065
const MOMENTS: int = 5
const SPACING_M: float = 1.6
const SIZE: Vector2i = Vector2i(1500, 700)

var _vp: SubViewport
var _camera: Camera3D
var _root3d: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://soldier_renders"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var clips: PackedStringArray = []
	var refs: Dictionary = {}  # clip -> fbx path
	var i: int = 1
	while i < args.size():
		if args[i] == "--ref" and i + 2 < args.size():
			refs[args[i + 1]] = args[i + 2]
			i += 3
			continue
		clips.append(args[i])
		i += 1
	var library: AnimationLibrary = load(ANIMS)
	if clips.is_empty():
		for a: StringName in library.get_animation_list():
			clips.append(String(a))
	_setup()
	for clip: String in clips:
		if not library.has_animation(clip):
			push_warning("no clip " + clip)
			continue
		var anim: Animation = library.get_animation(clip)
		for c: Node in _root3d.get_children():
			c.free()
		for k: int in MOMENTS:
			var t: float = anim.length * float(k) / float(MOMENTS - 1)
			var body: Node3D = (load(SOLDIER) as PackedScene).instantiate()
			body.scale = Vector3.ONE * SCALE
			body.rotation.y = PI
			body.position = Vector3(SPACING_M * (k - (MOMENTS - 1) * 0.5), 0.0, 0.0)
			_root3d.add_child(body)
			var player: AnimationPlayer = body.find_children("*", "AnimationPlayer", true, false)[0]
			player.add_animation_library(&"s", library)
			player.play(StringName("s/" + clip))
			player.seek(t, true)
			player.pause()
			if refs.has(clip):
				var ref: Node3D = (load(refs[clip]) as PackedScene).instantiate()
				ref.rotation.y = PI
				ref.position = body.position + Vector3(0.0, 0.0, 2.2)
				_root3d.add_child(ref)
				var rp: AnimationPlayer = ref.find_children("*", "AnimationPlayer", true, false)[0]
				rp.play(&"mixamo_com")
				rp.seek(minf(t, rp.current_animation_length), true)
				rp.pause()
		var depth: float = 2.2 if refs.has(clip) else 0.0
		var target := Vector3(0.0, 0.7, depth * 0.5)
		_camera.position = target + Vector3(-2.2, 1.6, -6.5 - depth)
		_camera.look_at(target)
		await _frames()
		_vp.get_texture().get_image().save_png("%s/%s.png" % [out_dir, clip])
		_camera.position = target + Vector3(-8.0, 1.2, -0.6)
		_camera.look_at(target)
		await _frames()
		_vp.get_texture().get_image().save_png("%s/%s_side.png" % [out_dir, clip])
		_camera.position = target + Vector3(0.0, 9.0, 0.0)
		_camera.look_at(target, Vector3.FORWARD)
		await _frames()
		_vp.get_texture().get_image().save_png("%s/%s_top.png" % [out_dir, clip])
	print("rendered %d clips to %s" % [clips.size(), ProjectSettings.globalize_path(out_dir)])
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
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = true
	_vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
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


func _frames() -> void:
	for i: int in 4:
		await process_frame
