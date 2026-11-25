extends SceneTree
## Bakes the bots' tactical grid for a map (TacticalGridData): ground height and, per
## cell, house/stone, water, steep, forest, road, wetland and cover (bushes, crowns).
##   godot --headless --path . --script res://tools/bake_tactical_grid.gd -- <map> [cell m]
##   e.g. -- vidingsjo
## Reads res://scenes/maps/<map>.tscn, plus the geodata land cover
## (geodata/<map>/out/landcover_index.png) when there is one, for water, forest,
## roads and wetland. Writes res://data/maps/<map>_tactical.res.
## Rerun after the map changes (houses, trees, terrain).

## Steeper than this over a whole cell blocks (degrees; the tanks climb ~32°)...
const MAX_SLOPE_DEG: float = 25.0
## ...or this steep over any FINE_STEP_M inside it (ditch and stream banks, walls of
## earth that the 8 m average smooths away).
const MAX_FINE_SLOPE_DEG: float = 30.0
const FINE_STEP_M: float = 2.0
## Below this the ground is sea (m).
const SEA_LEVEL_M: float = 0.5
## Cover (bushes, tree crowns) is looked for at these heights above the ground (m):
## from hull height up to where crowns hide a tank from a distance.
const COVER_SAMPLE_HEIGHTS_M: Array[float] = [1.5, 3.0, 5.0, 8.0]
## Stones are looked for with a box this share of the cell wide, from HOUSE_BOX_BOTTOM_M
## to HOUSE_BOX_TOP_M above the ground: anything in it blocks. Houses with a smaller box
## (walls in the middle of the cell) plus roofs over ROOF_MIN_SAMPLES of the 3 x 3
## ROOF_SAMPLES_M points: the big box made 8-10 m streets between facades one cell wide
## or shut (Drottninggatan in Peking), and it never saw a wide house's inside.
const HOUSE_BOX_SHARE: float = 0.85
const WALL_BOX_SHARE: float = 0.5
const ROOF_SAMPLES_M: Array[float] = [-2.7, 0.0, 2.7]
const ROOF_MIN_SAMPLES: int = 3
const STONE_PREFIX: String = "Stenar"
const HOUSE_BOX_BOTTOM_M: float = 0.6
const HOUSE_BOX_TOP_M: float = 2.5
## Trees with a trunk thicker than this can't be pushed over (TankData
## tree_push_max_diameter_m of the medium tanks).
const PUSHABLE_TRUNK_M: float = 0.7
## Object groups (children of the map's object glb) that block, and that don't.
## Roof test: a ray from this high above the ground, looking past this many other things.
const ROOF_RAY_FROM_M: float = 120.0
const ROOF_RAY_TRIES: int = 4
const BLOCKING_PREFIXES: Array[String] = ["Byggnader", "Stenar"]
## Bridge decks over water (glb group Broar): a level surface at least DECK_ABOVE_GROUND_M over the
## terrain (river bottom, road below), found by rays at DECK_SAMPLES offsets in the cell
## and wide enough (DECK_WIDTH_PROBE_M aside in 3 of 4 directions) not to be a wall top
## or a footbridge. Such cells are road at the deck's height, never water or steep: the
## terrain under a bridge is the river bottom, so a river was a closed line (Peking).
const BRIDGE_PREFIX: String = "Broar"
const DECK_ABOVE_GROUND_M: float = 1.0
const DECK_MIN_NORMAL_Y: float = 0.9
const DECK_SAMPLES_M: Array[float] = [-2.7, 0.0, 2.7]
const DECK_WIDTH_PROBE_M: float = 2.0
const DECK_LEVEL_SLACK_M: float = 0.5
## Land cover classes (geodata heightmap_info.json "landcover_classes").
const LC_SEA: int = 0
const LC_FOREST: int = 2
const LC_WETLAND: int = 7
const LC_LAKE: int = 11
const LC_ROAD_PAVED: int = 12
const LC_ROAD_GRAVEL: int = 13
const LC_RES_M: float = 2.0
## A road or path cell (land cover) whose ground lies this deep in a lake or river (GroundCoverData
## water levels) at any of the deck sample points is water, not road: a footpath across a creek gave a
## passable cell 1.4 m deep in Tinnerbäcken (Vidingsjö XL) and bots drove into it and stuck.
const ROAD_FORD_MAX_M: float = 0.8
## A road cell (not a bridge deck) with water on two opposite sides is a crossing: its flat top across
## (within CROSSING_TOP_SLACK_M of the highest point, heights every 0.5 m) narrower than this is a
## footpath embankment a tank slides off (Tinnerbäcken, Vidingsjö XL), so it is water; car roads over
## culverts are wider and stay open.
const CROSSING_MIN_WIDTH_M: float = 5.0
## A water cell (land cover, not the sea) whose lake/river water is nowhere deeper than this over the
## ground at its sample points, and not steep, is a ford: wetland (dear, passable), not water, and the
## widening of streams leaves it open. Tinnerbäcken by Söderleden (Vidingsjö XL) was filled to a flat
## U at 0.4-0.6 m (geodata overfarter.json) so bots can cross when wrecks block the bridge.
const SHALLOW_FORD_MAX_M: float = 0.6
## Only a ford of at least this many touching shallow cells counts: single shallow cells scattered in
## streams and on lake shores stay water, so a stream isn't opened through a gap with unknown banks.
const SHALLOW_FORD_MIN_CELLS: int = 6
## Shallow cells this many cells apart (or nearer) belong to one ford: a stream's land cover has gaps
## (Tinnerbäcken north of the bridge: one dry cell split the ford in 4 + 2).
const SHALLOW_FORD_REACH: int = 2
const CROSSING_TOP_SLACK_M: float = 0.5
const LANDCOVER_PATHS: Array[String] = ["res://geodata/%s/out/landcover_index.png",
		"res://geodata/out/landcover_index.png"]
