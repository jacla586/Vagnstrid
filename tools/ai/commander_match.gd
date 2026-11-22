extends SceneTree
## One whole ThunderRoad match of bots only, the bots' commander (TeamCommander) on for one
## team and off for the other, as fast as the machine runs it. Both teams attack once on
## the same route (round 1 team 0, round 2 team 1), so the commander team's attack and the
## other's compare directly; run many (both ways round) and sum the MATCH lines.
##   godot --headless --fixed-fps 30 --path . --script res://tools/ai/commander_match.gd -- \
##       [scenario] [size=N] [level=1|2] [team=0|1] [log] [set=field:value,field:value] [tag=name]
## set= overrides CommanderData fields for this run (tests of one part at a time).
## Prints: MATCH level=L cmd_team=T r1 att=A cps=N tl=S | r2 att=A cps=N tl=S | winner=W

var _mode: ThunderRoadMode
var _level: int = 2
var _team: int = 0
var _data: CommanderData
var _limit_s: float = 4.0 * 3600.0
var _t: float = 0.0
var _tag: String = ""


func _initialize() -> void:
	var scene_path: String = "res://scenes/scenarios/vidingsjo_thunder_red.tscn"
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
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		else:
			scene_path = "res://scenes/scenarios/%s.tscn" % a
	MatchSettings.bot_commander = _level
	ThunderRoadBots.commander_teams = 1 << _team
	_data = TeamCommander.data_for_setting()   # kept: the cached copy is the one used
	if _data != null:
		_data.log_decisions = log
		for o: String in overrides:
			var kv: PackedStringArray = o.split(":")
			var old: Variant = _data.get(kv[0])
			_data.set(kv[0], int(kv[1]) if old is int else float(kv[1]))
	var root: Node = (load(scene_path) as PackedScene).instantiate()
	var rig: Node = root.get_node_or_null("PlayerRig")
	if rig != null:   # bots only: no idle player tank on team 0
		root.remove_child(rig)
		rig.free()
	get_root().add_child(root)
	current_scene = root
	_mode = root.find_children("*", "ThunderRoadMode", true, false)[0] as ThunderRoadMode
	process_frame.connect(_frame)


func _frame() -> void:
	_t += 1.0 / 30.0
	if _mode == null or not (_mode.is_over() or _t > _limit_s):
		return
	var line: String = "MATCH level=%d cmd_team=%d tag=%s" % [_level, _team, _tag]
	for i: int in _mode.get_results().size():
		var r: Dictionary = _mode.get_results()[i]
		line += " | r%d att=%d cps=%d tl=%.0f" % [i + 1, int(r["attack_team"]), int(r["checkpoints"]),
				float(r["time_left"])]
	line += " | winner=%d | game_s=%.0f" % [_mode.get_winner() if _mode.is_over() else -1, _t]
	print(line)
	_mode = null
	quit()
