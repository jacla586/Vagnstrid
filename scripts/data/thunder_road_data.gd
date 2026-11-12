class_name ThunderRoadData
extends Resource
## Rules of ThunderRoad (a gauntlet): attackers clear a road checkpoint by checkpoint,
## defenders hold a corridor along it and fall back. Two rounds, sides swap.

@export_group("Briefing")
## Shown when a player joins (DeployScreen): the mode's name and its rules in a few
## short lines ({score} = score_to_win where the mode has one).
@export var display_name: String = "ThunderRoad"
@export_multiline var briefing: String = ""

@export_group("Corridors")
## Defenders keep within this of the road (m, each side) and ahead of the front less
## defender_behind_front_m...
@export var defender_half_width_m: float = 250.0
## ...which lets defenders posted forward (or in the zone) fight on a while when a
## checkpoint falls instead of finding themselves outside at once (m).
@export var defender_behind_front_m: float = 150.0
## ...attackers within this (m, each side), anywhere along it.
@export var attacker_half_width_m: float = 300.0
## Outside its corridor a tank can't fire, shows on the other team's maps this often (s)...
@export var outside_mark_s: float = 4.0
## ...and after this long (s) its commander is wounded (hatch shut), again each time the
## wound heals while still outside.
@export var outside_grace_s: float = 20.0
## The defenders' corridor starts this far ahead of the attackers' start before the
## first checkpoint falls (m).
@export var start_front_m: float = 150.0

@export_group("Checkpoints")
## The next checkpoint's zone is a rectangle round it, long across the road (towards
## the corridor edges, room for defenders to hide) and short along it: half sizes (m).
## Attacker tanks inside take it when they outnumber the defender tanks there...
@export var capture_half_width_m: float = 160.0
@export var capture_half_length_m: float = 60.0
## ...in this long with an edge of one tank (s), faster with a bigger edge (up to
## capture_speed_max times); as many defenders or more: contested, no progress...
@export var capture_time_s: float = 20.0
@export var capture_speed_max: float = 2.0
## ...and left without attackers the progress falls back this many times slower.
@export var capture_decay_factor: float = 0.5

@export_group("Time and lives")
## The attackers' time bank (s), topped up per checkpoint taken.
@export var start_time_s: float = 390.0
@export var time_per_capture_s: float = 120.0
## Time up with attackers in the zone: overtime, the round runs on while one is alive
## there and ends this long after the last one left or fell (s).
@export var overtime_grace_s: float = 3.0
## Attackers' shared lives: per tank in the team at the start, and per checkpoint taken.
@export var start_lives_per_tank: int = 2
## ...plus this many for the whole team at the start.
@export var start_lives_extra: int = 5
@export var lives_per_capture: int = 2
## Knocked-out attackers come back together: at every capture or this often (s), each
## costing a life, this far behind the front (m).
@export var wave_interval_s: float = 40.0
@export var attacker_spawn_back_m: float = 250.0
## Defenders come back after this long (s) at the checkpoint this many past the next one
## (not at the far end), a little further on.
@export var defender_respawn_s: float = 15.0
@export var defender_spawn_checkpoints: int = 2
@export var defender_spawn_beyond_m: float = 60.0
## ...but never closer than this (m along the road) past the next checkpoint, so they
## drive a bit before they are in the fight. Past the road's end (the last checkpoint is
## at it) the spawn lies on along the road's last direction.
@export var defender_spawn_min_ahead_m: float = 320.0
## At the round's start defenders begin in the first checkpoint's zone (ready to dig
## in: posts, mines) rather than at a respawn spawn.
@export var defender_start_in_zone: bool = true

@export_group("Rounds")
## Pause between the rounds and after the match (s), showing the result.
@export var round_break_s: float = 10.0

@export_group("Bots")
## Bot tanks for the teams (TankBuilder configs), picked at random; empty = the placed
## bot's tank.
@export var bot_configs: Array[TankConfig] = []
## Defenders move to a new post this often (s, random in range) if the front holds.
@export var defender_repost_min_s: float = 60.0
@export var defender_repost_max_s: float = 120.0
## Where defenders post: this share between the attackers and the next checkpoint's zone
## (a defence starts in front of the objective), this share in the zone, the rest just
## behind it (overwatch).
@export var defender_post_ahead_share: float = 0.5
@export var defender_post_zone_share: float = 0.3
