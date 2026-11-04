class_name SquadCamera
extends Camera3D
## Looking through the squad leader's eyes (PlayerViews squad view): free look from
## his eye height (lower when the squad kneels), no control over the squad. The leader
## is the squad's first living soldier (Squad.get_leader_eye). Binoculars on the
## "binoculars" action, like the commander's.

## Higher = zooming in and out happens faster.
@export var fov_sharpness: float = 15.0

## Radians per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.003
@export var tank: Tank

var _yaw: float = 0.0
var _pitch: float = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	# Slower mouse when zoomed in, so aim feels the same on screen.
	var zoom_scale: float = fov / tank.squad.data.view_fov_deg if can_view() else 1.0
	_yaw = wrapf(_yaw - motion.relative.x * mouse_sensitivity * zoom_scale, -PI, PI)
	_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity * zoom_scale,
			deg_to_rad(-60.0), deg_to_rad(70.0))


func is_binoculars_active() -> bool:
	return current and can_view() and Input.is_action_pressed("binoculars")


## The view is available: the tank has a squad that is off the tank.
func can_view() -> bool:
	return tank != null and tank.squad != null and is_instance_valid(tank.squad) \
			and not tank.squad.is_mounted()


## On entering the view: look the way the squad faces.
func start() -> void:
	if can_view():
		var h: Vector3 = tank.squad.get_heading()
		_yaw = atan2(-h.x, -h.z)
		_pitch = 0.0
		fov = tank.squad.data.view_fov_deg
	_process(0.0)


func get_aim_point() -> Vector3:
	return AimRay.cast(self, null)


func _process(delta: float) -> void:
	if not can_view():
		return
	var data: SquadData = tank.squad.data
	var target_fov: float = data.binocular_fov_deg if is_binoculars_active() else data.view_fov_deg
	fov = lerpf(fov, target_fov, minf(delta * fov_sharpness, 1.0)) if delta > 0.0 else target_fov
	global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)),
			tank.squad.get_leader_eye())
