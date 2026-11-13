extends "res://tools/trailer/trailer_shot.gd"
## Filler: seven T-34s advance in line over the field south-east of Vallastaden, their
## squads running a little ahead; HE rounds burst in the field. About 11 s, cut 4-5 from it.
##  cam=onboard (default)  riding on one of the tanks, behind the turret, the line beside
##  cam=drone              behind and above the line, rising, the town ahead
## The line finds its own start: open ground for every tank and the squads, Vallastaden
## (VALLASTADEN) ahead. Cheats: the squads start out ahead of the tanks (no dismount),
## the HE rounds come from nowhere (their shooter is the parked player tank, so the bursts
## spare the own team). Options: weather=<preset>, spot=<n>.

const LINE: int = 7
const GAP_M: float = 20.0
const STAGGER_M: Array[float] = [6.0, -4.0, 3.0, -2.0, 5.0, -3.0, -12.0]   # the camera's tank last, behind
const SPEED_MPS: float = 4.2
const CAM_TANK: int = 6   # the right end: it sees the line slant off towards the town
## Middle of Vallastaden's blocks (map metres).
const VALLASTADEN: Vector2 = Vector2(1960.0, 820.0)
const DRIVE_M: float = 60.0
const HE_TIMES_S: Array[float] = [2.2, 4.6, 7.4]
const HE_SPOTS: Array[Vector2] = [Vector2(10.0, 60.0), Vector2(-35.0, 45.0), Vector2(30.0, 85.0)]   # (right, ahead) of the line
const END_S: float = 11.0

var tanks: Array[Tank] = []
var _start: Vector3
var _fwd: Vector3
var _right: Vector3
var _squads_out: Array[bool] = []
var _he: ShellData = preload("res://data/shells/he_152.tres")
var _cam_eye: Vector3 = Vector3.ZERO


func _init() -> void:
	map = "road_to_science"
	weather = "clear"


func setup() -> void:
	if not _find_line():
		push_warning("no open line towards Vallastaden")
		done = true
		return
	place(player, Vector2(_start.x - _fwd.x * 300.0, _start.z - _fwd.z * 300.0), 0.0)   # out of the way
	var heading: float = rad_to_deg(atan2(_fwd.x, -_fwd.z))
	for i: int in LINE:
		var p: Vector3 = _lane(i, STAGGER_M[i])
		var tank: Tank = spawn("t34", 0, Vector2(p.x, p.z), heading, "Line%d" % i)
		protect_commander(tank)
		tank.linear_velocity = _fwd * SPEED_MPS
		tanks.append(tank)
		_squads_out.append(false)
	use_cam()


func _lane(i: int, ahead: float) -> Vector3:
	return ground_v(_start + _right * (float(i) - float(LINE - 1) * 0.5) * GAP_M + _fwd * ahead)


func _find_line() -> bool:
	var skip: int = int(options.get("spot", "0"))
	var tries: Array[Vector2] = []
	for x: int in range(2100, 2750, 25):
		for z: int in range(700, 1400, 25):
			tries.append(Vector2(x, z))
	# Nearest the town first: its houses should be big enough to know.
	tries.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_to(VALLASTADEN) < b.distance_to(VALLASTADEN))
	var gc: GroundCover = GroundCover.of(self)
	for xz: Vector2 in tries:
		var d_town: float = xz.distance_to(VALLASTADEN)
		if d_town < 300.0 or d_town > 650.0:
			continue
		var fwd := Vector3(VALLASTADEN.x - xz.x, 0.0, VALLASTADEN.y - xz.y).normalized()
		var right: Vector3 = fwd.cross(Vector3.UP).normalized()
		var start: Vector3 = Vector3(xz.x, 0.0, xz.y)
		if _line_ok(start, fwd, right, gc):
			if skip > 0:
				skip -= 1
				continue
			_start = ground(xz)
			_fwd = fwd
			_right = right
			print("advance: line at %s, %.0f m from Vallastaden" % [_start, d_town])
			return true
	return false


