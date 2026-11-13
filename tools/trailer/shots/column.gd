extends "res://tools/trailer/trailer_shot.gd"
## A column of four tanks drives along a ThunderRoad route in the rain.
##  cam=roadside (default)  low at the roadside; the column comes and rolls past
##  cam=drone               ahead of the column, high, backing along the road
## Options: route=<scenario> (default road_to_science_thunder; its map is loaded),
## at=<m along the route> (default 350), team=0 (friends: olive with blue bands).

const ROSTER: Array[String] = ["t34", "sherman", "t34", "pz4"]
const GAP_M: float = 24.0
const LOOK_AHEAD_M: float = 14.0
const CAM_AHEAD_M: float = 85.0
const CAM_SIDE_M: float = 9.0

var tanks: Array[Tank] = []
var _curve: Curve3D
var _start: float = 350.0
var _cam_s: float = 0.0
var _look: Vector3
var _passed_t: float = -1.0


func _init() -> void:
	map = "road_to_science"
	weather = "rain"


func setup() -> void:
	var route: String = options.get("route", "road_to_science_thunder")
	_curve = _route_curve("res://scenes/scenarios/%s.tscn" % route)
	if _curve == null:
		push_warning("no route in %s" % route)
		done = true
		return
	_start = float(options.get("at", "350"))
	place(player, Vector2(_curve.sample_baked(0.0).x, _curve.sample_baked(0.0).z) + Vector2(30, 30), 0.0)
	var team: int = int(options.get("team", "1"))
	for i: int in ROSTER.size():
		var s: float = _start - i * GAP_M
		var p: Vector3 = _curve.sample_baked(s)
		var tank: Tank = spawn(ROSTER[i], team, Vector2(p.x, p.z), _heading_at(s), "Column%d" % i)
		tanks.append(tank)
	_cam_s = _start + CAM_AHEAD_M
	_look = tanks[0].global_position
	use_cam()


func physics(_delta: float) -> void:
	if tanks.is_empty():
		return
	for i: int in tanks.size():
		var tank: Tank = tanks[i]
		var s: float = _curve.get_closest_offset(tank.global_position)
		var target: Vector3 = _curve.sample_baked(s + LOOK_AHEAD_M)
		var throttle: float = 0.6
		if i > 0:
			var gap: float = _curve.get_closest_offset(tanks[i - 1].global_position) - s
			throttle = clampf(0.6 + (gap - GAP_M) * 0.06, 0.0, 1.0)
		drive_to(tank, target, throttle)
		aim(tank, tank.global_position - tank.global_basis.z * 300.0 + Vector3.UP * 1.5)
	var last_s: float = _curve.get_closest_offset(tanks[-1].global_position)
	if _passed_t < 0.0 and last_s > _cam_s + 5.0:
		_passed_t = t
		cue("the column has passed")
	if _passed_t >= 0.0 and t > _passed_t + 4.0:
		done = true


func frame(delta: float) -> void:
	if tanks.is_empty():
		return
	if options.get("cam", "") == "drone":
		_drone()
		return
	var cam_c: Vector3 = _curve.sample_baked(_cam_s)
	var side: Vector3 = _tangent(_cam_s).cross(Vector3.UP).normalized()
	var eye: Vector3 = ground_v(cam_c + side * CAM_SIDE_M) + Vector3.UP * 1.7
	# Look at the tank nearest the camera that hasn't gone past, smoothly.
	var want: Vector3 = tanks[-1].get_global_transform_interpolated().origin
	for tank: Tank in tanks:
		if _curve.get_closest_offset(tank.global_position) < _cam_s + 8.0:
			want = tank.get_global_transform_interpolated().origin
			break
	_look = _look.lerp(want + Vector3.UP * 1.0, 1.0 - exp(-2.5 * delta))
	look_cam(eye, _look, 38.0)


func _drone() -> void:
	var lead_s: float = _curve.get_closest_offset(tanks[0].global_position)
	var mid: Vector3 = Vector3.ZERO
	for tank: Tank in tanks:
		mid += tank.get_global_transform_interpolated().origin
	mid /= float(tanks.size())
	var ahead: Vector3 = _curve.sample_baked(lead_s + 35.0 - t * 0.6)
	var side: Vector3 = _tangent(lead_s).cross(Vector3.UP).normalized()
	var eye: Vector3 = ahead + side * 14.0 + Vector3.UP * (22.0 - t * 0.3)
	look_cam(eye, mid, 48.0)


func _tangent(s: float) -> Vector3:
	var d: Vector3 = _curve.sample_baked(s + 2.0) - _curve.sample_baked(s - 2.0)
	d.y = 0.0
	return d.normalized()


func _heading_at(s: float) -> float:
	var d: Vector3 = _tangent(s)
	return rad_to_deg(atan2(d.x, -d.z))


## The Route Path3D's curve, read from a scenario scene without loading its map.
static func _route_curve(path: String) -> Curve3D:
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var state: SceneState = scene.get_state()
	for i: int in state.get_node_count():
		if state.get_node_name(i) != &"Route":
			continue
		for j: int in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == &"curve":
				return state.get_node_property_value(i, j) as Curve3D
	return null
