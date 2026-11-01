class_name WeaponStatus
extends Label
## Bottom-left gun status: "LOADED" or "RELOADING 3.4 s". Hidden in the debug view.

@export var views: PlayerViews
@export var font_size: int = 22
@export var loaded_color: Color = Color(0.75, 1.0, 0.7, 1.0)
@export var reloading_color: Color = Color(1.0, 0.8, 0.45, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	position += Vector2(24.0, -48.0)
	add_theme_font_size_override("font_size", font_size)
	add_theme_constant_override("outline_size", 6)
	add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))


func _process(_delta: float) -> void:
	visible = views != null and not views.is_debug_view()
	if not visible:
		return
	var tank: Tank = views.get_tank()
	if tank.is_loaded():
		text = "LOADED"
		add_theme_color_override("font_color", loaded_color)
	else:
		text = "RELOADING %.1f s" % tank.get_reload_remaining()
		add_theme_color_override("font_color", reloading_color)
