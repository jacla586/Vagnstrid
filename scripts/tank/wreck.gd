class_name Wreck
extends RigidBody3D
## A knocked-out tank's charred hull (Tank._make_wreck), in group "wrecks". Offline and on
## the host a rigid body of TankData.wreck_mass_share of the tank's mass with grippy
## friction, so tanks can push it off a road (Tank pushes harder against tanks and wrecks,
## TankData.push_accel), but lighter than a braking tank. On clients it is frozen and
## follows the host: NetGame sends moved wrecks (send_moves) keyed by where they were made,
## which every machine knows within a metre or two (made_at, find_near).

## A host wreck counts as moved (and is sent) past this distance / angle since last sent.
const SEND_MOVE_M: float = 0.03
const SEND_TURN_RAD: float = 0.01
## Clients find their copy of a host wreck within this distance of where it was made.
const MATCH_M: float = 4.0
## Clients ease towards the host's pose at this rate (1/s).
const FOLLOW_RATE: float = 8.0
## A thrown turret's key lies this far above where it was thrown from, so a client never
## takes a turret's moves for the hull's wreck made close by.
const THROWN_KEY_LIFT_M: float = 1000.0

## Where the wreck was made (world): the key between machines.
var made_at: Vector3 = Vector3.ZERO

var _sent := Transform3D()
var _target := Transform3D()
var _following: bool = false
## A thrown turret still in the air (setup_thrown): flies undamped on every machine; at
## rest it gets its damping and, on clients, freezes and follows the host's moves.
var _thrown: bool = false
var _rest_damp: float = 0.0
var _has_target: bool = false


## Sets the wreck up at `at`: a rigid body of `body_mass` on the host, a frozen follower
## on clients.
func setup(at: Transform3D, body_mass: float, friction: float, damp: float) -> void:
	made_at = at.origin
	_sent = at
	_target = at
	collision_layer = 1
	collision_mask = 1 | 2
	add_to_group(&"wrecks")
	mass = maxf(body_mass, 100.0)
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.rough = true
	physics_material_override = pm
	linear_damp = damp
	angular_damp = damp * 2.0
	can_sleep = true
	if NetRole.is_client():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true


## A turret thrown off a knocked-out tank (Tank.toss_turret): flies on its own physics on
## every machine (each throws it from the same rpc_turret_toss), then lies as a wreck that
## tanks can push like the hull (host), clients following the host from then on.
func setup_thrown(at: Transform3D, body_mass: float, friction: float, damp: float) -> void:
	setup(at, body_mass, friction, damp)
	made_at = at.origin + Vector3.UP * THROWN_KEY_LIFT_M
	_thrown = true
	_rest_damp = damp
	linear_damp = 0.0
	angular_damp = 0.0
	freeze = false
	sleeping_state_changed.connect(_on_sleeping_changed)


## The thrown turret has come to rest (or Tank's timeout says so).
func settle() -> void:
	if not _thrown:
		return
	_thrown = false
	linear_damp = _rest_damp
	angular_damp = _rest_damp * 2.0
	if NetRole.is_client():
		set_deferred("freeze", true)
		_following = _has_target


func _on_sleeping_changed() -> void:
	if sleeping:
		settle()


## The wreck nearest `pos` within MATCH_M (null: none).
static func find_near(tree: SceneTree, pos: Vector3) -> Wreck:
	var best: Wreck = null
	var best_d: float = MATCH_M
	for node: Node in tree.get_nodes_in_group(&"wrecks"):
		var w := node as Wreck
		if w == null or w.is_queued_for_deletion():
			continue
		var d: float = w.made_at.distance_to(pos)
		if d < best_d:
			best_d = d
			best = w
	return best


## Host: the wrecks that moved since last sent: [made_at array, transform array]; marks
## them sent.
static func collect_moves(tree: SceneTree) -> Array:
	var keys := PackedVector3Array()
	var poses: Array[Transform3D] = []
	for node: Node in tree.get_nodes_in_group(&"wrecks"):
		var w := node as Wreck
		if w == null or w.is_queued_for_deletion():
			continue
		var t: Transform3D = w.global_transform
		if t.origin.distance_to(w._sent.origin) < SEND_MOVE_M \
				and t.basis.get_rotation_quaternion().angle_to(w._sent.basis.get_rotation_quaternion()) < SEND_TURN_RAD:
			continue
		w._sent = t
		keys.append(w.made_at)
		poses.append(t)
	return [keys, poses]


## Client: the host moved the wreck made at `key` to `pose`.
static func apply_move(tree: SceneTree, key: Vector3, pose: Transform3D) -> void:
	var w: Wreck = find_near(tree, key)
	if w != null:
		w._target = pose
		w._has_target = true
		w._following = not w._thrown   # a turret still flying lands by itself first


func _physics_process(delta: float) -> void:
	if not _following:
		return
	var t: Transform3D = global_transform.interpolate_with(_target,
			clampf(FOLLOW_RATE * delta, 0.0, 1.0))
	global_transform = t
	if t.origin.distance_to(_target.origin) < 0.005:
		global_transform = _target
		_following = false
