class_name TankNetState
extends RefCounted
## One tank's state as the host sends it to clients, packed small: about 38 bytes for
## everyone plus 9 bytes only for the tank's owner (hp, modules, reload, ...). Enemy hp
## is never sent. Read and written by Tank (get/apply_net_state) and the net code.

const FLAG_KNOCKED_OUT: int = 1
const FLAG_BURNING: int = 2
const FLAG_MG_FIRING: int = 4
const FLAG_MG_ROOF: int = 8
const FLAG_WOUNDED: int = 16
const FLAG_OWNER_DATA: int = 128
## Module order in the owner data (2 bits each).
const MODULES: Array[StringName] = [&"engine", &"fuel", &"track_left", &"track_right",
		&"turret_ring", &"ammo"]
const ANGLE_SCALE: float = 32767.0 / PI
const VELOCITY_SCALE: float = 100.0   # cm/s

var net_id: int = 0
var position: Vector3 = Vector3.ZERO
var rotation: Quaternion = Quaternion.IDENTITY
var velocity: Vector3 = Vector3.ZERO
var turret_yaw: float = 0.0
var gun_pitch: float = 0.0
var hatch: float = 0.0
var flags: int = 0
var roof_mg_yaw: float = 0.0
var roof_mg_pitch: float = 0.0
# owner only
var hp_fraction: float = 1.0
var module_states: PackedInt32Array = PackedInt32Array()
var reload_s: float = 0.0
var ammo_index: int = 0
## Own tank: standing-still time left of the repair, and its total (s).
var repair_left_s: float = 0.0
var repair_total_s: float = 0.0
var spot_cooldown_s: float = 0.0
var wound_s: float = 0.0


func has(flag: int) -> bool:
	return flags & flag != 0


func write(buf: StreamPeerBuffer) -> void:
	buf.put_u16(net_id)
	buf.put_float(position.x); buf.put_float(position.y); buf.put_float(position.z)
	var q: Quaternion = rotation.normalized()
	for c: float in [q.x, q.y, q.z, q.w]:
		buf.put_16(roundi(clampf(c, -1.0, 1.0) * 32767.0))
	for c: float in [velocity.x, velocity.y, velocity.z]:
		buf.put_16(clampi(roundi(c * VELOCITY_SCALE), -32767, 32767))
	buf.put_16(_angle(turret_yaw)); buf.put_16(_angle(gun_pitch))
	buf.put_u8(roundi(clampf(hatch, 0.0, 1.0) * 255.0))
	buf.put_u8(flags)
	buf.put_16(_angle(roof_mg_yaw)); buf.put_16(_angle(roof_mg_pitch))
	if has(FLAG_OWNER_DATA):
		buf.put_u8(roundi(clampf(hp_fraction, 0.0, 1.0) * 255.0))
		var bits: int = 0
		for i: int in MODULES.size():
			bits |= (module_states[i] if i < module_states.size() else 0) << (2 * i)
		buf.put_u16(bits)
		buf.put_u8(_tenths(reload_s)); buf.put_u8(ammo_index)
		buf.put_u16(clampi(roundi(repair_left_s * 10.0), 0, 65535)); buf.put_u8(ceili(clampf(repair_total_s, 0.0, 255.0)))
		buf.put_u8(_tenths(spot_cooldown_s)); buf.put_u8(ceili(clampf(wound_s, 0.0, 255.0)))


static func read(buf: StreamPeerBuffer) -> TankNetState:
	var s := TankNetState.new()
	s.net_id = buf.get_u16()
	s.position = Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	s.rotation = Quaternion(buf.get_16() / 32767.0, buf.get_16() / 32767.0,
			buf.get_16() / 32767.0, buf.get_16() / 32767.0).normalized()
	s.velocity = Vector3(buf.get_16(), buf.get_16(), buf.get_16()) / VELOCITY_SCALE
	s.turret_yaw = buf.get_16() / ANGLE_SCALE
	s.gun_pitch = buf.get_16() / ANGLE_SCALE
	s.hatch = buf.get_u8() / 255.0
	s.flags = buf.get_u8()
	s.roof_mg_yaw = buf.get_16() / ANGLE_SCALE
	s.roof_mg_pitch = buf.get_16() / ANGLE_SCALE
	if s.has(FLAG_OWNER_DATA):
		s.hp_fraction = buf.get_u8() / 255.0
		var bits: int = buf.get_u16()
		for i: int in MODULES.size():
			s.module_states.append((bits >> (2 * i)) & 3)
		s.reload_s = buf.get_u8() / 10.0
		s.ammo_index = buf.get_u8()
		s.repair_left_s = buf.get_u16() / 10.0
		s.repair_total_s = buf.get_u8()
		s.spot_cooldown_s = buf.get_u8() / 10.0
		s.wound_s = buf.get_u8()
	return s


static func _angle(a: float) -> int:
	return roundi(wrapf(a, -PI, PI) * ANGLE_SCALE)


static func _tenths(s: float) -> int:
	return clampi(ceili(s * 10.0), 0, 255)
