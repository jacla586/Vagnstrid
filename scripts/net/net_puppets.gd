class_name NetPuppets
extends Node
## Client: keeps the host's snapshots per tank and shows each puppet INTERP_DELAY_S
## behind the newest data, interpolating between the two snapshots around that time
## (lerp position and angles, slerp rotation). Status (flags, own hp/modules) is applied
## from the newest snapshot at once. Big jumps (respawn) snap instead of sliding.

const INTERP_DELAY_S: float = 0.1
const MAX_EXTRAPOLATE_S: float = 0.25
const SNAP_DISTANCE_M: float = 25.0
const KEEP: int = 30

## net_id -> Tank
var puppets: Dictionary = {}
## net_id -> Array of [host_time, TankNetState]
var _samples: Dictionary = {}
var _clock_offset: float = INF
var _newest_tick: int = -1
## Seconds per host physics tick (the snapshot's tick counts them). Was a fixed 1/60 after
## physics went to 30 Hz: host time ran at half speed, the clock offset fell ever further
## behind and every puppet (the own hull too) was extrapolated 0.25 s on its last snapshot,
## its rotation stepping at 20 Hz.
var _host_tick_s: float = 1.0 / Engine.physics_ticks_per_second


func register(tank: Tank) -> void:
	puppets[tank.net_id] = tank
	_samples[tank.net_id] = []


func unregister(net_id: int) -> void:
	puppets.erase(net_id)
	_samples.erase(net_id)


func receive(buf: StreamPeerBuffer) -> void:
	var tick: int = buf.get_u32()
	var count: int = buf.get_u8()
	var host_time: float = tick * _host_tick_s
	var now: float = Time.get_ticks_msec() / 1000.0
	# Offset local - host: the smallest seen (least delayed packet), drifting slowly up.
	var offset: float = now - host_time
	if offset < _clock_offset or _clock_offset == INF:
		_clock_offset = offset
	else:
		_clock_offset += (offset - _clock_offset) * 0.002
	var newest: bool = tick > _newest_tick
	_newest_tick = maxi(_newest_tick, tick)
	for i: int in count:
		var s: TankNetState = TankNetState.read(buf)
		if not puppets.has(s.net_id):
			continue
		var list: Array = _samples[s.net_id]
		list.append([host_time, s])
		if list.size() > KEEP:
			list.pop_front()
		if newest:
			var tank_v: Variant = puppets[s.net_id]
			var tank: Tank = (tank_v as Tank) if is_instance_valid(tank_v) else null
			if is_instance_valid(tank):
				tank.net_set_status(s)


## In the physics step: physics interpolation then draws the puppets smoothly between
## steps (and their shapes are where shells look for them).
func _physics_process(_delta: float) -> void:
	if _clock_offset == INF:
		return
	var render_t: float = Time.get_ticks_msec() / 1000.0 - _clock_offset - INTERP_DELAY_S
	for net_id: int in puppets:
		var tank_v: Variant = puppets[net_id]
		var tank: Tank = (tank_v as Tank) if is_instance_valid(tank_v) else null
		var list: Array = _samples[net_id]
		if not is_instance_valid(tank) or list.is_empty():
			continue
		var a: Array = list[0]
		var b: Array = list[list.size() - 1]
		for i: int in range(list.size() - 1, -1, -1):
			if list[i][0] <= render_t:
				a = list[i]
				b = list[mini(i + 1, list.size() - 1)]
				break
		var sa: TankNetState = a[1]
		var sb: TankNetState = b[1]
		var span: float = b[0] - a[0]
		var t: float = clampf((render_t - a[0]) / span, 0.0, 1.0) if span > 0.0001 else 1.0
		var pos: Vector3
		var rot: Quaternion
		if sa.position.distance_to(sb.position) > SNAP_DISTANCE_M:
			pos = sb.position
			rot = sb.rotation
			t = 1.0
		elif render_t > b[0] and a == b:
			# Newest data is older than the render time: carry on a little with its velocity.
			pos = sb.position + sb.velocity * minf(render_t - b[0], MAX_EXTRAPOLATE_S)
			rot = sb.rotation
		else:
			pos = sa.position.lerp(sb.position, t)
			rot = sa.rotation.slerp(sb.rotation, t)
		tank.net_set_pose(Transform3D(Basis(rot), pos),
				lerp_angle(sa.turret_yaw, sb.turret_yaw, t), lerpf(sa.gun_pitch, sb.gun_pitch, t),
				lerpf(sa.hatch, sb.hatch, t), lerp_angle(sa.roof_mg_yaw, sb.roof_mg_yaw, t),
				lerpf(sa.roof_mg_pitch, sb.roof_mg_pitch, t), sa.velocity.lerp(sb.velocity, t))
