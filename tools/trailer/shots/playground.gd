extends "res://tools/trailer/trailer_shot.gd"
## A KV-2 ploughs straight through a playground (pieces fly), then on through whatever
## stands behind it. The shot finds a playground by itself: the biggest one with a clear,
## open run-up (no houses or trunks on the line). One take, two angles:
##  0 s      low beside the playground, panning with the tank as it comes and goes
##  cam=chase  low behind the tank instead
## Options: map=<map> (default vidingsjo), park=<n> (the n-th best playground, default 0).

const RUN_UP_M: float = 42.0
const RUN_ON_M: float = 45.0
const CLUSTER_M: float = 35.0
const END_AFTER_S: float = 3.0

var kv2: Tank
var _centre: Vector3
var _dir: Vector3
var _end: Vector3
var _arrived_t: float = -1.0
var _cam_at: Vector3
var _points: Array[Vector3] = []
## The line is moved up to this far to the KV-2's right, to the offset that runs over the
## most playground pieces (option shift=<m> forces one).
const MAX_SHIFT_M: float = 9.0
const HIT_REACH_M: float = 2.6


func _init() -> void:
	map = "vidingsjo"


func setup() -> void:
	place(player, Vector2(50.0, 50.0), 0.0)
	var parks: Array = _playgrounds()
	var pick: int = int(options.get("park", "0"))
	var found: bool = false
	print("playgrounds: ", parks.size(), " ", parks.slice(0, 5))
	var why: Dictionary = {}
	for p: Array in parks:
		var centre: Vector3 = p[0]
		if not _away_from_edge(centre):
			continue
		for a: int in 12:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, a * TAU / 12.0)
			var start: Vector3 = centre - dir * RUN_UP_M
			var end: Vector3 = centre + dir * RUN_ON_M
			if not open_ground(Vector2(start.x, start.z)) or not open_ground(Vector2(end.x, end.z), 3.0):
				why["ground"] = int(why.get("ground", 0)) + 1
				continue
			var lift := Vector3.UP * 1.6
			if not clear_line(ground_v(start) + lift, ground_v(centre) + lift, 1.6):
				why["run-up"] = int(why.get("run-up", 0)) + 1
				continue
			if not clear_line(ground_v(centre) + lift, ground_v(end) + lift, 1.6):
				continue
			if pick > 0:
				pick -= 1
				break
			_centre = ground_v(centre)
			_dir = dir
			_end = ground_v(end)
			found = true
			print("playground at ", _centre, " with ", p[1], " pieces, heading ", a * 30)
			break
		if found:
			break
	if not found:
		print(why)
		push_warning("no playground with a clear run-up")
		done = true
		return
	# The start stays where the run-up was checked clear; the line swings from it through
	# the playground's middle moved to the right (more pieces in the way).
	var start: Vector3 = _centre - _dir * RUN_UP_M
	_shift_right()
	_dir = Vector3(_centre.x - start.x, 0.0, _centre.z - start.z).normalized()
	_end = ground_v(_centre + _dir * RUN_ON_M)
	kv2 = spawn("kv2", 1, Vector2(start.x, start.z), rad_to_deg(atan2(_dir.x, -_dir.z)), "KV2")
	var side: Vector3 = _dir.cross(Vector3.UP).normalized()
	# The camera beside the playground, on whichever side has nothing in front of it.
	_cam_at = ground_v(_centre + side * 13.0 + _dir * 6.0) + Vector3.UP * 0.8
	for c: Vector3 in [side * 13.0 + _dir * 6.0, -side * 13.0 + _dir * 6.0, side * 16.0,
			-side * 16.0, side * 11.0 + _dir * 10.0, -side * 11.0 + _dir * 10.0]:
		var eye: Vector3 = ground_v(_centre + c) + Vector3.UP * 0.8
		if clear_line(eye, _centre + Vector3.UP * 1.5, 1.0, false) \
				and clear_line(eye, ground_v(start) + Vector3.UP * 1.5, 1.0, false):
			_cam_at = eye
			break
	use_cam()


