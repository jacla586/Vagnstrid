class_name BotGroup
extends Node
## A group of bots advancing on an objective: in column along a route until anyone
## makes contact, then spread out line abreast across the advance and push on to the
## objective, fighting with short halts (BotController). Contacts are shared over the
## radio (spotting is shared within a team), but each bot still has to see an enemy
## itself before it shoots.

## Emitted once, when the group leaves the column and spreads out.
signal deployed

const DEPLOY_DEPTH_M: float = 80.0
## Points where the ground is lower than this are sea (m).
const SEA_LEVEL_LIMIT_M: float = 0.5
## Steps used to pull a spread-out point back towards land.
const LAND_SEARCH_STEPS: int = 10

@export var members: Array[BotController] = []
## Column route, start to end (world space). Each member drives the part ahead of it.
@export var route: Array[Vector3] = []
## What the group advances on (world space).
@export var objective: Vector3 = Vector3.ZERO
@export_range(0.0, 1.0) var column_throttle: float = 0.5
@export_range(0.0, 1.0) var deployed_throttle: float = 0.6
## Distance between neighbours when spread out (m).
@export var spread_spacing_m: float = 60.0
## Spread at the objective as a share of the spread on the way.
@export_range(0.0, 1.0) var objective_spread_scale: float = 0.5

var _deployed: bool = false


func _ready() -> void:
	for member: BotController in members:
		member.contact.connect(_on_contact.bind(member))
	# Give the orders once every member and its tank is ready.
	_start_column.call_deferred()


func is_deployed() -> bool:
	return _deployed


func _start_column() -> void:
	for member: BotController in members:
		member.order_move(_route_ahead_of(member.tank.global_position), column_throttle)


## The rest of the route from the point nearest to `position`.
func _route_ahead_of(position: Vector3) -> Array[Vector3]:
	var nearest: int = 0
	var best: float = INF
	for i: int in route.size():
		var d: float = _flat(route[i] - position).length()
		if d < best:
			best = d
			nearest = i
	# Skip the nearest point if it's behind the tank (already passed).
	if nearest + 1 < route.size() and _flat(route[nearest + 1] - position).length() \
			< _flat(route[nearest + 1] - route[nearest]).length():
		nearest += 1
	return route.slice(nearest)


func _on_contact(enemy: Tank, at: Vector3, reporter: BotController) -> void:
	for member_v: Variant in members:
		var member: BotController = (member_v as BotController) if is_instance_valid(member_v) else null
		if member != reporter and is_instance_valid(member) and not member.tank.is_knocked_out():
			member.share_contact(enemy, at)
	if not _deployed:
		_deploy()


## Line abreast across the advance: members keep their left-to-right order.
func _deploy() -> void:
	_deployed = true
	var alive: Array[BotController] = []
	var centre := Vector3.ZERO
	for member_v: Variant in members:
		var member: BotController = (member_v as BotController) if is_instance_valid(member_v) else null
		if is_instance_valid(member) and not member.tank.is_knocked_out():
			alive.append(member)
			centre += member.tank.global_position
	if alive.is_empty():
		return
	centre /= alive.size()
	var forward: Vector3 = _flat(objective - centre).normalized()
	var side: Vector3 = forward.cross(Vector3.UP).normalized()
	alive.sort_custom(func(a: BotController, b: BotController) -> bool:
		return a.tank.global_position.dot(side) < b.tank.global_position.dot(side))
	for i: int in alive.size():
		var offset: float = (float(i) - (alive.size() - 1) * 0.5) * spread_spacing_m
		var position: Vector3 = alive[i].tank.global_position
		var spread_point: Vector3 = _on_land(
				centre + forward * (position - centre).dot(forward) + forward * DEPLOY_DEPTH_M
				+ side * offset, position)
		var final_point: Vector3 = _on_land(
				objective + side * offset * objective_spread_scale, objective)
		var points: Array[Vector3] = [spread_point, final_point]
		alive[i].order_move(points, deployed_throttle)
	deployed.emit()


## `point` if it's on land, else moved step by step towards `fallback` until it is.
func _on_land(point: Vector3, fallback: Vector3) -> Vector3:
	for step: int in LAND_SEARCH_STEPS + 1:
		var candidate: Vector3 = point.lerp(fallback, float(step) / LAND_SEARCH_STEPS)
		var height: float = _ground_height(candidate)
		if height >= SEA_LEVEL_LIMIT_M:
			return Vector3(candidate.x, height, candidate.z)
	return fallback


func _ground_height(point: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 500.0, point.z),
			Vector3(point.x, -50.0, point.z), 1)
	var hit: Dictionary = get_viewport().get_world_3d().direct_space_state.intersect_ray(query)
	return float(hit["position"].y) if not hit.is_empty() else -1.0


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
