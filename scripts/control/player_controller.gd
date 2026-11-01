class_name PlayerController
extends Node
## Turns the local player's input into a TankCommand for the controlled tank.
##
## Commander view: the turret only moves when "turret_to_view" is pressed; it then
## goes to the point under the screen centre and keeps aiming there.
## Debug view: the turret follows the camera.

@export var tank: Tank
@export var views: PlayerViews

var _command: TankCommand = TankCommand.new()
var _hatch_wanted: bool = false
var _turret_to_view_requested: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hatch"):
		_hatch_wanted = not _hatch_wanted
	elif event.is_action_pressed("turret_to_view"):
		_turret_to_view_requested = true


func _physics_process(_delta: float) -> void:
	if tank == null:
		return
	_command.throttle = Input.get_axis("move_backward", "move_forward")
	_command.steering = Input.get_axis("turn_left", "turn_right")
	_command.hatch_open = _hatch_wanted
	if views != null and (views.is_debug_view() or _turret_to_view_requested):
		# Ray queries are done here (physics frame), not in the input callback.
		_command.aim_point = views.get_aim_point()
		_command.has_aim = true
	_turret_to_view_requested = false
	tank.set_command(_command)
