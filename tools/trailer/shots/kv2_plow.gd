extends "res://tools/trailer/trailer_shot.gd"
## Two T-34s on an open field, a KV-2 that shrugs them off, one take:
##  0 s     straight down on two T-34s firing at targets out of sight, re-laying, firing
##  ~7      the camera cranes down behind them: a field full of burning wrecks and turrets
##  ~10     they cease fire. Then a KV-2 comes through the smoke and ploughs through the
##          wrecks (a low camera at one it shoves aside); the T-34s fire: ping, ping, ping
##  then    the KV-2 stops and fires: the first T-34's turret flies absurdly far
##  end=flank (default): the second T-34 puts HE in the KV-2's track while its 152 mm
##          reloads, drives round it (the box turret can't keep up) and kills it from
##          behind: its turret goes
##  end=kv: the KV-2 takes the second T-34 too
## Cheats (this shot's tank data only): the T-34s reload in RELOAD_S, their AP can't get
## through the KV-2 until the shot from behind (which always kills), the wrecks are light,
## the thrown turret gets a push, the HE always throws the track. Options: end=flank|kv,
## weather=<preset>, spot=<n>.

const RELOAD_S: float = 2.5
const PAIR_GAP_M: float = 7.0       # each T-34 this far to the side of the spot
const KV_START_M: float = 175.0
const KV_STOP_M: float = 85.0
const KV_GO_S: float = 8.0
const CEASE_FIRE_S: float = 10.0
const PING_FROM_S: float = 12.5
const WRECKS: int = 14
const BURNING: int = 8
const WRECK_MASS_KG: float = 1500.0
const PING_PEN_MM: float = 20.0
const FIRE_ERR_DEG: float = 0.35
const FLING_UP_MPS: float = 21.0
const FLING_AWAY_MPS: float = 13.0
const END_HOLD_S: float = 6.0
## Where the search starts: the smoke shot's field west of the forest.
const FIRST_TRY: Vector2 = Vector2(570.0, 1380.0)

enum Phase { OPEN_FIRE, PAUSE, KV_COMING, KV_FIRES, HE_SHOT, FLANK, REAR_SHOT, KV_SECOND, END }

var t34a: Tank
var kv: Tank
var _phase: Phase = Phase.OPEN_FIRE
var _phase_t: float = 0.0
var _home: Vector3
var _fwd: Vector3
var _right: Vector3
var _targets: Dictionary = {}       # Tank -> its current made-up target
var _wreck_tanks: Array[Tank] = []
var _lane_wreck: Node3D
var _plow_t: float = -1.0           # when the KV-2 came within reach of the lane wreck
var _shoved: Dictionary = {}        # wreck -> true once pushed aside
var _waypoints: Array[Vector3] = []
var _wp: int = 0
var _he_landed_t: float = -1.0
var _he_fired: bool = false
var _kill_t: float = -1.0
var _end_t: float = -1.0
var _ap: ShellData
var _ping: SoundSetData = preload("res://data/sounds/ping.tres")
var _look: Vector3
var _overhead_end: Transform3D
var _pings: int = 0
var _rear_fire_t: float = -1.0
var _chase_eye: Vector3 = Vector3.ZERO


func _init() -> void:
	weather = "overcast"


func setup() -> void:
	if not _find_spot():
		push_warning("no open field found")
		done = true
		return
	var heading: float = rad_to_deg(atan2(_fwd.x, -_fwd.z))
	place(player, Vector2(_home.x + _right.x * PAIR_GAP_M, _home.z + _right.z * PAIR_GAP_M), heading)
	t34a = spawn("t34", 0, Vector2(_home.x - _right.x * PAIR_GAP_M, _home.z - _right.z * PAIR_GAP_M),
			heading, "T34a")
	for tank: Tank in [player, t34a]:
		protect_commander(tank)
	# The T-34s share one TankData: a fast loader and AP that pings off the KV-2.
	player.data.reload_time_s = RELOAD_S
	player.data.ammo = player.data.ammo.duplicate()
	var ap_i: int = ammo_index(player, "AP")
	_ap = player.data.ammo[ap_i].duplicate()
	_ap.penetration_mm = PING_PEN_MM
	player.data.ammo[ap_i] = _ap
	var kv_at: Vector3 = ground_v(_home + _fwd * KV_START_M)
	kv = spawn("kv2", 1, Vector2(kv_at.x, kv_at.z), heading + 180.0, "KV2")
	kv.struck.connect(_on_kv_struck)
	_make_wreck_field()
	for tank: Tank in [player, t34a]:
		_targets[tank] = _new_target(Vector3.ZERO)
	_look = kv.global_position
	use_cam()


