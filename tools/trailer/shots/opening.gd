extends "res://tools/trailer/trailer_shot.gd"
## The opening, one take (cut it as you like):
##  0-9 s   a dive from 1200 m over Vidingsjö that lands in the commander's eyes
##  9-20    hatch open, the commander looks round, binoculars on the far woods
##  20-21   MG fire from ten o'clock rattles on the plate, an HE round lands in front
##  21.5    hatch shut, periscope, looking round
##  26      "Pansar klockan två!"; the turret swings
##  28      gunner's sight: a Pz IV on the gravel road at ~110 m, AP in its side, it burns

## The own T-34 at the forest edge west of Haningeleden, facing east over the fields.
const PLAYER_AT: Vector2 = Vector2(400.0, 610.0)
const PLAYER_HEADING: float = 90.0
## The hidden enemy that fires the MG and the HE round (ten o'clock, ~250 m).
const AMBUSH_AT: Vector2 = Vector2(520.0, 405.0)
## The target comes out of the field at two o'clock, ~75 m, and rolls north-east across
## the line of sight (left side to us).
const TARGET_FROM: Vector2 = Vector2(420.0, 686.0)
const TARGET_TO: Vector2 = Vector2(540.0, 616.0)
const TARGET_START_S: float = 21.0
const FLY_S: float = 9.0
const FLY_HEIGHT_M: float = 1200.0
const END_S: float = 39.0
## Commander's look: [t, yaw left of the hull's front (deg), pitch (deg)].
const LOOK: Array = [
	[9.0, 0.0, -1.0], [11.5, 34.0, -1.5], [13.2, 34.0, -0.5], [15.0, -16.0, -0.3],
	[18.0, -6.0, -0.3], [19.6, 8.0, 0.0], [20.0, 8.0, 0.0], [20.6, 52.0, 1.0],
	[21.1, 46.0, 0.0], [21.5, 34.0, -9.0], [22.0, 30.0, -7.0], [23.0, 2.0, 0.0], [24.4, 45.0, 0.0],
	[25.8, 22.0, 0.0], [26.4, 22.0, 0.0], [27.6, -58.0, -1.0], [40.0, -58.0, -1.0]]

var ambush: Tank
var target: Tank
var _fly_from: Transform3D
var _fly_to: Transform3D
var _shot_fired: bool = false


func setup() -> void:
	place(player, PLAYER_AT, PLAYER_HEADING)
	protect_commander(player)
	cmd(player).hatch_open = true
	aim(player, player.global_position + (-player.global_basis.z) * 500.0 + Vector3.UP * 1.5)
	ambush = spawn("t34", 1, AMBUSH_AT, 209.0, "Ambush")
	cmd(ambush).ammo_select = ammo_index(ambush, "HE")
	target = spawn("pz4", 1, TARGET_FROM, 60.0, "Target")
	make_fragile(target)
	# Dive: from straight above (north up) to the commander's eyes, looking east.
	var eye: Vector3 = player.get_commander_eye_position() + Vector3.UP * 0.0
	_fly_to = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-1.0), yaw_of(-player.global_basis.z), 0.0)), eye)
	_fly_from = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD),
			eye + Vector3(320.0, FLY_HEIGHT_M, 80.0))
	use_cam()
	cam.fov = 50.0


func physics(_delta: float) -> void:
	# The ambusher: MG on the turret round the commander, then HE just in front.
	var c: TankCommand = cmd(ambush)
	if t < 20.9:
		aim(ambush, player.global_position + Vector3.UP * 0.6)
	else:
		aim_ballistic(ambush, at_clock(player, 11.0, 7.5))
	c.ammo_select = -1 if t > 0.1 else ammo_index(ambush, "HE")
	c.fire_mg = t > 20.0 and t < 21.0
	c.fire = once("he", 21.05)
	if once("mg_cue", 20.0):
		cue("MG fire")
	if once("he_cue", 21.05):
		cue("HE fired (lands ~0.4 s later)")
	# Hatch shut after the burst.
	cmd(player).hatch_open = t < 21.75
	if once("hatch", 21.75):
		cue("hatch closes")
	# The target rolls along the road.
	if t > TARGET_START_S and not target.is_knocked_out():
		drive_to(target, ground(TARGET_TO), 0.45)
	else:
		stop(target)
	# The own gun: ahead until the call, then on the target with a little lead.
	if t > 26.2 and not target.is_knocked_out():
		var p: Vector3 = target.global_position + target.linear_velocity * 0.22 + Vector3.UP * 0.2
		aim(player, p)
		var muzzle: Transform3D = player.get_muzzle_transform()
		var err: float = rad_to_deg((-muzzle.basis.z).angle_to(p - muzzle.origin))
		if options.has("snap") and once("dbg%d" % floori(t * 2.0), 0.0):
			print("t=%.1f err=%.2f dist=%.0f" % [t, err, p.distance_to(muzzle.origin)])
		if t > 30.0 and err < 0.9 and not _shot_fired:
			_shot_fired = true
			cmd(player).fire = true
			cue("FIRE")
		else:
			cmd(player).fire = false
	else:
		cmd(player).fire = false
	if once("call", 26.2):
		say("res://assets/audio/radio/armour_2.ogg", 2.0)
		cue("Pansar klockan två!")
	if target.is_knocked_out() and once("ko", 0.0):
		cue("target knocked out")
	if t > END_S:
		done = true


func frame(_delta: float) -> void:
	if t < FLY_S:
		_fly()
		return
	if once("land", FLY_S):
		cue("in the commander's eyes")
		use_commander()
	if once("gunner", 27.9):
		use_gunner(1)
		cue("gunner's sight")
	if t > 27.9:
		return
	binoculars(t > 15.3 and t < 18.1)
	var hull_yaw: float = yaw_of(-player.global_basis.z)
	var look: Vector2 = _look_at_time(t)
	commander_look(hull_yaw + deg_to_rad(look.x), deg_to_rad(look.y))
	if once("shake_mg", 20.35):
		shake(0.25)
	if once("shake_he", 21.45):
		shake(0.75)


## Altitude falls on a log scale (it speeds up as the ground comes near) and eases in at
## the end; the view turns from straight down to the commander's in the last part.
func _fly() -> void:
	var u: float = t / FLY_S
	var e: float = ease_in_out(u)
	var k: float = 0.0015
	var share: float = (pow(k, e) - k) / (1.0 - k)
	var origin: Vector3 = _fly_to.origin + (_fly_from.origin - _fly_to.origin) * share
	var turn: float = ease_in_out((u - 0.45) / 0.55)
	var b: Basis = _fly_from.basis.slerp(_fly_to.basis, turn)
	cam.global_transform = Transform3D(b, origin)
	# The own commander's head and hatch lid would fill the screen at the end.
	cam.set_cull_mask_value(CommanderCamera.OWN_COMMANDER_LAYER, u < 0.8)
	cam.fov = lerpf(50.0, player.data.commander_fov_deg, ease_in_out((u - 0.6) / 0.4))


func _look_at_time(time: float) -> Vector2:
	for i: int in range(LOOK.size() - 1):
		var a: Array = LOOK[i]
		var b: Array = LOOK[i + 1]
		if time <= float(b[0]):
			var w: float = ease_in_out((time - float(a[0])) / (float(b[0]) - float(a[0])))
			return Vector2(lerpf(a[1], b[1], w), lerpf(a[2], b[2], w))
	var last: Array = LOOK[LOOK.size() - 1]
	return Vector2(last[1], last[2])
