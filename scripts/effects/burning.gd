extends Node3D
## A fire (burning tank, MG nest): flames (EffectsSetData.fire_flames) and a smoke column
## (fire_smoke) that rises and leans with the wind (WeatherData.fire_smoke_drift_share).
## Scale the node for a smaller fire (the tank's fuel fire is 0.6).

const RISE_MPS2: float = 1.0


func _ready() -> void:
	var fx: EffectsSetData = EffectFx.SET
	var size: float = global_basis.get_scale().x
	if fx.fire_flames != null:
		var flames: GPUParticles3D = EffectFx.emitter(fx.fire_flames, size)
		flames.name = "Flames"
		add_child(flames)
		flames.emitting = true
	if fx.fire_smoke != null:
		var smoke: GPUParticles3D = EffectFx.emitter(fx.fire_smoke, size)
		smoke.name = "Smoke"
		# Its own copy: the lean follows this weather's wind share for fire smoke.
		var process := (smoke.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
		process.gravity = Vector3(0.0, RISE_MPS2, 0.0) \
				+ Weather.wind() * Weather.current().fire_smoke_drift_share
		smoke.process_material = process
		smoke.preprocess = 3.0
		add_child(smoke)
		smoke.emitting = true
