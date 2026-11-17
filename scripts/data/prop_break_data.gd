class_name PropBreakData
extends Resource
## How street furniture falls when a tank drives into it (PropBreak): street lamps and
## catenary masts topple (their wires drop with them), traffic lights topple and go dark,
## playground equipment falls apart.
## Cosmetic and local on every machine; nothing is sent.

## Tanks are checked against the props this often (Hz).
@export var check_hz: float = 10.0
## A prop is hit when its foot is this close to the hull's footprint (m)...
@export var tank_margin_m: float = 0.3
## ...plus this much for wide kinds (kind name prefix -> m), e.g. bus shelters (3.3 m long).
@export var kind_reach_m: Dictionary = {"Vaderskydd": 1.3}
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
## Small props (kinds starting with one of these: signs, reflector posts, street furniture) are drawn only
## this far (m): a sign is a pixel or two beyond it, and the many sign kinds are many draws.
@export var small_kinds: PackedStringArray = PackedStringArray(["Skylt", "Hallplats", "Kantstolpe",
		"Ortnamn", "Racke", "Papperskorg", "Bank", "Elskap", "Cykelstall", "Brandpost", "Brevlada", "Gravsten"])
@export var small_draw_range_m: float = 450.0
## Playground pieces up to this far (m) are drawn.
@export var playground_draw_range_m: float = 450.0

@export_group("Traffic lights")
## Kinds starting with this are traffic lights: their node key is `<n>_<phase>_<axis>`
## (geodata vagkant.py: the junction's offset in thousandths of the cycle, and which of its
## two directions), and their lens surfaces (materials starting with `signal_material_prefix`)
## get `signal_shader`, which switches them. A toppled light is dark (the plain materials).
## Sign backs: materials ending in this get sign_back_shader (plain metal, the face's
## outline), not the darkened face texture they come with.
@export var sign_back_suffix: String = "_bak"
@export var sign_back_shader: Shader = preload("res://assets/shaders/sign_back.gdshader")
@export var signal_kind_prefix: String = "Trafikljus"
@export var signal_material_prefix: String = "Signal_"
@export var signal_shader: Shader = preload("res://assets/shaders/signal_light.gdshader")
## The cycle per direction (s): red+yellow, green, yellow, then red; all red between the two
## directions. Pedestrians walk for walk_s at the start of their road's red.
@export var signal_green_s: float = 14.0
@export var signal_yellow_s: float = 3.0
@export var signal_red_yellow_s: float = 1.5
@export var signal_all_red_s: float = 2.0
@export var signal_walk_s: float = 8.0
## Lit lens brightness (emission energy) and the unlit lens' share of its colour.
@export var signal_energy: float = 4.0
@export var signal_off_share: float = 0.08
## Lens colours by the material's name after the prefix (rod, gul, gron, gang_rod, gang_gron).
@export var signal_colours: Dictionary = {"rod": Color(1.0, 0.08, 0.04), "gul": Color(1.0, 0.62, 0.05),
		"gron": Color(0.1, 1.0, 0.55), "gang_rod": Color(1.0, 0.08, 0.04), "gang_gron": Color(0.85, 1.0, 0.9)}

@export_group("Playground debris")
## A broken piece falls apart into at most this many parts...
@export var debris_max_parts: int = 14
## ...thrown along the tank's way (m/s), up (m/s) and spinning (rad/s).
@export var debris_push_min_mps: float = 1.0
@export var debris_push_max_mps: float = 3.5
@export var debris_up_min_mps: float = 1.0
@export var debris_up_max_mps: float = 3.0
@export var debris_spin_max: float = 5.0
