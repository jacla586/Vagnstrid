class_name Squad
extends Node3D
## An infantry squad riding on a tank (TankData.squad): one unit of a few soldiers.
## It never reads input: the tank passes on its command's squad orders (move to a
## point, recall). Mounted it rides along unseen; sent out it gets off behind the
## tank and runs along a path for walkers (TacticalMap with the squad's tactics:
## forest cheap, open ground dear), never further than max_distance_from_tank_m from
## the tank; recalled (or left behind by its tank) it runs back and mounts.
## Lives in the map next to its tank, not under it (the tank moves on).
## Holding still the soldiers kneel and watch all round (hedgehog); moving they stand
## and face the way they go. The leader is the first living soldier (the player can
## look through his eyes, PlayerViews squad view).

enum State { MOUNTED, MOVING, HOLDING, RETURNING }

## Orders in TankCommand.squad_order.
const ORDER_NONE: int = 0
const ORDER_MOVE: int = 1
const ORDER_RECALL: int = 2
## A waypoint counts as reached this close (m).
const WAYPOINT_RADIUS_M: float = 3.0
## Soldiers turn towards where they go this fast (radians/s).
const TURN_RATE: float = 4.0
## Re-plan the way back to a moving tank this often (s).
const RETURN_REPLAN_S: float = 3.0

var tank: Tank
var data: SquadData

var _state: State = State.MOUNTED
var _path: Array[Vector3] = []
var _goal: Vector3 = Vector3.ZERO
var _heading: Vector3 = Vector3.FORWARD
var _soldiers: Array[Node3D] = []
var _replan_timer: float = 0.0
var _map: TacticalMap
var _map_looked_up: bool = false
## 0 = standing, 1 = kneeling (eases between).
var _kneel: float = 0.0
## Soldiers still alive, in leader order (all of them until there is combat).
var _alive: Array[bool] = []


func _ready() -> void:
	add_to_group("squads")
	for i: int in data.soldier_count:
		var soldier := _make_soldier()
		add_child(soldier)
		_soldiers.append(soldier)
		_alive.append(true)
	visible = false


func get_state() -> State:
	return _state


func is_mounted() -> bool:
	return _state == State.MOUNTED


func get_team() -> int:
	return tank.team if is_instance_valid(tank) else -1


func get_heading() -> Vector3:
	return _heading


## The leader: the first living soldier (null if none).
func get_leader() -> Node3D:
	for i: int in _soldiers.size():
		if _alive[i]:
			return _soldiers[i]
	return null


## The leader's eyes (world): lower when kneeling.
func get_leader_eye() -> Vector3:
	var leader: Node3D = get_leader()
	var at: Vector3 = leader.global_position if leader != null else global_position
	return at + Vector3.UP * lerpf(data.eye_height_standing_m, data.eye_height_kneeling_m, _kneel)


func is_kneeling() -> bool:
	return _kneel >= 0.5


## Where it is going (for the map), or its own position when holding.
func get_goal() -> Vector3:
	return _goal if _state == State.MOVING or _state == State.RETURNING else global_position


## From the tank, each physics frame its command carries an order.
func order(kind: int, target: Vector3) -> void:
	if not is_instance_valid(tank) or tank.is_knocked_out():
		return
	match kind:
		ORDER_MOVE:
			if _state == State.MOUNTED:
				_dismount()
			_move_to(_clamp_to_tank(target))
		ORDER_RECALL:
			if _state != State.MOUNTED:
				_start_return()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(tank):
		queue_free()
		return
	if _state == State.MOUNTED:
		global_position = tank.global_position
		return
	if tank.is_knocked_out():
		# The tank is gone: the squad stays where it is (later: walks back to the spawn).
		_state = State.HOLDING
	var to_tank: float = _flat(tank.global_position - global_position).length()
	if _state != State.RETURNING and to_tank > data.max_distance_from_tank_m + data.leash_margin_m \
			and not tank.is_knocked_out():
		_start_return()
	if _state == State.RETURNING:
		if to_tank <= data.mount_distance_m:
			_mount()
			return
		_replan_timer -= delta
		if _replan_timer <= 0.0:
			_replan_timer = RETURN_REPLAN_S
			_path = _plan(tank.global_position)
	if _state == State.MOVING or _state == State.RETURNING:
		_walk(delta)
	_place_soldiers(delta)


