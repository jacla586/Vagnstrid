extends "res://tools/trailer/trailer_shot.gd"
## Infantry ambush, one take, in Vidingsjö. The shot finds a ThunderRoad road with tall
## grass or crops beside it and a clear view onto the road.
##  0 s      low in the grass among four lying soldiers; a T-34 comes along the road
##  AT call  the AT gunner rises: over his shoulder ("Skott kommer! Klart bakåt!"),
##           back blast, the round strikes the track; the tank stops
##  +1.4 s   commander's view (hatch open): "Infanteri klockan N!", the rifles open up,
##           the roof MG answers over their heads (it misses); they throw smoke
##  +5.2     hatch shut, gunner's sight: HE loaded, the gun searches the smoke, one round; the man
##           a man (a cheat body) tumbles out of the smoke towards us, Wilhelm scream
## The squad fights by its own rules (spotting, AT aim time, rifles); only its AT round
## is made accurate, its rifles hold until the AT shot and only the thrown man screams.
## The thrown man is a copy of one of them sent up from the squad's point, wherever the
## round lands.
## The gunner's view is a cheat: a free camera at the sight with a wide view (no reticle).
## Options: at=<m> (AT range, default 85), cam=wide (after the hit: a free camera behind
## the tank instead of the crew views), spot=<n> (the n-th spot found, default 0).

const ColumnShot := preload("res://tools/trailer/shots/column.gd")
const ROUTES: Array[String] = ["vidingsjo_thunder_orange", "vidingsjo_thunder_red"]
const SIDE_DISTANCES_M: Array[float] = [45.0, 55.0, 38.0, 65.0]
const MIN_GRASS_M: float = 0.5
const START_BEFORE_M: float = 125.0
const DRIVE_ON_M: float = 140.0
const LOOK_AHEAD_M: float = 14.0
const THROTTLE: float = 0.5
const AT_CALL_PATH: String = "res://assets/audio/radio/at_fire.ogg"
const INFANTRY_CALL_PATH: String = "res://assets/audio/radio/infantry_%d.ogg"
const END_AFTER_HE_S: float = 5.0
const AT_CALL_DELAY_S: float = 1.2
## The gun sweeps the smoke (± SWEEP_M across) until SWEEP_END_S after the hit.
const SWEEP_M: float = 9.0
const SWEEP_END_S: float = 10.0
const THROW_UP_MPS: float = 9.0
const THROW_TOWARDS_MPS: float = 10.0
const DECOY_FROM_SQUAD_M: float = 11.0
const DECOY_ANIM: String = "death_back"
## The cheat gunner's view: from the sight, wider than any real sight step.
const GUNNER_WIDE_FOV: float = 32.0

var owner_tank: Tank
var squad: Squad
var _curve: Curve3D
var _road_s: float = 0.0
var _centre: Vector3          # the squad's point
var _facing: Vector3          # from the squad to the road
var _placed: bool = false
var _gunner: int = -1
var _hit_t: float = -1.0
var _at_due_t: float = -1.0
var _he_t: float = -1.0
var _he_fired: bool = false
var _look: Vector3
var _decoy: RigidBody3D
var _decoy_t: float = 0.0


func _init() -> void:
	map = "vidingsjo"


func setup() -> void:
	if not _find_spot():
		push_warning("no road with tall grass beside it")
		done = true
		return
	var start_s: float = maxf(_road_s - START_BEFORE_M, 0.0)
	var p: Vector3 = _curve.sample_baked(start_s)
	place(player, Vector2(p.x, p.z), _heading_at(start_s))
	protect_commander(player)
	cmd(player).hatch_open = true
	cmd(player).ammo_select = ammo_index(player, "AP")
	# The squad's own tank waits out of sight further back from the road.
	var back: Vector3 = _centre - _facing * 110.0
	owner_tank = spawn("t34", 1, Vector2(back.x, back.z), rad_to_deg(atan2(_facing.x, -_facing.z)), "SquadTank")
	player.struck.connect(_on_struck)
	player.fired.connect(func(shell: Shell) -> void:
		if _he_fired and not shell.finished.is_connected(_on_he_burst):
			shell.finished.connect(_on_he_burst.bind(shell)))
	_look = player.global_position
	use_cam()