# --- The place ---------------------------------------------------------------------

func _find_spot() -> bool:
	var skip: int = int(options.get("spot", "0"))
	var tries: Array[Vector2] = [FIRST_TRY]
	for x: int in range(300, 3200, 40):
		for z: int in range(300, 2900, 40):
			tries.append(Vector2(x, z))
	for xz: Vector2 in tries:
		if not open_ground(xz):
			continue
		var home: Vector3 = ground(xz)
		for a: int in 16:
			var fwd := Vector3.FORWARD.rotated(Vector3.UP, a * TAU / 16.0)
			if _field_ok(home, fwd):
				if skip > 0:
					skip -= 1
					continue
				_home = home
				_fwd = fwd
				_right = fwd.cross(Vector3.UP).normalized()
				print("kv2_plow: T-34s at %s, heading %d" % [home, a])
				return true
	return false


## Open, flat-ish grass ahead (no forest, crops or trees) far enough for the KV-2's
## drive, room for the flank, both T-34s on open ground and a camera view over it all.
func _field_ok(home: Vector3, fwd: Vector3) -> bool:
	var gc: GroundCover = GroundCover.of(self)
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var bare: int = 0
	for d: float in range(30, int(KV_START_M) + 31, 15):
		for l: float in [-60.0, -30.0, 0.0, 30.0, 60.0]:
			var p: Vector3 = home + fwd * d + right * l
			var c: GroundCoverClassData = gc.class_at(p) if gc != null else null
			if c == null or c.name == "ingen":
				bare += 1
				if bare > 6:
					return false
			elif c.name == "skogsbotten" or c.height_m > 0.6:
				return false
	for side: float in [-PAIR_GAP_M, 0.0, PAIR_GAP_M]:
		var p2: Vector3 = home + right * side
		if not open_ground(Vector2(p2.x, p2.z)):
			return false
		var c2: GroundCoverClassData = gc.class_at(p2) if gc != null else null
		if c2 == null or c2.name == "ingen":
			return false   # on grass, not a road or a yard
	for p3: Vector3 in _flank_points(home, fwd, right) + [home + fwd * KV_START_M, home + fwd * KV_STOP_M]:
		if not open_ground(Vector2(p3.x, p3.z), 1.6):
			return false
	# No trunk or house in the field: rows of short segments a metre over the ground.
	for l2: float in [-45.0, -15.0, 0.0, 15.0, 45.0]:
		for d2: float in range(15, int(KV_START_M) + 30, 30):
			var a3: Vector3 = ground_v(home + fwd * d2 + right * l2) + Vector3.UP * 1.3
			var b3: Vector3 = ground_v(home + fwd * (d2 + 30.0) + right * l2) + Vector3.UP * 1.3
			if not clear_line(a3, b3):
				return false
	# The crane's view and the T-34s' line to the KV-2 (crowns count).
	if not clear_line(home + Vector3.UP * 4.0, ground_v(home + fwd * KV_START_M) + Vector3.UP * 2.0, 3.0, false):
		return false
	return true


## The second T-34's way round the stopped KV-2: its side, then its rear quarter.
func _flank_points(home: Vector3, fwd: Vector3, right: Vector3) -> Array[Vector3]:
	var stop_at: Vector3 = home + fwd * KV_STOP_M
	return [stop_at + right * 34.0 - fwd * 22.0, stop_at + right * 36.0 + fwd * 8.0,
			stop_at + right * 22.0 + fwd * 28.0]


