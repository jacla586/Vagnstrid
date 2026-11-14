class_name ThunderPanel
extends Control
## Top-centre ThunderRoad panel: round and role, checkpoint, the attackers' time bank,
## lives and next wave, capture progress, the ceasefire after a capture (regroup /
## fall back), the own respawn, a warning outside the own corridor (knocked out in n s), and between the rounds (the Scoreboard shows in the middle then) the
## result at the top and a big countdown to the next round at the bottom; after round 2
## a VICTORY / DEFEAT banner for the match. The final result is on the Scoreboard. Hidden when the
## scene has no ThunderRoadMode. A checkpoint taken or lost flashes a big ZONE CAPTURED / ZONE LOST
## in the middle; the command radio (`ThunderRoadData.calls`, `ThunderCallsData`) goes out
## through `radio` (SquadRadio): taken/lost, fall back, the enemy regrouping, the ceasefire's
## end, the clock at 2 and 1 min, outside the corridor, the line held.

@export var views: PlayerViews
@export var font_size: int = 20
@export var attack_color: Color = Color(1.0, 0.75, 0.35, 1.0)
@export var defend_color: Color = Color(0.45, 0.85, 1.0, 1.0)
@export var text_color: Color = Color(0.92, 0.92, 0.88, 1.0)
@export var good_color: Color = Color(0.55, 1.0, 0.5, 1.0)
@export var warn_color: Color = Color(1.0, 0.3, 0.25, 1.0)
## Between rounds: title size and its baseline from the top (px; the Scoreboard is in
## the middle), the countdown's size and its baseline (share of the screen height).
@export var banner_font_size: int = 84
@export var banner_top_px: float = 110.0
@export var countdown_font_size: int = 54
@export var countdown_height: float = 0.88
## ZONE CAPTURED / ZONE LOST: size, seconds shown (the last one fades), baseline (share of height).
@export var flash_font_size: int = 72
@export var flash_s: float = 4.0
@export var flash_height: float = 0.3
## Plays the command calls (subtitle and queue shared with the squad's radio).
@export var radio: SquadRadio


const REDRAW_HZ: float = 10.0
var _redraw_clock := PackedFloat32Array([0.0])
var _mode: ThunderRoadMode
var _flash_title: String = ""
var _flash_line: String = ""
var _flash_color: Color = Color.WHITE
var _flash_left: float = 0.0
var _last_time: float = -1.0
var _last_pause: float = -1.0
var _was_outside: bool = false
var _return_clock: float = INF
# True from the start: the player's rig (and this panel) is made when they deploy, after
# round 1's round_started, so a fresh panel greets the round it lands in.
var _start_pending: bool = true
var _start_flash: bool = true
var _flash_scale: float = 1.0
var _result_said: bool = false
var _stragglers_left: float = -1.0    # s until the stragglers check after a capture
var _left_behind: bool = false        # the own tank, last frame
var _late_said: bool = false
var _behind_mates: Dictionary = {}    # teammates left behind -> true
var _lost_clock: float = INF

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # full size: text centres on the screen
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var mode: ThunderRoadMode = ThunderRoadMode.instance
	visible = mode != null and views != null and not views.is_debug_view()
	if mode != _mode:
		_connect(mode)
	if mode != null:
		_watch_calls(mode, delta)
	if _flash_left > 0.0:
		_flash_left -= delta
		if visible:
			queue_redraw()   # the fade wants every frame
	# Clocks and counts: REDRAW_HZ times a second is plenty.
	elif visible and Ticks.due(_redraw_clock, delta, REDRAW_HZ):
		queue_redraw()


func _connect(mode: ThunderRoadMode) -> void:
	if _mode != null and is_instance_valid(_mode):
		_mode.checkpoint_taken.disconnect(_on_checkpoint_taken)
		_mode.pause_ended.disconnect(_on_pause_ended)
		_mode.round_over.disconnect(_on_round_over)
		_mode.round_started.disconnect(_on_round_started)
		_mode.match_over.disconnect(_on_match_over)
	_mode = mode
	if _mode != null:
		_mode.checkpoint_taken.connect(_on_checkpoint_taken)
		_mode.pause_ended.connect(_on_pause_ended)
		_mode.round_over.connect(_on_round_over)
		_mode.round_started.connect(_on_round_started)
		_mode.match_over.connect(_on_match_over)


func _own_attacking(mode: ThunderRoadMode) -> int:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == null:
		return -1
	return 1 if mode.role_of(tank.team) == ThunderRoadMode.Role.ATTACK else 0


