class_name FreeFightPanel
extends Control
## Top-centre free fight panel: the wave, easy or hard, bots left, whether it holds
## (its circle is on the map) or attacks, the gap to the next wave, and the own
## return when knocked out. Hidden when the scene has no FreeFight; the end result is
## on the Scoreboard.

@export var views: PlayerViews
@export var font_size: int = 20
@export var text_color: Color = Color(0.92, 0.92, 0.88, 1.0)
@export var hold_color: Color = Color(1.0, 0.85, 0.3, 1.0)
@export var attack_color: Color = Color(1.0, 0.3, 0.25, 1.0)
@export var good_color: Color = Color(0.55, 1.0, 0.5, 1.0)
@export var banner_font_size: int = 44

const REDRAW_HZ: float = 10.0
var _redraw_clock := PackedFloat32Array([0.0])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var mode: FreeFight = FreeFight.instance
	visible = mode != null and views != null
	if visible and Ticks.due(_redraw_clock, delta, REDRAW_HZ):
		queue_redraw()


func _draw() -> void:
	var mode: FreeFight = FreeFight.instance
	var tank: Tank = views.get_tank() if views != null else null
	if mode == null or tank == null or mode.is_over():
		return
	var font: Font = get_theme_default_font()
	var cx: float = size.x * 0.5
	var y: float = 34.0
	match mode.get_phase():
		FreeFight.Phase.WAITING:
			if mode.get_gap_left() >= 0.0:
				_text(font, Vector2(cx, y), "FIRST WAVE IN %d s" % ceili(mode.get_gap_left()),
						font_size + 4, hold_color)
			return
		FreeFight.Phase.GAP:
			_text(font, Vector2(cx, y + 30.0), "WAVE %d BEATEN" % mode.get_wave_number(),
					banner_font_size, good_color)
			_text(font, Vector2(cx, y + 30.0 + banner_font_size), "Next wave in %d s" % ceili(mode.get_gap_left()),
					font_size, text_color)
			return
	var level: String = "HARD" if mode.is_hard() else "EASY"
	_text(font, Vector2(cx, y), "WAVE %d   ·   %s   ·   %d LEFT" % [mode.get_wave_number(), level,
			mode.get_alive()], font_size + 4, text_color)
	y += font_size + 8.0
	if mode.is_defending():
		_text(font, Vector2(cx, y), "Enemy holding – circle on your map", font_size - 4, hold_color)
	else:
		_text(font, Vector2(cx, y), "ENEMY ATTACKING", font_size - 2, attack_color)
	if tank.is_knocked_out():
		_text(font, Vector2(cx, y + font_size + 10.0), "BACK WHEN YOUR TEAM BEATS THE WAVE",
				font_size, text_color)


func _text(font: Font, at: Vector2, t: String, px: int, color: Color) -> void:
	var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string_outline(font, Vector2(at.x - w * 0.5, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px,
			4, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(at.x - w * 0.5, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
