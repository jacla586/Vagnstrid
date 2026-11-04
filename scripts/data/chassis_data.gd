class_name ChassisData
extends Resource
## One chassis (class) for the tank builder: size, engine, base mass and armour, and
## the guns and armour packages that fit it. TankBuilder turns a TankConfig into
## TankData from this.

enum Kind { LIGHT, MEDIUM, HEAVY, TANK_DESTROYER }

@export var id: StringName = &"medium"
@export var display_name: String = "Medium"
@export var kind: Kind = Kind.MEDIUM
## TankModel style: light, sloped, boxy or heavy.
@export var model_style: StringName = &"sloped"
## Everything not set by the builder (optics, suspension, MGs, squad, sounds...).
@export var base: TankData

@export_group("Geometry")
## Hull with tracks: width, height, length (m).
@export var hull_size: Vector3 = Vector3(3.2, 1.4, 6.5)
@export var turret_radius_m: float = 1.2
@export var turret_height_m: float = 0.8

@export_group("Power and armour")
@export var engine_kw: float = 400.0
## Mass without gun and armour package (kg).
@export var base_mass_kg: float = 28500.0
@export var armour: ArmourData

@export_group("Options")
@export var guns: Array[GunData] = []
@export var armour_packages: Array[ArmourPackageData] = []
@export var cost: int = 160
