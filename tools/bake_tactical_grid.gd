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
## Houses and stones are looked for with a box this share of the cell wide, from
## HOUSE_BOX_BOTTOM_M to HOUSE_BOX_TOP_M above the ground: anything in it blocks.
const HOUSE_BOX_SHARE: float = 0.85
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
## Land cover classes (geodata heightmap_info.json "landcover_classes").
const LC_SEA: int = 0
const LC_FOREST: int = 2
const LC_WETLAND: int = 7
const LC_LAKE: int = 11
const LC_ROAD_PAVED: int = 12
const LC_ROAD_GRAVEL: int = 13
const LC_RES_M: float = 2.0
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
	var house_box := BoxShape3D.new()
	house_box.size = Vector3(_cell * HOUSE_BOX_SHARE, HOUSE_BOX_TOP_M - HOUSE_BOX_BOTTOM_M,
			_cell * HOUSE_BOX_SHARE)
	var house_query := PhysicsShapeQueryParameters3D.new()
	house_query.shape = house_box
	house_query.collision_mask = 1
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
			if _fine_slope_deg(terrain_data, p) > MAX_FINE_SLOPE_DEG:
				f |= TacticalGridData.STEEP
			if h <= SEA_LEVEL_M:
				f |= TacticalGridData.WATER
			house_query.transform = Transform3D(Basis(), p + Vector3.UP * (HOUSE_BOX_BOTTOM_M
					+ HOUSE_BOX_TOP_M) * 0.5)
			if _hits_blocking(space, house_query) or _under_roof(space, p):
				f |= TacticalGridData.HOUSE
			if _has_cover(space, p):
				f |= TacticalGridData.CONCEALED
			if landcover != null:
				f |= _landcover_flags(landcover, p)
			grid.flags[grid.index_of(c)] = f
	# Slope from the neighbours' heights (after all heights are known).
	for cz: int in grid.height:
		for cx: int in grid.width:
			var c := Vector2i(cx, cz)
			if _slope_deg(grid, c) > MAX_SLOPE_DEG:
				grid.flags[grid.index_of(c)] |= TacticalGridData.STEEP
	_mark_thick_trees(scene, grid)
	# Streams and lake shores: widen water into its side neighbours (not across roads,
	# where culverts and bridges are), so a diagonal stream is a closed line.
	var wet_edge: PackedInt32Array = []
	for cz: int in grid.height:
		for cx: int in grid.width:
			var c := Vector2i(cx, cz)
			var f: int = grid.flags[grid.index_of(c)]
			if f & (TacticalGridData.WATER | TacticalGridData.ROAD):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = c + d
				if grid.has_cell(nb) and grid.flags[grid.index_of(nb)] & TacticalGridData.WATER \
						and not grid.flags[grid.index_of(nb)] & TacticalGridData.ROAD:
					wet_edge.append(grid.index_of(c))
					break
	for i: int in wet_edge:
		grid.flags[i] |= TacticalGridData.WATER
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
func _hits_blocking(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> bool:
	for r: Dictionary in space.intersect_shape(query, 16):
		var collider: Object = r["collider"]
		if collider is Terrain3D or collider is TreeField:
			continue
		if _is_blocking_object(collider as Node):
			return true
	return false


## A house over the cell's centre: a ray from above meets a roof before the ground. The
## box above only touches walls, so cells inside a wide house (B-huset's wings) were open
## and let enclosed courtyards connect to the streets.
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
