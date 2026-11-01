class_name Tank
extends RigidBody3D
## A tracked vehicle. Acts only on TankCommand; never reads input directly.
##
## Suspension: RayCast3D children of $Suspension act as road wheels. Each grounded
## ray pushes the hull up with a spring + damper force.
## Driving: the command is turned into a target forward speed and yaw rate. The
## needed force/torque (limited by the data's accelerations) is split into a left and
## right track force, applied at the grounded wheels' contact points.
## Turret: turns toward the command's aim point at the data's traverse/elevation speed.
## No stabilization: when the hull turns, the turret has to catch up.
## Hatch: opens/closes toward the command's hatch_open over the data's transition
## time. The commander is exposed whenever the hatch isn't fully closed.
## Gun: fires the data's main shell when the command says fire and it's loaded,
## then reloads. Recoil is an impulse at the muzzle. Switching ammo type empties
## the breech and starts a full reload of the new type.
## Armour: shells call on_shell_hit(); the hit zone comes from the collision shape
## and the hit normal, and Armour decides the outcome. For now one penetration
## knocks the tank out: it ignores commands, turns charred and smokes.
## Commander: while exposed, a hitbox follows his head. A hit wounds him: the hatch
## slams shut and stays locked for the data's wound time.

## Emitted after a shot leaves the barrel.
signal fired(shell: Shell)
## Emitted when a shell this tank fired lands. `result` is null for a plain hit.
signal shot_landed(result: HitResult)
## Emitted when this tank is knocked out.
signal knocked_out
## Emitted when the exposed commander is hit.
signal commander_wounded

const KMH_TO_MS: float = 1.0 / 3.6
const SHELL_SCENE: PackedScene = preload("res://scenes/weapons/shell.tscn")
const MUZZLE_FLASH_SCENE: PackedScene = preload("res://scenes/effects/muzzle_flash.tscn")
const BURNING_SCENE: PackedScene = preload("res://scenes/effects/burning.tscn")
## Normals steeper than this (Y in local space) count as roof/belly.
const ROOF_NORMAL_Y: float = 0.7
const CHARRED_COLOR: Color = Color(0.08, 0.08, 0.075)
## Commander hitbox centre sits this far below his eyes (m).
const COMMANDER_HITBOX_DROP: float = 0.35
## Visual only: how far the hatch lid swings open.
const HATCH_OPEN_ANGLE_DEG: float = 110.0

@export var data: TankData
## Visual only: paint colour for this tank. Alpha 0 keeps the scene's paint.
@export var paint_color: Color = Color(0.0, 0.0, 0.0, 0.0)

var _command: TankCommand = TankCommand.new()
var _left_rays: Array[RayCast3D] = []
var _right_rays: Array[RayCast3D] = []
var _track_half_width: float = 1.0
var _hatch_progress: float = 0.0
var _reload_remaining: float = 0.0
## Index into data.ammo of the shell in the breech (or being loaded).
var _ammo_index: int = 0
var _knocked_out: bool = false
var _commander_wound_remaining: float = 0.0
var _idle_command: TankCommand = TankCommand.new()
var _burning: Node3D
var _paint_override: StandardMaterial3D
var _charred_material: StandardMaterial3D

@onready var _suspension: Node3D = $Suspension
@onready var _turret: Node3D = $Visual/Turret
@onready var _gun_pivot: Node3D = $Visual/Turret/GunPivot
@onready var _hatch_hinge: Node3D = $Visual/Turret/Cupola/HatchHinge
@onready var _head_closed: Marker3D = $Visual/Turret/Cupola/HeadClosed
@onready var _head_open: Marker3D = $Visual/Turret/Cupola/HeadOpen
@onready var _gunner_sight: Marker3D = $Visual/Turret/GunPivot/GunnerSight
@onready var _muzzle: Marker3D = $Visual/Turret/GunPivot/Muzzle
@onready var _visual: Node3D = $Visual
@onready var _commander_hitbox: CommanderHitbox = $Visual/Turret/Cupola/CommanderHitbox
@onready var _commander_hitbox_shape: CollisionShape3D = \
		$Visual/Turret/Cupola/CommanderHitbox/Shape
