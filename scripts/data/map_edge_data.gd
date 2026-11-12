class_name MapEdgeData
extends Resource
## The invisible edge every map has (MapEdge).

## The playable area ends this far inside the map's real edge (its picture's world
## rect), so nobody drives off the terrain (m).
@export var margin_m: float = 50.0
## A tank past the edge is pushed back in at this speed per metre it is out (m/s per m),
## at most push_max_mps.
@export var push_mps_per_m: float = 1.5
@export var push_max_mps: float = 3.0
