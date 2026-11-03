class_name MapImageData
extends Resource
## A top-down picture of a map for the minimap and the big map. Made by
## tools/render_map_image.gd and saved as data/maps/<map>_map.tres.

@export var texture: Texture2D
## The world area the picture covers: position = (x, z) of its north-west corner,
## size = (east-west, north-south) in metres. North (-Z) is up in the picture.
@export var world_rect: Rect2 = Rect2()


## The map picture for the scene's terrain (Terrain3D data_directory
## res://terrain/<map>), or null if none has been rendered.
static func find_for_scene(scene_root: Node) -> MapImageData:
	if scene_root == null:
		return null
	var terrains: Array[Node] = scene_root.find_children("*", "Terrain3D", true, false)
	if terrains.is_empty():
		return null
	var map_name: String = String(terrains[0].get("data_directory")).get_file()
	var path: String = "res://data/maps/%s_map.tres" % map_name
	if not ResourceLoader.exists(path):
		return null
	return load(path) as MapImageData
