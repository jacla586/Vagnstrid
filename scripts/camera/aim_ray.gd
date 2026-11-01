class_name AimRay
extends RefCounted
## Finds the world point under a camera's screen centre.

const RANGE: float = 2000.0


## First hit within RANGE straight ahead of the camera (ignoring `exclude`),
## or the point at RANGE if nothing is hit.
static func cast(camera: Camera3D, exclude: CollisionObject3D) -> Vector3:
	var from: Vector3 = camera.global_position
	var to: Vector3 = from - camera.global_basis.z * RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if exclude != null:
		query.exclude = [exclude.get_rid()]
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return hit["position"]
