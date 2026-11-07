class_name TacticsData
extends Resource
## How a bot crew moves and picks positions (BotData.tactics). The path costs are
## per cell of the tactical grid, relative to open ground (1.0).

@export_group("Path costs")
## Paved or gravel road (fast).
@export var cost_road: float = 0.8
@export var cost_open: float = 1.0
## Trees (felling them is slow).
@export var cost_forest: float = 1.8
@export var cost_wet: float = 2.5
## Next to a house or stone (keeps paths off walls; alleys stay usable).
@export var cost_near_blocked: float = 3.0
## Trees too thick to push over: the tank has to weave round them.
@export var cost_thick_trees: float = 3.0
## Open ground right beside forest or bushes: along the tree line, fast and half hidden.
@export var cost_cover_edge: float = 0.75
## Multiplier for cells where bushes or crowns hide the tank (below 1 = prefer cover).
@export var concealed_factor: float = 0.6

@export_group("Scouting")
## Before an open stretch at least this long (m, no bushes, trees or houses beside the
## way), stop at the last covered spot and look...
@export var scout_open_m: float = 150.0
## ...for this long, hatch open (s). Keep it short: bots must keep moving.
@export var scout_time_s: float = 5.0
## At least this far between two scouting stops on one path (m).
@export var scout_min_spacing_m: float = 300.0
## No scouting stops within this long after contact (an enemy seen, reported or a hit; s).
@export var scout_skip_after_contact_s: float = 30.0

@export_group("Positions")
## Candidate spots tried when choosing where to stand.
@export var position_candidates: int = 24
## Score for a spot with something beside it (bushes, trees, tree line, houses)...
@export var w_cover: float = 2.0
## ...and extra when bushes or crowns hide the tank itself.
@export var w_concealed: float = 1.5
## Hull down: ground towards the threat 0.8-1.8 m higher than the spot, a few metres
## ahead (hull hidden, gun and commander over the crest). Higher ground that hides the
## view counts against.
@export var w_hull_down: float = 3.0
## Per sight line (of 3) from the commander's eye to the area to watch.
@export var w_sight: float = 2.0
## Penalty for standing closer than spread_min_m to a teammate (or his goal).
@export var w_spacing: float = 3.0
@export var spread_min_m: float = 40.0
## Penalty per 100 m of driving to the spot.
@export var w_travel: float = 0.5

@export_group("Bounding")
## Closer than this to the objective's edge (or after contact), pairs move up in turns:
## one watches from a position while the other drives to the next one (m).
@export var bound_start_m: float = 300.0
## Each move goes at most this far forward (m).
@export var bound_length_m: float = 200.0
## The watcher goes anyway after this long (s): keep moving.
@export var overwatch_max_s: float = 15.0
## A bot without a partner halts this long between its own moves (s).
@export var solo_halt_s: float = 5.0
## Contact this recent switches to bounding even far from the objective (s).
@export var bound_after_contact_s: float = 30.0

@export_group("Shoot and scoot")
## After a shot, back out of the target's sight while reloading, then come up again a
## little to the side (not where the enemy last saw the flash).
@export var shoot_and_scoot: bool = true
## Hide spots are looked for this far back (m)...
@export var hide_distance_min_m: float = 8.0
@export var hide_distance_max_m: float = 25.0
## ...and the next firing spot this far to the side of the last one (m).
@export var peek_side_min_m: float = 5.0
@export var peek_side_max_m: float = 15.0
## Chance to back off after a shot (0..1); otherwise the tank stays up and fights.
@export var scoot_chance: float = 1.0
## Stay hidden until reloaded plus this (s), at most hide_max_s in all.
@export var hide_extra_s: float = 1.0
@export var hide_max_s: float = 12.0
## Pulling back: each gun round that hits or nearly misses (Tank.shell_threat) within
## relocate_window_s of the last one may send the tank to a new position away from
## that threat. Chance per count: [after 1, after 2, after 3...]; the last value holds
## for more (empty = never).
@export var relocate_chance_by_hits: Array[float] = [0.3, 0.85, 1.0]
@export var relocate_window_s: float = 30.0
## The new position is looked for about this far away (m)...
@export var relocate_distance_m: float = 80.0
## ...and held this long after getting there before other orders take over (s).
@export var relocate_hold_s: float = 6.0
## Under fire a crew first looks for an answer: it stays and fights if the gun can bear
## on the shooter within answer_time_s (reload + traverse), unless exposed_hits rounds
## came in a row. Else it backs into cover if a hide spot is near; only with neither
## is it too exposed: smoke and a new position.
@export var answer_time_s: float = 3.0
@export var exposed_hits: int = 3
## The target counts as the shooter within this angle of where the round came from.
@export var answer_cone_deg: float = 30.0


@export_group("Aggression")
## Throttle for drives to the objective and hunts (KothBots).
@export var travel_throttle: float = 0.7
## On the way somewhere, halt to fire only at targets within this range (m).
@export var transit_fire_range_m: float = 100000.0
## Hunting: go after an enemy seen or reported within hunt_memory_s (s), up to
## hunt_range_m (m) from the tank, if it is no further than hunt_zone_margin_m (m)
## outside the zone (where kills pay and where it scores). 0 range = never hunt.
@export var hunt_range_m: float = 0.0
@export var hunt_memory_s: float = 20.0
@export var hunt_zone_margin_m: float = 250.0
## Drive to a firing spot about this far from the enemy's last known position (m);
## already closer than this with it in sight: just fight from where it is.
@export var hunt_engage_m: float = 250.0
## Give a hunt up after this long (s) and go back to the zone orders.
@export var hunt_max_s: float = 40.0
