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
## How far round an unreachable goal to look for a reachable cell (cells).
const COMPONENT_SEARCH_CELLS: int = 40
## Open areas with fewer cells than this that connect to nothing else (courtyards closed
## in by houses, a patch walled in by water and banks) are closed like houses: nobody
## spawns, is sent or parks there, as there's no way out. 150 cells = ~1 ha.
const POCKET_MAX_CELLS: int = 150
## Commander's eye above the ground with the hatch open (m).
const EYE_HEIGHT_M: float = 3.0
## What a position must see: points this high above the ground (a tank's hull, m).
const LOOK_TARGET_HEIGHT_M: float = 1.5
## Sight rays start this far out from the eye (the bush the tank stands in, m).
const SIGHT_START_SKIP_M: float = 4.0
## Sight counts as clear if the ray stops this close to its target (m).
const SIGHT_END_SLACK_M: float = 3.0
## Hull down: probe the ground this far towards the threat (m); a crest this high
## above the spot hides the hull (m); higher hides the view too.
const HULL_DOWN_PROBE_M: Array[float] = [4.0, 8.0, 12.0]
const HULL_DOWN_MIN_M: float = 0.8
const HULL_DOWN_MAX_M: float = 1.8
const HULL_DOWN_BLIND_M: float = 2.5
## Half the width a straightened leg must keep clear, in cells (8 m cells: ~2.4 m).
const LINE_HALF_WIDTH_CELLS: float = 0.3

static var _cache: Dictionary = {}  # "grid id/tactics id" -> TacticalMap
## Path planning budget per physics tick (all maps and bots together, ms): the first
## plan of a tick always runs, later ones wait for a tick with time left
## (`may_plan`, BotController's pending plans), so plans don't pile up into one tick.
static var plan_budget_ms: float = 3.0
static var _plan_tick: int = -1
static var _plan_used_ms: float = 0.0

var grid: TacticalGridData
var _astar: AStarGrid2D
var _weights: PackedFloat32Array
## Per cell: which connected area of open cells it belongs to (-1 = closed).
var _components: PackedInt32Array
## 1 = open cell right beside forest or bushes (a tree line).
var _edge: PackedByteArray
## The map's playable area (MapEdge; empty = none): cells outside are closed.
var _inside: Rect2 = Rect2()


## The map for the scene's terrain with `tactics` path costs (null = the tanks'
## default), or null if its grid hasn't been baked. One per grid and cost set.
static func for_scene(scene_root: Node, tactics: TacticsData = null) -> TacticalMap:
	var data: TacticalGridData = TacticalGridData.find_for_scene(scene_root)
	if data == null:
		return null
	if tactics == null:
		tactics = DEFAULT_TACTICS
	var key: String = "%d/%d" % [data.get_instance_id(), tactics.get_instance_id()]
	if not _cache.has(key):
		_cache[key] = TacticalMap.new(data, tactics, MapEdge.inner_rect(scene_root.get_tree()))
	return _cache[key]


