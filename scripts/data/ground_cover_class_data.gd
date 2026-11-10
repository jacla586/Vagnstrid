class_name GroundCoverClassData
extends Resource
## One ground-cover class (grass, crop, reed...): how tall it stands (hides soldiers,
## GroundCover) and how it is drawn (GroundCoverField near the camera, GroundCoverCanopy
## beyond it). Classes are indexed as in the map's GroundCoverData raster.

@export var name: String = ""
## Height of the vegetation's top (m). 0 = nothing grows here.
@export var height_m: float = 0.0
## Clumps per square metre drawn (0 = not drawn).
@export var density: float = 0.0
## Blades per clump, and their width at the base (m).
@export var blades: int = 7
@export var blade_width_m: float = 0.05
## Clump radius (m): how far blades spread from the clump's centre.
@export var spread_m: float = 0.18
## Height spread: each clump is height_m × (1 ± this).
@export var height_jitter: float = 0.25
## Lean of the blades (0 straight up, 1 = 45°).
@export var lean: float = 0.35
## Tip colour range (the base is darker); each clump picks between them.
@export var color_a: Color = Color(0.45, 0.6, 0.25)
@export var color_b: Color = Color(0.55, 0.62, 0.3)
## Ears on top (crops): this many of the blades get a small seed head.
@export var heads: int = 0
@export var head_color: Color = Color(0.8, 0.72, 0.4)
