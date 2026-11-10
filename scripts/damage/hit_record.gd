class_name HitRecord
extends RefCounted
## One gun round (>= Tank.THREAT_MIN_CALIBER_MM) that struck a tank, kept for the
## owner's killcam and hit picture (Tank.get_hits_this_life). Positions and directions
## are in the hull's frame so the picture can be drawn on the wreck's outline.

var time_s: float = 0.0
var outcome: int = HitResult.Outcome.HIT
var part: String = ""
var face: String = ""
## Impact point and flight direction in the hull's frame (forward -Z).
var local_point: Vector3 = Vector3.ZERO
var local_dir: Vector3 = Vector3.FORWARD
var armour_mm: float = 0.0
var effective_mm: float = 0.0
var penetration_mm: float = 0.0
var angle_deg: float = 0.0
var modules: PackedStringArray = PackedStringArray()
var shell_name: String = ""
var calibre_mm: float = 0.0
## Where the round was fired from and where it struck (world).
var origin: Vector3 = Vector3.ZERO
var impact: Vector3 = Vector3.ZERO
var shooter_label: String = ""
## Host only (not sent): the shooting Tank's instance id, 0 = unknown.
var shooter_id: int = 0
## Host only: what it came from for the kill feed ("Bazooka"; "" = the tank's gun).
var weapon: String = ""
var distance_m: float = 0.0
## This hit knocked the tank out (penetration damage or the ammo).
var killed: bool = false
## This hit set the fuel burning (a later fire knock-out goes on its account).
var set_fire: bool = false


func is_penetration() -> bool:
	return outcome == HitResult.Outcome.PENETRATION


## The round did damage (an assist when the tank goes): not a bounce or a stopped round.
func dealt_damage() -> bool:
	return outcome == HitResult.Outcome.PENETRATION \
			or outcome == HitResult.Outcome.HIT and not modules.is_empty()


func to_array() -> Array:
	return [time_s, outcome, part, face, local_point, local_dir, armour_mm, effective_mm,
			penetration_mm, angle_deg, modules, shell_name, calibre_mm, origin, impact,
			shooter_label, distance_m, killed, set_fire]


static func from_array(a: Array) -> HitRecord:
	var r := HitRecord.new()
	if a.size() < 19:
		return r
	r.time_s = a[0]; r.outcome = a[1]; r.part = a[2]; r.face = a[3]
	r.local_point = a[4]; r.local_dir = a[5]; r.armour_mm = a[6]; r.effective_mm = a[7]
	r.penetration_mm = a[8]; r.angle_deg = a[9]; r.modules = a[10]; r.shell_name = a[11]
	r.calibre_mm = a[12]; r.origin = a[13]; r.impact = a[14]; r.shooter_label = a[15]
	r.distance_m = a[16]; r.killed = a[17]; r.set_fire = a[18]
	return r


## The hit a knock-out goes on: the killing one, else the one that lit the fire, else
## the last penetration (null: nothing to show, e.g. abandoned).
static func kill_of(records: Array[HitRecord]) -> HitRecord:
	for r: HitRecord in records:
		if r.killed:
			return r
	for i: int in range(records.size() - 1, -1, -1):
		if records[i].set_fire:
			return records[i]
	for i: int in range(records.size() - 1, -1, -1):
		if records[i].is_penetration():
			return records[i]
	return null
