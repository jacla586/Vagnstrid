class_name TankConfigs
extends RefCounted
## The tanks to choose from (presets, res://data/configs/, read only) and which one the
## player chose last (user://garage.cfg). Own builds (user://configs/) are no longer
## offered; a stored choice of one falls back to DEFAULT_PRESET.

const PRESET_DIR: String = "res://data/configs/"
const SETTINGS_PATH: String = "user://garage.cfg"
## Driven when the player hasn't chosen a tank (or the chosen one is gone).
const DEFAULT_PRESET: String = "res://data/configs/2_t34.tres"

static var _selected: TankConfig
static var _selected_loaded: bool = false


static func presets() -> Array[TankConfig]:
	return _load_dir(PRESET_DIR)


## Every tank a player can choose: the presets (own builds are gone).
static func all() -> Array[TankConfig]:
	return presets()


## The preset built from `key` (TankConfig.key()), or null: what a client asks for must
## be one of the presets.
static func preset_of_key(key: String) -> TankConfig:
	for cfg: TankConfig in presets():
		if cfg.key() == key:
			return cfg
	return null


## The config the player drives (DEFAULT_PRESET unless one is chosen).
static func get_selected() -> TankConfig:
	if not _selected_loaded:
		_selected_loaded = true
		var settings := ConfigFile.new()
		var path: String = ""
		if settings.load(SETTINGS_PATH) == OK:
			path = settings.get_value("garage", "selected", "")
		if path == "" or not path.begins_with(PRESET_DIR) or not ResourceLoader.exists(path):
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
