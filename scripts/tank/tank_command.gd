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