func _init(data: TacticalGridData, tactics: TacticsData, inside: Rect2 = Rect2()) -> void:
	grid = data
	_inside = inside
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, grid.width, grid.height)
	_astar.cell_size = Vector2(grid.cell_size, grid.cell_size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_astar.update()
	_weights.resize(grid.width * grid.height)
	_find_edges()
	for z: int in grid.height:
		for x: int in grid.width:
			var c := Vector2i(x, z)
			var i: int = grid.index_of(c)
			var f: int = grid.flags[i]
			if f & TacticalGridData.BLOCKED or not _is_inside(c):
				_astar.set_point_solid(c, true)
				_weights[i] = INF
				continue
			var w: float = _cost(f, tactics)
			if _edge[i] != 0:
				w = minf(w, tactics.cost_cover_edge)
			_weights[i] = w
			_astar.set_point_weight_scale(c, w)
	_label_components()
	_close_pockets()


## Open, drivable cells with forest or bushes in a neighbouring cell.
func _find_edges() -> void:
	_edge.resize(grid.width * grid.height)
	var covering: int = TacticalGridData.CONCEALED | TacticalGridData.FOREST
	var skip: int = covering | TacticalGridData.BLOCKED
	for z: int in grid.height:
		for x: int in grid.width:
			var c := Vector2i(x, z)
			if grid.flags[grid.index_of(c)] & skip:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				if grid.flags_at(c + d) & covering and not grid.flags_at(c + d) & TacticalGridData.BLOCKED:
					_edge[grid.index_of(c)] = 1
					break


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


## The cell under `point` is road (OSM/NVDB roads baked into the grid).
func is_road(point: Vector3) -> bool:
	var c: Vector2i = grid.cell_of(point)
	return grid.has_cell(c) and grid.flags[grid.index_of(c)] & TacticalGridData.ROAD != 0


## Something beside the way hides or shields a tank here: bushes or crowns, forest,
## a tree line, or houses next to it.
func is_covered(point: Vector3) -> bool:
	var c: Vector2i = grid.cell_of(point)
	if not grid.has_cell(c):
		return false
	var f: int = grid.flags[grid.index_of(c)]
	return f & (TacticalGridData.CONCEALED | TacticalGridData.FOREST | TacticalGridData.NEAR_BLOCKED) != 0 \
			or _edge[grid.index_of(c)] != 0


## Where along `path` (starting at `from`) to stop and scout: the last covered spot
## before each open stretch of at least scout_open_m, at least scout_min_spacing_m
## apart. Not where the tank already stands in the open.
func scout_points(from: Vector3, path: PackedVector3Array, tactics: TacticsData) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var step: float = grid.cell_size
	var last_covered := Vector3.INF
	var open_since: float = -1.0   # distance along the path where the open stretch began
	var travelled: float = 0.0
	var last_stop: float = -INF
	var prev: Vector3 = from
	for p: Vector3 in path:
		var leg: float = prev.distance_to(p)
		var n: int = maxi(ceili(leg / step), 1)
		for i: int in range(1, n + 1):
			var q: Vector3 = prev.lerp(p, float(i) / n)
			var d: float = travelled + leg * i / n
			if is_covered(q):
				last_covered = q
				open_since = -1.0
			elif open_since < 0.0:
				open_since = d
				# Open ahead from a covered spot: stop there if the stretch turns out long.
			elif d - open_since >= tactics.scout_open_m and last_covered != Vector3.INF \
					and open_since - last_stop >= tactics.scout_min_spacing_m:
				points.append(last_covered)
				last_stop = open_since
				last_covered = Vector3.INF   # one stop per stretch
		travelled += leg
		prev = p
	return points


## Where to stand in a circle (`center`, `radius`) to fight towards `threat_dir`
## while watching `look_at` (± `look_spread` sideways): tries candidate spots and
## scores cover, hull-down ground (from the grid's heights), sight lines from the
## commander's eye, spacing from `friends` and the drive from `from`. Weights in
## `tactics`. Returns `center` (on the ground) if no candidate is drivable.
## With `min_progress` > 0 only spots at least that much closer (flat) to `progress_to`
## than `from` count (a bound must get somewhere).
## Its time counts towards the tick's planning budget (may_plan), like find_path's.
func find_position(world: World3D, center: Vector3, radius: float, threat_dir: Vector3,
		look_at: Vector3, look_spread: float, from: Vector3, friends: PackedVector3Array,
		tactics: TacticsData, rng: RandomNumberGenerator, exclude: Array[RID] = [],
		progress_to: Vector3 = Vector3.ZERO, min_progress: float = 0.0) -> Vector3:
	may_plan()   # starts this tick's count
	var started: int = Time.get_ticks_usec()
	var spot: Vector3 = _find_position(world, center, radius, threat_dir, look_at, look_spread,
			from, friends, tactics, rng, exclude, progress_to, min_progress)
	_plan_used_ms += (Time.get_ticks_usec() - started) / 1000.0
	return spot


func _find_position(world: World3D, center: Vector3, radius: float, threat_dir: Vector3,
		look_at: Vector3, look_spread: float, from: Vector3, friends: PackedVector3Array,
		tactics: TacticsData, rng: RandomNumberGenerator, exclude: Array[RID],
		progress_to: Vector3, min_progress: float) -> Vector3:
	var start_dist: float = Vector2(progress_to.x - from.x, progress_to.z - from.z).length()
	var threat := Vector3(threat_dir.x, 0.0, threat_dir.z)
	threat = threat.normalized() if threat.length() > 0.01 else Vector3.FORWARD
	var side: Vector3 = threat.cross(Vector3.UP)
	var looks: Array[Vector3] = []
	for k: float in [-1.0, 0.0, 1.0]:
		var p: Vector3 = look_at + side * look_spread * 0.5 * k
		looks.append(Vector3(p.x, _height_at(p) + LOOK_TARGET_HEIGHT_M, p.z))
	var best: Vector3 = Vector3(center.x, _height_at(center), center.z)
	var best_score: float = -INF
	for i: int in tactics.position_candidates:
		var offset: Vector2 = Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius
		var p := Vector3(center.x + offset.x, 0.0, center.z + offset.y)
		var c: Vector2i = grid.cell_of(p)
		if not grid.has_cell(c) or grid.flags[grid.index_of(c)] & TacticalGridData.BLOCKED \
				or not _is_inside(c):
			continue
		p.y = grid.heights[grid.index_of(c)]
		if min_progress > 0.0 and start_dist - Vector2(progress_to.x - p.x,
				progress_to.z - p.z).length() < min_progress:
			continue
		var score: float = _position_score(world, p, threat, looks, from, friends, tactics, exclude)
		if score > best_score:
			best_score = score
			best = p
	return best


func _position_score(world: World3D, p: Vector3, threat: Vector3, looks: Array[Vector3],
		from: Vector3, friends: PackedVector3Array, t: TacticsData, exclude: Array[RID]) -> float:
	var score: float = 0.0
	var c: Vector2i = grid.cell_of(p)
	if is_covered(p):
		score += t.w_cover
	if grid.flags[grid.index_of(c)] & TacticalGridData.CONCEALED:
		score += t.w_concealed
	# Hull down: the highest ground a few metres towards the threat.
	var crest: float = -INF
	for d: float in HULL_DOWN_PROBE_M:
		crest = maxf(crest, _height_at(p + threat * d) - p.y)
	if crest >= HULL_DOWN_MIN_M and crest <= HULL_DOWN_MAX_M:
		score += t.w_hull_down
	elif crest > HULL_DOWN_BLIND_M:
		score -= t.w_hull_down
	# Sight lines from the commander's eye.
	var eye: Vector3 = p + Vector3.UP * EYE_HEIGHT_M
	for target: Vector3 in looks:
		if _sight_clear(world, eye, target, exclude):
			score += t.w_sight
	for f: Vector3 in friends:
		var d: float = Vector2(f.x - p.x, f.z - p.z).length()
		if d < t.spread_min_m:
			score -= t.w_spacing * (1.0 - d / t.spread_min_m)
	score -= t.w_travel * from.distance_to(p) / 100.0
	return score


## Ground height under a world point from the grid (0 off the grid).
func _height_at(p: Vector3) -> float:
	var c: Vector2i = grid.cell_of(p)
	return grid.heights[grid.index_of(c)] if grid.has_cell(c) else 0.0


## Nothing blocks sight (terrain, houses, bushes, crowns) between `from` and `to`,
## or the first thing hit is right at `to` (the ground there). The first few metres
## are skipped: a tank in a bush looks out through its edge.
static func _sight_clear(world: World3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> bool:
	var dir: Vector3 = (to - from).normalized()
	var query := PhysicsRayQueryParameters3D.create(from + dir * SIGHT_START_SKIP_M, to)
	query.collide_with_areas = true
	query.exclude = exclude
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < SIGHT_END_SLACK_M


func is_blocked(point: Vector3) -> bool:
	var c: Vector2i = grid.cell_of(point)
	if grid.flags_at(c) & TacticalGridData.BLOCKED != 0 or not _is_inside(c):
		return true
	return grid.has_cell(c) and _components[grid.index_of(c)] < 0


## The cell's centre lies in the map's playable area (MapEdge).
func _is_inside(c: Vector2i) -> bool:
	if not _inside.has_area():
		return true
	return _inside.has_point(Vector2(grid.origin.x + (c.x + 0.5) * grid.cell_size,
			grid.origin.y + (c.y + 0.5) * grid.cell_size))


## How dear the way from `from` to `to` is (sum of path cost weights times metres; INF
## if there is no way) and the share of it that runs covered (is_covered). For judging
## places (zone placement), not for driving: the raw A* cells, not straightened.
func path_info(from: Vector3, to: Vector3) -> Dictionary:
	var start: Vector2i = _snap(grid.cell_of(from))
	var goal: Vector2i = _snap(grid.cell_of(to))
	if start.x < 0 or goal.x < 0 \
			or _components[grid.index_of(start)] != _components[grid.index_of(goal)]:
		return {"cost": INF, "cover": 0.0}
	var cells: Array[Vector2i] = _astar.get_id_path(start, goal)
	if cells.is_empty():
		return {"cost": INF, "cover": 0.0}
	var cost: float = 0.0
	var covered: int = 0
	for k: int in cells.size():
		var i: int = grid.index_of(cells[k])
		var step: float = grid.cell_size
		if k > 0 and cells[k].x != cells[k - 1].x and cells[k].y != cells[k - 1].y:
			step *= 1.4142136
		cost += _weights[i] * step
		if is_covered(grid.center_of(cells[k])):
			covered += 1
	return {"cost": cost, "cover": float(covered) / cells.size()}


## The ground within `radius` of `center` (every 2nd cell): shares of cells that are
## blocked (houses, water, steep), water, and covered (of the drivable ones).
func area_info(center: Vector3, radius: float) -> Dictionary:
	var c: Vector2i = grid.cell_of(center)
	var r: int = ceili(radius / grid.cell_size)
	var total: int = 0
	var blocked: int = 0
	var water: int = 0
	var covered: int = 0
	for dz: int in range(-r, r + 1, 2):
		for dx: int in range(-r, r + 1, 2):
			if dx * dx + dz * dz > r * r:
				continue
			var cell := c + Vector2i(dx, dz)
			total += 1
			if not grid.has_cell(cell):
				blocked += 1
				continue
			var f: int = grid.flags[grid.index_of(cell)]
			if f & TacticalGridData.WATER:
				water += 1
			if f & TacticalGridData.BLOCKED or not _is_inside(cell):
				blocked += 1
			elif is_covered(grid.center_of(cell)):
				covered += 1
	var open: int = maxi(total - blocked, 1)
	return {"blocked": float(blocked) / maxi(total, 1), "water": float(water) / maxi(total, 1),
			"cover": float(covered) / open}


## Waypoints from `from` to `to` (world, at ground height), or empty if there is no
## way (or both ends lie far inside closed areas). `avoid`: extra cells to treat as
## closed for this search (where this tank got stuck on something the grid misses).
## True while this physics tick has planning time left (plan_budget_ms).
static func may_plan() -> bool:
	var tick: int = Engine.get_physics_frames()
	if tick != _plan_tick:
		_plan_tick = tick
		_plan_used_ms = 0.0
	return _plan_used_ms < plan_budget_ms


func find_path(from: Vector3, to: Vector3, avoid: Array[Vector2i] = []) -> PackedVector3Array:
	may_plan()   # starts this tick's count
	var started: int = Time.get_ticks_usec()
	var path: PackedVector3Array = _find_path_avoiding(from, to, avoid)
	_plan_used_ms += (Time.get_ticks_usec() - started) / 1000.0
	return path


func _find_path_avoiding(from: Vector3, to: Vector3, avoid: Array[Vector2i]) -> PackedVector3Array:
	var closed: Array[Vector2i] = []
	for c: Vector2i in avoid:
		if grid.has_cell(c) and not _astar.is_point_solid(c):
			_astar.set_point_solid(c, true)
			closed.append(c)
	var result: PackedVector3Array = _find_path(from, to)
	for c: Vector2i in closed:
		_astar.set_point_solid(c, false)
	return result


func _find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start: Vector2i = _snap(grid.cell_of(from))
	var goal: Vector2i = _snap(grid.cell_of(to))
	if start.x < 0 or goal.x < 0:
		return PackedVector3Array()
	# A goal in a pocket the start can't reach would make A* search the whole map before
	# giving up: head for the nearest cell that can be reached instead.
	if _components[grid.index_of(start)] != _components[grid.index_of(goal)]:
		var reachable: Vector2i = _nearest_in_component(goal, _components[grid.index_of(start)])
		if reachable.x >= 0:
			goal = reachable
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


## Numbers the areas of open cells that connect (4-neighbours: paths can't cut corners).
func _label_components() -> void:
	_components.resize(grid.width * grid.height)
	_components.fill(-1)
	var stack := PackedInt32Array()
	var label: int = 0
	var w: int = grid.width
	for first: int in _components.size():
		if _components[first] >= 0 or is_inf(_weights[first]):
			continue
		_components[first] = label
		stack.append(first)
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x: int = i % w
			for n: int in [i - w, i + w, i - 1 if x > 0 else -1, i + 1 if x < w - 1 else -1]:
				if n >= 0 and n < _components.size() and _components[n] < 0 and not is_inf(_weights[n]):
					_components[n] = label
					stack.append(n)
		label += 1


## Closes the small areas with no way out (POCKET_MAX_CELLS): solid for A*, no
## component, so is_blocked, _snap and find_position keep off them.
func _close_pockets() -> void:
	var sizes: Dictionary = {}   # component -> cells
	for i: int in _components.size():
		var k: int = _components[i]
		if k >= 0:
			sizes[k] = int(sizes.get(k, 0)) + 1
	for i: int in _components.size():
		var k: int = _components[i]
		if k < 0 or int(sizes[k]) >= POCKET_MAX_CELLS:
			continue
		_components[i] = -1
		_weights[i] = INF
		_astar.set_point_solid(Vector2i(i % grid.width, i / grid.width), true)


## The nearest cell of `component` within COMPONENT_SEARCH_CELLS of `cell`, else (-1, -1).
func _nearest_in_component(cell: Vector2i, component: int) -> Vector2i:
	for r: int in range(1, COMPONENT_SEARCH_CELLS + 1):
		var best := Vector2i(-1, -1)
		var best_d: float = INF
		for dz: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var c := cell + Vector2i(dx, dz)
				if grid.has_cell(c) and _components[grid.index_of(c)] == component:
					var d: float = Vector2(dx, dz).length()
					if d < best_d:
						best_d = d
						best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


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
	# Jumps from each kept cell to the farthest cell within SMOOTH_LOOKAHEAD that a
	# straight line reaches. Tried from the far end back, stopping at the first that
	# works: the same cell as trying them all (2026-11-18: that took 7-28 ms on long paths).
	var out: Array[Vector2i] = [cells[0]]
	var dearest := PackedFloat32Array()
	dearest.resize(SMOOTH_LOOKAHEAD + 1)
	var w: int = grid.width
	var i: int = 0
	while i < cells.size() - 1:
		var last: int = mini(cells.size() - 1, i + SMOOTH_LOOKAHEAD)
		# Dearest cell weight on the path from i to each j (a shortcut may cross no cell
		# dearer than the path it replaces).
		var d: float = _weights[cells[i].y * w + cells[i].x]
		for j: int in range(i + 1, last + 1):
			d = maxf(d, _weights[cells[j].y * w + cells[j].x])
			dearest[j - i] = d
		var best: int = i + 1
		for j: int in range(last, i + 1, -1):
			if _line_ok(cells[i], cells[j], dearest[j - i]):
				best = j
				break
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
	var cx: int = floori(from.x)
	var cy: int = floori(from.y)
	var ex: int = floori(to.x)
	var ey: int = floori(to.y)
	var dir: Vector2 = to - from
	var sx: int = signi(roundi(signf(dir.x)))
	var sy: int = signi(roundi(signf(dir.y)))
	# Kept in Vector2s (32-bit floats) as before, so ties step the same way.
	var t_delta := Vector2(INF if dir.x == 0.0 else absf(1.0 / dir.x),
			INF if dir.y == 0.0 else absf(1.0 / dir.y))
	var t_max := Vector2(
			INF if dir.x == 0.0 else ((cx + (1 if sx > 0 else 0)) - from.x) / dir.x,
			INF if dir.y == 0.0 else ((cy + (1 if sy > 0 else 0)) - from.y) / dir.y)
	var w: int = grid.width
	var h: int = grid.height
	var bound: float = limit + 0.001
	# Plain ints and inlined grid lookups: this runs for every cell of every shortcut tried.
	var guard: int = absi(ex - cx) + absi(ey - cy) + 2
	while guard > 0:
		guard -= 1
		if cx < 0 or cy < 0 or cx >= w or cy >= h or _weights[cy * w + cx] > bound:
			return false
		if cx == ex and cy == ey:
			return true
		if t_max.x < t_max.y:
			t_max.x += t_delta.x
			cx += sx
		else:
			t_max.y += t_delta.y
			cy += sy
	return true
