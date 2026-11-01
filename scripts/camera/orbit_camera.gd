class_name OrbitCamera
extends Camera3D
## Debug third-person camera. The mouse orbits it around the target in world space,
## so turning the hull doesn't move the view. The screen centre is the aim point.

@export var target: Node3D
@export var distance: float = 14.0
## Height of the orbit pivot above the target's origin (m).
@export var pivot_height: float = 3.0
## Higher = pivot catches up with the target faster.
@export var follow_sharpness: float = 10.0
## Radians per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.003
@export var min_pitch_deg: float = -60.0
@export var max_pitch_deg: float = 30.0

var _yaw: float = 0.0
var _pitch: float = deg_to_rad(-12.0)
var _pivot: Vector3 = Vector3.ZERO


func _ready() -> void:
	if target != null:
		_yaw = target.global_rotation.y
		_pivot = target.global_position + Vector3.UP * pivot_height
		_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if not current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	_yaw = wrapf(_yaw - motion.relative.x * mouse_sensitivity, -PI, PI)
	_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


func _process(delta: float) -> void:
	if target == null:
		return
	var weight: float = 1.0 - exp(-follow_sharpness * delta)
	_pivot = _pivot.lerp(target.global_position + Vector3.UP * pivot_height, weight)
	_update_transform()


func get_aim_point() -> Vector3:
	return AimRay.cast(self, target as CollisionObject3D)


func _update_transform() -> void:
	var orbit := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	global_transform = Transform3D(orbit, _pivot + orbit.z * distance)
