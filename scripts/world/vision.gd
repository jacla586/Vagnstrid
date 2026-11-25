class_name Vision
extends RefCounted
## Line-of-sight rules shared by everything that "sees": MG nests now, the spotting
## system and bots later (same rules as the player, no cheating).
##
## Physics layers (named in project settings):
##   1 world             terrain, hulls, tree trunks: block sight and shells
##   2 vehicles          tanks (also on layer 1); watched by tree push triggers
##   3 commander_hitbox  exposed commanders (areas)
##   5 vision_blocker    bushes and tree canopies (areas): block sight only
##   6 smoke             smoke clouds (areas, also on 5): block sight, even infantry's
## Shells and fragments use SHOT_MASK, so they pass through vision blockers and smoke.

const LAYER_VEHICLES: int = 1 << 1
const LAYER_COMMANDER_HITBOX: int = 1 << 2
const LAYER_VISION_BLOCKER: int = 1 << 4
const LAYER_SMOKE: int = 1 << 5
## Mask for shell and fragment rays: everything except vision blockers and smoke.
const SHOT_MASK: int = 0xFFFFFFFF & ~LAYER_VISION_BLOCKER & ~LAYER_SMOKE
## The solid ray of a see-through look (has_line_of_sight_through): as shells, but smoke
## blocks it. Infantry see through a little vegetation, never through smoke.
const SIGHT_THROUGH_MASK: int = SHOT_MASK | LAYER_SMOKE


## True if a ray from `from` to `to` reaches `target` before anything else that
## blocks sight (terrain, hulls, bushes, canopies). `exclude` lists RIDs to ignore
## (usually the looker itself).
static func has_line_of_sight(world: World3D, from: Vector3, to: Vector3,
		target: CollisionObject3D, exclude: Array[RID] = []) -> bool:
	return has_line_of_sight_in(world.direct_space_state, from, to, target, exclude)


## has_line_of_sight in a given physics space (a thread can't get one from World3D).
static func has_line_of_sight_in(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		target: CollisionObject3D, exclude: Array[RID] = []) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * 0.5)
	query.collide_with_areas = true
	query.exclude = exclude
	var hit: Dictionary = space.intersect_ray(query)
	return not hit.is_empty() and int(hit["collider_id"]) == target.get_instance_id()


## Like has_line_of_sight, but the ray may pass through up to `max_blockers` vision
## blockers (bush or canopy crowns, each crown one layer). Terrain, hulls and
## trunks still block. Used by infantry, who see through a little vegetation.
static func has_line_of_sight_through(world: World3D, from: Vector3, to: Vector3,
		target: CollisionObject3D, max_blockers: int, exclude: Array[RID] = []) -> bool:
	return has_line_of_sight_through_in(world.direct_space_state, from, to, target,
			max_blockers, exclude)


## has_line_of_sight_through in a given physics space (a thread can't get one from World3D).
static func has_line_of_sight_through_in(space: PhysicsDirectSpaceState3D, from: Vector3,
		to: Vector3, target: CollisionObject3D, max_blockers: int,
		exclude: Array[RID] = []) -> bool:
	var dir: Vector3 = (to - from).normalized()
	var end: Vector3 = to + dir * 0.5
	# Solid things, smoke (and other hitboxes) first: the target must be the first of them.
	var query := PhysicsRayQueryParameters3D.create(from, end, SIGHT_THROUGH_MASK)
	query.collide_with_areas = true
	query.exclude = exclude
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty() or int(hit["collider_id"]) != target.get_instance_id():
		return false
	if max_blockers < 0:
		return true
	# Then count the crowns on the way to it. A ray starting inside a crown doesn't see
	# that crown, so each step starts just past the last entry point.
	var stop: float = from.distance_to(hit["position"] as Vector3)
	var crowns := PhysicsRayQueryParameters3D.create(from, hit["position"], LAYER_VISION_BLOCKER)
	crowns.collide_with_areas = true
	crowns.collide_with_bodies = false
	crowns.exclude = exclude
	var count: int = 0
	var start: Vector3 = from
	var last_rid := RID()
	var last_shape: int = -1
	for i: int in max_blockers * 2 + 4:
		crowns.from = start
		var c: Dictionary = space.intersect_ray(crowns)
		if c.is_empty():
			return true
		var p: Vector3 = c["position"]
		# The same crown again (its far side): not a new layer.
		if c["rid"] != last_rid or int(c["shape"]) != last_shape:
			count += 1
			if count > max_blockers:
				return false
		last_rid = c["rid"]
		last_shape = int(c["shape"])
		start = p + dir * 0.05
		if from.distance_to(start) >= stop:
			return true
	return false
