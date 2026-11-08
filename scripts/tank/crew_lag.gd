class_name CrewLag
extends RefCounted
## A wounded crew member answers late (Tank, host only, so bots and players alike).
## Driver: every throttle/steering change gets its own delay, rolled between min and
## max, never overtaking an earlier change. Gunner: aim, main-gun and coaxial MG fire
## are played back from a moment ago; the delay drifts slowly between min and max so the
## gun never jumps back in time. Everything else in the command passes straight through.

## Driving changes smaller than this aren't a new order.
const DRIVE_EPSILON: float = 0.05
## How fast the gunner's delay may drift (s per s): below 1, time never runs backwards.
const DRIFT_RATE: float = 0.25
## Gunner history kept (s): more than the longest delay.
const HISTORY_S: float = 3.0

var _out: TankCommand = TankCommand.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _clock: float = 0.0
# driver: queued [apply_at, throttle, steering]; the current values
var _drive_queue: Array = []
var _drive_last_in: Vector2 = Vector2.ZERO
var _drive_last_at: float = 0.0
var _drive_now: Vector2 = Vector2.ZERO
var _driver_was_wounded: bool = false
# gunner: [time, has_aim, aim_point, fire, fire_mg]
var _aim_history: Array = []
var _gunner_lag: float = 0.0
var _gunner_lag_goal: float = 0.0
var _gunner_sampled_to: float = 0.0


func _init() -> void:
	_rng.randomize()


## The command the tank acts on this physics frame.
func apply(command: TankCommand, delta: float, data: TankData, driver_wounded: bool,
		gunner_wounded: bool) -> TankCommand:
	_clock += delta
	_copy(command, _out)
	_drive(command, data, driver_wounded)
	_gunner(command, delta, data, gunner_wounded)
	return _out


func _drive(command: TankCommand, data: TankData, wounded: bool) -> void:
	var wanted := Vector2(command.throttle, command.steering)
	if not wounded:
		if _driver_was_wounded:
			_drive_queue.clear()
		_driver_was_wounded = false
		_drive_last_in = wanted
		_drive_now = wanted
		_drive_last_at = _clock
		return
	_driver_was_wounded = true
	if (wanted - _drive_last_in).length() > DRIVE_EPSILON:
		var at: float = maxf(_clock + _rng.randf_range(data.driver_wounded_lag_min_s,
				maxf(data.driver_wounded_lag_max_s, data.driver_wounded_lag_min_s)), _drive_last_at)
		_drive_queue.append([at, wanted])
		_drive_last_in = wanted
		_drive_last_at = at
	while not _drive_queue.is_empty() and float(_drive_queue[0][0]) <= _clock:
		_drive_now = _drive_queue.pop_front()[1]
	_out.throttle = _drive_now.x
	_out.steering = _drive_now.y


func _gunner(command: TankCommand, delta: float, data: TankData, wounded: bool) -> void:
	_aim_history.append([_clock, command.has_aim, command.aim_point, command.fire,
			command.fire_mg and not command.mg_use_roof])
	while _aim_history.size() > 2 and _clock - float(_aim_history[1][0]) > HISTORY_S:
		_aim_history.pop_front()
	var lo: float = data.gunner_wounded_lag_min_s
	var hi: float = maxf(data.gunner_wounded_lag_max_s, lo)
	if not wounded:
		_gunner_lag = 0.0
		_gunner_lag_goal = lo
		_gunner_sampled_to = _clock
		return
	if absf(_gunner_lag_goal - _gunner_lag) < 0.01:
		_gunner_lag_goal = _rng.randf_range(lo, hi)
	_gunner_lag = move_toward(_gunner_lag, _gunner_lag_goal, DRIFT_RATE * delta)
	var at: float = _clock - _gunner_lag
	# The state at `at`, and any fire pressed since the last sample (short presses count).
	var sample: Array = _aim_history[0]
	var fire: bool = false
	var fire_mg: bool = false
	for entry: Array in _aim_history:
		var t: float = float(entry[0])
		if t > at:
			break
		sample = entry
		if t > _gunner_sampled_to:
			fire = fire or bool(entry[3])
			fire_mg = fire_mg or bool(entry[4])
	_gunner_sampled_to = maxf(_gunner_sampled_to, at)
	_out.has_aim = bool(sample[1])
	_out.aim_point = sample[2]
	_out.fire = fire or bool(sample[3])
	if not command.mg_use_roof:
		_out.fire_mg = fire_mg or bool(sample[4])


static func _copy(from: TankCommand, to: TankCommand) -> void:
	to.throttle = from.throttle
	to.steering = from.steering
	to.aim_point = from.aim_point
	to.has_aim = from.has_aim
	to.hatch_open = from.hatch_open
	to.ammo_select = from.ammo_select
	to.fire = from.fire
	to.fire_mg = from.fire_mg
	to.mg_use_roof = from.mg_use_roof
	to.mg_aim_point = from.mg_aim_point
	to.spot = from.spot
	to.spot_point = from.spot_point
	to.squad_order = from.squad_order
	to.squad_target = from.squad_target
	to.smoke = from.smoke
	to.abandon = from.abandon
