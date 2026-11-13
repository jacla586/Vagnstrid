extends "res://tools/trailer/trailer_shot.gd"
## The turret toss, one take, in a Vidingsjö housing area:
##  0-4 s   low camera under a KV-2 creeping forward, its box turret swinging round
##  4       it fires: slow motion, the camera chases the 152 mm round
##  impact  the Sherman's ammo goes up: cut to a low wide shot, the turret flies
##          (toss=<m> high, default 13) and comes down; time speeds back up to normal
## Sound runs at normal speed through the slow motion: lay it in the edit.
## Options: toss=<m>, slow=<time scale> (default 0.12).

const SHERMAN_AT: Vector2 = Vector2(2600.0, 1500.0)
const SHERMAN_HEADING: float = 80.0
## The KV-2 fires from the Sherman's rear quarter: the first spot (by angle off the
## Sherman's tail, then range) on open ground with a clear line to its turret.
const KV2_ANGLES_DEG: Array[float] = [140.0, -140.0, 120.0, -120.0, 160.0, -160.0, 100.0, -100.0]
const KV2_RANGES_M: Array[float] = [70.0, 85.0, 55.0, 100.0]
const FIRE_AT_S: float = 4.2
const HOLD_AFTER_S: float = 7.0

var kv2: Tank
var sherman: Tank
var _round: Shell
var _impact_t: float = -1.0
var _real_since_impact: float = 0.0
var _slow: float = 0.12
var _wide_eye: Vector3
var _shot_done: bool = false
var _lost_round_s: float = 0.0


func setup() -> void:
	_slow = float(options.get("slow", "0.12"))
	# The player rig's own tank stays out of the way (its rig makes the weather etc.).
	place(player, Vector2(2450.0, 1650.0), 0.0)
	sherman = spawn("sherman", 0, SHERMAN_AT, SHERMAN_HEADING, "Sherman")
	var kv2_at: Vector2 = _firing_spot()
	var to_target: Vector3 = sherman.global_position - Vector3(kv2_at.x, 0.0, kv2_at.y)
	kv2 = spawn("kv2", 1, kv2_at, rad_to_deg(atan2(to_target.x, -to_target.z)) - 25.0, "KV2")
	make_fragile(sherman)
	var dmg: TankDamage = sherman.get("_damage")
	dmg.ammo_exploded = true
	var toss: float = float(options.get("toss", "13"))
	sherman.data.turret_toss_min_m = toss
	sherman.data.turret_toss_max_m = toss
	sherman.data.turret_toss_side_mps = 1.5
	kv2.fired.connect(func(s: Shell) -> void:
		_round = s
		cue("KV-2 fires"))
	sherman.knocked_out.connect(_on_impact)
	# Low wide camera on the Sherman's far side for the toss.
	var side: Vector3 = sherman.global_basis.x
	_wide_eye = ground_v(sherman.global_position + side * 15.0 - sherman.global_basis.z * 5.0) + Vector3.UP * 0.6
	use_cam()


func physics(_delta: float) -> void:
	var turret: Vector3 = sherman.to_global(sherman.get_turret_local_position())
	aim(kv2, turret + Vector3.UP * 0.3)
	if t < FIRE_AT_S - 0.8:
		cmd(kv2).throttle = 0.35
	else:
		stop(kv2)
	var muzzle: Transform3D = kv2.get_muzzle_transform()
	var err: float = rad_to_deg((-muzzle.basis.z).angle_to(turret - muzzle.origin))
	cmd(kv2).fire = false
	if t >= FIRE_AT_S and err < 0.6 and not _shot_done:
		_shot_done = true
		cmd(kv2).fire = true
		Engine.time_scale = _slow
	# A miss (it shouldn't): the ammo goes up anyway once the round is gone.
	if _shot_done and _impact_t < 0.0 and (_round == null or not is_instance_valid(_round)):
		_lost_round_s += _delta / maxf(Engine.time_scale, 0.01)
		if _lost_round_s > 0.4:
			push_warning("the round missed: knocking the Sherman out by hand")
			sherman.call("_knock_out")
	if _impact_t >= 0.0 and t > _impact_t + 0.2:
		# Back to full speed over ~2 s of film, so the turret's climb is slow and the fall quick.
		Engine.time_scale = lerpf(0.3, 1.0, ease_in_out(_real_since_impact / 2.2))
	if _impact_t >= 0.0 and t > _impact_t + HOLD_AFTER_S:
		Engine.time_scale = 1.0
		done = true


func frame(delta: float) -> void:
	if _impact_t >= 0.0:
		_real_since_impact += delta / maxf(Engine.time_scale, 0.01)
		_wide()
	elif _round != null and is_instance_valid(_round):
		_chase()
	else:
		_low()


## Under the KV-2's front, looking up at the gun as the turret swings.
func _low() -> void:
	var fwd: Vector3 = -kv2.global_basis.z
	var side: Vector3 = kv2.global_basis.x
	var u: float = span(0.0, FIRE_AT_S)
	var eye: Vector3 = kv2.global_position + fwd * 9.0 + side * lerpf(-6.0, -3.0, u)
	eye.y = ground_v(eye).y + 0.5
	var look: Vector3 = kv2.global_position + Vector3.UP * 2.2 + fwd * 2.0
	look_cam(eye, look, lerpf(55.0, 46.0, u), deg_to_rad(-4.0))


## Behind and a little above the round.
func _chase() -> void:
	var v: Vector3 = _round.get_velocity().normalized()
	var eye: Vector3 = _round.global_position - v * 7.0 + Vector3.UP * 0.9 + v.cross(Vector3.UP) * 1.6
	look_cam(eye, _round.global_position + v * 6.0, 42.0)


## Low and wide on the far side, tilting up after the turret.
func _wide() -> void:
	var tank_c: Vector3 = sherman.global_position + Vector3.UP * 1.0
	var look: Vector3 = tank_c
	var wreck: Node3D = get_parent().get_node_or_null("TurretWreck")
	if wreck != null:
		look = tank_c.lerp(wreck.global_position, 0.65)
	var u: float = clampf(_real_since_impact / 6.0, 0.0, 1.0)
	var eye: Vector3 = _wide_eye + Vector3.UP * u * 0.8
	look_cam(eye, look, 52.0)


func _firing_spot() -> Vector2:
	var turret: Vector3 = sherman.to_global(sherman.get_turret_local_position())
	var fwd: Vector3 = -sherman.global_basis.z
	for a: float in KV2_ANGLES_DEG:
		for r: float in KV2_RANGES_M:
			var d: Vector3 = fwd.rotated(Vector3.UP, deg_to_rad(a)) * r
			var xz := Vector2(sherman.global_position.x + d.x, sherman.global_position.z + d.z)
			if not open_ground(xz):
				continue
			if clear_line(ground(xz) + Vector3.UP * 2.8, turret, 1.5):
				print("KV-2 spot ", xz, " angle ", a, " range ", r)
				return xz
	push_warning("no clear spot for the KV-2")
	return Vector2(sherman.global_position.x + 40.0, sherman.global_position.z + 60.0)


func _on_impact() -> void:
	_impact_t = t
	cue("impact: the turret goes")
	var turret: Vector3 = sherman.to_global(sherman.get_turret_local_position())
	effect(&"explosion", turret, 3.2)
	effect(&"impact_armour", turret, 2.0)
