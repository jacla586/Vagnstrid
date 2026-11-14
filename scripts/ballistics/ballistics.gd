class_name Ballistics
extends RefCounted
## Shared shell flight model: gravity + quadratic air drag. Simulated shells must
## advance with `integrate()` at the physics tick so they land where the sight says.
## Integration is Heun's method (exact for gravity alone, so the result barely
## depends on the tick rate).

## Sea-level air density (kg/m³).
const AIR_DENSITY: float = 1.225
## Steepest gun angle the range search will try (radians).
const MAX_SEARCH_ANGLE: float = deg_to_rad(15.0)
const SEARCH_ITERATIONS: int = 30
## Give up simulating a shot after this long (s).
const MAX_FLIGHT_TIME: float = 30.0


static func gravity() -> float:
	return ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


static func physics_step() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


## k in a_drag = -k·|v|·v (1/m): ½·ρ·Cd·A / m.
static func drag_factor(shell: ShellData) -> float:
	var radius: float = shell.caliber_mm * 0.0005
	var area: float = PI * radius * radius
	return 0.5 * AIR_DENSITY * shell.drag_coefficient * area / maxf(shell.mass_kg, 0.001)


## Acceleration of a shell moving at `velocity` (gravity + drag).
static func acceleration(velocity: Vector3, k: float) -> Vector3:
	return _acceleration(velocity, k, gravity())


## Advances a shell one step. Returns [new_position, new_velocity].
static func integrate(position: Vector3, velocity: Vector3, k: float,
		dt: float) -> PackedVector3Array:
	return _integrate(position, velocity, k, gravity(), dt)


## superelevation_for_range keeps found angles per shell in steps of this (m) and
## interpolates between them: bots ask every scan for both guns, and each search
## simulates the flight ~30 times.
const CACHE_STEP_M: float = 5.0

static var _angle_cache: Dictionary = {}   # ShellData instance id -> {step index: angle}


## Gun angle above the line of sight (radians) needed to hit a target at `range_m`
## on level ground at the gun's height. Returns MAX_SEARCH_ANGLE if out of reach.
## Cached in CACHE_STEP_M steps (linear between them: well under 0.01 mrad off).
static func superelevation_for_range(shell: ShellData, range_m: float) -> float:
	if range_m <= 0.0:
		return 0.0
	var table: Dictionary = _angle_cache.get(shell.get_instance_id(), {})
	if table.is_empty():
		_angle_cache[shell.get_instance_id()] = table
	var f: float = range_m / CACHE_STEP_M
	var i: int = floori(f)
	var a0: float = _cached_angle(shell, table, i)
	var a1: float = _cached_angle(shell, table, i + 1)
	if a1 >= MAX_SEARCH_ANGLE:
		return a1 if f - i > 0.5 or a0 >= MAX_SEARCH_ANGLE else a0
	return lerpf(a0, a1, f - i)


static func _cached_angle(shell: ShellData, table: Dictionary, i: int) -> float:
	if table.has(i):
		return table[i]
	var a: float = 0.0 if i <= 0 else search_superelevation(shell, i * CACHE_STEP_M)
	table[i] = a
	return a


## superelevation_for_range without the cache: a bisection over simulated flights.
static func search_superelevation(shell: ShellData, range_m: float) -> float:
	var k: float = drag_factor(shell)
	var g: float = gravity()
	if _height_at_range(shell, k, g, MAX_SEARCH_ANGLE, range_m) < 0.0:
		return MAX_SEARCH_ANGLE
	var low: float = 0.0
	var high: float = MAX_SEARCH_ANGLE
	for i: int in SEARCH_ITERATIONS:
		var mid: float = (low + high) * 0.5
		if _height_at_range(shell, k, g, mid, range_m) < 0.0:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5


## Height of the shell (m, relative to the muzzle) when it has travelled `range_m`
## horizontally, fired at `angle`. -INF if it never gets that far.
static func height_at_range(shell: ShellData, angle: float, range_m: float) -> float:
	return _height_at_range(shell, drag_factor(shell), gravity(), angle, range_m)


static func _height_at_range(shell: ShellData, k: float, g: float, angle: float,
		range_m: float) -> float:
	var dt: float = physics_step()
	var position := Vector3.ZERO
	var velocity := Vector3(shell.muzzle_velocity_mps * cos(angle),
			shell.muzzle_velocity_mps * sin(angle), 0.0)
	var time: float = 0.0
	while time < MAX_FLIGHT_TIME:
		var previous: Vector3 = position
		var next: PackedVector3Array = _integrate(position, velocity, k, g, dt)
		position = next[0]
		velocity = next[1]
		time += dt
		if position.x >= range_m:
			var t: float = (range_m - previous.x) / maxf(position.x - previous.x, 0.0001)
			return lerpf(previous.y, position.y, t)
	return -INF


static func _integrate(position: Vector3, velocity: Vector3, k: float, g: float,
		dt: float) -> PackedVector3Array:
	var a0: Vector3 = _acceleration(velocity, k, g)
	var a1: Vector3 = _acceleration(velocity + a0 * dt, k, g)
	var new_velocity: Vector3 = velocity + (a0 + a1) * 0.5 * dt
	var new_position: Vector3 = position + velocity * dt + (a0 * (2.0 / 3.0) + a1 * (1.0 / 3.0)) * 0.5 * dt * dt
	return PackedVector3Array([new_position, new_velocity])


static func _acceleration(velocity: Vector3, k: float, g: float) -> Vector3:
	return Vector3(0.0, -g, 0.0) - velocity * velocity.length() * k
