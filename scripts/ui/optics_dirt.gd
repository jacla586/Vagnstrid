class_name OpticsDirt
extends ColorRect
## Dirt over the view after an HE burst near the own tank (Tank.get_optics_dirt, fading
## exponentially, TankData.optics_dirt_fade_s): drawn by optics_dirt.gdshader under the
## optics mask, in the commander's and the gunner's views alike (not the debug view,
## the squad leader's eyes or the killcam). A fresh splash gets a new pattern.

const SHADER: Shader = preload("res://assets/shaders/optics_dirt.gdshader")

@export var views: PlayerViews

var _material: ShaderMaterial
var _shown: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	visible = false


func _process(_delta: float) -> void:
	var tank: Tank = views.get_tank() if views != null else null
	var dirt: float = tank.get_optics_dirt() if tank != null else 0.0
	var show: bool = dirt > 0.0 and not views.is_debug_view() and not views.is_squad_view() \
			and not views.is_killcam()
	visible = show
	if not show:
		_shown = 0.0
		return
	if dirt > _shown + 0.05:
		# A new splash on top: a new pattern (the old dirt is covered anyway).
		_material.set_shader_parameter(&"seed", Vector2(_rng.randf() * 100.0, _rng.randf() * 100.0))
	_shown = dirt
	_material.set_shader_parameter(&"amount", dirt)
	_material.set_shader_parameter(&"aspect", size.x / maxf(size.y, 1.0))
