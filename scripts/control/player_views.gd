class_name PlayerViews
extends Node
## Owns the local player's cameras: commander view (default), gunner's sight, the
## squad leader's eyes (only while the squad is off the tank; look only, no control).
## Also handles mouse capture. There is deliberately no free third-person camera: the
## commander's view is the point of the game.

enum ViewMode { COMMANDER, GUNNER, SQUAD }
## Values match the `mode` uniform in view_mask.gdshader.
enum OverlayMode { NONE, PERISCOPE, BINOCULARS, SIGHT }

@export var commander_camera: CommanderCamera
@export var gunner_camera: GunnerCamera
@export var squad_camera: SquadCamera

var _spectated: Tank
var _spectate_camera: Camera3D
var _mode: ViewMode = ViewMode.COMMANDER
var _killcam: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The cameras are placed every frame (_process) from the hull's interpolated pose:
	# physics interpolation must leave them alone.
	for camera: Camera3D in [commander_camera, gunner_camera, squad_camera]:
		if camera != null:
			camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_apply_view()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("toggle_gunner_sight"):
		_set_mode(ViewMode.COMMANDER if _mode == ViewMode.GUNNER else ViewMode.GUNNER)
	elif event.is_action_pressed("toggle_squad_view"):
		if _mode == ViewMode.SQUAD:
			_set_mode(ViewMode.COMMANDER)
		elif squad_camera != null and squad_camera.can_view():
			_set_mode(ViewMode.SQUAD)
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func get_mode() -> ViewMode:
	return _mode


func is_gunner_view() -> bool:
	return _mode == ViewMode.GUNNER


func is_squad_view() -> bool:
	return _mode == ViewMode.SQUAD


## True when the active view steers the turret every frame (gunner's sight).
func drives_turret() -> bool:
	return _mode == ViewMode.GUNNER


## Back to the tank when the squad mounts (or is gone) while looking through it.
func _process(_delta: float) -> void:
	# This machine's player decides who looks friendly (TeamLook).
	var own: Tank = get_tank()
	if own != null:
		TeamLook.set_viewer_team(own.team)
	if _mode == ViewMode.SQUAD and (squad_camera == null or not squad_camera.can_view()):
		_set_mode(ViewMode.COMMANDER)


func get_aim_point() -> Vector3:
	match _mode:
		ViewMode.GUNNER:
			return gunner_camera.get_aim_point()
		ViewMode.SQUAD:
			return squad_camera.get_aim_point()
		_:
			return commander_camera.get_aim_point()


func get_overlay_mode() -> OverlayMode:
	if _killcam:
		return OverlayMode.NONE
	match _mode:
		ViewMode.GUNNER:
			return OverlayMode.SIGHT
		ViewMode.SQUAD:
			return OverlayMode.BINOCULARS if squad_camera.is_binoculars_active() else OverlayMode.NONE
	if commander_camera.is_binoculars_active():
		return OverlayMode.BINOCULARS
	if commander_camera.is_periscope_view():
		return OverlayMode.PERISCOPE
	return OverlayMode.NONE


func get_tank() -> Tank:
	return commander_camera.tank


## The camera the player looks through from the tank (commander or gunner); null in
## the squad view.
func get_view_camera() -> Camera3D:
	match _mode:
		ViewMode.COMMANDER: return commander_camera
		ViewMode.GUNNER: return gunner_camera
	return null


func get_tank_data() -> TankData:
	return commander_camera.tank.data


func _set_mode(mode: ViewMode) -> void:
	if mode == ViewMode.GUNNER and _mode != ViewMode.GUNNER:
		gunner_camera.sync_to_gun()
	if mode == ViewMode.SQUAD and _mode != ViewMode.SQUAD:
		squad_camera.start()
	_mode = mode
	_apply_view()


## Killcam (Killcam) has the screen: no view camera, no optics overlays.
func set_killcam(active: bool) -> void:
	_killcam = active
	if not active:
		_apply_view()


func is_killcam() -> bool:
	return _killcam


## Knocked out: the teammate the killcam follows and its camera (null: none). The maps
## centre on it and draw it as the own tank, so the player sees where the fight is.
func set_spectated(watched: Tank, camera: Camera3D) -> void:
	_spectated = watched
	_spectate_camera = camera


func get_spectated() -> Tank:
	return _spectated if _spectated != null and is_instance_valid(_spectated) else null


func get_spectate_camera() -> Camera3D:
	return _spectate_camera if get_spectated() != null else null


func _apply_view() -> void:
	if _killcam:
		return
	commander_camera.current = _mode == ViewMode.COMMANDER
	gunner_camera.current = _mode == ViewMode.GUNNER
	if squad_camera != null:
		squad_camera.current = _mode == ViewMode.SQUAD