const MAIN_GEODATA_MAP: String = "vikbolandet"

var _map: String = ""
var _cell: float = 8.0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <map> [cell size m]")
		quit(1)
		return
	_map = args[0]
	if args.size() >= 2:
		_cell = maxf(float(args[1]), 2.0)
	_run.call_deferred()


## Width (m) of the flat top across a crossing cell: heights every 0.5 m along `axis` (towards the
## water on both sides) through the cell's centre, the run round the highest point within
## CROSSING_TOP_SLACK_M of it.
func _crossing_width(terrain_data: Object, centre: Vector3, axis: Vector3) -> float:
	var hs: PackedFloat32Array = []
	var top: int = 0
	for k: int in range(-int(_cell), int(_cell) + 1):
		var h: float = terrain_data.call("get_height", centre + axis * (k * 0.5))
		hs.append(-INF if is_nan(h) else h)
		if hs[hs.size() - 1] > hs[top]:
			top = hs.size() - 1
	var lo: int = top
	var hi: int = top
	while lo > 0 and hs[lo - 1] >= hs[top] - CROSSING_TOP_SLACK_M:
		lo -= 1
	while hi < hs.size() - 1 and hs[hi + 1] >= hs[top] - CROSSING_TOP_SLACK_M:
		hi += 1
	return (hi - lo) * 0.5


## Turns shallow clusters under SHALLOW_FORD_MIN_CELLS back into water (marks 1: WET was added,
## 2: the land cover had it) and clears their marks; returns the cells kept as fords.
func _keep_big_fords(grid: TacticalGridData, shallow: PackedByteArray) -> int:
	var seen := PackedByteArray()
	seen.resize(shallow.size())
	var kept: int = 0
	for start: int in shallow.size():
		if shallow[start] == 0 or seen[start] == 1:
			continue
		var cluster: PackedInt32Array = [start]
		seen[start] = 1
		var k: int = 0
		while k < cluster.size():
			var i: int = cluster[k]
			k += 1
			var c := Vector2i(i % grid.width, i / grid.width)
			for dz: int in range(-SHALLOW_FORD_REACH, SHALLOW_FORD_REACH + 1):
				for dx: int in range(-SHALLOW_FORD_REACH, SHALLOW_FORD_REACH + 1):
					var nb := Vector2i(c.x + dx, c.y + dz)
					if not grid.has_cell(nb):
						continue
					var ni: int = grid.index_of(nb)
					if shallow[ni] != 0 and seen[ni] == 0:
						seen[ni] = 1
						cluster.append(ni)
		if cluster.size() >= SHALLOW_FORD_MIN_CELLS:
			kept += cluster.size()
			continue
		for i: int in cluster:
			var f: int = grid.flags[i] | TacticalGridData.WATER
			if shallow[i] == 1:
				f &= ~TacticalGridData.WET
			grid.flags[i] = f
			shallow[i] = 0
	return kept


