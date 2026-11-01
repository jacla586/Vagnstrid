class_name ChaseCamera
extends Camera3D
## Temporary third-person camera that follows behind a target.
## Will be replaced by the cupola / periscope views.

@export var target: Node3D
@export var distance: float = 14.0
@export var height: float = 5.0
@export var look_height: float = 1.5
## Higher = camera catches up faster.
@export var follow_sharpness: float = 4.0


func _ready() -> void:
	if target != null:
		global_position = _desired_position()
		look_at(target.global_position + Vector3.UP * look_height)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var weight: float = 1.0 - exp(-follow_sharpness * delta)
	global_position = global_position.lerp(_desired_position(), weight)
	look_at(target.global_position + Vector3.UP * look_height)


func _desired_position() -> Vector3:
	var back: Vector3 = target.global_basis.z
	back.y = 0.0
	if back.length_squared() < 0.0001:
		back = Vector3.BACK
	return target.global_position + back.normalized() * distance + Vector3.UP * height
