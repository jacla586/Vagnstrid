class_name SmokePuffs
extends RefCounted
## Shared look for soft smoke particles (exhaust, gun smoke): a round soft-edged
## billboard that grows and fades over its life.

static var _texture: GradientTexture2D


## A particle system emitting soft puffs in world space. Colour and alpha come from
## `color`; sizes in m.
static func make(color: Color, start_size_m: float, end_size_m: float,
		lifetime_s: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.local_coords = false
	p.lifetime = lifetime_s
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.visibility_aabb = AABB(Vector3(-20.0, -5.0, -20.0), Vector3(40.0, 40.0, 40.0))
	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3.ZERO
	process.damping_min = 0.5
	process.damping_max = 1.0
	process.angle_min = -180.0
	process.angle_max = 180.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, start_size_m / maxf(end_size_m, 0.01)))
	grow.add_point(Vector2(1.0, 1.0), 0.0, 0.0)
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	process.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.15, Color(1.0, 1.0, 1.0, 1.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	process.color_ramp = fade_tex
	p.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * end_size_m
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.albedo_texture = _puff_texture()
	mat.disable_receive_shadows = true
	quad.material = mat
	p.draw_pass_1 = quad
	return p


static func _puff_texture() -> GradientTexture2D:
	if _texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		g.add_point(0.4, Color(1.0, 1.0, 1.0, 0.6))
		_texture = GradientTexture2D.new()
		_texture.gradient = g
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(0.5, 0.0)
		_texture.width = 64
		_texture.height = 64
	return _texture
