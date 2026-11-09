class_name EffectFx
extends RefCounted
## Plays EffectData effects (impacts, muzzle flashes, blast dust) and makes continuous
## emitters from BurstData (track dust, flames). Cosmetic and local: every machine plays
## them from the events it already gets (shells, firing), nothing is sent.
## Materials and meshes are cached per burst and size, so a burst of MG impacts doesn't
## make new resources each time.

const SET: EffectsSetData = preload("res://data/effects/effects.tres")

## Soft particles fade out this close to what is behind them (m): no hard edge where a
## cloud meets the ground.
const PROXIMITY_FADE_M: float = 1.2

static var _cache: Dictionary = {}
static var _puff: ImageTexture


## Plays `effect` at `at`, its +Y along `out` (surface normal, barrel direction), sizes
## and speeds times `scale`. Frees itself when done. Returns the effect's node.
static func play(effect: EffectData, parent: Node, at: Vector3, out: Vector3,
		scale: float = 1.0) -> Node3D:
	if effect == null or parent == null or not parent.is_inside_tree():
		return null
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(root)
	root.global_transform = Transform3D(basis_towards(out), at)
	var longest: float = 0.0
	for burst: BurstData in effect.bursts:
		var p: GPUParticles3D = emitter(burst, scale)
		p.one_shot = true
		root.add_child(p)
		p.emitting = true
		longest = maxf(longest, burst.lifetime_s * (1.0 + burst.lifetime_randomness))
	if effect.light_energy > 0.0:
		var light := OmniLight3D.new()
		light.light_color = effect.light_color
		light.light_energy = effect.light_energy
		light.omni_range = effect.light_range_m * scale
		light.shadow_enabled = false
		root.add_child(light)
		var tween: Tween = light.create_tween()
		tween.tween_property(light, "light_energy", 0.0, effect.light_time_s)
		longest = maxf(longest, effect.light_time_s)
	parent.get_tree().create_timer(longest + 0.2, false).timeout.connect(root.queue_free)
	return root


## Plays every effect once far below the map, so their shaders are compiled while the
## map loads and the first real impact doesn't stall a frame (WeatherView calls it).
static func prewarm(parent: Node) -> void:
	var hidden := Vector3(0.0, -2000.0, 0.0)
	for effect: EffectData in [SET.impact_ground, SET.impact_armour, SET.impact_building,
			SET.impact_wood, SET.explosion, SET.bullet_ground, SET.bullet_armour,
			SET.bullet_building, SET.muzzle_flash, SET.muzzle_blast_dust]:
		play(effect, parent, hidden, Vector3.UP, 1.0)
	for burst: BurstData in [SET.track_dust, SET.fire_flames, SET.fire_smoke, SET.gun_smoke]:
		if burst == null:
			continue
		var p: GPUParticles3D = emitter(burst, 1.0)
		p.one_shot = true
		parent.add_child(p)
		p.global_position = hidden
		p.emitting = true
		parent.get_tree().create_timer(1.0, false).timeout.connect(p.queue_free)


