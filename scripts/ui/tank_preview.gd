class_name TankPreview
extends SubViewportContainer
## A tank turning slowly on a soft dark disc, in its own little world (garage and the
## in-match tank picker). show_tank(data) builds the look from a throw-away tank.

const TANK_SCENE: PackedScene = preload("res://scenes/tank/tank.tscn")

@export var turn_deg_s: float = 20.0

var _root: Node3D
var _tank: Node3D
var _camera: Camera3D
var _floor: MeshInstance3D


func _init() -> void:
	stretch = true
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(320, 240)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.45, 0.48)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_color = Color(1.0, 0.9, 0.8)
	sun.shadow_enabled = true
	vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_color = MenuTheme.ACCENT
	rim.light_energy = 0.3
	vp.add_child(rim)
	# Only the shadow and a soft dark round floor show; the picture is behind.
	_floor = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 64
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.1, 0.1, 0.11, 0.65)
	floor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	floor_mat.roughness = 1.0
	disc.material = floor_mat
	_floor.mesh = disc
	vp.add_child(_floor)
	_root = Node3D.new()
	vp.add_child(_root)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	vp.add_child(_camera)


func _process(delta: float) -> void:
	_root.rotate_y(deg_to_rad(turn_deg_s) * delta)


## Shows the tank `d` (painted as a friend), framed by the camera.
func show_tank(d: TankData) -> void:
	if _tank != null:
		_tank.queue_free()
		_tank = null
	if d == null:
		return
	var tank: Tank = TANK_SCENE.instantiate()
	tank.data = d
	tank.apply_geometry()
	var visual: Node3D = tank.get_node("Visual")
	visual.get_node("Turret/Cupola/CommanderHitbox").free()
	tank.remove_child(visual)
	tank.free()
	_root.add_child(visual)
	Tank.paint_visual(visual, true)
	visual.position = Vector3(0.0, d.hull_size.y * 0.5, 0.0)
	_tank = visual
	var extent: float = maxf(d.hull_size.z, d.gun_length_m + d.turret_radius_m * 2.0)
	_floor.scale = Vector3(extent * 0.62, 1.0, extent * 0.62)
	# Not look_at: the preview may not be in the tree yet.
	_camera.transform = Transform3D(Basis(), Vector3(0.0, extent * 0.42, extent * 1.35)) \
			.looking_at(Vector3(0.0, d.hull_size.y * 0.55, 0.0), Vector3.UP)
