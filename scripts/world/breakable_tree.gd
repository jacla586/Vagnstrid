class_name BreakableTree
extends Node3D
## A tree tanks can push over if its trunk is thin enough for them.
##
## A push trigger around the trunk notices tanks (layer "vehicles") just before
## contact. A tank heading for the trunk fast enough fells it at once and loses some
## speed; a slow tank has to keep pushing for a while. Too thick for the tank: the
## trunk stays solid. Main-gun shells snap thin trunks too.
## Felled trees fall away from the cause, lose their trunk collision, and keep their
## canopy vision blocker (low cover). Visuals live under FallPivot/Visual, so they
## can be swapped for a model without touching the logic.

## Emitted once when the tree starts to fall (sound, effects, network sync later).
signal felled(direction: Vector3)

const KMH_TO_MS: float = 1.0 / 3.6
## A tank must point/drive this directly at the tree to count as pushing (cosine).
const PUSH_DIRECTION_COS: float = 0.5
## Throttle needed to count as pushing slowly.
const PUSH_THROTTLE: float = 0.3
## Extra lateral margin when deciding whether the tank's path hits the trunk (m).
const PATH_MARGIN_M: float = 0.1
const SNAP_MIN_CALIBER_MM: float = 20.0

@export var data: TreeData

var _felled: bool = false
var _fall_time: float = 0.0
var _fall_axis: Vector3 = Vector3.RIGHT
var _upright_basis: Basis
var _push_time: Dictionary = {}  # Tank -> seconds pushed slowly

@onready var _trunk_shape: CollisionShape3D = $Trunk/Shape
@onready var _push_trigger: Area3D = $PushTrigger
@onready var _fall_pivot: Node3D = $FallPivot


func is_felled() -> bool:
	return _felled


## Trunk diameter of this placed tree (m), including its scale.
func get_trunk_diameter() -> float:
	return data.trunk_diameter_m * global_basis.get_scale().x


## Fells the tree towards `direction` (horizontal part is used).
func fell(direction: Vector3) -> void:
	if _felled:
		return
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3.FORWARD
	horizontal = horizontal.normalized()
	_felled = true
	_trunk_shape.disabled = true
	_push_trigger.set_deferred("monitoring", false)
	# Rotating "up" around (up × direction) tips the top towards `direction`.
	_fall_axis = Vector3.UP.cross(horizontal).normalized()
	_upright_basis = _fall_pivot.global_basis
	_fall_time = 0.0
	felled.emit(horizontal)


## Called by TreeTrunk when a shell hits the trunk.
func on_shell_hit(shell_data: ShellData, velocity: Vector3) -> HitResult:
	if _felled or shell_data.caliber_mm < SNAP_MIN_CALIBER_MM \
			or get_trunk_diameter() > data.shell_snap_max_diameter_m:
		return null
	fell(velocity)
	var result := HitResult.new()
	result.note = "TREE DOWN"
	result.target = self
	return result


func _physics_process(delta: float) -> void:
	if _felled:
		_update_fall(delta)
		return
	for body: Node3D in _push_trigger.get_overlapping_bodies():
		var tank := body as Tank
		if tank != null:
			_check_push(tank, delta)
			if _felled:
				return


func _check_push(tank: Tank, delta: float) -> void:
	if get_trunk_diameter() > tank.data.tree_push_max_diameter_m:
		return  # too thick for this tank: the trunk stops it
	var to_tree := global_position - tank.global_position
	to_tree.y = 0.0
	var velocity := Vector3(tank.linear_velocity.x, 0.0, tank.linear_velocity.z)
	var speed_towards: float = velocity.dot(to_tree.normalized())
	# Fast: driving into the trunk.
	if speed_towards >= tank.data.tree_push_min_speed_kmh * KMH_TO_MS \
			and _path_hits_trunk(tank, to_tree, velocity.normalized()):
		fell(velocity)
		tank.apply_obstacle_drag(tank.data.tree_push_speed_loss)
		return
	# Slow: leaning on it with throttle.
	var forward := -tank.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var throttle: float = tank.get_throttle()
	var push_dir: Vector3 = forward if throttle >= 0.0 else -forward
	var pushing: bool = absf(throttle) >= PUSH_THROTTLE \
			and push_dir.dot(to_tree.normalized()) >= PUSH_DIRECTION_COS \
			and _path_hits_trunk(tank, to_tree, push_dir)
	if not pushing:
		_push_time.erase(tank)
		return
	_push_time[tank] = _push_time.get(tank, 0.0) + delta
	if _push_time[tank] >= tank.data.tree_slow_push_time_s:
		fell(push_dir)


## True if the trunk lies in front of the tank along `direction`, within the hull's
## width (so tanks passing close by don't fell trees they would miss).
func _path_hits_trunk(tank: Tank, to_tree: Vector3, direction: Vector3) -> bool:
	if direction.length_squared() < 0.0001 or to_tree.dot(direction) <= 0.0:
		return false
	var lateral: float = (to_tree - direction * to_tree.dot(direction)).length()
	return lateral <= tank.get_hull_half_extents().x + get_trunk_diameter() * 0.5 + PATH_MARGIN_M


## Falls with the angle growing as t² (slow start, like a real fall).
func _update_fall(delta: float) -> void:
	if _fall_time >= data.fall_time_s:
		return
	_fall_time = minf(_fall_time + delta, data.fall_time_s)
	var t: float = _fall_time / maxf(data.fall_time_s, 0.01)
	var angle: float = deg_to_rad(data.fallen_angle_deg) * t * t
	_fall_pivot.global_basis = Basis(_fall_axis, angle) * _upright_basis
