class_name TargetTankController
extends Node
## Drives a target tank on the test bench through TankCommand (same path as the
## player and future bots). Stands still or patrols back and forth between
## waypoints. Never aims or fires. Repairs the tank a while after a knock-out.

enum Mode { STATIONARY, PATROL }

## Waypoints count as reached within this distance (m).
const WAYPOINT_RADIUS: float = 8.0
## Heading error (radians) that gives full steering.
const FULL_STEER_ERROR: float = 0.6

@export var tank: Tank
@export var mode: Mode = Mode.STATIONARY
## World-space points driven to in order, then back again.
@export var waypoints: Array[Vector3] = []
@export_range(0.0, 1.0) var patrol_throttle: float = 0.5
## Test bench: seconds after a knock-out until the tank is repaired. 0 = never.
@export var respawn_delay_s: float = 10.0
## Turn on the spot when the next waypoint is more than this far off the heading
## (degrees), e.g. turning around at the end of a narrow street. 0 = off (wide arcs).
@export_range(0.0, 180.0) var pivot_turn_deg: float = 0.0
## Reverse for a moment after standing still this long with throttle (s). 0 = off.
@export var unstick_after_s: float = 0.0
@export var unstick_reverse_s: float = 2.0

## Averaging less than this over unstick_after_s with throttle counts as stuck (m/s).
## Measured as distance covered, so a tank bouncing in place on a slope counts too.
const STUCK_SPEED: float = 0.5

var _command: TankCommand = TankCommand.new()
var _waypoint_index: int = 0
var _direction: int = 1
var _respawn_timer: float = 0.0
var _stuck_time: float = 0.0
var _stuck_check_position: Vector3 = Vector3.ZERO
var _reverse_time: float = 0.0


func _physics_process(delta: float) -> void:
	if tank == null:
		return
	if tank.is_knocked_out():
		_update_respawn(delta)
		return
	_command.throttle = 0.0
	_command.steering = 0.0
	_patrol_step(delta)
	tank.set_command(_command)


func get_waypoint_index() -> int:
	return _waypoint_index


## Sets throttle and steering for one frame of patrolling (no-op when stationary).
func _patrol_step(delta: float) -> void:
	if mode != Mode.PATROL or waypoints.size() < 2:
		return
	if _reverse_time > 0.0:
		_reverse_time -= delta
		_command.throttle = -patrol_throttle
	else:
		_drive_patrol()
		_update_stuck(delta)


func _update_respawn(delta: float) -> void:
	if respawn_delay_s <= 0.0:
		return
	_respawn_timer += delta
	if _respawn_timer >= respawn_delay_s:
		_respawn_timer = 0.0
		tank.repair()


func _drive_patrol() -> void:
	if _steer_towards(waypoints[_waypoint_index], patrol_throttle):
		if _waypoint_index + _direction < 0 or _waypoint_index + _direction >= waypoints.size():
			_direction = -_direction
		_waypoint_index += _direction


## Sets steering and throttle towards `target` for this frame. Returns true (and
## leaves the command alone) once the target is within WAYPOINT_RADIUS.
func _steer_towards(target: Vector3, throttle: float) -> bool:
	var to_target: Vector3 = target - tank.global_position
	to_target.y = 0.0
	if to_target.length() < WAYPOINT_RADIUS:
		return true
	var forward: Vector3 = -tank.global_basis.z
	forward.y = 0.0
	# Positive error = target to the left; steering +1 is right.
	var error: float = forward.signed_angle_to(to_target, Vector3.UP)
	if pivot_turn_deg > 0.0 and absf(error) > deg_to_rad(pivot_turn_deg):
		_command.steering = -signf(error)
		_command.throttle = 0.0
		return false
	_command.steering = clampf(-error / FULL_STEER_ERROR, -1.0, 1.0)
	# Slow down in sharp turns.
	_command.throttle = throttle * clampf(1.0 - absf(error) / PI * 1.5, 0.2, 1.0)
	return false


func _update_stuck(delta: float) -> void:
	if unstick_after_s <= 0.0 or absf(_command.throttle) < 0.01:
		_stuck_time = 0.0
		_stuck_check_position = tank.global_position
		return
	_stuck_time += delta
	if _stuck_time < unstick_after_s:
		return
	var moved: Vector3 = tank.global_position - _stuck_check_position
	moved.y = 0.0
	_stuck_time = 0.0
	_stuck_check_position = tank.global_position
	if moved.length() < STUCK_SPEED * unstick_after_s:
		_reverse_time = unstick_reverse_s
		_on_stuck()


## Called when the tank is found stuck, as it starts reversing. Override to replan.
func _on_stuck() -> void:
	pass
