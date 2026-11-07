class_name KothData
extends Resource
## Rules of King of the Hill (data/modes/*.tres). Zones come one at a time at random
## spots: a zone appears at full size, holds for zone_hold_s, then shrinks (scoring
## faster). It closes when it has paid out zone_point_budget, or at zone_lifetime_s,
## and zone_gap_s later the next one opens (its spot shows on the map in the gap). The zone is never contested: every team
## scores for its own tanks in it, the team with more tanks there scores more, and
## knocking out an enemy in the zone from inside it gives a bonus. Each new zone moves
## the teams' spawns: south team south of it, the others north.

@export_group("Zones")
## Zones per match; after the last the best score wins. 0 = no limit (score_to_win).
@export var zone_count: int = 0
## Points one zone gives out in all (zone scoring and kill bonuses); then it closes.
@export var zone_point_budget: float = 1000.0
## A zone stays at full size this long after it opens (s)...
@export var zone_hold_s: float = 120.0
## ...then shrinks, closing at the latest this long after opening (s).
@export var zone_lifetime_s: float = 300.0
## Pause between one zone disappearing and the next opening (s).
@export var zone_gap_s: float = 30.0
## Radius when the zone opens, and when it disappears (m, horizontal).
@export var radius_start_m: float = 300.0
@export var radius_end_m: float = 60.0

@export_group("Scoring")
## Points per second for each counted tank in the zone, at full size and at the end
## of the shrink (in between it follows the shrink).
@export var points_per_tank_start: float = 0.5
@export var points_per_tank_end: float = 4.0
## At most this many tanks per team count in the zone (no winning by crowding).
@export var max_counted_tanks: int = 4
## The team with the most tanks in the zone (no tie) scores this many times more.
@export var majority_multiplier: float = 1.5
## Points for knocking out an enemy in the zone while in it, times a factor that
## follows the shrink from start to end.
@export var kill_bonus_points: float = 75.0
@export var kill_bonus_factor_start: float = 1.0
@export var kill_bonus_factor_end: float = 3.0
## True: the bonus needs the shooter in the zone too. False: any knock-out of an enemy
## in the zone pays, wherever it was fired from (support from outside counts).
@export var kill_bonus_needs_shooter_in_zone: bool = true
## First team to this many points wins.
@export var score_to_win: float = 3000.0
## How often the zone is counted (s).
@export var tick_interval_s: float = 0.25

@export_group("Zone placement")
## SPOTS: zones open at the hand-placed Marker3D spots. ROAMING: the first zone opens at
## a spot, each later one at a fair random place roam_min_m..roam_max_m from the last
## (mostly along the front, similar travel time and cover for both teams).
enum Placement { SPOTS, ROAMING }
@export var zone_placement: Placement = Placement.SPOTS
@export var roam_min_m: float = 400.0
@export var roam_max_m: float = 700.0
## Candidate places tried (one per physics frame, so the choice takes about this many frames).
@export var roam_candidates: int = 30
## Zone centres stay this far inside the map edge (m).
@export var roam_edge_margin_m: float = 400.0
## The team with the longer way may need at most this many times the other's travel cost.
@export var roam_max_travel_ratio: float = 1.25
## Best share of covered cells inside the zone (cover in it, open ground round it).
@export var roam_cover_target: float = 0.35
## Score for a candidate near (within the zone radius of) a hand-placed spot.
@export var roam_marker_bonus: float = 0.5
## The new zone is picked at random among this many best candidates.
@export var roam_top_picks: int = 4

@export_group("Bot tactics")
## Bots of a team split onto attack axes (left, centre, right of their side), meet at an
## assembly point outside the zone in pairs and bound in along their own axis.
@export var bot_attack_axes: bool = false
## Angle between the centre axis and each side axis (degrees).
@export var axis_spread_deg: float = 55.0
## Assembly points lie this far outside the zone edge on the axis (m).
@export var assembly_distance_m: float = 450.0
## At the assembly point a bot waits at most this long for its partner (s).
@export var assembly_wait_max_s: float = 18.0
## Bots per team that support from outside the zone instead of going in.
@export var support_per_team: int = 0
## Support positions lie this far outside the zone edge (m).
@export var support_distance_min_m: float = 120.0
@export var support_distance_max_m: float = 300.0

@export_group("Spawns")
## Spawns lie this far from the zone centre, straight south / north (m)...
@export var spawn_distance_m: float = 800.0
## ...or closer, down to this, if the ideal spot is off the map, in water or in a house.
@export var spawn_min_distance_m: float = 400.0
## Spawns stay at least this far from enemy tanks (m) when the ground allows: the axis
## is turned, then brought closer, before giving up on it.
@export var spawn_enemy_clear_m: float = 350.0
## This team spawns south of the zone (first zone; later on its own side, see KothMode);
## every other team on the other side.
@export var south_team: int = 0
## Tanks of one team spawn this far apart, side by side (m).
@export var spawn_spacing_m: float = 15.0
## Knocked-out bots come back at their team's spawn after this long (s).
@export var bot_respawn_delay_s: float = 12.0
## Bot tanks without a config of their own get a random one of these (empty = as placed).
@export var bot_configs: Array[TankConfig] = []
