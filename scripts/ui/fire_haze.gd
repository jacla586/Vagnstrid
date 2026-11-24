class_name FireHaze
extends ColorRect
## While the own tank's fuel burns, smoke fills the view (TankData.fire_immobilises
## and fire_view_range_factor: the crew can hardly see out): a flickering haze over
## everything but the HUD. Not in the debug view.

@export var views: PlayerViews
@export var haze_color: Color = Color(0.22, 0.2, 0.18, 1.0)
## Opacity at the start of the fire; it flickers a little round this.
@export_range(0.0, 1.0) var opacity: float = 0.72
## Fades in and out this fast (opacity per second).
@export var fade_rate: float = 1.5

var _amount: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = haze_color
	modulate.a = 0.0


func _process(delta: float) -> void:
	_time += delta
	var tank: Tank = views.get_tank() if views != null else null
	var burning: bool = tank != null and tank.is_burning() and not tank.is_knocked_out()
	_amount = move_toward(_amount, 1.0 if burning else 0.0, fade_rate * delta)
	var flicker: float = 0.06 * sin(_time * 5.3) + 0.04 * sin(_time * 11.7)
	modulate.a = _amount * clampf(opacity + flicker, 0.0, 1.0)
	visible = _amount > 0.0
