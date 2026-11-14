class_name TutorialMode
extends Node
## The tutorial (TUTORIAL_PLAN.md; node `Tutorial` in scenes/scenarios/vidingsjo_tutorial.tscn,
## offline only, no lobby: the map's PlayerRig plays). Runs TutorialData's stages in order:
## each has a goal checked here, an English instruction (TutorialPanel) and the instructor's
## Swedish line (through the rig's SquadRadio). Marks, targets and bots are placed round the
## player when a lesson starts (open ground, in sight from the commander's eye, in a cone
## ahead), so the lessons work wherever the tank stands. Holding skip_tutorial_step for
## TutorialData.skip_hold_s skips a lesson. Knocked out or overturned, the tank comes back
## where it last stood upright. The last lesson ends in TRAINING COMPLETE.

const SETTINGS_PATH: String = "user://settings.cfg"
const SPOT_TRIES: int = 80
const SIGHT_MASK: int = 1 | Vision.LAYER_VISION_BLOCKER
const MARKER_HEIGHT_M: float = 40.0

static var instance: TutorialMode

@export var data: TutorialData

var _stage: int = -1
var _stage_time: float = 0.0
var _done_left: float = -1.0
var _skip_held: float = 0.0
var _finished: bool = false
var _panel: TutorialPanel

var _views: PlayerViews
var _tank: Tank          # the player's, watched for signals
var _squad: Squad
var _safe: Transform3D
var _has_safe: bool = false
var _safe_clock: float = 0.0
var _down_time: float = 0.0
var _respawn_left: float = -1.0

var _marker: Node3D
var _marker_at: Vector3
var _target: Tank        # binoculars, spotting, gunnery
var _heavy: Tank         # ammunition
var _attacker: Tank      # smoke
var _final: Array[Tank] = []
var _bots: Dictionary = {}   # Tank -> BotController
var _serial: int = 0
var _hunt_clock: float = 0.0

# Goal flags, reset when a stage starts.
var _spotted: bool = false
var _hit: bool = false
var _stopped: bool = false
var _mine_armed: bool = false
var _smoke_used: bool = false
var _aim_time: float = 0.0
var _hidden_time: float = 0.0
var _last_short: float = -INF
var _clock: float = 0.0
var _stage_origin: Vector3


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	# The map's own bots and the plain respawn don't play here.
	var parent: Node = get_parent()
	var enemies: Node = parent.get_node_or_null("Enemies")
	if enemies != null:
		for child: Node in enemies.get_children():
			enemies.remove_child(child)
			child.queue_free()
	var respawn: Node = parent.get_node_or_null("PlayerRespawn")
	if respawn != null:
		respawn.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_panel = TutorialPanel.new()
	layer.add_child(_panel)


# --- Flow ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	_find_player()
	if _tank == null or _finished:
		return
	if _stage < 0:
		if data.start_position != Vector3.ZERO:
			var at: Vector3 = _open_near(data.start_position, 60.0)
			if at == Vector3.INF:
				var g: Dictionary = KothMode.ground_hit(get_viewport().world_3d, data.start_position)
				at = (g["position"] as Vector3 if not g.is_empty() else data.start_position) \
						+ Vector3.UP * KothMode.SPAWN_LIFT_M
			KothMode.place_tank(_tank, Transform3D(Basis(Vector3.UP, deg_to_rad(data.start_yaw_deg)), at))
		_say(data.welcome)
		_begin(0)
		return
	# Hits harm nothing until the final test (the smoke lesson's attacker only shakes you).
	_tank.damage_immune = data.steps[_stage].goal != TutorialStepData.Goal.KNOCK_OUT_ALL
	_stage_time += delta
	_update_skip(delta)
	_update_respawn(delta)
	if _respawn_left >= 0.0:
		return
	_update_final_hunt(delta)
	if _done_left >= 0.0:
		_done_left -= delta
		if _done_left < 0.0:
			_begin(_stage + 1)
		return
	if _goal_met(delta):
		var step: TutorialStepData = data.steps[_stage]
		_say(step.done_voice)
		_panel.show_done()
		_done_left = data.done_pause_s


