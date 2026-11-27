extends "res://tools/trailer/trailer_shot.gd"
## Shoot and scoot, one take: a Sherman at a forest edge knocks out four tanks crossing
## the field (reload cut to RELOAD_S for the film), smokes and moves when an HE round
## lands in front of it.
##  0 s      low behind the Sherman: four enemy tanks come over the field
##  ~3       gunner's sight: two kills (the second throws its turret)
##  then     an HE round bursts just in front ("Närträff!"), dirt on the sight; still in
##           the sight the smoke goes up, then wide: the Sherman backs into it
##  then     the camera on the smoke: the last two come out through it (a cheat: they are
##           moved up behind it meanwhile), stop and search with their turrets; the
##           Sherman is gone. A round in the first one's side: the Sherman has come up
##           SCOOT_M to the side; cut to it as it swings onto the second and kills it
##  end      wide behind the Sherman over four burning wrecks
## The shot finds its own forest edge: open, flat ground with a clear view to the enemy
## line from both firing spots. Options: spot=<n> (the n-th spot found), weather=<preset>.

const ENEMIES: Array[String] = ["t34", "pz4", "t34", "bt7"]
## Enemy line: lateral offsets (m) across the Sherman's front, and depth jitter.
const LINE_OFFSETS_M: Array[float] = [-55.0, -15.0, 25.0, 65.0]
const LINE_DEPTH_M: Array[float] = [0.0, 25.0, -15.0, 10.0]
const RANGES_M: Array[float] = [240.0, 200.0, 280.0, 170.0]
const ENEMY_THROTTLE: float = 0.35
const RELOAD_S: float = 2.5
const SCOOT_M: float = 25.0
## The Sherman comes up to the new spot from this far back (out of the trees).
const COME_UP_M: float = 9.0
## Enemies stand on grass at most (no crops: they hide a tank in the sight).
const MAX_COVER_M: float = 0.6
const SIGHT_ZOOM: int = 5   # clamped to the sight's strongest step
const BACK_M: float = 9.0
const FIRE_ERR_DEG: float = 0.25
const GUNNER_AT_S: float = 3.0
const END_AFTER_S: float = 6.0
## Where the search starts: the opening's forest edge west of Haningeleden.
const FIRST_TRY: Vector2 = Vector2(400.0, 610.0)

enum Phase { FIRST_PAIR, NEAR_MISS, SMOKE, REVERSE, WATCH, STRIKE, END }

## The last two come through the smoke from behind it to these spots ((ahead, right) of
## the Sherman's old spot), then search.
const THROUGH_FROM: Array[Vector2] = [Vector2(58.0, 3.0), Vector2(72.0, 17.0)]
const THROUGH_TO: Array[Vector2] = [Vector2(13.0, 2.0), Vector2(22.0, 15.0)]
const SEARCH_S: float = 3.2

var enemies: Array[Tank] = []
var _phase: Phase = Phase.FIRST_PAIR
var _phase_t: float = 0.0
var _home: Vector3
var _fwd: Vector3
var _left: Vector3
var _scoot: Vector3
var _shot_fired_t: float = -10.0
var _kills: int = 0
var _last_kill_t: float = -1.0
var _he_point: Vector3
var _smoke_eye: Vector3
var _why_line: Dictionary = {}
var _watch_eye: Vector3
var _arrived: Array[bool] = [false, false]
var _searching_t: float = -1.0
var _sherman_up: bool = false


func _init() -> void:
	weather = "overcast"


func player_config() -> String:
	return CONFIGS["sherman"]


