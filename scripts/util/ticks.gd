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


## Light frames: a rendered frame without a physics tick in it. At 30 ticks and 60 frames a
## second every other frame carries a whole tick, so read-only work that may come a frame
## late (bots' and squads' looks round, `BotController._scan`, `Squad._scan`) waits for a
## light frame in _process instead, evening the frames out. Callers keep a fallback in the
## tick (`overdue`) for when there are no light frames (30 fps, a dedicated server).
static var _frame_seen: int = -1
static var _last_physics: int = -1
static var _ticked: bool = true

static func light_frame() -> bool:
	var frame: int = Engine.get_process_frames()
	if frame != _frame_seen:
		_frame_seen = frame
		var physics: int = Engine.get_physics_frames()
		_ticked = physics != _last_physics
		_last_physics = physics
	return not _ticked


## Ticks a deferred job may wait for a light frame before the tick does it itself.
const LIGHT_FRAME_WAIT_TICKS: int = 2
