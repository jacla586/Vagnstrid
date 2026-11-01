class_name HitResult
extends RefCounted
## What one shell did to one armour zone. Made by Armour.resolve().

enum Outcome { HIT, PENETRATION, NO_PENETRATION, RICOCHET }

var outcome: Outcome = Outcome.HIT
## Zone hit, e.g. "hull" + "side".
var part: String = ""
var face: String = ""
## Plate thickness straight on (mm).
var armour_mm: float = 0.0
## Impact angle from the plate's normal (degrees).
var angle_deg: float = 0.0
## Thickness along the shell's path (mm).
var effective_mm: float = 0.0
## Shell's penetration at impact speed (mm).
var penetration_mm: float = 0.0
## Node that was hit (null for a plain hit report).
var target: Node = null


func is_penetration() -> bool:
	return outcome == Outcome.PENETRATION


## Short readable line for the HUD and logs.
func describe() -> String:
	if outcome == Outcome.HIT:
		return "HIT"
	var head: String = {
		Outcome.PENETRATION: "PENETRATION",
		Outcome.NO_PENETRATION: "NO PENETRATION",
		Outcome.RICOCHET: "RICOCHET",
	}[outcome]
	var zone: String = "%s %s %d mm @ %d°" % [part, face, roundi(armour_mm), roundi(angle_deg)]
	if outcome == Outcome.RICOCHET:
		return "%s – %s" % [head, zone]
	return "%s – %s = %d mm vs %d mm" % [head, zone, roundi(effective_mm), roundi(penetration_mm)]
