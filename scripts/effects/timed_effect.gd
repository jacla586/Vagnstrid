class_name TimedEffect
extends Node3D
## Short-lived visual effect: optional "Mesh" child grows and fades, optional "Light"
## child fades out, then the node frees itself.

@export var lifetime: float = 0.2
@export var start_scale: float = 0.5
@export var end_scale: float = 2.0

var _age: float = 0.0
var _material: StandardMaterial3D
var _start_alpha: float = 1.0
var _light_energy: float = 0.0

@onready var _mesh: MeshInstance3D = get_node_or_null("Mesh")
@onready var _light: OmniLight3D = get_node_or_null("Light")


func _ready() -> void:
	if _mesh != null and _mesh.material_override is StandardMaterial3D:
		# Own copy so fading one effect doesn't fade all of them.
		_material = _mesh.material_override.duplicate()
		_mesh.material_override = _material
		_start_alpha = _material.albedo_color.a
	if _light != null:
		_light_energy = _light.light_energy
	_apply(0.0)


func _process(delta: float) -> void:
	_age += delta
	var t: float = _age / maxf(lifetime, 0.001)
	if t >= 1.0:
		queue_free()
		return
	_apply(t)


func _apply(t: float) -> void:
	if _mesh != null:
		_mesh.scale = Vector3.ONE * lerpf(start_scale, end_scale, t)
	if _material != null:
		_material.albedo_color.a = _start_alpha * (1.0 - t)
	if _light != null:
		_light.light_energy = _light_energy * (1.0 - t)
