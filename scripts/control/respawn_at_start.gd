class_name RespawnAtStart
extends Node
## Test bench: brings a knocked-out tank back where it started, repaired, after a delay.

@export var tank: Tank
## Seconds after the knock-out until the tank is back at its start.
@export var delay_s: float = 10.0

var _start: Transform3D
var _timer: float = -1.0


func _ready() -> void:
	if tank == null:
		return
	_start = tank.global_transform
	tank.knocked_out.connect(func() -> void: _timer = delay_s)


func _physics_process(delta: float) -> void:
	if _timer < 0.0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = -1.0
	tank.global_transform = _start
	tank.linear_velocity = Vector3.ZERO
	tank.angular_velocity = Vector3.ZERO
	tank.repair()
