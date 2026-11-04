class_name MachineGunNest
extends StaticBody3D
## A static machine-gun position: the first threat to an exposed commander.
##
## Spotting follows the same rules bots will: a few times a second it looks for
## tanks with the commander exposed, within range, with a clear line of sight from
## its eye to the commander's head. After seeing a target for the reaction time it
## swings the gun on (with lead and drop) and fires bursts with random spread.
## A main-gun shell hit destroys it, and so do fragments (it's a fragment target,
## aimed at the gunner).

const SHELL_SCENE: PackedScene = preload("res://scenes/weapons/shell.tscn")
const BURNING_SCENE: PackedScene = preload("res://scenes/effects/burning.tscn")
const SCAN_INTERVAL_S: float = 0.2
## Fires only when the gun points within this angle of the aim (radians, ~1°).
const AIM_TOLERANCE_RAD: float = 0.0175
## Shells at least this big destroy the nest; bullets don't.
const MIN_DESTROY_CALIBER_MM: float = 20.0
## Rough average bullet speed over the flight, as a share of muzzle velocity (lead).
const AVERAGE_SPEED_FACTOR: float = 0.85
const CHARRED_COLOR: Color = Color(0.08, 0.08, 0.075)

@export var data: MachineGunData
## Test bench: seconds until a destroyed nest is back. 0 = never.
@export var respawn_delay_s: float = 20.0

var _target: Tank
var _awareness: float = 0.0
var _scan_timer: float = 0.0
var _aim_direction: Vector3 = Vector3.FORWARD
var _engage_time: float = 0.0
var _shot_timer: float = 0.0
var _destroyed: bool = false
var _respawn_timer: float = 0.0
var _burning: Node3D
var _charred_material: StandardMaterial3D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _sound: GunfireSound

@onready var _mount: Node3D = $Mount
@onready var _pitch: Node3D = $Mount/Pitch
@onready var _muzzle: Marker3D = $Mount/Pitch/Muzzle
@onready var _eye: Marker3D = $Eye
@onready var _gunner: Node3D = $Mount/Gunner


func _ready() -> void:
	assert(data != null and data.bullet != null, "MachineGunNest needs MachineGunData with a bullet")
	_charred_material = StandardMaterial3D.new()
	_charred_material.albedo_color = CHARRED_COLOR
	_rng.randomize()
	_aim_direction = -_mount.global_basis.z
	add_to_group(Explosion.TARGET_GROUP)
	_sound = GunfireSound.new()
	add_child(_sound)


func is_destroyed() -> bool:
	return _destroyed


## The tank it's currently engaging, or null.
func get_target() -> Tank:
	return _target


## True once the gunner has seen the target long enough to open fire.
func is_engaging() -> bool:
	return _target != null and _awareness >= data.reaction_time_s


## Hook called by Shell. Main-gun shells destroy the nest; bullets do nothing.
func on_shell_hit(shell_data: ShellData, _point: Vector3, _normal: Vector3,
		_velocity: Vector3, _shape: int = -1) -> HitResult:
	if _destroyed or shell_data.caliber_mm < MIN_DESTROY_CALIBER_MM:
		return null
	return _destroy_with_result()


func is_fragment_target_active() -> bool:
	return not _destroyed


func get_fragment_aim_point() -> Vector3:
	return _gunner.global_position


func get_fragment_collider() -> CollisionObject3D:
	return self


func on_fragment_hit(_shell_data: ShellData, _distance: float) -> HitResult:
	if _destroyed:
		return null
	return _destroy_with_result()


func _destroy_with_result() -> HitResult:
	_destroy()
	var result := HitResult.new()
	result.note = "MG NEST DESTROYED"
	result.part = "MG nest"
	result.target = self
	return result


func _physics_process(delta: float) -> void:
	if _destroyed:
		_update_respawn(delta)
		return
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer += SCAN_INTERVAL_S
		_scan()
	_turn_gun(delta)
	_update_fire(delta)


func _scan() -> void:
	var best: Tank = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or tank.is_knocked_out() or not _can_see_commander(tank):
			continue
		var distance: float = _eye.global_position.distance_to(tank.get_commander_hitbox_position())
		# Stick with the current target if it's still visible.
		if tank == _target:
			distance = -1.0
		if distance < best_distance:
			best = tank
			best_distance = distance
	if best != null:
		if best != _target:
			_awareness = 0.0
		_target = best
		_awareness = minf(_awareness + SCAN_INTERVAL_S, data.reaction_time_s)
		_aim_direction = _lead_aim(best)
	else:
		_awareness = maxf(_awareness - SCAN_INTERVAL_S, 0.0)
		if _awareness <= 0.0:
			_target = null


