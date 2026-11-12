extends SceneTree
## Imports a real map from the geodata pipeline: terrain into Terrain3D, and the
## object glb, trees and tree models into assets/maps/<name>/.
##   godot --headless --path . --script res://tools/import_geodata_map.gd -- <name> <out dir> [--textures]
##   e.g. -- vikbolandet res://geodata/out   (these are the defaults)
## Reads <out dir>/ (heightmap.r16, heightmap_info.json, landcover_color.png, *_objekt.glb,
## trees.bin, trees_info.json, trad_*.glb) and writes terrain/<name>/. Rerun after
## rebuilding the geodata; it overwrites any sculpting or painting in terrain/<name>/.
## material.tres and assets.tres are only made when missing, so edits made to them in the
## editor (textures, meshes, shader settings) survive a rebuild; delete them to start over.
## Textures (tools/terrain_textures.json): with <out dir>/terrain_control.r32 from
## tools/terrain_control.py each land cover class gets its texture, else the old auto shader
## (grass on flats, rock on slopes). --textures only puts the textures on an imported map:
## the texture list in assets.tres, the material settings, and the control and colour maps
## (heights, objects and trees are left alone).
##
## Coordinates follow geodata/CLAUDE.md: origin at the heightmap's NW corner, x east,
## z south, y metres above sea level, pixel (column j, row i) at (j * RES, i * RES).

## Copied as-is from the out dir to assets/maps/<name>/ (the object glb is renamed).
const COPY_FILES: Array[String] = ["trees.bin", "trees_info.json", "buskar.bin", "buskar_info.json"]
## Terrain3D region size in pixels; with 2 m spacing a region covers 2048 m.
const REGION_SIZE: int = 1024
const TEXTURES_CONFIG: String = "res://tools/terrain_textures.json"
const CONTROL_FILE: String = "terrain_control.r32"

var _terrain: Terrain3D
var _name: String = "vikbolandet"
var _geo_out: String = "res://geodata/out"
var _directory: String
var _images: Array[Image] = []
var _frames: int = 0
var _textures_only: bool = false
## tools/terrain_textures.json
var _config: Dictionary = {}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1:
		_name = args[0]
	if args.size() >= 2:
		_geo_out = args[1]
	_textures_only = args.has("--textures")
	_config = JSON.parse_string(FileAccess.get_file_as_string(TEXTURES_CONFIG))
	_directory = "res://terrain/" + _name
	print("map %s from %s%s" % [_name, _geo_out, " (textures only)" if _textures_only else ""])
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_geo_out + "/heightmap_info.json"))
	var size := Vector2i(int(info.width_px), int(info.height_px))
	var spacing: float = float(info.resolution_m)
	var height_range := Vector2(float(info.height_min_m), float(info.height_max_m))

	if _textures_only:
		_start_textures_only(size)
		return
	var height_image: Image = Terrain3DUtil.load_image(
			ProjectSettings.globalize_path(_geo_out + "/heightmap.r16"),
			ResourceLoader.CACHE_MODE_IGNORE, height_range, size)
	print("height image %s, range %s" % [str(height_image.get_size()), str(Terrain3DUtil.get_min_max(height_image))])

	height_image = _pad_to_regions(height_image)
	_images = [height_image, _control_image(size), _color_image()]

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	_clear_old_regions()
	_save_if_missing(_make_material(), _directory + "/material.tres")
	_save_if_missing(_make_assets(), _directory + "/assets.tres")
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
	if _textures_only:
		_finish_textures_only()
		return true
	_terrain.change_region_size(REGION_SIZE)
	_terrain.data.import_images(_images, Vector3.ZERO, 0.0, 1.0)
	_terrain.data.save_directory(_directory)
	print("%s: %d regions, height range %s" % [_name, _terrain.data.get_region_count(),
			str(_terrain.data.get_height_range())])
	_save_ground_cover()
	return true


