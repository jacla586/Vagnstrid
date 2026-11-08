class_name ThunderRoadData
extends Resource
## Rules of ThunderRoad (a gauntlet): attackers clear a road checkpoint by checkpoint,
## defenders hold a corridor along it and fall back. Two rounds, sides swap.

@export_group("Corridors")
## Defenders keep within this of the road (m, each side) and ahead of the front...
@export var defender_half_width_m: float = 250.0
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
@export var start_time_s: float = 240.0
@export var time_per_capture_s: float = 120.0
## Attackers' shared lives: per tank in the team at the start, and per checkpoint taken.
@export var start_lives_per_tank: int = 2
@export var lives_per_capture: int = 2
## Knocked-out attackers come back together: at every capture or this often (s), each
## costing a life, this far behind the front (m).
@export var wave_interval_s: float = 60.0
@export var attacker_spawn_back_m: float = 250.0
## Defenders come back after this long (s) at the checkpoint this many past the next one
## (not at the far end), a little further on.
@export var defender_respawn_s: float = 15.0
@export var defender_spawn_checkpoints: int = 2
@export var defender_spawn_beyond_m: float = 60.0
## At the round's start defenders begin this many checkpoints past the first (closer
## than a respawn, so they reach their posts before the attackers' drive is over).
@export var defender_start_checkpoints: int = 1

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
## A defending bot's squad lays its mine on the road this far towards the attackers (m).
@export var defender_mine_min_m: float = 80.0
@export var defender_mine_max_m: float = 150.0