@onready var _hull_shape: CollisionShape3D = $HullShape
@onready var _turret_shape: CollisionShape3D = $TurretShape


func _ready() -> void:
	assert(data != null, "Tank needs a TankData resource")
	add_to_group("tanks")
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
	_align_gunner_sight()
	_setup_paint()


## Boresights the gunner's sight: tilts it so its line of sight crosses the gun's
## bore at the zeroing range. Both markers live in GunPivot space.
func _align_gunner_sight() -> void:
	if data.sight_zero_range_m <= 0.0:
		return
	var bore_point: Vector3 = _muzzle.position \
			+ _muzzle.basis * Vector3.FORWARD * data.sight_zero_range_m
	_gunner_sight.basis = Basis.looking_at(bore_point - _gunner_sight.position)


func set_command(command: TankCommand) -> void:
	_command = command


## Throttle commanded this frame (-1..1).
func get_throttle() -> float:
	return _command.throttle


## Half size of the hull's collision box (m): x = half width, z = half length.
func get_hull_half_extents() -> Vector3:
	var box := _hull_shape.shape as BoxShape3D
	return box.size * 0.5 if box != null else Vector3.ONE


## Takes `fraction` of the horizontal speed away (e.g. felling a tree). Physics
## contact, not input: the command rule still holds.
func apply_obstacle_drag(fraction: float) -> void:
	var horizontal := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	apply_central_impulse(-horizontal * clampf(fraction, 0.0, 1.0) * mass)


func is_knocked_out() -> bool:
	return _knocked_out


func is_commander_wounded() -> bool:
	return _commander_wound_remaining > 0.0


func get_commander_wound_remaining() -> float:
	return _commander_wound_remaining


func get_commander_hitbox() -> CommanderHitbox:
	return _commander_hitbox


## Centre of the commander's hitbox (head and shoulders) in world space.
func get_commander_hitbox_position() -> Vector3:
	return _commander_hitbox.global_position


## Called by the commander hitbox when something hits the exposed commander.
func on_commander_hit(_shell_data: ShellData, _point: Vector3) -> HitResult:
	if not is_commander_exposed():
		return null
	_commander_wound_remaining = data.commander_wound_time_s
	# The hatch slams shut: no second hit while it swings closed.
	_hatch_progress = 0.0
	_update_hatch(0.0)
	_update_commander_hitbox()
	commander_wounded.emit()
	var result := HitResult.new()
	result.outcome = HitResult.Outcome.COMMANDER_HIT
	result.part = "commander"
	result.target = self
	return result


## Called by Shell when a shell hits this tank. Returns what happened.
func on_shell_hit(shell_data: ShellData, _point: Vector3, normal: Vector3,
		velocity: Vector3, shape: int = -1) -> HitResult:
	if data.armour == null:
		return null
	var part: String = "hull"
	var reference: Basis = global_basis
	if _shape_node(shape) == _turret_shape:
		part = "turret"
		reference = _turret.global_basis
	var face: String = _face_for_normal(reference.orthonormalized().inverse() * normal)
	var result: HitResult = Armour.resolve(shell_data, velocity.length(),
			data.armour.thickness_mm(part, face), Armour.impact_angle(velocity, normal),
			data.armour.ricochet_angle_deg)
	result.part = part
	result.face = face
	result.target = self
	if result.is_penetration() and not _knocked_out:
		_knock_out()
	return result


## Called by Shell when a shell this tank fired lands.
func report_shot(result: HitResult) -> void:
	shot_landed.emit(result)


## Undoes a knock-out (test bench respawn).
func repair() -> void:
	_knocked_out = false
	if _burning != null:
		_burning.queue_free()
		_burning = null
	_apply_paint(false)