func _begin(index: int) -> void:
	if index >= data.steps.size():
		_finish()
		return
	var new_lesson: bool = _stage < 0 or data.steps[index].lesson != data.steps[_stage].lesson
	_stage = index
	_stage_time = 0.0
	_done_left = -1.0
	_spotted = false
	_hit = false
	_stopped = false
	_mine_armed = false
	_smoke_used = false
	_aim_time = 0.0
	_hidden_time = 0.0
	_stage_origin = _tank.global_position if _tank != null else Vector3.ZERO
	var step: TutorialStepData = data.steps[index]
	if new_lesson:
		_setup_lesson(step.lesson)
	if step.goal == TutorialStepData.Goal.DRIVE_TO:
		_place_marker()
	_say(step.voice)
	_panel.show_step(step.lesson, _lesson_count(), step.title, ControlsPanel.expand(step.text))


func _lesson_count() -> int:
	var n: int = 0
	for s: TutorialStepData in data.steps:
		n = maxi(n, s.lesson)
	return n


## The first stage of the next lesson (or the end).
func _skip_lesson() -> void:
	var lesson: int = data.steps[_stage].lesson
	var i: int = _stage
	while i < data.steps.size() and data.steps[i].lesson == lesson:
		i += 1
	_say(data.skip)
	_begin(i)


func _update_skip(delta: float) -> void:
	if Input.is_action_pressed("skip_tutorial_step"):
		_skip_held += delta
		if _skip_held >= data.skip_hold_s:
			_skip_held = 0.0
			_panel.set_skip_progress(0.0)
			_skip_lesson()
			return
	else:
		_skip_held = 0.0
	_panel.set_skip_progress(_skip_held / data.skip_hold_s)


func _finish() -> void:
	_finished = true
	_clear_marker()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("tutorial", "done", true)
	cfg.save(SETTINGS_PATH)
	_panel.show_end(data.end_title, ControlsPanel.expand(data.end_text), data.next_scenario)


static func is_done() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SETTINGS_PATH) == OK and bool(cfg.get_value("tutorial", "done", false))


# --- Lessons: what each needs in the world --------------------------------------------

func _setup_lesson(lesson: int) -> void:
	_clear_marker()
	var goals: Array[int] = []
	for s: TutorialStepData in data.steps:
		if s.lesson == lesson:
			goals.append(s.goal)
	var needs_target: bool = goals.has(TutorialStepData.Goal.BINOCULARS_ON_TARGET) or goals.has(TutorialStepData.Goal.SPOT_TARGET) \
			or goals.has(TutorialStepData.Goal.HIT_TARGET)
	if not needs_target:
		_remove(_target)
		_target = null
	elif _target == null or not is_instance_valid(_target) or _target.is_knocked_out():
		_remove(_target)
		_target = _spawn(_place_for(lesson, TutorialStepData.Goal.BINOCULARS_ON_TARGET,
				data.target_min_m, data.target_max_m, true, true),
				data.target_config, null)
		_target.hit_recorded.connect(func(_r: HitRecord) -> void: _hit = true)
	if not goals.has(TutorialStepData.Goal.STOP_TARGET):
		_remove(_heavy)
		_heavy = null
	elif _heavy == null or not is_instance_valid(_heavy):
		_heavy = _spawn(_place_for(lesson, TutorialStepData.Goal.STOP_TARGET,
				data.heavy_min_m, data.heavy_max_m, true, false),
				data.heavy_config, null)
		_heavy.module_changed.connect(func(id: StringName, state: int) -> void:
			if String(id).begins_with("track") and state == TankDamage.State.DESTROYED:
				_stopped = true)
	if not goals.has(TutorialStepData.Goal.SMOKE_AND_HIDE):
		_remove(_attacker)
		_attacker = null
	elif _attacker == null or not is_instance_valid(_attacker):
		# Ahead of the turret, so the smoke (fired ahead of it) lands between.
		var turret_dir := Vector3(-sin(_tank.get_turret_global_yaw()), 0.0, -cos(_tank.get_turret_global_yaw()))
		_attacker = _spawn(_find_spot(data.attacker_min_m, data.attacker_max_m, true, false, true,
				turret_dir, 20.0),
				_pick_config(), data.bot_crew)
	if goals.has(TutorialStepData.Goal.KNOCK_OUT_ALL) and _final.is_empty():
		for i: int in data.final_count:
			_final.append(_spawn(_place_for(lesson, TutorialStepData.Goal.KNOCK_OUT_ALL,
					data.final_min_m, data.final_max_m, false, true),
					_pick_config(), data.bot_crew))
		_hunt_clock = data.hunt_every_s * 0.5