## The road point, the squad's point and its facing: grass at least MIN_GRASS_M high
## round the squad, nothing (trees, bushes, houses) between it and the road it watches.
func _find_spot() -> bool:
	var gc: GroundCover = GroundCover.of(self)
	if gc == null:
		return false
	var rect := Rect2(0.0, 0.0, 3380.0, 3050.0)
	var md: MapImageData = load("res://data/maps/%s_map.tres" % map) as MapImageData
	if md != null:
		rect = md.world_rect
	rect = rect.grow(-300.0)
	var skip: int = int(options.get("spot", "0"))
	for route: String in ROUTES:
		var curve: Curve3D = ColumnShot._route_curve("res://scenes/scenarios/%s.tscn" % route)
		if curve == null:
			continue
		_curve = curve
		var length: float = curve.get_baked_length()
		var s: float = START_BEFORE_M + 20.0
		while s < length - DRIVE_ON_M:
			s += 10.0
			var c: Vector3 = ground_v(curve.sample_baked(s))
			if not rect.has_point(Vector2(c.x, c.z)):
				continue
			var along: Vector3 = _tangent(s)
			for sign: float in [1.0, -1.0]:
				var n: Vector3 = along.cross(Vector3.UP).normalized() * sign
				for d: float in SIDE_DISTANCES_M:
					var centre: Vector3 = ground_v(c + n * d)
					if not _grassy(gc, centre, along, n):
						continue
					var eye: Vector3 = centre + Vector3.UP * 1.0
					var ok: bool = true
					for k: float in [-80.0, -50.0, -20.0, 0.0]:
						var road: Vector3 = ground_v(curve.sample_baked(s + k)) + Vector3.UP * 1.8
						if not clear_line(eye, road, 0.0, false):
							ok = false
							break
					# The tank's guns (where it stops) must see the men, and a man thrown
					# 5 m up: no crown or trunk in the way.
					for k: float in [-55.0, -40.0, -25.0, -10.0]:
						var gun: Vector3 = ground_v(curve.sample_baked(s + k)) + Vector3.UP * 2.3
						for up: float in [1.0, 3.0, 5.0]:
							if ok and not clear_line(gun, centre + Vector3.UP * up, 0.0, false):
								ok = false
					# The low camera behind the squad must see the road too.
					var cam_eye: Vector3 = ground_v(centre + n * 4.0) + Vector3.UP * 0.6
					if ok and not clear_line(cam_eye, ground_v(curve.sample_baked(s - 60.0)) + Vector3.UP * 1.8, 0.0, false):
						ok = false
					if not ok:
						continue
					if skip > 0:
						skip -= 1
						continue
					_road_s = s
					_centre = centre
					_facing = -n
					print("ambush: %s s=%.0f squad at %s, %.0f m off the road, grass %.2f m" % [
							route, s, centre, d, gc.height_at(centre)])
					return true
	return false


func _grassy(gc: GroundCover, centre: Vector3, along: Vector3, n: Vector3) -> bool:
	for off: Vector3 in [Vector3.ZERO, along * 6.0, -along * 6.0, n * 4.0, -n * 3.0, n * 6.0 + along * 4.0]:
		if gc.height_at(centre + off) < MIN_GRASS_M:
			return false
	if not open_ground(Vector2(centre.x, centre.z), 1.0):
		return false
	return true


