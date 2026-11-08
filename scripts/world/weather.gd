class_name Weather
extends RefCounted
## The match's weather (WeatherData). Chosen in the main menu (MatchSettings.weather,
## "random" or a preset) and fixed for the match by resolve() (offline, host), or set by
## the host (clients, Net.rpc_welcome). Read by WeatherView (looks) and by the rules
## everybody plays by (view ranges, spotting, hearing, wind).

const RANDOM: String = "random"
const DIR: String = "res://data/weather/"
## Menu order; "random" picks among these.
const PRESETS: PackedStringArray = ["clear", "overcast", "dawn", "dusk", "fog", "rain"]
const DEFAULT_ID: String = "clear"

static var _current: WeatherData


## The match's weather; resolves the menu choice the first time (F5/F6 in the editor too).
static func current() -> WeatherData:
	if _current == null:
		resolve()
	return _current


## Fixes the weather from the menu choice (a random preset for "random").
static func resolve() -> void:
	MatchSettings.load_settings()
	var id: String = MatchSettings.weather
	if id == RANDOM or not PRESETS.has(id):
		id = PRESETS[randi() % PRESETS.size()] if id == RANDOM else DEFAULT_ID
	_current = load_preset(id)


static func set_current(weather: WeatherData) -> void:
	_current = weather


## Clients: the host's preset by path (falls back to the default).
static func set_by_path(path: String) -> void:
	var w: WeatherData = load(path) as WeatherData if ResourceLoader.exists(path) else null
	_current = w if w != null else load_preset(DEFAULT_ID)


static func load_preset(id: String) -> WeatherData:
	return load(DIR + id + ".tres") as WeatherData


## A view range cut to what the weather lets anyone see (m).
static func view_range(range_m: float) -> float:
	return minf(range_m, current().visibility_m)


## Wind (m/s) as a world vector (x east, z south).
static func wind() -> Vector3:
	var w: Vector2 = current().wind_mps
	return Vector3(w.x, 0.0, w.y)
