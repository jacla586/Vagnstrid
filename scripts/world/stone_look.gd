class_name StoneLook
extends Node
## Puts the stone shader (assets/shaders/stone.gdshader: faceted, mottled, moss and lichen)
## on the map's boulders from the geodata glb (meshes named Stenar_*). Wet in rain
## (Weather.current()). Lives in the player rig; cosmetic.

const SHADER_PATH: String = "res://assets/shaders/stone.gdshader"
const PREFIX: String = "Stenar"

var _done: bool = false


func _process(_delta: float) -> void:
	if _done:
		return
	_done = true
	set_process(false)
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var mat: ShaderMaterial = null
	for node: Node in root.find_children(PREFIX + "*", "MeshInstance3D", true, false):
		if mat == null:
			mat = ShaderMaterial.new()
			mat.shader = load(SHADER_PATH)
			mat.set_shader_parameter("wetness", clampf(Weather.current().rain_intensity, 0.0, 1.0))
		(node as MeshInstance3D).material_override = mat
