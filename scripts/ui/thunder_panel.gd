class_name ThunderPanel
extends Control
## Top-centre ThunderRoad panel: round and role, checkpoint, the attackers' time bank,
## lives and next wave, capture progress, the own respawn, a warning outside the own
## corridor, and between the rounds a big VICTORY / DEFEAT banner (the round's winner;
## after round 2 the match's). The final result is on the Scoreboard. Hidden when the
## scene has no ThunderRoadMode.

@export var views: PlayerViews
@export var font_size: int = 22
@export var attack_color: Color = Color(1.0, 0.75, 0.35, 1.0)
@export var defend_color: Color = Color(0.45, 0.85, 1.0, 1.0)
@export var text_color: Color = Color(0.92, 0.92, 0.88, 1.0)
@export var good_color: Color = Color(0.55, 1.0, 0.5, 1.0)
@export var warn_color: Color = Color(1.0, 0.3, 0.25, 1.0)
## The banner between rounds: title size and its height on the screen (share).
@export var banner_font_size: int = 110
@export var banner_height: float = 0.36


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var mode: ThunderRoadMode = ThunderRoadMode.instance
	visible = mode != null and views != null and not views.is_debug_view()
	queue_redraw()


func _draw() -> void:
	var mode: ThunderRoadMode = ThunderRoadMode.instance
	var tank: Tank = views.get_tank() if views != null else null
	if mode == null or tank == null or mode.get_round() == 0:
		return
	var font: Font = get_theme_default_font()
	var cx: float = size.x * 0.5
	var y: float = 34.0
	if mode.is_over():
		return   # the Scoreboard shows the result
	if mode.is_in_break():
		_draw_banner(mode, tank, font, cx)
		return
	var attacking: bool = mode.role_of(tank.team) == ThunderRoadMode.Role.ATTACK
	_text(font, Vector2(cx, y), "ROUND %d/2   ·   %s" % [mode.get_round(),
			"ATTACK" if attacking else "DEFEND"], font_size + 4,
			attack_color if attacking else defend_color)
	y += font_size + 8.0
	var count: int = mode.get_checkpoint_count()
	var next: int = mode.get_next_checkpoint()
	var line: String = "CHECKPOINT %d/%d   ·   TIME %s   ·   LIVES %d   ·   WAVE %s" % [
			mini(next + 1, count), count, ScorePanel._clock(mode.get_time_left()),
			mode.get_lives(), ScorePanel._clock(mode.get_wave_left())]
	if mode.get_target() > 0:
		line += "   ·   TO WIN %d" % mini(mode.get_target(), count)
	_text(font, Vector2(cx, y), line, font_size - 6, text_color)
	y += font_size + 2.0
	var progress: float = mode.get_capture_progress()
	if mode.is_contested():
		_text(font, Vector2(cx, y), "CHECKPOINT %d CONTESTED" % (next + 1), font_size - 4, warn_color)
		y += font_size + 2.0
	elif progress > 0.0:
		var verb: String = "TAKING" if attacking else "LOSING"
		_text(font, Vector2(cx, y), "%s CHECKPOINT %d   %d %%" % [verb, next + 1, roundi(progress * 100.0)],
				font_size - 4, good_color if attacking else warn_color)
		y += font_size + 2.0
	if tank.is_knocked_out():
		var wait: String
		if mode.is_waiting_for_wave(tank):
			wait = "BACK WITH THE WAVE IN %s" % ScorePanel._clock(mode.get_wave_left()) \
					if mode.get_lives() > 0 else "NO LIVES LEFT – WAIT FOR A CHECKPOINT"
		else:
			wait = "BACK IN %d s" % ceili(mode.get_respawn_left(tank))
		_text(font, Vector2(cx, y), wait, font_size, text_color)
		return
	var out: float = mode.outside_time(tank)
	if out > 0.0:
		var left: float = mode.data.outside_grace_s - out
		var warn: String = "OUTSIDE YOUR CORRIDOR – CAN'T FIRE"
		warn += "   ·   COMMANDER HIT IN %d s" % ceili(left) if left > 0.0 else "   ·   GET BACK IN"
		_text(font, Vector2(cx, y + 30.0), warn, font_size + 4, warn_color)


## Between the rounds. After round 1: ROUND 1 OVER big, how far the attackers got and
## what wins round 2. After round 2: VICTORY / DEFEAT / DRAW for the match.
func _draw_banner(mode: ThunderRoadMode, tank: Tank, font: Font, cx: float) -> void:
	var results: Array[Dictionary] = mode.get_results()
	if results.is_empty():
		return
	var y: float = size.y * banner_height
	if mode.is_decided():
		var winner: int = mode.get_winner()
		_text(font, Vector2(cx, y), result_title(winner, tank.team), banner_font_size,
				result_color(winner, tank.team), 12)
		y += font_size * 2.0
		for i: int in results.size():
			_text(font, Vector2(cx, y), round_line(i + 1, results[i], tank.team, mode), font_size,
					text_color)
			y += font_size + 8.0
		_text(font, Vector2(cx, y + 6.0), "results in %d s" % ceili(mode.get_break_left()),
				font_size - 6, text_color)
		return
	var r: Dictionary = results[results.size() - 1]
	_text(font, Vector2(cx, y), "ROUND %d OVER" % mode.get_round(), banner_font_size,
			text_color, 12)
	y += font_size * 2.0
	_text(font, Vector2(cx, y), round_line(mode.get_round(), r, tank.team, mode), font_size,
			text_color)
	y += font_size + 8.0
	var need: int = int(r["checkpoints"]) + 1
	var we_attacked: bool = int(r["attack_team"]) == tank.team
	var goal: String
	if need > mode.get_checkpoint_count():
		goal = ("the enemy must take all %d faster to win" if we_attacked
				else "take all %d faster to win") % mode.get_checkpoint_count()
	else:
		goal = ("hold them under %d checkpoints to win" if we_attacked
				else "take %d checkpoints to win") % need
	_text(font, Vector2(cx, y), goal.to_upper(), font_size + 4,
			attack_color if not we_attacked else defend_color)
	y += font_size + 10.0
	_text(font, Vector2(cx, y + 6.0), "sides swap – round %d in %d s"
			% [mode.get_round() + 1, ceili(mode.get_break_left())], font_size - 6, text_color)


func result_title(winner: int, own_team: int) -> String:
	return "DRAW" if winner < 0 else ("VICTORY" if winner == own_team else "DEFEAT")


func result_color(winner: int, own_team: int) -> Color:
	return text_color if winner < 0 else (good_color if winner == own_team else warn_color)


## "ROUND 1: you took 4/6 checkpoints" – also used by the Scoreboard.
static func round_line(number: int, result: Dictionary, own_team: int, mode: ThunderRoadMode) -> String:
	var who: String = "you" if int(result["attack_team"]) == own_team else "the enemy"
	var line: String = "ROUND %d: %s took %d/%d checkpoints" % [number, who,
			int(result["checkpoints"]), mode.get_checkpoint_count()]
	if bool(result["all"]):
		line += " with %s left" % ScorePanel._clock(float(result["time_left"]))
	return line


## One line of outlined text, centred on `at` (baseline).
func _text(font: Font, at: Vector2, text: String, font_px: int, color: Color,
		outline: int = 6) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var x: float = at.x - width * 0.5
	draw_string_outline(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, outline,
			Color(0.0, 0.0, 0.0, 0.8))
	draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)
