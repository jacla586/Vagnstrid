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
## Damage HE fragments do to external modules (tracks) they hit, and an HE burst on the
## hull to the exposed modules near it (ModuleData.blast_exposed).
@export var fragment_module_damage: float = 0.0
## A penetration does full damage (damage_hp, module_damage, module_reach_m) with this
## much penetration to spare, as a share of the calibre (0.5: 18 mm for 37 mm, 38 mm for
## 75 mm); with less it falls towards pen_damage_floor (just through: little left to
## do harm). Explosive rounds always do full damage inside (the burst does it).
@export var full_damage_surplus_calibres: float = 0.5
@export_range(0.0, 1.0) var pen_damage_floor: float = 0.35

@export_group("Explosive")
## Fragments always hit exposed targets within this distance of the burst (m).
@export var fragment_lethal_radius_m: float = 0.0
## Hit chance falls linearly to zero at this distance (m). 0 = not explosive.
@export var fragment_max_radius_m: float = 0.0

## Landing on a track breaks it (HE, AT rounds); other rounds only damage it.
@export var breaks_tracks: bool = false
## An explosive round bursts on the plate (never glances off). Not penetrating, the blast
## still takes this much structure hp...
@export var blast_hp: float = 0.0
## ...and damages exposed modules (engine, turret ring) within this of the burst by
## fragment_module_damage (m).
@export var blast_module_reach_m: float = 0.0
## Bursting within this of a tank (m; a direct hit counts as 0) it throws dirt over the
## crew's optics (Tank.add_optics_dirt): full at the plate, none at the edge.
@export var optics_dirt_radius_m: float = 0.0
## Bursting fells every tree (with a trunk) within this distance (m; TreeField.fell_near).
@export var tree_fell_radius_m: float = 0.0

@export_group("Trees")
## A gun round (>= 20 mm) that isn't explosive goes through a trunk (felling it if thin
## enough); a bullet only through trunks up to this thick (m; 0 = it stops in every trunk).
@export var tree_pass_max_diameter_m: float = 0.0
## Going through, it is turned this many degrees off its path in a random direction...
@export var tree_deflection_min_deg: float = 5.0
@export var tree_deflection_max_deg: float = 15.0
## ...and keeping this share of its speed. Explosive rounds burst on the trunk; bullets stop.
@export_range(0.0, 1.0) var tree_speed_keep: float = 0.85

@export_group("Infantry")
## Never knocks a tank out: no last structure points, no ammo blow-up.
@export var cannot_knock_out: bool = false
## Knocks out only by taking a tank's last structure points, and only one already
## down to finish_below_share of its structure hp before the hit (finishing off a
## nearly dead one, the squad AT round: possible but rare); never sets off the ammo.
@export var finishes_only: bool = false
@export_range(0.0, 1.0) var finish_below_share: float = 0.15
## A hit on the fuel tank sets it burning (off for the AT round: a fire would make its
## kills common).
@export var sets_fire: bool = true
## Named in the kill feed instead of the shooter's tank type ("Bazooka"; "" = the tank).
@export var kill_feed_name: String = ""
## Any hit restarts the crew's repair, penetrating or not (AT rounds). Otherwise only
## a penetrating gun round does.
@export var stops_repair_on_hit: bool = false

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


## Share of the full damage a penetration with `surplus_mm` to spare does
## (full_damage_surplus_calibres, pen_damage_floor); explosive rounds: always 1.
func penetration_damage_share(surplus_mm: float) -> float:
	if is_explosive():
		return 1.0
	var full: float = maxf(caliber_mm * full_damage_surplus_calibres, 0.001)
	return lerpf(pen_damage_floor, 1.0, clampf(surplus_mm / full, 0.0, 1.0))