## Earlier victims: tanks knocked out where they stand (most throw their turret), made
## into light wrecks, eight of them burning. Two lie in the KV-2's lane.
func _make_wreck_field() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var spots: Array[Vector3] = [_home + _fwd * 118.0 + _right * 2.0, _home + _fwd * 146.0 - _right * 2.5]
	var tries: int = 0
	while spots.size() < WRECKS and tries < 400:
		tries += 1
		var d: float = rng.randf_range(55.0, 215.0)
		var l: float = rng.randf_range(-65.0, 65.0)
		if absf(l) < 9.0:
			continue   # the lane: only the two above
		if l > 12.0 and d < 125.0:
			continue   # the flank's way
		var p: Vector3 = _home + _fwd * d + _right * l
		var near: bool = false
		for q: Vector3 in spots:
			if q.distance_to(p) < 17.0:
				near = true
		if near or not open_ground(Vector2(p.x, p.z), 2.0):
			continue
		spots.append(p)
	var kinds: Array[String] = ["pz4", "t34", "bt7", "sherman", "t34", "pz4", "bt7"]
	for i: int in spots.size():
		var kind: String = kinds[i % kinds.size()]
		var w: Tank = spawn(kind, 1, Vector2(spots[i].x, spots[i].z), rng.randf_range(0.0, 360.0), "Victim%d" % i)
		if i >= 2 and rng.randf() < 0.65:
			var dmg: TankDamage = w.get("_damage")
			dmg.ammo_exploded = true
			w.data.turret_toss_min_m = 2.0
			w.data.turret_toss_max_m = 7.0
			w.data.turret_toss_side_mps = 3.0
		w.call("_knock_out")
		_wreck_tanks.append(w)


## Once the turrets have landed the burnt-out tanks become plain wrecks (cheap, pushable).
func _settle_wrecks() -> void:
	for i: int in _wreck_tanks.size():
		var w: Tank = _wreck_tanks[i]
		w.leave_wreck()
		var wrecks: Array[Node] = get_tree().get_nodes_in_group(&"wrecks")
		var wreck: Wreck = null
		for j: int in range(wrecks.size() - 1, -1, -1):
			if wrecks[j] is Wreck:
				wreck = wrecks[j]
				break
		var fire: Node3D = w.get("_burning")
		if fire != null:
			if i >= 2 and i < BURNING + 2 and wreck != null:   # the lane's two don't burn (hide the KV-2)
				fire.reparent(wreck, true)
			else:
				fire.queue_free()
		if wreck != null:
			wreck.mass = WRECK_MASS_KG
			(wreck.physics_material_override as PhysicsMaterial).friction = 0.45
			if i == 0:
				_lane_wreck = wreck
		w.queue_free()
	_wreck_tanks.clear()


# --- Action ------------------------------------------------------------------------

