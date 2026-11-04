class_name NetInput
extends Node
## Client: sends the local player's TankCommand to the host every SEND_TICKS physics
## ticks (30 Hz, unreliable). PlayerController keeps setting the command on the own
## (puppet) tank as offline, which also drives the local turret prediction; this node
## reads it from there. One-shot actions are latched so a lost packet doesn't drop them.

const SEND_TICKS: int = 2

var tank: Tank
var _tick: int = 0
var _wanted_ammo: int = -1
var _spot_seq: int = 0
var _spot_point: Vector3 = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	if tank == null or not is_instance_valid(tank):
		return
	var c: TankCommand = tank.get_command()
	if c.ammo_select >= 0:
		_wanted_ammo = c.ammo_select
	if c.spot:
		_spot_seq = (_spot_seq + 1) & 255
		_spot_point = c.spot_point
	_tick += 1
	if _tick % SEND_TICKS != 0:
		return
	var buf := StreamPeerBuffer.new()
	buf.put_u8(NetSession.PACKET_COMMAND)
	var spot_saved: Vector3 = c.spot_point
	c.spot_point = _spot_point
	NetCommandCodec.write(buf, c, _wanted_ammo, _spot_seq)
	c.spot_point = spot_saved
	NetSession.instance.send_raw(buf.data_array, 1, NetSession.CH_COMMAND)
