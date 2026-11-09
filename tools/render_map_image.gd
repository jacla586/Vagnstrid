extends SceneTree
## Renders a map from straight above (orthographic, like an orthophoto) into a
## picture for the minimap and the big map. Tanks are hidden; fog is turned off.
##   godot --path . --disable-vsync --script res://tools/render_map_image.gd -- <map> [metres per pixel]
##   e.g. -- vidingsjo
## Needs a real window (not --headless: the dummy renderer draws nothing).
## Reads res://scenes/maps/<map>.tscn. The area is the geodata heightmap
## (heightmap_info.json, if found) or else all Terrain3D regions.
## Writes res://assets/maps/<map>/map_image.png and res://data/maps/<map>_map.tres.
## Rerun after the map changes (new houses, trees, terrain paint).

## Tile side in pixels; one camera shot per tile.
const TILE_PX: int = 512
## Frames to wait after moving the camera (terrain LOD, tree chunks, shadows).
const SETTLE_FRAMES: int = 6
## Shots per tile at most while waiting for the picture to stop changing.
const MAX_SHOTS: int = 8
## Mean byte difference between two shots below which the tile counts as settled.
const STEADY_DIFFERENCE: float = 0.5
## Camera height above the highest terrain point (m).
const CAMERA_CLEARANCE_M: float = 150.0
## Materials shinier than this count as water (geodata sea and lakes: 0.15).
const WATER_ROUGHNESS: float = 0.5
## Where heightmap_info.json may be, per map ("%s" = map name).
const INFO_PATHS: Array[String] = ["res://geodata/%s/out/heightmap_info.json",
		"res://geodata/out/heightmap_info.json"]
## Maps whose heightmap_info.json lies in geodata/out (the main geodata area).
const MAIN_GEODATA_MAP: String = "vikbolandet"

var _map: String = ""
var _metres_per_px: float = 2.0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <map> [metres per pixel]")
		quit(1)
		return
	_map = args[0]
	if args.size() >= 2:
		_metres_per_px = maxf(float(args[1]), 0.25)
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://scenes/maps/%s.tscn" % _map) as PackedScene
	if packed == null:
		push_error("no scene res://scenes/maps/%s.tscn" % _map)
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for i: int in 10:
		await process_frame

	var terrains: Array[Node] = scene.find_children("*", "Terrain3D", true, false)
	if terrains.is_empty():
		push_error("no Terrain3D in the map")
		quit(1)
		return
	var terrain: Node = terrains[0]
	var area: Rect2 = _find_area(terrain)
	var height_range: Vector2 = terrain.get("data").call("get_height_range")
	print("map %s: area %s, heights %s, %.2f m/px" % [_map, area, height_range, _metres_per_px])
	_prepare_scene(scene)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(TILE_PX, TILE_PX)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = TILE_PX * _metres_per_px
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 1.0
	camera.far = height_range.y - minf(height_range.x, 0.0) + CAMERA_CLEARANCE_M * 2.0
	# Looking straight down with north (-Z) at the top of the picture.
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	viewport.add_child(camera)
	camera.current = true
	terrain.call("set_camera", camera)

	var width_px: int = ceili(area.size.x / _metres_per_px)
	var height_px: int = ceili(area.size.y / _metres_per_px)
	var image := Image.create_empty(width_px, height_px, false, Image.FORMAT_RGB8)
	var tile_m: float = TILE_PX * _metres_per_px
	var tiles := Vector2i(ceili(width_px / float(TILE_PX)), ceili(height_px / float(TILE_PX)))
	for ty: int in tiles.y:
		for tx: int in tiles.x:
			var centre := area.position + Vector2(tx + 0.5, ty + 0.5) * tile_m
			camera.global_position = Vector3(centre.x, height_range.y + CAMERA_CLEARANCE_M, centre.y)
			var shot: Image = await _steady_shot(viewport)
			image.blit_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()),
					Vector2i(tx * TILE_PX, ty * TILE_PX))
		print("row %d/%d" % [ty + 1, tiles.y])

	var dir: String = "res://assets/maps/%s" % _map
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var png_path: String = dir + "/map_image.png"
	var err: Error = image.save_png(png_path)
	if err != OK:
		push_error("could not save %s: %s" % [png_path, error_string(err)])
		quit(1)
		return
	_write_import_settings(png_path)
	_write_data(png_path, Rect2(area.position, Vector2(width_px, height_px) * _metres_per_px))
	print("wrote %s (%d x %d)" % [png_path, width_px, height_px])
	quit()