## Where a lesson's tank goes: in the area of the stage with `goal` when the data gives one
## (in sight of the commander if it can be), else round the tank.
func _place_for(_lesson: int, goal: int, min_m: float, max_m: float, sight: bool, cover: bool) -> Vector3:
	for st: TutorialStepData in data.steps:
		if st.goal == goal and st.area != Vector2.ZERO:
			return _find_in_area(st.area, st.area_radius_m, sight, cover)
	return _find_spot(min_m, max_m, sight, cover)


## The current stage's circle for the maps: [centre (x, z), radius, label], or [] for none.
func get_map_area() -> Array:
	if _stage < 0 or _finished or _done_left >= 0.0 or _stage >= data.steps.size():
		return []
	var st: TutorialStepData = data.steps[_stage]
	if st.area == Vector2.ZERO or st.area_radius_m <= 0.0:
		return []
	return [st.area, st.area_radius_m, st.area_label]


func _pick_config() -> TankConfig:
	return data.bot_configs.pick_random() if not data.bot_configs.is_empty() else data.target_config


# --- Goals ---------------------------------------------------------------------------

func _goal_met(delta: float) -> bool:
	var step: TutorialStepData = data.steps[_stage]
	match step.goal:
		TutorialStepData.Goal.DRIVE_TO:
			var d := Vector2(_tank.global_position.x - _marker_at.x, _tank.global_position.z - _marker_at.z)
			if d.length() <= data.marker_radius_m:
				_clear_marker()
				return true
		TutorialStepData.Goal.HATCH_OPEN:
			return _tank.get_hatch_progress() >= 1.0
		TutorialStepData.Goal.WAIT:
			return _stage_time >= step.wait_s
		TutorialStepData.Goal.HATCH_CLOSED:
			return _tank.get_hatch_progress() <= 0.0
		TutorialStepData.Goal.BINOCULARS_ON_TARGET:
			_aim_time = _aim_time + delta if _binoculars_on(_target) else 0.0
			return _aim_time >= data.binocular_hold_s
		TutorialStepData.Goal.SPOT_TARGET:
			return _spotted
		TutorialStepData.Goal.HIT_TARGET:
			return _hit
		TutorialStepData.Goal.STOP_TARGET:
			return _stopped or (_heavy != null and is_instance_valid(_heavy) and _heavy.is_knocked_out())
		TutorialStepData.Goal.SQUAD_IN_POSITION:
			if _squad == null or _squad.get_state() != Squad.State.HOLDING:
				return false
			if step.area == Vector2.ZERO:
				return true
			var leader: Node3D = _squad.get_leader()
			return leader != null and Vector2(leader.global_position.x, leader.global_position.z) \
					.distance_to(step.area) <= step.area_radius_m + 25.0
		TutorialStepData.Goal.MINE_LAID:
			return _mine_armed
		TutorialStepData.Goal.SQUAD_MOUNTED:
			return _squad != null and _squad.is_mounted()
		TutorialStepData.Goal.SMOKE_AND_HIDE:
			if _attacker == null or not is_instance_valid(_attacker) or _attacker.is_knocked_out():
				return true
			var moved := Vector2(_tank.global_position.x - _stage_origin.x, _tank.global_position.z - _stage_origin.z)
			var hidden: bool = _smoke_used and moved.length() >= data.retreat_m and not _seen_by(_attacker)
			_hidden_time = _hidden_time + delta if hidden else 0.0
			return _hidden_time >= data.hide_hold_s
		TutorialStepData.Goal.KNOCK_OUT_ALL:
			for t: Tank in _final:
				if is_instance_valid(t) and not t.is_knocked_out():
					return false
			return true
	return false


func _binoculars_on(target: Tank) -> bool:
	if target == null or not is_instance_valid(target) or _views == null:
		return false
	if _views.get_overlay_mode() != PlayerViews.OverlayMode.BINOCULARS:
		return false
	var cam: Camera3D = _views.get_view_camera()
	if cam == null:
		return false
	var to: Vector3 = target.global_position + Vector3.UP - cam.global_position
	return rad_to_deg((-cam.global_basis.z).angle_to(to)) <= data.binocular_aim_deg


