class_name PropBreakData
extends Resource
## How street furniture falls when a tank drives into it (PropBreak): street lamps and
## catenary masts topple (their wires drop with them), playground equipment falls apart.
## Cosmetic and local on every machine; nothing is sent.

## Tanks are checked against the props this often (Hz).
@export var check_hz: float = 10.0
## A prop is hit when it is this close to the hull's footprint (m).
@export var tank_margin_m: float = 0.3
## Toppling: time to fall (angle grows as t²) and the angle it ends at (deg).
@export var fall_time_s: float = 1.3
@export var fallen_angle_deg: float = 86.0
## Fallen things lie this long (s), then sink into the ground over sink_s (by
## sink_depth_m) and are gone until the map is reset (ThunderRoad's next round).
@export var lie_s: float = 30.0
@export var sink_s: float = 3.0
@export var sink_depth_m: float = 1.5
## Catenary spans of a toppled mast drop to the track in this long (s).
@export var wire_drop_s: float = 0.9
## Standing props are drawn up to this far (m, 0 = always), in cells this big (m).
@export var draw_range_m: float = 1200.0
@export var cell_m: float = 250.0
## Small props (kinds starting with one of these: signs, reflector posts) are drawn only
## this far (m): a sign is a pixel or two beyond it, and the many sign kinds are many draws.
@export var small_kinds: PackedStringArray = PackedStringArray(["Skylt", "Hallplats", "Kantstolpe"])
@export var small_draw_range_m: float = 450.0
## Playground pieces up to this far (m) are drawn.
@export var playground_draw_range_m: float = 450.0

@export_group("Playground debris")
## A broken piece falls apart into at most this many parts...
@export var debris_max_parts: int = 14
## ...thrown along the tank's way (m/s), up (m/s) and spinning (rad/s).
@export var debris_push_min_mps: float = 1.0
@export var debris_push_max_mps: float = 3.5
@export var debris_up_min_mps: float = 1.0
@export var debris_up_max_mps: float = 3.0
@export var debris_spin_max: float = 5.0
