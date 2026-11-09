class_name WeatherView
extends Node
## Player rig: dresses the map in the match's weather (Weather.current()): our own sky
## shader, the sun's angle, colour and energy, AgX tone mapping, SSAO, glow, fog
## (density from WeatherData.visibility_m, so it matches what bots can see) and colour
## grading; shadows, SSAO and glow settings from GraphicsData. The map's
## WorldEnvironment and Sun get copies of their resources; the map files never change.
## Rain: the rain loops (outside on World, muffled by the shut hatch; drumming on the
## roof on Own, loudest shut) and wet terrain (Terrain3D texture assets, put back on exit).

const SKY_SHADER: Shader = preload("res://assets/shaders/sky.gdshader")
## Cloud drift on the sky shader per m/s of wind (uv/s).
const CLOUD_DRIFT_PER_MPS: float = 0.0012
const APPLIED_META: StringName = &"weather_applied"
## The roof drumming this much quieter with the hatch fully open (dB).
const ROOF_OPEN_DB: float = -14.0

@export var tank: Tank
@export var graphics: GraphicsData = preload("res://data/world/graphics.tres")

var _outside: AudioStreamPlayer
var _roof: AudioStreamPlayer
## Terrain texture assets made wet: [asset, roughness, albedo colour] to put back.
var _wet: Array = []


func _ready() -> void:
	apply.call_deferred()


func apply() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var weather: WeatherData = Weather.current()
	var world_env: WorldEnvironment = _find(scene, "WorldEnvironment") as WorldEnvironment
	var sun: DirectionalLight3D = _find(scene, "DirectionalLight3D") as DirectionalLight3D
	if world_env != null and not (world_env.has_meta(APPLIED_META)
			and world_env.get_meta(APPLIED_META) == weather):
		var env: Environment = world_env.environment.duplicate() if world_env.environment != null \
				else Environment.new()
		_set_environment(env, weather, graphics)
		world_env.environment = env
		world_env.set_meta(APPLIED_META, weather)
	if sun != null:
		_set_sun(sun, weather, graphics)
	if weather.rain_intensity > 0.0:
		_start_rain(weather)
		_wet_terrain(scene, weather)


func _process(_delta: float) -> void:
	if _roof == null or tank == null or not is_instance_valid(tank):
		return
	var open: float = smoothstep(0.0, 1.0, tank.get_hatch_progress())
	_roof.volume_db = Weather.current().rain_roof_db + ROOF_OPEN_DB * open


func _exit_tree() -> void:
	for entry: Array in _wet:
		var asset: Terrain3DTextureAsset = entry[0]
		asset.roughness = entry[1]
		asset.albedo_color = entry[2]
	_wet.clear()


func _start_rain(w: WeatherData) -> void:
	if w.rain_outside != null and _outside == null:
		_outside = _loop_player(w.rain_outside, w.rain_outside_db, SoundFx.WORLD_BUS)
	if w.rain_roof != null and _roof == null:
		_roof = _loop_player(w.rain_roof, w.rain_roof_db, HatchMuffle.OWN_BUS)


func _loop_player(stream: AudioStream, volume_db: float, bus_name: StringName) -> AudioStreamPlayer:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = bus_name
	add_child(p)
	p.play()
	return p


## Shinier, darker ground in the rain (the assets are shared: _exit_tree puts them back).
func _wet_terrain(scene: Node, w: WeatherData) -> void:
	if not _wet.is_empty():
		return
	var terrain: Node = _find(scene, "Terrain3D")
	var assets: Terrain3DAssets = terrain.get("assets") as Terrain3DAssets if terrain != null else null
	if assets == null:
		return
	for i: int in assets.get_texture_count():
		var asset: Terrain3DTextureAsset = assets.get_texture_asset(i)
		if asset == null:
			continue
		_wet.append([asset, asset.roughness, asset.albedo_color])
		asset.roughness = clampf(asset.roughness + w.wet_roughness, -1.0, 1.0)
		asset.albedo_color = asset.albedo_color * Color(w.wet_darken, w.wet_darken, w.wet_darken, 1.0)


