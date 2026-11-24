extends SceneTree
## How fast the attacking bots get to the checkpoints in a ThunderRoad match (bots only, as fast
## as the machine runs it). Every `every` s of game time a PACE line: the next checkpoint, its
## clock, the living attackers' distance along the road short of it (mean / nearest), how many
## move, their jobs (dev/asl/res/snp/out), bounding states (move/watch/hold) and waiting for a
## wave; a CAPTURE line per checkpoint taken (time since the round or the last capture); a
## ROUND line per round (checkpoints, time used).
##   godot --headless --fixed-fps 30 --path . --script res://tools/ai/thunder_pace_probe.gd -- \
##       [scenario] [size=N] [rounds=1|2] [every=15] [tag=name] [nodrive] [nodef]
## nodrive: ThunderRoadBots.drive_up off (attackers bound all the way, as before 2026-11-24).
## nodef: the defenders are kept knocked out (by rule), so the legs measure the attackers' driving alone.

var _mode: ThunderRoadMode
var _t: float = 0.0
var _round_t: float = 0.0
var _last_capture_t: float = 0.0
var _next_log: float = 0.0
var _every: float = 15.0
var _rounds: int = 1
var _tag: String = ""
var _captures: Array[float] = []
var _limit_s: float = 3.0 * 3600.0
var _no_defenders: bool = false
var _debug: bool = false


func _initialize() -> void:
	var scene_path: String = "res://scenes/scenarios/vidingsjo_xl_thunder.tscn"
	MatchSettings.load_settings()
	MatchSettings.team_size = 6
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("size="):
			MatchSettings.team_size = int(a.substr(5))
		elif a.begins_with("rounds="):
			_rounds = int(a.substr(7))
		elif a.begins_with("every="):
			_every = float(a.substr(6))
		elif a.begins_with("tag="):
			_tag = a.substr(4)
		elif a == "nodrive":
			ThunderRoadBots.drive_up = false
		elif a == "nodef":
			_no_defenders = true
		elif a == "debug":
			_debug = true
		else:
			scene_path = "res://scenes/scenarios/%s.tscn" % a
	var root: Node = (load(scene_path) as PackedScene).instantiate()
	var rig: Node = root.get_node_or_null("PlayerRig")
	if rig != null:   # bots only
		root.remove_child(rig)
		rig.free()
	get_root().add_child(root)
	current_scene = root
	_mode = root.find_children("*", "ThunderRoadMode", true, false)[0] as ThunderRoadMode
	_mode.checkpoint_taken.connect(_on_taken)
	_mode.round_started.connect(_on_round_started)
	_mode.round_over.connect(_on_round_over)
	process_frame.connect(_frame)


func _on_round_started(round_number: int, attack_team: int) -> void:
	_round_t = _t
	_last_capture_t = _t
	_next_log = _t
	print("ROUND_START tag=%s r=%d att=%d t=%.0f" % [_tag, round_number, attack_team, _t])


func _on_taken(index: int) -> void:
	_captures.append(_t - _last_capture_t)
	print("CAPTURE tag=%s r=%d cp=%d after=%.0f s round_t=%.0f" % [_tag, _mode.get_round(), index + 1,
			_t - _last_capture_t, _t - _round_t])
	_last_capture_t = _t


func _on_round_over(round_number: int, result: Dictionary) -> void:
	print("ROUND tag=%s r=%d cps=%d round_t=%.0f captures=%s" % [_tag, round_number,
			int(result.get("checkpoints", -1)), _t - _round_t, str(_captures)])
	_captures.clear()
	if round_number >= _rounds:
		_mode = null
		quit()


func _frame() -> void:
	_t += 1.0 / 30.0
	if _mode == null:
		return
	if _t > _limit_s or _mode.is_over():
		print("END tag=%s t=%.0f" % [_tag, _t])
		_mode = null
		quit()
		return
	if _no_defenders and _mode.get_round() > 0 and not _mode.is_in_break():
		var att: int = _mode.get_attack_team()
		for node: Node in get_root().get_tree().get_nodes_in_group("tanks"):
			var tank := node as Tank
			if tank != null and tank.team != att and not tank.is_knocked_out() and not tank.net_puppet:
				tank.knock_out_by_rule()
	if _mode.get_round() == 0 or _mode.is_in_break() or _t < _next_log:
		return
	_next_log = _t + _every
	var next: int = _mode.get_next_checkpoint()
	if next >= _mode.get_checkpoint_count():
		return
	var cp_s: float = _mode.get_checkpoint_s(next)
	var team: int = _mode.get_attack_team()
	var bots: ThunderRoadBots = ThunderRoadBots.instance
	var alive: int = 0
	var moving: int = 0
	var waiting: int = 0
	var sum_d: float = 0.0
	var min_d: float = INF
	var jobs: Array[int] = [0, 0, 0, 0, 0]   # OUTSIDE, SNIPER, RESERVE, DEVELOP, ASSAULT
	var bound: Array[int] = [0, 0, 0]
	for node: Node in get_root().get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or tank.team != team:
			continue
		if _mode.is_waiting_for_wave(tank):
			waiting += 1
			continue
		if tank.is_knocked_out():
			continue
		alive += 1
		var d: float = cp_s - _mode.project(tank.global_position).x
		sum_d += d
		min_d = minf(min_d, d)
		if tank.linear_velocity.length() > 2.0:
			moving += 1
		if bots != null:
			for bot: BotController in bots._bots:
				if bot.tank == tank:
					jobs[bots._job_of(bot)] += 1
					if bots._bound.has(bot):
						bound[int(bots._bound[bot])] += 1
					if _debug and bots._job_of(bot) == ThunderRoadBots.Job.DEVELOP:
						var at: Vector2 = _mode.project(tank.global_position)
						var lg: Vector3 = bots._line_goal.get(bot, Vector3.INF)
						print("  BOT %s pos=(%.0f,%.0f) s=%.0f off=%.0f v=%.1f bound=%s travel=%s line=(%.0f,%.0f) path_goal=(%.0f,%.0f) order %d/%d pending=%d" % [
								tank.name, tank.global_position.x, tank.global_position.z, at.x, at.y,
								tank.linear_velocity.length(), str(bots._bound.get(bot, -1)),
								str(bots._travelling(bot, bot._tactics())), lg.x, lg.z, bot._path_goal.x,
								bot._path_goal.z, bot._order_index, bot._orders.size(), bot._pending_plan.size()])
	print("PACE tag=%s r=%d t=%.0f cp=%d left=%.0f alive=%d wait=%d dist_mean=%.0f dist_min=%.0f moving=%d jobs out/snp/res/dev/asl=%s bound mv/wt/hd=%s assault=%s paused=%s" % [
			_tag, _mode.get_round(), _t - _round_t, next + 1, _mode.get_time_left(), alive, waiting,
			sum_d / maxf(alive, 1), min_d, moving, str(jobs), str(bound),
			str(bots != null and bots._assault.has(team)), str(_mode.is_paused())])
