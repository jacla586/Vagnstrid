class_name TeamCommander
extends RefCounted
## A team's commander for its bots (2026-11-22): reads the fight by lanes across the front
## from what the team may know (own tanks, enemies its bots have seen or had reported, the
## public kill feed) and decides where the effort goes and what threats need an answer; the
## bot directors (ThunderRoadBots, later KothBots) carry it out. Bots only: it never orders
## or shows anything to players. Level and on/off: MatchSettings.bot_commander ->
## CommanderData (for_setting).
##
## The directors act on it: lanes, hunts and guards, the push and the defence (CommanderData).

const LANES: int = 3
const LANE_NAMES: PackedStringArray = ["left", "centre", "right"]

var team: int = -1
var data: CommanderData

## The decided main effort: lane 0 left, 1 centre, 2 right (along the attack direction);
## -1 none yet.
var main_lane: int = -1
## Defending: the lane with the most known enemies (CommanderData.threat_min_enemies), held
## main_hold_s; -1 none yet.
var threat_lane: int = -1
## Known enemies that knocked own tanks out from far (CommanderData.long_range_m).
var snipers: PackedVector3Array = PackedVector3Array()
## Known enemies on the team's flank or behind it.
var flankers: PackedVector3Array = PackedVector3Array()

## The picture per lane at the last think.
var own: PackedInt32Array = PackedInt32Array([0, 0, 0])
var enemies: PackedInt32Array = PackedInt32Array([0, 0, 0])
var losses: PackedInt32Array = PackedInt32Array([0, 0, 0])

var _think_wait: float = 0.0
var _main_since: float = -INF
var _main_losses_at_pick: int = 0
var _threat_since: float = -INF


func _init(team_: int, data_: CommanderData) -> void:
	team = team_
	data = data_


## The commander for the current setting, or null when off.
static func data_for_setting() -> CommanderData:
	MatchSettings.load_settings()
	var path: String = MatchSettings.commander_path()
	return load(path) as CommanderData if path != "" else null


## A new objective (checkpoint, zone, round): the main effort is chosen afresh.
func reset() -> void:
	main_lane = -1
	_main_since = -INF
	threat_lane = -1
	_threat_since = -INF
	_think_wait = 0.0
	snipers.clear()
	flankers.clear()


## Thinks every CommanderData.think_interval_s. `own_tanks`: the team's living tanks'
## positions in the picture; `known`: known enemies' positions in it; `kos`: the kill feed
## (TeamSituation.KnockoutLog); `lane_of`(point) -> 0..2; `along`(point) -> metres along
## the attack direction. True when it thought (new decisions).
func think(delta: float, clock: float, own_tanks: PackedVector3Array, known: PackedVector3Array,
		kos: TeamSituation.KnockoutLog, lane_of: Callable, along: Callable) -> bool:
	_think_wait -= delta
	if _think_wait > 0.0:
		return false
	_think_wait = data.think_interval_s
	own = PackedInt32Array([0, 0, 0])
	enemies = PackedInt32Array([0, 0, 0])
	losses = PackedInt32Array([0, 0, 0])
	var own_along: float = 0.0
	for p: Vector3 in own_tanks:
		own[int(lane_of.call(p))] += 1
		own_along += float(along.call(p))
	if not own_tanks.is_empty():
		own_along /= own_tanks.size()
	for p: Vector3 in known:
		enemies[int(lane_of.call(p))] += 1
	snipers.clear()
	for entry: Array in kos.entries:
		if int(entry[1]) != team or clock - float(entry[0]) > data.loss_window_s or entry.size() < 5:
			continue
		var at: Vector3 = entry[3]
		var by: Vector3 = entry[4]
		losses[int(lane_of.call(at))] += 1
		if by.is_finite() and at.distance_to(by) >= data.long_range_m:
			snipers.append(by)
	flankers.clear()
	if not own_tanks.is_empty():
		for p: Vector3 in known:
			if float(along.call(p)) < own_along - data.flank_behind_m:
				flankers.append(p)
	_choose_main(clock)
	_choose_threat(clock)
	if data.log_decisions:
		print("CMD team %d t=%.0f %s" % [team, clock, describe()])
	return true


func _choose_main(clock: float) -> void:
	var best: int = 1
	var best_score: float = INF
	for lane: int in LANES:
		var score: float = enemies[lane] * data.enemy_weight + losses[lane] * data.loss_weight \
				- own[lane] * data.own_weight
		if lane == 1:
			score -= 0.01   # ties: the middle
		if score < best_score:
			best_score = score
			best = lane
	if main_lane < 0:
		_pick(best, clock)
		return
	var bled: bool = losses[main_lane] - _main_losses_at_pick >= data.switch_after_losses
	if best != main_lane and (bled or clock - _main_since >= data.main_hold_s):
		_pick(best, clock)


func _choose_threat(clock: float) -> void:
	var best: int = -1
	var most: int = data.threat_min_enemies - 1
	for lane: int in LANES:
		if enemies[lane] > most:
			most = enemies[lane]
			best = lane
	if best < 0 or best == threat_lane:
		return   # nobody known enough: the last threat stands
	if threat_lane < 0 or clock - _threat_since >= data.main_hold_s:
		threat_lane = best
		_threat_since = clock


func _pick(lane: int, clock: float) -> void:
	main_lane = lane
	_main_since = clock
	_main_losses_at_pick = losses[lane]


func describe() -> String:
	return "main %s threat %s | own %s enemies %s losses %s | snipers %d flankers %d" % [
		LANE_NAMES[main_lane] if main_lane >= 0 else "-",
		LANE_NAMES[threat_lane] if threat_lane >= 0 else "-", own, enemies, losses,
		snipers.size(), flankers.size()]
