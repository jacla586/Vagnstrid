class_name GroundCoverData
extends Resource
## A map's ground-cover classes, one byte per cell (index into GroundCoverSetData.classes),
## row by row from the north-west corner: cell (col, row) covers world x = col × cell_m,
## z = row × cell_m. Made from geodata/<map>/out/markvegetation.bin by
## tools/import_ground_cover.gd into data/maps/<map>_groundcover.res.

@export var width: int = 0
@export var height: int = 0
@export var cell_m: float = 2.0
@export var classes: PackedByteArray = PackedByteArray()


func class_at(pos: Vector3) -> int:
	var c: int = int(roundf(pos.x / cell_m))
	var r: int = int(roundf(pos.z / cell_m))
	if c < 0 or r < 0 or c >= width or r >= height:
		return 0
	return classes[r * width + c]


## The ground cover for the scene's terrain (Terrain3D data_directory res://terrain/<map>),
## or null if none has been made.
static func find_for_scene(scene_root: Node) -> GroundCoverData:
	if scene_root == null:
		return null
	var terrains: Array[Node] = scene_root.find_children("*", "Terrain3D", true, false)
	if terrains.is_empty():
		return null
	var map_name: String = String(terrains[0].get("data_directory")).get_file()
	var path: String = "res://data/maps/%s_groundcover.res" % map_name
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GroundCoverData
