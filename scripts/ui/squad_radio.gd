class_name SquadRadio
extends Node
## The own squad's radio: plays its calls (RadioData on the squad's data) one at a time
## over the headset (not muffled by the hatch, not positional). No subtitles: the game's
## text is English and the Swedish voices are a bonus for those who understand them. Contacts get a clock direction from the own tank's hull. A call of the same
## kind (and clock hour) isn't repeated within RadioData.repeat_cooldown_s.
## The own crew's shouts (TankData.crew_voice: "Vi är träffade!" when a gun round hits,
## "Närträff!" when one lands close) go first in the same queue, then ThunderRoad's
## command calls (`command_call`).

@export var views: PlayerViews

## Queue kinds that are never dropped for an ordinary call (-1 = crew shout, -2 = command).
const _URGENT: Array[int] = [Squad.RADIO_AT_FIRE, Squad.RADIO_AT_HIT, Squad.RADIO_AT_MISS, -1, -2]
const COMMAND: int = -2

var _player: AudioStreamPlayer
var _squad: Squad
var _tank: Tank
var _queue: Array = []          # [stream, volume_db, kind (-1: crew, -2: command)]
var _last: Dictionary = {}      # call key -> time it was last played
var _time: float = 0.0
var _crash_prev: Vector3 = Vector3.INF
var _crash_speeds: Array = []   # [time, ground speed km/h], the last crash_window_s


var _last_near: AudioStream   # the near-miss line said last (not repeated straight after)

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = GameSettings.VOICE_BUS
	add_child(_player)


func _process(delta: float) -> void:
	_time += delta
	var tank: Tank = views.get_tank() if views != null else null
	if tank != _tank:
		if _tank != null and is_instance_valid(_tank):
			if _tank.struck.is_connected(_on_struck):
				_tank.struck.disconnect(_on_struck)
			if _tank.near_missed.is_connected(_on_near_miss):
				_tank.near_missed.disconnect(_on_near_miss)
			if _tank.module_changed.is_connected(_on_module_changed):
				_tank.module_changed.disconnect(_on_module_changed)
			if _tank.commander_wounded.is_connected(_on_commander_wounded):
				_tank.commander_wounded.disconnect(_on_commander_wounded)
			if _tank.mine_hit.is_connected(_on_mine_hit):
				_tank.mine_hit.disconnect(_on_mine_hit)
			if _tank.optics_dirtied.is_connected(_on_optics_dirtied):
				_tank.optics_dirtied.disconnect(_on_optics_dirtied)
		_tank = tank
		if _tank != null:
			_tank.struck.connect(_on_struck)
			_tank.near_missed.connect(_on_near_miss)
			_tank.module_changed.connect(_on_module_changed)
			_tank.commander_wounded.connect(_on_commander_wounded)
			_tank.mine_hit.connect(_on_mine_hit)
			_tank.optics_dirtied.connect(_on_optics_dirtied)
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
		_player.volume_db = float(next[1])
		_player.play()


