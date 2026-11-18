class_name TreePush
extends RefCounted
## The push-over rule for the laser trees of real maps (TreeField), as plain functions.
## Keep it in step with BreakableTree._check_push / _path_hits_trunk (hills.tscn), which
## follows the same rule with the same constants and tank data; they can be merged later.

const KMH_TO_MS: float = 1.0 / 3.6
## A tank must point/drive this directly at the tree to count as pushing (cosine).
const PUSH_DIRECTION_COS: float = 0.5
## Throttle needed to count as pushing slowly.
const PUSH_THROTTLE: float = 0.3
## Extra lateral margin when deciding whether the tank's path hits the trunk (m).
const PATH_MARGIN_M: float = 0.1


## Direction the tree at `tree_position` should fall because of `tank`, or ZERO if it
## stands. Fast: the tank drives into it (and loses some speed). Slow: the tank leans
## on it with throttle for a while; `push_time` keeps the seconds per `key`.
static func push_direction(tank: Tank, tree_position: Vector3, trunk_diameter: float,
		delta: float, push_time: Dictionary, key: Variant) -> Vector3:
	if trunk_diameter > tank.data.tree_push_max_diameter_m:
		return Vector3.ZERO  # too thick for this tank: the trunk stops it
	var to_tree := tree_position - tank.global_position
	to_tree.y = 0.0
	var velocity := Vector3(tank.linear_velocity.x, 0.0, tank.linear_velocity.z)
	var speed_towards: float = velocity.dot(to_tree.normalized())
	if speed_towards >= tank.data.tree_push_min_speed_kmh * KMH_TO_MS \
			and path_hits_trunk(tank, to_tree, velocity.normalized(), trunk_diameter):
		push_time.erase(key)
		tank.apply_obstacle_drag(tank.data.tree_push_speed_loss)
		return fall_direction(tank, to_tree, velocity.normalized())
	var forward := -tank.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var throttle: float = tank.get_throttle()
	var push_dir: Vector3 = forward if throttle >= 0.0 else -forward
	var pushing: bool = absf(throttle) >= PUSH_THROTTLE \
			and push_dir.dot(to_tree.normalized()) >= PUSH_DIRECTION_COS \
			and path_hits_trunk(tank, to_tree, push_dir, trunk_diameter)
	if not pushing:
		push_time.erase(key)
		return Vector3.ZERO
	push_time[key] = float(push_time.get(key, 0.0)) + delta
	if push_time[key] >= tank.data.tree_slow_push_time_s:
		push_time.erase(key)
		return fall_direction(tank, to_tree, push_dir)
	return Vector3.ZERO


## Where a tree pushed along `direction` (flat, unit) falls: turned off the tank's path
## towards the side of the hull's centre line the trunk was struck on (TankData
## tree_fall_*), so felled trees don't lie across the way and block the view ahead.
static func fall_direction(tank: Tank, to_tree: Vector3, direction: Vector3) -> Vector3:
	var right: Vector3 = direction.cross(Vector3.UP)
	var offset: float = to_tree.dot(right) / maxf(tank.get_hull_half_extents().x, 0.1)
	var side: float = signf(offset)
	if absf(offset) < 0.05:
		side = 1.0 if randf() < 0.5 else -1.0
	var d: TankData = tank.data
	var angle: float = lerpf(d.tree_fall_side_min_deg, d.tree_fall_side_max_deg,
			clampf(absf(offset), 0.0, 1.0)) + randf_range(-1.0, 1.0) * d.tree_fall_jitter_deg
	# Positive rotation about UP turns left; `right` is the positive side of the offset.
	return direction.rotated(Vector3.UP, -side * deg_to_rad(maxf(angle, 0.0)))


## True if the trunk lies in front of the tank along `direction`, within the hull's
## width (so tanks passing close by don't fell trees they would miss).
static func path_hits_trunk(tank: Tank, to_tree: Vector3, direction: Vector3,
		trunk_diameter: float) -> bool:
	if direction.length_squared() < 0.0001 or to_tree.dot(direction) <= 0.0:
		return false
	var lateral: float = (to_tree - direction * to_tree.dot(direction)).length()
	return lateral <= tank.get_hull_half_extents().x + trunk_diameter * 0.5 + PATH_MARGIN_M
