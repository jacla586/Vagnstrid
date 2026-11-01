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

@export_group("Optics")
## Time for the commander to open or close the hatch (s).
@export var hatch_transition_time_s: float = 0.8
## Commander's vertical field of view with the hatch open, naked eye (degrees).
@export var commander_fov_deg: float = 70.0
## Binocular magnification (hatch open only).
@export var binocular_magnification: float = 6.0
## Pitch limits for the commander's head with the hatch open (degrees).
@export var open_pitch_min_deg: float = -40.0
@export var open_pitch_max_deg: float = 60.0
## Vertical field of view through the cupola periscope (degrees).
@export var periscope_fov_deg: float = 45.0
## Size of the periscope's visible window, as fractions of screen width/height.
@export var periscope_window_width: float = 0.55
@export var periscope_window_height: float = 0.22
## Max rotation speed of the periscope (degrees/s). Makes it feel sluggish.
@export var periscope_turn_speed_deg: float = 60.0
## How far the periscope can turn from turret forward (degrees). 180 = all round.
@export var periscope_yaw_limit_deg: float = 180.0
## Pitch limits through the periscope (degrees).
@export var periscope_pitch_min_deg: float = -10.0
@export var periscope_pitch_max_deg: float = 15.0
## Gunner's sight zoom levels as vertical field of view (degrees), widest first.
@export var gunner_sight_fov_deg: PackedFloat32Array = PackedFloat32Array([24.0, 12.0])
## Gunner's sight range ladder: a mark every step, out to max, labels every label step (m).
@export var sight_range_step_m: float = 100.0
@export var sight_range_max_m: float = 2000.0
@export var sight_range_label_step_m: float = 200.0
## Range where the gunner's sight line crosses the gun's bore (m). The sight sits
## beside the gun; boresighting at this range cancels that gap there and keeps it
## small at other ranges. 0 = sight parallel to the bore.
@export var sight_zero_range_m: float = 800.0

@export_group("Crew")
## How long a hit commander stays wounded (s): hatch locked shut meanwhile.
@export var commander_wound_time_s: float = 20.0

@export_group("Armour")
@export var armour: ArmourData

@export_group("Armament")
## Shell fired by the main gun; the sight's range ladder is calibrated for it.
@export var main_shell: ShellData
## Time to reload the main gun after a shot (s).
@export var reload_time_s: float = 6.0
## Backward impulse on the tank when firing (N·s). Tuned for feel, not history.
@export var recoil_impulse_ns: float = 30000.0
