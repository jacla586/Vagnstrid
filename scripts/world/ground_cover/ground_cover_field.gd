class_name GroundCoverField
extends Node3D
## Draws the ground vegetation (GroundCover) round the active camera: square cells of
## GroundCoverSetData.cell_m, one MultiMesh per class and cell, placed on the terrain with
## a fixed random pattern per cell (the same grass every time).
##
## How far: by "seen" distance, the true distance divided by the camera's zoom (its FOV
## against reference_fov_deg). All round the camera cells go out to blade_range_m; inside
## a zoomed camera's view (gunner's sight, binoculars) out to blade_range_m × zoom, capped
## at max_reach_m. Zoomed views also thin by 1 / zoom^zoom_thin_exponent. Beyond full_density_m the clumps thin as (full / d)^thin_exponent and
## the survivors widen (ground_cover.gdshader does both per clump, from the clump's rank in
## INSTANCE_CUSTOM.r), so on screen the grass looks as thick far out as near. A cell holds
## only the clumps its nearest point needs (1, 1/4, 1/16... of them: the first ones of the
## same random sequence, so a finer rebuild adds clumps and moves none). Cells are built
## (GroundCoverCellBuild) within build_ms_per_frame, nearest first, a dense one over
## several frames; a camera jump builds the near ones at once. Cells no longer wanted hide and are freed after keep_hidden_s.
## Lives in the player rig; purely cosmetic and local (bots use GroundCover's rule).

## Finest level is 0 (every clump), each level up keeps a quarter.
const MAX_LEVEL: int = 5
## Seen distance within which a camera jump builds everything at once (m).
const JUMP_BUILD_M: float = 45.0
## Rebuild the wanted set when the camera moved this far (m), turned this much (rad) or
## its zoom changed by this share.
const RESCAN_MOVE_M: float = 2.0
const RESCAN_TURN_RAD: float = 0.03
const RESCAN_ZOOM: float = 0.03


class Cell:
	var node: Node3D
	var level: int = MAX_LEVEL + 1   # built level; MAX_LEVEL + 1 = nothing built
	var hidden_since: float = -1.0


var _gc: GroundCover
var _tried: bool = false
var _cells: Dictionary = {}    # Vector2i -> Cell
var _wanted: Dictionary = {}   # Vector2i -> [level, seen distance]
var _queue: Array[Vector2i] = []   # wanted cells to build, nearest first
var _scan_pos := Vector3(INF, INF, INF)
var _scan_dir := Vector3.ZERO
var _scan_zoom: float = 0.0
var _max_density: float = 0.0
var _job: GroundCoverCellBuild   # the cell being built, a slice a frame
var _job_free: bool = false      # built at once (near cells after a camera jump)


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY   # instances are placed in world coordinates
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(_delta: float) -> void:
	if _gc == null:
		if _tried and Engine.get_process_frames() % 60 != 0:
			return
		_tried = true
		_gc = GroundCover.of(self)
		if _gc == null:
			return
		for k: GroundCoverClassData in _gc.rules.classes:
			if k != null:
				_max_density = maxf(_max_density, k.density)
		GroundCoverMesh.material(_gc.rules)
	if _max_density <= 0.0:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var rules: GroundCoverSetData = _gc.rules
	var p: Vector3 = cam.global_position
	var fwd: Vector3 = -cam.global_basis.z
	var zoom: float = clampf(tan(deg_to_rad(rules.reference_fov_deg) * 0.5)
			/ tan(deg_to_rad(cam.fov) * 0.5), 0.5, 100.0)
	if p.distance_to(_scan_pos) > RESCAN_MOVE_M or fwd.angle_to(_scan_dir) > RESCAN_TURN_RAD \
			or absf(zoom / maxf(_scan_zoom, 0.001) - 1.0) > RESCAN_ZOOM:
		_scan(p, fwd, zoom, cam)
	_build_some(p)


## Which cells the camera wants and at what level; hides the rest, frees old hidden ones.
func _scan(p: Vector3, fwd: Vector3, zoom: float, cam: Camera3D) -> void:
	_scan_pos = p
	_scan_dir = fwd
	_scan_zoom = zoom
	var rules: GroundCoverSetData = _gc.rules
	var cell: float = rules.cell_m
	var range_m: float = rules.blade_range_m
	_wanted.clear()
	var p2 := Vector2(p.x, p.z)
	# all round the camera, unzoomed
	_add_area(p2, Rect2(p2 - Vector2(range_m, range_m), Vector2(range_m, range_m) * 2.0),
			1.0, Vector2.ZERO, 0.0)
	# the zoomed view's wedge
	var flat := Vector2(fwd.x, fwd.z)
	if zoom > 1.05 and flat.length() > 0.05:
		flat = flat.normalized()
		var reach: float = minf(range_m * zoom, rules.max_reach_m)
		var aspect: float = cam.get_viewport().get_visible_rect().size.aspect()
		var half: float = atan(tan(deg_to_rad(cam.fov) * 0.5) * maxf(aspect, 1.0))
		var box := Rect2(p2, Vector2.ZERO)
		for a: float in [-half, 0.0, half]:
			box = box.expand(p2 + flat.rotated(a) * reach)
		_add_area(p2, box.grow(cell), zoom, flat, half)
	# what to build: missing or too coarse, nearest (seen) first
	_queue.clear()
	for c: Vector2i in _wanted:
		var cs: Cell = _cells.get(c)
		if cs == null or cs.level > int(_wanted[c][0]):
			_queue.append(c)
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return float(_wanted[a][1]) < float(_wanted[b][1]))
	# show the wanted ones, hide the others, free those hidden long enough
	var now: float = Time.get_ticks_msec() / 1000.0
	for c: Vector2i in _cells.keys():
		var cs: Cell = _cells[c]
		if _wanted.has(c):
			cs.hidden_since = -1.0
			if cs.node != null:
				cs.node.visible = true
		elif cs.hidden_since < 0.0:
			cs.hidden_since = now
			if cs.node != null:
				cs.node.visible = false
		elif now - cs.hidden_since > rules.keep_hidden_s:
			if cs.node != null:
				cs.node.queue_free()
			_cells.erase(c)


