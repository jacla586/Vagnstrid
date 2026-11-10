class_name CommanderHitbox
extends Area3D
## The exposed commander's head and shoulders. Shells and bullets hit it (their ray
## queries include areas); the tank moves it with the hatch and disables it when
## the hatch is shut. Also a fragment target (see Explosion). The open hatch lid behind
## him stops bullets and fragments on their way through it (Tank.hatch_lid_shields).

## How far back along a bullet's path the hatch lid is looked for (m).
const LID_CHECK_M: float = 3.0

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


## Explosion: fragments from `origin` the open hatch lid stops (it stands behind him).
func fragment_shielded(origin: Vector3) -> bool:
	return tank != null and tank.hatch_lid_shields(origin, global_position)


func on_fragment_hit(shell_data: ShellData, _distance: float) -> HitResult:
	if tank == null:
		return null
	return tank.on_commander_hit(shell_data, global_position)


func on_shell_hit(shell_data: ShellData, point: Vector3, _normal: Vector3,
		velocity: Vector3, _shape: int = -1) -> HitResult:
	if tank == null:
		return null
	# Bullets that came through the open hatch lid (from behind him) stop in it; gun
	# rounds go through the thin plate.
	if shell_data.caliber_mm < Tank.THREAT_MIN_CALIBER_MM and velocity.length() > 0.01 \
			and tank.hatch_lid_shields(point - velocity.normalized() * LID_CHECK_M, point):
		return null
	return tank.on_commander_hit(shell_data, point)
