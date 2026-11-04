class_name HitFeedback
extends Label
## Shows what the player's last shot did ("PENETRATION – hull side ..."), centred
## below the crosshair for a few seconds. Simple stand-in for an X-ray hit view.

@export var views: PlayerViews
@export var font_size: int = 22
@export var show_time_s: float = 3.0
@export var offset_below_centre: float = 140.0
@export var hit_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var penetration_color: Color = Color(0.5, 1.0, 0.45, 1.0)
@export var no_penetration_color: Color = Color(1.0, 0.85, 0.3, 1.0)
@export var ricochet_color: Color = Color(0.5, 0.75, 1.0, 1.0)
@export var commander_hit_color: Color = Color(1.0, 0.4, 0.35, 1.0)

var _tank: Tank
var _time_left: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	add_theme_font_size_override("font_size", font_size)
	add_theme_constant_override("outline_size", 6)
	add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	visible = false


func _process(delta: float) -> void:
	_connect_to_tank()
	_time_left = maxf(_time_left - delta, 0.0)
	visible = _time_left > 0.0
	if visible:
		var screen: Vector2 = get_viewport_rect().size
		size.x = screen.x
		position = Vector2(0.0, screen.y * 0.5 + offset_below_centre)
		modulate.a = clampf(_time_left / 0.5, 0.0, 1.0)


func show_result(result: HitResult) -> void:
	text = "HIT" if result == null else result.describe()
	if result != null and result.outcome == HitResult.Outcome.COMMANDER_HIT \
			and result.target == _tank:
		text = "OWN COMMANDER HIT"
	var color: Color = hit_color
	if result != null:
		match result.outcome:
			HitResult.Outcome.PENETRATION: color = penetration_color
			HitResult.Outcome.NO_PENETRATION: color = no_penetration_color
			HitResult.Outcome.RICOCHET: color = ricochet_color
			HitResult.Outcome.COMMANDER_HIT: color = commander_hit_color
	add_theme_color_override("font_color", color)
	_time_left = show_time_s


## Shows a result the host sent (network client): text plus HitResult.Outcome.
func show_text(result_text: String, outcome: int) -> void:
	text = result_text
	var color: Color = hit_color
	match outcome:
		HitResult.Outcome.PENETRATION: color = penetration_color
		HitResult.Outcome.NO_PENETRATION: color = no_penetration_color
		HitResult.Outcome.RICOCHET: color = ricochet_color
		HitResult.Outcome.COMMANDER_HIT: color = commander_hit_color
	add_theme_color_override("font_color", color)
	_time_left = show_time_s


## Follows the player's current tank (connects once it exists).
func _connect_to_tank() -> void:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == _tank:
		return
	if _tank != null and _tank.shot_landed.is_connected(show_result):
		_tank.shot_landed.disconnect(show_result)
	_tank = tank
	if _tank != null:
		_tank.shot_landed.connect(show_result)
