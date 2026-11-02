class_name FieldTreeData
extends TreeData
## One species of laser tree on a real map (TreeField). These trees have no fixed
## scale: each has its own height and crown radius from the laser data, so the trunk
## and the sight-blocking crown are worked out from those. trunk_diameter_m (from
## TreeData) is not used; fall time, fallen angle and shell snapping are.

## Trunk diameter per metre of tree height (m/m).
@export var trunk_diameter_per_height_m: float = 0.015
## Thinnest trunk, for small trees (m).
@export var min_trunk_diameter_m: float = 0.08
## Height of the crown's lower edge as a share of the tree height.
@export_range(0.0, 0.95) var crown_base_fraction: float = 0.3
## Radius of the sight-blocking crown as a share of the drawn crown radius.
@export var canopy_radius_factor: float = 0.85
## Height of the trunk collider as a share of the tree height (shells over it pass).
@export_range(0.1, 1.0) var trunk_height_fraction: float = 0.7


func trunk_diameter_for(height: float) -> float:
	return maxf(trunk_diameter_per_height_m * height, min_trunk_diameter_m)