## A command call: sound only (what happens shows in English: `_flash`).
func _call(stream: AudioStream) -> void:
	var c: ThunderCallsData = _mode.data.calls if _mode != null else null
	if radio != null and c != null and stream != null:
		radio.command_call(stream, c.volume_db)


## The plain call, or now and then its rare (funny) stand-in.
func _call_or_rare(stream: AudioStream, rare: AudioStream, chance: float) -> void:
	_call(rare if rare != null and randf() < chance else stream)


static func _pick(streams: Array[AudioStream]) -> AudioStream:
	return null if streams.is_empty() else streams[randi() % streams.size()]


## One of the crew's lines at random, sound only.
func _banter(streams: Array[AudioStream]) -> void:
	var c: ThunderCallsData = _mode.data.calls if _mode != null else null
	if radio == null or c == null or streams.is_empty():
		return
	radio.command_call(streams[randi() % streams.size()], c.banter_volume_db)


## A big line of English in the middle for a few seconds: what just happened and what to do.
## `scale` < 1 for lesser news than a checkpoint.
func _flash(title: String, line: String, color: Color, scale: float = 1.0) -> void:
	_flash_title = title
	_flash_line = line
	_flash_color = color
	_flash_scale = scale
	_flash_left = flash_s


## Said once the round is under way and the own tank is there (round 1 may start
## before the player has deployed).
func _on_round_started(_round_number: int, _attack_team: int) -> void:
	_start_pending = true
	_start_flash = true


## Said when VICTORY / DEFEAT shows (round 2's end decides it), not at match_over
## round_break_s later, when the player may already have left.
func _on_match_over(winner_team: int) -> void:
	_say_result(winner_team)


func _say_result(winner_team: int) -> void:
	if _result_said:
		return
	var c: ThunderCallsData = _mode.data.calls
	var tank: Tank = views.get_tank() if views != null else null
	if c == null or tank == null or winner_team < 0:
		return
	_result_said = true
	if winner_team == tank.team:
		_banter(c.victory)
	else:
		_banter(c.defeat)


func _on_checkpoint_taken(index: int) -> void:
	var attacking: int = _own_attacking(_mode)
	if attacking < 0:
		return
	var count: int = _mode.get_checkpoint_count()
	var last: bool = index >= count - 1
	var line: String = "FINAL CHECKPOINT" if last else "CHECKPOINT %d OF %d" % [index + 1, count]
	if not last:
		var push: String = "ADVANCE" if _mode.data.retreat_instead_of_pause else "REGROUP"
		line += "   ·   " + push if attacking == 1 else "   ·   FALL BACK TO CHECKPOINT %d" % (index + 2)
	_flash("ZONE CAPTURED" if attacking == 1 else "ZONE LOST", line,
			good_color if attacking == 1 else warn_color)
	var c: ThunderCallsData = _mode.data.calls
	# The last checkpoint of round 2 ends the match: only the win/loss line is said then.
	if c == null or (last and _mode.get_round() >= 2):
		return
	if attacking == 1:
		if last:
			_call(c.secured)
		elif _mode.data.retreat_instead_of_pause and not c.advance.is_empty():
			_call(_pick(c.advance))
			_stragglers_left = c.stragglers_delay_s
		else:
			_call(c.taken)
	else:
		_call_or_rare(c.lost, c.lost_rare, c.lost_rare_chance)
		if not last:
			var number: int = index + 2   # the next checkpoint, 1-based
			_call(c.fall_back[number - 1] if number <= c.fall_back.size() else null)


func _on_pause_ended(index: int) -> void:
	var attacking: int = _own_attacking(_mode)
	var c: ThunderCallsData = _mode.data.calls
	if attacking == 1:
		_flash("CHECKPOINT %d OPEN" % (index + 1), "ATTACK", attack_color, 0.75)
		if c != null and not c.next_open.is_empty():
			_call(_pick(c.next_open))
	elif attacking == 0:
		_flash("ENEMY ADVANCING", "TAKE YOUR POSITIONS   ·   HOLD CHECKPOINT %d" % (index + 1),
				defend_color, 0.75)
		if c != null:
			var all: Array[AudioStream] = c.enemy_coming_more.duplicate()
			if c.enemy_coming != null:
				all.append(c.enemy_coming)
			_call(_pick(all))


