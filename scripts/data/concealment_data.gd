class_name ConcealmentData
extends Resource
## How cover and movement make a tank harder to spot. Used by everything that spots
## (bots now, the player's spotting later), so the rules are the same for all.
## Cover = sight blockers (bushes, tree crowns: layer "vision_blocker") around the target.

## Box around the target in which sight blockers count as cover (m, centred on the
## target horizontally, from just below it upwards).
@export var cover_box_size: Vector3 = Vector3(16.0, 30.0, 16.0)
## This many sight blockers in the box give full cover.
@export var full_cover_blockers: int = 6
## Full cover makes spotting take (1 + this) times longer.
@export var cover_spot_time_factor: float = 3.0
## Full cover cuts the range at which the target can be spotted to this share.
@export_range(0.0, 1.0) var cover_range_factor: float = 0.5
@export_group("Movement")
## At or below this speed the target counts as standing still (m/s).
@export var stationary_speed_mps: float = 1.0
## Standing still makes spotting take this many times longer.
@export var stationary_spot_time_factor: float = 1.5
## At or above this speed dust and movement give the target away (m/s).
@export var fast_speed_mps: float = 4.0
## Moving fast multiplies the spotting time by this.
@export var moving_fast_spot_time_factor: float = 0.7
