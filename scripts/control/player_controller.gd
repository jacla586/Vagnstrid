class_name PlayerController
extends Node
## Turns the local player's input into a TankCommand for the controlled tank.

@export var tank: Tank

var _command: TankCommand = TankCommand.new()


func _physics_process(_delta: float) -> void:
	if tank == null:
		return
	_command.throttle = Input.get_axis("move_backward", "move_forward")
	_command.steering = Input.get_axis("turn_left", "turn_right")
	tank.set_command(_command)