func physics(_delta: float) -> void:
	for tank: Tank in [player, t34a, kv]:
		cmd(tank).fire = false
	if once("settle", 3.0):
		_settle_wrecks()
	_plough()
	var pt: float = t - _phase_t
	match _phase:
		Phase.OPEN_FIRE:
			for tank: Tank in [player, t34a]:
				_fire_at_nothing(tank)
			if t >= CEASE_FIRE_S:
				_set_phase(Phase.PAUSE)
				cue("cease fire: the field of wrecks")
		Phase.PAUSE, Phase.KV_COMING:
			for tank: Tank in [player, t34a]:
				if t < PING_FROM_S:
					aim(tank, tank.global_position - tank.global_basis.z * 300.0 + Vector3.UP * 1.0)
				else:
					_ping_at_kv(tank)
			if t >= KV_GO_S:
				if _phase == Phase.PAUSE:
					_set_phase(Phase.KV_COMING)
					cue("the KV-2 comes")
				var goal: Vector3 = _home
				aim(kv, goal + Vector3.UP * 1.5)
				if _flat(kv.global_position - _home).length() > KV_STOP_M:
					drive_to(kv, goal, 1.0)
				else:
					stop(kv)
					_set_phase(Phase.KV_FIRES)
					cue("the KV-2 stops")
					var dmg: TankDamage = t34a.get("_damage")
					make_fragile(t34a)
					dmg.ammo_exploded = true
					t34a.turret_tossed.connect(_fling.bind(t34a), CONNECT_ONE_SHOT)
					t34a.knocked_out.connect(_on_t34a_out, CONNECT_ONE_SHOT)
		Phase.KV_FIRES:
			_ping_at_kv(player)
			if t34a.is_knocked_out():
				aim(t34a, t34a.global_position - t34a.global_basis.z * 50.0)
			else:
				_ping_at_kv(t34a)
				_fire_at(kv, _turret_of(t34a), pt > 1.4, 0.4)
			if _kill_t >= 0.0 and t > _kill_t + 4.5:
				if options.get("end", "flank") == "kv":
					_set_phase(Phase.KV_SECOND)
					kv.data.reload_time_s = 4.0
					# The 152 mm's reload already running counts on: cut it short too.
					kv.set("_reload_remaining", minf(float(kv.get("_reload_remaining")), 2.5))
					make_fragile(player)
					var dmg2: TankDamage = player.get("_damage")
					dmg2.ammo_exploded = true
					player.turret_tossed.connect(_fling.bind(player), CONNECT_ONE_SHOT)
					player.knocked_out.connect(func() -> void:
						cue("the second T-34 goes too")
						_end_t = t, CONNECT_ONE_SHOT)
				else:
					_set_phase(Phase.HE_SHOT)
					cmd(player).ammo_select = ammo_index(player, "HE")
					cue("gunner's sight: HE")
					player.fired.connect(func(s: Shell) -> void:
						_he_fired = true
						cue("HE at the track")
						s.finished.connect(func(_struck: Array[Tank]) -> void:
							_he_landed_t = t), CONNECT_ONE_SHOT)
		Phase.HE_SHOT:
			aim(kv, _turret_of(player))
			if not _he_fired:
				_fire_at(player, _track_point(), pt > 2.2 and player.get_loaded_shell().short_name == "HE", 0.3)
			elif _he_landed_t >= 0.0 and t > _he_landed_t + 0.3:
				var dmg3: TankDamage = kv.get("_damage")
				if not dmg3.is_immobilised():
					push_warning("the HE missed the track: throwing it by hand")
					dmg3.apply_mine(_track_id())
				if once("tracked", 0.0):
					cue("track broken")
				if t > _he_landed_t + 1.4:
					_waypoints = _flank_points(_home, _fwd, _right)
					# The cut hides a jump: the T-34 is already on its way, at the first point.
					var from: Vector3 = _waypoints[0]
					var along: Vector3 = _flat(_waypoints[1] - from).normalized()
					place(player, Vector2(from.x, from.z), rad_to_deg(atan2(along.x, -along.z)))
					player.linear_velocity = along * 8.0
					_wp = 1
					cmd(player).ammo_select = ammo_index(player, "AP")
					_set_phase(Phase.FLANK)
					cue("round it")
		Phase.FLANK:
			aim(kv, _turret_of(player))
			aim(player, kv.global_position + Vector3.UP * 1.5)
			var wp: Vector3 = ground_v(_waypoints[_wp])
			if drive_to(player, wp, 1.0) < 7.0:
				_wp += 1
				if _wp >= _waypoints.size():
					stop(player)
					_set_phase(Phase.REAR_SHOT)
					cue("behind it")
					_ap.penetration_mm = 400.0   # the rear always gives
					make_fragile(kv)
					var dmg4: TankDamage = kv.get("_damage")
					dmg4.ammo_exploded = true
					kv.data.turret_toss_min_m = 12.0
					kv.data.turret_toss_max_m = 12.0
					kv.data.turret_toss_side_mps = 2.0
					kv.knocked_out.connect(func() -> void:
						cue("KV-2 knocked out")
						_end_t = t, CONNECT_ONE_SHOT)
		Phase.REAR_SHOT:
			if not kv.is_knocked_out():
				aim(kv, _turret_of(player))
				# The turret's rear (the hull's is below the gun's depression this close).
				_fire_at(player, kv.to_global(kv.get_turret_local_position() + Vector3(0.0, 0.3, 1.3)),
						pt > 1.0 and player.get_loaded_shell().short_name == "AP", 2.0)
				if cmd(player).fire and _rear_fire_t < 0.0:
					_rear_fire_t = t
					cue("fire from behind")
				# This close the lay is ~1° off (the gun sits off the turret's centre): if
				# the round hasn't done it by the time it gets there, the KV-2 goes anyway.
				var flight: float = player.global_position.distance_to(kv.global_position) / _ap.muzzle_velocity_mps
				if _rear_fire_t >= 0.0 and t > _rear_fire_t + flight + 2.0 / 60.0:
					effect(&"impact_armour", _turret_of(kv), 1.5)
					kv.call("_knock_out")
			if _end_t >= 0.0:
				_set_phase(Phase.END)
		Phase.KV_SECOND:
			_ping_at_kv(player)
			_fire_at(kv, _turret_of(player), true, 0.4)
			if _end_t >= 0.0:
				_set_phase(Phase.END)
		Phase.END:
			stop(player)
			if t > _end_t + END_HOLD_S:
				done = true


