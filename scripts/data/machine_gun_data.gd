class_name MachineGunData
extends Resource
## One machine gun type (nests now, coaxial/hull MGs later).

@export var display_name: String = "Machine gun"
@export var bullet: ShellData
@export var rounds_per_minute: float = 600.0
## A burst lasts this long, then the gunner pauses (s).
@export var burst_time_s: float = 1.5
@export var burst_pause_s: float = 1.2
## Random spread of each bullet around the aim (mrad, radius).
@export var dispersion_mrad: float = 10.0
## Won't engage targets farther than this (m).
@export var max_range_m: float = 800.0
## How long a target must be seen before the gunner opens fire (s).
@export var reaction_time_s: float = 1.5
## How fast the gun swings onto a target (degrees/s).
@export var traverse_speed_deg: float = 60.0