## The squad gets off its tank once, then lies in a fan facing the road.
func _place_squad() -> void:
	squad = owner_tank.squad
	if squad == null or not squad.is_inside_tree():
		return
	_placed = true
	var d: SquadData = squad.data.duplicate()
	d.at_dispersion_mrad = 3.0
	d.at_moving_factor = 1.0
	d.at_range_m = float(options.get("at", "85"))
	d.ambush_rifle_range_m = 0.0   # silent until the AT round goes
	d.scream_chance = 1.0
	squad.data = d
	squad.set("_wilhelm", -1)   # nobody screams until the thrown man
	squad.set("_at_left", 1)
	squad.call("_dismount")
	squad.global_position = _centre - _facing * 4.0
	squad.set("_heading", _facing)
	var side: Vector3 = _facing.cross(Vector3.UP).normalized()
	var spots: Array[Vector3] = squad.get("_spot")
	var soldiers: Array[Node3D] = squad.get("_soldiers")
	var last: Array[Vector3] = squad.get("_last_pos")
	var prone: Array[float] = squad.get("_prone")
	var kneel: Array[float] = squad.get("_kneel")
	for i: int in soldiers.size():
		var off: Vector3 = _facing * (4.0 + (1.2 if i % 2 == 0 else 0.0)) \
				+ side * (float(i) - float(soldiers.size() - 1) * 0.5) * 3.2
		spots[i] = off
		var p: Vector3 = ground_v(squad.global_position + off)
		soldiers[i].global_position = p
		last[i] = p
		prone[i] = 1.0
		kneel[i] = 1.0
		squad.call("_size_hitbox", i)
	squad.set("_spots_chosen", true)
	squad.set("_hold_time", 10.0)
	squad.at_aiming.connect(_on_at_aiming)
	squad.fired_round.connect(func(kind: int, from: Vector3, v: Vector3) -> void:
		if kind == Squad.SHOT_AT and _at_due_t < 0.0:
			_at_due_t = t + from.distance_to(player.global_position) / maxf(v.length(), 1.0) + 0.15
			cue("AT round fired"))


func physics(_delta: float) -> void:
	if done:
		return
	if not _placed:
		_place_squad()
	stop(owner_tank)
	# The T-34 rolls along the road, gun ahead, until it is hit.
	if _hit_t < 0.0 and _at_due_t >= 0.0 and t > _at_due_t:
		# The round missed (it has no lead, the tank braked late): the hit happens anyway.
		push_warning("ambush: the AT round missed: striking the track by hand")
		var to_sq: Vector3 = player.to_local(_squad_point())
		var side_x: float = signf(to_sq.x)
		var hs: Vector3 = player.data.hull_size
		var at_track: Vector3 = player.to_global(Vector3(side_x * (hs.x * 0.5 + 0.1), -hs.y * 0.3, -hs.z * 0.2))
		effect(&"explosion", at_track, 0.8)
		effect(&"impact_armour", at_track, 0.8)
		var at_shell: ShellData = (squad.get("data") as SquadData).at_round
		SoundFx.play_at(self, at_shell.sound_explosion, at_track)
		SoundFx.play_at(self, at_shell.sound_hit_armour, at_track)
		var dmg: TankDamage = player.get("_damage")
		dmg.apply_mine(&"track_right" if side_x > 0.0 else &"track_left")
		_on_struck(HitResult.Outcome.HIT, Vector3.ZERO)
	if _hit_t < 0.0:
		var s: float = _curve.get_closest_offset(player.global_position)
		# Once the AT gunner is up the driver brakes: a sure hit (the round has no lead).
		var throttle: float = 0.0 if _gunner >= 0 else THROTTLE
		drive_to(player, ground_v(_curve.sample_baked(s + LOOK_AHEAD_M)), throttle)
		aim(player, player.global_position - player.global_basis.z * 300.0 + Vector3.UP * 1.5)
		if s > _road_s + DRIVE_ON_M - 20.0:
			push_warning("ambush: the tank got past without a shot")
			done = true
		return
	stop(player)
	var c: TankCommand = cmd(player)
	var since: float = t - _hit_t
	var target: Vector3 = _squad_point()
	var side: Vector3 = _facing.cross(Vector3.UP).normalized()
	# Roof MG from the open hatch, high over their heads; then hatch shut, HE.
	c.hatch_open = since < 5.0
	c.mg_use_roof = true
	c.mg_aim_point = target + Vector3.UP * 3.2 + side * 2.5 - _facing * 6.0
	if since < 5.0:
		aim(player, target + Vector3.UP * 0.5)
	elif since < SWEEP_END_S:
		# The gunner searches the smoke: the gun sweeps across it and back, then settles.
		var u: float = (since - 5.0) / (SWEEP_END_S - 5.0)
		var swing: float = sin(u * TAU * 1.5) * (1.0 - u * 0.6)
		aim_ballistic(player, target + side * swing * SWEEP_M)
	else:
		aim_ballistic(player, target + Vector3.UP * 1.2)   # clear of the bank in front
	c.fire_mg = since > 2.4 and since < 4.3
	if once("roof_mg", _hit_t + 2.4):
		cue("roof MG (misses)")
	if once("smoke", _hit_t + 3.7):
		for off: Vector3 in [_facing * 7.0, _facing * 7.0 + side * 6.0, _facing * 5.0 - side * 6.0]:
			squad.throw_smoke(target + off)
		cue("smoke")
	if once("hatch", _hit_t + 5.0):
		cue("hatch closes")
	if once("load_he", _hit_t + 5.4):
		c.ammo_select = ammo_index(player, "HE")
		cue("loading HE")
	var muzzle: Transform3D = player.get_muzzle_transform()
	var err: float = rad_to_deg((-muzzle.basis.z).angle_to(c.aim_point - muzzle.origin))
	c.fire = false
	if options.has("snap") and since > 6.0 and once("dbg%d" % floori(t * 2.0), 0.0):
		var ls: ShellData = player.get_loaded_shell()
		print("t=%.1f err=%.2f loaded=%s %s" % [t, err, ls.short_name if ls != null else "-",
				player.is_loaded()])
	if not _he_fired and since > SWEEP_END_S + 0.9 and err < 2.0 and player.get_loaded_shell() != null \
			and player.get_loaded_shell().short_name == "HE":
		_he_fired = true
		_he_t = t
		c.fire = true
		cue("HE into the smoke")
	if _he_t >= 0.0 and t > _he_t + END_AFTER_HE_S:
		done = true
	if since > 22.0:
		done = true


