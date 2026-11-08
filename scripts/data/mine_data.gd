class_name MineData
extends Resource
## An anti-tank mine laid by an infantry squad (SquadData.mine). It throws the track of
## an enemy tank that drives over it (never a knock-out, never a kill), and is gone.

## Goes off when an enemy tank's track comes over it: the track's box (ModuleData)
## grown by this much (m)...
@export var trigger_margin_m: float = 0.3
## ...but only this long after it was laid (s): the layer gets clear.
@export var arm_time_s: float = 3.0
## The blast lifts the tank: an upward kick of this speed (m/s) on its mass, at the mine.
@export var jolt_speed_mps: float = 0.6

@export_group("Destroyed by gunfire")
## Any gun round (>= 20 mm, not of the mine's team) landing this close destroys it (m)...
@export var destroy_by_gun_m: float = 2.0
## ...or an explosive (HE) one this close (m).
@export var destroy_by_he_m: float = 6.0

@export_group("Found by soldiers")
## Enemy soldiers make it out within this (m), in sight from the leader's eyes...
@export var spot_range_m: float = 25.0
## ...after looking at it this long (s); then it is a red cross on their team's maps.
@export var spot_time_s: float = 3.0

@export_group("Look and sound")
## A small, dark disc, half sunk into the ground: visible but discreet.
@export var disc_radius_m: float = 0.17
@export var disc_height_m: float = 0.09
@export var sink_m: float = 0.05
@export var color: Color = Color(0.2, 0.22, 0.16)
## The blast: impact effect scale and sound.
@export var effect_scale: float = 3.0
@export var sound_explosion: SoundSetData
