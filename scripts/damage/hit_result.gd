class_name HitResult
extends RefCounted
## What one shell did to one armour zone. Made by Armour.resolve().

enum Outcome { HIT, PENETRATION, NO_PENETRATION, RICOCHET, COMMANDER_HIT }

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
## Plate thickness before wear (mm); equal to armour_mm on an unworn plate.
var unworn_mm: float = 0.0
## Modules the shell damaged ("engine", "track_left", ...), worst effect first.
var modules: PackedStringArray = PackedStringArray()
## True if this hit knocked the tank out.
var knocked_out: bool = false
## Optional text that replaces the default description (e.g. "MG NEST DESTROYED").
var note: String = ""
## Node that was hit (null for a plain hit report).
var target: Node = null


func is_penetration() -> bool:
	return outcome == Outcome.PENETRATION


## Short readable line for the HUD and logs.
func describe() -> String:
	if note != "":
		return note
	var mods: String = ""
	for m: String in modules:
		mods += " – " + module_label(m)
	if knocked_out:
		mods += " – KNOCKED OUT"
	if outcome == Outcome.HIT:
		return "HIT" + mods
	if outcome == Outcome.COMMANDER_HIT:
		return "COMMANDER HIT"
	var head: String = {
		Outcome.PENETRATION: "PENETRATION",
		Outcome.NO_PENETRATION: "NO PENETRATION",
		Outcome.RICOCHET: "RICOCHET",
	}[outcome]
	if outcome == Outcome.PENETRATION:
		return head + (mods if mods != "" else " – %s %s" % [part, face])
	var plate: String = "%d mm" % roundi(armour_mm)
	if unworn_mm > armour_mm + 0.5:
		plate = "%d mm (worn from %d)" % [roundi(armour_mm), roundi(unworn_mm)]
	var zone: String = "%s %s %s @ %d°" % [part, face, plate, roundi(angle_deg)]
	if outcome == Outcome.RICOCHET:
		return "%s – %s%s" % [head, zone, mods]
	return "%s – %s = %d mm vs %d mm%s" % [head, zone, roundi(effective_mm), roundi(penetration_mm), mods]


## HUD name of a module id.
static func module_label(id: String) -> String:
	match id:
		"engine": return "ENGINE"
		"track_left": return "LEFT TRACK"
		"track_right": return "RIGHT TRACK"
		"turret_ring": return "TURRET RING"
		"fuel": return "FUEL TANK"
		"ammo": return "AMMO"
	return id.to_upper()
