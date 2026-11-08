class_name Weather
extends RefCounted
## The match's weather (WeatherData). Set from the main menu's choice (offline, host) or
## by the host (clients, Net.rpc_welcome); read by WeatherView (looks) and by the rules
## everybody plays by (view ranges, spotting, hearing, wind).

const DEFAULT_PATH: String = "res://data/weather/clear.tres"

static var _current: WeatherData


static func current() -> WeatherData:
	if _current == null:
		_current = load(DEFAULT_PATH) as WeatherData
	return _current


static func set_current(weather: WeatherData) -> void:
	_current = weather


## A view range cut to what the weather lets anyone see (m).
static func view_range(range_m: float) -> float:
	return minf(range_m, current().visibility_m)


## Wind (m/s) as a world vector (x east, z south).
static func wind() -> Vector3:
	var w: Vector2 = current().wind_mps
	return Vector3(w.x, 0.0, w.y)
