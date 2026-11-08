class_name MatchNotice
extends Label
## A short line at the top of the screen for match events of the own player: team
## swap requests and results, tank changes (NetGame.on_notice, EscMenu). Fades out.

@export var font_size: int = 22
@export var color: Color = Color(1.0, 0.9, 0.55, 1.0)
## Distance from the top of the screen (px), below the mode panels.
@export var top_px: float = 190.0
## Fade over the last this many seconds.
@export var fade_s: float = 0.6

var _left: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	position.y = top_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_color", color)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("outline_size", 6)
	text = ""


func show_text(line: String, seconds: float) -> void:
	text = line
	_left = seconds
	modulate.a = 1.0


## Takes the line away early (e.g. the swap request was answered).
func clear_text(line: String) -> void:
	if text == line:
		_left = 0.0
		text = ""


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	modulate.a = clampf(_left / maxf(fade_s, 0.01), 0.0, 1.0)
	if _left <= 0.0:
		text = ""
