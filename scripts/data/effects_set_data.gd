class_name EffectsSetData
extends Resource
## Which effect plays where (data/effects/effects.tres). Shell picks an impact by what it
## hit and how big it is; Tank picks the muzzle effects.

@export_group("Gun rounds (>= 20 mm)")
@export var impact_ground: EffectData
@export var impact_armour: EffectData
@export var impact_building: EffectData
@export var impact_wood: EffectData
## Added on top of the surface impact by explosive rounds.
@export var explosion: EffectData
@export_group("Bullets")
@export var bullet_ground: EffectData
@export var bullet_armour: EffectData
@export var bullet_building: EffectData
@export_group("Gun")
@export var muzzle_flash: EffectData
## Dust kicked up under the muzzle when it is within blast_dust_height_m of the ground.
@export var muzzle_blast_dust: EffectData
@export var blast_dust_height_m: float = 3.5
## The cloud a main-gun shot leaves at the muzzle (GunSmoke; +Y along the bore).
@export var gun_smoke: BurstData
@export_group("Tanks")
## Dust behind each track while driving (continuous; TankDust): none below
## dust_min_speed_mps, full from dust_full_speed_mps, times WeatherData.dust_factor.
@export var track_dust: BurstData
@export var dust_min_speed_mps: float = 1.5
@export var dust_full_speed_mps: float = 10.0
## Flames of a fire (burning tank, MG nest; continuous, on Burning).
@export var fire_flames: BurstData
## Its smoke column (continuous; Burning leans it with the weather's fire smoke drift).
@export var fire_smoke: BurstData
