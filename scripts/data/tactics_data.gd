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
## Multiplier for cells where bushes or crowns hide the tank (below 1 = prefer cover).
@export var concealed_factor: float = 0.7
