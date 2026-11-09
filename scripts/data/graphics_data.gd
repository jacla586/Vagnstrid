class_name GraphicsData
extends Resource
## Picture settings that are the same in every weather (data/world/graphics.tres): sun
## shadows, ambient occlusion and glow. WeatherView puts them on the map; per-weather
## looks (sun, sky, fog, grading) are in WeatherData.

@export_group("Sun shadows")
## How far from the camera the sun casts shadows (m). Further costs GPU time: trees
## within it are drawn a second time for the shadow map.
@export var shadow_max_distance_m: float = 300.0
## Where the 2nd, 3rd and 4th shadow cascades start, as shares of the distance
## (smaller = sharper shadows close by).
@export_range(0.0, 1.0) var shadow_split_1: float = 0.08
@export_range(0.0, 1.0) var shadow_split_2: float = 0.22
@export_range(0.0, 1.0) var shadow_split_3: float = 0.5
## Shadows fade out from this share of the distance.
@export_range(0.0, 1.0) var shadow_fade_start: float = 0.8
@export var shadow_blur: float = 1.0

@export_group("Ambient occlusion")
@export var ssao_radius: float = 1.5
@export var ssao_intensity: float = 1.6
@export var ssao_power: float = 1.5
## How much direct light AO darkens (0 = only ambient light).
@export_range(0.0, 1.0) var ssao_light_affect: float = 0.0

@export_group("Glow")
@export var glow_intensity: float = 0.35
@export var glow_bloom: float = 0.03
@export var glow_hdr_threshold: float = 1.3