func setup() -> void:
	if not _find_spot():
		push_warning("no forest edge with a clear field found")
		done = true
		return
	place(player, Vector2(_home.x, _home.z), rad_to_deg(atan2(_fwd.x, -_fwd.z)))
	protect_commander(player)
	player.data.reload_time_s = RELOAD_S   # the film's cheats (this shot's tank data only):
	player.data.gunner_sight_fov_deg = PackedFloat32Array([24.0, 12.0, 7.0])   # a stronger sight
	# The wind takes the smoke forward and away from the new spot.
	var w: Vector3 = (_fwd * 0.6 - _left * 0.8).normalized() * 3.0
	Weather.current().wind_mps = Vector2(w.x, w.z)
	var right: Vector3 = -_left
	for i: int in ENEMIES.size():
		var p: Vector3 = _enemy_spot(_home, _fwd, _range, i)
		var e: Tank = spawn(ENEMIES[i], 1, Vector2(p.x, p.z), rad_to_deg(atan2(-_fwd.x, _fwd.z)) \
				+ (8.0 if i % 2 == 0 else -8.0), "Enemy%d" % i)
		make_fragile(e)
		enemies.append(e)
	var dmg: TankDamage = enemies[1].get("_damage")
	dmg.ammo_exploded = true   # the second one throws its turret
	enemies[1].data.turret_toss_min_m = 9.0
	enemies[1].data.turret_toss_max_m = 9.0
	cmd(enemies[2]).ammo_select = ammo_index(enemies[2], "HE")
	# The burst throws dirt on the sight (the rule gives a little at this distance).
	enemies[2].fired.connect(func(s: Shell) -> void:
		s.finished.connect(func(_struck: Array[Tank]) -> void:
			player.add_optics_dirt(0.9)
			shake(0.7)
			cue("HE bursts: dirt on the sight")), CONNECT_ONE_SHOT)
	# The smoke camera: the first spot with nothing (bushes count) in front of it.
	_smoke_eye = ground_v(_home - _fwd * 18.0 + _left * 9.0) + Vector3.UP * 1.3
	for off: Vector3 in [-_fwd * 16.0 - _left * 9.0, -_fwd * 18.0 + _left * 9.0, _left * 16.0 - _fwd * 4.0,
			-_left * 16.0 - _fwd * 4.0, -_fwd * 12.0 + _left * 5.0, -_fwd * 12.0 - _left * 5.0]:
		var e: Vector3 = ground_v(_home + off) + Vector3.UP * 1.3
		if clear_line(e, _home + Vector3.UP * 1.5, 0.6, false):
			_smoke_eye = e
			break
	_he_point = ground_v(_home + _fwd * 9.0 + right * 2.0)
	# The smoke camera: right of the old spot at the edge, on the smoke and the field
	# behind it (the new spot, to the left, out of the frame).
	_watch_eye = ground_v(_home + right * 16.0 - _fwd * 2.0) + Vector3.UP * 1.6
	for off2: Vector3 in [right * 16.0 - _fwd * 2.0, right * 18.0 + _fwd * 2.0, right * 13.0 - _fwd * 4.0,
			right * 20.0 + _fwd * 5.0, right * 12.0 + _fwd * 3.0]:
		var e2: Vector3 = ground_v(_home + off2) + Vector3.UP * 1.6
		if clear_line(e2, ground_v(_home + _fwd * 16.0 + right * 3.0) + Vector3.UP * 1.5, 0.8, false):
			_watch_eye = e2
			break
	for e: Tank in enemies:
		e.knocked_out.connect(_on_kill.bind(e))
	use_cam()


var _range: float = 340.0


