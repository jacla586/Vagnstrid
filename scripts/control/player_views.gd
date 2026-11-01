class_name PlayerViews
extends Node
## Owns the local player's cameras: commander view (default) and the debug orbit view.
## Also handles mouse capture.

enum OverlayMode { NONE, PERISCOPE, BINOCULARS }

@export var commander_camera: CommanderCamera
@export var debug_camera: OrbitCamera

var _debug_view: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_view()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("toggle_debug_view"):
		_debug_view = not _debug_view
		_apply_view()
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func is_debug_view() -> bool:
	return _debug_view


func get_aim_point() -> Vector3:
	if _debug_view:
		return debug_camera.get_aim_point()
	return commander_camera.get_aim_point()


func get_overlay_mode() -> OverlayMode:
	if _debug_view:
		return OverlayMode.NONE
	if commander_camera.is_binoculars_active():
		return OverlayMode.BINOCULARS
	if commander_camera.is_periscope_view():
		return OverlayMode.PERISCOPE
	return OverlayMode.NONE


func get_tank_data() -> TankData:
	return commander_camera.tank.data


func _apply_view() -> void:
	commander_camera.current = not _debug_view
	debug_camera.current = _debug_view
