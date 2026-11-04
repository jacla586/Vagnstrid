class_name GunData
extends Resource
## One main gun for the tank builder (ChassisData.guns). Small guns: fast, flat,
## quick to reload; big guns: slow "sledgehammers" that hit hard.

@export var id: StringName = &"gun"
@export var display_name: String = "Gun"
@export var caliber_mm: float = 75.0
## Ammunition types, in selection-key order (AP first, then HE).
@export var ammo: Array[ShellData] = []
@export var reload_time_s: float = 6.0
@export var recoil_impulse_ns: float = 30000.0
@export var mass_kg: float = 1000.0
## Barrel length from the gun pivot (m) and its outer radius (m, looks only).
@export var gun_length_m: float = 3.6
@export var barrel_radius_m: float = 0.08
## A gun this big needs at least this turret radius (m).
@export var min_turret_radius_m: float = 1.0
@export var fire_sound: SoundSetData
## Looks: a muzzle brake, and a turret variant the gun needs (e.g. box_turret).
@export var muzzle_brake: bool = false
@export var turret_variant: StringName = &""
@export var cost: int = 50
