class_name GroundCoverMesh
extends RefCounted
## Blade-clump meshes for the ground-cover classes (GroundCoverClassData), one per class,
## built once: thin tapered blades leaning out from the clump's centre, optional seed
## heads on top (crops). Clump height 1 (instances scale it). Vertex colour = the blade's
## own tint (a little lighter or darker, greener or yellower than the clump) with alpha =
## height along the blade, so the shader can darken the base and sway the tips.

const MATERIAL_PATH: String = "res://assets/shaders/ground_cover.gdshader"

static var _meshes: Dictionary = {}   # class resource path / name -> ArrayMesh
static var _material: ShaderMaterial


static func mesh_for(c: GroundCoverClassData) -> ArrayMesh:
	var key: String = c.resource_path + c.name
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c.name)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: int in maxi(c.blades, 1):
		var ang: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * c.spread_m
		var base := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var lean_dir := Vector3(cos(ang + rng.randf_range(-0.6, 0.6)), 0.0,
				sin(ang + rng.randf_range(-0.6, 0.6)))
		var h: float = rng.randf_range(0.7, 1.0)
		var tip: Vector3 = base + Vector3.UP * h + lean_dir * h * c.lean * rng.randf_range(0.5, 1.0)
		var side := lean_dir.cross(Vector3.UP).normalized() * c.blade_width_m * 0.5
		var mid: Vector3 = base.lerp(tip, 0.5) + lean_dir * h * c.lean * 0.15
		var lum: float = rng.randf_range(0.82, 1.15)
		var hue: float = rng.randf_range(-0.08, 0.08)   # + yellower, - greener
		var bt := Color(lum * (1.0 + hue), lum, lum * (1.0 - hue * 1.5))
		_tri(st, base - side, base + side, mid + side * 0.6, 0.0, 0.0, 0.5, bt)
		_tri(st, base - side, mid + side * 0.6, mid - side * 0.6, 0.0, 0.5, 0.5, bt)
		_tri(st, mid - side * 0.6, mid + side * 0.6, tip, 0.5, 0.5, 1.0, bt)
		if b < c.heads:
			# a seed head: a small elongated diamond along the blade's tip
			var dir: Vector3 = (tip - mid).normalized()
			var hs := side * 1.1
			var top: Vector3 = tip + dir * 0.06
			var low: Vector3 = tip - dir * 0.04
			# vertex colour × the clump's colour (MultiMesh) ≈ head_color
			var hc: Color = c.head_color.srgb_to_linear()
			var base_c: Color = c.color_a.srgb_to_linear()
			var tint := Color(clampf(hc.r / maxf(base_c.r, 0.01), 0.0, 3.0),
					clampf(hc.g / maxf(base_c.g, 0.01), 0.0, 3.0), clampf(hc.b / maxf(base_c.b, 0.01), 0.0, 3.0))
			_tri(st, low - hs, low + hs, top, 1.0, 1.0, 1.0, tint)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	_meshes[key] = m
	return m


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ha: float, hb: float, hc: float,
		tint: Color = Color.WHITE) -> void:
	for v: Array in [[a, ha], [b, hb], [c, hc]]:
		st.set_color(Color(tint.r, tint.g, tint.b, v[1]))
		st.add_vertex(v[0])


## The shared material (one for every class: the colour comes from the instances).
static func material(rules: GroundCoverSetData) -> ShaderMaterial:
	if _material != null:
		return _material
	var m := ShaderMaterial.new()
	m.shader = load(MATERIAL_PATH)
	m.set_shader_parameter("sway_m", rules.wind_sway_m)
	m.set_shader_parameter("ref_tan_half", tan(deg_to_rad(rules.reference_fov_deg) * 0.5))
	m.set_shader_parameter("full_density_m", rules.full_density_m)
	m.set_shader_parameter("blade_range_m", rules.blade_range_m)
	m.set_shader_parameter("max_widen", rules.max_widen)
	m.set_shader_parameter("thin_exponent", rules.thin_exponent)
	m.set_shader_parameter("zoom_thin_exponent", rules.zoom_thin_exponent)
	m.set_shader_parameter("flat_colour_m", rules.blade_range_m * rules.flat_colour_share)
	var w: Vector2 = Weather.current().wind_mps
	m.set_shader_parameter("wind_dir", w.normalized() * clampf(w.length() / 4.0, 0.3, 1.5) if w.length() > 0.01 else Vector2(0.3, 0.1))
	_material = m
	return m