## The attacker's commander sees a part of the player's tank (smoke and terrain block).
func _seen_by(viewer: Tank) -> bool:
	var eye: Vector3 = viewer.get_commander_eye_position()
	var world: World3D = get_viewport().world_3d
	var exclude: Array[RID] = [viewer.get_rid(), viewer.get_commander_hitbox().get_rid()]
	for p: Vector3 in _tank.get_spot_points():
		if Vision.has_line_of_sight(world, eye, _tank.global_transform * p, _tank, exclude):
			return true
	return false


# --- The player ----------------------------------------------------------------------

func _find_player() -> void:
	if _views == null or not is_instance_valid(_views):
		_views = null
		for child: Node in get_parent().get_children():
			var v := child.get_node_or_null("PlayerViews") as PlayerViews
			if v != null:
				_views = v
				break
	var tank: Tank = _views.get_tank() if _views != null else null
	if tank != _tank:
		if _tank != null and is_instance_valid(_tank):
			_tank.spotted.disconnect(_on_spotted)
			_tank.fired.disconnect(_on_fired)
			_tank.smoke_launched.disconnect(_on_smoke)
		_tank = tank
		if _tank != null:
			_tank.spotted.connect(_on_spotted)
			_tank.fired.connect(_on_fired)
			_tank.smoke_launched.connect(_on_smoke)
	var squad: Squad = _tank.squad if _tank != null and is_instance_valid(_tank.squad) else null
	if squad != _squad:
		if _squad != null and is_instance_valid(_squad):
			_squad.radio.disconnect(_on_squad_radio)
		_squad = squad
		if _squad != null:
			_squad.radio.connect(_on_squad_radio)


func _on_spotted(target: Node3D, _point: Vector3) -> void:
	if target == _target:
		_spotted = true


func _on_smoke(_points: PackedVector3Array) -> void:
	_smoke_used = true


func _on_squad_radio(kind: int, _at: Vector3) -> void:
	if kind == Squad.RADIO_MINE_ARMED:
		_mine_armed = true


## A round at the gunnery target that lands short: the instructor's hint.
func _on_fired(shell: Shell) -> void:
	if _stage < 0 or data.steps[_stage].goal != TutorialStepData.Goal.HIT_TARGET:
		return
	var from: Vector3 = _tank.global_position
	shell.finished.connect(func(struck: Array[Tank]) -> void:
		if not struck.is_empty() or _target == null or not is_instance_valid(_target) \
				or not is_instance_valid(shell):
			return
		var range_m: float = from.distance_to(_target.global_position)
		if from.distance_to(shell.global_position) < range_m - 15.0 \
				and _clock - _last_short >= data.short_hint_cooldown_s:
			_last_short = _clock
			_say(data.short_hint)
			_panel.show_hint(data.short_hint_text))


## Knocked out or lying on its side: the line, then back upright where it last stood well.
func _update_respawn(delta: float) -> void:
	if _respawn_left >= 0.0:
		_respawn_left -= delta
		if _respawn_left < 0.0:
			var at: Transform3D = _safe if _has_safe else _tank.global_transform
			at.origin += Vector3.UP * KothMode.SPAWN_LIFT_M
			KothMode.place_tank(_tank, Transform3D(Basis(Vector3.UP, at.basis.get_euler().y), at.origin))
			_tank.repair()
		return
	var upright: bool = _tank.global_basis.y.y > 0.8
	_safe_clock += delta
	if upright and not _tank.is_knocked_out() and _safe_clock >= 1.0:
		_safe_clock = 0.0
		_safe = _tank.global_transform
		_has_safe = true
	_down_time = _down_time + delta if _tank.global_basis.y.y < 0.35 else 0.0
	if _tank.is_knocked_out() or _down_time >= data.overturned_s:
		_down_time = 0.0
		_respawn_left = data.respawn_s
		_say(data.restart)
		_panel.show_hint("TRY AGAIN")


# --- The final test ------------------------------------------------------------------

