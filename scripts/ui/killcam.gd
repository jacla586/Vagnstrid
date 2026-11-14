class_name Killcam
extends Node
## Player rig: when the own tank is knocked out by a gun round, replays that round
## (HitRecord from Tank.get_kill_record): a chase camera follows a ghost round from
## where it was fired to where it struck, then holds on the entry (red marker). Any
## key or click skips. The hit picture (KillcamPanel) stays up until the respawn; behind
## it a chase camera follows a living teammate (KillcamData "Spectate"; click: the next).

const GHOST_COLOR: Color = Color(1.0, 0.6, 0.2)
const MARK_COLOR: Color = Color(1.0, 0.15, 0.1)

@export var views: PlayerViews
@export var tank: Tank
@export var data: KillcamData

var _camera: Camera3D
var _ghost: MeshInstance3D
var _mark: MeshInstance3D
var _record: HitRecord
var _wait: float = -1.0
var _time: float = 0.0
var _flight_s: float = 1.0
var _drop_m: float = 0.0
var _running: bool = false
## The replay for this knock-out is over, was skipped or had nothing to show.
var _played: bool = false
var _tank: Tank
var _spectating: bool = false
var _watched: Tank


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.top_level = true
	_camera.far = 8000.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_ghost = _glow_mesh(0.12, 1.4, GHOST_COLOR)
	_mark = _glow_mesh(0.3, 0.6, MARK_COLOR)
	for m: MeshInstance3D in [_ghost, _mark]:
		m.top_level = true
		m.visible = false
		m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(m)


func _process(delta: float) -> void:
	var own: Tank = views.get_tank() if views != null else tank
	if own != _tank:
		if _tank != null and is_instance_valid(_tank) and _tank.knocked_out.is_connected(_on_knocked_out):
			_tank.knocked_out.disconnect(_on_knocked_out)
		_tank = own
		if _tank != null:
			_tank.knocked_out.connect(_on_knocked_out)
	if _tank == null or not is_instance_valid(_tank):
		return
	if not _tank.is_knocked_out():
		_played = false
		_wait = -1.0
		if _running:
			_stop()   # respawned
		_end_spectate()
		return
	if _wait >= 0.0:
		_wait -= delta
		if _wait < 0.0:
			_start()
		return
	if _running:
		_time += delta
		_update_replay()
	elif _played:
		_spectate(delta)


func _input(event: InputEvent) -> void:
	if _spectating:
		if event.is_action_pressed("fire"):
			_watched = _next_teammate(_watched)
			get_viewport().set_input_as_handled()
		return
	if not _running:
		return
	var key := event as InputEventKey
	var skip: bool = (key != null and key.pressed and not key.echo
			and not event.is_action("scoreboard") and not event.is_action("release_mouse")) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if skip:
		_stop()
		get_viewport().set_input_as_handled()


func is_running() -> bool:
	return _running


func has_played() -> bool:
	return _played


func _on_knocked_out() -> void:
	_played = false
	_wait = data.start_delay_s


func _start() -> void:
	_record = _tank.get_kill_record()
	if _record == null or _record.origin.distance_to(_record.impact) < 1.0:
		_played = true
		return
	var distance: float = _record.origin.distance_to(_record.impact)
	_flight_s = clampf(distance / maxf(data.replay_speed_mps, 1.0), data.min_flight_s,
			data.max_flight_s)
	var t: float = distance / maxf(data.assumed_shell_speed_mps, 1.0)
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_drop_m = g * t * t / 8.0   # the arc's height over the straight line
	_time = 0.0
	_running = true
	_ghost.visible = true
	_mark.visible = false
	views.set_killcam(true)
	_camera.current = true
	_update_replay()


func _stop() -> void:
	if not _running:
		return
	_running = false
	_played = true
	_ghost.visible = false
	_mark.visible = false
	_camera.current = false
	views.set_killcam(false)


# --- Spectating a teammate ------------------------------------------------------------

