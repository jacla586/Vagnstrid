class_name Explosion
extends RefCounted
## Fragments from an exploding shell. Instead of random rays (which almost never hit
## a head and make tuning luck-based), every active fragment target in range gets a
## line-of-sight check and a hit roll: certain inside the shell's lethal radius,
## falling linearly to zero at its max radius. Cover blocks fragments.
##
## Fragment targets join group "fragment_targets" and implement:
##   is_fragment_target_active() -> bool
##   get_fragment_aim_point() -> Vector3
##   get_fragment_collider() -> CollisionObject3D
##   on_fragment_hit(shell_data: ShellData, distance: float) -> HitResult
## and optionally fragment_hit_ok(point: Vector3) -> bool, for targets that are only
## part of their collider (a tank's tracks): the fragment must strike near the target,
## fragment_shielded(origin: Vector3) -> bool, for cover that isn't a collider (the
## commander's open hatch lid), and fragment_radius_factor() -> float, for targets the
## fragments reach farther (soldiers: both radii scaled).
## Every tank of another team within ShellData.optics_dirt_radius_m gets dirt on its
## optics (Tank.add_optics_dirt; no sight line needed: the dust cloud spreads).

const TARGET_GROUP: StringName = &"fragment_targets"
## Line-of-sight rays start this far off the surface, so the plate hit doesn't block.
const SURFACE_OFFSET: float = 0.2


## Chance that fragments hit a target at `distance` (m) from the burst; `radius_factor`
## scales both radii.
static func fragment_hit_chance(shell: ShellData, distance: float, radius_factor: float = 1.0) -> float:
	var lethal: float = shell.fragment_lethal_radius_m * radius_factor
	var most: float = shell.fragment_max_radius_m * radius_factor
	if not shell.is_explosive() or distance >= most:
		return 0.0
	if distance <= lethal:
		return 1.0
	return (most - distance) / maxf(most - lethal, 0.001)


## Applies fragments around `point`. Returns the results of every target hit.
## Targets of `shooter_team` are spared (no friendly fire; -1 = spare nobody).
static func detonate(world: World3D, tree: SceneTree, point: Vector3, normal: Vector3,
		shell: ShellData, rng: RandomNumberGenerator, shooter_team: int = -1) -> Array[HitResult]:
	var results: Array[HitResult] = []
	if not shell.is_explosive():
		return results
	var origin: Vector3 = point + normal.normalized() * SURFACE_OFFSET
	for target: Node in tree.get_nodes_in_group(TARGET_GROUP):
		if not target.is_fragment_target_active():
			continue
		if shooter_team >= 0 and Tank.team_of(target) == shooter_team:
			continue
		var aim: Vector3 = target.get_fragment_aim_point()
		var distance: float = origin.distance_to(aim)
		var factor: float = target.fragment_radius_factor() if target.has_method("fragment_radius_factor") \
				else 1.0
		var chance: float = fragment_hit_chance(shell, distance, factor)
		if chance <= 0.0 or not _has_line_of_sight(world, origin, aim, target):
			continue
		if rng.randf() >= chance:
			continue
		var result: HitResult = target.on_fragment_hit(shell, distance)
		if result != null:
			results.append(result)
	_dirty_optics(tree, point, shell, shooter_team)
	return results


## Dirt over the optics of every tank of another team near the burst.
static func _dirty_optics(tree: SceneTree, point: Vector3, shell: ShellData, shooter_team: int) -> void:
	var radius: float = shell.optics_dirt_radius_m
	if radius <= 0.0:
		return
	for node: Node in tree.get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or tank.is_knocked_out() or tank.net_puppet \
				or (shooter_team >= 0 and tank.team == shooter_team):
			continue
		# From the hull's surface (about its half width), not its middle.
		var d: float = maxf(tank.global_position.distance_to(point) - tank.get_hull_radius(), 0.0)
		if d < radius:
			tank.add_optics_dirt(1.0 - d / radius)


static func _has_line_of_sight(world: World3D, from: Vector3, to: Vector3, target: Node) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * 0.5)
	query.collide_with_areas = true
	# Fragments fly through bushes; only solid things give cover.
	query.collision_mask = Vision.SHOT_MASK
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit["collider"] != target.get_fragment_collider():
		return false
	if target.has_method("fragment_shielded") and target.fragment_shielded(from):
		return false
	return not target.has_method("fragment_hit_ok") or target.fragment_hit_ok(hit["position"])
