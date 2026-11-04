class_name TacticalGridData
extends Resource
## A map seen as a grid for the bots: ground height and what each cell is (house,
## water, forest, road, cover...). Made by tools/bake_tactical_grid.gd and saved as
## data/maps/<map>_tactical.res; TacticalMap turns it into paths and positions.
## Map knowledge only (players know the map too): no enemy information in here.

## Cell flags.
const BLOCKED: int = 1     ## can't drive here (house, stone, water, too steep)
const CONCEALED: int = 2   ## bushes or tree crowns hide a tank here
const FOREST: int = 4      ## trees: slow (felling them)
const ROAD: int = 8        ## paved or gravel road: fast
const WET: int = 16        ## wetland: slow
const WATER: int = 32      ## sea, lake (also BLOCKED)
const HOUSE: int = 64      ## a building or stone (also BLOCKED)
const STEEP: int = 128     ## steeper than the tanks can take (also BLOCKED)
const NEAR_BLOCKED: int = 256  ## next to a house or stone: drive past, not along it
const THICK_TREES: int = 512   ## trees too thick to push over: slow going round them

## World (x, z) of the north-west corner of cell (0, 0).
@export var origin: Vector2 = Vector2.ZERO
## Cell side (m).
@export var cell_size: float = 8.0
@export var width: int = 0
@export var height: int = 0
## Ground height at each cell centre (m), row by row (z), west to east (x).
@export var heights: PackedFloat32Array = PackedFloat32Array()
@export var flags: PackedInt32Array = PackedInt32Array()


func index_of(cell: Vector2i) -> int:
	return cell.y * width + cell.x


func has_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori((point.x - origin.x) / cell_size), floori((point.z - origin.y) / cell_size))


## World position of a cell's centre, at ground height.
func center_of(cell: Vector2i) -> Vector3:
	return Vector3(origin.x + (cell.x + 0.5) * cell_size, heights[index_of(cell)],
			origin.y + (cell.y + 0.5) * cell_size)


func flags_at(cell: Vector2i) -> int:
	return flags[index_of(cell)] if has_cell(cell) else BLOCKED


## The grid for the scene's terrain (Terrain3D data_directory res://terrain/<map>),
## or null if none has been baked.
static func find_for_scene(scene_root: Node) -> TacticalGridData:
	if scene_root == null:
		return null
	var terrains: Array[Node] = scene_root.find_children("*", "Terrain3D", true, false)
	if terrains.is_empty():
		return null
	var map_name: String = String(terrains[0].get("data_directory")).get_file()
	var path: String = "res://data/maps/%s_tactical.res" % map_name
	if not ResourceLoader.exists(path):
		return null
	return load(path) as TacticalGridData
