class_name WeatherView
extends Node
## Player rig: dresses the map in the match's weather (Weather.current()): our own sky
## shader, the sun's angle, colour and energy, AgX tone mapping, SSAO, glow and fog
## (density from WeatherData.visibility_m, so it matches what bots can see). The map's
## WorldEnvironment and Sun get copies of their resources; the map files never change.

const SKY_SHADER: Shader = preload("res://assets/shaders/sky.gdshader")
## Cloud drift on the sky shader per m/s of wind (uv/s).
const CLOUD_DRIFT_PER_MPS: float = 0.0012
const APPLIED_META: StringName = &"weather_applied"


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
		_set_environment(env, weather)
		world_env.environment = env
		world_env.set_meta(APPLIED_META, weather)
	if sun != null:
		_set_sun(sun, weather)


static func _set_environment(env: Environment, w: WeatherData) -> void:
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
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	env.glow_enabled = w.glow
	env.glow_intensity = 0.35
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.3
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
		env.volumetric_fog_albedo = w.fog_color
		env.volumetric_fog_length = 200.0
	env.adjustment_enabled = not is_equal_approx(w.saturation, 1.0)
	env.adjustment_saturation = w.saturation


static func _set_sun(sun: DirectionalLight3D, w: WeatherData) -> void:
	var to_sun: Vector3 = w.sun_direction()
	var up: Vector3 = Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD
	sun.global_basis = Basis.looking_at(-to_sun, up)
	sun.light_color = w.sun_color
	sun.light_energy = w.sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_blend_splits = true


## The first node of `type_name` in the scene (maps keep them at the top).
static func _find(scene: Node, type_name: String) -> Node:
	for child: Node in scene.get_children():
		if child.is_class(type_name):
			return child
	var found: Array[Node] = scene.find_children("*", type_name, true, false)
	return found[0] if not found.is_empty() else null
