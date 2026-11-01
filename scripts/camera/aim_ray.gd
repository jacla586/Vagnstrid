class_name AimRay
extends RefCounted
## Finds the world point a view is aiming at.

const RANGE: float = 2000.0


## First hit straight ahead of the camera (screen centre), ignoring `exclude`.
static func cast(camera: Camera3D, exclude: CollisionObject3D) -> Vector3:
	return cast_from(camera.get_world_3d(), camera.global_position,
			-camera.global_basis.z, exclude)


## First hit within RANGE from `from` along `direction` (ignoring `exclude`),
## or the point at RANGE if nothing is hit.
static func cast_from(world: World3D, from: Vector3, direction: Vector3,
		exclude: CollisionObject3D) -> Vector3:
	var to: Vector3 = from + direction.normalized() * RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if exclude != null:
		query.exclude = [exclude.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return hit["position"]
