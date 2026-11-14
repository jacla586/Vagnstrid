class_name ModeRadio
extends Node
## Voices for King of the Hill and Bot hunt (`ModeCallsData` on KothData/FreeFightData)
## and the crew's kill banter in every mode (`CrewVoiceData` "Kill banter": the own tank's
## knock-outs from the kill feed, the victim in the KotH zone or the ThunderRoad
## checkpoint for the zone lines). Sound only, through `radio` (SquadRadio); reads only
## what this machine knows (mode state, the kill feed, tank positions), so clients hear the
## same. ThunderRoad's own calls are ThunderPanel's.

const COUNT_HZ: float = 2.0
## A knocked-out enemy is matched to a kill feed line within this long (s).
const KILL_MATCH_S: float = 2.0

@export var views: PlayerViews
@export var radio: SquadRadio

var _time: float = 0.0
var _feed: KillFeed
var _koth: KothMode
var _free: FreeFight
var _started: bool = false
## Start lines already said, by match and round (`claim_start`): a new rig (deploy,
## change tank, respawn online) mustn't greet the match again.
static var _starts_said: Dictionary = {}
var _down: Dictionary = {}            # tank -> [time knocked out, position] (enemies), or true (alive)
var _banter_at: float = -INF
# King of the Hill
var _open: bool = false
var _closing_said: bool = false
var _count_clock := PackedFloat32Array([0.0])
var _count_state: int = 0             # +1 more of ours in the zone, -1 more of theirs
var _count_since: float = 0.0
var _count_said: int = 0
var _count_said_at: float = -INF
var _near_said: bool = false
var _enemy_near_said: bool = false
var _result_said: bool = false
# Bot hunt
var _mates_out: Dictionary = {}       # teammate -> knocked out last frame
var _lost_at: float = -INF
var _alone: bool = false


func _process(delta: float) -> void:
	_time += delta
	var tank: Tank = views.get_tank() if views != null else null
	if radio == null or tank == null:
		return
	if _feed == null:
		_feed = get_tree().get_first_node_in_group(KillFeed.GROUP) as KillFeed
		if _feed != null:
			_feed.entry_added.connect(_on_kill_entry)
	_watch_enemies(tank)
	if KothMode.instance != _koth:
		_connect_koth(KothMode.instance)
	if FreeFight.instance != _free:
		_connect_free(FreeFight.instance)
	var calls: ModeCallsData = _calls()
	if calls == null:
		return
	if not _started and MatchLobby.instance == null:
		_started = true
		if claim_start(0):
			_banter(calls.round_start)
	if _koth != null:
		_watch_koth(tank, calls, delta)
	elif _free != null:
		_watch_free(tank, calls)


## True the first time it is asked for this match (the loaded scene) and round: only
## the first rig with a chosen tank says the start line.
static func claim_start(round_number: int) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var scene: Node = tree.current_scene if tree != null else null
	var key: String = "%d:%d" % [scene.get_instance_id() if scene != null else 0, round_number]
	if _starts_said.has(key):
		return false
	_starts_said[key] = true
	return true


func _calls() -> ModeCallsData:
	if _koth != null and _koth.data != null:
		return _koth.data.calls
	if _free != null and _free.data != null:
		return _free.data.calls
	return null


func _call(streams: Array[AudioStream]) -> void:
	var c: ModeCallsData = _calls()
	if c != null and not streams.is_empty():
		radio.command_call(streams[randi() % streams.size()], c.volume_db)


func _banter(streams: Array[AudioStream]) -> void:
	var c: ModeCallsData = _calls()
	if c != null and not streams.is_empty():
		radio.command_call(streams[randi() % streams.size()], c.banter_volume_db)


# --- Kill banter (every mode) ------------------------------------------------------

## Remembers when and where enemy tanks went down, so a kill feed line can find its victim.
func _watch_enemies(own: Tank) -> void:
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var other := node as Tank
		if other == null or other.team == own.team:
			continue
		if other.is_knocked_out():
			if not (_down.get(other, true) is Array):
				_down[other] = [_time, other.global_position]
		else:
			_down[other] = true


func _on_kill_entry(entry: Array) -> void:
	var own: Tank = views.get_tank() if views != null else null
	if own == null or own.is_knocked_out() or entry.size() < 6:
		return
	var name_: String = own.get_player_name()
	if name_ == "Bot" or String(entry[0]) != name_ or int(entry[2]) != own.team:
		return
	var v: CrewVoiceData = own.data.crew_voice if own.data != null else null
	if v == null or _time - _banter_at < v.banter_cooldown_s:
		return
	var in_zone: bool = _victim_in_zone()
	var streams: Array[AudioStream] = v.kill_zone if in_zone else v.kill
	if streams.is_empty() or randf() >= (v.kill_zone_chance if in_zone else v.kill_chance):
		return
	_banter_at = _time
	radio.command_call(streams[randi() % streams.size()], v.volume_db)