## The HE round burst. A cheat, like the turret toss: wherever it landed, a man (a fresh
## soldier model in the squad's camouflage on a RigidBody) goes up out of the smoke,
## tumbling, with the Wilhelm scream, and comes down where physics puts him.
func _on_he_burst(_struck: Array[Tank], _shell: Shell) -> void:
	cue("HE bursts")
	var body: Node3D = squad.call("_make_body")
	squad.call("_apply_look")   # the new body's uniform gets the camouflage too
	var players: Array[Node] = body.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var ap := players[0] as AnimationPlayer
		ap.add_animation_library(Squad.ANIM_LIBRARY, squad.data.model_animations)
		ap.play(StringName("%s/%s" % [Squad.ANIM_LIBRARY, DECOY_ANIM]))
		ap.speed_scale = 0.7
	var rb := RigidBody3D.new()
	rb.name = "ThrownSoldier"
	rb.mass = 80.0
	rb.collision_layer = 0
	rb.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3.UP * 0.9
	rb.add_child(shape)
	rb.add_child(body)
	get_parent().add_child(rb)
	var away: Vector3 = _squad_point() - player.global_position
	away.y = 0.0
	away = away.normalized()
	# Out of the smoke's near side, flung towards the tank (and the camera).
	var at: Vector3 = ground_v(_squad_point() - away * DECOY_FROM_SQUAD_M) + Vector3.UP * 0.8
	rb.global_transform = Transform3D(Basis(Vector3.UP, atan2(away.x, away.z)), at)
	rb.reset_physics_interpolation()
	var side: Vector3 = away.cross(Vector3.UP).normalized()
	rb.linear_velocity = -away * THROW_TOWARDS_MPS + side * 1.0 + Vector3.UP * THROW_UP_MPS
	rb.angular_velocity = side * 5.0 + Vector3.UP * 1.2
	_decoy = rb
	_decoy_t = t
	effect(&"explosion", at, 1.2)
	SoundFx.play_at(squad, squad.data.scream_sound, at + Vector3.UP * 2.0)
	cue("a man goes up (Wilhelm)")


## Where the squad's living men are, on the ground.
func _squad_point() -> Vector3:
	var sum := Vector3.ZERO
	var count: int = 0
	var soldiers: Array[Node3D] = squad.get("_soldiers")
	for i: int in soldiers.size():
		if squad.is_soldier_alive(i):
			sum += soldiers[i].global_position
			count += 1
	return sum / float(count) if count > 0 else squad.global_position


