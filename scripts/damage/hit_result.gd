class_name HitResult
extends RefCounted
## What one shell did to one armour zone. Made by Armour.resolve().

enum Outcome { HIT, PENETRATION, NO_PENETRATION, RICOCHET, COMMANDER_HIT }

## Came from an MG or rifle bullet (under Tank.THREAT_MIN_CALIBER_MM): the shooter
## isn't told (no hit text for MG fire, so it can't sweep smoke to find targets).
var bullet: bool = false
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
## A penetration with little to spare (ShellData.penetration_damage_share below
## WEAK_SHARE): it got in but did less harm. Shown as "WEAK PENETRATION".
var weak: bool = false
const WEAK_SHARE: float = 0.7
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
		Outcome.PENETRATION: "WEAK PENETRATION" if weak else "PENETRATION",
		Outcome.NO_PENETRATION: "NO PENETRATION",
		Outcome.RICOCHET: "RICOCHET",
	}[outcome]
	if outcome == Outcome.PENETRATION:
		return head + (mods if mods != "" else " – %s %s" % [part, face])
	# Only where it struck: no thickness, angle or penetration figures for the shooter.
	return "%s – %s %s%s" % [head, part, face, mods]


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
