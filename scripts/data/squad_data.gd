class_name SquadData
extends Resource
## One kind of infantry squad that rides on a tank (TankData.squad). The squad is one
## unit of a few soldiers: sent by clicking the big map, recalled with a key, never
## further than max_distance_from_tank_m from its tank.

@export var display_name: String = "Rifle squad"
@export var soldier_count: int = 4

@export_group("Movement")
## Running speed on open ground (m/s).
@export var run_speed_mps: float = 4.0
## Path costs for walking (forest and bushes cheap, open ground dear).
@export var tactics: TacticsData
## Soldiers keep about this far apart in their wedge (m).
@export var spacing_m: float = 4.0
## Orders are cut off at this distance from the tank (m)...
@export var max_distance_from_tank_m: float = 300.0
## ...and if the tank drives more than this beyond it, the squad comes back (m).
@export var leash_margin_m: float = 60.0
## Getting this close to its tank while coming back, the squad mounts (m).
@export var mount_distance_m: float = 8.0
## Soldiers get off this far behind the tank (m).
@export var dismount_behind_m: float = 6.0

@export_group("Look")
## Holding still the soldiers kneel: height as a share of standing...
@export var kneel_height_share: float = 0.6
## ...taking this long to kneel or get up (s).
@export var stance_change_s: float = 0.5
## The leader's eyes, standing and kneeling (m above the ground).
@export var eye_height_standing_m: float = 1.65
@export var eye_height_kneeling_m: float = 1.05
## Field of view through the leader's eyes, and through his binoculars (degrees).
@export var view_fov_deg: float = 70.0
@export var binocular_fov_deg: float = 10.0
## Uniform colour: green or brown, naturally hard to see.
@export var uniform_color: Color = Color(0.29, 0.36, 0.2)
## Soldier size (m).
@export var soldier_height_m: float = 1.8
@export var soldier_radius_m: float = 0.3
