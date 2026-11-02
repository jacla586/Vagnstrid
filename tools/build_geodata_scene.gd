extends SceneTree
## One-off builder for scenes/maps/<name>.tscn from a real map imported with
## tools/import_geodata_map.gd: Terrain3D node, environment, the object glb (roads,
## buildings, water) with building collision, the laser trees, and the player start
## in the middle of a road.
##   godot --headless --path . --script res://tools/build_geodata_scene.gd -- <name> <out dir> [road ref]
##   e.g. -- vikbolandet res://geodata/out "E 851"
## Without a road ref (or if it isn't found) the longest road is used.
## After that the scene belongs to the editor; rerunning overwrites your edits.

const TREE_TYPES: Array[String] = ["gran", "tall", "lov"]

var _name: String = "vikbolandet"
var _geo_out: String = "res://geodata/out"
var _road_ref: String = ""
var _root: Node3D
var _terrain: Terrain3D
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1:
		_name = args[0]
	if args.size() >= 2:
		_geo_out = args[1]
	if args.size() >= 3:
		_road_ref = args[2]
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_geo_out + "/heightmap_info.json"))
	var terrain_dir: String = "res://terrain/" + _name
	_root = Node3D.new()
	_root.name = _name.to_pascal_case()
	root.add_child(_root)
	_terrain = Terrain3D.new()
	_terrain.name = "Terrain3D"
	_terrain.material = load(terrain_dir + "/material.tres")
	_terrain.assets = load(terrain_dir + "/assets.tres")
	_terrain.vertex_spacing = float(info.resolution_m)
	_terrain.data_directory = terrain_dir
	_terrain.collision_mode = 3  # Full / Game: shells and nests act far from the camera
	_add(_root, _terrain)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false  # Terrain3D loads its data a frame after entering the tree
	_build()
	var out: String = "res://scenes/maps/%s.tscn" % _name
	var packed := PackedScene.new()
	var err: int = packed.pack(_root)
	print("pack: %d, save %s: %d" % [err, out, ResourceSaver.save(packed, out)])
	return true


func _build() -> void:
	var assets_dir: String = "res://assets/maps/" + _name
	print("terrain regions: %d, region size %d" % [_terrain.data.get_region_count(), _terrain.get_region_size()])
	_add_environment()

	var objects: Node3D = load("%s/%s_objekt.glb" % [assets_dir, _name]).instantiate()
	objects.name = "Objects"
	objects.set_script(load("res://scripts/world/mesh_collision.gd"))
	_add(_root, objects)

	if FileAccess.file_exists(assets_dir + "/trees.bin"):
		var trees := TreeField.new()
		trees.name = "Trees"
		trees.info_path = assets_dir + "/trees_info.json"
		trees.data_path = assets_dir + "/trees.bin"
		for type: String in TREE_TYPES:
			trees.tree_scenes.append(load("%s/trad_%s.glb" % [assets_dir, type]))
			trees.tree_data.append(load("res://data/world/field_tree_%s.tres" % type))
		# The chunks it creates in _ready() have no owner, so they are not saved.
		_add(_root, trees)

	var rig: Node3D = load("res://scenes/player/player_rig.tscn").instantiate()
	rig.name = "PlayerRig"
	_add(_root, rig)
	var start: Array = _road_start()
	var start_point: Vector3 = start[0]
	var forward: Vector3 = start[1]
	rig.global_position = _ground(start_point.x, start_point.z) + Vector3(0.0, 0.5, 0.0)
	# Tank forward is -Z.
	rig.rotation.y = atan2(-forward.x, -forward.z)
	print("player start %s heading %.0f°" % [str(rig.global_position), rad_to_deg(rig.rotation.y)])


## Midpoint and direction of the longest drivable road with the wanted ref, or of the
## longest drivable road at all.
func _road_start() -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_geo_out + "/roads.json"))
	var best: Array = []
	var best_any: Array = []
	for road: Dictionary in data.roads:
		if road.highway in ["path", "footway", "cycleway", "steps"]:
			continue
		if road.points.size() > best_any.size():
			best_any = road.points
		if road.ref == _road_ref and road.points.size() > best.size():
			best = road.points
	if best.is_empty():
		best = best_any
	var mid: int = best.size() / 2
	var a: Vector3 = _point(best[mid])
	var b: Vector3 = _point(best[mini(mid + 1, best.size() - 1)])
	return [a, (b - a).normalized()]


func _point(p: Array) -> Vector3:
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _add_environment() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Distance haze: spotting gets harder with range. Tune in the editor.
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.68, 0.73, 0.8)
	environment.fog_density = 0.0004
	environment.fog_aerial_perspective = 0.4
	environment.fog_sky_affect = 0.25
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	_add(_root, world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	_add(_root, sun)


func _add(parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = _root


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, _terrain.data.get_height(Vector3(x, 0.0, z)), z)
