class_name TacticalMap
extends RefCounted
## Paths (and later positions) for the bots on a map's TacticalGridData: A* over the
## grid (AStarGrid2D), houses/water/steep cells closed, other cells weighted by
## TacticsData (roads cheap, forest and wetland dear, cover cheaper). Paths are then
## straightened where a straight line crosses no closed or dearer cells. One map per
## grid, built on first use and shared by all bots.

const DEFAULT_TACTICS: TacticsData = preload("res://data/bots/tactics_regular.tres")
## How far to look for an open cell when a start or goal lies on a closed one (cells).
const SNAP_RADIUS_CELLS: int = 8
## Straightening looks at most this many path cells ahead.
const SMOOTH_LOOKAHEAD: int = 48
## Half the width a straightened leg must keep clear, in cells (8 m cells: ~2.4 m).
const LINE_HALF_WIDTH_CELLS: float = 0.3

static var _cache: Dictionary = {}  # TacticalGridData -> TacticalMap

var grid: TacticalGridData
var _astar: AStarGrid2D
var _weights: PackedFloat32Array


## The map for the scene's terrain, or null if its grid hasn't been baked.
static func for_scene(scene_root: Node) -> TacticalMap:
	var data: TacticalGridData = TacticalGridData.find_for_scene(scene_root)
	if data == null:
		return null
	if not _cache.has(data):
		_cache[data] = TacticalMap.new(data, DEFAULT_TACTICS)
	return _cache[data]


