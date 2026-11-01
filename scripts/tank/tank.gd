class_name Tank
extends RigidBody3D
## A tracked vehicle. Acts only on TankCommand; never reads input directly.
##
## Suspension: RayCast3D children of $Suspension act as road wheels. Each grounded
## ray pushes the hull up with a spring + damper force.
## Driving: the command is turned into a target forward speed and yaw rate. The
## needed force/torque (limited by the data's accelerations) is split into a left and
## right track force, applied at the grounded wheels' contact points.

const KMH_TO_MS: float = 1.0 / 3.6

@export var data: TankData

var _command: TankCommand = TankCommand.new()
var _left_rays: Array[RayCast3D] = []
var _right_rays: Array[RayCast3D] = []
var _track_half_width: float = 1.0

@onready var _suspension: Node3D = $Suspension


func _ready() -> void:
	assert(data != null, "Tank needs a TankData resource")
	mass = data.mass_kg
	var width_sum: float = 0.0
	for child: Node in _suspension.get_children():
		var ray := child as RayCast3D
		if ray == null:
			continue
		ray.add_exception(self)
		ray.target_position = Vector3(0.0, -data.suspension_rest_length, 0.0)
		width_sum += absf(ray.position.x)
		if ray.position.x < 0.0:
			_left_rays.append(ray)
		else:
			_right_rays.append(ray)
	var ray_count: int = _left_rays.size() + _right_rays.size()
	assert(ray_count > 0, "Tank needs RayCast3D children under Suspension")
	_track_half_width = maxf(width_sum / ray_count, 0.1)


func set_command(command: TankCommand) -> void:
	_command = command


## Speed along the hull's forward axis (m/s), negative when reversing.
func get_forward_speed() -> float:
	return linear_velocity.dot(-global_basis.z)


func _physics_process(delta: float) -> void:
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(get_rid())
	if state == null:
		return
	var ray_count: int = _left_rays.size() + _right_rays.size()
	var left_points: Array[Vector3] = []
	var left_normals: Array[Vector3] = []
	var right_points: Array[Vector3] = []
	var right_normals: Array[Vector3] = []
	_apply_suspension(state, _left_rays, ray_count, left_points, left_normals)
	_apply_suspension(state, _right_rays, ray_count, right_points, right_normals)

	var grounded: int = left_points.size() + right_points.size()
	if grounded == 0:
		return
	_apply_drive(state, delta, left_points, left_normals, right_points, right_normals)

	# Tracks resist sideways sliding, in proportion to how many wheels touch ground.
	var right_dir: Vector3 = global_basis.x
	var lateral_speed: float = linear_velocity.dot(right_dir)
	var lateral_accel: float = clampf(-lateral_speed / delta,
			-data.track_lateral_grip, data.track_lateral_grip)
	lateral_accel *= float(grounded) / float(ray_count)
	apply_central_force(right_dir * lateral_accel * mass)


func _apply_suspension(state: PhysicsDirectBodyState3D, rays: Array[RayCast3D],
		ray_count: int, points: Array[Vector3], normals: Array[Vector3]) -> void:
	var omega: float = TAU * data.suspension_frequency_hz
	var stiffness: float = mass * omega * omega / ray_count
	var damping: float = 2.0 * data.suspension_damping_ratio * mass * omega / ray_count
	var com_global: Vector3 = global_position + state.center_of_mass
	for ray: RayCast3D in rays:
		ray.force_raycast_update()
		if not ray.is_colliding():
			continue
		var point: Vector3 = ray.get_collision_point()
		var up: Vector3 = ray.global_basis.y
		var compression: float = data.suspension_rest_length - ray.global_position.distance_to(point)
		var point_velocity: Vector3 = linear_velocity + angular_velocity.cross(point - com_global)
		var force: float = stiffness * compression - damping * point_velocity.dot(up)
		apply_force(up * maxf(force, 0.0), point - global_position)
		points.append(point)
		normals.append(ray.get_collision_normal())


func _apply_drive(state: PhysicsDirectBodyState3D, delta: float,
		left_points: Array[Vector3], left_normals: Array[Vector3],
		right_points: Array[Vector3], right_normals: Array[Vector3]) -> void:
	var forward: Vector3 = -global_basis.z
	var up: Vector3 = global_basis.y

	# Longitudinal: chase the target speed, limited by acceleration / braking.
	var throttle: float = clampf(_command.throttle, -1.0, 1.0)
	var top_speed_kmh: float = data.max_forward_speed_kmh if throttle >= 0.0 else data.max_reverse_speed_kmh
	var target_speed: float = throttle * top_speed_kmh * KMH_TO_MS
	var speed: float = linear_velocity.dot(forward)
	var speeding_up: bool = target_speed * speed >= 0.0 and absf(target_speed) > absf(speed)
	var accel_limit: float = data.acceleration if speeding_up else data.brake_deceleration
	var accel: float = clampf((target_speed - speed) / delta, -accel_limit, accel_limit)
	var drive_force: float = mass * accel

	# Yaw: chase the target turn rate. Positive yaw (around +Y) turns left.
	var steering: float = clampf(_command.steering, -1.0, 1.0)
	var target_yaw_rate: float = -steering * deg_to_rad(data.max_turn_rate_deg)
	var yaw_rate: float = angular_velocity.dot(up)
	var turn_limit: float = deg_to_rad(data.turn_acceleration_deg)
	var yaw_accel: float = clampf((target_yaw_rate - yaw_rate) / delta, -turn_limit, turn_limit)
	var yaw_inertia: float = 1.0 / maxf((state.inverse_inertia_tensor * up).dot(up), 1e-9)
	var yaw_torque: float = yaw_accel * yaw_inertia

	# Skid steer: right track pushing harder turns the tank left, and vice versa.
	var track_split: float = yaw_torque / (2.0 * _track_half_width)
	_apply_track_force(drive_force * 0.5 - track_split, forward, left_points, left_normals)
	_apply_track_force(drive_force * 0.5 + track_split, forward, right_points, right_normals)


func _apply_track_force(force: float, forward: Vector3,
		points: Array[Vector3], normals: Array[Vector3]) -> void:
	if points.is_empty():
		return
	var per_wheel: float = force / points.size()
	for i: int in points.size():
		var normal: Vector3 = normals[i]
		var direction: Vector3 = (forward - normal * forward.dot(normal)).normalized()
		apply_force(direction * per_wheel, points[i] - global_position)
