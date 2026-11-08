class_name ExhaustData
extends Resource
## A tank's exhaust smoke (TankData.exhaust; null = data/tanks/exhaust_default.tres).
## Thin at idle, thick dark smoke under load: it shows over cover and gives the tank
## away (the spotting side is in ConcealmentData.exhaust_*, same for everyone).

## Smoke puffs per second per pipe at idle and at full load.
@export var idle_rate: float = 1.5
@export var full_rate: float = 10.0
## A throttle kick gives a burst this many times the load rate, fading over burst_s.
@export var burst_factor: float = 1.8
@export var burst_s: float = 1.5
## How fast the load follows the engine (1/s).
@export var response: float = 3.0
## Puff colour (alpha = opacity at full load; at idle it is idle_alpha_share of it).
@export var color: Color = Color(0.09, 0.085, 0.08, 0.4)
@export_range(0.0, 1.0) var idle_alpha_share: float = 0.45
## Puff size when it leaves the pipe and when it fades (m), and its life (s).
@export var start_size_m: float = 0.35
@export var end_size_m: float = 2.2
@export var lifetime_s: float = 3.5
## Rise speed of a puff (m/s), its cone round straight up (degrees) and how much
## turbulence pushes it sideways (m/s).
@export var rise_mps: float = 2.2
@export var cone_deg: float = 8.0
@export var spread_mps: float = 0.3
## Pipe positions as shares of the hull's half size (x across, y up, z back).
@export var pipes: PackedVector3Array = PackedVector3Array([
	Vector3(-0.45, 1.0, 0.85), Vector3(0.45, 1.0, 0.85)])