func _update_final_hunt(delta: float) -> void:
	if _final.is_empty() or data.hunt_every_s <= 0.0:
		return
	_hunt_clock += delta
	if _hunt_clock < data.hunt_every_s:
		return
	_hunt_clock = 0.0
	var at: Vector3 = _tank.global_position
	for t: Tank in _final:
		var bot: BotController = _bots.get(t) as BotController
		if bot == null or not is_instance_valid(bot) or t.is_knocked_out():
			continue
		var away: Vector3 = t.global_position - at
		away.y = 0.0
		if away.length() > data.hunt_close_m + 50.0:
			bot.order_path(at + away.normalized() * data.hunt_close_m, 0.7)


# --- Placing -------------------------------------------------------------------------

## Open ground `min_m`..`max_m` from the player in the cone ahead; `sight`: the commander
## (hatch open) sees it; `cover`: cover near it scores higher. Relaxes sight, then gives
## a plain point ahead, so a lesson never stalls.
func _find_spot(min_m: float, max_m: float, sight: bool, cover: bool, mutual: bool = false,
		dir_override: Vector3 = Vector3.ZERO, cone_override: float = -1.0) -> Vector3:
	var origin: Vector3 = _tank.global_position if _tank != null else Vector3.ZERO
	var fwd: Vector3 = -_tank.global_basis.z if _tank != null else Vector3.FORWARD
	if dir_override != Vector3.ZERO:
		fwd = dir_override
	var cone: float = cone_override if cone_override >= 0.0 else data.cone_deg
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var eye: Vector3 = origin + Vector3.UP * 3.0
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	for need_sight: bool in ([true, false] if sight else [false]):
		var best: Vector3 = Vector3.INF
		var best_score: float = -1.0
		for i: int in SPOT_TRIES:
			var dir: Vector3 = fwd.rotated(Vector3.UP, deg_to_rad(randf_range(-cone, cone)))
			var g: Vector3 = _open_ground(origin + dir * randf_range(min_m, max_m))
			if g == Vector3.INF or _near_spawned(g):
				continue
			if need_sight and not _sees(eye, g + Vector3.UP * 0.5):
				continue
			# A bot that must fire: its own closed-hatch eye sees the player's hull too.
			if need_sight and mutual and not _sees(g + Vector3.UP * 0.8, origin + Vector3.UP * 0.3):
				continue
			var score: float = randf()
			if cover and map != null and map.is_covered(g):
				score += 1.0
			if score > best_score:
				best_score = score
				best = g
		if best != Vector3.INF:
			return best
	var p: Vector3 = origin + fwd * min_m
	var hit: Dictionary = KothMode.ground_hit(get_viewport().world_3d, p)
	return (hit["position"] as Vector3 if not hit.is_empty() else p) + Vector3.UP * KothMode.SPAWN_LIFT_M


## Open ground in a circle of the map (x, z); in sight of the commander's eye if `sight`
## can be had there (else without), cover preferred if `cover`.
func _find_in_area(centre: Vector2, radius: float, sight: bool, cover: bool) -> Vector3:
	var eye: Vector3 = (_tank.global_position if _tank != null else Vector3.ZERO) + Vector3.UP * 3.0
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	for need_sight: bool in ([true, false] if sight else [false]):
		var best: Vector3 = Vector3.INF
		var best_score: float = -1.0
		for i: int in SPOT_TRIES:
			var off: Vector2 = Vector2.from_angle(randf() * TAU) * sqrt(randf()) * radius
			var g: Vector3 = _open_ground(Vector3(centre.x + off.x, 0.0, centre.y + off.y))
			if g == Vector3.INF or _near_spawned(g):
				continue
			if need_sight and not _sees(eye, g + Vector3.UP * 0.5):
				continue
			var score: float = randf()
			if cover and map != null and map.is_covered(g):
				score += 1.0
			if score > best_score:
				best_score = score
				best = g
		if best != Vector3.INF:
			return best
	var p: Vector3 = _open_near(Vector3(centre.x, 0.0, centre.y), radius + 60.0)
	return p if p != Vector3.INF else _find_spot(data.target_min_m, data.target_max_m, false, false)


## The nearest open ground to `p` within `reach` (rings 8 m apart), INF if none.
func _open_near(p: Vector3, reach: float) -> Vector3:
	var g: Vector3 = _open_ground(p)
	var ring: float = 8.0
	while g == Vector3.INF and ring <= reach:
		for k: int in 12:
			g = _open_ground(p + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 12.0) * ring)
			if g != Vector3.INF:
				break
		ring += 8.0
	return g