func _on_round_over(_round_number: int, result: Dictionary) -> void:
	var c: ThunderCallsData = _mode.data.calls
	if c != null and _own_attacking(_mode) == 0 and not bool(result.get("all", false)) \
			and not _mode.is_decided():   # the match's end: only the win/loss line
		_call(c.held)
	if _mode.is_decided():
		_say_result(_mode.get_winner())


## Calls from the clocks: the enemy regrouping mid-ceasefire, time running short, and
## the own tank leaving its corridor.
func _watch_calls(mode: ThunderRoadMode, delta: float) -> void:
	var c: ThunderCallsData = mode.data.calls
	var tank: Tank = views.get_tank() if views != null else null
	if c == null or tank == null or mode.get_round() == 0 or mode.is_over() or mode.is_in_break():
		_last_time = -1.0
		_last_pause = -1.0
		return
	if _start_pending:
		_start_pending = false
		_banter(c.round_start)
	var attacking: bool = mode.role_of(tank.team) == ThunderRoadMode.Role.ATTACK
	if _start_flash:
		_start_flash = false
		_flash("ROUND %d   ·   %s" % [mode.get_round(), "ATTACK" if attacking else "DEFEND"],
				"TAKE THE CHECKPOINTS ALONG THE ROAD" if attacking else "HOLD THE ROAD",
				attack_color if attacking else defend_color, 0.75)
	var pause: float = mode.get_pause_left() if mode.is_paused() else -1.0
	var mark: float = mode.transition_s() * c.regroup_call_share
	if attacking and not mode.data.retreat_instead_of_pause and _last_pause > mark and pause >= 0.0 and pause <= mark:
		_call(c.regrouping)
		_flash("ENEMY REGROUPING", "PREPARE TO ATTACK", attack_color, 0.75)
	_last_pause = pause
	var time: float = -1.0 if mode.is_paused() else mode.get_time_left()
	if _last_time >= 0.0 and time >= 0.0:
		var streams: Array[AudioStream] = c.attack_clock if attacking else c.defend_clock
		for i: int in c.clock_call_s.size():
			var at: float = c.clock_call_s[i]
			if _last_time > at and time <= at:
				var stream: AudioStream = streams[i] if i < streams.size() else null
				if attacking and i == c.clock_call_s.size() - 1 and c.attack_clock_last_rare != null \
						and randf() < c.attack_clock_last_rare_chance:
					stream = c.attack_clock_last_rare
				_call(stream)
				var minutes: int = roundi(at / 60.0)
				_flash("%d MINUTE%s LEFT" % [minutes, "" if minutes == 1 else "S"],
						"PRESS THE ATTACK" if attacking else "HOLD THE LINE", warn_color, 0.75)
	_last_time = time
	_return_clock += delta
	var outside: bool = not tank.is_knocked_out() and mode.outside_time(tank) > 0.0 \
			and not mode.is_left_behind(tank)   # left behind: the fall-back call said it
	if outside and not _was_outside and _return_clock >= c.return_cooldown_s:
		_return_clock = 0.0
		_call_or_rare(c.return_to_lines, c.return_rare, c.return_rare_chance)
	_was_outside = outside
	_watch_retreat(mode, tank, c, attacking, delta)


