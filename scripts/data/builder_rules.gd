class_name BuilderRules
extends Resource
## How the tank builder turns parts into performance (data/builder/builder_rules.tres).
## The reference values are today's medium tank, so it comes out as before.

@export_group("Mobility")
## Power-to-weight that gives the reference top speed (kW per tonne)...
@export var reference_kw_per_ton: float = 13.5
@export var reference_top_speed_kmh: float = 40.0
## ...top speed follows power-to-weight to this power, within these limits.
@export var speed_exponent: float = 0.6
@export var min_top_speed_kmh: float = 20.0
@export var max_top_speed_kmh: float = 65.0
## Reverse speed as a share of the top speed.
@export var reverse_share: float = 0.2
@export var reference_acceleration: float = 1.5
@export var min_acceleration: float = 0.6
@export var max_acceleration: float = 3.0
## Turn rate at the reference mass (degrees/s); heavier turns slower (exponent).
@export var reference_mass_kg: float = 29500.0
@export var reference_turn_rate_deg: float = 30.0
@export var turn_mass_exponent: float = 0.4
## Pitch rocking (TankData.pitch_rock_lever_m) grows with mass: the chassis' value at
## the reference mass times (mass / reference) ^ this.
@export var rock_mass_exponent: float = 1.0

@export_group("Turret")
## Traverse at the reference gun mass (degrees/s); heavier guns traverse slower.
@export var reference_traverse_deg: float = 20.0
@export var reference_gun_mass_kg: float = 1000.0
@export var traverse_exponent: float = 0.5
@export var min_traverse_deg: float = 8.0
@export var max_traverse_deg: float = 40.0

@export_group("Toughness and stealth")
## Structure hit points per tonne.
@export var hp_per_ton: float = 3.4
@export var min_structure_hp: float = 50.0
## Camouflage makes the tank this many times slower to spot.
@export var camo_spot_factor: float = 1.25
@export var camo_cost: int = 15
