extends SceneTree
## One-off generator for the starter landscape of scenes/maps/hills.tscn.
## Run once: godot --headless --path . --script res://tools/generate_hills.gd
## Writes terrain/hills/ (Terrain3D region data, material, assets). After that the
## terrain belongs to the editor: sculpt and paint freely, don't rerun this unless
## you want to throw your edits away.
##
## Layout (x east, z south, metres, map centred on the origin):
## - start area around (0, 700), flattened
## - steep test knoll at (160, 600), ~28° flanks, for climb testing
## - long east-west ridge winding around z = -100, the main hull-down line
## - shallow valley north of it around z = -450
## - rolling ground everywhere, rising towards the map edge

const SIZE: int = 2048
const ORIGIN: Vector3 = Vector3(-1024.0, 0.0, -1024.0)
const DIRECTORY: String = "res://terrain/hills"
const START: Vector2 = Vector2(0.0, 700.0)
const KNOLL: Vector2 = Vector2(160.0, 600.0)

var _rolling := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _terrain: Terrain3D
var _height_image: Image
var _control_image: Image
var _frames: int = 0


func _initialize() -> void:
	_rolling.seed = 7
	_rolling.frequency = 1.0 / 320.0
	_rolling.fractal_octaves = 3
	_detail.seed = 11
	_detail.frequency = 1.0 / 55.0
	_detail.fractal_octaves = 2

	var heights := PackedFloat32Array()
	heights.resize(SIZE * SIZE)
	var min_h: float = INF
	for j: int in SIZE:
		for i: int in SIZE:
			var h: float = _height(ORIGIN.x + i, ORIGIN.z + j)
			heights[j * SIZE + i] = h
			min_h = minf(min_h, h)
	for k: int in heights.size():
		heights[k] -= min_h  # lowest point at 0 m
	var height_image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF,
			heights.to_byte_array())
	# Every pixel on auto shader: grass (overlay) on flats, cliff (base) on slopes.
	var auto: float = Terrain3DUtil.as_float(Terrain3DUtil.enc_auto(true))
	var control_image := Terrain3DUtil.get_filled_image(Vector2i(SIZE, SIZE),
			Color(auto, 0.0, 0.0, 1.0), false, Image.FORMAT_RF)

	_height_image = height_image
	_control_image = control_image
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var material: Terrain3DMaterial = _make_material()
	var assets: Terrain3DAssets = _make_assets()
	ResourceSaver.save(material, DIRECTORY + "/material.tres")
	ResourceSaver.save(assets, DIRECTORY + "/assets.tres")
	_terrain = Terrain3D.new()
	_terrain.material = load(DIRECTORY + "/material.tres")
	_terrain.assets = load(DIRECTORY + "/assets.tres")
	_terrain.data_directory = DIRECTORY
	root.add_child(_terrain)


## Terrain3D sets up its data a frame after entering the tree.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_terrain.data.import_images([_height_image, _control_image, null], ORIGIN, 0.0, 1.0)
	_terrain.data.save_directory(DIRECTORY)
	print("hills: %d regions, height range %s" % [_terrain.data.get_region_count(),
			str(_terrain.data.get_height_range())])
	return true


func _height(x: float, z: float) -> float:
	var h: float = 9.0 * _rolling.get_noise_2d(x, z) + 1.5 * _detail.get_noise_2d(x, z)
	# Winding ridge.
	var ridge_z: float = -100.0 + 90.0 * sin(x / 380.0)
	h += 22.0 * exp(-pow((z - ridge_z) / 110.0, 2.0))
	# Valley beyond it.
	h -= 9.0 * exp(-pow((z + 450.0) / 140.0, 2.0))
	# Steep test knoll.
	h += 25.0 * exp(-Vector2(x, z).distance_squared_to(KNOLL) / (40.0 * 40.0))
	# Rim rising towards the edges.
	var edge: float = maxf(absf(x), absf(z))
	h += 18.0 * smoothstep(800.0, 1024.0, edge)
	# Flatten the start area towards a gentle base.
	var start_blend: float = smoothstep(150.0, 70.0, Vector2(x, z).distance_to(START))
	return lerpf(h, 2.0 * _rolling.get_noise_2d(x, z), start_blend)


func _make_material() -> Terrain3DMaterial:
	var material := Terrain3DMaterial.new()
	material.auto_shader_enabled = true
	material.world_background = 0  # None: no fake terrain outside the regions
	return material


func _make_assets() -> Terrain3DAssets:
	var assets := Terrain3DAssets.new()
	# Auto shader: base texture (0) shows on slopes, overlay (1) on flat ground.
	assets.set_texture_asset(0, _texture("cliff", "rock023"))
	assets.set_texture_asset(1, _texture("grass", "ground037"))
	return assets


func _texture(asset_name: String, file: String) -> Terrain3DTextureAsset:
	var texture := Terrain3DTextureAsset.new()
	texture.set_asset_name(asset_name)
	texture.set_albedo_texture(load("res://assets/terrain/%s_alb_ht.png" % file))
	texture.set_normal_texture(load("res://assets/terrain/%s_nrm_rgh.png" % file))
	return texture
