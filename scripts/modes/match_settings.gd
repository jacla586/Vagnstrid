class_name MatchSettings
extends RefCounted
## Match options picked in the main menu (kept in user://settings.cfg).

const SETTINGS_PATH: String = "user://settings.cfg"
const MAX_TEAM_SIZE: int = 32

## Tanks per team in King of the Hill, players included (bots fill the rest; offline and
## when hosting with bots); 0 = as the map places them.
static var team_size: int = 0
## Weather preset (file name in data/weather/, e.g. "fog") or "random" (Weather).
static var weather: String = "random"
## Bot tanks on the players' side in free fight (bot hunt).
static var free_allies: int = 0
const MAX_FREE_ALLIES: int = 8
static var _loaded: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		team_size = clampi(int(cfg.get_value("match", "team_size", 0)), 0, MAX_TEAM_SIZE)
		weather = str(cfg.get_value("match", "weather", "random"))
		free_allies = clampi(int(cfg.get_value("match", "free_allies", 0)), 0, MAX_FREE_ALLIES)


static func set_team_size(n: int) -> void:
	load_settings()
	team_size = clampi(n, 0, MAX_TEAM_SIZE)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("match", "team_size", team_size)
	cfg.save(SETTINGS_PATH)


static func set_weather(id: String) -> void:
	load_settings()
	weather = id
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("match", "weather", weather)
	cfg.save(SETTINGS_PATH)


static func set_free_allies(n: int) -> void:
	load_settings()
	free_allies = clampi(n, 0, MAX_FREE_ALLIES)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("match", "free_allies", free_allies)
	cfg.save(SETTINGS_PATH)
