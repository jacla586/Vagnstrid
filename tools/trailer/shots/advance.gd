extends "res://tools/trailer/trailer_shot.gd"
## Filler: seven T-34s advance in line over the field south-east of Vallastaden, their
## squads running a little ahead; HE rounds burst in the field. About 11 s, cut 4-5 from it.
##  cam=onboard (default)  riding on one of the tanks, behind the turret, the line beside
##  cam=drone              behind and above the line, rising, the town ahead; burning
##                         wrecks in the field and enemy tanks at the town's edge firing HE
##  cam=commander          the own tank rolls in the line: buttoned up (periscope), the
##                         hatch opens on the move, the commander looks along the line
##                         (tanks, running squads) and back ahead as the HE comes
## The line finds its own start: open ground for every tank and the squads, Vallastaden
## (VALLASTADEN) ahead. Cheats: the squads start out ahead of the tanks (no dismount),
## the HE rounds come from nowhere (their shooter is the parked player tank, so the bursts
## spare the own team). Options: weather=<preset>, spot=<n>.

const LINE: int = 7
const GAP_M: float = 20.0
const STAGGER_M: Array[float] = [6.0, -4.0, 3.0, -2.0, 5.0, -3.0, -12.0]   # the camera's tank last, behind
const SPEED_MPS: float = 4.2
const CAM_TANK: int = 6   # the right end: it sees the line slant off towards the town
## Middle of Vallastaden's blocks (map metres; road_to_science grown 2026-11-20, origin moved 1350 m W and 1610 m N).
const VALLASTADEN: Vector2 = Vector2(3310.0, 2430.0)
const DRIVE_M: float = 60.0
const HE_TIMES_S: Array[float] = [2.2, 4.6, 7.4]   # after the line starts rolling
const HE_SPOTS: Array[Vector2] = [Vector2(10.0, 60.0), Vector2(-35.0, 45.0), Vector2(30.0, 85.0)]   # (right, ahead) of the line
const END_S: float = 11.0
## cam=drone: the shot runs longer (the end title lies over it).
const DRONE_END_S: float = 14.0
## cam=commander: when the hatch opens and the line starts rolling, and how long it rolls.
const HATCH_OPEN_S: float = 2.4
const ROLL_S: float = 0.0
const COMMANDER_ROLL_FOR_S: float = 12.5
## Commander's look (cam=commander): [t, yaw left of the hull's front (deg), pitch (deg)].
const LOOK: Array = [
	[0.0, 6.0, -1.0], [2.2, 10.0, -1.0], [3.2, 16.0, -2.0], [5.0, 58.0, -3.0], [6.6, 66.0, -2.5],
	[8.2, 16.0, -1.0], [10.0, 8.0, -0.5], [20.0, 6.0, -0.5]]
## cam=drone: burnt-out tanks in the field (ahead m, right m), and enemies at the town's edge.
const WRECK_SPOTS: Array[Vector2] = [Vector2(75.0, -95.0), Vector2(95.0, 90.0), Vector2(125.0, -30.0),
		Vector2(135.0, 45.0), Vector2(160.0, -110.0), Vector2(175.0, 120.0), Vector2(150.0, 5.0),
		Vector2(205.0, -60.0)]
const WRECK_KINDS: Array[String] = ["pz4", "t34", "bt7", "sherman", "pz4", "t34", "kv2", "bt7"]
const ENEMY_KINDS: Array[String] = ["pz4", "t34", "pz4", "kv2"]
const ENEMY_AHEAD_M: float = 330.0
const ENEMY_SPREAD_M: float = 55.0
## (time after rolling, enemy index, (right, ahead) of the line's middle where its HE lands).
const ENEMY_FIRE: Array = [[1.2, 0, Vector2(-60.0, 110.0)], [3.4, 2, Vector2(45.0, 95.0)],
		[5.6, 1, Vector2(-10.0, 120.0)], [8.0, 3, Vector2(70.0, 105.0)], [9.8, 0, Vector2(-40.0, 90.0)]]

