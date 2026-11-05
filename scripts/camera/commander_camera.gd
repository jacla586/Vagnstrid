class_name CommanderCamera
extends Camera3D
## The commander's eyes. Position comes from the tank (rises as the hatch opens);
## look direction is world-space yaw/pitch from the mouse, so the view stays steady
## while the turret or hull turns.
##
## Hatch open: naked eye, wide pitch range, binoculars on the "binoculars" action.
## Hatch closed: periscope with a narrow FOV and pitch range. It turns toward the
## mouse at most at the periscope's turn speed and is limited relative to the turret.

## Radians per pixel of mouse movement at the naked-eye FOV.
@export var mouse_sensitivity: float = 0.003
## Higher = FOV changes (binoculars, hatch) happen faster.
@export var fov_sharpness: float = 15.0
@export var tank: Tank

var _target_yaw: float = 0.0
var _target_pitch: float = 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0
## Extra pitch, yaw and roll (radians) while the view shakes from a hit (HitReaction).
var shake: Vector3 = Vector3.ZERO


func _ready() -> void:
	if tank != null:
		_yaw = tank.global_rotation.y
		_target_yaw = _yaw
		fov = tank.data.commander_fov_deg
		_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if not current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or tank == null:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	# Slower mouse when zoomed in, so aim feels the same on screen.
	var zoom_scale: float = fov / tank.data.commander_fov_deg
	_target_yaw = wrapf(_target_yaw - motion.relative.x * mouse_sensitivity * zoom_scale, -PI, PI)
	_target_pitch -= motion.relative.y * mouse_sensitivity * zoom_scale


## True when looking from the open hatch (past the halfway point of opening).
func is_hatch_view() -> bool:
	return tank != null and tank.get_hatch_progress() >= 0.5


func is_periscope_view() -> bool:
	return tank != null and not is_hatch_view()


func is_binoculars_active() -> bool:
	return current and is_hatch_view() and Input.is_action_pressed("binoculars")


## Sets where the commander wants to look (world yaw/pitch, radians).
func set_target_view(yaw: float, pitch: float) -> void:
	_target_yaw = wrapf(yaw, -PI, PI)
	_target_pitch = pitch


func get_view_yaw() -> float:
	return _yaw


func get_aim_point() -> Vector3:
	return AimRay.cast(self, tank)


func _process(delta: float) -> void:
	if tank == null:
		return
	var d: TankData = tank.data
	var target_fov: float
	if is_hatch_view():
		_target_pitch = clampf(_target_pitch,
				deg_to_rad(d.open_pitch_min_deg), deg_to_rad(d.open_pitch_max_deg))
		_yaw = _target_yaw
		_pitch = _target_pitch
		target_fov = d.commander_fov_deg
		if is_binoculars_active():
			target_fov = d.binocular_fov_deg()
	else:
		_target_pitch = clampf(_target_pitch,
				deg_to_rad(d.periscope_pitch_min_deg), deg_to_rad(d.periscope_pitch_max_deg))
		var limit: float = deg_to_rad(d.periscope_yaw_limit_deg)
		if limit < PI:
			var turret_yaw: float = tank.get_turret_global_yaw()
			var relative: float = wrapf(_target_yaw - turret_yaw, -PI, PI)
			_target_yaw = wrapf(turret_yaw + clampf(relative, -limit, limit), -PI, PI)
		var step: float = deg_to_rad(d.periscope_turn_speed_deg) * delta
		var yaw_diff: float = wrapf(_target_yaw - _yaw, -PI, PI)
		_yaw = wrapf(_yaw + clampf(yaw_diff, -step, step), -PI, PI)
		_pitch = move_toward(_pitch, _target_pitch, step)
		target_fov = d.periscope_fov_deg
	fov = lerpf(fov, target_fov, 1.0 - exp(-fov_sharpness * delta))
	_update_transform()


func _update_transform() -> void:
	global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
			* Basis.from_euler(shake), tank.get_commander_eye_position_interpolated())