## The fighting retreat: stragglers for the attackers; for a defender its own last stand
## (crew on the intercom) and teammates lost behind the line.
func _watch_retreat(mode: ThunderRoadMode, tank: Tank, c: ThunderCallsData, attacking: bool,
		delta: float) -> void:
	if _stragglers_left >= 0.0:
		_stragglers_left -= delta
		if _stragglers_left < 0.0 and attacking:
			for node: Node in get_tree().get_nodes_in_group("tanks"):
				var other := node as Tank
				if other != null and other.team != tank.team and not other.is_knocked_out() \
						and mode.is_left_behind(other):
					_call(_pick(c.stragglers))
					break
	var behind: bool = not tank.is_knocked_out() and mode.is_left_behind(tank)
	if behind and not _left_behind:
		_late_said = false
		_banter(c.left_behind)
	elif behind and not _late_said and mode.data.retreat_s - mode.outside_time(tank) <= c.left_behind_late_s:
		_late_said = true
		if c.left_behind_late != null:
			radio.command_call(c.left_behind_late, c.banter_volume_db)
	elif not behind and _left_behind and not tank.is_knocked_out():
		_banter(c.made_it_back)
	_left_behind = behind
	_lost_clock += delta
	if attacking:
		_behind_mates.clear()
		return
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var mate := node as Tank
		if mate == null or mate == tank or mate.team != tank.team:
			continue
		if mate.is_knocked_out():
			if _behind_mates.has(mate):
				_behind_mates.erase(mate)
				if _lost_clock >= c.tank_lost_cooldown_s:
					_lost_clock = 0.0
					_call(c.tank_lost)
		elif mode.is_left_behind(mate):
			_behind_mates[mate] = true
		else:
			_behind_mates.erase(mate)


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
	if _flash_left > 0.0:
		var fade: Color = _flash_color
		fade.a = clampf(_flash_left, 0.0, 1.0)
		var fy: float = size.y * flash_height
		_text(font, Vector2(cx, fy), _flash_title, roundi(flash_font_size * _flash_scale), fade, 12, fade.a)
		var sub: Color = Color.WHITE
		sub.a = fade.a
		_text(font, Vector2(cx, fy + font_size * 2.0), _flash_line, font_size + 8, sub, 8, fade.a)
	var attacking: bool = mode.role_of(tank.team) == ThunderRoadMode.Role.ATTACK
	_text(font, Vector2(cx, y), "ROUND %d/2   ·   %s" % [mode.get_round(),
			"ATTACK" if attacking else "DEFEND"], font_size + 4,
			attack_color if attacking else defend_color)
	y += font_size + 8.0
	var count: int = mode.get_checkpoint_count()
	var next: int = mode.get_next_checkpoint()
	var paused: bool = mode.is_paused()
	var retreat: bool = mode.data.retreat_instead_of_pause
	var pause_word: String = ("ADVANCE" if attacking else "FALL BACK") if retreat else "REGROUP"
	var clock: String = "%s %s" % [pause_word, ScorePanel._clock(mode.get_pause_left())] if paused \
			else "TIME %s" % ScorePanel._clock(mode.get_time_left())
	var line: String = "CHECKPOINT %d/%d   ·   %s   ·   LIVES %d   ·   WAVE %s" % [
			mini(next + 1, count), count, clock, mode.get_lives(),
			ScorePanel._clock(mode.get_wave_left())]
	_text(font, Vector2(cx, y), line, font_size - 6, text_color)
	y += font_size + 2.0
	var goal: Array = target_state(mode, attacking)
	if not String(goal[0]).is_empty():
		var reached: bool = bool(goal[1])
		_text(font, Vector2(cx, y), String(goal[0]), font_size - 2,
				(good_color if attacking else warn_color) if reached else text_color)
		y += font_size + 2.0
	if paused:
		var pause: String
		if attacking:
			pause = "CHECKPOINT %d TAKEN – %s   ·   NEXT OPENS IN %d s" % [next,
					"ADVANCE, HUNT THE STRAGGLERS" if retreat else "REGROUP", ceili(mode.get_pause_left())]
		else:
			pause = "FALL BACK TO CHECKPOINT %d   ·   ENEMY ATTACKS IN %d s" % [next + 1,
					ceili(mode.get_pause_left())]
		_text(font, Vector2(cx, y), pause, font_size + 2, attack_color if attacking else defend_color)
		y += font_size + 6.0
	var progress: float = mode.get_capture_progress()
	if mode.is_overtime():
		_text(font, Vector2(cx, y), "OVERTIME", font_size + 2, warn_color)
		y += font_size + 6.0
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
	if out > 0.0 and mode.is_left_behind(tank):
		var stand: String = "LEFT BEHIND – FALL BACK PAST THE LINE   ·   THE ENEMY SEES YOU"
		stand += "   ·   KNOCKED OUT IN %d s" % ceili(maxf(mode.data.retreat_s - out, 0.0))
		_text(font, Vector2(cx, y + 30.0), stand, font_size + 4, warn_color)
	elif out > 0.0:
		var left: float = mode.data.outside_knockout_s - out
		var warn: String = "OUTSIDE YOUR CORRIDOR – CAN'T FIRE"
		warn += "   ·   KNOCKED OUT IN %d s" % ceili(maxf(left, 0.0))
		_text(font, Vector2(cx, y + 30.0), warn, font_size + 4, warn_color)