## True when the lake/river levels know water at any of the cell's sample points (a water cell
## of the land cover with no level, e.g. a pond the levels miss, is not called shallow).
func _any_water_here(water: GroundCoverData, p: Vector3) -> bool:
	for dx: float in DECK_SAMPLES_M:
		for dz: float in DECK_SAMPLES_M:
			if not is_nan(water.water_level_at(Vector3(p.x + dx, 0.0, p.z + dz))):
				return true
	return false


## Deepest lake/river water over the ground at the cell's deck sample points (0 on land).
func _deepest_water(water: GroundCoverData, terrain_data: Object, p: Vector3) -> float:
	var deepest: float = 0.0
	for dx: float in DECK_SAMPLES_M:
		for dz: float in DECK_SAMPLES_M:
			var q := Vector3(p.x + dx, 0.0, p.z + dz)
			var level: float = water.water_level_at(q)
			var g: float = terrain_data.call("get_height", q)
			if not is_nan(level) and not is_nan(g):
				deepest = maxf(deepest, level - g)
	return deepest


func _run() -> void:
	var packed := load("res://scenes/maps/%s.tscn" % _map) as PackedScene
	if packed == null:
		push_error("no scene res://scenes/maps/%s.tscn" % _map)
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	for i: int in 10:   # colliders (houses, tree chunks) are made in _ready / first frames
		await physics_frame
	var terrains: Array[Node] = scene.find_children("*", "Terrain3D", true, false)
	if terrains.is_empty():
		push_error("no Terrain3D in the map")
		quit(1)
		return
	var terrain_data: Object = terrains[0].get("data")
	var area: Rect2 = _find_area(scene)
	var started: int = Time.get_ticks_msec()
	var grid := TacticalGridData.new()
	grid.origin = area.position
	grid.cell_size = _cell
	grid.width = ceili(area.size.x / _cell)
	grid.height = ceili(area.size.y / _cell)
	var n: int = grid.width * grid.height
	grid.heights.resize(n)
	grid.flags.resize(n)
	var space: PhysicsDirectSpaceState3D = scene.get_viewport().get_world_3d().direct_space_state
	var landcover: Image = _load_landcover()
	var water_data: GroundCoverData = GroundCoverData.find_for_scene(scene)
	var fords: int = 0
	var shallow := PackedByteArray()
	shallow.resize(grid.width * grid.height)
	var bridges := PackedByteArray()
	bridges.resize(n)
	var house_box := BoxShape3D.new()
	house_box.size = Vector3(_cell * HOUSE_BOX_SHARE, HOUSE_BOX_TOP_M - HOUSE_BOX_BOTTOM_M,
			_cell * HOUSE_BOX_SHARE)
	var house_query := PhysicsShapeQueryParameters3D.new()
	house_query.shape = house_box
	house_query.collision_mask = 1
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(_cell * WALL_BOX_SHARE, HOUSE_BOX_TOP_M - HOUSE_BOX_BOTTOM_M,
			_cell * WALL_BOX_SHARE)
	var wall_query := PhysicsShapeQueryParameters3D.new()
	wall_query.shape = wall_box
	wall_query.collision_mask = 1
	for cz: int in grid.height:
		for cx: int in grid.width:
			var c := Vector2i(cx, cz)
			var p: Vector3 = Vector3(grid.origin.x + (cx + 0.5) * _cell, 0.0,
					grid.origin.y + (cz + 0.5) * _cell)
			var h: float = terrain_data.call("get_height", p)
			if is_nan(h):
				h = 0.0
			grid.heights[grid.index_of(c)] = h
			p.y = h
			var f: int = 0
			var lc: int = _landcover_flags(landcover, p) if landcover != null else 0
			# Only over water: an underpass' deck would lift its cells above the trench road.
			# Water also from the lake/river levels (a stream under a road bridge is road in the
			# land cover), and a steep road cell (a bridge over a dry bank): Söderleden's bridge
			# over Tinnerbäcken (Vidingsjö XL) was steep, the main road cut, bots jammed on footpaths.
			var deck: float = NAN
			if h <= SEA_LEVEL_M or lc & TacticalGridData.WATER \
					or (water_data != null and _deepest_water(water_data, terrain_data, p) > 0.0) \
					or (lc & TacticalGridData.ROAD and _fine_slope_deg(terrain_data, p) > MAX_FINE_SLOPE_DEG):
				deck = _bridge_deck(space, terrain_data, p)
			if not is_nan(deck):
				bridges[grid.index_of(c)] = 1
				grid.heights[grid.index_of(c)] = deck
			elif _fine_slope_deg(terrain_data, p) > MAX_FINE_SLOPE_DEG:
				f |= TacticalGridData.STEEP
			if h <= SEA_LEVEL_M and is_nan(deck):
				f |= TacticalGridData.WATER
			house_query.transform = Transform3D(Basis(), p + Vector3.UP * (HOUSE_BOX_BOTTOM_M
					+ HOUSE_BOX_TOP_M) * 0.5)
			wall_query.transform = house_query.transform
			if _hits_blocking(space, house_query, true) or _hits_blocking(space, wall_query, false) \
					or _roofed_samples(space, p) >= ROOF_MIN_SAMPLES:
				f |= TacticalGridData.HOUSE
			if _has_cover(space, p):
				f |= TacticalGridData.CONCEALED
			f |= lc
			if is_nan(deck) and f & TacticalGridData.WATER and not f & (TacticalGridData.STEEP
					| TacticalGridData.ROAD) and h > SEA_LEVEL_M and water_data != null \
					and _deepest_water(water_data, terrain_data, p) <= SHALLOW_FORD_MAX_M \
					and _any_water_here(water_data, p):
				shallow[grid.index_of(c)] = 2 if f & TacticalGridData.WET else 1
				f = (f & ~TacticalGridData.WATER) | TacticalGridData.WET
			if is_nan(deck) and f & TacticalGridData.ROAD and water_data != null \
					and _deepest_water(water_data, terrain_data, p) > ROAD_FORD_MAX_M:
				f = (f & ~TacticalGridData.ROAD) | TacticalGridData.WATER
				fords += 1
			if not is_nan(deck):
				f = (f & ~(TacticalGridData.WATER | TacticalGridData.WET)) | TacticalGridData.ROAD
			grid.flags[grid.index_of(c)] = f
	# A deck found over water continues along the bridge: road cells next to a deck cell are
	# tried too (the bridge's ends over dry banks or a stream the water test missed), over and
	# over, so the whole deck is found (Söderleden over Tinnerbäcken: one cell of five).
	var grown: int = 0
	var queue: Array[Vector2i] = []
	for cz: int in grid.height:
		for cx: int in grid.width:
			if bridges[cz * grid.width + cx] == 1:
				queue.append(Vector2i(cx, cz))
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for dz: int in [-1, 0, 1]:
			for dx: int in [-1, 0, 1]:
				var nb := Vector2i(c.x + dx, c.y + dz)
				if not grid.has_cell(nb):
					continue
				var ni: int = grid.index_of(nb)
				if bridges[ni] == 1 or not grid.flags[ni] & TacticalGridData.ROAD:
					continue
				var np := Vector3(grid.origin.x + (nb.x + 0.5) * _cell, 0.0, grid.origin.y + (nb.y + 0.5) * _cell)
				var d: float = _bridge_deck(space, terrain_data, np)
				if is_nan(d):
					continue
				bridges[ni] = 1
				grid.heights[ni] = d
				grid.flags[ni] = (grid.flags[ni] & ~(TacticalGridData.WATER | TacticalGridData.WET
						| TacticalGridData.STEEP)) | TacticalGridData.ROAD
				grown += 1
				queue.append(nb)
	print("bridge deck cells grown along bridges: ", grown)
	# Slope from the neighbours' heights (after all heights are known).
	for cz: int in grid.height:
		for cx: int in grid.width:
			var c := Vector2i(cx, cz)
			if bridges[grid.index_of(c)] == 0 and _slope_deg(grid, c) > MAX_SLOPE_DEG:
				grid.flags[grid.index_of(c)] |= TacticalGridData.STEEP
	_mark_thick_trees(scene, grid)
	var bridge_cells: int = 0
	for b: int in bridges:
		bridge_cells += b
	print("shallow water cells (fords, wetland): ", _keep_big_fords(grid, shallow))
	print("bridge deck cells: ", bridge_cells, ", road cells in deep water (fords) closed: ", fords)
	# Streams and lake shores: widen water into its side neighbours (not across roads,
	# where culverts and bridges are), so a diagonal stream is a closed line.
	var wet_edge: PackedInt32Array = []
	for cz: int in grid.height:
		for cx: int in grid.width:
			var c := Vector2i(cx, cz)
			var f: int = grid.flags[grid.index_of(c)]
			if f & (TacticalGridData.WATER | TacticalGridData.ROAD) or shallow[grid.index_of(c)] == 1:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = c + d
				if grid.has_cell(nb) and grid.flags[grid.index_of(nb)] & TacticalGridData.WATER \
						and not grid.flags[grid.index_of(nb)] & TacticalGridData.ROAD:
					wet_edge.append(grid.index_of(c))
					break
	for i: int in wet_edge:
		grid.flags[i] |= TacticalGridData.WATER
	var narrow: PackedInt32Array = []
	for cz: int in grid.height:
		for cx: int in grid.width:
			var c := Vector2i(cx, cz)
			var i: int = grid.index_of(c)
			if not grid.flags[i] & TacticalGridData.ROAD or grid.flags[i] & TacticalGridData.WATER \
					or bridges[i] == 1:
				continue
			for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a: Vector2i = c + axis
				var b: Vector2i = c - axis
				if grid.has_cell(a) and grid.has_cell(b) \
						and grid.flags[grid.index_of(a)] & TacticalGridData.WATER \
						and grid.flags[grid.index_of(b)] & TacticalGridData.WATER \
						and _crossing_width(terrain_data, grid.center_of(c), Vector3(axis.x, 0.0, axis.y)) \
						< CROSSING_MIN_WIDTH_M:
					narrow.append(i)
					break
	for i: int in narrow:
		grid.flags[i] = (grid.flags[i] & ~TacticalGridData.ROAD) | TacticalGridData.WATER
	print("narrow crossings over water closed: ", narrow.size())
	# Cells beside a house or stone: dearer, so paths keep off the walls.
	var near: PackedInt32Array = []
	for cz: int in grid.height:
		for cx: int in grid.width:
			var c := Vector2i(cx, cz)
			if grid.flags[grid.index_of(c)] & TacticalGridData.HOUSE:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				if grid.has_cell(c + d) and grid.flags[grid.index_of(c + d)] & TacticalGridData.HOUSE:
					near.append(grid.index_of(c))
					break
	for i: int in near:
		grid.flags[i] |= TacticalGridData.NEAR_BLOCKED
	var counts: Dictionary = {}
	for i: int in n:
		var f: int = grid.flags[i]
		if f & (TacticalGridData.WATER | TacticalGridData.HOUSE | TacticalGridData.STEEP):
			f |= TacticalGridData.BLOCKED
			grid.flags[i] = f
		for bit: int in [1, 2, 4, 8, 16, 32, 64, 128, 256, 512]:
			if f & bit:
				counts[bit] = int(counts.get(bit, 0)) + 1
	var path: String = "res://data/maps/%s_tactical.res" % _map
	var err: Error = ResourceSaver.save(grid, path)
	print("tactical grid %s: %d x %d cells of %.0f m (%d), %d ms -> %s (%s)" % [_map, grid.width,
			grid.height, _cell, n, Time.get_ticks_msec() - started, path, error_string(err)])
	var names: Dictionary = {1: "blocked", 2: "concealed", 4: "forest", 8: "road", 16: "wet",
			32: "water", 64: "house/stone", 128: "steep", 256: "near house", 512: "thick trees"}
	for bit: int in names:
		print("  %-12s %6d cells (%4.1f %%)" % [names[bit], int(counts.get(bit, 0)),
				100.0 * int(counts.get(bit, 0)) / n])
	if landcover == null:
		print("  (no geodata land cover found: no water/forest/road/wetland from it)")
	quit()


