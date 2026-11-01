class_name ArmourData
extends Resource
## Armour of one tank type: plate thickness per zone (mm, measured straight on).
## Effective thickness grows with the impact angle; see Armour.

@export_group("Hull")
@export var hull_front_mm: float = 80.0
@export var hull_side_mm: float = 45.0
@export var hull_rear_mm: float = 30.0
@export var hull_roof_mm: float = 15.0

@export_group("Turret")
@export var turret_front_mm: float = 90.0
@export var turret_side_mm: float = 50.0
@export var turret_rear_mm: float = 40.0
@export var turret_roof_mm: float = 20.0

@export_group("Ricochet")
## Hits flatter than this (angle from the plate's normal, degrees) bounce off.
@export var ricochet_angle_deg: float = 70.0


## Thickness of a zone, e.g. ("hull", "side"). 0 if the zone is unknown.
func thickness_mm(part: String, face: String) -> float:
	var value: Variant = get("%s_%s_mm" % [part, face])
	return float(value) if value != null else 0.0
