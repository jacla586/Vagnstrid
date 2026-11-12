class_name ChassisData
extends Resource
## One chassis (class) for the tank builder: size, engine, base mass and armour, and
## the guns and armour packages that fit it. TankBuilder turns a TankConfig into
## TankData from this.

enum Kind { LIGHT, MEDIUM, HEAVY, TANK_DESTROYER }

@export var id: StringName = &"medium"
@export var display_name: String = "Medium"
@export var kind: Kind = Kind.MEDIUM
## TankModel style: light, sloped, boxy, heavy or tall.
@export var model_style: StringName = &"sloped"
## Everything not set by the builder (optics, suspension, MGs, squad, sounds...).
@export var base: TankData

@export_group("Geometry")
## Hull with tracks: width, height, length (m).
@export var hull_size: Vector3 = Vector3(3.2, 1.4, 6.5)
@export var turret_radius_m: float = 1.2
@export var turret_height_m: float = 0.8
## Max gun depression below the turret's horizontal plane (degrees, positive number).
@export var gun_max_depression_deg: float = 8.0

@export_group("Power and armour")
@export var engine_kw: float = 400.0
## Mass without gun and armour package (kg).
@export var base_mass_kg: float = 28500.0
@export var armour: ArmourData

@export_group("Character")
## What sets this chassis apart beyond size and armour (each preset's clear strength and
## weakness). Turret traverse times this (a powered traverse > 1).
@export var traverse_factor: float = 1.0
## Gunner's sight zoom levels (vertical FOV, deg); empty = the base's.
@export var gunner_sight_fov_deg: PackedFloat32Array = PackedFloat32Array()
## Gun stabiliser 0..1 (TankData.gun_stabiliser): fires well on the move.
@export_range(0.0, 1.0) var gun_stabiliser: float = 0.0
## The fastest hull pitch it takes out (deg/s, TankData.gun_stabiliser_max_rate_deg).
@export var gun_stabiliser_max_rate_deg: float = 0.0
## Steepest climb (deg; 0 = the base's) and speed lost at ford depth (share; < 0 = the
## base's): wide tracks and a strong engine take rough ground better.
@export var max_climb_deg: float = 0.0
@export var ford_slow_share: float = -1.0
## Smoke salvos per life (-1 = the base's).
@export var smoke_salvos: int = -1
## Silhouette: spot time times this (tall < 1: seen sooner), times camouflage.
@export var signature_spot_factor: float = 1.0

## How bots use it (BotRoleData; none = a brawler).
@export var bot_role: BotRoleData

@export_group("Options")
@export var guns: Array[GunData] = []
@export var armour_packages: Array[ArmourPackageData] = []
@export var cost: int = 160
