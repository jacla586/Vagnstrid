extends Node3D
## A fire (burning tank, MG nest): the smoke rises and leans with the wind (Weather).

const RISE_MPS2: float = 1.2


func _ready() -> void:
	var smoke := get_node_or_null(^"Smoke") as CPUParticles3D
	if smoke != null:
		smoke.gravity = Vector3(0.0, RISE_MPS2, 0.0) \
				+ Weather.wind() * Weather.current().fire_smoke_drift_share