## Every lane open (no forest, crops, trunks or houses) for the drive and the squads'
## run ahead of it; the onboard camera sees down the field.
func _line_ok(start: Vector3, fwd: Vector3, right: Vector3, gc: GroundCover) -> bool:
	var bare: int = 0
	for i: int in LINE:
		var l: float = (float(i) - float(LINE - 1) * 0.5) * GAP_M
		for d: float in [-10.0, 15.0, 40.0, 65.0, 90.0, 115.0]:
			var p: Vector3 = start + right * l + fwd * d
			if not open_ground(Vector2(p.x, p.z), 1.6):
				return false
			var c: GroundCoverClassData = gc.class_at(p) if gc != null else null
			if c == null or c.name == "ingen":
				bare += 1
				if bare > 5:
					return false
			elif c.name == "skogsbotten" or c.height_m > 0.6:
				return false
		for d2: float in [-10.0, 25.0, 60.0, 95.0]:
			var a: Vector3 = ground_v(start + right * l + fwd * d2) + Vector3.UP * 1.3
			var b: Vector3 = ground_v(start + right * l + fwd * (d2 + 35.0)) + Vector3.UP * 1.3
			if not clear_line(a, b):
				return false
	var cam_l: float = (float(CAM_TANK) - float(LINE - 1) * 0.5) * GAP_M
	var eye: Vector3 = ground_v(start + right * cam_l) + Vector3.UP * 3.0
	return clear_line(eye, ground_v(start + fwd * 200.0) + Vector3.UP * 3.0, 2.0, false)


func physics(_delta: float) -> void:
	for i: int in tanks.size():
		var tank: Tank = tanks[i]
		_send_squad(i)
		var along: float = (tank.global_position - _start).dot(_fwd)
		var goal: Vector3 = _lane(i, along + 40.0)
		var speed: float = tank.linear_velocity.dot(_fwd)
		var throttle: float = clampf(0.45 + (SPEED_MPS - speed) * 0.3, 0.0, 1.0)
		if along > DRIVE_M + 40.0:
			throttle = 0.0
		drive_to(tank, goal, throttle)
		# Guns towards the town, each a little off.
		aim(tank, Vector3(VALLASTADEN.x, 0.0, VALLASTADEN.y) + _right * (float(i) - 3.0) * 25.0
				+ Vector3.UP * (ground_v(_start).y + 6.0 + float(i % 3)))
	for k: int in HE_TIMES_S.size():
		if once("he%d" % k, HE_TIMES_S[k]):
			_he_burst(HE_SPOTS[k])
	if t > END_S:
		done = true


## The squad gets off at once, already out ahead of its tank, and runs for the town.
func _send_squad(i: int) -> void:
	if _squads_out[i]:
		return
	var tank: Tank = tanks[i]
	var squad: Squad = tank.squad
	if squad == null or not squad.is_inside_tree():
		return
	_squads_out[i] = true
	var goal: Vector3 = _lane(i, 260.0)
	squad.order(Squad.ORDER_MOVE, goal)   # gets off behind the tank...
	squad.global_position = _lane(i, STAGGER_M[i] + 14.0 + float((i * 7) % 10))   # ...a cheat: ahead of it
	squad.set("_heading", _fwd)
	squad.call("_snap_soldiers")
	squad.order(Squad.ORDER_MOVE, goal)


## A 152 mm HE round lands in the field at (right, ahead) of the line's middle; it comes
## in from the town's side.
func _he_burst(at: Vector2) -> void:
	var mid: float = 0.0
	for tank: Tank in tanks:
		mid += (tank.global_position - _start).dot(_fwd)
	mid /= float(tanks.size())
	var target: Vector3 = ground_v(_start + _right * at.x + _fwd * (mid + at.y))
	var from: Vector3 = target + _fwd * 160.0 + Vector3.UP * 28.0
	var s := (load(SHELL_SCENE) as PackedScene).instantiate() as Shell
	get_parent().add_child(s)
	s.launch(_he, from, (target - from).normalized() * _he.muzzle_velocity_mps, player)
	cue("HE lands (%d, %d)" % [roundi(at.x), roundi(at.y)])


func frame(delta: float) -> void:
	if tanks.is_empty():
		return
	var ct: Tank = tanks[CAM_TANK]
	var tf: Transform3D = ct.get_global_transform_interpolated()
	if options.get("cam", "onboard") == "drone":
		var mid: Vector3 = Vector3.ZERO
		for tank: Tank in tanks:
			mid += tank.get_global_transform_interpolated().origin
		mid /= float(tanks.size())
		var eye: Vector3 = mid - _fwd * (26.0 - t * 0.8) + Vector3.UP * (9.0 + t * 0.9) - _right * 6.0
		look_cam(eye, mid + _fwd * 140.0 + Vector3.UP * 4.0, 58.0)
		return
	# On the tank's rear deck, left of the turret, looking ahead along the line; the
	# camera rides the hull but is eased a little so it doesn't buzz.
	var want: Vector3 = tf * Vector3(-1.1, 2.8, 2.2)
	_cam_eye = want if _cam_eye == Vector3.ZERO else _cam_eye.lerp(want, 1.0 - exp(-14.0 * delta))
	var look: Vector3 = tf * Vector3(-40.0, 1.5, -60.0)
	cam.global_transform = Transform3D(Basis.looking_at(look - _cam_eye, tf.basis.y.lerp(Vector3.UP, 0.6)), _cam_eye)
	cam.fov = 64.0
