class_name SightRays
extends RefCounted
## Many sight lines at once on worker threads (WorkerThreadPool): the same tests as
## Vision.has_line_of_sight and Vision.has_line_of_sight_through. Rays only: the threads touch nothing but the
## physics space and this object's arrays, and the caller waits for them, so no physics
## step runs meanwhile. Bots and squads ask before a look round (BotController._scan,
## Squad._scan) and read the answers instead of casting one ray at a time: 4-5 times
## faster on a 12-thread CPU (2026-11-20, 40 tanks, identical results).
##
## Per request: from, to, the target's instance id, the RIDs to leave out and
## `blockers`: -2 = Vision.has_line_of_sight (every layer, areas too), -1 or more =
## has_line_of_sight_through with that many vegetation layers seen through (-1: solid
## things only).

## Fewer requests than this run here, without threads (the hand-over costs more).
const MIN_THREADED: int = 24
const PLAIN: int = -2

var _space: PhysicsDirectSpaceState3D
var _from: PackedVector3Array = PackedVector3Array()
var _to: PackedVector3Array = PackedVector3Array()
var _target: PackedInt64Array = PackedInt64Array()
var _blockers: PackedInt32Array = PackedInt32Array()
var _exclude: Array = []
var _seen: Array = []


func _init(space: PhysicsDirectSpaceState3D) -> void:
	_space = space


func add(from: Vector3, to: Vector3, target: Object, exclude: Array[RID], blockers: int = PLAIN) -> int:
	_from.append(from)
	_to.append(to)
	_target.append(target.get_instance_id())
	_blockers.append(blockers)
	_exclude.append(exclude)
	return _from.size() - 1


func size() -> int:
	return _from.size()


## Casts them all; then seen(i) answers request i.
func run() -> void:
	var n: int = _from.size()
	_seen.resize(n)
	if n < MIN_THREADED:
		for i: int in n:
			_one(i)
		return
	var task: int = WorkerThreadPool.add_group_task(_one, n, -1, true, "sight rays")
	WorkerThreadPool.wait_for_group_task_completion(task)


func seen(i: int) -> bool:
	return bool(_seen[i])


func _one(i: int) -> void:
	var from: Vector3 = _from[i]
	var to: Vector3 = _to[i]
	var dir: Vector3 = (to - from).normalized()
	var max_blockers: int = _blockers[i]
	var query := PhysicsRayQueryParameters3D.create(from, to + dir * 0.5,
			0xFFFFFFFF if max_blockers == PLAIN else Vision.SIGHT_THROUGH_MASK)
	query.collide_with_areas = true
	query.exclude = _exclude[i]
	var hit: Dictionary = _space.intersect_ray(query)
	if hit.is_empty() or int(hit["collider_id"]) != _target[i]:
		_seen[i] = false
		return
	if max_blockers < 0:
		_seen[i] = true
		return
	# Vegetation crowns on the way (as Vision.has_line_of_sight_through).
	var stop: float = from.distance_to(hit["position"] as Vector3)
	var crowns := PhysicsRayQueryParameters3D.create(from, hit["position"], Vision.LAYER_VISION_BLOCKER)
	crowns.collide_with_areas = true
	crowns.collide_with_bodies = false
	crowns.exclude = _exclude[i]
	var count: int = 0
	var start: Vector3 = from
	var last_rid := RID()
	var last_shape: int = -1
	for k: int in max_blockers * 2 + 4:
		crowns.from = start
		var c: Dictionary = _space.intersect_ray(crowns)
		if c.is_empty():
			_seen[i] = true
			return
		var p: Vector3 = c["position"]
		if c["rid"] != last_rid or int(c["shape"]) != last_shape:
			count += 1
			if count > max_blockers:
				_seen[i] = false
				return
		last_rid = c["rid"]
		last_shape = int(c["shape"])
		start = p + dir * 0.05
		if from.distance_to(start) >= stop:
			_seen[i] = true
			return
	_seen[i] = false
