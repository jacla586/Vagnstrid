class_name DeployData
extends Resource
## The in-match deploy screen (DeployScreen): text for maps without a game mode, the
## camera that circles over the map before the player has a tank, and how the tank
## picker words a tank's strengths and weaknesses (TankSummary).

@export_group("No game mode")
@export var free_fight_name: String = "Free fight"
@export_multiline var free_fight_briefing: String = "Knock out the enemy tanks.\nKnocked-out tanks come back at the start after a while."

@export_group("Camera before deploy")
## Height above the ground under it, distance from the point it circles (m)...
@export var orbit_height_m: float = 140.0
@export var orbit_radius_m: float = 220.0
## ...and how fast it goes round (deg/s).
@export var orbit_deg_s: float = 3.0

@export_group("Tank summary")
## A value this share better than the middle (median) preset's reads as a strength,
## as much worse as a weakness.
@export_range(0.0, 1.0) var margin_share: float = 0.12
## HE doing at least this much damage gets "strong HE" on the gun line (hp).
@export var strong_he_hp: float = 30.0
