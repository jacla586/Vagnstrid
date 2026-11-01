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

var _command: TankCommand = TankCommand.new()
var _waypoint_index: int = 0
var _direction: int = 1
var _respawn_timer: float = 0.0


func _physics_process(delta: float) -> void:
	if tank == null:
		return
	if tank.is_knocked_out():
		_update_respawn(delta)
		return
	_command.throttle = 0.0
	_command.steering = 0.0
	if mode == Mode.PATROL and waypoints.size() >= 2:
		_drive_patrol()
	tank.set_command(_command)


func get_waypoint_index() -> int:
	return _waypoint_index


func _update_respawn(delta: float) -> void:
	if respawn_delay_s <= 0.0:
		return
	_respawn_timer += delta
	if _respawn_timer >= respawn_delay_s:
		_respawn_timer = 0.0
		tank.repair()


func _drive_patrol() -> void:
	var target: Vector3 = waypoints[_waypoint_index]
	var to_target: Vector3 = target - tank.global_position
	to_target.y = 0.0
	if to_target.length() < WAYPOINT_RADIUS:
		if _waypoint_index + _direction < 0 or _waypoint_index + _direction >= waypoints.size():
			_direction = -_direction
		_waypoint_index += _direction
		return
	var forward: Vector3 = -tank.global_basis.z
	forward.y = 0.0
	# Positive error = target to the left; steering +1 is right.
	var error: float = forward.signed_angle_to(to_target, Vector3.UP)
	_command.steering = clampf(-error / FULL_STEER_ERROR, -1.0, 1.0)
	# Slow down in sharp turns.
	_command.throttle = patrol_throttle * clampf(1.0 - absf(error) / PI * 1.5, 0.2, 1.0)