func _knock_out() -> void:
	_knocked_out = true
	_burning = BURNING_SCENE.instantiate()
	add_child(_burning)
	_burning.position = _turret.position
	_apply_paint(true)
	knocked_out.emit()


func _shape_node(shape: int) -> Node:
	if shape < 0:
		return null
	var owner_id: int = shape_find_owner(shape)
	return shape_owner_get_owner(owner_id) as Node


## Zone face from a normal in the part's own space (forward is -Z).
func _face_for_normal(local_normal: Vector3) -> String:
	if absf(local_normal.y) > ROOF_NORMAL_Y:
		return "roof"
	var angle: float = absf(rad_to_deg(atan2(local_normal.x, -local_normal.z)))
	if angle <= 45.0:
		return "front"
	if angle >= 135.0:
		return "rear"
	return "side"


func _setup_paint() -> void:
	if paint_color.a > 0.0:
		_paint_override = StandardMaterial3D.new()
		_paint_override.albedo_color = paint_color
		_paint_override.roughness = 0.85
	_charred_material = StandardMaterial3D.new()
	_charred_material.albedo_color = CHARRED_COLOR
	_charred_material.roughness = 1.0
	_apply_paint(false)


## Paint override goes on meshes that use the scene's paint (same material as the
## hull); charred goes on every mesh.
func _apply_paint(charred: bool) -> void:
	var hull_mesh: Mesh = ($Visual/Hull as MeshInstance3D).mesh
	var paint: Material = hull_mesh.surface_get_material(0) if hull_mesh != null else null
	for mesh_instance: MeshInstance3D in _visual.find_children("*", "MeshInstance3D", true, false):
		if charred:
			mesh_instance.material_override = _charred_material
		elif mesh_instance.mesh != null and mesh_instance.mesh.surface_get_material(0) == paint:
			mesh_instance.material_override = _paint_override
		else:
			mesh_instance.material_override = null


## Speed along the hull's forward axis (m/s), negative when reversing.
func get_forward_speed() -> float:
	return linear_velocity.dot(-global_basis.z)


## Turret angle relative to the hull (radians, positive = left).
func get_turret_yaw() -> float:
	return _turret.rotation.y


## Gun angle relative to the turret (radians, positive = up).
func get_gun_pitch() -> float:
	return _gun_pivot.rotation.x


## Turret heading in world space (radians, same convention as Node3D rotation.y).
func get_turret_global_yaw() -> float:
	var forward: Vector3 = -_turret.global_basis.z
	return atan2(-forward.x, -forward.z)


## 0 = hatch closed, 1 = fully open.
func get_hatch_progress() -> float:
	return _hatch_progress


## True whenever the hatch isn't fully closed.
func is_commander_exposed() -> bool:
	return _hatch_progress > 0.0


## Commander's eye in world space: rises out of the cupola as the hatch opens.
func get_commander_eye_position() -> Vector3:
	return _head_closed.global_position.lerp(_head_open.global_position,
			smoothstep(0.0, 1.0, _hatch_progress))


## Gunner's sight in world space. Fixed to the gun: follows traverse and elevation.
func get_gunner_sight_transform() -> Transform3D:
	return _gunner_sight.global_transform


func is_loaded() -> bool:
	return _reload_remaining <= 0.0


## Seconds until the gun is loaded again (0 when loaded).
func get_reload_remaining() -> float:
	return _reload_remaining


## Shell in the breech, or the one being loaded. Null if the tank has no ammo.
func get_loaded_shell() -> ShellData:
	if _ammo_index < 0 or _ammo_index >= data.ammo.size():
		return null
	return data.ammo[_ammo_index]


func get_ammo_index() -> int:
	return _ammo_index


func _physics_process(delta: float) -> void:
	if _knocked_out:
		_command = _idle_command
	_update_turret(delta)
	_commander_wound_remaining = maxf(_commander_wound_remaining - delta, 0.0)
	_update_hatch(delta)
	_update_commander_hitbox()
	_update_gun(delta)
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


