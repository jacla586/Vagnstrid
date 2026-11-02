extends SceneTree
## Imports a real map from the geodata pipeline: terrain into Terrain3D, and the
## object glb, trees and tree models into assets/maps/<name>/.
##   godot --headless --path . --script res://tools/import_geodata_map.gd -- <name> <out dir>
##   e.g. -- vikbolandet res://geodata/out   (these are the defaults)
## Reads <out dir>/ (heightmap.r16, heightmap_info.json, landcover_color.png, *_objekt.glb,
## trees.bin, trees_info.json, trad_*.glb) and writes terrain/<name>/. Rerun after
## rebuilding the geodata; it overwrites any sculpting or painting in terrain/<name>/.
##
## Coordinates follow geodata/CLAUDE.md: origin at the heightmap's NW corner, x east,
## z south, y metres above sea level, pixel (column j, row i) at (j * RES, i * RES).

## Copied as-is from the out dir to assets/maps/<name>/ (the object glb is renamed).
const COPY_FILES: Array[String] = ["trees.bin", "trees_info.json", "trad_gran.glb", "trad_tall.glb", "trad_lov.glb"]
## Terrain3D region size in pixels; with 2 m spacing a region covers 2048 m.
const REGION_SIZE: int = 1024
## How strongly the land-cover colour tints the terrain textures (0 = none).
const TINT_STRENGTH: float = 0.7
## Land-cover colours are dark map colours; scale them so mid tones sit near white.
const TINT_GAIN: float = 1.9

var _terrain: Terrain3D
var _name: String = "vikbolandet"
var _geo_out: String = "res://geodata/out"
var _directory: String
var _images: Array[Image] = []
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1:
		_name = args[0]
	if args.size() >= 2:
		_geo_out = args[1]
	_directory = "res://terrain/" + _name
	print("map %s from %s" % [_name, _geo_out])
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_geo_out + "/heightmap_info.json"))
	var size := Vector2i(int(info.width_px), int(info.height_px))
	var spacing: float = float(info.resolution_m)
	var height_range := Vector2(float(info.height_min_m), float(info.height_max_m))

	var height_image: Image = Terrain3DUtil.load_image(
			ProjectSettings.globalize_path(_geo_out + "/heightmap.r16"),
			ResourceLoader.CACHE_MODE_IGNORE, height_range, size)
	print("height image %s, range %s" % [str(height_image.get_size()), str(Terrain3DUtil.get_min_max(height_image))])

	# Every pixel on auto shader: grass on flats, rock on slopes.
	var auto: float = Terrain3DUtil.as_float(Terrain3DUtil.enc_auto(true))
	height_image = _pad_to_regions(height_image)
	var control_image := Terrain3DUtil.get_filled_image(height_image.get_size(), Color(auto, 0.0, 0.0, 1.0), false, Image.FORMAT_RF)
	var color_image := _tint_image(ProjectSettings.globalize_path(_geo_out + "/landcover_color.png"))
	color_image = _pad_to_regions(color_image)
	_images = [height_image, control_image, color_image]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	_clear_old_regions()
	ResourceSaver.save(_make_material(), _directory + "/material.tres")
	ResourceSaver.save(_make_assets(), _directory + "/assets.tres")
	_copy_files()

	_terrain = Terrain3D.new()
	_terrain.material = load(_directory + "/material.tres")
	_terrain.assets = load(_directory + "/assets.tres")
	_terrain.vertex_spacing = spacing
	_terrain.data_directory = _directory
	root.add_child(_terrain)


## Terrain3D sets up its data a frame after entering the tree.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false
	_terrain.change_region_size(REGION_SIZE)
	_terrain.data.import_images(_images, Vector3.ZERO, 0.0, 1.0)
	_terrain.data.save_directory(_directory)
	print("%s: %d regions, height range %s" % [_name, _terrain.data.get_region_count(),
			str(_terrain.data.get_height_range())])
	return true


## Turns the land-cover map into a gentle albedo tint around white, so the grass and
## rock textures still show but fields, forest and roads read differently.
## Grows an image to whole Terrain3D regions by repeating its last column and row.
## Otherwise the unused part of the edge regions is height 0: a cliff on inland maps.
func _pad_to_regions(source: Image) -> Image:
	var w: int = source.get_width()
	var h: int = source.get_height()
	var padded_w: int = ceili(float(w) / REGION_SIZE) * REGION_SIZE
	var padded_h: int = ceili(float(h) / REGION_SIZE) * REGION_SIZE
	var padded := Image.create_empty(padded_w, padded_h, false, source.get_format())
	padded.blit_rect(source, Rect2i(0, 0, w, h), Vector2i.ZERO)
	var column: Image = padded.get_region(Rect2i(w - 1, 0, 1, h))
	for x: int in range(w, padded_w):
		padded.blit_rect(column, Rect2i(0, 0, 1, h), Vector2i(x, 0))
	var row: Image = padded.get_region(Rect2i(0, h - 1, padded_w, 1))
	for y: int in range(h, padded_h):
		padded.blit_rect(row, Rect2i(0, 0, padded_w, 1), Vector2i(0, y))
	return padded


func _tint_image(path: String) -> Image:
	var source := Image.load_from_file(path)
	source.convert(Image.FORMAT_RGB8)
	var w: int = source.get_width()
	var h: int = source.get_height()
	var src: PackedByteArray = source.get_data()
	var dst := PackedByteArray()
	dst.resize(w * h * 4)
	for k: int in w * h:
		for c: int in 3:
			var v: float = minf(src[k * 3 + c] / 255.0 * TINT_GAIN, 1.0)
			dst[k * 4 + c] = int(lerpf(1.0, v, TINT_STRENGTH) * 255.0)
		dst[k * 4 + 3] = 128  # alpha = roughness modifier, 0.5 is neutral
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, dst)


## Region files from an earlier import with other bounds would otherwise linger.
func _clear_old_regions() -> void:
	var dir := DirAccess.open(_directory)
	for file: String in dir.get_files():
		if file.begins_with("terrain3d") and file.ends_with(".res"):
			dir.remove(file)


func _copy_files() -> void:
	var target_dir: String = "res://assets/maps/" + _name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_dir))
	var pairs: Dictionary = {}
	for file: String in DirAccess.get_files_at(_geo_out):
		if file.ends_with("_objekt.glb"):
			pairs[file] = "%s_objekt.glb" % _name
	for file: String in COPY_FILES:
		pairs[file] = file
	for file: String in pairs:
		var source: String = ProjectSettings.globalize_path(_geo_out + "/" + file)
		if not FileAccess.file_exists(source):
			print("  missing %s, skipped" % file)
			continue
		var err: int = DirAccess.copy_absolute(source, ProjectSettings.globalize_path(target_dir + "/" + pairs[file]))
		print("  copy %s -> %s: %s" % [file, pairs[file], error_string(err)])


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
