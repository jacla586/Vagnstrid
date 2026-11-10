class_name GroundCoverSetData
extends Resource
## The ground-cover classes and the rules for how they hide soldiers
## (data/world/ground_cover.tres). See GroundCover.

@export var classes: Array[GroundCoverClassData] = []

@export_group("Hiding soldiers")
## Height of a soldier's visible body by stance (m).
@export var body_height_standing_m: float = 1.75
@export var body_height_kneeling_m: float = 1.0
@export var body_height_prone_m: float = 0.35
## Vegetation lower than this hides nothing (a lawn); above it the hidden share grows to 1
## where it reaches the body's height.
@export var min_hiding_height_m: float = 0.1
## The vegetation hides fully when seen along the ground; looking down from above it
## hides less: full effect up to grazing_full_deg, none from grazing_none_deg.
@export var grazing_full_deg: float = 4.0
@export var grazing_none_deg: float = 35.0
## Spot time × (1 + hidden × this): hidden = share of the body below the vegetation.
@export var hide_spot_time_factor: float = 6.0
## Spot range × (1 − hidden × this).
@export var hide_range_share: float = 0.6

@export_group("Drawing")
## GroundCoverField: vegetation drawn this far from the camera (m), in square cells.
@export var draw_radius_m: float = 55.0
@export var cell_m: float = 24.0
## GroundCoverCanopy (the flat far vegetation) dithers in this far inside the radius,
## under the outer blades.
@export var fade_m: float = 10.0
## Wind sway (m at the tip) and its speed.
@export var wind_sway_m: float = 0.06