## The map area: the map picture's world rect if rendered, else all Terrain3D regions.
func _find_area(scene: Node) -> Rect2:
	var image: MapImageData = MapImageData.find_for_scene(scene)
	if image != null and image.world_rect.has_area():
		return image.world_rect
	var terrain: Node = scene.find_children("*", "Terrain3D", true, false)[0]
	var data: Object = terrain.get("data")
	var region_size: float = float(terrain.get("region_size")) * float(terrain.get("vertex_spacing"))
	var rect := Rect2()
	for loc: Vector2i in data.call("get_region_locations"):
		var r := Rect2(Vector2(loc) * region_size, Vector2(region_size, region_size))
		rect = r if not rect.has_area() else rect.merge(r)
	return rect


## A house or stone inside the cell's box (above the ground, below roof height).
## (stones: only stones; else anything blocking).
func _hits_blocking(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D,
		stones: bool) -> bool:
	for r: Dictionary in space.intersect_shape(query, 16):
		var collider: Object = r["collider"]
		if collider is Terrain3D or collider is TreeField:
			continue
		if _is_blocking_object(collider as Node) and (not stones or _has_prefix(collider as Node, STONE_PREFIX)):
			return true
	return false


## How many of the cell's 3 x 3 sample points lie under a roof. Wall boxes only touch
## walls, so cells inside a wide house (B-huset's wings) were open and let enclosed
## courtyards connect to the streets.
func _roofed_samples(space: PhysicsDirectSpaceState3D, p: Vector3) -> int:
	var count: int = 0
	for dz: float in ROOF_SAMPLES_M:
		for dx: float in ROOF_SAMPLES_M:
			if _under_roof(space, p + Vector3(dx, 0.0, dz)):
				count += 1
	return count