func _can_see_commander(tank: Tank) -> bool:
	if not tank.is_commander_exposed():
		return false
	var head: Vector3 = tank.get_commander_hitbox_position()
	var from: Vector3 = _eye.global_position
	if from.distance_to(head) > data.max_range_m:
		return false
	return Vision.has_line_of_sight(get_world_3d(), from, head, tank.get_commander_hitbox(),
			[get_rid()])


## Direction to fire: leads the commander's motion and adds drop.
func _lead_aim(tank: Tank) -> Vector3:
	var from: Vector3 = _muzzle.global_position
	var head: Vector3 = tank.get_commander_hitbox_position()
	var flight_time: float = from.distance_to(head) \
			/ (data.bullet.muzzle_velocity_mps * AVERAGE_SPEED_FACTOR)
	var predicted: Vector3 = head + tank.linear_velocity * flight_time
	var d: Vector3 = predicted - from
	var horizontal: float = Vector2(d.x, d.z).length()
	var drop: float = Ballistics.superelevation_for_range(data.bullet, horizontal)
	return Basis.from_euler(Vector3(atan2(d.y, horizontal) + drop, atan2(-d.x, -d.z), 0.0)) \
			* Vector3.FORWARD


func _turn_gun(delta: float) -> void:
	if _target == null:
		return
	var local: Vector3 = global_basis.inverse() * _aim_direction
	var target_yaw: float = atan2(-local.x, -local.z)
	var target_pitch: float = atan2(local.y, Vector2(local.x, local.z).length())
	var step: float = deg_to_rad(data.traverse_speed_deg) * delta
	_mount.rotation.y = wrapf(_mount.rotation.y
			+ clampf(wrapf(target_yaw - _mount.rotation.y, -PI, PI), -step, step), -PI, PI)
	_pitch.rotation.x += clampf(target_pitch - _pitch.rotation.x, -step, step)


func _update_fire(delta: float) -> void:
	var gun_forward: Vector3 = -_muzzle.global_basis.z
	if not is_engaging() or gun_forward.angle_to(_aim_direction) > AIM_TOLERANCE_RAD:
		_engage_time = 0.0
		_shot_timer = 0.0
		return
	_engage_time += delta
	var cycle: float = data.burst_time_s + data.burst_pause_s
	if fmod(_engage_time, cycle) > data.burst_time_s:
		return
	_shot_timer -= delta
	var interval: float = 60.0 / maxf(data.rounds_per_minute, 1.0)
	while _shot_timer <= 0.0:
		_shot_timer += interval
		_fire_bullet(gun_forward)


func _fire_bullet(gun_forward: Vector3) -> void:
	# Random point in a disc of radius dispersion around the aim.
	var radius: float = sqrt(_rng.randf()) * data.dispersion_mrad * 0.001
	var angle: float = _rng.randf() * TAU
	var muzzle_basis: Basis = _muzzle.global_basis
	var direction: Vector3 = (gun_forward + muzzle_basis.x * cos(angle) * radius
			+ muzzle_basis.y * sin(angle) * radius).normalized()
	var bullet := SHELL_SCENE.instantiate() as Shell
	get_parent().add_child(bullet)
	bullet.launch(data.bullet, _muzzle.global_position,
			direction * data.bullet.muzzle_velocity_mps, self)
	_sound.on_shot(data.sound_shot, _muzzle.global_position)


func _destroy() -> void:
	_destroyed = true
	_sound.silence()
	_target = null
	_awareness = 0.0
	_burning = BURNING_SCENE.instantiate()
	add_child(_burning)
	_set_charred(true)


func _update_respawn(delta: float) -> void:
	if respawn_delay_s <= 0.0:
		return
	_respawn_timer += delta
	if _respawn_timer >= respawn_delay_s:
		_respawn_timer = 0.0
		_destroyed = false
		if _burning != null:
			_burning.queue_free()
			_burning = null
		_set_charred(false)


func _set_charred(charred: bool) -> void:
	for mesh_instance: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh_instance.material_override = _charred_material if charred else null