## Adds the cells in `box` within the blade range seen with `zoom`; with a direction
## `flat`, only those inside the wedge of half-angle `half` round it.
func _add_area(p2: Vector2, box: Rect2, zoom: float, flat: Vector2, half: float) -> void:
	var rules: GroundCoverSetData = _gc.rules
	var cell: float = rules.cell_m
	var range_m: float = rules.blade_range_m
	var c0 := Vector2i(floori(box.position.x / cell), floori(box.position.y / cell))
	var c1 := Vector2i(floori(box.end.x / cell), floori(box.end.y / cell))
	for cz: int in range(c0.y, c1.y + 1):
		for cx: int in range(c0.x, c1.x + 1):
			var lo := Vector2(cx * cell, cz * cell)
			var near := Vector2(clampf(p2.x, lo.x, lo.x + cell), clampf(p2.y, lo.y, lo.y + cell))
			var d: float = near.distance_to(p2)
			if zoom > 1.0:
				if d > rules.max_reach_m:
					continue
				var to_c: Vector2 = lo + Vector2(cell, cell) * 0.5 - p2
				var dc: float = to_c.length()
				if dc > cell:
					var margin: float = asin(minf(cell * 0.72 / dc, 1.0))
					if absf(flat.angle_to(to_c)) > half + margin:
						continue
			var seen: float = d / zoom
			if seen > range_m:
				continue
			var level: int = _level_for(seen, zoom)
			var c := Vector2i(cx, cz)
			if _wanted.has(c):
				var w: Array = _wanted[c]
				if seen < float(w[1]):
					_wanted[c] = [mini(level, int(w[0])), seen]
			else:
				_wanted[c] = [level, seen]


## The coarsest level whose share of clumps covers what is drawn at seen distance `seen`
## with `zoom` (as ground_cover.gdshader thins them).
func _level_for(seen: float, zoom: float) -> int:
	var rules: GroundCoverSetData = _gc.rules
	var f: float = 1.0 if seen <= rules.full_density_m \
			else pow(rules.full_density_m / seen, rules.thin_exponent)
	f /= pow(maxf(zoom, 1.0), rules.zoom_thin_exponent)
	return clampi(floori(log(1.0 / f) / log(4.0)), 0, MAX_LEVEL)


func _build_some(p: Vector3) -> void:
	if _queue.is_empty() and _job == null:
		return
	var rules: GroundCoverSetData = _gc.rules
	var cell: float = rules.cell_m
	var c_here := Vector2i(floori(p.x / cell), floori(p.z / cell))
	var jumped: bool = not _cells.has(c_here)
	var t0: int = Time.get_ticks_usec()
	var deadline: int = t0 + int(rules.build_ms_per_frame * 1000.0)
	var built: int = 0
	while true:
		if _job == null:
			if _queue.is_empty() or Time.get_ticks_usec() > deadline and not jumped:
				break
			var c: Vector2i = _queue.pop_front()
			var w: Array = _wanted.get(c, [])
			if w.is_empty():
				continue
			var cs: Cell = _cells.get(c)
			if cs != null and cs.level <= int(w[0]):
				continue
			_job = GroundCoverCellBuild.new(_gc, c, int(w[0]), _max_density)
			_job_free = jumped and float(w[1]) <= JUMP_BUILD_M
		if not _job.step(0 if _job_free else deadline):
			break
		_install(_job)
		_job = null
		built += 1
		if Time.get_ticks_usec() > deadline and not jumped:
			break
	if built > 0 and OS.has_environment("GC_DEBUG"):
		print("gcfield built %d in %.1f ms, cells %d, queue %d" % [built,
				(Time.get_ticks_usec() - t0) / 1000.0, _cells.size(), _queue.size()])


## Puts a finished build in place of the cell's old clumps.
func _install(job: GroundCoverCellBuild) -> void:
	var cs: Cell = _cells.get(job.cell)
	if cs == null:
		cs = Cell.new()
		_cells[job.cell] = cs
	if cs.node != null:
		cs.node.queue_free()
	cs.node = job.node()
	add_child(cs.node)
	cs.node.visible = _wanted.has(job.cell)
	cs.level = job.level
	cs.hidden_since = -1.0 if cs.node.visible else Time.get_ticks_msec() / 1000.0


## A MultiMeshInstance3D of class `k` from a MultiMesh buffer `buf` (per clump: 3×4
## transform rows, colour, custom data = [rank, 0, 0, 0]).
static func make_instances(k: GroundCoverClassData, buf: PackedFloat32Array, rules: GroundCoverSetData) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = GroundCoverMesh.mesh_for(k)
	mm.instance_count = buf.size() / 20
	mm.buffer = buf
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = GroundCoverMesh.material(rules)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# widened far clumps reach a little past the cell
	mi.extra_cull_margin = 1.0
	return mi
