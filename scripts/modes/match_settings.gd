class_name MatchSettings
extends RefCounted
## Match options picked in the main menu (kept in user://settings.cfg).

const SETTINGS_PATH: String = "user://settings.cfg"
const MAX_TEAM_SIZE: int = 32

## Tanks per team in King of the Hill, players included (bots fill the rest; offline and
## when hosting with bots); 0 = as the map places them.
static var team_size: int = 0
static var _loaded: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		team_size = clampi(int(cfg.get_value("match", "team_size", 0)), 0, MAX_TEAM_SIZE)


static func set_team_size(n: int) -> void:
	_loaded = true
	team_size = clampi(n, 0, MAX_TEAM_SIZE)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("match", "team_size", team_size)
	cfg.save(SETTINGS_PATH)
