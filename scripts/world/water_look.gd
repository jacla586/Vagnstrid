class_name WaterLook
extends Node
## Puts the water shader (assets/shaders/water.gdshader) on the map's water meshes from the
## geodata glb: lakes (Sjo_*), the sea (Hav_*) and the streams (under Vattendrag). Wind and
## rain from the match's weather (Weather.current()). Lives in the player rig; cosmetic.

const SHADER_PATH: String = "res://assets/shaders/water.gdshader"
const PREFIXES: PackedStringArray = ["Sjo_", "Hav_"]
const GROUP: String = "Vattendrag"

var _done: bool = false


func _process(_delta: float) -> void:
	if _done:
		return
	_done = true
	set_process(false)
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var meshes: Array[MeshInstance3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var n: String = String(mi.name)
		var in_group: bool = mi.get_parent() != null and String(mi.get_parent().name).begins_with(GROUP)
		for p: String in PREFIXES:
			if n.begins_with(p):
				in_group = true
		if in_group:
			meshes.append(mi)
	if meshes.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	mat.set_shader_parameter("normal_a", _normal_noise(0.012, 11))
	mat.set_shader_parameter("normal_b", _normal_noise(0.03, 23))
	var w: WeatherData = Weather.current()
	var wind: Vector2 = w.wind_mps
	mat.set_shader_parameter("wind", wind if wind.length() > 0.05 else Vector2(0.4, 0.15))
	mat.set_shader_parameter("rain", clampf(w.rain_intensity, 0.0, 1.0))
	for mi: MeshInstance3D in meshes:
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _normal_noise(frequency: float, seed_value: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	tex.noise = noise
	tex.generate_mipmaps = true
	return tex