func _near_spawned(p: Vector3) -> bool:
	for t: Tank in [_target, _heavy, _attacker] + _final:
		if t != null and is_instance_valid(t) and t.global_position.distance_to(p) < 60.0:
			return true
	return false


func _sees(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, SIGHT_MASK)
	query.collide_with_areas = true
	var rids: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
	query.exclude = rids
	return get_viewport().world_3d.direct_space_state.intersect_ray(query).is_empty()


## Ground a tank can stand on at (x, z) of `p` (as FreeFight's), lifted for a spawn; INF if not.
func _open_ground(p: Vector3) -> Vector3:
	if not MapEdge.contains(get_tree(), p):
		return Vector3.INF
	var hit: Dictionary = KothMode.ground_hit(get_viewport().world_3d, p)
	if hit.is_empty() or not (hit["collider"] is Terrain3D):
		return Vector3.INF
	var g: Vector3 = hit["position"]
	if g.y <= KothMode.SEA_LEVEL_LIMIT_M \
			or (hit["normal"] as Vector3).angle_to(Vector3.UP) > deg_to_rad(KothMode.SPAWN_MAX_SLOPE_DEG):
		return Vector3.INF
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	if map != null and map.is_blocked(g):
		return Vector3.INF
	if not KothMode.box_clear(get_viewport().world_3d, g):
		return Vector3.INF
	return g + Vector3.UP * KothMode.SPAWN_LIFT_M


func _spawn(at: Vector3, config: TankConfig, crew: BotData) -> Tank:
	var tank: Tank = (load(FreeFight.TANK_SCENE_PATH) as PackedScene).instantiate()
	_serial += 1
	tank.name = "TutorialTank%d" % _serial
	tank.team = 1
	tank.data = load(FreeFight.BOT_TANK_DATA)
	tank.config = config
	var parent: Node = get_parent()
	parent.add_child(tank)
	var look: Vector3 = (_tank.global_position if _tank != null else at + Vector3.FORWARD) - at
	look.y = 0.0
	if look.length() < 0.1:
		look = Vector3.FORWARD
	KothMode.place_tank(tank, Transform3D(Basis.looking_at(look.normalized(), Vector3.UP), at))
	if crew != null:
		var bot := BotController.new()
		bot.name = tank.name + "Controller"
		bot.bot_data = crew
		bot.tank = tank
		bot.respawn_delay_s = 0.0
		parent.add_child(bot)
		_bots[tank] = bot
	return tank


## Takes a placed tank (its bot and squad) away; a wreck stays.
func _remove(tank: Tank) -> void:
	if tank == null or not is_instance_valid(tank):
		return
	var bot: Node = _bots.get(tank) as Node
	_bots.erase(tank)
	if bot != null and is_instance_valid(bot):
		bot.queue_free()
	tank.leave_wreck()
	if tank.squad != null and is_instance_valid(tank.squad):
		tank.squad.queue_free()
	tank.queue_free()


func _place_marker() -> void:
	_clear_marker()
	var save_cone: float = data.cone_deg
	data.cone_deg = minf(save_cone, 25.0)
	var st: TutorialStepData = data.steps[_stage]
	if st.area != Vector2.ZERO:
		_marker_at = _open_near(Vector3(st.area.x, 0.0, st.area.y), 40.0)
	if st.area == Vector2.ZERO or _marker_at == Vector3.INF:
		_marker_at = _find_spot(data.marker_distance_m * 0.8, data.marker_distance_m * 1.2, false, false)
	data.cone_deg = save_cone
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.2
	mesh.bottom_radius = 1.2
	mesh.height = MARKER_HEIGHT_M
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(MenuTheme.ACCENT, 0.55)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(node)
	node.global_position = _marker_at + Vector3.UP * (MARKER_HEIGHT_M * 0.5 - KothMode.SPAWN_LIFT_M)
	_marker = node


func _clear_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null


func _say(stream: AudioStream) -> void:
	if stream == null or _views == null:
		return
	var radio := _views.get_parent().get_node_or_null("HUD/SquadRadio") as SquadRadio
	if radio != null:
		radio.command_call(stream, data.volume_db)
