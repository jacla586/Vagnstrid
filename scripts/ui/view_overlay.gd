class_name ViewOverlay
extends ColorRect
## Full-screen mask for the commander's optics: periscope slit or binocular circles.
## Drawn by view_mask.gdshader; this script feeds it the mode and sizes.

@export var views: PlayerViews

var _shader_material: ShaderMaterial


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_material = material as ShaderMaterial


func _process(_delta: float) -> void:
	if views == null or _shader_material == null:
		visible = false
		return
	var mode: PlayerViews.OverlayMode = views.get_overlay_mode()
	visible = mode != PlayerViews.OverlayMode.NONE
	if not visible:
		return
	var d: TankData = views.get_tank_data()
	_shader_material.set_shader_parameter("mode", int(mode))
	_shader_material.set_shader_parameter("rect_size", size)
	_shader_material.set_shader_parameter("window_size",
			Vector2(d.periscope_window_width, d.periscope_window_height))
