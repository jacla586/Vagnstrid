class_name TankConfigs
extends RefCounted
## Stores tank configs: presets (res://data/configs/, read only), the player's own
## (user://configs/) and which one the player has chosen (user://garage.cfg).

const PRESET_DIR: String = "res://data/configs/"
const SAVE_DIR: String = "user://configs/"
const SETTINGS_PATH: String = "user://garage.cfg"
## Driven when the player hasn't chosen a tank (or the chosen one is gone).
const DEFAULT_PRESET: String = "res://data/configs/2_t34.tres"

static var _selected: TankConfig
static var _selected_loaded: bool = false


static func presets() -> Array[TankConfig]:
	return _load_dir(PRESET_DIR)


static func saved() -> Array[TankConfig]:
	return _load_dir(SAVE_DIR)


## The player's own configs first, then the presets.
static func all() -> Array[TankConfig]:
	var out: Array[TankConfig] = saved()
	out.append_array(presets())
	return out


static func is_preset(cfg: TankConfig) -> bool:
	return cfg != null and cfg.resource_path.begins_with(PRESET_DIR)


## Saves a copy of `cfg` under its name in user://configs/ and returns the saved one.
static func save(cfg: TankConfig) -> TankConfig:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var copy: TankConfig = cfg.duplicate()
	var file: String = cfg.display_name.strip_edges().to_lower().validate_filename().replace(" ", "_")
	if file == "":
		file = "tank"
	var path: String = SAVE_DIR + file + ".tres"
	var err: Error = ResourceSaver.save(copy, path)
	if err != OK:
		push_warning("TankConfigs: could not save %s (%s)" % [path, error_string(err)])
		return null
	copy.take_over_path(path)
	return copy


static func remove(cfg: TankConfig) -> void:
	if cfg == null or not cfg.resource_path.begins_with(SAVE_DIR):
		return
	DirAccess.remove_absolute(cfg.resource_path)
	if _selected != null and _selected.resource_path == cfg.resource_path:
		select(null)


## The config the player drives (DEFAULT_PRESET unless one is chosen).
static func get_selected() -> TankConfig:
	if not _selected_loaded:
		_selected_loaded = true
		var settings := ConfigFile.new()
		var path: String = ""
		if settings.load(SETTINGS_PATH) == OK:
			path = settings.get_value("garage", "selected", "")
		if path == "" or not ResourceLoader.exists(path):
			path = DEFAULT_PRESET
		_selected = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as TankConfig
	return _selected


static func select(cfg: TankConfig) -> void:
	_selected = cfg
	_selected_loaded = true
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("garage", "selected", cfg.resource_path if cfg != null else "")
	settings.save(SETTINGS_PATH)
	if cfg == null:
		_selected_loaded = false   # back to the default preset


static func _load_dir(dir: String) -> Array[TankConfig]:
	var out: Array[TankConfig] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files: PackedStringArray = d.get_files()
	files.sort()
	for f: String in files:
		var name_: String = f.trim_suffix(".remap")
		if not name_.ends_with(".tres"):
			continue
		var cfg := ResourceLoader.load(dir + name_, "", ResourceLoader.CACHE_MODE_REPLACE) as TankConfig
		if cfg != null and TankBuilder.build(cfg) != null:
			out.append(cfg)
	return out
