class_name TreeData
extends Resource
## One kind of tree. Size values are at scale 1; placed trees multiply by their scale.

## Trunk diameter at scale 1 (m). Decides which tanks can push it over.
@export var trunk_diameter_m: float = 0.5
## Time to fall once felled (s).
@export var fall_time_s: float = 1.6
## Tilt of a felled tree when it comes to rest (degrees from upright).
@export var fallen_angle_deg: float = 85.0
## Thickest trunk a main-gun shell hit snaps (m).
@export var shell_snap_max_diameter_m: float = 0.5
