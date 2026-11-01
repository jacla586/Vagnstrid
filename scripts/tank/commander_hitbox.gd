class_name CommanderHitbox
extends Area3D
## The exposed commander's head and shoulders. Shells and bullets hit it (their ray
## queries include areas); the tank moves it with the hatch and disables it when
## the hatch is shut. Also a fragment target (see Explosion).

@export var tank: Tank

@onready var _shape: CollisionShape3D = $Shape


func _ready() -> void:
	add_to_group(Explosion.TARGET_GROUP)


func is_fragment_target_active() -> bool:
	return tank != null and tank.is_commander_exposed() and not _shape.disabled


func get_fragment_aim_point() -> Vector3:
	return global_position


func get_fragment_collider() -> CollisionObject3D:
	return self


func on_fragment_hit(shell_data: ShellData, _distance: float) -> HitResult:
	if tank == null:
		return null
	return tank.on_commander_hit(shell_data, global_position)


func on_shell_hit(shell_data: ShellData, point: Vector3, _normal: Vector3,
		_velocity: Vector3, _shape: int = -1) -> HitResult:
	if tank == null:
		return null
	return tank.on_commander_hit(shell_data, point)
