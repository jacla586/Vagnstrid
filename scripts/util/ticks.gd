class_name Ticks
extends RefCounted
## Physics-tick helpers, so rates hold whatever physics/common/physics_ticks_per_second is
## (30 since 2026-11-09: a slow tank game needs no more, and every _physics_process,
## ray and body costs half).


## How many physics ticks apart something `hz` times a second should run (at least 1).
static func every(hz: float) -> int:
	return maxi(1, roundi(Engine.physics_ticks_per_second / maxf(hz, 0.001)))


## Time-based pacing for sends: adds `delta` to the running total in `state[0]` and
## returns true when 1/hz has passed (then takes it off, so the average rate holds).
static func due(state: PackedFloat32Array, delta: float, hz: float) -> bool:
	var period: float = 1.0 / hz
	state[0] = minf(state[0] + delta, period * 2.0)
	if state[0] < period:
		return false
	state[0] -= period
	return true
