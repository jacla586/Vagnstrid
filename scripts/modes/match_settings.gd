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
## The bots' team commander (TeamCommander): 0 off, 1 normal, 2 sharp (COMMANDER_PATHS).
static var bot_commander: int = 1
const COMMANDER_NAMES: PackedStringArray = ["Off", "Normal", "Sharp"]
const COMMANDER_PATHS: PackedStringArray = ["", "res://data/bots/commander_normal.tres",
		"res://data/bots/commander_sharp.tres"]
## The player's name as last typed in the main menu ("" = none yet).
static var player_name: String = ""
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
		player_name = str(cfg.get_value("player", "name", ""))
		bot_commander = clampi(int(cfg.get_value("match", "bot_commander", 1)), 0,
				COMMANDER_PATHS.size() - 1)


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


static func set_bot_commander(level: int) -> void:
	load_settings()
	bot_commander = clampi(level, 0, COMMANDER_PATHS.size() - 1)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("match", "bot_commander", bot_commander)
	cfg.save(SETTINGS_PATH)


## The CommanderData file for the setting ("" = off).
static func commander_path() -> String:
	load_settings()
	return COMMANDER_PATHS[clampi(bot_commander, 0, COMMANDER_PATHS.size() - 1)]


static func set_player_name(n: String) -> void:
	load_settings()
	player_name = n.strip_edges()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("player", "name", player_name)
	cfg.save(SETTINGS_PATH)
