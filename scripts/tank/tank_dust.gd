class_name TankDust
extends Node3D
## Dust thrown up behind the tracks while a tank drives (EffectsSetData.track_dust), more
## the faster it goes, less in wet weather (WeatherData.dust_factor). Reads only how the
## tank moves, like TankExhaust, so puppets dust the same. Cosmetic: bots see through it.

## Faster than this between two frames is a teleport (respawn), not driving (m/s).
const MAX_PLAUSIBLE_SPEED: float = 60.0

var tank: Tank

var _emitters: Array[GPUParticles3D] = []
var _last_position: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _weather: float = 1.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var fx: EffectsSetData = EffectFx.SET
	_weather = Weather.current().dust_factor if Weather.current() != null else 1.0
	if fx.track_dust == null or _weather <= 0.0:
		set_process(false)
		return
	var half: Vector3 = tank.data.hull_size * 0.5
	var size: float = sqrt(tank.data.hull_size.x / 3.2)
	for side: float in [-1.0, 1.0]:
		var p: GPUParticles3D = EffectFx.emitter(fx.track_dust, size)
		p.one_shot = false
		# Behind the track, at the ground; the dust rises up and back.
		p.position = Vector3(side * half.x * 0.8, -half.y - 0.3, half.z * 0.95)
		p.emitting = false
		add_child(p)
		_emitters.append(p)
	_last_position = tank.global_position


func _process(delta: float) -> void:
	var now: Vector3 = tank.global_position
	if delta > 0.0:
		var speed: float = (now - _last_position).length() / delta
		if speed <= MAX_PLAUSIBLE_SPEED:
			_speed = lerpf(_speed, speed, minf(delta * 4.0, 1.0))
	_last_position = now
	var fx: EffectsSetData = EffectFx.SET
	var share: float = 0.0
	if not tank.is_knocked_out():
		share = clampf((_speed - fx.dust_min_speed_mps)
				/ maxf(fx.dust_full_speed_mps - fx.dust_min_speed_mps, 0.1), 0.0, 1.0) * _weather
	for p: GPUParticles3D in _emitters:
		p.emitting = share > 0.02
		p.amount_ratio = share