## A shot of the tile once the picture has stopped changing: after a long camera
## jump (a new row) terrain LOD and tree chunks can lag several frames, and a shot
## taken too early showed part of the previous view.
func _steady_shot(viewport: SubViewport) -> Image:
	var last: Image = null
	for attempt: int in MAX_SHOTS:
		for i: int in SETTLE_FRAMES:
			await process_frame
		await RenderingServer.frame_post_draw
		var shot: Image = viewport.get_texture().get_image()
		shot.convert(Image.FORMAT_RGB8)
		if last != null and _difference(shot, last) < STEADY_DIFFERENCE:
			return shot
		last = shot
	push_warning("tile never settled; using the last shot")
	return last


## Mean absolute difference per byte between two same-sized RGB8 images (sampled).
func _difference(a: Image, b: Image) -> float:
	var da: PackedByteArray = a.get_data()
	var db: PackedByteArray = b.get_data()
	var total: int = 0
	var count: int = 0
	for i: int in range(0, mini(da.size(), db.size()), 97):
		total += absi(da[i] - db[i])
		count += 1
	return float(total) / maxi(count, 1)


## The heightmap's area from heightmap_info.json, or all Terrain3D regions.
func _find_area(terrain: Node) -> Rect2:
	for pattern: String in INFO_PATHS:
		var path: String = pattern % _map if pattern.contains("%s") else pattern
		if not pattern.contains("%s") and _map != MAIN_GEODATA_MAP:
			continue
		if FileAccess.file_exists(path):
			var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			var spacing: float = float(info.resolution_m)
			return Rect2(0.0, 0.0, float(info.width_px) * spacing, float(info.height_px) * spacing)
	var region_m: float = float(terrain.get("region_size")) * float(terrain.get("vertex_spacing"))
	var locations: Array = terrain.get("data").call("get_region_locations")
	var area := Rect2()
	for i: int in locations.size():
		var loc: Vector2i = locations[i]
		var r := Rect2(Vector2(loc) * region_m, Vector2(region_m, region_m))
		area = r if i == 0 else area.merge(r)
	return area


## Hides tanks and HUDs, turns off fog, stretches sun shadows over a whole tile and
## turns off reflections and sun glint, and draws water (shiny materials) unshaded:
## lit water came out a different shade in each tile and showed as bands on the sea.
func _prepare_scene(scene: Node) -> void:
	for node: Node in scene.find_children("*", "", true, false):
		if node is Tank or node is CanvasLayer:
			(node as Node).set("visible", false)
			node.process_mode = Node.PROCESS_MODE_DISABLED
		elif node is WorldEnvironment:
			var env: Environment = (node as WorldEnvironment).environment
			if env != null:
				env = env.duplicate() as Environment
				env.fog_enabled = false
				env.volumetric_fog_enabled = false
				env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
				(node as WorldEnvironment).environment = env
		elif node is MeshInstance3D:
			_flatten_water(node as MeshInstance3D)
		elif node is DirectionalLight3D:
			(node as DirectionalLight3D).light_specular = 0.0
			(node as DirectionalLight3D).directional_shadow_max_distance = \
					TILE_PX * _metres_per_px * 1.5


## First time only: import the picture with mipmaps, so it stays smooth when the
## big map shrinks it. Later runs keep whatever the import settings are.
## Water is the only shiny material (roughness below WATER_ROUGHNESS).
func _flatten_water(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	for i: int in mesh_instance.mesh.get_surface_count():
		var material := mesh_instance.get_active_material(i) as BaseMaterial3D
		if material == null or material.roughness >= WATER_ROUGHNESS:
			continue
		var flat := material.duplicate() as BaseMaterial3D
		flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh_instance.set_surface_override_material(i, flat)


func _write_import_settings(png_path: String) -> void:
	if FileAccess.file_exists(png_path + ".import"):
		return
	var file := FileAccess.open(png_path + ".import", FileAccess.WRITE)
	file.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n"
			+ "[params]\n\ncompress/mode=0\nmipmaps/generate=true\n")


func _write_data(png_path: String, world_rect: Rect2) -> void:
	var text: String = """[gd_resource type="Resource" script_class="MapImageData" format=3]

[ext_resource type="Script" path="res://scripts/data/map_image_data.gd" id="1_script"]
[ext_resource type="Texture2D" path="%s" id="2_texture"]

[resource]
script = ExtResource("1_script")
texture = ExtResource("2_texture")
world_rect = Rect2(%s, %s, %s, %s)
""" % [png_path, world_rect.position.x, world_rect.position.y, world_rect.size.x, world_rect.size.y]
	var file := FileAccess.open("res://data/maps/%s_map.tres" % _map, FileAccess.WRITE)
	file.store_string(text)
