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
## Armour penetration at muzzle velocity, straight on (mm). Falls off with speed.
@export var penetration_mm: float = 110.0
## Aerodynamic drag coefficient. Higher = slows down faster, drops more at range.
@export var drag_coefficient: float = 0.3
## Size of the impact effect (1 = full-calibre puff, small for bullets).
@export var impact_scale: float = 1.0
## Size of the tracer (1 = main-gun tracer, small for bullets).
@export var tracer_scale: float = 1.0
## Colour of the glowing tracer.
@export var tracer_color: Color = Color(1.0, 0.55, 0.15, 1.0)
