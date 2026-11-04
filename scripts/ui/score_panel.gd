class_name ScorePanel
extends Control
## Top-centre King of the Hill panel: own and enemy score, which zone, its points left
## and what happens next (shrinking, closing, next zone opening), IN ZONE / OUT OF ZONE, kill bonus
## pop-ups (the result is on the Scoreboard).
## Hidden when the scene has no KothMode.

@export var views: PlayerViews
@export var font_size: int = 22
@export var own_color: Color = Color(0.45, 0.85, 1.0, 1.0)
@export var enemy_color: Color = Color(1.0, 0.45, 0.35, 1.0)
@export var text_color: Color = Color(0.92, 0.92, 0.88, 1.0)
@export var in_zone_color: Color = Color(0.55, 1.0, 0.5, 1.0)
@export var out_zone_color: Color = Color(1.0, 0.8, 0.45, 1.0)
## How long a kill bonus pop-up stays (s).
@export var bonus_show_s: float = 3.0

var _bonus_text: String = ""
var _bonus_timer: float = 0.0
var _hooked: KothMode


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var mode: KothMode = KothMode.instance
	visible = mode != null and views != null and not views.is_debug_view()
	if mode != null and mode != _hooked:
		_hooked = mode
		mode.kill_bonus.connect(_on_kill_bonus)
	_bonus_timer = maxf(_bonus_timer - delta, 0.0)
	queue_redraw()


func _on_kill_bonus(team: int, points: float) -> void:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == null or team != tank.team:
		return
	_bonus_text = "ZONE KILL +%d" % roundi(points)
	_bonus_timer = bonus_show_s


func _draw() -> void:
	var mode: KothMode = KothMode.instance
	var tank: Tank = views.get_tank() if views != null else null
	if mode == null or tank == null:
		return
	var font: Font = get_theme_default_font()
	var cx: float = size.x * 0.5
	var y: float = 34.0
	var own: int = roundi(mode.get_score(tank.team))
	var enemy: int = roundi(mode.get_best_other_score(tank.team))
	var target: int = roundi(mode.data.score_to_win)
	_text(font, Vector2(cx - 16.0, y), "%d" % own, font_size + 8, own_color, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(font, Vector2(cx, y), "–", font_size + 8, text_color, HORIZONTAL_ALIGNMENT_CENTER)
	_text(font, Vector2(cx + 16.0, y), "%d" % enemy, font_size + 8, enemy_color, HORIZONTAL_ALIGNMENT_LEFT)
	y += font_size + 8.0
	_text(font, Vector2(cx, y), "first to %d" % target, font_size - 6, text_color,
			HORIZONTAL_ALIGNMENT_CENTER)
	y += font_size - 2.0
	var zone: String = "ZONE %d" % mode.get_zone_number()
	if mode.get_zone_count() > 0:
		zone += "/%d" % mode.get_zone_count()
	var next: float = mode.get_time_to_next_event()
	if not mode.is_zone_open():
		zone += "   ·   opens in %s (see map)" % _clock(next)
	else:
		zone += "   ·   %d p left   ·   %d m" % [roundi(mode.get_budget_left()), roundi(mode.get_radius())]
		if mode.get_shrink_progress() <= 0.0:
			zone += "   ·   shrinks in %s" % _clock(next)
		else:
			zone += ", shrinking   ·   closes in %s" % _clock(next)
	_text(font, Vector2(cx, y), zone, font_size - 6, text_color, HORIZONTAL_ALIGNMENT_CENTER)
	y += font_size + 4.0
	if not tank.is_knocked_out() and mode.is_zone_open():
		var inside: bool = mode.is_in_zone(tank.global_position)
		_text(font, Vector2(cx, y), "IN ZONE" if inside else "OUT OF ZONE", font_size - 2,
				in_zone_color if inside else out_zone_color, HORIZONTAL_ALIGNMENT_CENTER)
		y += font_size + 4.0
	if _bonus_timer > 0.0:
		var c: Color = in_zone_color
		c.a = clampf(_bonus_timer, 0.0, 1.0)
		_text(font, Vector2(cx, y), _bonus_text, font_size, c, HORIZONTAL_ALIGNMENT_CENTER)


## One line of outlined text; `at` is the anchor point on the baseline.
func _text(font: Font, at: Vector2, text: String, font_px: int, color: Color,
		align: HorizontalAlignment) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var x: float = at.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= width
	draw_string_outline(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, 6,
			Color(0.0, 0.0, 0.0, 0.8))
	draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)


static func _clock(seconds: float) -> String:
	var s: int = ceili(seconds)
	return "%d:%02d" % [floori(s / 60.0), s % 60]
