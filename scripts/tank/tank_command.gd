class_name TankCommand
extends RefCounted
## What a controller (player, bot, later network) wants the tank to do this frame.
## The tank only acts on commands; it never reads input itself.

## -1 = full reverse, 0 = stop, 1 = full forward.
var throttle: float = 0.0
## -1 = full left, 0 = straight, 1 = full right.
var steering: float = 0.0
## World-space point the turret and gun should aim at.
var aim_point: Vector3 = Vector3.ZERO
## False = no aim this frame; turret and gun hold their position.
var has_aim: bool = false
## Desired hatch state. The tank opens/closes over its hatch transition time.
var hatch_open: bool = false
## Ammo type index (TankData.ammo) to switch to this frame, or -1 for no change.
var ammo_select: int = -1
## True = wants to fire this frame. The tank fires only when loaded.
var fire: bool = false
## True = wants to fire a machine gun this frame (held for bursts).
var fire_mg: bool = false
## True = the roof MG (needs the hatch fully open), false = the coaxial MG.
var mg_use_roof: bool = false
## World-space point the roof MG should aim at.
var mg_aim_point: Vector3 = Vector3.ZERO
## True = the commander marks spot_point this frame (ignored while on cooldown).
var spot: bool = false
## World-space point the commander wants to mark as spotted.
var spot_point: Vector3 = Vector3.ZERO
## Order for the tank's infantry squad this frame: 0 none, 1 move to squad_target,
## 2 recall (Squad.ORDER_*).
var squad_order: int = 0
var squad_target: Vector3 = Vector3.ZERO