func frame(delta: float) -> void:
	if options.has("snap") and _decoy != null and t < _decoy_t + 3.5 \
			and once("fly%d" % floori(t * 6.0), 0.0):
		snap("flight")
	if squad == null:
		look_cam(_centre - _facing * 3.0 + Vector3.UP * 0.6, player.global_position, 40.0)
		return
	var tank_c: Vector3 = player.get_global_transform_interpolated().origin + Vector3.UP * 1.0
	if _hit_t >= 0.0 and t > _hit_t + 1.4:
		_after_hit(delta)
		return
	var side: Vector3 = _facing.cross(Vector3.UP).normalized()
	if _gunner >= 0:
		# Over the AT gunner's shoulder.
		var soldiers: Array[Node3D] = squad.get("_soldiers")
		var g: Vector3 = soldiers[_gunner].global_position
		var to: Vector3 = tank_c - g
		to.y = 0.0
		to = to.normalized()
		var right: Vector3 = to.cross(Vector3.UP).normalized()
		var eye: Vector3 = g - to * 2.0 + right * 0.55 + Vector3.UP * 1.75
		_look = _look.lerp(tank_c, 1.0 - exp(-6.0 * delta))
		look_cam(eye, _look, 34.0)
		return
	# Low in the grass behind the line of lying men.
	var eye: Vector3 = ground_v(squad.global_position - _facing * 2.5 + side * 1.5) + Vector3.UP * 1.0
	_look = _look.lerp(tank_c, 1.0 - exp(-3.0 * delta))
	# Tilted down a little so the men in the grass are in the picture's foot.
	look_cam(eye, _look.lerp(squad.global_position + _facing * 4.0, 0.12), 44.0)


func _after_hit(_delta: float) -> void:
	var since: float = t - _hit_t
	if options.get("cam", "") == "wide":
		var fwd: Vector3 = -player.global_basis.z
		var to_sq: Vector3 = (_squad_point() - player.global_position)
		to_sq.y = 0.0
		var eye: Vector3 = player.global_position - to_sq.normalized() * 14.0 + fwd * 4.0 + Vector3.UP * 3.2
		look_cam(eye, _squad_point() + Vector3.UP * 0.5, 46.0)
		return
	if once("commander", 0.0):
		use_commander()
		shake(0.5)
		player.set("_optics_dirt", minf(player.get_optics_dirt(), 0.3))   # keep the view readable
		cue("commander's view")
	if once("gunner", _hit_t + 5.2):
		use_cam()
		cue("gunner's view (wide)")
	if since >= 5.2:
		# Along the gun from the sight, wide enough for the field and the sky above it.
		var gt: Transform3D = views.gunner_camera.global_transform
		# A little above the barrel, looking where the sight looks.
		var aim_at: Vector3 = gt.origin - gt.basis.z * 60.0
		look_cam(gt.origin + Vector3.UP * 0.7, aim_at)
		cam.fov = GUNNER_WIDE_FOV
		return
	if since < 5.2:
		var dir: Vector3 = _squad_point() + Vector3.UP * 0.4 - player.get_commander_eye_position()
		var w: float = ease_in_out((since - 1.4) / 0.9)
		var hull_yaw: float = yaw_of(-player.global_basis.z)
		commander_look(lerp_angle(hull_yaw, yaw_of(dir), w), pitch_of(dir) * w)


func _on_at_aiming(index: int, _point: Vector3) -> void:
	if _gunner >= 0 or index < 0:
		return
	_gunner = index
	_look = player.global_position + Vector3.UP
	cue("AT gunner rises")
	# The call once he is nearly up; it ends just before the round goes.
	get_tree().create_timer(AT_CALL_DELAY_S, false).timeout.connect(func() -> void:
		say(AT_CALL_PATH, 2.0)
		cue("Skott kommer! Klart bakåt!"))


func _on_struck(_outcome: int, _dir: Vector3) -> void:
	if _hit_t >= 0.0:
		return
	_hit_t = t
	cue("AT round strikes the track")
	var to: Vector3 = player.to_local(_squad_point())
	var hour: int = posmod(roundi(atan2(to.x, -to.z) / TAU * 12.0), 12)
	var path: String = INFANTRY_CALL_PATH % (12 if hour == 0 else hour)
	get_tree().create_timer(2.0, false).timeout.connect(func() -> void:
		say(path, 2.0)
		cue("Infanteri klockan %d!" % (12 if hour == 0 else hour)))


func _tangent(s: float) -> Vector3:
	var d: Vector3 = _curve.sample_baked(s + 2.0) - _curve.sample_baked(s - 2.0)
	d.y = 0.0
	return d.normalized()


func _heading_at(s: float) -> float:
	var d: Vector3 = _tangent(s)
	return rad_to_deg(atan2(d.x, -d.z))
