class_name ShellData
extends Resource
## One type of shell. Ballistics (and later penetration/damage) read these values.

@export var display_name: String = "Unnamed shell"
## Speed leaving the barrel (m/s). Deliberately slower than historical guns
## (~500 instead of ~800 for AP) so drop is readable on the reticle and range
## estimation matters. Fun over realism.
@export var muzzle_velocity_mps: float = 500.0
@export var mass_kg: float = 6.8
@export var caliber_mm: float = 75.0
## Aerodynamic drag coefficient. Higher = slows down faster, drops more at range.
@export var drag_coefficient: float = 0.3
## Colour of the glowing tracer.
@export var tracer_color: Color = Color(1.0, 0.55, 0.15, 1.0)
