class_name NetInput
extends Node
## Client: sends the local player's TankCommand to the host SEND_HZ times a second
## (unreliable). PlayerController keeps setting the command on the own
## (puppet) tank as offline, which also drives the local turret prediction; this node
## reads it from there. One-shot actions are latched so a lost packet doesn't drop them.

const SEND_HZ: float = 30.0

var tank: Tank
var _send_clock := PackedFloat32Array([0.0])
var _wanted_ammo: int = -1
var _spot_seq: int = 0
var _spot_point: Vector3 = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if tank == null or not is_instance_valid(tank):
		return
	var c: TankCommand = tank.get_command()
	if tank.is_knocked_out():
		_wanted_ammo = -1   # the respawned tank starts with its first ammo
	if c.ammo_select >= 0:
		_wanted_ammo = c.ammo_select
	if c.spot:
		_spot_seq = (_spot_seq + 1) & 255
		_spot_point = c.spot_point
	if c.smoke:
		NetSession.instance.rpc_id(1, "rpc_tank_action", RemoteController.ACTION_SMOKE)
	if c.abandon:
		NetSession.instance.rpc_id(1, "rpc_tank_action", RemoteController.ACTION_ABANDON)
	if c.squad_order != 0:
		# Squad orders are rare and must not get lost: reliable, not in the stream.
		NetSession.instance.rpc_id(1, "rpc_squad_order", c.squad_order, c.squad_target)
	if not Ticks.due(_send_clock, delta, SEND_HZ):
		return
	var buf := StreamPeerBuffer.new()
	buf.put_u8(NetSession.PACKET_COMMAND)
	var spot_saved: Vector3 = c.spot_point
	c.spot_point = _spot_point
	NetCommandCodec.write(buf, c, _wanted_ammo, _spot_seq)
	c.spot_point = spot_saved
	NetSession.instance.send_raw(buf.data_array, 1, NetSession.CH_COMMAND)
