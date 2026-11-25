class_name NetCommandCodec
extends RefCounted
## Packs a TankCommand for the wire (client -> host, about 42 bytes, unreliable).
## One-shot actions survive lost packets: ammo is sent as the wanted index every time,
## and spotting as a sequence number that changes once per spot.

const FLAG_HAS_AIM: int = 1
const FLAG_FIRE: int = 2
const FLAG_FIRE_MG: int = 4
const FLAG_MG_ROOF: int = 8
const FLAG_HATCH: int = 16
const FLAG_COAST: int = 32


static func write(buf: StreamPeerBuffer, c: TankCommand, wanted_ammo: int, spot_seq: int) -> void:
	buf.put_8(roundi(clampf(c.throttle, -1.0, 1.0) * 127.0))
	buf.put_8(roundi(clampf(c.steering, -1.0, 1.0) * 127.0))
	var f: int = 0
	if c.has_aim: f |= FLAG_HAS_AIM
	if c.fire: f |= FLAG_FIRE
	if c.fire_mg: f |= FLAG_FIRE_MG
	if c.mg_use_roof: f |= FLAG_MG_ROOF
	if c.hatch_open: f |= FLAG_HATCH
	if c.coast: f |= FLAG_COAST
	buf.put_u8(f)
	buf.put_8(wanted_ammo)
	buf.put_u8(spot_seq & 255)
	for v: Vector3 in [c.aim_point, c.mg_aim_point, c.spot_point]:
		buf.put_float(v.x); buf.put_float(v.y); buf.put_float(v.z)


## Reads into `c`. Returns [wanted_ammo, spot_seq].
static func read(buf: StreamPeerBuffer, c: TankCommand) -> Array[int]:
	c.throttle = buf.get_8() / 127.0
	c.steering = buf.get_8() / 127.0
	var f: int = buf.get_u8()
	c.has_aim = f & FLAG_HAS_AIM != 0
	c.fire = f & FLAG_FIRE != 0
	c.fire_mg = f & FLAG_FIRE_MG != 0
	c.mg_use_roof = f & FLAG_MG_ROOF != 0
	c.hatch_open = f & FLAG_HATCH != 0
	c.coast = f & FLAG_COAST != 0
	var wanted: int = buf.get_8()
	var seq: int = buf.get_u8()
	c.aim_point = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	c.mg_aim_point = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	c.spot_point = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	return [wanted, seq]
