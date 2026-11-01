class_name TankCommand
extends RefCounted
## What a controller (player, bot, later network) wants the tank to do this frame.
## The tank only acts on commands; it never reads input itself.

## -1 = full reverse, 0 = stop, 1 = full forward.
var throttle: float = 0.0
## -1 = full left, 0 = straight, 1 = full right.
var steering: float = 0.0