## The forest edge: the Sherman's spot, its front and a scoot spot to its left, with
## open ground at every tank and a clear (vegetation counts) line to each enemy.
func _find_spot() -> bool:
	var skip: int = int(options.get("spot", "0"))
	var rect := Rect2(0.0, 0.0, 3380.0, 3050.0)
	var md: MapImageData = load("res://data/maps/%s_map.tres" % map) as MapImageData
	if md != null:
		rect = md.world_rect
	rect = rect.grow(-150.0)
	var tries: Array[Vector2] = [FIRST_TRY]
	for x: int in range(300, 3200, 30):
		for z: int in range(300, 2900, 30):
			tries.append(Vector2(x, z))
	var why: Dictionary = {}
	for xz: Vector2 in tries:
		var home := Vector3(xz.x, 0.0, xz.y)
		var headings: Array[int] = []
		for a: int in 16:
			var fwd := Vector3.FORWARD.rotated(Vector3.UP, a * TAU / 16.0)
			if _edge_of_forest(home, fwd, r_max()):
				headings.append(a)
		if headings.is_empty():
			continue
		why["edge"] = int(why.get("edge", 0)) + 1
		if not open_ground(xz):
			continue
		home = ground(xz)
		for a: int in headings:
			var fwd := Vector3.FORWARD.rotated(Vector3.UP, a * TAU / 16.0)
			# The new spot is to the left (the shot sets the wind to take the smoke right).
			var left: Vector3 = Vector3.UP.cross(fwd).normalized()
			var scoot: Vector3 = ground_v(home + left * SCOOT_M)
			if not open_ground(Vector2(scoot.x, scoot.z)):
				why["scoot"] = int(why.get("scoot", 0)) + 1
				continue
			var back: Vector3 = home - fwd * BACK_M
			if not open_ground(Vector2(back.x, back.z), 2.0):
				why["back"] = int(why.get("back", 0)) + 1
				continue
			# The way up to the new spot: no trunk in a tank's width.
			var from: Vector3 = scoot - fwd * COME_UP_M
			if not open_ground(Vector2(from.x, from.z), 2.0) \
					or not clear_line(from + Vector3.UP * 1.2, scoot + Vector3.UP * 1.2, 1.8):
				why["come_up"] = int(why.get("come_up", 0)) + 1
				continue
			# A forest edge: trees close behind the spot (something to back into).
			if clear_line(home + Vector3.UP * 3.0 - fwd * 6.0, home + Vector3.UP * 3.0 - fwd * 40.0, 0.0, false):
				why["no_trees"] = int(why.get("no_trees", 0)) + 1
				continue
			why["to_line"] = int(why.get("to_line", 0)) + 1
			for r: float in RANGES_M:
				if _line_clear(home, scoot, fwd, r, rect):
					if skip > 0:
						skip -= 1
						continue
					_home = home
					_fwd = fwd
					_left = left
					_scoot = scoot
					_range = r
					print("smoke: Sherman at %s facing %d deg, enemies at %.0f m" % [home, a * 360 / 16, r])
					return true
	print("smoke: no spot; ", why, " line: ", _why_line)
	return false


func r_max() -> float:
	return RANGES_M[0]


## Forest floor behind `home`, open grass (no road, house or crop) ahead of it.
func _edge_of_forest(home: Vector3, fwd: Vector3, reach: float) -> bool:
	var gc: GroundCover = GroundCover.of(self)
	if gc == null:
		return true
	var forest: int = 0
	for d: float in [12.0, 22.0, 32.0]:
		var c: GroundCoverClassData = gc.class_at(home - fwd * d)
		if c != null and c.name == "skogsbotten":
			forest += 1
	if forest < 2:
		return false
	# Ahead: grass or lawn; bare ground (roads, yards, houses) at most once.
	var bare: int = 0
	var d2: float = 0.0
	while d2 < reach * 0.8:
		var c2: GroundCoverClassData = gc.class_at(home + fwd * d2)
		if c2 == null or c2.name == "ingen":
			bare += 1
			if bare > 1:
				return false
		elif c2.height_m > MAX_COVER_M or c2.name == "skogsbotten":
			return false
		d2 += 15.0
	return true


func _line_clear(home: Vector3, scoot: Vector3, fwd: Vector3, r: float, rect: Rect2) -> bool:
	var gc: GroundCover = GroundCover.of(self)
	for i: int in ENEMIES.size():
		var p: Vector3 = _enemy_spot(home, fwd, r, i)
		if not rect.has_point(Vector2(p.x, p.z)) or not open_ground(Vector2(p.x, p.z)):
			_why_line["enemy_ground"] = int(_why_line.get("enemy_ground", 0)) + 1
			return false
		if gc != null:
			for k: int in 4:
				if gc.height_at(p - fwd * 20.0 * k) > MAX_COVER_M:
					_why_line["cover"] = int(_why_line.get("cover", 0)) + 1
					return false
		# Their path towards us must be open too (they drive ~60 m).
		var on: Vector3 = p - fwd * 60.0
		if not open_ground(Vector2(on.x, on.z), 1.6):
			_why_line["path"] = int(_why_line.get("path", 0)) + 1
			return false
		var target: Vector3 = ground_v(p) + Vector3.UP * 2.1
		for gun: Vector3 in [home, scoot]:
			# From 8 m out: the edge's own crowns over the tank only frame the view.
			if not clear_line(ground_v(gun + fwd * 8.0) + Vector3.UP * 2.6, target, 0.0, false):
				_why_line["los_%s" % ("home" if gun == home else "scoot")] = int(_why_line.get("los_%s" % ("home" if gun == home else "scoot"), 0)) + 1
				return false
	return true


