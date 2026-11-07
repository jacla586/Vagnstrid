class_name GunnerCamera
extends Camera3D
## The gunner's sight. The view is fixed to the gun (the tank's GunnerSight marker),
## so it follows traverse and elevation. The mouse sets a desired aim direction in
## world space; the turret chases it, and the view lags behind at traverse speed.

## Render layer of the tank's own gun/mantlet meshes, hidden from the sight.
const OWN_GUN_LAYER: int = 2
## Aim point distance when the sight has no zeroing range (m).
const MIN_AIM_DISTANCE: float = 500.0
## Radius of the sight's clear circle as a share of the screen height
## (keep in step with mode 3 in view_mask.gdshader).
const SIGHT_CIRCLE_RADIUS: float = 0.46

## Radians per pixel of mouse movement at the commander's naked-eye FOV.
@export var mouse_sensitivity: float = 0.003
@export var tank: Tank
## How far the desired aim may lead the gun, in sight-circle radii (1.25 = a little
## outside the black edge). Keeps the aim mark on screen on wide monitors and stops
## the aim from wrapping round to the other side of the turret.
@export var aim_lead_limit: float = 1.25

var _target_yaw: float = 0.0
var _target_pitch: float = 0.0
var _zoom_index: int = 0
## The tank whose gun is moved to OWN_GUN_LAYER (only this camera's own tank).
var _hidden_gun_tank: Tank
## Extra pitch, yaw and roll (radians) while the view shakes from a hit (HitReaction).
var shake: Vector3 = Vector3.ZERO


func _ready() -> void:
	set_cull_mask_value(OWN_GUN_LAYER, false)
	_hide_own_gun()
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
		_limit_lead()


func _process(_delta: float) -> void:
	if tank != _hidden_gun_tank:
		_hide_own_gun()
	if tank != null:
		_apply()
		if current:
			_limit_lead()


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


## Where the turret should aim: on the desired sight line, at the range where the
## sight crosses the bore (the zeroing range). Not what a ray hits: a tree drifting
## into the line would change the parallax and make the gun (and this view) jump.
## Range is the gunner's job, with the reticle's range ladder.
func get_aim_point() -> Vector3:
	var distance: float = maxf(tank.data.sight_zero_range_m, MIN_AIM_DISTANCE)
	return tank.get_gunner_sight_transform().origin + get_desired_direction() * distance


## Screen position of the desired aim direction, or Vector2.INF if it's behind.
func get_desired_aim_screen_position() -> Vector2:
	var point: Vector3 = global_position + get_desired_direction() * 100.0
	if is_position_behind(point):
		return Vector2.INF
	return unproject_position(point)


## Only the own tank's gun is hidden from the sight; every other tank's gun shows.
func _hide_own_gun() -> void:
	if is_instance_valid(_hidden_gun_tank):
		_hidden_gun_tank.set_gun_render_layer(1)
	_hidden_gun_tank = tank
	if tank != null:
		tank.set_gun_render_layer(OWN_GUN_LAYER)


## Keeps the desired aim within aim_lead_limit sight radii of where the sight
## points now (also after zooming in, which shrinks the circle's angle).
func _limit_lead() -> void:
	var forward: Vector3 = -tank.get_gunner_sight_transform().basis.z.normalized()
	var desired: Vector3 = get_desired_direction()
	# Angle from the view centre to the circle edge times the limit (vertical FOV).
	var max_angle: float = atan(aim_lead_limit * SIGHT_CIRCLE_RADIUS * 2.0
			* tan(deg_to_rad(fov) * 0.5))
	var angle: float = forward.angle_to(desired)
	if angle <= max_angle:
		return
	var limited: Vector3 = forward.slerp(desired, max_angle / angle).normalized()
	set_target_view(atan2(-limited.x, -limited.z), asin(clampf(limited.y, -1.0, 1.0)))


func _apply() -> void:
	var levels: PackedFloat32Array = tank.data.gunner_sight_fov_deg
	if not levels.is_empty():
		_zoom_index = clampi(_zoom_index, 0, levels.size() - 1)
		fov = levels[_zoom_index]
	var sight: Transform3D = tank.get_gunner_sight_transform_interpolated()
	global_transform = Transform3D(sight.basis * Basis.from_euler(shake), sight.origin)