func _on_radio(kind: int, at: Vector3) -> void:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == null or _squad == null or _squad.data.radio == null:
		return
	var r: RadioData = _squad.data.radio
	var stream: AudioStream = null
	var key: String = str(kind)
	match kind:
		Squad.RADIO_UNDER_ATTACK:
			stream = r.under_attack
		Squad.RADIO_DISMOUNT:
			stream = r.dismount
		Squad.RADIO_RETURNING:
			stream = r.returning
		Squad.RADIO_IN_POSITION:
			stream = r.in_position
		Squad.RADIO_AT_FIRE:
			stream = r.at_fire
		Squad.RADIO_AT_HIT:
			stream = r.at_hit
		Squad.RADIO_AT_MISS:
			stream = r.at_miss
		Squad.RADIO_MINE_LAYING:
			stream = r.mine_laying
		Squad.RADIO_MINE_ARMED:
			stream = r.mine_armed
		Squad.RADIO_MINE_TRIGGERED:
			stream = r.mine_triggered
		Squad.RADIO_ESCORT:
			stream = r.escort
		Squad.RADIO_ARMOUR, Squad.RADIO_INFANTRY:
			var hour: int = clock_hour(tank.global_transform, at)
			var list: Array[AudioStream] = r.armour if kind == Squad.RADIO_ARMOUR else r.infantry
			stream = list[hour - 1] if list.size() >= hour else null
			key += "/%d" % hour
		_:
			return
	if stream == null:
		return
	var entry: Array = [stream, r.volume_db, kind]
	if kind == Squad.RADIO_AT_FIRE:
		# Urgent and always said: first in the queue, no repeat limit.
		_queue.push_front(entry)
		while _queue.size() > r.max_queue:
			_queue.pop_back()
		return
	if kind == Squad.RADIO_AT_HIT or kind == Squad.RADIO_AT_MISS:
		# Always said, straight after its "Skott kommer!" if that is still waiting.
		var slot: int = 0
		while slot < _queue.size() and int(_queue[slot][2]) == Squad.RADIO_AT_FIRE:
			slot += 1
		_queue.insert(slot, entry)
		while _queue.size() > r.max_queue + 1:
			_queue.pop_back()
		return
	if _time - float(_last.get(key, -INF)) < r.repeat_cooldown_s:
		return
	_last[key] = _time
	_queue.append(entry)
	# Too many: drop the oldest ordinary call (AT calls and crew shouts stay).
	while _queue.size() > r.max_queue:
		var drop: int = -1
		for j: int in _queue.size():
			if not _URGENT.has(int(_queue[j][2])):
				drop = j
				break
		_queue.remove_at(drop)


func _on_struck(_outcome: int, _direction: Vector3) -> void:
	var v: CrewVoiceData = _tank.data.crew_voice if _tank != null else null
	if v != null:
		var rares: Array[AudioStream] = v.hit_rare_more.duplicate()
		if v.hit_rare != null:
			rares.append(v.hit_rare)
		var rare: bool = not rares.is_empty() and randf() < v.hit_rare_chance
		_crew_call("hit", rares.pick_random() if rare else v.hit, v)


## A hard crash (CrewVoiceData "Crash"): the own tank's ground speed, from its position (so a
## client's puppet too), falls by crash_drop_kmh within crash_window_s from crash_min_kmh up.
## Not after a hit or a mine (they stop tanks too), nor across a respawn jump.
func _physics_process(delta: float) -> void:
	var v: CrewVoiceData = _tank.data.crew_voice if _tank != null and is_instance_valid(_tank) else null
	if v == null or v.crash.is_empty() or delta <= 0.0 or _tank.is_knocked_out():
		_crash_prev = Vector3.INF
		_crash_speeds.clear()
		return
	var pos: Vector3 = _tank.global_position
	var prev: Vector3 = _crash_prev
	_crash_prev = pos
	if prev == Vector3.INF or pos.distance_to(prev) > 15.0:
		_crash_speeds.clear()
		return
	var kmh: float = Vector2(pos.x - prev.x, pos.z - prev.z).length() / delta * 3.6
	_crash_speeds.append([_time, kmh])
	while not _crash_speeds.is_empty() and _time - float(_crash_speeds[0][0]) > v.crash_window_s:
		_crash_speeds.pop_front()
	var top: float = 0.0
	for row: Array in _crash_speeds:
		top = maxf(top, float(row[1]))
	if top < v.crash_min_kmh or top - kmh < v.crash_drop_kmh:
		return
	_crash_speeds.clear()
	for key: String in ["crew/hit", "crew/mine"]:
		if _time - float(_last.get(key, -INF)) < 1.5:
			return
	if _time - float(_last.get("crew/crash", -INF)) < v.crash_cooldown_s:
		return
	if randf() >= v.crash_chance:
		_last["crew/crash"] = _time   # a crash that got no line still waits out the cooldown
		return
	var tutorial: TutorialMode = TutorialMode.instance
	var line: AudioStream = tutorial.data.crash if tutorial != null and tutorial.data.crash != null \
			else v.crash.pick_random()
	_crew_call("crash", line, v)


