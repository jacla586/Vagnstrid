class_name TankData
extends Resource
## All tuning values for one tank type. Code reads these; no balance numbers in code.
## Values are mostly accelerations, so tuning doesn't depend on the tank's mass.

@export var display_name: String = "Unnamed tank"

@export_group("Mass")
@export var mass_kg: float = 30000.0

@export_group("Mobility")
## Top speed driving forward (km/h).
@export var max_forward_speed_kmh: float = 40.0
## Top speed in reverse (km/h).
@export var max_reverse_speed_kmh: float = 8.0
## How fast the tank speeds up (m/s²).
@export var acceleration: float = 1.5
## How fast the tank slows down when throttle is released or reversed (m/s²).
@export var brake_deceleration: float = 4.0
## Max yaw rate when steering fully (degrees/s).
@export var max_turn_rate_deg: float = 30.0
## How fast the yaw rate builds up or stops (degrees/s²).
@export var turn_acceleration_deg: float = 90.0
## Max sideways acceleration the tracks can take before sliding (m/s²).
@export var track_lateral_grip: float = 8.0

@export_group("Suspension")
## Length of each suspension ray: how far the road wheels reach below the hull (m).
@export var suspension_rest_length: float = 0.6
## Natural bounce frequency of the sprung hull (Hz). Higher = stiffer.
@export var suspension_frequency_hz: float = 1.5
## 1.0 = critically damped (no bounce), lower = bouncier.
@export var suspension_damping_ratio: float = 0.6

@export_group("Turret")
## How fast the turret turns relative to the hull (degrees/s).
@export var turret_traverse_speed_deg: float = 20.0
## How fast the gun elevates/depresses (degrees/s).
@export var gun_elevation_speed_deg: float = 5.0
## Max gun elevation above the turret's horizontal plane (degrees).
@export var gun_max_elevation_deg: float = 20.0
## Max gun depression below the turret's horizontal plane (degrees, positive number).
@export var gun_max_depression_deg: float = 8.0
