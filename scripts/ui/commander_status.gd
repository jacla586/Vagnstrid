class_name CommanderStatus
extends Control
## Commander wound feedback: a red flash when hit, a dim pulsing red tint over the
## commander view while wounded, and "COMMANDER WOUNDED – 14 s" text. Pressing the
## hatch key while wounded shows "HATCH BLOCKED".

@export var views: PlayerViews
@export var font_size: int = 26
@export var text_color: Color = Color(1.0, 0.35, 0.3, 1.0)
@export var flash_alpha: float = 0.55
@export var flash_time_s: float = 0.5
@export var wounded_tint_alpha: float = 0.14
@export var blocked_message_time_s: float = 1.5

var _tank: Tank
var _flash: float = 0.0
var _blocked_message: float = 0.0
var _time: float = 0.0
## Something was drawn last time (so one more redraw clears it).
var _drawn: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hatch") and _tank != null and _tank.is_commander_wounded():
		_blocked_message = blocked_message_time_s


func _process(delta: float) -> void:
	_connect_to_tank()
	_time += delta
	_flash = maxf(_flash - delta / maxf(flash_time_s, 0.01), 0.0)
	_blocked_message = maxf(_blocked_message - delta, 0.0)
	# A full-screen layer: only redrawn while it shows something (or to clear it).
	var showing: bool = _tank != null and (_flash > 0.0 or _tank.is_commander_wounded())
	if showing or _drawn:
		queue_redraw()
	_drawn = showing


func _draw() -> void:
	if _tank == null or views == null or views.is_debug_view():
		return
	var rect := Rect2(Vector2.ZERO, size)
	var alpha: float = _flash * flash_alpha
	if _tank.is_commander_wounded() and views.get_mode() == PlayerViews.ViewMode.COMMANDER:
		alpha = maxf(alpha, wounded_tint_alpha * (0.75 + 0.25 * sin(_time * 3.0)))
	if alpha > 0.0:
		draw_rect(rect, Color(0.6, 0.0, 0.0, alpha))
	if not _tank.is_commander_wounded():
		return
	var font: Font = get_theme_default_font()
	var line: String = "COMMANDER WOUNDED – %d s" % ceili(_tank.get_commander_wound_remaining())
	if _blocked_message > 0.0:
		line += "   HATCH BLOCKED"
	var width: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var position_px := Vector2((size.x - width) * 0.5, 80.0)
	draw_string_outline(font, position_px, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6,
			Color(0.0, 0.0, 0.0, 0.85))
	draw_string(font, position_px, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)


func _on_commander_wounded() -> void:
	_flash = 1.0


func _connect_to_tank() -> void:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == _tank:
		return
	if _tank != null and _tank.commander_wounded.is_connected(_on_commander_wounded):
		_tank.commander_wounded.disconnect(_on_commander_wounded)
	_tank = tank
	if _tank != null:
		_tank.commander_wounded.connect(_on_commander_wounded)
