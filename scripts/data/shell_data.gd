class_name ShellData
extends Resource
## One type of shell. Ballistics (and later penetration/damage) read these values.

@export var display_name: String = "Unnamed shell"
## Short label for the HUD, e.g. "AP" or "HE".
@export var short_name: String = "AP"
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

@export_group("Damage")
## Structure hp a penetration takes from the tank (TankData.structure_hp).
@export var damage_hp: float = 0.0
## Damage to every module the shell passes after penetrating, out to module_reach_m.
@export var module_damage: float = 0.0
## How far into the tank a penetrating shell damages modules (m).
@export var module_reach_m: float = 2.5
## Armour worn off the hit spot by a hit that doesn't penetrate (mm).
@export var wear_mm: float = 0.0
## Damage HE fragments do to external modules (tracks) they hit.
@export var fragment_module_damage: float = 0.0

@export_group("Explosive")
## Fragments always hit exposed targets within this distance of the burst (m).
@export var fragment_lethal_radius_m: float = 0.0
## Hit chance falls linearly to zero at this distance (m). 0 = not explosive.
@export var fragment_max_radius_m: float = 0.0

@export_group("Infantry")
## Fired by infantry (rifles, AT rounds). Infantry fire doesn't make squads throw smoke.
@export var infantry: bool = false
## Never knocks a tank out (AT rounds): no last structure points, no ammo blow-up.
@export var cannot_knock_out: bool = false

@export_group("Sound")
## Landing on a tank.
@export var sound_hit_armour: SoundSetData
## Landing on ground, buildings and trees.
@export var sound_hit_ground: SoundSetData
## Explosive shells: the detonation, played on every impact on top of the hit sound.
@export var sound_explosion: SoundSetData
## Bouncing off armour.
@export var sound_ricochet: SoundSetData


func is_explosive() -> bool:
	return fragment_max_radius_m > 0.0