## A particle emitter for one burst (not emitting yet; one_shot off). Emits in world
## space along the node's +Y.
static func emitter(burst: BurstData, scale: float = 1.0) -> GPUParticles3D:
	var parts: Array = _resources(burst, scale)
	var p := GPUParticles3D.new()
	p.local_coords = false
	p.amount = maxi(burst.amount, 1)
	p.lifetime = maxf(burst.lifetime_s, 0.01)
	p.explosiveness = burst.explosiveness
	p.randomness = 0.3
	p.fixed_fps = 0
	p.interpolate = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var reach: float = (burst.speed_max_mps * scale + burst.gravity.length() * burst.lifetime_s) \
			* burst.lifetime_s + burst.size_end_m * scale + 2.0
	p.visibility_aabb = AABB(-Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	if burst.align_to_velocity:
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	p.process_material = parts[0]
	p.draw_pass_1 = parts[1]
	return p


## A basis whose +Y points along `out`.
static func basis_towards(out: Vector3) -> Basis:
	var y: Vector3 = out.normalized() if out.length_squared() > 0.0001 else Vector3.UP
	var helper: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = helper.cross(y).normalized()
	return Basis(x, y, x.cross(y).normalized())


## [process material, draw mesh] for a burst at a size (cached).
static func _resources(burst: BurstData, scale: float) -> Array:
	var bucket: int = roundi(scale * 10.0)
	var weather: WeatherData = Weather.current()
	var key: String = "%d:%d:%d" % [burst.get_instance_id(), bucket,
			weather.get_instance_id() if weather != null else 0]
	if _cache.has(key):
		return _cache[key]
	var s: float = bucket / 10.0
	var process := ParticleProcessMaterial.new()
	process.direction = burst.direction.normalized()
	process.spread = burst.spread_deg
	process.initial_velocity_min = burst.speed_min_mps * s
	process.initial_velocity_max = burst.speed_max_mps * s
	process.gravity = burst.gravity + (Weather.wind() * burst.wind_share if weather != null else Vector3.ZERO)
	process.damping_min = burst.damping
	process.damping_max = burst.damping
	process.lifetime_randomness = burst.lifetime_randomness
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = maxf(burst.emission_radius_m * s, 0.001)
	process.scale_min = 1.0 - burst.size_randomness
	process.scale_max = 1.0 + burst.size_randomness
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, burst.size_start_m / maxf(burst.size_end_m, burst.size_start_m)))
	grow.add_point(Vector2(1.0, burst.size_end_m / maxf(burst.size_end_m, burst.size_start_m)))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var ramp := Gradient.new()
	ramp.set_color(0, burst.color_start)
	ramp.set_color(1, burst.color_end)
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	if not burst.align_to_velocity:
		process.angle_min = -180.0
		process.angle_max = 180.0
	var size: float = maxf(burst.size_end_m, burst.size_start_m) * s
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.disable_receive_shadows = true
	if burst.additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	elif burst.soft:
		# Smoke and dust: unshaded (a camera-facing quad lit by the sky alone turns blue),
		# tinted by the weather's light instead.
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = weather_light()
	if burst.soft:
		material.albedo_texture = puff_texture()
		material.proximity_fade_enabled = true
		material.proximity_fade_distance = PROXIMITY_FADE_M
		if burst.near_fade_m > 0.0:
			material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
			material.distance_fade_min_distance = burst.near_fade_m * 0.25
			material.distance_fade_max_distance = burst.near_fade_m
	var mesh: Mesh
	if burst.align_to_velocity:
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size * maxf(burst.stretch, 1.0))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad.material = material
		mesh = quad
	elif burst.soft:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * size
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		quad.material = material
		mesh = quad
	else:
		# Chunks (dirt, splinters): small lit boxes tumbling.
		var box := BoxMesh.new()
		box.size = Vector3(size, size * 0.6, size * 0.8)
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		material.roughness = 1.0
		box.material = material
		process.particle_flag_rotate_y = true
		process.angular_velocity_min = -360.0
		process.angular_velocity_max = 360.0
		mesh = box
	var parts: Array = [process, mesh]
	_cache[key] = parts
	return parts


## How bright smoke looks in the current weather: the sun's colour and strength over a
## floor of sky light.
static func weather_light() -> Color:
	var w: WeatherData = Weather.current()
	if w == null:
		return Color.WHITE
	var sun: Color = w.sun_color * clampf(w.sun_energy / 1.25, 0.0, 1.0)
	var sky: float = clampf(w.ambient_energy, 0.3, 1.3) * 0.45
	var c: Color = Color(sky, sky, sky) + sun * 0.6
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0), 1.0)


## A cloudy puff: a soft round falloff broken up by noise, so overlapping puffs read as
## smoke rather than as balls.
static func puff_texture() -> ImageTexture:
	if _puff == null:
		var size: int = 128
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.frequency = 0.045
		noise.fractal_octaves = 4
		var image := Image.create_empty(size, size, true, Image.FORMAT_RGBA8)
		for y: int in size:
			for x: int in size:
				var d: float = Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
				var n: float = noise.get_noise_2d(x, y) * 0.5 + 0.5
				var a: float = clampf(1.0 - smoothstep(0.25, 1.0, d + (0.5 - n) * 0.45), 0.0, 1.0)
				var shade: float = lerpf(0.8, 1.0, n)
				image.set_pixel(x, y, Color(shade, shade, shade, a * a))
		image.generate_mipmaps()
		_puff = ImageTexture.create_from_image(image)
	return _puff
