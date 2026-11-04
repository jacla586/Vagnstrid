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
## Stay hidden until reloaded plus this (s), at most hide_max_s in all.
@export var hide_extra_s: float = 1.0
@export var hide_max_s: float = 12.0
## Hit this many times from about the same direction within relocate_window_s: move
## to a new position away from that threat (0 = never).
@export var relocate_after_hits: int = 2
@export var relocate_window_s: float = 30.0
## The new position is looked for about this far away (m).
@export var relocate_distance_m: float = 80.0

