class_name PlayerController
extends Node
## Turns the local player's input into a TankCommand for the controlled tank.
##
## Commander view: the turret only moves when "turret_to_view" is pressed; it then
## goes to the point under the screen centre and keeps aiming there.
## Gunner's sight and debug view: the turret follows the view's aim every frame.

@export var tank: Tank
@export var views: PlayerViews

var _command: TankCommand = TankCommand.new()
var _hatch_wanted: bool = false
var _turret_to_view_requested: bool = false
var _fire_armed: bool = false


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
	if views != null and (views.drives_turret() or _turret_to_view_requested):
		# Ray queries are done here (physics frame), not in the input callback.
		_command.aim_point = views.get_aim_point()
		_command.has_aim = true
	_turret_to_view_requested = false
	_command.fire = _wants_fire()
	tank.set_command(_command)


## Fire while the button is held, but only presses that start with the mouse
## captured count, so the click that captures the mouse doesn't also fire.
func _wants_fire() -> bool:
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var pressed: bool = Input.is_action_pressed("fire")
	if not captured:
		_fire_armed = false
	elif not pressed:
		_fire_armed = true
	return captured and pressed and _fire_armed
