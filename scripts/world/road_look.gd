class_name RoadLook
extends Node
## Puts the asphalt shader (assets/shaders/asphalt.gdshader: tone patches, grain, cracks, repairs,
## wheel ruts, oil, worn paint; wet and puddled in rain) on the geodata glb's road meshes (under
## `Vagar`). Each glb material keeps its colour; how worn it looks goes by its name (`WEAR`). Road
## paint (`Vagmarkering`) wears towards the plain asphalt. Lives in the player rig; cosmetic.

const SHADER_PATH: String = "res://assets/shaders/asphalt.gdshader"
const GROUP_PREFIX: String = "Vagar"
## glb material name -> wear 0..1 (new asphalt from NVDB's paving year, old asphalt, pavements).
const WEAR: Dictionary = {
	"Vag_asfalt_ny": 0.15,
	"Vag_asfalt": 0.5,
	"Vag_asfalt_gammal": 0.85,
	"Trottoar": 0.45,
	"Vagmarkering": 0.5,
}
const PAINT: String = "Vagmarkering"
const PAINT_UNDER: String = "Vag_asfalt"

var _done: bool = false


func _process(_delta: float) -> void:
	if _done:
		return
	_done = true
	set_process(false)
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var wet: float = clampf(Weather.current().rain_intensity, 0.0, 1.0)
	var made: Dictionary = {}            # glb material name -> ShaderMaterial
	var under: Color = Color(0.24, 0.24, 0.25)
	var meshes: Array[MeshInstance3D] = []
	for node: Node in root.find_children(GROUP_PREFIX + "*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)
	# the plain asphalt's colour first: paint wears towards it
	for mi: MeshInstance3D in meshes:
		var m: Material = _surface_material(mi)
		if m is StandardMaterial3D and m.resource_name == PAINT_UNDER:
			under = (m as StandardMaterial3D).albedo_color
			break
	for mi: MeshInstance3D in meshes:
		var m: Material = _surface_material(mi)
		if not (m is StandardMaterial3D) or not WEAR.has(m.resource_name):
			continue
		var key: String = m.resource_name
		if not made.has(key):
			var sm := ShaderMaterial.new()
			sm.shader = load(SHADER_PATH)
			sm.set_shader_parameter("base_color", (m as StandardMaterial3D).albedo_color)
			sm.set_shader_parameter("wear", WEAR[key])
			sm.set_shader_parameter("wetness", wet)
			sm.set_shader_parameter("paint", 1.0 if key == PAINT else 0.0)
			sm.set_shader_parameter("paint_under", under)
			made[key] = sm
		mi.material_override = made[key]


func _surface_material(mi: MeshInstance3D) -> Material:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return null
	return mi.mesh.surface_get_material(0)