## A mine: its own call, and the "hit" call the struck right after would give is held back.
func _on_mine_hit() -> void:
	var v: CrewVoiceData = _tank.data.crew_voice if _tank != null else null
	if v == null or v.mine == null:
		return
	var rare: bool = v.mine_rare != null and randf() < v.mine_rare_chance
	_crew_call("mine", v.mine_rare if rare else v.mine, v)
	_last["crew/hit"] = _time


## Dirt on the optics from a burst: now and then the crew swears about it, after "Vi är träffade!".
func _on_optics_dirtied(_amount: float) -> void:
	var v: CrewVoiceData = _tank.data.crew_voice if _tank != null else null
	if v != null and v.he_dirt != null and randf() < v.he_dirt_chance:
		_crew_call("he", v.he_dirt, v, true)


func _on_near_miss(_direction: Vector3) -> void:
	var v: CrewVoiceData = _tank.data.crew_voice if _tank != null else null
	if v == null or _time - float(_last.get("crew/near", -INF)) < v.near_miss_cooldown_s:
		return
	var lines: Array[AudioStream] = []
	if v.near_miss != null:
		lines.append(v.near_miss)
	lines.append_array(v.near_miss_more)
	if lines.size() > 1:
		lines.erase(_last_near)   # never the same line twice in a row
	if lines.is_empty():
		return
	_last_near = lines[randi() % lines.size()]
	_crew_call("near", _last_near, v)


func _on_module_changed(id: StringName, state: int) -> void:
	var v: CrewVoiceData = _tank.data.crew_voice if _tank != null else null
	if v == null or state == TankDamage.State.OK:
		return
	match id:
		&"driver": _crew_call("driver", v.driver_hit, v, true)
		&"gunner": _crew_call("gunner", v.gunner_hit, v, true)


func _on_commander_wounded() -> void:
	var v: CrewVoiceData = _tank.data.crew_voice if _tank != null else null
	if v != null:
		_crew_call("commander", v.commander_hit, v, true)


## A crew shout: urgent, so it goes first; the same one not again within its cooldown.
## after_crew: behind the crew shouts already waiting ("Vi är träffade!" first, then who).
func _crew_call(key: String, stream: AudioStream, v: CrewVoiceData,
		after_crew: bool = false) -> void:
	if stream == null:
		return
	if _time - float(_last.get("crew/" + key, -INF)) < v.repeat_cooldown_s:
		return
	_last["crew/" + key] = _time
	var at: int = 0
	if after_crew:
		while at < _queue.size() and int(_queue[at][2]) == -1:
			at += 1
	_queue.insert(at, [stream, v.volume_db, -1])
	# Keep the queue short, but never drop a command call (ThunderRoad, the tutorial's instructor).
	var i: int = _queue.size() - 1
	while _queue.size() > 3 and i >= 0:
		if int(_queue[i][2]) != COMMAND:
			_queue.remove_at(i)
		i -= 1


## A command call (ThunderRoad, `ThunderPanel`): after the crew shouts and the other
## command calls waiting, ahead of the squad's calls. Never dropped for them.
func command_call(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	var at: int = 0
	while at < _queue.size() and (int(_queue[at][2]) == -1 or int(_queue[at][2]) == COMMAND):
		at += 1
	_queue.insert(at, [stream, volume_db, COMMAND])


## Clock hour (1..12, 12 = straight ahead) of `point` seen from the tank's hull.
static func clock_hour(hull: Transform3D, point: Vector3) -> int:
	var local: Vector3 = hull.affine_inverse() * point
	var angle: float = atan2(local.x, -local.z)   # 0 ahead, positive to the right
	var hour: int = posmod(roundi(rad_to_deg(angle) / 30.0), 12)
	return 12 if hour == 0 else hour
