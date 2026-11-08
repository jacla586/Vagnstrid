class_name TankExhaust
extends Node3D
## A tank's exhaust smoke (ExhaustData). Reads only tank state (command throttle and
## how fast it moves), like TankAudio, so puppets smoke the same. The load (0 idle ..
## 1 full, Tank.get_exhaust_load) also makes the tank easier to spot (Concealment).

const KMH_TO_MS: float = 1.0 / 3.6
const DEFAULT: ExhaustData = preload("res://data/tanks/exhaust_default.tres")
## Faster than this between two frames is a teleport (respawn), not driving (m/s).
const MAX_PLAUSIBLE_SPEED: float = 60.0

var tank: Tank
## 0 = idle .. 1 = full load (more with a throttle burst, clamped for spotting).
var engine_load: float = 0.0

var _data: ExhaustData
var _pipes: Array[GPUParticles3D] = []
var _last_throttle: float = 0.0
var _burst: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _speed: float = 0.0


func _ready() -> void:
	assert(tank != null, "TankExhaust needs its tank")
	_data = tank.data.exhaust if tank.data.exhaust != null else DEFAULT
	var half: Vector3 = tank.data.hull_size * 0.5
	for share: Vector3 in _data.pipes:
		var p: GPUParticles3D = SmokePuffs.make(_data.color, _data.start_size_m,
				_data.end_size_m, _data.lifetime_s)
		p.amount = maxi(int(ceil(_data.full_rate * _data.burst_factor * _data.lifetime_s)), 1)
		var process := p.process_material as ParticleProcessMaterial
		process.direction = Vector3.UP
		process.spread = _data.cone_deg
		process.initial_velocity_min = _data.rise_mps * 0.8
		process.initial_velocity_max = _data.rise_mps * 1.2
		process.damping_min = 0.3
		process.damping_max = 0.6
		# Rises on, drifting with the wind.
		process.gravity = Vector3(0.0, _data.rise_mps * 0.15, 0.0) + Weather.wind() * 0.15
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 0.15
		process.turbulence_enabled = true
		process.turbulence_noise_strength = _data.spread_mps
		process.turbulence_noise_scale = 4.0
		p.position = Vector3(share.x * half.x, share.y * half.y, share.z * half.z)
		add_child(p)
		_pipes.append(p)
	_last_position = tank.global_position
	_apply()


func _process(delta: float) -> void:
	var now: Vector3 = tank.global_position
	if delta > 0.0:
		var speed: float = (now - _last_position).length() / delta
		if speed <= MAX_PLAUSIBLE_SPEED:
			_speed = lerpf(_speed, speed, minf(delta * 8.0, 1.0))
	_last_position = now
	if tank.is_knocked_out():
		engine_load = 0.0
		for p: GPUParticles3D in _pipes:
			p.emitting = false
		return
	var top: float = maxf(tank.data.max_forward_speed_kmh * KMH_TO_MS, 0.1)
	var throttle: float = absf(tank.get_command().throttle)
	if throttle > _last_throttle + 0.3:
		_burst = 1.0   # a sharp throttle kick: a black puff
	_last_throttle = throttle
	_burst = maxf(_burst - delta / maxf(_data.burst_s, 0.01), 0.0)
	var target: float = clampf(maxf(throttle, _speed / top * 0.7), 0.0, 1.0)
	engine_load = lerpf(engine_load, target, minf(delta * _data.response, 1.0))
	_apply()


## Spotting share 0..1 (a burst counts as full load).
func get_spot_load() -> float:
	return clampf(maxf(engine_load, _burst), 0.0, 1.0)


func _apply() -> void:
	var rate: float = lerpf(_data.idle_rate, _data.full_rate, engine_load) \
			* (1.0 + (_data.burst_factor - 1.0) * _burst)
	var full_amount: float = _data.full_rate * _data.burst_factor
	var alpha: float = _data.color.a * lerpf(_data.idle_alpha_share, 1.0, maxf(engine_load, _burst))
	for p: GPUParticles3D in _pipes:
		p.emitting = true
		p.amount_ratio = clampf(rate / maxf(full_amount, 0.01), 0.0, 1.0)
		var mat := (p.draw_pass_1 as QuadMesh).material as StandardMaterial3D
		mat.albedo_color.a = alpha
