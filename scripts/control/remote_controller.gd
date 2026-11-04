class_name RemoteController
extends Node
## Host side: drives a remote player's tank with the commands that player's client sends
## (NetInput). Like PlayerController, but the input comes over the network. If no packet
## arrives for STALE_S, the tank stops and holds fire.

const STALE_S: float = 0.5

@export var tank: Tank

var _received: TankCommand = TankCommand.new()
var _command: TankCommand = TankCommand.new()
var _wanted_ammo: int = -1
var _spot_seq: int = -1
var _spot_pending: bool = false
var _age: float = 999.0


func receive(buf: StreamPeerBuffer) -> void:
	var extra: Array[int] = NetCommandCodec.read(buf, _received)
	_wanted_ammo = extra[0]
	if _spot_seq >= 0 and extra[1] != _spot_seq:
		_spot_pending = true
	_spot_seq = extra[1]
	_age = 0.0


func _physics_process(delta: float) -> void:
	if tank == null:
		return
	_age += delta
	var c: TankCommand = _command
	var fresh: bool = _age < STALE_S
	c.throttle = _received.throttle if fresh else 0.0
	c.steering = _received.steering if fresh else 0.0
	c.has_aim = _received.has_aim and fresh
	c.aim_point = _received.aim_point
	c.fire = _received.fire and fresh
	c.fire_mg = _received.fire_mg and fresh
	c.mg_use_roof = _received.mg_use_roof
	c.mg_aim_point = _received.mg_aim_point
	c.hatch_open = _received.hatch_open
	c.ammo_select = _wanted_ammo if _wanted_ammo != tank.get_ammo_index() else -1
	c.spot = _spot_pending
	c.spot_point = _received.spot_point
	_spot_pending = false
	tank.set_command(c)