## The latest enemy knocked out (within KILL_MATCH_S) lay in the KotH zone or the next
## ThunderRoad checkpoint's zone.
func _victim_in_zone() -> bool:
	var best: float = -INF
	var at: Vector3 = Vector3.ZERO
	for tank: Variant in _down:
		var row: Variant = _down[tank]
		if row is Array and float(row[0]) > best:
			best = float(row[0])
			at = row[1]
	if _time - best > KILL_MATCH_S:
		return false
	if KothMode.instance != null:
		return KothMode.instance.is_in_zone(at)
	var thunder: ThunderRoadMode = ThunderRoadMode.instance
	if thunder != null:
		var next: int = thunder.get_next_checkpoint()
		return thunder.is_in_checkpoint(at, next) or (next > 0 and thunder.is_in_checkpoint(at, next - 1))
	return false


# --- King of the Hill --------------------------------------------------------------

func _connect_koth(mode: KothMode) -> void:
	_koth = mode
	if mode != null:
		mode.match_over.connect(_on_koth_over)
		_open = mode.is_zone_open()


func _on_koth_over(winner: int) -> void:
	var c: ModeCallsData = _calls()
	var own: Tank = views.get_tank() if views != null else null
	if c == null or own == null or winner < 0 or _result_said:
		return
	_result_said = true
	_banter(c.victory if winner == own.team else c.defeat)


func _watch_koth(own: Tank, c: ModeCallsData, delta: float) -> void:
	if _koth.is_over() or not _koth.has_started():
		return
	var open: bool = _koth.is_zone_open()
	if open and not _open:
		_call(c.zone_open)
		_closing_said = false
		_count_state = 0
		_count_said = 0
	elif not open and _open:
		_call(c.zone_next)
	_open = open
	if open and not _closing_said and _koth.get_shrink_progress() > 0.0 \
			and _koth.get_time_to_next_event() <= c.closing_at_s:
		_closing_said = true
		_call(c.closing)
	var goal: float = _koth.data.score_to_win
	if goal > 0.0:
		if not _near_said and _koth.get_score(own.team) >= goal * c.near_win_share:
			_near_said = true
			_call(c.near_win)
		if not _enemy_near_said and _koth.get_best_other_score(own.team) >= goal * c.near_win_share:
			_enemy_near_said = true
			_call(c.enemy_near_win)
	if open and Ticks.due(_count_clock, delta, COUNT_HZ):
		_count_zone(own, c)


## Who has more tanks in the zone, held count_hold_s: the news once, then not again for
## count_cooldown_s (positions only: every machine sees every tank).
func _count_zone(own: Tank, c: ModeCallsData) -> void:
	var counts: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank != null and not tank.is_knocked_out() and _koth.is_in_zone(tank.global_position):
			counts[tank.team] = int(counts.get(tank.team, 0)) + 1
	var ours: int = int(counts.get(own.team, 0))
	var theirs: int = 0
	for team: Variant in counts:
		if int(team) != own.team:
			theirs = maxi(theirs, int(counts[team]))
	var state: int = 1 if ours > theirs else (-1 if theirs > ours else 0)
	if state != _count_state:
		_count_state = state
		_count_since = _time
		return
	if state == 0 or state == _count_said or _time - _count_since < c.count_hold_s \
			or _time - _count_said_at < c.count_cooldown_s:
		return
	_count_said = state
	_count_said_at = _time
	_call(c.advantage if state > 0 else c.outnumbered)


# --- Bot hunt ----------------------------------------------------------------------

func _connect_free(mode: FreeFight) -> void:
	_free = mode
	if mode != null:
		mode.wave_started.connect(func(_r: int) -> void:
			var c: ModeCallsData = _calls()
			if c != null:
				_call(c.wave_new))
		mode.wave_cleared.connect(func(_r: int) -> void:
			var c: ModeCallsData = _calls()
			if c != null:
				_call(c.wave_cleared))
		mode.match_over.connect(func(_cleared: int) -> void:
			var c: ModeCallsData = _calls()
			if c != null and not _result_said:
				_result_said = true
				_banter(c.defeat))


## Teammates lost, and the own tank left alone.
func _watch_free(own: Tank, c: ModeCallsData) -> void:
	if _free.is_over():
		return
	var mates: int = 0
	var living: int = 0
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var mate := node as Tank
		if mate == null or mate == own or mate.team != own.team:
			continue
		mates += 1
		var out: bool = mate.is_knocked_out()
		if not out:
			living += 1
		if out and not bool(_mates_out.get(mate, true)) and _time - _lost_at >= c.tank_lost_cooldown_s:
			_lost_at = _time
			_call(c.tank_lost)
		_mates_out[mate] = out
	var alone: bool = mates > 0 and living == 0 and not own.is_knocked_out()
	if alone and not _alone:
		_banter(c.alone)
	_alone = alone