static func _set_environment(env: Environment, w: WeatherData, g: GraphicsData) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	mat.set_shader_parameter(&"zenith_color", w.zenith_color)
	mat.set_shader_parameter(&"horizon_color", w.horizon_color)
	mat.set_shader_parameter(&"ground_color", w.ground_color)
	mat.set_shader_parameter(&"sunset_color", w.sunset_color)
	mat.set_shader_parameter(&"sky_energy", w.sky_energy)
	mat.set_shader_parameter(&"sun_disc_scale", w.sun_disc_scale)
	mat.set_shader_parameter(&"sun_halo", w.sun_halo)
	mat.set_shader_parameter(&"cloud_coverage", w.cloud_coverage)
	mat.set_shader_parameter(&"cloud_softness", w.cloud_softness)
	mat.set_shader_parameter(&"cloud_opacity", w.cloud_opacity)
	mat.set_shader_parameter(&"cloud_color", w.cloud_color)
	mat.set_shader_parameter(&"cloud_shade", w.cloud_shade_color)
	mat.set_shader_parameter(&"cloud_scale", w.cloud_scale)
	mat.set_shader_parameter(&"cloud_wind", w.wind_mps * CLOUD_DRIFT_PER_MPS)
	var sky := Sky.new()
	sky.sky_material = mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = w.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = w.exposure
	env.ssao_enabled = w.ssao
	env.ssao_radius = g.ssao_radius
	env.ssao_intensity = g.ssao_intensity * w.ssao_intensity_factor
	env.ssao_power = g.ssao_power
	env.ssao_light_affect = g.ssao_light_affect
	env.glow_enabled = w.glow
	env.glow_intensity = g.glow_intensity
	env.glow_bloom = g.glow_bloom
	env.glow_hdr_threshold = g.glow_hdr_threshold
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = w.fog_color
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = w.fog_sun_scatter
	env.fog_density = w.fog_density()
	env.fog_sky_affect = w.fog_sky_affect
	env.fog_aerial_perspective = w.fog_aerial_perspective
	env.volumetric_fog_enabled = w.mist_density > 0.0
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = w.mist_density
		env.volumetric_fog_albedo = w.fog_color.lerp(Color.WHITE, 0.6)
		env.volumetric_fog_length = 200.0
	env.adjustment_enabled = true
	env.adjustment_saturation = w.saturation
	env.adjustment_contrast = w.contrast
	env.adjustment_brightness = w.brightness
	env.adjustment_color_correction = _grading_curve(w) if w.grade_strength > 0.0 else null


## Split toning as a per-channel curve (Environment colour correction with a 1D texture):
## dark tones lean towards grade_shadow_color, light tones towards grade_highlight_color.
static func _grading_curve(w: WeatherData) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	var dark: Color = Color.WHITE.lerp(w.grade_shadow_color, w.grade_strength)
	var light: Color = Color.WHITE.lerp(w.grade_highlight_color, w.grade_strength)
	gradient.colors = PackedColorArray([Color.BLACK, Color(dark * 0.25, 1.0),
			Color(light * 0.75, 1.0), Color.WHITE])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.use_hdr = false
	return texture


static func _set_sun(sun: DirectionalLight3D, w: WeatherData, g: GraphicsData) -> void:
	var to_sun: Vector3 = w.sun_direction()
	var up: Vector3 = Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD
	sun.global_basis = Basis.looking_at(-to_sun, up)
	sun.light_color = w.sun_color
	sun.light_energy = w.sun_energy
	sun.shadow_enabled = w.sun_shadows
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = g.shadow_max_distance_m
	sun.directional_shadow_split_1 = g.shadow_split_1
	sun.directional_shadow_split_2 = g.shadow_split_2
	sun.directional_shadow_split_3 = g.shadow_split_3
	sun.directional_shadow_fade_start = g.shadow_fade_start
	sun.shadow_blur = g.shadow_blur


## The first node of `type_name` in the scene (maps keep them at the top).
static func _find(scene: Node, type_name: String) -> Node:
	for child: Node in scene.get_children():
		if child.is_class(type_name):
			return child
	var found: Array[Node] = scene.find_children("*", type_name, true, false)
	return found[0] if not found.is_empty() else null