func physics(_delta: float) -> void:
	if kv2 == null:
		return
	var left: float = drive_to(kv2, _end, 1.0)
	aim(kv2, kv2.global_position - kv2.global_basis.z * 300.0 + Vector3.UP * 1.0)
	if kv2.global_position.distance_to(_centre) < 6.0 and once("smash", 0.0):
		cue("through the playground")
	if left < 6.0 and _arrived_t < 0.0:
		_arrived_t = t
	if _arrived_t >= 0.0:
		stop(kv2)
		if t > _arrived_t + END_AFTER_S:
			done = true


func frame(_delta: float) -> void:
	if kv2 == null:
		return
	var tank_c: Vector3 = kv2.get_global_transform_interpolated().origin + Vector3.UP * 0.6
	if options.get("cam", "") == "chase":
		# Raised over the KV-2's own exhaust and dust, looking down past its turret.
		var back: Vector3 = -_dir * 13.0 + _dir.cross(Vector3.UP) * 3.0
		var eye: Vector3 = tank_c + back
		eye.y = ground_v(eye).y + 4.6
		look_cam(eye, tank_c + _dir * 12.0, 60.0)
	else:
		look_cam(_cam_at, tank_c, 50.0)


## [centre, piece count] of every playground, biggest first.
func _playgrounds() -> Array:
	var points: Array[Vector3] = []
	for group: Node in get_tree().current_scene.find_children("Lekplatser", "", true, false):
		for c: Node in group.get_children():
			# The pieces sit at the origin; their place is in the mesh.
			var meshes: Array[Node] = c.find_children("*", "MeshInstance3D", true, false)
			if c is MeshInstance3D:
				meshes.append(c)
			for m: Node in meshes.slice(0, 1):
				var mi := m as MeshInstance3D
				if mi.mesh != null:
					points.append(mi.global_transform * mi.mesh.get_aabb().get_center())
	_points = points
	var clusters: Array = []   # [sum, count]
	for p: Vector3 in points:
		var joined: bool = false
		for c: Array in clusters:
			if (c[0] as Vector3 / float(c[1])).distance_to(p) < CLUSTER_M:
				c[0] = (c[0] as Vector3) + p
				c[1] = int(c[1]) + 1
				joined = true
				break
		if not joined:
			clusters.append([p, 1])
	var out: Array = []
	for c: Array in clusters:
		out.append([(c[0] as Vector3) / float(c[1]), c[1]])
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	return out


## Moves the line (centre and end) to the KV-2's right, where it runs over the most pieces.
func _shift_right() -> void:
	var right: Vector3 = _dir.cross(Vector3.UP).normalized()
	var best: float = 0.0
	var best_n: int = _pieces_on(0.0, right)
	if options.has("shift"):
		best = float(options["shift"])
	else:
		for k: int in range(1, int(MAX_SHIFT_M * 2.0) + 1):
			var off: float = k * 0.5
			var n: int = _pieces_on(off, right)
			if n > best_n:
				best_n = n
				best = off
	print("playground: line moved %.1f m right, %d pieces on it (%d at 0)" % [best, _pieces_on(best, right), _pieces_on(0.0, right)])
	_centre = ground_v(_centre + right * best)
	_end = ground_v(_end + right * best)


## Pieces within HIT_REACH_M of the line through the playground (±CLUSTER_M along it).
func _pieces_on(off: float, right: Vector3) -> int:
	var n: int = 0
	var c: Vector3 = _centre + right * off
	for p: Vector3 in _points:
		var rel: Vector3 = p - c
		rel.y = 0.0
		var along: float = rel.dot(_dir)
		if absf(along) < CLUSTER_M and absf(rel.dot(right)) < HIT_REACH_M:
			n += 1
	return n


## Not near the map's edge, where the camera would look out over nothing.
func _away_from_edge(p: Vector3) -> bool:
	var rect := Rect2(0.0, 0.0, 3380.0, 3050.0)
	var data: MapImageData = load("res://data/maps/%s_map.tres" % map) as MapImageData
	if data != null:
		rect = data.world_rect
	return rect.grow(-350.0).has_point(Vector2(p.x, p.z))