func _set_phase(p: Phase) -> void:
	_phase = p
	_phase_t = t


## Lays on `point` (drop allowed for) and fires when `ok`, loaded and within `tol` degrees.
func _fire_at(tank: Tank, point: Vector3, ok: bool, tol: float) -> void:
	aim_ballistic(tank, point)
	if not ok or not tank.is_loaded():
		return
	var muzzle: Transform3D = tank.get_muzzle_transform()
	var err: float = rad_to_deg((-muzzle.basis.z).angle_to(cmd(tank).aim_point - muzzle.origin))
	if err < tol:
		cmd(tank).fire = true


## The opening: targets nobody sees, 350-650 m out; after each shot the next lay is a
## little off the last (most of the time) or a new target.
func _fire_at_nothing(tank: Tank) -> void:
	var target: Vector3 = _targets[tank]
	aim_ballistic(tank, target)
	if not tank.is_loaded():
		return
	var muzzle: Transform3D = tank.get_muzzle_transform()
	var err: float = rad_to_deg((-muzzle.basis.z).angle_to(cmd(tank).aim_point - muzzle.origin))
	if err < FIRE_ERR_DEG and t > 0.6 + (0.9 if tank == t34a else 0.0):
		cmd(tank).fire = true
		_targets[tank] = _new_target(target)


func _new_target(last: Vector3) -> Vector3:
	if last != Vector3.ZERO and _rng.randf() < 0.6:
		return last + _right * _rng.randf_range(-12.0, 12.0) + _fwd * _rng.randf_range(-20.0, 20.0)
	return ground_v(_home + _fwd * _rng.randf_range(350.0, 650.0) + _right * _rng.randf_range(-120.0, 120.0)) \
			+ Vector3.UP * 1.2


## Fires AP at the KV-2's turret front (the box: the rounds ping off it) when it's clear.
func _ping_at_kv(tank: Tank) -> void:
	var p: Vector3 = _turret_of(kv) + Vector3.UP * 0.2 + _right * (0.5 if tank == t34a else -0.5)
	aim_ballistic(tank, p)
	if not tank.is_loaded() or t < PING_FROM_S + (1.1 if tank == t34a else 0.0):
		return
	var muzzle: Transform3D = tank.get_muzzle_transform()
	if not clear_line(muzzle.origin - muzzle.basis.z * 2.0, p):
		return   # a wreck in the way
	var err: float = rad_to_deg((-muzzle.basis.z).angle_to(cmd(tank).aim_point - muzzle.origin))
	if err < FIRE_ERR_DEG:
		cmd(tank).fire = true


func _on_kv_struck(outcome: int, _dir: Vector3) -> void:
	if _phase not in [Phase.KV_COMING, Phase.KV_FIRES, Phase.KV_SECOND]:
		return
	if outcome == HitResult.Outcome.NO_PENETRATION or outcome == HitResult.Outcome.RICOCHET:
		SoundFx.play_at(self, _ping, _turret_of(kv), &"Master")
		_pings += 1
		cue("ping %d" % _pings)


func _on_t34a_out() -> void:
	_kill_t = t
	cue("the first T-34's turret flies")
	effect(&"explosion", _turret_of(t34a), 2.2)


## Gives a tossed turret a push away from the KV-2: high and far.
func _fling(_v: Vector3, _spin: Vector3, tank: Tank) -> void:
	var away: Vector3 = _flat(tank.global_position - kv.global_position).normalized()
	var side: Vector3 = away.cross(Vector3.UP)
	var wrecks: Array[Node] = get_tree().get_nodes_in_group(&"wrecks")
	for j: int in range(wrecks.size() - 1, -1, -1):
		var body := wrecks[j] as RigidBody3D
		if body != null and not (body is Wreck):
			body.linear_velocity = Vector3.UP * FLING_UP_MPS + away * FLING_AWAY_MPS + side * 2.5
			body.angular_velocity = side * 4.0 + Vector3.UP * 2.0
			return