## Ground vegetation classes (geodata markvegetation.bin/.json, 2 m cells as the heightmap)
## -> data/maps/<map>_groundcover.res (GroundCoverData).
func _save_ground_cover() -> void:
	var bin: String = _geo_out + "/markvegetation.bin"
	var info_path: String = _geo_out + "/markvegetation.json"
	if not FileAccess.file_exists(bin) or not FileAccess.file_exists(info_path):
		print("%s: no markvegetation.bin, no ground cover" % _name)
		return
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(info_path))
	var gc := GroundCoverData.new()
	gc.width = int(info["width"])
	gc.height = int(info["height"])
	gc.cell_m = 2.0
	gc.classes = FileAccess.get_file_as_bytes(bin)
	# lakes for fording (vatten.bin/.json): id per cell and the levels
	if FileAccess.file_exists(_geo_out + "/vatten.bin") and FileAccess.file_exists(_geo_out + "/vatten.json"):
		var w: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_geo_out + "/vatten.json"))
		gc.water_ids = FileAccess.get_file_as_bytes(_geo_out + "/vatten.bin")
		gc.water_levels = PackedFloat32Array(w["nivaer"])
	var path: String = "res://data/maps/%s_groundcover.res" % _name
	_save_keeping_uid(gc, path)
	print("%s: ground cover %d x %d -> %s" % [_name, gc.width, gc.height, path])


## The control map: textures per land cover class (terrain_control.r32), or without
## one every pixel on the auto shader (grass on flats, rock on slopes). Padded to regions.
func _control_image(size: Vector2i) -> Image:
	var path: String = _geo_out + "/" + CONTROL_FILE
	var image: Image
	if FileAccess.file_exists(path):
		# Raw uint32 in Terrain3D's control format: the same bytes as a FORMAT_RF image.
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		assert(bytes.size() == size.x * size.y * 4, "%s is not the heightmap's size" % path)
		image = Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, bytes)
		print("control map from %s" % path)
	else:
		var auto: float = Terrain3DUtil.as_float(Terrain3DUtil.enc_auto(true))
		image = Terrain3DUtil.get_filled_image(size, Color(auto, 0.0, 0.0, 1.0), false, Image.FORMAT_RF)
		print("no %s: auto shader everywhere" % CONTROL_FILE)
	return _pad_to_regions(image)


func _color_image() -> Image:
	var ortho: String = _ortho_tint_path()
	if ortho != "":
		print("  colour map from the orthophoto: %s" % ortho)
		return _pad_to_regions(_ortho_image(ortho))
	return _pad_to_regions(_tint_image(ProjectSettings.globalize_path(_geo_out + "/landcover_color.png")))


## The orthophoto tint (geodata/scripts/ortofoto_tint.py) when the config wants it and the map has one;
## only with textures (it is encoded round neutral_linear and the textures are brightened to match).
func _ortho_tint_path() -> String:
	var ortho: Dictionary = _config.get("ortho_tint", {})
	if not _textures_only or not bool(ortho.get("enabled", false)):
		return ""
	var path: String = ProjectSettings.globalize_path(_geo_out + "/" + String(ortho.get("file", "")))
	return path if FileAccess.file_exists(path) else ""


## How much the textures are brightened so the orthophoto tint's neutral comes out as 1. Terrain3D
## takes albedo_color as sRGB (it is linearised for the shader), so the linear factor is encoded.
func _albedo_boost() -> float:
	if _ortho_tint_path() == "":
		return 1.0
	return Color(1.0 / float(_config["ortho_tint"].get("neutral_linear", 1.0)), 0.0, 0.0).linear_to_srgb().r


func _ortho_image(path: String) -> Image:
	var image := Image.load_from_file(path)
	image.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = image.get_data()
	for k: int in data.size() / 4:
		data[k * 4 + 3] = 128  # alpha = roughness modifier, 0.5 is neutral
	return Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)


# --- Textures only (--textures) -----------------------------------------------------

