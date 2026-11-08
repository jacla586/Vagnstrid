class_name WeatherData
extends Resource
## One weather preset (data/weather/*.tres): sun, sky, clouds, light, fog, and what it
## does to play (same for bots, squads and players). Picked in the main menu
## (MatchSettings.weather), held by Weather, shown by WeatherView in the player rig.

@export var display_name: String = "Clear"

@export_group("Sun")
## Height of the sun over the horizon (degrees) and its compass direction (degrees,
## 0 = north (-Z), 90 = east (+X)).
@export_range(-10.0, 90.0) var sun_elevation_deg: float = 42.0
@export_range(0.0, 360.0) var sun_azimuth_deg: float = 200.0
@export var sun_color: Color = Color(1.0, 0.96, 0.88)
@export var sun_energy: float = 1.25
## Sun disc size on the sky (1 = the light's own angular size).
@export var sun_disc_scale: float = 2.5
## Glow round the sun.
@export var sun_halo: float = 0.35

@export_group("Sky")
@export var zenith_color: Color = Color(0.2, 0.4, 0.78)
@export var horizon_color: Color = Color(0.66, 0.76, 0.88)
@export var ground_color: Color = Color(0.32, 0.33, 0.3)
## The horizon towards a low sun turns this colour (dawn, dusk).
@export var sunset_color: Color = Color(1.0, 0.55, 0.3)
@export var sky_energy: float = 1.0

@export_group("Clouds")
@export_range(0.0, 1.0) var cloud_coverage: float = 0.46
## Soft (high) or sharp (low) cloud edges.
@export_range(0.01, 1.0) var cloud_softness: float = 0.2
@export_range(0.0, 1.0) var cloud_opacity: float = 0.9
@export var cloud_color: Color = Color(1.0, 1.0, 1.0)
@export var cloud_shade_color: Color = Color(0.56, 0.62, 0.72)
## Bigger = smaller, busier clouds.
@export var cloud_scale: float = 1.0

@export_group("Light")
@export var exposure: float = 1.0
@export var ambient_energy: float = 1.0
@export var ssao: bool = true
@export var glow: bool = true
@export_range(0.0, 2.0) var saturation: float = 1.05

@export_group("Fog and visibility")
## How far anyone can see (m): the fog is ~95 % thick there, and bots' and squads'
## view ranges are cut to it.
@export var visibility_m: float = 7500.0
@export var fog_color: Color = Color(0.7, 0.77, 0.86)
@export_range(0.0, 1.0) var fog_sun_scatter: float = 0.15
@export_range(0.0, 1.0) var fog_sky_affect: float = 0.25
@export_range(0.0, 1.0) var fog_aerial_perspective: float = 0.5
## Ground mist (volumetric fog density; 0 = off).
@export var mist_density: float = 0.0

@export_group("Play")
## Spotting takes this many times longer (rain, mist).
@export var spot_time_factor: float = 1.0
## Other tanks' sounds this much quieter (dB; rain drowns them).
@export var hearing_db: float = 0.0

@export_group("Wind and rain")
## Wind (m/s, x east, y south): clouds, smoke and rain drift with it.
@export var wind_mps: Vector2 = Vector2(2.0, 0.8)
## 0 = dry .. 1 = heavy rain.
@export_range(0.0, 1.0) var rain_intensity: float = 0.0


## Fog density for the exponential fog: ~95 % fogged at visibility_m.
func fog_density() -> float:
	return 3.0 / maxf(visibility_m, 10.0)


## Direction towards the sun (unit, world).
func sun_direction() -> Vector3:
	var el: float = deg_to_rad(sun_elevation_deg)
	var az: float = deg_to_rad(sun_azimuth_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()
