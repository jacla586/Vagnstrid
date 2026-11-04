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

