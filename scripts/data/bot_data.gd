class_name BotData
extends Resource
## How one kind of bot crew sees, shoots and handles its hatch. The tank's own
## abilities (optics, gun, MGs) come from its TankData; this is the crew's skill.

## Movement and positions (paths, scouting, ...). Null = data/bots/tactics_regular.tres.
@export var tactics: TacticsData

@export_group("Spotting")
## How often the commander looks around (s).
@export var scan_interval_s: float = 0.25
## Farthest the commander spots a tank with the hatch open / closed (m).
@export var view_range_open_m: float = 1200.0
@export var view_range_closed_m: float = 700.0
## Hatch closed: the periscope only covers this far either side of the turret (degrees).
@export var periscope_half_angle_deg: float = 60.0
## A tank must stay in sight this long before it counts as spotted (s).
@export var spot_time_open_s: float = 1.5
@export var spot_time_closed_s: float = 4.0
## A spotted tank out of sight this long is forgotten (s).
@export var forget_after_s: float = 8.0
## Cover and movement rules for the tanks this crew looks for. Null = ignored.
@export var concealment: ConcealmentData

@export_group("Gunnery")
## Range estimation error for the first shot, as a share of the true range (±).
@export var range_error_start: float = 0.3
## Random laying error for the first shot (mrad, up to this in any direction).
@export var lay_error_mrad: float = 8.0
## Misjudged target speed for the lead, as a share of the true speed (±).
@export var lead_error: float = 0.3
## Each shot multiplies all errors by this (the gunner corrects from the fall of shot).
@export var range_error_correction: float = 0.7
## The gun must stay on target this long before firing (s).
@export var aim_settle_s: float = 2.5
## How close the gun must point to the aim to count as on target (degrees).
@export var aim_tolerance_deg: float = 0.3
## Fires the main gun only below this speed (km/h): stops to shoot.
@export var max_fire_speed_kmh: float = 3.0

@export_group("Machine gun")
## Fires MGs at an exposed commander within this range (m).
@export var mg_range_m: float = 500.0
## Bursts: fire this long, then pause (s).
@export var mg_burst_s: float = 1.2
@export var mg_pause_s: float = 1.0
## Fires only when the MG points this close to the aim (degrees).
@export var mg_aim_tolerance_deg: float = 2.0

@export_group("Hatch")
## Rides with the hatch open when nothing threatens (sees more, but exposed).
@export var hatch_open_when_calm: bool = true
## Closes the hatch when a spotted enemy is this close (m).
@export var close_hatch_within_m: float = 300.0
## Keeps the hatch closed this long after the tank is hit (s).
@export var close_hatch_after_hit_s: float = 15.0
## After closing, waits this long without contact before opening again (s).
@export var reopen_calm_s: float = 10.0
