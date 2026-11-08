class_name RainField
extends GPUParticles3D
## Player rig: rain streaks in a box round the camera in use, falling in world space and
## slanted by the wind (Weather). Off when the weather is dry. No collision: it falls
## through roofs and crowns (cheap; under a roof you hardly look up).

## Box round the camera that rain falls in (m, half sizes) and how high above it starts.
const HALF_EXTENT: Vector3 = Vector3(22.0, 1.0, 22.0)
const START_ABOVE_M: float = 14.0
const FALL_MPS: float = 11.0
## Streaks at full intensity.
const MAX_AMOUNT: int = 12000
const STREAK_SIZE: Vector2 = Vector2(0.008, 0.45)
const COLOR: Color = Color(0.7, 0.75, 0.8, 0.26)


func _ready() -> void:
	var intensity: float = Weather.current().rain_intensity
	if intensity <= 0.0:
		emitting = false
		set_process(false)
		return
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved in _process
	top_level = true
	local_coords = false
	amount = maxi(int(MAX_AMOUNT * intensity), 1)
	lifetime = (START_ABOVE_M + 8.0) / FALL_MPS
	preprocess = lifetime
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-40.0, -40.0, -40.0), Vector3(80.0, 60.0, 80.0))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = HALF_EXTENT
	var fall: Vector3 = Vector3.DOWN * FALL_MPS + Weather.wind()
	process.direction = fall.normalized()
	process.spread = 2.0
	process.initial_velocity_min = fall.length() * 0.9
	process.initial_velocity_max = fall.length() * 1.1
	process.gravity = Vector3.ZERO
	process.particle_flag_align_y = true
	process_material = process
	var quad := QuadMesh.new()
	quad.size = STREAK_SIZE
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.albedo_color = COLOR
	mat.disable_receive_shadows = true
	quad.material = mat
	draw_pass_1 = quad
	emitting = true


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position + Vector3.UP * START_ABOVE_M