## Wrecks and turrets in the KV-2's way give like cardboard: woken, thawed and shoved
## off to the side they lie on.
func _plough() -> void:
	if kv == null or kv.is_knocked_out():
		return
	var kv_fwd: Vector3 = -kv.global_basis.z
	for n: Node in get_tree().get_nodes_in_group(&"wrecks"):
		var body := n as RigidBody3D
		if body == null:
			continue
		var rel: Vector3 = _flat(body.global_position - kv.global_position)
		var ahead: float = rel.dot(kv_fwd)
		if rel.length() > 9.0 or ahead < 0.0:
			continue
		body.freeze = false
		body.sleeping = false
		if body.mass > WRECK_MASS_KG:
			body.mass = 600.0   # a turret
		if n == _lane_wreck and _plow_t < 0.0:
			_plow_t = t
		if rel.length() < 6.5 and not _shoved.has(body):
			_shoved[body] = true
			var out: Vector3 = kv_fwd.cross(Vector3.UP) * signf(rel.dot(kv_fwd.cross(Vector3.UP)) + 0.01)
			body.apply_central_impulse((out * 4.5 + kv_fwd * 2.5 + Vector3.UP * 2.0) * body.mass)
			body.apply_torque_impulse(Vector3.UP * body.mass * 6.0 * signf(rel.dot(out)))
			if n == _lane_wreck:
				cue("the KV-2 shoves a wreck aside")


func _turret_of(tank: Tank) -> Vector3:
	return tank.to_global(tank.get_turret_local_position())


## The KV-2's track facing the second T-34, near its front.
func _track_point() -> Vector3:
	var hs: Vector3 = kv.data.hull_size
	var s: float = signf(kv.to_local(player.global_position).x)
	return kv.to_global(Vector3(s * (hs.x * 0.5 + 0.15), -hs.y * 0.3, -hs.z * 0.3))


func _track_id() -> StringName:
	return &"track_right" if kv.to_local(player.global_position).x > 0.0 else &"track_left"


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# --- Cameras -----------------------------------------------------------------------

