class_name SpottingData
extends Resource
## Rules for spot marks on the minimap.

## How long a spot mark stays on the minimap (s). It marks the last known
## position and doesn't follow the target.
@export var mark_lifetime_s: float = 25.0
## The mark fades out over this last part of its lifetime (s).
@export var mark_fade_s: float = 5.0