func _update_turret(delta: float) -> void:
	if not _command.has_aim:
		return
	# Yaw: aim point in the turret's parent (hull) space; forward is -Z, positive = left.
	var hull_local: Vector3 = (_turret.get_parent() as Node3D).to_local(_command.aim_point)
	var target_yaw: float = atan2(-hull_local.x, -hull_local.z)
	var yaw_step: float = deg_to_rad(data.turret_traverse_speed_deg) * delta
	var yaw_diff: float = wrapf(target_yaw - _turret.rotation.y, -PI, PI)
	_turret.rotation.y = wrapf(_turret.rotation.y + clampf(yaw_diff, -yaw_step, yaw_step), -PI, PI)

	# Pitch: aim point in turret space, measured from the gun pivot.
	var from_pivot: Vector3 = _turret.to_local(_command.aim_point) - _gun_pivot.position
	var horizontal: float = Vector2(from_pivot.x, from_pivot.z).length()
	var target_pitch: float = clampf(atan2(from_pivot.y, horizontal),
			-deg_to_rad(data.gun_max_depression_deg), deg_to_rad(data.gun_max_elevation_deg))
	var pitch_step: float = deg_to_rad(data.gun_elevation_speed_deg) * delta
	_gun_pivot.rotation.x += clampf(target_pitch - _gun_pivot.rotation.x, -pitch_step, pitch_step)


func _update_hatch(delta: float) -> void:
	var target: float = 1.0 if _command.hatch_open and not is_commander_wounded() else 0.0
	_hatch_progress = move_toward(_hatch_progress, target,
			delta / maxf(data.hatch_transition_time_s, 0.01))
	_hatch_hinge.rotation.x = deg_to_rad(HATCH_OPEN_ANGLE_DEG) * _hatch_progress


## Keeps the commander's hitbox on his head; only collides while he's exposed.
func _update_commander_hitbox() -> void:
	_commander_hitbox.position = _head_closed.position.lerp(_head_open.position,
			smoothstep(0.0, 1.0, _hatch_progress)) - Vector3(0.0, COMMANDER_HITBOX_DROP, 0.0)
	_commander_hitbox_shape.disabled = not is_commander_exposed()


func _update_gun(delta: float) -> void:
	var wanted: int = _command.ammo_select
	if wanted >= 0 and wanted < data.ammo.size() and wanted != _ammo_index:
		_ammo_index = wanted
		_reload_remaining = data.reload_time_s
	_reload_remaining = maxf(_reload_remaining - delta, 0.0)
	if _command.fire and is_loaded() and get_loaded_shell() != null:
		_fire()


func _fire() -> void:
	var direction: Vector3 = -_muzzle.global_basis.z
	var muzzle_position: Vector3 = _muzzle.global_position
	var shell := SHELL_SCENE.instantiate() as Shell
	get_parent().add_child(shell)
	# The tank's own motion carries over to the shell: firing on the move costs accuracy.
	var shell_data: ShellData = get_loaded_shell()
	shell.launch(shell_data, muzzle_position,
			direction * shell_data.muzzle_velocity_mps + linear_velocity, self)
	var flash: Node3D = MUZZLE_FLASH_SCENE.instantiate()
	get_parent().add_child(flash)
	flash.global_position = muzzle_position
	apply_impulse(-direction * data.recoil_impulse_ns, muzzle_position - global_position)
	_reload_remaining = data.reload_time_s
	fired.emit(shell)


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
	# The tracks also cancel gravity along the slope (uphill pull, downhill push),
	# up to what the steepest climbable slope needs.
	var gravity_along: float = state.total_gravity.dot(forward)
	var traction_limit: float = maxf(state.total_gravity.length()
			* sin(deg_to_rad(data.max_climb_deg)), accel_limit)
	var drive_force: float = mass * clampf(accel - gravity_along, -traction_limit, traction_limit)

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
