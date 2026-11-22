class_name BotData
extends Resource
## How one kind of bot crew sees, shoots and handles its hatch. The tank's own
## abilities (optics, gun, MGs) come from its TankData; this is the crew's skill.

## Movement and positions (paths, scouting, ...). Null = data/bots/tactics_regular.tres.
@export var tactics: TacticsData

@export_group("Spotting")
## How often the commander looks around (s).
@export var scan_interval_s: float = 0.25
## Against more enemy tanks than this the interval stretches with their number (each
## look covers them all), up to scan_max_stretch times: 20 v 20 looks round every 0.5 s.
## The time in between still counts towards spotting.
@export var scan_reference_enemies: int = 10
@export var scan_max_stretch: float = 2.0
## Tanks farther away than these ranges (m) are looked at only every 2nd / 4th scan (the
## time in between still counts towards spotting): fewer sight lines, same rules. The
## current target is looked at every scan.
@export var look_every_2nd_beyond_m: float = 250.0
@export var look_every_4th_beyond_m: float = 600.0
## Enemy soldiers are each looked at afresh every this many look rounds (by index, in turn);
## between, his last answer stands while the spotting time runs on (SquadData has the same).
## Always afresh: the squad in the MG's sights, men within soldier_look_full_m, a man who
## just fired, and answers older than this many rounds. 1 = every round.
@export var soldier_look_rounds: int = 4
@export var soldier_look_full_m: float = 100.0
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
## Like a player, the commander marks enemies he sees for the team (minimap), with the
## same spot cooldown; one still in sight is marked again after this long (s).
@export var spot_remark_s: float = 12.0
## Cover and movement rules for the tanks this crew looks for. Null = ignored.
@export var concealment: ConcealmentData

@export_group("Far from players")
## Beyond this distance (m) from every human player's tank and the camera (Relevance), the
## crew thinks far_think_hz times a second and looks round far_scan_factor times as seldom:
## the same rules at a slower pace (a fight nobody watches). Near again within far_m.
@export var far_m: float = 400.0
@export var far_margin_m: float = 100.0
@export var far_think_hz: float = 7.5
@export var far_scan_factor: float = 2.0

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
## Fires the main gun only below this speed (km/h): stops to shoot...
@export var max_fire_speed_kmh: float = 3.0
## ...except on the move in the open (no cover for a halt): then it fires on the move
## at targets within this range (m; 0 = never), with a looser lay, a shorter settle and
## an extra laying error per m/s of own speed (mrad).
@export var move_fire_range_m: float = 300.0
@export var move_aim_tolerance_deg: float = 1.0
@export var move_aim_settle_s: float = 0.8
@export var move_lay_error_mrad_per_mps: float = 1.5
## Within this range (m) the gun also counts as on target when a ray along the barrel
## hits the target tank, whatever the angle: up close the turret's pivot and the muzzle
## see the aim from different places (degrees off), and a target below the gun's
## depression is still hit in the hull. Like a player who sees the sight on the tank.
@export var barrel_ray_range_m: float = 80.0

@export_group("Repair")
## Without a destroyed module or thrown track, the crew only stops to repair below
## this share of structure hp; lighter damage mends while it holds a position anyway.
@export var repair_stop_hp_fraction: float = 0.4

@export_group("Stuck")
## Trying to drive but not this far from where it was (m) for abandon_stuck_s (s): the
## crew abandons the tank (hung on a rock) and it respawns, like a player can.
@export var abandon_stuck_m: float = 8.0
@export var abandon_stuck_s: float = 60.0
## Driving with throttle but covering less than 0.5 m/s over this long (s) counts as
## stuck: the bot reverses unstick_reverse_s (s), then plans round the spot. Used when
## the controller's own unstick_after_s is 0 (the KotH scenarios' bots).
@export var unstick_after_s: float = 3.0
@export var unstick_reverse_s: float = 2.5

@export_group("Machine gun")
## Fires MGs at an exposed commander within this range (m).
@export var mg_range_m: float = 500.0
## Bursts: fire this long, then pause (s).
@export var mg_burst_s: float = 1.2
@export var mg_pause_s: float = 1.0
## Fires only when the MG points this close to the aim (degrees).
@export var mg_aim_tolerance_deg: float = 2.0
## A commander who comes up out of his hatch is fired on only after his head has been in
## sight this long (s, random between the two, drawn each time he shows): the crew has to
## notice him and swing the MG. Without it a spotted tank's commander was hit as the hatch
## opened.
@export var head_reaction_min_s: float = 1.6
@export var head_reaction_max_s: float = 3.2

@export_group("Hatch")
## Rides with the hatch open when nothing threatens (sees more, but exposed).
@export var hatch_open_when_calm: bool = true
## Closes the hatch when a spotted enemy is this close (m).
@export var close_hatch_within_m: float = 300.0
## Keeps the hatch closed this long after the tank is hit (s).
@export var close_hatch_after_hit_s: float = 15.0
## After closing, waits this long without contact before opening again (s).
@export var reopen_calm_s: float = 10.0
