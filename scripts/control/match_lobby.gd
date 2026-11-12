class_name MatchLobby
extends Node
## A player who has just come into a match has no tank yet: this shows the deploy screen
## (DeployScreen: the game mode in short, the teams, then the tank) over a camera that
## circles high over the fight, and spawns the player when a tank is chosen. Online
## NetGame adds it and does the work on the host (pick_team / request_deploy, roster);
## offline (single player from the main menu, NetSession.play_offline) it takes the
## map's own PlayerRig out at the start and brings a new one in at the chosen team's
## spawn, a bot making room (the bot director's make_room / refill). Running a
## scenario straight from the editor has no lobby: the map's rig plays as before.
## Once the player has a tank the lobby goes.

const RIG_SCENE_PATH: String = "res://scenes/player/player_rig.tscn"
const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
## The host has not spawned us this long after the request: let the player try again (s).
const DEPLOY_RETRY_S: float = 4.0

static var instance: MatchLobby

var _screen: DeployScreen
var _layer: CanvasLayer
var _camera: Camera3D
var _team: int = -1
var _angle: float = 0.0
var _focus: Vector3 = Vector3.ZERO
var _has_focus: bool = false
var _waiting_s: float = -1.0
var _shown_roster: Array = []
var _roster_clock := PackedFloat32Array([0.0])
## Offline: where the map's rig sat (team 0's start outside a mode), its parent, and
## the respawn nodes that looked after its tank.
var _start0: Transform3D = Transform3D.IDENTITY
var _rig_parent: Node
var _respawns: Array[RespawnAtStart] = []
var _offline_ready: bool = false


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.far = 8000.0
	_camera.fov = 60.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_camera)
	_camera.make_current()
	_layer = CanvasLayer.new()
	_layer.layer = 60
	add_child(_layer)
	_screen = DeployScreen.new()
	_layer.add_child(_screen)
	_screen.team_chosen.connect(_on_team_chosen)
	_screen.tank_chosen.connect(_on_tank_chosen)
	_screen.back_pressed.connect(func() -> void: _screen.show_page(DeployScreen.Page.BRIEFING))
	_screen.leave_pressed.connect(_leave)
	_screen.set_tank_page("", "Deploy", true)
	_fill_briefing()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetRole.is_online():
		var game: NetGame = NetSession.instance.game
		if game != null:
			game.roster_changed.connect(_refresh_roster)
	else:
		_take_offline_rig()
	_refresh_roster()


func _process(delta: float) -> void:
	_move_camera(delta)
	if NetRole.is_online():
		var game: NetGame = NetSession.instance.game
		if game != null and game.has_own_tank():
			_finish()
			return
		if _waiting_s >= 0.0:
			_waiting_s += delta
			if _waiting_s > DEPLOY_RETRY_S:
				_waiting_s = -1.0
				_screen.set_busy("")
	elif Ticks.due(_roster_clock, delta, 2.0):
		_refresh_roster()   # offline: bots come and go
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Screen ------------------------------------------------------------------------

func _fill_briefing() -> void:
	var title: String = TankSummary.data().free_fight_name
	var rules: String = TankSummary.data().free_fight_briefing
	if KothMode.instance != null and KothMode.instance.data != null:
		var koth: KothData = KothMode.instance.data
		title = koth.display_name
		rules = koth.briefing.format({"score": "%d" % roundi(koth.score_to_win)})
	elif ThunderRoadMode.instance != null and ThunderRoadMode.instance.data != null:
		title = ThunderRoadMode.instance.data.display_name
		rules = ThunderRoadMode.instance.data.briefing
	elif FreeFight.instance != null and FreeFight.instance.data != null:
		title = FreeFight.instance.data.display_name
		rules = FreeFight.instance.data.briefing
	var scene: Node = get_tree().current_scene
	var map_name: String = scene.scene_file_path.get_file().get_basename().capitalize() \
			if scene != null else ""
	_screen.set_briefing(title, map_name, rules)
	_update_team_labels()


func _update_team_labels() -> void:
	var labels: Array[String] = ["Team 1", "Team 2"]
	var thunder: ThunderRoadMode = ThunderRoadMode.instance
	if thunder != null:
		for i: int in 2:
			labels[i] += "  (attacking)" if thunder.get_attack_team() == i else "  (defending)"
	_screen.set_teams(labels, _joinable())


## Offline outside a two-sided mode the bots are the other side: team 1 only.
func _joinable() -> Array[bool]:
	if FreeFight.instance != null:
		return [true, false]   # the players together against the waves
	var two_sided: bool = KothMode.instance != null or ThunderRoadMode.instance != null
	if NetRole.is_online() or two_sided:
		return [true, true]
	return [true, false]


func _refresh_roster() -> void:
	var rows: Array = roster_rows()
	if rows == _shown_roster:
		return
	_shown_roster = rows
	_screen.set_roster(rows)
	_update_team_labels()


## [team, name, kind (DeployScreen.Kind), tank type] for every tank and choosing player.
func roster_rows() -> Array:
	if NetRole.is_online():
		var game: NetGame = NetSession.instance.game
		if game == null:
			return []
		var out: Array = []
		var me: int = NetSession.instance.my_id()
		for row: Array in game.roster:
			var r: Array = row.duplicate()
			if int(row[4]) == me:
				r[1] = str(row[1]) + " (you)"
			out.append(r)
		return out
	var rows: Array = []
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or tank.is_queued_for_deletion() or tank.wreck_only:
			continue
		rows.append([tank.team, "Bot", DeployScreen.Kind.BOT, tank.get_type_name()])
	if _team >= 0:
		rows.append([_team, "You", DeployScreen.Kind.CHOOSING, ""])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) < int(b[0]) if a[0] != b[0] else int(a[2]) < int(b[2]))
	return rows