func _enemy_spot(home: Vector3, fwd: Vector3, r: float, i: int) -> Vector3:
	var left: Vector3 = Vector3.UP.cross(fwd).normalized()
	# The last two stand on the new spot's side: its view of them misses the smoke.
	return ground_v(home + fwd * (r + LINE_DEPTH_M[i]) + left * LINE_OFFSETS_M[i])


func physics(_delta: float) -> void:
	if done:
		return
	_phase_t += _delta
	# The enemy line rolls towards the forest; nobody fires but the HE tank, once.
	for i: int in enemies.size():
		var e: Tank = enemies[i]
		if e.is_knocked_out():
			stop(e)
			continue
		if _phase >= Phase.WATCH:
			_through(i - 2)
			continue
		drive_to(e, e.global_position - e.global_basis.z * 50.0, ENEMY_THROTTLE)
		if i == 2:
			aim_ballistic(e, _he_point)
		else:
			aim(e, player.global_position + Vector3.UP * 1.5)
		cmd(e).fire = false
	var c: TankCommand = cmd(player)
	c.fire = false
	c.smoke = false
	match _phase:
		Phase.FIRST_PAIR:
			stop(player)
			_hunt([0, 1])
			if _kills >= 2 and t > _last_kill_t + 1.2:
				_set_phase(Phase.NEAR_MISS)
		Phase.NEAR_MISS:
			stop(player)
			_aim_next([2, 3])
			if once("he", 0.0):
				cmd(enemies[2]).fire = true
				cue("enemy HE fired (lands in front)")
			if _phase_t > 1.6:
				_set_phase(Phase.SMOKE)
		Phase.SMOKE:
			stop(player)
			if once("smoke", 0.0):
				c.smoke = true
				cue("smoke salvo")
			if _phase_t > 2.4:
				_set_phase(Phase.REVERSE)
		Phase.REVERSE:
			if once("reverse", 0.0):
				cue("backing into the smoke")
			c.throttle = -0.8
			c.steering = 0.0
			if _phase_t > 3.0:
				_set_phase(Phase.WATCH)
		Phase.WATCH:
			# Cut away: the Sherman is put in the trees by the new spot, the last two
			# behind the smoke; the Sherman creeps up while they come through.
			if once("move", 0.0):
				var from: Vector3 = _scoot - _fwd * COME_UP_M
				place(player, Vector2(from.x, from.z), rad_to_deg(atan2(_fwd.x, -_fwd.z)))
				var toward_us: float = rad_to_deg(atan2(-_fwd.x, _fwd.z))
				for k: int in 2:
					var p: Vector3 = _home + _fwd * THROUGH_FROM[k].x - _left * THROUGH_FROM[k].y
					place(enemies[k + 2], Vector2(p.x, p.z), toward_us)
					enemies[k + 2].linear_velocity = -_fwd * 4.0
				cue("on the smoke: the last two come through it (Sherman moved)")
			_aim_next([2, 3])
			if not _sherman_up and drive_to(player, _scoot + _fwd * 1.0, 0.45) < 1.5:
				_sherman_up = true
				cue("Sherman at the new spot")
			if _sherman_up:
				stop(player)
			if _arrived[0] and _arrived[1] and _searching_t < 0.0:
				_searching_t = t
				cue("they search")
			if (_searching_t >= 0.0 and t > _searching_t + SEARCH_S and _sherman_up) or _phase_t > 20.0:
				_set_phase(Phase.STRIKE)
		Phase.STRIKE:
			stop(player)
			# Close by: the lay is a degree or two off the turret's centre line.
			_hunt([2, 3], 2.0)
			if _kills >= 4:
				_set_phase(Phase.END)
		Phase.END:
			stop(player)
			if _phase_t > END_AFTER_S:
				done = true
	if t > 80.0:
		done = true


func _set_phase(p: Phase) -> void:
	_phase = p
	_phase_t = 0.0


## Lays on the first living tank of `which` (lead and drop allowed for) and fires when on.
func _hunt(which: Array, tol: float = FIRE_ERR_DEG) -> void:
	var e: Tank = _aim_next(which)
	if e == null or t < GUNNER_AT_S + 0.8:
		return
	var c: TankCommand = cmd(player)
	var muzzle: Transform3D = player.get_muzzle_transform()
	var err: float = rad_to_deg((-muzzle.basis.z).angle_to(c.aim_point - muzzle.origin))
	if err < tol and player.is_loaded() and t > _shot_fired_t + 0.5:
		c.fire = true
		_shot_fired_t = t
		cue("FIRE at %s" % e.name)