func _dismount() -> void:
	var back: Vector3 = tank.global_basis.z
	back.y = 0.0
	global_position = tank.global_position + back.normalized() * data.dismount_behind_m
	_heading = -back.normalized()
	_state = State.HOLDING
	visible = true
	_snap_soldiers()


func _mount() -> void:
	_state = State.MOUNTED
	_path.clear()
	visible = false


func _move_to(target: Vector3) -> void:
	_goal = target
	_path = _plan(target)
	_state = State.MOVING


func _start_return() -> void:
	_state = State.RETURNING
	_goal = tank.global_position
	_path = _plan(_goal)
	_replan_timer = RETURN_REPLAN_S


## Orders further than max_distance_from_tank_m from the tank are pulled in to it.
func _clamp_to_tank(target: Vector3) -> Vector3:
	var offset: Vector3 = _flat(target - tank.global_position)
	if offset.length() > data.max_distance_from_tank_m:
		offset = offset.normalized() * data.max_distance_from_tank_m
	return tank.global_position + offset


func _plan(target: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var map: TacticalMap = _tactical_map()
	if map != null:
		for p: Vector3 in map.find_path(global_position, target):
			points.append(p)
	if points.is_empty():
		points.append(target)
	return points


func _tactical_map() -> TacticalMap:
	if not _map_looked_up:
		_map_looked_up = true
		_map = TacticalMap.for_scene(get_tree().current_scene, data.tactics)
	return _map


func _walk(delta: float) -> void:
	if _path.is_empty():
		if _state == State.MOVING:
			_state = State.HOLDING
		return
	var to_next: Vector3 = _flat(_path[0] - global_position)
	if to_next.length() <= WAYPOINT_RADIUS_M:
		_path.remove_at(0)
		return
	var dir: Vector3 = to_next.normalized()
	_heading = _heading.slerp(dir, minf(delta * TURN_RATE, 1.0)).normalized()
	var p: Vector3 = global_position + dir * minf(data.run_speed_mps * delta, to_next.length())
	p.y = _ground_height(p, global_position.y)
	global_position = p


## Soldiers in a loose wedge behind the squad's point, facing its heading, on the
## ground; kneeling while the squad holds still.
func _place_soldiers(delta: float) -> void:
	var moving: bool = (_state == State.MOVING or _state == State.RETURNING) and not _path.is_empty()
	var step: float = delta / maxf(data.stance_change_s, 0.01)
	_kneel = move_toward(_kneel, 0.0 if moving else 1.0, step)
	var height_scale: float = lerpf(1.0, data.kneel_height_share, _kneel)
	var side: Vector3 = _heading.cross(Vector3.UP).normalized()
	for i: int in _soldiers.size():
		var row: int = (i + 1) >> 1
		var lateral: float = row * (1.0 if i % 2 == 1 else -1.0)
		var p: Vector3 = global_position - _heading * row * data.spacing_m \
				+ side * lateral * data.spacing_m
		p.y = _ground_height(p, global_position.y)
		var soldier: Node3D = _soldiers[i]
		soldier.global_position = p
		# Hedgehog: kneeling, each soldier watches his own direction all round.
		var facing: Vector3 = _heading.rotated(Vector3.UP, TAU * i / maxf(_soldiers.size(), 1) * _kneel)
		soldier.look_at(p + facing, Vector3.UP)
		soldier.scale = Vector3(1.0, height_scale, 1.0)


func _snap_soldiers() -> void:
	global_position.y = _ground_height(global_position, global_position.y)
	_place_soldiers(0.0)


## Ground (terrain, a bridge deck...) under `p`; tree trunks and tanks don't count.
func _ground_height(p: Vector3, fallback: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 30.0, p.z),
			Vector3(p.x, p.y - 60.0, p.z))
	query.collision_mask = 1
	var exclude: Array[RID] = []
	for i: int in 4:
		query.exclude = exclude
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return fallback
		var collider: Object = hit["collider"]
		if collider is TreeField or collider is Tank:
			exclude.append(hit["rid"])
			continue
		return (hit["position"] as Vector3).y
	return fallback


## Placeholder soldier: a capsule in the squad's uniform colour, standing on the ground.
func _make_soldier() -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = data.soldier_height_m
	capsule.radius = data.soldier_radius_m
	mesh.mesh = capsule
	var material := StandardMaterial3D.new()
	material.albedo_color = data.uniform_color
	material.roughness = 0.9
	mesh.material_override = material
	mesh.position = Vector3(0.0, data.soldier_height_m * 0.5, 0.0)
	root.add_child(mesh)
	return root


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
