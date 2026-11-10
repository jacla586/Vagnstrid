class_name SoldierHitbox
extends Area3D
## One soldier's body: shells and bullets hit it (their rays include areas) and it is
## a fragment target (Explosion). Any hit puts the soldier down. Belongs to its
## squad's team (no friendly fire).

var squad: Squad
var index: int = 0

var _shape: CollisionShape3D
var _capsule: CapsuleShape3D


func _init() -> void:
	collision_layer = Vision.LAYER_COMMANDER_HITBOX
	collision_mask = 0
	monitoring = false
	_capsule = CapsuleShape3D.new()
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	add_child(_shape)


func _ready() -> void:
	add_to_group(Explosion.TARGET_GROUP)


## Body height (standing or kneeling) and radius, feet at the origin.
func set_size(height: float, radius: float) -> void:
	_capsule.height = maxf(height, radius * 2.0)
	_capsule.radius = radius
	_shape.rotation = Vector3.ZERO
	_shape.position = Vector3(0.0, height * 0.5, 0.0)


## Lying down: a capsule `length` long along the ground (Z), `radius` thick, its middle
## `ahead` ahead of his position (-Z).
func set_lying(length: float, radius: float, ahead: float) -> void:
	_capsule.height = maxf(length, radius * 2.0)
	_capsule.radius = radius
	_shape.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_shape.position = Vector3(0.0, radius, -ahead)


func set_active(on: bool) -> void:
	_shape.set_deferred("disabled", not on)


func get_team() -> int:
	return squad.get_team() if squad != null else -1


func get_aim_point() -> Vector3:
	return to_global(_shape.position)


func is_fragment_target_active() -> bool:
	return squad != null and squad.is_soldier_exposed(index)


func get_fragment_aim_point() -> Vector3:
	return get_aim_point()


func get_fragment_collider() -> CollisionObject3D:
	return self


## Explosion: fragments reach soldiers farther (SquadData.fragment_radius_factor).
func fragment_radius_factor() -> float:
	return squad.data.fragment_radius_factor if squad != null and squad.data != null else 1.0


func on_fragment_hit(_shell_data: ShellData, _distance: float) -> HitResult:
	return squad.soldier_hit(index) if squad != null else null


func on_shell_hit(_shell_data: ShellData, _point: Vector3, _normal: Vector3,
		_velocity: Vector3, _shape_index: int = -1) -> HitResult:
	return squad.soldier_hit(index) if squad != null else null