## One of the last two (k 0/1) comes through the smoke to its spot, then searches with
## its turret: sweeps ahead and to the right, never towards the Sherman's new spot.
func _through(k: int) -> void:
	var e: Tank = enemies[k + 2]
	cmd(e).fire = false
	var to: Vector3 = ground_v(_home + _fwd * THROUGH_TO[k].x - _left * THROUGH_TO[k].y)
	if not _arrived[k]:
		if drive_to(e, to, 0.5) < 2.5:
			_arrived[k] = true
		aim(e, e.global_position - e.global_basis.z * 100.0 + Vector3.UP * 1.5)
		return
	stop(e)
	var centre: Vector3 = (-_fwd - _left * 0.6).normalized()
	var swing: float = sin((t - maxf(_searching_t, 0.0)) * 0.9 + float(k) * 2.1) * deg_to_rad(65.0)
	aim(e, e.global_position + centre.rotated(Vector3.UP, swing) * 80.0 + Vector3.UP * 1.5)


func _aim_next(which: Array) -> Tank:
	for i: int in which:
		var e: Tank = enemies[i]
		if e.is_knocked_out():
			continue
		var shell: ShellData = player.get_loaded_shell()
		if shell == null:
			shell = player.data.ammo[player.get_ammo_index()]
		var d: float = player.global_position.distance_to(e.global_position)
		var lead: Vector3 = e.linear_velocity * d / maxf(shell.muzzle_velocity_mps, 1.0)
		aim_ballistic(player, e.global_position + lead + Vector3.UP * 0.6)
		return e
	return null


func _on_kill(e: Tank) -> void:
	_kills += 1
	_last_kill_t = t
	cue("%s knocked out (%d)" % [e.name, _kills])


func frame(_delta: float) -> void:
	if enemies.is_empty():
		return
	var sherman_c: Vector3 = player.get_global_transform_interpolated().origin
	var right: Vector3 = -_left
	match _phase:
		Phase.FIRST_PAIR:
			if t < GUNNER_AT_S:
				# Low behind the Sherman's right shoulder, over the field.
				var eye: Vector3 = ground_v(sherman_c - _fwd * 7.0 + right * 3.0) + Vector3.UP * 1.4
				var mid: Vector3 = Vector3.ZERO
				for e: Tank in enemies:
					mid += e.global_position
				look_cam(eye, mid / float(enemies.size()) + Vector3.UP * 1.0, 30.0)
			elif once("gunner_%d" % _phase, 0.0):
				use_gunner(SIGHT_ZOOM)
				cue("gunner's sight")
		Phase.NEAR_MISS, Phase.SMOKE:
			pass   # still in the sight: the burst, the dirt, the smoke going up
		Phase.REVERSE:
			if once("wide_smoke", 0.0):
				use_cam()
				cue("wide: smoke")
			# Low, behind and to the left: the Sherman backs towards us out of the smoke.
			look_cam(_smoke_eye, sherman_c + Vector3.UP * 1.2 + _fwd * 6.0, 46.0)
		Phase.WATCH, Phase.STRIKE:
			if _kills < 3 or t < _last_kill_t + 1.3:
				# On the smoke at the old spot; they come out of it and search.
				if once("watch_cam", 0.0):
					use_cam()
				look_cam(_watch_eye, ground_v(_home + _fwd * 16.0 - _left * 3.0) + Vector3.UP * 1.6, 48.0)
			else:
				if once("new_spot_cam", 0.0):
					cue("the Sherman at its new spot")
				# Behind the Sherman's shoulder at the new spot, on the last one.
				var e3: Vector3 = enemies[3].get_global_transform_interpolated().origin
				var to_e: Vector3 = (e3 - sherman_c)
				to_e.y = 0.0
				to_e = to_e.normalized()
				var eye: Vector3 = sherman_c - to_e * 8.0 + Vector3.UP * 2.6 + to_e.cross(Vector3.UP) * 2.5
				look_cam(eye, e3 + Vector3.UP * 1.0, 44.0)
		Phase.END:
			# Back on the smoke: the two burning where they searched.
			look_cam(_watch_eye, ground_v(_home + _fwd * 16.0 - _left * 3.0) + Vector3.UP * 1.6, 48.0)