## A ray from above meets a roof before the ground at p.
func _under_roof(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * ROOF_RAY_FROM_M,
			p + Vector3.UP * HOUSE_BOX_BOTTOM_M, 1)
	var exclude: Array[RID] = []
	for i: int in ROOF_RAY_TRIES:
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider: Object = hit["collider"]
		if not (collider is Terrain3D or collider is TreeField) and _is_blocking_object(collider as Node):
			return true
		exclude.append(hit["rid"])   # a bridge deck, a tree: look on below it
	return false


## The height of a bridge deck over the cell (the highest found), else NAN.
func _bridge_deck(space: PhysicsDirectSpaceState3D, terrain_data: Object, p: Vector3) -> float:
	var best: float = NAN
	for dz: float in DECK_SAMPLES_M:
		for dx: float in DECK_SAMPLES_M:
			var q := Vector3(p.x + dx, 0.0, p.z + dz)
			var y: float = _deck_hit(space, terrain_data, q)
			if is_nan(y):
				continue
			var wide: int = 0
			for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
				var y2: float = _deck_hit(space, terrain_data, q + d * DECK_WIDTH_PROBE_M)
				if not is_nan(y2) and absf(y2 - y) <= DECK_LEVEL_SLACK_M:
					wide += 1
			if wide >= 3 and (is_nan(best) or y > best):
				best = y
	return best