func _init(data: TacticalGridData, tactics: TacticsData) -> void:
	grid = data
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, grid.width, grid.height)
	_astar.cell_size = Vector2(grid.cell_size, grid.cell_size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.update()
	_weights.resize(grid.width * grid.height)
	for z: int in grid.height:
		for x: int in grid.width:
			var c := Vector2i(x, z)
			var i: int = grid.index_of(c)
			var f: int = grid.flags[i]
			if f & TacticalGridData.BLOCKED:
				_astar.set_point_solid(c, true)
				_weights[i] = INF
				continue
			var w: float = _cost(f, tactics)
			_weights[i] = w
			_astar.set_point_weight_scale(c, w)


static func _cost(f: int, t: TacticsData) -> float:
	var w: float = t.cost_open
	if f & TacticalGridData.ROAD:
		w = t.cost_road
	elif f & TacticalGridData.WET:
		w = t.cost_wet
	elif f & TacticalGridData.FOREST:
		w = t.cost_forest
	if f & TacticalGridData.THICK_TREES:
		w = maxf(w, t.cost_thick_trees)
	if f & TacticalGridData.NEAR_BLOCKED and not f & TacticalGridData.ROAD:
		w = maxf(w, t.cost_near_blocked)   # streets between houses stay cheap
	if f & TacticalGridData.CONCEALED:
		w *= t.concealed_factor
	return w


func is_blocked(point: Vector3) -> bool:
	return grid.flags_at(grid.cell_of(point)) & TacticalGridData.BLOCKED != 0


## Waypoints from `from` to `to` (world, at ground height), or empty if there is no
## way (or both ends lie far inside closed areas).
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start: Vector2i = _snap(grid.cell_of(from))
	var goal: Vector2i = _snap(grid.cell_of(to))
	if start.x < 0 or goal.x < 0:
		return PackedVector3Array()
	var cells: Array[Vector2i] = _astar.get_id_path(start, goal, true)
	if cells.is_empty():
		return PackedVector3Array()
	var straight: Array[Vector2i] = _straighten(cells)
	var result := PackedVector3Array()
	for c: Vector2i in straight:
		result.append(grid.center_of(c))
	result.remove_at(0)   # the start cell: where the tank already is
	# Finish at the asked-for point when it is drivable and the last leg to it is clear,
	# else at the centre of the nearest open cell.
	if goal == grid.cell_of(to):
		var before: Vector2i = straight[straight.size() - 2] if straight.size() >= 2 else start
		var limit: float = maxf(_weights[grid.index_of(before)], _weights[grid.index_of(goal)])
		var to_cells := Vector2((to.x - grid.origin.x) / grid.cell_size, (to.z - grid.origin.y) / grid.cell_size)
		if _ray_ok(Vector2(before) + Vector2(0.5, 0.5), to_cells, limit):
			if result.size() > 0:
				result[result.size() - 1] = to
			else:
				result.append(to)
	return result


## The cell itself if open, else the nearest open cell within SNAP_RADIUS_CELLS, else
## (-1, -1).
func _snap(cell: Vector2i) -> Vector2i:
	cell = Vector2i(clampi(cell.x, 0, grid.width - 1), clampi(cell.y, 0, grid.height - 1))
	if not _astar.is_point_solid(cell):
		return cell
	for r: int in range(1, SNAP_RADIUS_CELLS + 1):
		var best := Vector2i(-1, -1)
		var best_d: float = INF
		for dz: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var c := cell + Vector2i(dx, dz)
				if grid.has_cell(c) and not _astar.is_point_solid(c):
					var d: float = Vector2(dx, dz).length()
					if d < best_d:
						best_d = d
						best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Drops waypoints where a straight line from an earlier one crosses no closed cell
## and no cell dearer than the stretch of path it replaces (so shortcuts don't leave
## cover or cut through forest the path went around).
func _straighten(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = [cells[0]]
	var i: int = 0
	while i < cells.size() - 1:
		var best: int = i + 1
		var dearest: float = _weights[grid.index_of(cells[i])]
		var last: int = mini(cells.size() - 1, i + SMOOTH_LOOKAHEAD)
		for j: int in range(i + 1, last + 1):
			dearest = maxf(dearest, _weights[grid.index_of(cells[j])])
			if _line_ok(cells[i], cells[j], dearest):
				best = j
		out.append(cells[best])
		i = best
	return out


## A straight line between two cells crosses no closed cell and none dearer than `limit`.
## Checked exactly (every cell the line passes) along the centre line and two lines a
## little to each side (tanks are ~3 m wide), so a shortcut can't clip a house corner.
func _line_ok(a: Vector2i, b: Vector2i, limit: float) -> bool:
	var from := Vector2(a) + Vector2(0.5, 0.5)
	var to := Vector2(b) + Vector2(0.5, 0.5)
	var dir: Vector2 = to - from
	var length: float = dir.length()
	if length < 0.001:
		return true
	var side: Vector2 = Vector2(-dir.y, dir.x) / length * LINE_HALF_WIDTH_CELLS
	return _ray_ok(from, to, limit) and _ray_ok(from + side, to + side, limit) \
			and _ray_ok(from - side, to - side, limit)


## Walks every cell a segment (in cell units) passes through (Amanatides-Woo).
func _ray_ok(from: Vector2, to: Vector2, limit: float) -> bool:
	var cell := Vector2i(floori(from.x), floori(from.y))
	var end := Vector2i(floori(to.x), floori(to.y))
	var dir: Vector2 = to - from
	var step := Vector2i(signi(roundi(signf(dir.x))), signi(roundi(signf(dir.y))))
	var t_delta := Vector2(INF if dir.x == 0.0 else absf(1.0 / dir.x),
			INF if dir.y == 0.0 else absf(1.0 / dir.y))
	var t_max := Vector2(
			INF if dir.x == 0.0 else ((cell.x + (1 if step.x > 0 else 0)) - from.x) / dir.x,
			INF if dir.y == 0.0 else ((cell.y + (1 if step.y > 0 else 0)) - from.y) / dir.y)
	var guard: int = absi(end.x - cell.x) + absi(end.y - cell.y) + 2
	while guard > 0:
		guard -= 1
		if not grid.has_cell(cell) or _weights[grid.index_of(cell)] > limit + 0.001:
			return false
		if cell == end:
			return true
		if t_max.x < t_max.y:
			t_max.x += t_delta.x
			cell.x += step.x
		else:
			t_max.y += t_delta.y
			cell.y += step.y
	return true
