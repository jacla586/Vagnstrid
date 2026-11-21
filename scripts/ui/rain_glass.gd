class_name RainGlass
extends ColorRect
## Rain on the optics (periscope, binoculars, gunner's sight) in wet weather
## (Weather.current().rain_intensity), drawn by rain_glass.gdshader under the optics mask.

const SHADER: Shader = preload("res://assets/shaders/rain_glass.gdshader")

@export var views: PlayerViews

var _material: ShaderMaterial


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var intensity: float = Weather.current().rain_intensity
	if intensity <= 0.0:
		visible = false
		set_process(false)
		return
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"intensity", intensity)
	material = _material


func _process(_delta: float) -> void:
	visible = views != null \
			and views.get_overlay_mode() != PlayerViews.OverlayMode.NONE
	if visible:
		_material.set_shader_parameter(&"aspect", size.x / maxf(size.y, 1.0))
