class_name PlayerViews
extends Node
## Owns the local player's cameras: commander view (default), gunner's sight and the
## debug orbit view. Also handles mouse capture.

enum ViewMode { COMMANDER, GUNNER, DEBUG }
## Values match the `mode` uniform in view_mask.gdshader.
enum OverlayMode { NONE, PERISCOPE, BINOCULARS, SIGHT }

@export var commander_camera: CommanderCamera
@export var gunner_camera: GunnerCamera
@export var debug_camera: OrbitCamera

var _mode: ViewMode = ViewMode.COMMANDER
var _mode_before_debug: ViewMode = ViewMode.COMMANDER


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_view()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("toggle_debug_view"):
		if _mode == ViewMode.DEBUG:
			_set_mode(_mode_before_debug)
		else:
			_mode_before_debug = _mode
			_set_mode(ViewMode.DEBUG)
	elif event.is_action_pressed("toggle_gunner_sight") and _mode != ViewMode.DEBUG:
		_set_mode(ViewMode.COMMANDER if _mode == ViewMode.GUNNER else ViewMode.GUNNER)
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func get_mode() -> ViewMode:
	return _mode


func is_gunner_view() -> bool:
	return _mode == ViewMode.GUNNER


func is_debug_view() -> bool:
	return _mode == ViewMode.DEBUG


## True when the active view steers the turret every frame (gunner's sight, debug).
func drives_turret() -> bool:
	return _mode != ViewMode.COMMANDER


func get_aim_point() -> Vector3:
	match _mode:
		ViewMode.GUNNER:
			return gunner_camera.get_aim_point()
		ViewMode.DEBUG:
			return debug_camera.get_aim_point()
		_:
			return commander_camera.get_aim_point()


func get_overlay_mode() -> OverlayMode:
	match _mode:
		ViewMode.GUNNER:
			return OverlayMode.SIGHT
		ViewMode.DEBUG:
			return OverlayMode.NONE
	if commander_camera.is_binoculars_active():
		return OverlayMode.BINOCULARS
	if commander_camera.is_periscope_view():
		return OverlayMode.PERISCOPE
	return OverlayMode.NONE


func get_tank() -> Tank:
	return commander_camera.tank


func get_tank_data() -> TankData:
	return commander_camera.tank.data


func _set_mode(mode: ViewMode) -> void:
	if mode == ViewMode.GUNNER and _mode != ViewMode.GUNNER:
		gunner_camera.sync_to_gun()
	_mode = mode
	_apply_view()


func _apply_view() -> void:
	commander_camera.current = _mode == ViewMode.COMMANDER
	gunner_camera.current = _mode == ViewMode.GUNNER
	debug_camera.current = _mode == ViewMode.DEBUG