## Between the rounds. After round 1: ROUND 1 OVER big, how far the attackers got and
## what wins round 2. After round 2: VICTORY / DEFEAT / DRAW for the match.
func _draw_banner(mode: ThunderRoadMode, tank: Tank, font: Font, cx: float) -> void:
	var results: Array[Dictionary] = mode.get_results()
	if results.is_empty():
		return
	var y: float = banner_top_px
	var countdown_y: float = size.y * countdown_height
	var seconds: int = ceili(mode.get_break_left())
	if mode.is_decided():
		var winner: int = mode.get_winner()
		_text(font, Vector2(cx, y), result_title(winner, tank.team), banner_font_size,
				result_color(winner, tank.team), 12)
		y += font_size * 2.2
		for i: int in results.size():
			_text(font, Vector2(cx, y), round_line(i + 1, results[i], tank.team, mode), font_size + 4,
					text_color)
			y += font_size + 10.0
		_text(font, Vector2(cx, countdown_y), "RESULTS IN %d" % seconds, countdown_font_size - 14,
				text_color, 10)
		return
	var r: Dictionary = results[results.size() - 1]
	var attacked: bool = int(r["attack_team"]) == tank.team
	_text(font, Vector2(cx, y), "ROUND %d OVER" % mode.get_round(), banner_font_size,
			attack_color if attacked else defend_color, 12)
	y += font_size * 2.2
	# How it went, from this player's side: what they took, or what they let through.
	var taken: int = int(r["checkpoints"])
	var count: int = mode.get_checkpoint_count()
	var how: String
	if attacked:
		how = "YOU TOOK %d OF %d CHECKPOINTS" % [taken, count]
	else:
		how = "THE ENEMY TOOK %d OF %d CHECKPOINTS" % [taken, count]
	if bool(r["all"]):
		how += " WITH %s LEFT" % ScorePanel._clock(float(r["time_left"]))
	_text(font, Vector2(cx, y), how, font_size + 12, Color.WHITE, 8)
	y += font_size + 18.0
	var need: int = int(r["checkpoints"]) + 1
	var we_attacked: bool = int(r["attack_team"]) == tank.team
	var goal: String
	if need > mode.get_checkpoint_count():
		goal = ("the enemy must take all %d faster to win" if we_attacked
				else "take all %d faster to win") % mode.get_checkpoint_count()
	else:
		goal = ("hold them under %d checkpoints to win" if we_attacked
				else "take %d checkpoints to win") % need
	_text(font, Vector2(cx, y), "ROUND %d: YOU %s – %s" % [mode.get_round() + 1,
			"DEFEND" if we_attacked else "ATTACK", goal.to_upper()], font_size + 2,
			defend_color if we_attacked else attack_color)
	_text(font, Vector2(cx, countdown_y), "ROUND %d STARTS IN %d" % [mode.get_round() + 1, seconds],
			countdown_font_size, Color.WHITE, 10)


func result_title(winner: int, own_team: int) -> String:
	return "DRAW" if winner < 0 else ("VICTORY" if winner == own_team else "DEFEAT")


func result_color(winner: int, own_team: int) -> Color:
	return text_color if winner < 0 else (good_color if winner == own_team else warn_color)


## Round 2's goal from this side, counting down: [text, reached]. Attackers: "2 MORE
## CHECKPOINTS TO WIN" until they have enough, then "WIN SECURED"; defenders: "STOP
## THEM: 2 MORE AND THEY WIN", then "THEY HAVE ENOUGH – MATCH LOST". When round 1 took
## them all, round 2 must take all with more time left. ["", false] outside round 2.
static func target_state(mode: ThunderRoadMode, attacking: bool) -> Array:
	var target: int = mode.get_target()
	if target <= 0:
		return ["", false]
	var count: int = mode.get_checkpoint_count()
	var taken: int = mode.get_next_checkpoint()
	var all: bool = target > count   # round 1 took them all: only faster wins
	var left: int = (count if all else target) - taken
	if left <= 0 and not all:
		return ["WIN SECURED" if attacking else "THEY HAVE ENOUGH – MATCH LOST", true]
	var what: String = "%d MORE CHECKPOINT%s" % [left, "" if left == 1 else "S"]
	if all:
		var beat: String = ScorePanel._clock(float(mode.get_results()[0]["time_left"]))
		return [("TAKE ALL: %s, FINISH WITH OVER %s LEFT" % [what, beat]) if attacking
				else ("STOP THEM: %s AND OVER %s LEFT WINS IT FOR THEM" % [what, beat]), false]
	return [("%s TO WIN" % what) if attacking else ("STOP THEM: %s AND THEY WIN" % what), false]


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
		outline: int = 6, alpha: float = 1.0) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var x: float = at.x - width * 0.5
	draw_string_outline(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, outline,
			Color(0.0, 0.0, 0.0, 0.8 * alpha))
	draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)
