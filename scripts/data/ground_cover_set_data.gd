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
## GroundCoverField draws blade clumps in square cells of cell_m. Distances below are
## "seen" distances: the true distance divided by the camera's zoom against
## reference_fov_deg, so the gunner's sight and binoculars draw grass as far out as it
## looks near (only inside their narrow view).
@export var cell_m: float = 24.0
@export var reference_fov_deg: float = 70.0
## Full clump density out to this seen distance (m); beyond, the clumps thin as
## (full_density_m / d)^thin_exponent and the survivors widen by 1/sqrt of that (at most
## max_widen times), so the grass covers the ground about the same. 2 would keep the
## clumps per pixel across the view; more thins faster towards the horizon, where depth
## crowds them (and a zoomed view sees mostly far ground).
@export var full_density_m: float = 30.0
@export var thin_exponent: float = 3.0
@export var max_widen: float = 5.0
## A zoomed view looks along the ground at a flatter angle, so each pixel row holds more
## depth (and more clumps) than at the same seen distance unzoomed: the clumps are also
## thinned by 1 / zoom^zoom_thin_exponent (1 would keep the clumps per pixel the same).
@export var zoom_thin_exponent: float = 0.6
## Far blades lose their dark bases and light tips (they turn to stripes otherwise): the
## contrast is gone at this share of blade_range_m.
@export var flat_colour_share: float = 0.6
## The blades end at this seen distance (m), thinning out over the last quarter;
## GroundCoverCanopy (the flat far vegetation) dithers in under them from
## canopy_fade_start..canopy_fade_end × blade_range_m.
@export var blade_range_m: float = 130.0
@export var canopy_fade_start: float = 0.6
@export var canopy_fade_end: float = 0.9
## Never farther than this true distance (m), however strong the zoom.
@export var max_reach_m: float = 800.0
## Time spent building cells per frame at most (ms; at least one cell a frame).
@export var build_ms_per_frame: float = 2.0
## Cells no longer wanted are kept hidden this long (s): back from the binoculars at once.
@export var keep_hidden_s: float = 30.0
## Wind sway (m at the tip) and its speed.
@export var wind_sway_m: float = 0.06
