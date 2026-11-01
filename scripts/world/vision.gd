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
## Shells and fragments use SHOT_MASK, so they pass through vision blockers.

const LAYER_VEHICLES: int = 1 << 1
const LAYER_COMMANDER_HITBOX: int = 1 << 2
const LAYER_VISION_BLOCKER: int = 1 << 4
## Mask for shell and fragment rays: everything except vision blockers.
const SHOT_MASK: int = 0xFFFFFFFF & ~LAYER_VISION_BLOCKER


## True if a ray from `from` to `to` reaches `target` before anything else that
## blocks sight (terrain, hulls, bushes, canopies). `exclude` lists RIDs to ignore
## (usually the looker itself).
static func has_line_of_sight(world: World3D, from: Vector3, to: Vector3,
		target: CollisionObject3D, exclude: Array[RID] = []) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * 0.5)
	query.collide_with_areas = true
	query.exclude = exclude
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == target
