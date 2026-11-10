class_name PlaceNamesData
extends Resource
## Place names of a map (districts, villages, hamlets...) for PlaceBanner. Made by
## geodata/scripts/platser.py from OSM place=* and saved as data/maps/<map>_places.tres.

## One entry per place, in step.
@export var names: PackedStringArray = PackedStringArray()
## OSM place kind (suburb, neighbourhood, hamlet...).
@export var kinds: PackedStringArray = PackedStringArray()
## (x, z) in the world.
@export var positions: PackedVector2Array = PackedVector2Array()
## How far from its point one counts as being in the place (m), by kind.
@export var reach_m: PackedFloat32Array = PackedFloat32Array()


## The place at `p` (x, z): the one nearest relative to its reach, -1 when none reaches.
func place_at(p: Vector2) -> int:
	var best: int = -1
	var best_share: float = 1.0
	for i: int in mini(names.size(), mini(positions.size(), reach_m.size())):
		var share: float = p.distance_to(positions[i]) / maxf(reach_m[i], 1.0)
		if share < best_share:
			best_share = share
			best = i
	return best


## The widest place other than `inside` that also reaches `p` (e.g. the suburb round a
## neighbourhood), -1 when none.
func around(p: Vector2, inside: int) -> int:
	var best: int = -1
	for i: int in mini(names.size(), mini(positions.size(), reach_m.size())):
		if i == inside or reach_m[i] <= reach_m[inside] or p.distance_to(positions[i]) > reach_m[i]:
			continue
		if best < 0 or reach_m[i] < reach_m[best]:
			best = i
	return best


## The place names for the scene's terrain (Terrain3D data_directory res://terrain/<map>),
## or null if none were made.
static func find_for_scene(scene_root: Node) -> PlaceNamesData:
	if scene_root == null:
		return null
	var terrains: Array[Node] = scene_root.find_children("*", "Terrain3D", true, false)
	if terrains.is_empty():
		return null
	var map_name: String = String(terrains[0].get("data_directory")).get_file()
	var path: String = "res://data/maps/%s_places.tres" % map_name
	if not ResourceLoader.exists(path):
		return null
	return load(path) as PlaceNamesData
