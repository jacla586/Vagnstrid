class_name Concealment
extends RefCounted
## Spotting modifiers from cover and movement (see ConcealmentData). Pure functions
## like Vision, so bots and later the player's spotting share the same rules.
## Cover counts sight-blocker shapes (layer "vision_blocker") around the target:
## bushes and tree crowns in hand-made maps, laser-tree crowns in real maps.


## 0 = in the open, 1 = full cover.
static func cover(world: World3D, target: Node3D, data: ConcealmentData) -> float:
	var box := BoxShape3D.new()
	box.size = data.cover_box_size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis(), target.global_position
			+ Vector3.UP * (data.cover_box_size.y * 0.5 - 2.0))
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = Vision.LAYER_VISION_BLOCKER
	var hits: Array[Dictionary] = world.direct_space_state.intersect_shape(query,
			maxi(data.full_cover_blockers, 1))
	return clampf(float(hits.size()) / maxf(float(data.full_cover_blockers), 1.0), 0.0, 1.0)


## How many times longer than normal it takes to spot a target with this cover and speed.
static func spot_time_factor(cover_amount: float, speed: float, data: ConcealmentData) -> float:
	var factor: float = 1.0 + cover_amount * data.cover_spot_time_factor
	if speed <= data.stationary_speed_mps:
		factor *= data.stationary_spot_time_factor
	elif speed >= data.fast_speed_mps:
		factor *= data.moving_fast_spot_time_factor
	return factor


## Share of the normal spotting range at which a target with this cover can be spotted.
static func range_factor(cover_amount: float, data: ConcealmentData) -> float:
	return lerpf(1.0, data.cover_range_factor, cover_amount)
