extends "res://tools/trailer/trailer_shot.gd"
## "Lugn nu, Rally-Kalle!": a T-34 comes down a street in Garnisonen (Vidingsjö XL) far
## too fast, takes a traffic light (or a sign) on the corner with it and stops in the
## house behind; the crew has a word.
##  0 s     low behind the tank, racing down the street
##  then    beside the corner: the pole goes over, the tank hits the wall
##  then    the line (crew_crash_1)
## The shot finds its own corner: a traffic light (else a road sign) near Garnisonen with a
## straight, open run of road up to it and a house wall straight on behind it. Cheats:
## the tank starts at speed. Options: spot=<n>, weather=<preset>.

## Garnisonen, Brigadgatan (58.396452, 15.615612) in map metres.
const NEAR: Vector2 = Vector2(1155.0, 1546.0)
const SEARCH_M: float = 1800.0
const RUN_M: float = 60.0
const START_MPS: float = 12.0
const LINE_AFTER_S: float = 0.7
const END_AFTER_S: float = 4.0

var _pole: Vector3
var _u: Vector3
var _perp: Vector3
var _crash_t: float = -1.0
var _top_speed: float = 0.0
var _chase_eye: Vector3 = Vector3.ZERO


func _init() -> void:
	map = "vidingsjo_xl"
	weather = "clear"


func setup() -> void:
	if not _find_corner():
		push_warning("no corner found")
		done = true
		return
	var start: Vector3 = _pole - _u * RUN_M
	place(player, Vector2(start.x, start.z), rad_to_deg(atan2(_u.x, -_u.z)))
	protect_commander(player)
	use_cam()


func started() -> void:
	player.linear_velocity = _u * START_MPS


func _props() -> Array:   # [kind name, position]
	var out: Array = []
	var pb: Node = null
	for n: Node in get_tree().current_scene.find_children("*", "", true, false):
		if n.get_script() != null and (n.get_script() as Script).get_global_name() == &"PropBreak":
			pb = n
			break
	if pb == null:
		push_warning("no PropBreak")
		return out
	var names: PackedStringArray = pb.get("_kind_names")
	var kind_of: PackedInt32Array = pb.get("_kind_of")
	var xf: Array = pb.get("_xform")
	for i: int in kind_of.size():
		out.append([names[kind_of[i]], (xf[i] as Transform3D).origin])
	return out


