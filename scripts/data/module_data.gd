class_name ModuleData
extends Resource
## One internal or external part of a tank that can be damaged: engine, tracks,
## turret ring, fuel tank, ammo. A box in the hull's or the turret's local space.
## See TankDamage for what each id does when damaged or destroyed.

## engine, track_left, track_right, turret_ring, fuel, ammo, or a crew member: driver,
## gunner (see crew).
@export var id: StringName = &"engine"
## Space the box is in: "hull" (tank body) or "turret" (turns with the turret).
@export var frame: StringName = &"hull"
## Box centre and size in that space (m). The tank's forward is -Z.
@export var center: Vector3 = Vector3.ZERO
@export var size: Vector3 = Vector3.ONE
@export var hp: float = 60.0
## The module counts as damaged below this share of its hp (destroyed at 0).
@export_range(0.0, 1.0) var damaged_below: float = 0.75
## Outside the armour (tracks): hit by shells that don't penetrate and by HE fragments.
@export var external: bool = false
## Own repair time when broken (s, standing still), rolled between min and max each time
## it breaks (tracks: putting a thrown track back on). 0 = the tank's repair_time_s.
@export var repair_time_min_s: float = 0.0
@export var repair_time_max_s: float = 0.0
## A crew member, not a part: a hit only wounds him (never destroyed, never a knock-out),
## standing still doesn't help, he gets over it heal_time_s after the last wound (s).
@export var crew: bool = false
@export var heal_time_s: float = 60.0