func frame(delta: float) -> void:
	if kv == null:
		return
	var pair: Vector3 = (player.get_global_transform_interpolated().origin
			+ t34a.get_global_transform_interpolated().origin) * 0.5
	var yaw0: float = yaw_of(_fwd)
	var kv_p: Vector3 = kv.get_global_transform_interpolated().origin
	if t < 7.0:
		# Straight down, sinking and turning a little.
		var u: float = span(0.0, 7.0)
		var eye: Vector3 = pair + Vector3.UP * lerpf(30.0, 23.0, u) - _fwd * 1.5
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-88.0),
				yaw0 + deg_to_rad(lerpf(28.0, 0.0, ease_in_out(u))), 0.0)), eye)
		cam.fov = 50.0
		_overhead_end = cam.global_transform
		return
	if t < 12.5:
		# The crane: down behind the pair, tilting up to the field.
		var s: float = ease_in_out(span(7.0, 12.0))
		var eye2: Vector3 = _overhead_end.origin.lerp(pair - _fwd * 16.0 + Vector3.UP * 5.0, s)
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(lerpf(-88.0, -6.0, s)),
				yaw0, 0.0)), eye2)
		cam.fov = 50.0
		return
	match _phase:
		Phase.PAUSE, Phase.KV_COMING:
			if _plow_t >= 0.0 and t < _plow_t + 4.0 and _lane_wreck != null:
				_plough_cam()
			else:
				# Long lens from behind the pair, on the KV-2.
				_look = _look.lerp(kv_p + Vector3.UP * 1.5, 1.0 - exp(-3.0 * delta))
				# Out to the side of the pair, clear of their gun smoke.
				var close: bool = _plow_t >= 0.0
				var eye3: Vector3 = pair + _right * 14.0 - _fwd * 5.0 + Vector3.UP * 2.6
				var dist: float = eye3.distance_to(_look)
				look_cam(eye3, _look, clampf(rad_to_deg(2.0 * atan(14.0 / dist)), 8.0, 30.0) * (1.6 if close else 1.0))
		Phase.KV_FIRES:
			if _kill_t < 0.0:
				# Over the KV-2's shoulder, on the first T-34.
				var back: Vector3 = _flat(kv_p - t34a.global_position).normalized()
				var eye4: Vector3 = kv_p + back * 9.0 + Vector3.UP * 4.2 + back.cross(Vector3.UP) * 3.0
				look_cam(eye4, _turret_of(t34a), 11.0)
			else:
				_toss_cam(t34a)
		Phase.KV_SECOND:
			var back2: Vector3 = _flat(kv_p - player.global_position).normalized()
			look_cam(kv_p + back2 * 9.0 + Vector3.UP * 4.2 - back2.cross(Vector3.UP) * 3.0, _turret_of(player), 11.0)
		Phase.HE_SHOT:
			if _he_landed_t < 0.0 or t < _he_landed_t + 1.0:
				if once("gunner on", 0.0):
					use_gunner(1)
			else:
				if once("gunner off", 0.0):
					use_cam()
				_low_track_cam()
		Phase.FLANK:
			if once("gunner off 2", 0.0):
				use_cam()
			# Low behind the T-34 as it swings round; the box turret tries to follow.
			var p: Vector3 = player.get_global_transform_interpolated().origin
			var back: Vector3 = player.global_basis.z
			back.y = 0.0
			_chase_eye = p + back.normalized() * 11.0 + Vector3.UP * 3.0 if _chase_eye == Vector3.ZERO \
					else _chase_eye.lerp(p + back.normalized() * 11.0 + Vector3.UP * 3.0, 1.0 - exp(-2.5 * delta))
			look_cam(_chase_eye, p.lerp(kv_p, 0.3) + Vector3.UP * 1.0, 55.0)
		Phase.REAR_SHOT:
			var p2: Vector3 = player.get_global_transform_interpolated().origin
			var to_kv: Vector3 = _flat(kv_p - p2).normalized()
			look_cam(p2 - to_kv * 8.0 + Vector3.UP * 2.8 + to_kv.cross(Vector3.UP) * 1.8, kv_p + Vector3.UP * 1.5, 38.0)
		Phase.END:
			if options.get("end", "flank") == "kv":
				_toss_cam(player)
			else:
				_toss_cam(kv)


## Low beside the lane wreck as the KV-2 comes through it.
func _plough_cam() -> void:
	var w: Vector3 = _lane_wreck.global_position
	var eye: Vector3 = ground_v(w + _right * 15.0 - _fwd * 9.0) + Vector3.UP * 0.8
	var kv_p: Vector3 = kv.get_global_transform_interpolated().origin
	look_cam(eye, w.lerp(kv_p, 0.4) + Vector3.UP * 1.0, 44.0)


## Low at the KV-2's side as the track goes.
func _low_track_cam() -> void:
	var kv_p: Vector3 = kv.get_global_transform_interpolated().origin
	var side: Vector3 = _flat(player.global_position - kv_p).normalized()
	var eye: Vector3 = ground_v(kv_p + side * 13.0 + _fwd * 7.0) + Vector3.UP * 0.9
	look_cam(eye, kv_p + Vector3.UP * 0.8, 46.0)


## Wide from the side of a tank whose turret is flying, following the turret up.
var _toss_eye: Vector3 = Vector3.ZERO
var _toss_of: Tank
func _toss_cam(tank: Tank) -> void:
	var c: Vector3 = tank.global_position + Vector3.UP * 1.0
	if _toss_of != tank:
		_toss_of = tank
		var away: Vector3 = _flat(c - kv.global_position).normalized()
		_toss_eye = ground_v(c + away.cross(Vector3.UP) * 34.0 + away * 10.0) + Vector3.UP * 2.0
		if tank == kv:
			_toss_eye = ground_v(c + _right * 32.0 - _fwd * 20.0) + Vector3.UP * 2.0
	var look: Vector3 = c
	var wrecks: Array[Node] = get_tree().get_nodes_in_group(&"wrecks")
	for j: int in range(wrecks.size() - 1, -1, -1):
		var body := wrecks[j] as RigidBody3D
		if body != null and not (body is Wreck):
			look = c.lerp(body.global_position, 0.6)
			break
	look_cam(_toss_eye, look, 58.0)