func _find_corner() -> bool:
	var skip: int = int(options.get("spot", "0"))
	var props: Array = _props()
	var cands: Array = []
	for p: Array in props:
		var pos: Vector3 = p[1]
		var d: float = Vector2(pos.x, pos.z).distance_to(NEAR)
		if d > SEARCH_M:
			continue
		var kind: String = p[0]
		var rank: float = d + (0.0 if kind.begins_with("Trafikljus") else (600.0 if kind.begins_with("Skylt") else 5000.0))
		cands.append([rank, kind, pos])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	print("rally: %d props, %d candidates" % [props.size(), cands.size()])
	for c: Array in cands.slice(0, 400):
		var pole: Vector3 = c[2]
		for a: int in 32:
			var u := Vector3.FORWARD.rotated(Vector3.UP, a * TAU / 32.0)
			# A house wall straight on behind the pole, 5-18 m, wide and tall enough.
			var eye: Vector3 = ground_v(pole) + Vector3.UP * 1.5
			var hit: Dictionary = _house_hit(eye, u)
			if hit.is_empty():
				continue
			var wall_d: float = (hit["position"] as Vector3).distance_to(eye)
			if wall_d < 5.0 or wall_d > 18.0 or absf((hit["normal"] as Vector3).dot(u)) < 0.7:
				continue   # too near, too far, or glancing: the tank would slide along it
			var side0 := u.cross(Vector3.UP).normalized()
			var wide: bool = true
			for off: Vector3 in [side0 * 1.6, -side0 * 1.6, Vector3.UP * 1.8]:
				var h2: Dictionary = _house_hit(eye + off, u)
				if h2.is_empty() or absf((h2["position"] as Vector3).distance_to(eye + off) - wall_d) > 2.0:
					wide = false
			if not wide:
				continue
			# The run up to it: road most of the way, nothing in the way, fairly level.
			var road: int = 0
			var ok: bool = true
			for k: int in range(1, 7):
				var p2: Vector3 = pole - u * (RUN_M * k / 6.0)
				var g: Vector3 = ground(Vector2(p2.x, p2.z))
				if absf(g.y - eye.y + 1.5) > 4.0:
					ok = false
					break
				if RoadSurface.on_road(get_tree(), g).y > g.y + 0.01:
					road += 1
			if not ok or road < 4:
				continue
			if not clear_line(ground_v(pole - u * RUN_M) + Vector3.UP * 1.4, eye - u * 1.5, 1.7):
				continue
			var side := u.cross(Vector3.UP).normalized()
			var cam_ok: bool = false
			for sd: float in [1.0, -1.0]:
				var ce: Vector3 = ground_v(pole - u * 9.0 + side * sd * 15.0) + Vector3.UP * 1.8
				if clear_line(ce, eye, 0.5, false) and clear_line(ce, eye - u * 25.0, 0.5, false):
					_perp = side * sd
					cam_ok = true
					break
			if not cam_ok:
				continue
			if skip > 0:
				skip -= 1
				continue
			_pole = ground_v(pole)
			_u = u
			print("rally: %s at %s, heading %d, wall at %.1f m" % [c[1], pole, a * 360 / 32,
					(hit["position"] as Vector3).distance_to(eye)])
			return true
	return false


## The first thing a ray along `u` from `eye` hits within 25 m, if it is a house.
func _house_hit(eye: Vector3, u: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(eye + u * 1.0, eye + u * 25.0, 1)
	var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit["collider"] is Node) or not str((hit["collider"] as Node).get_path()).contains("Byggnader"):
		return {}
	return hit


func physics(_delta: float) -> void:
	if _u == Vector3.ZERO:
		return
	var speed: float = player.linear_velocity.length()
	_top_speed = maxf(_top_speed, speed)
	if _crash_t < 0.0:
		drive_to(player, _pole + _u * 30.0, 1.0)
		aim(player, player.global_position + _u * 200.0 + Vector3.UP * 1.5)
		if _top_speed > 8.0 and speed < _top_speed * 0.35:
			_crash_t = t
			stop(player)
			shake(0.9)
			cue("crash (%.0f km/h)" % (_top_speed * 3.6))
	else:
		stop(player)
		if once("line", _crash_t + LINE_AFTER_S):
			say("res://assets/audio/radio/crew_crash_1.ogg", 3.0)
			cue("Lugn nu, Rally-Kalle!")
		if t > _crash_t + END_AFTER_S:
			done = true
	if t > 25.0:
		done = true


func frame(delta: float) -> void:
	if _u == Vector3.ZERO:
		return
	var p: Vector3 = player.get_global_transform_interpolated().origin
	var to_pole: float = (_pole - p).dot(_u)
	if to_pole > 22.0 and _crash_t < 0.0:
		# Low behind, a little to the side, racing along.
		var want: Vector3 = p - _u * 11.0 + _perp * 2.5 + Vector3.UP * 2.2
		_chase_eye = want if _chase_eye == Vector3.ZERO else _chase_eye.lerp(want, 1.0 - exp(-6.0 * delta))
		look_cam(_chase_eye, p + _u * 10.0 + Vector3.UP * 1.0, 62.0)
	else:
		if once("corner_cam", 0.0):
			cue("corner camera")
		# Beside the corner: the pole goes, the wall stops it.
		var eye: Vector3 = ground_v(_pole - _u * 9.0 + _perp * 15.0) + Vector3.UP * 1.8
		look_cam(eye, _pole.lerp(p, 0.3) + Vector3.UP * 1.3, 48.0)