func _on_team_chosen(team: int) -> void:
	_team = team
	if NetRole.is_online() and NetSession.instance.game != null:
		NetSession.instance.game.pick_team(team)
	_has_focus = false   # over the team's side now
	_refresh_roster()
	_screen.show_page(DeployScreen.Page.TANKS)


func _on_tank_chosen(cfg: TankConfig) -> void:
	if _team < 0:
		_screen.show_page(DeployScreen.Page.BRIEFING)
		return
	TankConfigs.select(cfg)
	if NetRole.is_online():
		var game: NetGame = NetSession.instance.game
		if game == null:
			return
		_screen.set_busy("Deploying…")
		_waiting_s = 0.0
		game.request_deploy(cfg)
		return
	if not _offline_ready:
		_screen.set_busy("Getting ready…")
		return
	_deploy_offline()
	_finish()


func _leave() -> void:
	if NetRole.is_online():
		NetSession.instance.leave()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


## The player has a tank: the screen and camera go (the rig's cameras take over).
func _finish() -> void:
	_camera.current = false
	queue_free()


# --- Camera ------------------------------------------------------------------------

## Circles high over the chosen team's tanks (before a choice: over all of them).
func _move_camera(delta: float) -> void:
	var settings: DeployData = TankSummary.data()
	var sum := Vector3.ZERO
	var n: int = 0
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or not tank.is_inside_tree() or (_team >= 0 and tank.team != _team):
			continue
		sum += tank.global_position
		n += 1
	if n > 0:
		var target: Vector3 = sum / n
		_focus = target if not _has_focus else _focus.lerp(target, minf(1.0, delta * 0.5))
		_has_focus = true
	_angle += deg_to_rad(settings.orbit_deg_s) * delta
	var offset := Vector3(cos(_angle) * settings.orbit_radius_m, settings.orbit_height_m,
			sin(_angle) * settings.orbit_radius_m)
	_camera.global_position = _focus + offset
	_camera.look_at(_focus, Vector3.UP)


# --- Offline -----------------------------------------------------------------------

## The map's own rig goes once the bot director has filled the teams; a bot takes its
## place until the player deploys.
func _take_offline_rig() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var scene: Node = get_tree().current_scene
	_rig_parent = scene
	var rig: Node = scene.get_node_or_null("PlayerRig") if scene != null else null
	var tank: Tank = rig.get_node_or_null("Tank") as Tank if rig != null else null
	if tank != null:
		_start0 = tank.global_transform
		_rig_parent = rig.get_parent()
		for node: Node in scene.find_children("*", "", true, false):
			var respawn := node as RespawnAtStart
			if respawn != null and respawn.tank == tank:
				_respawns.append(respawn)
		if tank.squad != null and is_instance_valid(tank.squad):
			tank.squad.queue_free()
		rig.name = "PlayerRigOld"
		rig.get_parent().remove_child(rig)   # out of the "tanks" group now: the refill counts right
		rig.queue_free()
		var director: Node = _director()
		if director != null:
			director.refill()
	_camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_offline_ready = true
	_screen.set_busy("")


func _deploy_offline() -> void:
	var director: Node = _director()
	if director != null:
		var bot_tank: Tank = director.make_room(_team)
		if bot_tank != null:
			bot_tank.leave_wreck()
			if bot_tank.squad != null and is_instance_valid(bot_tank.squad):
				bot_tank.squad.queue_free()
			bot_tank.queue_free()
	var rig: Node3D = (load(RIG_SCENE_PATH) as PackedScene).instantiate()
	rig.name = "PlayerRig"
	var tank: Tank = rig.get_node("Tank")
	tank.team = _team
	var parent: Node = _rig_parent if is_instance_valid(_rig_parent) else get_tree().current_scene
	parent.add_child(rig)
	KothMode.place_tank(tank, _offline_spawn(tank))
	for respawn: RespawnAtStart in _respawns:
		if is_instance_valid(respawn):
			respawn.set_tank(tank)
	if director != null:
		director.refill.call_deferred()


## The mode's spawn for the team, else the map's start (team 0) or beside the team's
## first tank.
func _offline_spawn(tank: Tank) -> Transform3D:
	if ThunderRoadMode.instance != null:
		return ThunderRoadMode.instance.spawn_for_new(_team, tank)
	if FreeFight.instance != null:
		return FreeFight.instance.spawn_for_new(_team, tank)
	var koth: KothMode = KothMode.instance
	if koth != null and koth.has_started():
		return koth.get_free_spawn(_team, tank)
	if _team != 0:
		for node: Node in get_tree().get_nodes_in_group("tanks"):
			var other := node as Tank
			if other != null and other != tank and other.team == _team:
				return other.global_transform.translated(other.global_basis.x * 15.0)
	return _start0


func _director() -> Node:
	if KothBots.instance != null:
		return KothBots.instance
	if FreeFight.instance != null:
		return FreeFight.instance
	return ThunderRoadBots.instance