## Where a ray down at (q.x, q.z) first meets a level bridge surface well above the
## terrain, else NAN.
func _deck_hit(space: PhysicsDirectSpaceState3D, terrain_data: Object, q: Vector3) -> float:
	var ground: float = terrain_data.call("get_height", q)
	if is_nan(ground):
		return NAN
	var query := PhysicsRayQueryParameters3D.create(Vector3(q.x, ground + ROOF_RAY_FROM_M, q.z),
			Vector3(q.x, ground + DECK_ABOVE_GROUND_M, q.z), 1)
	var exclude: Array[RID] = []
	for i: int in ROOF_RAY_TRIES:
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return NAN
		var node := hit["collider"] as Node
		if node != null and _has_prefix(node, BRIDGE_PREFIX):
			return (hit["position"] as Vector3).y if (hit["normal"] as Vector3).y >= DECK_MIN_NORMAL_Y else NAN
		if node != null and _is_blocking_object(node):
			return NAN   # a house over it
		exclude.append(hit["rid"])   # trees, lamps, wires: look on below
	return NAN


static func _has_prefix(node: Node, prefix: String) -> bool:
	while node != null:
		if String(node.name).begins_with(prefix):
			return true
		node = node.get_parent()
	return false


## Cells with a standing tree the tanks can't push over.
func _mark_thick_trees(scene: Node, grid: TacticalGridData) -> void:
	var count: int = 0
	for node: Node in scene.find_children("*", "", true, false):
		var field := node as TreeField
		if field == null:
			continue
		for t: int in field.get_tree_count():
			if field.is_tree_felled(t) or field.get_trunk_diameter(t) <= PUSHABLE_TRUNK_M:
				continue
			var c: Vector2i = grid.cell_of(field.get_tree_position(t))
			if grid.has_cell(c):
				grid.flags[grid.index_of(c)] |= TacticalGridData.THICK_TREES
				count += 1
	print("thick trees: ", count)


