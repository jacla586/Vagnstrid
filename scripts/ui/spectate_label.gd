class_name SpectateLabel
extends Label
## Knocked out and following a teammate (Killcam, PlayerViews.get_spectated): a line at
## the bottom of the screen saying whom, "SPECTATING <player name> – T-34" (bots: "Bot"),
## and that a click goes to the next. Hidden otherwise.

@export var views: PlayerViews
@export var font_size: int = 20
@export var color: Color = Color(1.0, 0.9, 0.55, 1.0)
## Distance from the bottom of the screen (px).
@export var bottom_px: float = 70.0

var _shown: Tank
var _shown_name: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -bottom_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_color", color)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("outline_size", 6)
	text = ""
	visible = false


func _process(_delta: float) -> void:
	var watched: Tank = views.get_spectated() if views != null else null
	if watched == null:
		if visible:
			visible = false
			_shown = null
		return
	# Text only when it changes (HUD rule: no per-frame theme or text churn).
	var line: String = "SPECTATING %s – %s" % [watched.get_player_name(), watched.get_type_name()]
	if watched != _shown or line != _shown_name:
		_shown = watched
		_shown_name = line
		text = line + "\nclick: next teammate"
	if not visible:
		visible = true
