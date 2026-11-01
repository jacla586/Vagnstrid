class_name GunnerCamera
extends Camera3D
## The gunner's sight. The view is fixed to the gun (the tank's GunnerSight marker),
## so it follows traverse and elevation. The mouse sets a desired aim direction in
## world space; the turret chases it, and the view lags behind at traverse speed.

## Render layer of the tank's own gun/mantlet meshes, hidden from the sight.
const OWN_GUN_LAYER: int = 2

## Radians per pixel of mouse movement at the commander's naked-eye FOV.
@export var mouse_sensitivity: float = 0.003
@export var tank: Tank

var _target_yaw: float = 0.0
var _target_pitch: float = 0.0
var _zoom_index: int = 0


func _ready() -> void:
	set_cull_mask_value(OWN_GUN_LAYER, false)
	if tank != null:
		sync_to_gun()
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	if not current or tank == null:
		return
	var levels: PackedFloat32Array = tank.data.gunner_sight_fov_deg
	if event.is_action_pressed("sight_zoom_in"):
		_zoom_index = mini(_zoom_index + 1, levels.size() - 1)
	elif event.is_action_pressed("sight_zoom_out"):
		_zoom_index = maxi(_zoom_index - 1, 0)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		# Slower mouse when zoomed in, so aim feels the same on screen.
		var zoom_scale: float = fov / tank.data.commander_fov_deg
		set_target_view(_target_yaw - motion.relative.x * mouse_sensitivity * zoom_scale,
				_target_pitch - motion.relative.y * mouse_sensitivity * zoom_scale)


func _process(_delta: float) -> void:
	if tank != null:
		_apply()


## Sets the desired aim to where the gun points now, so entering the sight
## doesn't make the turret jump.
func sync_to_gun() -> void:
	var forward: Vector3 = -tank.get_gunner_sight_transform().basis.z
	set_target_view(atan2(-forward.x, -forward.z), asin(clampf(forward.y, -1.0, 1.0)))


## Sets the desired aim direction (world yaw/pitch, radians). Pitch is clamped to
## the gun's elevation limits.
func set_target_view(yaw: float, pitch: float) -> void:
	_target_yaw = wrapf(yaw, -PI, PI)
	_target_pitch = clampf(pitch, -deg_to_rad(tank.data.gun_max_depression_deg),
			deg_to_rad(tank.data.gun_max_elevation_deg))


func get_zoom_index() -> int:
	return _zoom_index


func get_desired_direction() -> Vector3:
	return Basis.from_euler(Vector3(_target_pitch, _target_yaw, 0.0)) * Vector3.FORWARD


## Where the turret should aim: along the desired direction from the sight.
func get_aim_point() -> Vector3:
	return AimRay.cast_from(get_world_3d(), tank.get_gunner_sight_transform().origin,
			get_desired_direction(), tank)


## Screen position of the desired aim direction, or Vector2.INF if it's behind.
func get_desired_aim_screen_position() -> Vector2:
	var point: Vector3 = global_position + get_desired_direction() * 100.0
	if is_position_behind(point):
		return Vector2.INF
	return unproject_position(point)


func _apply() -> void:
	var levels: PackedFloat32Array = tank.data.gunner_sight_fov_deg
	if not levels.is_empty():
		_zoom_index = clampi(_zoom_index, 0, levels.size() - 1)
		fov = levels[_zoom_index]
	global_transform = tank.get_gunner_sight_transform()
