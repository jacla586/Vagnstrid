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

@export_group("Wear")
## Plates are split into square cells of this size (m). Hits that don't penetrate wear
## their cell, so heavy armour only gives way to shots that land close together.
@export var wear_cell_m: float = 0.75
## Worn armour never gets thinner than this share of the plate.
@export_range(0.0, 1.0) var wear_min_fraction: float = 0.4
## The eight neighbouring cells wear this share of the hit cell's wear.
@export_range(0.0, 1.0) var wear_neighbour_share: float = 0.5

@export_group("Ricochet")
## Hits flatter than this (angle from the plate's normal, degrees) bounce off.
@export var ricochet_angle_deg: float = 70.0
## Overmatch: a round much wider than the plate bites instead of glancing off. From this
## calibre/thickness ratio the ricochet angle rises towards 90°...
@export var overmatch_start_ratio: float = 2.5
## ...and at this ratio the round never bounces (e.g. 152 mm on 25 mm).
@export var overmatch_full_ratio: float = 6.0


## Thickness of a zone, e.g. ("hull", "side"). 0 if the zone is unknown.
func thickness_mm(part: String, face: String) -> float:
	var value: Variant = get("%s_%s_mm" % [part, face])
	return float(value) if value != null else 0.0
