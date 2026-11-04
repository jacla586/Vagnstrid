class_name ArmourPackageData
extends Resource
## An armour package for the tank builder: thicker or thinner plates, more or less mass.

@export var id: StringName = &"standard"
@export var display_name: String = "Standard"
## Plate thickness multipliers.
@export var front_factor: float = 1.0
@export var side_factor: float = 1.0
@export var rear_factor: float = 1.0
@export var roof_factor: float = 1.0
## Mass change as a share of the chassis' base mass (heavier = slower).
@export var mass_fraction: float = 0.0
## The hull grows a little with thick armour (share of its size).
@export var size_factor: float = 1.0
@export var cost: int = 0
