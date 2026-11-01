class_name CommanderHitbox
extends Area3D
## The exposed commander's head and shoulders. Shells and bullets hit it (their ray
## queries include areas); the tank moves it with the hatch and disables it when
## the hatch is shut.

@export var tank: Tank


func on_shell_hit(shell_data: ShellData, point: Vector3, _normal: Vector3,
		_velocity: Vector3, _shape: int = -1) -> HitResult:
	if tank == null:
		return null
	return tank.on_commander_hit(shell_data, point)