var tanks: Array[Tank] = []
var _start: Vector3
var _fwd: Vector3
var _right: Vector3
var _squads_out: Array[bool] = []
var _he: ShellData = preload("res://data/shells/he_152.tres")
var _cam_eye: Vector3 = Vector3.ZERO
var _enemies: Array[Tank] = []
var _mode: String = "onboard"


func _init() -> void:
	map = "road_to_science"
	weather = "clear"


func setup() -> void:
	_mode = options.get("cam", "onboard")
	if not _find_line():
		push_warning("no open line towards Vallastaden")
		done = true
		return
	var heading: float = rad_to_deg(atan2(_fwd.x, -_fwd.z))
	if _mode != "commander":
		place(player, Vector2(_start.x - _fwd.x * 300.0, _start.z - _fwd.z * 300.0), 0.0)   # out of the way
	for i: int in LINE:
		var p: Vector3 = _lane(i, STAGGER_M[i])
		var tank: Tank
		if _mode == "commander" and i == CAM_TANK:
			tank = player
			place(player, Vector2(p.x, p.z), heading)
		else:
			tank = spawn("t34", 0, Vector2(p.x, p.z), heading, "Line%d" % i)
		protect_commander(tank)
		tanks.append(tank)
		_squads_out.append(false)
	if _mode == "drone":
		_make_wrecks()
		_make_enemies()
	if _mode == "commander":
		use_commander()
		cmd(player).hatch_open = false
		# The roof MG's gun filled the lower middle of the commander's view.
		var gun := player.get_node_or_null("Visual/Turret/RoofMG/Pitch/Gun") as MeshInstance3D
		if gun != null:
			gun.layers = 1 << (CommanderCamera.OWN_COMMANDER_LAYER - 1)
	else:
		use_cam()


func started() -> void:
	for tank: Tank in tanks:
		tank.linear_velocity = _fwd * SPEED_MPS


## Seconds since the line began rolling (negative before).
func _rolling_t() -> float:
	return t - (ROLL_S if _mode == "commander" else 0.0)


## Earlier victims burning in the field ahead (knocked out at setup: the turrets that
## fly have landed by the time the action starts).
func _make_wrecks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in WRECK_SPOTS.size():
		var p: Vector3 = _start + _fwd * WRECK_SPOTS[i].x + _right * WRECK_SPOTS[i].y
		if not open_ground(Vector2(p.x, p.z), 2.0):
			continue
		var w: Tank = spawn(WRECK_KINDS[i], 1, Vector2(p.x, p.z), rng.randf_range(0.0, 360.0), "Wreck%d" % i)
		if i % 2 == 1:
			var dmg: TankDamage = w.get("_damage")
			dmg.ammo_exploded = true
			w.data.turret_toss_min_m = 2.0
			w.data.turret_toss_max_m = 5.0
		w.call("_knock_out")


## Enemy tanks at the town's edge, facing the line; they fire HE into the field.
func _make_enemies() -> void:
	var heading: float = rad_to_deg(atan2(-_fwd.x, _fwd.z))
	for i: int in ENEMY_KINDS.size():
		var lat: float = (float(i) - float(ENEMY_KINDS.size() - 1) * 0.5) * ENEMY_SPREAD_M
		var found: bool = false
		for back: float in [0.0, -25.0, 25.0, -50.0, 50.0]:
			var p: Vector3 = _start + _fwd * (ENEMY_AHEAD_M + back) + _right * lat
			if open_ground(Vector2(p.x, p.z), 2.0):
				var e: Tank = spawn(ENEMY_KINDS[i], 1, Vector2(p.x, p.z), heading + (i * 7 % 11 - 5), "Enemy%d" % i)
				cmd(e).ammo_select = ammo_index(e, "HE")
				_enemies.append(e)
				found = true
				break
		if not found:
			_enemies.append(null)


func _lane(i: int, ahead: float) -> Vector3:
	return ground_v(_start + _right * (float(i) - float(LINE - 1) * 0.5) * GAP_M + _fwd * ahead)