func _start_textures_only(size: Vector2i) -> void:
	_images = [null, _control_image(size), _color_image()]
	var assets: Terrain3DAssets = load(_directory + "/assets.tres")
	if assets == null:
		# Unreadable (e.g. a texture it lists is gone): a fresh list, without its meshes.
		print("  %s/assets.tres unreadable, making a new one" % _directory)
		assets = Terrain3DAssets.new()
	_set_texture_list(assets)
	_save_keeping_uid(assets, _directory + "/assets.tres")
	var material: Terrain3DMaterial = load(_directory + "/material.tres")
	_set_material(material)
	_terrain = Terrain3D.new()
	_terrain.material = material
	_terrain.assets = assets
	_terrain.vertex_spacing = float(JSON.parse_string(FileAccess.get_file_as_string(
			_geo_out + "/heightmap_info.json")).resolution_m)
	_terrain.data_directory = _directory
	root.add_child(_terrain)


## Each region gets its piece of the control and colour maps; heights stay as they are.
func _finish_textures_only() -> void:
	var data: Terrain3DData = _terrain.data
	var region_px: int = _terrain.region_size
	var control: Image = _images[1]
	var color: Image = _images[2]
	for location: Vector2i in data.get_region_locations():
		var rect := Rect2i(location * region_px, Vector2i(region_px, region_px))
		if location.x < 0 or location.y < 0 or rect.end.x > control.get_width() \
				or rect.end.y > control.get_height():
			print("  region %s outside the land cover, skipped" % str(location))
			continue
		var region: Terrain3DRegion = data.get_region(location)
		region.set_control_map(control.get_region(rect))
		region.set_color_map(color.get_region(rect))
		data.set_region_modified(location, true)
	data.update_maps(Terrain3DRegion.TYPE_MAX, true, false)
	data.save_directory(_directory)
	# Shader parameters only stick once the terrain's shader is built (now).
	_set_material(_terrain.material)
	_save_keeping_uid(_terrain.material, _directory + "/material.tres")
	print("%s: textures on %d regions" % [_name, data.get_region_count()])


## Scenes refer to these files by UID; a plain save from a script drops it.
func _save_keeping_uid(resource: Resource, path: String) -> void:
	var uid: int = ResourceLoader.get_resource_uid(path)
	ResourceSaver.save(resource, path)
	if uid != ResourceUID.INVALID_ID:
		ResourceSaver.set_uid(path, uid)


func _set_texture_list(assets: Terrain3DAssets) -> void:
	var textures: Array = _config["textures"]
	for i: int in textures.size():
		var entry: Dictionary = textures[i]
		var texture := _texture(String(entry["name"]), String(entry["file"]))
		texture.uv_scale = float(entry.get("uv_scale", 0.1))
		texture.detiling_rotation = float(entry.get("detiling_rotation", 0.0))
		texture.detiling_shift = float(entry.get("detiling_shift", 0.0))
		var tint: Array = entry.get("albedo_color", [1.0, 1.0, 1.0])
		var boost: float = _albedo_boost()
		texture.albedo_color = Color(float(tint[0]) * boost, float(tint[1]) * boost, float(tint[2]) * boost)
		assets.set_texture_asset(i, texture)
	# Drop textures beyond the list (an older, longer list).
	for i: int in range(assets.get_texture_count() - 1, textures.size() - 1, -1):
		assets.set_texture_asset(i, null)


func _set_material(material: Terrain3DMaterial) -> void:
	material.auto_shader_enabled = false
	material.macro_variation_enabled = bool(_config.get("macro_variation", false))
	material.set_shader_param(&"blend_sharpness", float(_config.get("blend_sharpness", 0.5)))
	for key: String in ["macro_variation1", "macro_variation2"]:
		var c: Array = _config.get(key, [1.0, 1.0, 1.0])
		material.set_shader_param(StringName(key), Color(float(c[0]), float(c[1]), float(c[2])))


