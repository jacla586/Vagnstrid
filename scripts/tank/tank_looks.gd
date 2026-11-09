class_name TankLooks
extends Node
## A tank's living looks, read from how it moves (so puppets look the same; nothing is
## sent): the paint's weathering (tank_paint.gdshader instance values: dust that builds
## up as the tank drives, wetness in rain, where the mud line is on each part), its
## tactical number, wheels and tracks that move with each track's travel
## (tank_wheel/tank_track.gdshader) and an antenna that sways when the tank speeds up,
## brakes or turns. Made by Tank.

## Dust on a clean tank, and how much more per metre driven (times the weather's
## dust_factor); it never quite covers the paint.
const DUST_START: float = 0.15
const DUST_PER_M: float = 1.0 / 1500.0
const DUST_MAX: float = 0.9
## Paint values are updated this often (Hz).
const PAINT_HZ: float = 4.0
## Parts that never get mud (gun, figure, roof MG): their mud line far below.
const NO_MUD_Y: float = -100.0
## Faster than this between two frames is a teleport (respawn), not driving (m/s).
const MAX_PLAUSIBLE_SPEED: float = 60.0

var tank: Tank

## Offline tanks have no net_id: numbered in order per team.
static var _next_index: Dictionary = {}
var _offline_index: int = 0
var _number_key: String = ""

var _driven_m: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _paint_clock := PackedFloat32Array([0.0])
var _meshes: Array[MeshInstance3D] = []
## How far each track has rolled (m, forward positive).
var _track_l: float = 0.0
var _track_r: float = 0.0
## The same a physics tick ago: frames between ticks blend between them.
var _track_l_prev: float = 0.0
var _track_r_prev: float = 0.0
var _last_yaw: float = 0.0
var _last_velocity: Vector3 = Vector3.ZERO
var _hull_mesh: MeshInstance3D
var _antenna: Node3D
## Antenna tilt (radians about x, z) and its rate: a damped spring pushed by acceleration.
var _sway := Vector2.ZERO
var _sway_rate := Vector2.ZERO

## Antenna: how far it leans per m/s² and its spring (Hz) and damping.
const SWAY_PER_ACCEL: float = 0.035
const SWAY_FREQ_HZ: float = 1.6
const SWAY_DAMPING: float = 0.18
const SWAY_MAX: float = 0.5


func _ready() -> void:
	_last_position = tank.global_position
	_last_yaw = tank.global_rotation.y
	tank.repaired.connect(func() -> void: _driven_m = 0.0)
	_find_meshes.call_deferred()


## Every mesh of the tank's look and its mud line in its own space.
func _find_meshes() -> void:
	var visual: Node3D = tank.get_node("Visual")
	var bottom := Vector3(0.0, -tank.data.hull_size.y * 0.5, 0.0)
	_meshes.clear()
	_hull_mesh = visual.get_node_or_null("Hull") as MeshInstance3D
	_antenna = visual.get_node_or_null("Turret/Antenna") as Node3D
	for mi: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)
		var to_visual := Transform3D.IDENTITY
		var node: Node = mi
		while node != visual and node is Node3D:
			to_visual = (node as Node3D).transform * to_visual
			node = node.get_parent()
		var muddy: bool = not (mi.name in [&"Gun", &"Mantlet", &"CommanderFigure", &"Mount"])
		mi.set_instance_shader_parameter(&"base_y",
				(to_visual.affine_inverse() * bottom).y if muddy else NO_MUD_Y)
	_apply()


func _process(delta: float) -> void:
	_update_number()
	if _hull_mesh != null:
		var f: float = Engine.get_physics_interpolation_fraction()
		var l: float = lerpf(_track_l_prev, _track_l, f)
		var r: float = lerpf(_track_r_prev, _track_r, f)
		_hull_mesh.set_instance_shader_parameter(&"wheel_dist_l", l)
		_hull_mesh.set_instance_shader_parameter(&"wheel_dist_r", r)
		_hull_mesh.set_instance_shader_parameter(&"track_dist_l", l)
		_hull_mesh.set_instance_shader_parameter(&"track_dist_r", r)
	if _antenna != null:
		_antenna.rotation = Vector3(_sway.x, 0.0, _sway.y)
	if Ticks.due(_paint_clock, delta, PAINT_HZ):
		_apply()


## Movement is read at the physics rate: the tank's pose changes only then.
func _physics_process(delta: float) -> void:
	_track_l_prev = _track_l
	_track_r_prev = _track_r
	var now: Vector3 = tank.global_position
	var moved: Vector3 = now - _last_position
	var step: float = moved.length()
	var yaw: float = tank.global_rotation.y
	if delta > 0.0 and step / delta <= MAX_PLAUSIBLE_SPEED:
		_driven_m += step
		# Each track rolls the hull's forward travel, plus or minus the turn: turning left
		# (yaw up) the right track goes further.
		var forward: float = moved.dot(-tank.global_basis.z)
		var turn: float = wrapf(yaw - _last_yaw, -PI, PI) * tank.get_track_half_width()
		_track_l += forward - turn
		_track_r += forward + turn
		_update_sway(moved / delta, delta)
	_last_position = now
	_last_yaw = yaw


func _apply() -> void:
	var weather: WeatherData = Weather.current()
	var dust_factor: float = weather.dust_factor if weather != null else 1.0
	var dust: float = minf(DUST_START + _driven_m * DUST_PER_M * dust_factor, DUST_MAX)
	var wet: float = weather.rain_intensity if weather != null else 0.0
	for mi: MeshInstance3D in _meshes:
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter(&"dust_amount", dust)
			mi.set_instance_shader_parameter(&"wetness", wet)


## Tactical number: team digit (1, 2, ...) and two digits per tank, the same on every
## machine online (from net_id); hidden on a knocked-out tank.
func _update_number() -> void:
	if tank.number_labels.is_empty():
		return
	var index: int
	if tank.net_id > 0:
		index = tank.net_id % 99 + 1
	else:
		if _offline_index == 0:
			_offline_index = int(_next_index.get(tank.team, 0)) + 1
			_next_index[tank.team] = _offline_index
		index = _offline_index
	var text: String = "%d%02d" % [tank.team + 1, index]
	var show: bool = not tank.is_knocked_out()
	var key: String = text + ("" if show else "-")
	if key == _number_key:
		return
	_number_key = key
	for label: Label3D in tank.number_labels:
		label.text = text
		label.visible = show


## The antenna whip leans back when the tank speeds up, forward when it brakes, out in a
## turn, and springs back.
func _update_sway(velocity: Vector3, delta: float) -> void:
	if _antenna == null or delta <= 0.0:
		return
	var accel: Vector3 = (velocity - _last_velocity) / delta
	_last_velocity = velocity
	# In the turret's frame: the whip leans against the acceleration.
	var local: Vector3 = _antenna.get_parent().global_basis.inverse() * accel
	var push := Vector2(local.z, -local.x) * SWAY_PER_ACCEL
	var omega: float = TAU * SWAY_FREQ_HZ
	_sway_rate += ((push - _sway) * omega * omega - _sway_rate * 2.0 * SWAY_DAMPING * omega) * delta
	_sway += _sway_rate * delta
	_sway = _sway.limit_length(SWAY_MAX)
