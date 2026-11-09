class_name BurstData
extends Resource
## One particle burst of a visual effect (EffectData): dirt, sparks, dust, smoke, flame.
## Directions are in the effect's own space, where +Y is "out" (the surface normal of
## an impact, the barrel's direction of a muzzle flash). Sizes and speeds are scaled by
## the effect's scale (shell size).

@export var amount: int = 12
@export var lifetime_s: float = 1.0
## 1 = all at once, 0 = spread over the lifetime (continuous emitters ignore it).
@export_range(0.0, 1.0) var explosiveness: float = 1.0
@export_range(0.0, 1.0) var lifetime_randomness: float = 0.3

@export_group("Motion")
@export var direction: Vector3 = Vector3.UP
@export_range(0.0, 180.0) var spread_deg: float = 30.0
@export var speed_min_mps: float = 2.0
@export var speed_max_mps: float = 6.0
## World gravity on the particles (m/s², not scaled).
@export var gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
## Share of the weather's wind added to gravity (smoke and dust drift).
@export_range(0.0, 1.0) var wind_share: float = 0.0
@export var damping: float = 0.0
## Particles start anywhere in a sphere this big (m).
@export var emission_radius_m: float = 0.1

@export_group("Look")
@export var size_start_m: float = 0.3
@export var size_end_m: float = 0.6
@export_range(0.0, 1.0) var size_randomness: float = 0.4
@export var color_start: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var color_end: Color = Color(1.0, 1.0, 1.0, 0.0)
## Glowing (fire, sparks, flash): added light, unshaded.
@export var additive: bool = false
## Stretched along the motion (sparks); `stretch` = length / width.
@export var align_to_velocity: bool = false
@export var stretch: float = 1.0
## Soft round puff (smoke, dust, fire) or a hard-edged chunk (dirt, splinters).
@export var soft: bool = true
## Soft puffs closer to the camera than this fade out (m; 0 = off): a cloud right in
## front of the view (own gun smoke) costs much less to draw.
@export var near_fade_m: float = 0.0