## Turns the land-cover map into a gentle albedo tint around white, so the textures still
## show but areas read a little differently (tint_strength, tint_gain in the config).
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
	var strength: float = float(_config.get("tint_strength", 0.7))
	var gain: float = float(_config.get("tint_gain", 1.9))
	var dst := PackedByteArray()
	dst.resize(w * h * 4)
	for k: int in w * h:
		for c: int in 3:
			var v: float = minf(src[k * 3 + c] / 255.0 * gain, 1.0)
			dst[k * 4 + c] = int(lerpf(1.0, v, strength) * 255.0)
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
		elif file.ends_with("_markvegetation.glb"):
			pairs[file] = "%s_markvegetation.glb" % _name   # far ground vegetation (GroundCoverCanopy)
		elif file.begins_with("veg_") and file.ends_with(".glb"):
			pairs[file] = file   # tree and bush models (vegetation.json)
	for file: String in COPY_FILES:
		pairs[file] = file
	# Only a changed object glb is reimported (and extracts its images again): an unchanged one
	# keeps its images, else they would be gone for good.
	var objekt_src: String = ""
	for file: String in pairs:
		if pairs[file] == "%s_objekt.glb" % _name:
			objekt_src = _geo_out + "/" + file
	var objekt_dst: String = target_dir + "/%s_objekt.glb" % _name
	if objekt_src.is_empty() or not FileAccess.file_exists(objekt_dst) \
			or FileAccess.get_md5(objekt_src) != FileAccess.get_md5(objekt_dst):
		_remove_extracted_images(target_dir)
	for file: String in pairs:
		var source: String = ProjectSettings.globalize_path(_geo_out + "/" + file)
		if not FileAccess.file_exists(source):
			print("  missing %s, skipped" % file)
			continue
		var err: int = DirAccess.copy_absolute(source, ProjectSettings.globalize_path(target_dir + "/" + pairs[file]))
		print("  copy %s -> %s: %s" % [file, pairs[file], error_string(err)])


## Godot extracts the object glb's images as <name>_objekt_<n>.png and keeps each file's
## import settings: after a rebuild image n may be something else (a roof texture where a
## normal map was, which then turns yellow). The old ones go, so they are made afresh.
func _remove_extracted_images(target_dir: String) -> void:
	var prefix: String = "%s_objekt_" % _name
	for file: String in DirAccess.get_files_at(target_dir):
		if file.begins_with(prefix) and (file.ends_with(".png") or file.ends_with(".png.import")):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(target_dir + "/" + file))
			print("  removed old extracted image %s" % file)


func _make_material() -> Terrain3DMaterial:
	var material := Terrain3DMaterial.new()
	material.world_background = 0  # None: no fake terrain outside the regions
	if FileAccess.file_exists(_geo_out + "/" + CONTROL_FILE):
		_set_material(material)
	else:
		material.auto_shader_enabled = true
	return material


## The texture list from the config; without a control map the auto shader uses
## texture 0 (rock) on slopes and 1 (meadow) on flat ground.
func _make_assets() -> Terrain3DAssets:
	var assets := Terrain3DAssets.new()
	_set_texture_list(assets)
	return assets


func _texture(asset_name: String, file: String) -> Terrain3DTextureAsset:
	var texture := Terrain3DTextureAsset.new()
	texture.set_asset_name(asset_name)
	texture.set_albedo_texture(load("res://assets/terrain/%s_alb_ht.png" % file))
	texture.set_normal_texture(load("res://assets/terrain/%s_nrm_rgh.png" % file))
	return texture


## Saves a resource only if the file doesn't exist yet: an existing one may hold editor
## changes (and its UID, which scenes refer to), so it is kept as it is.
func _save_if_missing(resource: Resource, path: String) -> void:
	if FileAccess.file_exists(path):
		print("  keeping %s" % path)
		return
	ResourceSaver.save(resource, path)