func _spectate(delta: float) -> void:
	var first: bool = not _spectating
	if first:
		_spectating = true
		views.set_killcam(true)
		_camera.current = true
	if _watched == null or not is_instance_valid(_watched) or _watched.is_knocked_out():
		var had: bool = _watched != null
		_watched = _next_teammate(null)
		first = first or (had and _watched != null)
	if _watched == null:
		if first or _camera.global_position == Vector3.ZERO:
			var at: Vector3 = _tank.global_position
			_camera.global_position = at - _tank.global_basis.z * -data.spectate_back_m \
					+ Vector3.UP * data.spectate_up_m * 2.0
			_camera.look_at(at, Vector3.UP)
		return
	var target: Vector3 = _watched.get_global_transform_interpolated().origin
	var yaw: float = _watched.get_turret_global_yaw()
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var want: Vector3 = target - ahead * data.spectate_back_m + Vector3.UP * data.spectate_up_m
	if first:
		_camera.global_position = want
	else:
		_camera.global_position = _camera.global_position.lerp(want,
				1.0 - exp(-data.spectate_follow * delta))
	_camera.look_at(target + ahead * 20.0 + Vector3.UP * 2.0, Vector3.UP)


func _end_spectate() -> void:
	if not _spectating:
		return
	_spectating = false
	_watched = null
	_camera.current = false
	views.set_killcam(false)


## The living teammate after `after` by distance from the own tank (nearest first, round).
func _next_teammate(after: Tank) -> Tank:
	var mates: Array[Tank] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var t := node as Tank
		if t != null and t != _tank and t.team == _tank.team and not t.is_knocked_out() \
				and t.is_inside_tree():
			mates.append(t)
	if mates.is_empty():
		return null
	var from: Vector3 = _tank.global_position
	mates.sort_custom(func(a: Tank, b: Tank) -> bool:
		return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
	var i: int = mates.find(after) if after != null else -1
	return mates[(i + 1) % mates.size()]


## Point on the drawn path at share u (0 muzzle .. 1 impact).
func _path(u: float) -> Vector3:
	return _record.origin.lerp(_record.impact, u) + Vector3.UP * (4.0 * _drop_m * u * (1.0 - u))


func _update_replay() -> void:
	var u: float = clampf(_time / _flight_s, 0.0, 1.0)
	var at: Vector3 = _path(u)
	var ahead: Vector3 = (_path(minf(u + 0.01, 1.0)) - _path(maxf(u - 0.01, 0.0))).normalized()
	if ahead.length_squared() < 0.5:
		ahead = (_record.impact - _record.origin).normalized()
	if u < 1.0:
		_ghost.global_position = at
		_ghost.look_at(at + ahead, _up_for(ahead))
		_ghost.rotate_object_local(Vector3.RIGHT, PI * 0.5)   # the capsule lies along the path
		var cam: Vector3 = at - ahead * data.chase_back_m + Vector3.UP * data.chase_up_m
		_camera.global_position = cam
		_camera.look_at(at + ahead * 20.0, Vector3.UP)
		return
	# Hold on the entry, a little to the side of the incoming line.
	_ghost.visible = false
	_mark.visible = true
	_mark.global_position = _record.impact
	var pulse: float = 1.0 + 0.25 * sin(_time * 10.0)
	_mark.scale = Vector3.ONE * pulse
	var side: Vector3 = ahead.cross(Vector3.UP).normalized()
	var hold_t: float = clampf((_time - _flight_s) / maxf(data.hold_s, 0.01), 0.0, 1.0)
	var from: Vector3 = _record.impact - ahead * data.hold_distance_m + Vector3.UP * 1.5
	var to: Vector3 = _record.impact - ahead * data.hold_distance_m * 0.6 \
			+ side * data.hold_distance_m * 0.6 + Vector3.UP * 2.5
	_camera.global_position = from.lerp(to, smoothstep(0.0, 1.0, hold_t))
	_camera.look_at(_record.impact, Vector3.UP)
	if _time >= _flight_s + data.hold_s:
		_stop()


static func _up_for(dir: Vector3) -> Vector3:
	return Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT


static func _glow_mesh(radius: float, height: float, color: Color) -> MeshInstance3D:
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	capsule.material = mat
	var m := MeshInstance3D.new()
	m.mesh = capsule
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m
