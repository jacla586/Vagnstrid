extends SceneTree
## One whole King of the Hill match of bots only, the bots' commander (TeamCommander) on
## for one team and off for the other, as fast as the machine runs it; run many (both ways
## round) and sum the KOTH lines.
##   godot --headless --fixed-fps 30 --path . --script res://tools/ai/koth_match.gd -- \
##       [scenario] [size=N] [level=1|2] [team=0|1] [log] [set=field:value,field:value]
##       [koth=field:value,...] [tag=name]
## set= overrides CommanderData fields for this run (tests of one part at a time), koth= KothData
## fields (e.g. koth=shrink_at_budget_share:0).
## Prints a ZONE line per closed zone (open_s, closed by budget or time, shrink progress and
## radius at the close) and: KOTH level=L cmd_team=T tag=X | score0=S score1=S | zones=Z | winner=W
## | game_s=S | zone_s=mean | by_budget=n/N | shrunk=mean progress at close

var _mode: KothMode
var _level: int = 2
var _team: int = 0
var _data: CommanderData
var _limit_s: float = 4.0 * 3600.0
var _t: float = 0.0
var _tag: String = ""
var _koth_overrides: PackedStringArray = []
var _was_open: bool = false
var _opened_at: float = 0.0
var _last_progress: float = 0.0
var _last_radius: float = 0.0
## [open_s, by_budget, progress] per closed zone
var _zones: Array = []


func _initialize() -> void:
	var scene_path: String = "res://scenes/scenarios/vidingsjo_koth.tscn"
	MatchSettings.load_settings()
	MatchSettings.team_size = 8
	var log: bool = false
	var overrides: PackedStringArray = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("size="):
			MatchSettings.team_size = int(a.substr(5))
		elif a.begins_with("level="):
			_level = int(a.substr(6))
		elif a.begins_with("team="):
			_team = int(a.substr(5))
		elif a == "log":
			log = true
		elif a.begins_with("set="):
			overrides = a.substr(4).split(",", false)
		elif a.begins_with("koth="):
			_koth_overrides = a.substr(5).split(",", false)
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		else:
			scene_path = "res://scenes/scenarios/%s.tscn" % a
	MatchSettings.bot_commander = _level
	KothBots.commander_teams = 1 << _team
	_data = TeamCommander.data_for_setting()   # kept: the cached copy is the one used
	if _data != null:
		_data.log_decisions = log
		for o: String in overrides:
			var kv: PackedStringArray = o.split(":")
			var old: Variant = _data.get(kv[0])
			if old is bool:
				_data.set(kv[0], kv[1] == "true" or kv[1] == "1")
			else:
				_data.set(kv[0], int(kv[1]) if old is int else float(kv[1]))
	var root: Node = (load(scene_path) as PackedScene).instantiate()
	var rig: Node = root.get_node_or_null("PlayerRig")
	if rig != null:   # bots only: no idle player tank on team 0
		root.remove_child(rig)
		rig.free()
	get_root().add_child(root)
	current_scene = root
	_mode = root.find_children("*", "KothMode", true, false)[0] as KothMode
	for o: String in _koth_overrides:
		var kv: PackedStringArray = o.split(":")
		var old_v: Variant = _mode.data.get(kv[0])
		_mode.data.set(kv[0], int(kv[1]) if old_v is int else float(kv[1]))
	process_frame.connect(_frame)


func _frame() -> void:
	_t += 1.0 / 30.0
	if _mode == null:
		return
	var open: bool = _mode.is_zone_open()
	if open and not _was_open:
		_opened_at = _t
	if open:
		_last_progress = _mode.get_shrink_progress()
		_last_radius = _mode.get_radius()
	elif _was_open:
		# The budget runs dry within the tick that closes the zone, so the last frame seen
		# open may still show some left: anything short of the lifetime is the budget (or
		# the match's end, the last zone).
		var by_budget: bool = _t - _opened_at < _mode.data.zone_lifetime_s - 1.0
		_zones.append([_t - _opened_at, by_budget, _last_progress])
		print("ZONE tag=%s n=%d open_s=%.0f by=%s progress=%.2f radius=%.0f" % [_tag, _zones.size(),
				_t - _opened_at, "budget" if by_budget else "time", _last_progress, _last_radius])
	_was_open = open
	if not (_mode.is_over() or _t > _limit_s):
		return
	var zone_s: float = 0.0
	var budget_n: int = 0
	var shrunk: float = 0.0
	for z: Array in _zones:
		zone_s += float(z[0])
		budget_n += 1 if z[1] else 0
		shrunk += float(z[2])
	var n: int = maxi(_zones.size(), 1)
	print("KOTH level=%d cmd_team=%d tag=%s | score0=%.0f score1=%.0f | zones=%d | winner=%d | game_s=%.0f | zone_s=%.0f | by_budget=%d/%d | shrunk=%.2f" % [
			_level, _team, _tag, _mode.get_score(0), _mode.get_score(1), _mode.get_zone_number(),
			_mode.get_winner() if _mode.is_over() else -1, _t, zone_s / n, budget_n, _zones.size(),
			shrunk / n])
	_mode = null
	quit()