func _find_line() -> bool:
	var skip: int = int(options.get("spot", "0"))
	var tries: Array[Vector2] = []
	for x: int in range(3450, 4100, 25):
		for z: int in range(2310, 3010, 25):
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
	var rt: float = _rolling_t()
	if _mode == "commander":
		cmd(player).hatch_open = t >= HATCH_OPEN_S
		if once("hatch", HATCH_OPEN_S):
			cue("hatch opens")
	for i: int in tanks.size():
		var tank: Tank = tanks[i]
		_send_squad(i)
		if rt < 0.0:
			stop(tank)
			aim(tank, tank.global_position - tank.global_basis.z * 300.0 + Vector3.UP * 1.5)
			continue
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
	if rt >= 0.0:
		for k: int in HE_TIMES_S.size():
			if HE_TIMES_S[k] + 0.0 < rt and once("he%d" % k, 0.0):
				_he_burst(HE_SPOTS[k])
	_enemy_fire(rt)
	var end: float = DRONE_END_S if _mode == "drone" else END_S
	if _mode == "commander":
		end = ROLL_S + COMMANDER_ROLL_FOR_S
	if t > end:
		done = true


## The enemies at the town's edge: guns on the field, HE at the times in ENEMY_FIRE.
func _enemy_fire(rt: float) -> void:
	if _enemies.is_empty():
		return
	var mid: float = 0.0
	for tank: Tank in tanks:
		mid += (tank.global_position - _start).dot(_fwd)
	mid /= float(tanks.size())
	for e: Tank in _enemies:
		if e != null:
			cmd(e).fire = false
			stop(e)
	for k: int in ENEMY_FIRE.size():
		var row: Array = ENEMY_FIRE[k]
		var e: Tank = _enemies[int(row[1])]
		if e == null:
			continue
		var at: Vector2 = row[2]
		var target: Vector3 = ground_v(_start + _right * at.x + _fwd * (mid + at.y))
		if rt > float(row[0]) - 2.5 and rt < float(row[0]) + 0.5:
			aim_ballistic(e, target)
		if rt >= float(row[0]) and e.is_loaded() and once("enemy_fire%d" % k, 0.0):
			cmd(e).fire = true
			cue("%s fires HE" % e.name)


## The squad gets off at once, already out ahead of its tank, and runs for the town (with
## cam=commander it kneels there until the line rolls).
func _send_squad(i: int) -> void:
	var tank: Tank = tanks[i]
	var squad: Squad = tank.squad
	if squad == null or not squad.is_inside_tree():
		return
	var goal: Vector3 = _lane(i, 260.0)
	if _squads_out[i]:
		if _rolling_t() >= 0.0 and once("squad_run%d" % i, 0.0):
			squad.order(Squad.ORDER_MOVE, goal)
		return
	_squads_out[i] = true
	var spot: Vector3 = _lane(i, STAGGER_M[i] + 14.0 + float((i * 7) % 10))
	squad.order(Squad.ORDER_MOVE, goal)   # gets off behind the tank...
	squad.global_position = spot   # ...a cheat: ahead of it
	squad.set("_heading", _fwd)
	squad.call("_snap_soldiers")
	squad.order(Squad.ORDER_MOVE, goal if _rolling_t() >= 0.0 else spot)


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
	if _mode == "commander":
		var look: Vector2 = _look_at_time(t)
		commander_look(yaw_of(-player.global_basis.z) + deg_to_rad(look.x), deg_to_rad(look.y))
		return
	if _mode == "drone":
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


func _look_at_time(time: float) -> Vector2:
	for i: int in range(LOOK.size() - 1):
		var a: Array = LOOK[i]
		var b: Array = LOOK[i + 1]
		if time <= float(b[0]):
			var w: float = ease_in_out((time - float(a[0])) / (float(b[0]) - float(a[0])))
			return Vector2(lerpf(a[1], b[1], w), lerpf(a[2], b[2], w))
	var last: Array = LOOK[LOOK.size() - 1]
	return Vector2(last[1], last[2])