## Houses and stones block; bridges, trees and anything else don't.
func _is_blocking_object(node: Node) -> bool:
	while node != null:
		for prefix: String in BLOCKING_PREFIXES:
			if String(node.name).begins_with(prefix):
				return true
		node = node.get_parent()
	return false


func _has_cover(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = Vision.LAYER_VISION_BLOCKER
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for h: float in COVER_SAMPLE_HEIGHTS_M:
		q.position = p + Vector3.UP * h
		if not space.intersect_point(q, 1).is_empty():
			return true
	return false


func _load_landcover() -> Image:
	for pattern: String in LANDCOVER_PATHS:
		if pattern.count("%s") == 0 and _map != MAIN_GEODATA_MAP:
			continue
		var path: String = pattern % _map if pattern.count("%s") > 0 else pattern
		var abs_path: String = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null:
				print("land cover: ", path)
				return img
	return null


## Water, forest, roads and wetland from the land cover pixels inside the cell.
func _landcover_flags(img: Image, p: Vector3) -> int:
	var half: int = maxi(roundi(_cell / LC_RES_M / 2.0), 1)
	var cj: int = floori(p.x / LC_RES_M)
	var ci: int = floori(p.z / LC_RES_M)
	var counts: Dictionary = {}
	var total: int = 0
	for i: int in range(ci - half, ci + half):
		for j: int in range(cj - half, cj + half):
			if j < 0 or i < 0 or j >= img.get_width() or i >= img.get_height():
				continue
			var cls: int = roundi(img.get_pixel(j, i).r * 255.0)
			counts[cls] = int(counts.get(cls, 0)) + 1
			total += 1
	if total == 0:
		return 0
	var f: int = 0
	var water: int = int(counts.get(LC_SEA, 0)) + int(counts.get(LC_LAKE, 0))
	if water * 2 > total:
		f |= TacticalGridData.WATER
	if int(counts.get(LC_FOREST, 0)) * 2 > total:
		f |= TacticalGridData.FOREST
	if int(counts.get(LC_WETLAND, 0)) * 2 > total:
		f |= TacticalGridData.WET
	if int(counts.get(LC_ROAD_PAVED, 0)) + int(counts.get(LC_ROAD_GRAVEL, 0)) > 0:
		f |= TacticalGridData.ROAD
	return f


## Steepest slope over FINE_STEP_M across the cell, east-west and north-south (degrees).
func _fine_slope_deg(terrain_data: Object, p: Vector3) -> float:
	var half: int = floori(_cell / FINE_STEP_M / 2.0)
	var steepest: float = 0.0
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var prev: float = NAN
		for k: int in range(-half, half + 1):
			var h: float = terrain_data.call("get_height", p + axis * (k * FINE_STEP_M))
			if not is_nan(prev) and not is_nan(h):
				steepest = maxf(steepest, absf(h - prev))
			prev = h
	return rad_to_deg(atan(steepest / FINE_STEP_M))


## Steepest slope to a direct neighbour (degrees).
func _slope_deg(grid: TacticalGridData, c: Vector2i) -> float:
	var h: float = grid.heights[grid.index_of(c)]
	var steepest: float = 0.0
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb: Vector2i = c + d
		if grid.has_cell(nb):
			steepest = maxf(steepest, absf(grid.heights[grid.index_of(nb)] - h))
	return rad_to_deg(atan(steepest / grid.cell_size))
