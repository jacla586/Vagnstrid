class_name SquadRadio
extends Label
## The own squad's radio: plays its calls (RadioData on the squad's data) one at a time
## over the headset (not muffled by the hatch, not positional) and shows them as a
## subtitle. Contacts get a clock direction from the own tank's hull. A call of the same
## kind (and clock hour) isn't repeated within RadioData.repeat_cooldown_s.

@export var views: PlayerViews
@export var color: Color = Color(0.75, 1.0, 0.7, 1.0)
@export var font_size: int = 20

var _player: AudioStreamPlayer
var _squad: Squad
var _queue: Array = []          # [stream, text]
var _last: Dictionary = {}      # call key -> time it was last played
var _time: float = 0.0
var _subtitle_left: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	position.y -= 170.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_color", color)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("outline_size", 6)
	_player = AudioStreamPlayer.new()
	_player.bus = &"Master"
	add_child(_player)
	text = ""


func _process(delta: float) -> void:
	_time += delta
	var tank: Tank = views.get_tank() if views != null else null
	var squad: Squad = tank.squad if tank != null and is_instance_valid(tank.squad) else null
	if squad != _squad:
		if _squad != null and is_instance_valid(_squad) and _squad.radio.is_connected(_on_radio):
			_squad.radio.disconnect(_on_radio)
		_squad = squad
		if _squad != null:
			_squad.radio.connect(_on_radio)
	if not _player.playing and not _queue.is_empty():
		var next: Array = _queue.pop_front()
		_player.stream = next[0]
		_player.volume_db = _squad.data.radio.volume_db if _squad != null and _squad.data.radio != null else 0.0
		if _player.stream != null:
			_player.play()
		text = "Grupp: " + String(next[1])
		var length: float = (next[0] as AudioStream).get_length() if next[0] != null else 2.0
		_subtitle_left = length + (_squad.data.radio.subtitle_extra_s if _squad != null and _squad.data.radio != null else 1.5)
	_subtitle_left -= delta
	if _subtitle_left <= 0.0 and not _player.playing:
		text = ""


func _on_radio(kind: int, at: Vector3) -> void:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == null or _squad == null or _squad.data.radio == null:
		return
	var r: RadioData = _squad.data.radio
	var stream: AudioStream = null
	var line: String = ""
	var key: String = str(kind)
	match kind:
		Squad.RADIO_UNDER_ATTACK:
			stream = r.under_attack
			line = r.under_attack_text
		Squad.RADIO_RETURNING:
			stream = r.returning
			line = r.returning_text
		Squad.RADIO_IN_POSITION:
			stream = r.in_position
			line = r.in_position_text
		Squad.RADIO_AT_FIRE:
			stream = r.at_fire
			line = r.at_fire_text
		Squad.RADIO_ARMOUR, Squad.RADIO_INFANTRY:
			var hour: int = clock_hour(tank.global_transform, at)
			var list: Array[AudioStream] = r.armour if kind == Squad.RADIO_ARMOUR else r.infantry
			stream = list[hour - 1] if list.size() >= hour else null
			var word: String = r.clock_words[hour - 1] if r.clock_words.size() >= hour else str(hour)
			line = (r.armour_text if kind == Squad.RADIO_ARMOUR else r.infantry_text) % word
			key += "/%d" % hour
		_:
			return
	if kind == Squad.RADIO_AT_FIRE:
		# Urgent and always said: first in the queue, no repeat limit.
		_queue.push_front([stream, line])
		while _queue.size() > r.max_queue:
			_queue.pop_back()
		return
	if _time - float(_last.get(key, -INF)) < r.repeat_cooldown_s:
		return
	_last[key] = _time
	_queue.append([stream, line])
	while _queue.size() > r.max_queue:
		_queue.pop_front()


## Clock hour (1..12, 12 = straight ahead) of `point` seen from the tank's hull.
static func clock_hour(hull: Transform3D, point: Vector3) -> int:
	var local: Vector3 = hull.affine_inverse() * point
	var angle: float = atan2(local.x, -local.z)   # 0 ahead, positive to the right
	var hour: int = posmod(roundi(rad_to_deg(angle) / 30.0), 12)
	return 12 if hour == 0 else hour
