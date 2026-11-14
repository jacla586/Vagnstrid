class_name FreeFightData
extends Resource
## Rules of free fight (FreeFight): the players against ever larger waves of bots.
## Round r brings start_count + r / 2 bots, easy on even rounds, hard on odd ones
## (2 easy, 2 hard, 3 easy, 3 hard ...), each round's crews a little better.

@export_group("Briefing")
@export var display_name: String = "Free fight"
@export_multiline var briefing: String = ""

@export_group("Radio")
## Command radio and crew banter (ModeRadio); none = silent.
@export var calls: ModeCallsData

@export_group("Spawns")
## Players start at a random spot in a circle round the map's centre, this far inside
## the map's edge (MapEdge) at its narrowest (m).
@export var spawn_edge_margin_m: float = 400.0
## A wave's centre lies this far from the living players' centre (m).
@export var wave_distance_min_m: float = 250.0
@export var wave_distance_max_m: float = 350.0
## A wave's centre keeps this far inside the map's edge (m).
@export var wave_edge_inset_m: float = 100.0
## The bots stand within this of the wave's centre; the players' maps show the circle
## until the wave attacks (m).
@export var wave_radius_m: float = 50.0
## Directions tried for a wave's centre; one no player can see is preferred.
@export var wave_tries: int = 16
## Bots spawn at least this far apart (m).
@export var bot_spacing_m: float = 14.0

@export_group("Waves")
@export var start_count: int = 2
## Each player beyond the first adds this share of a wave's bots (rounded up).
@export var extra_player_share: float = 0.6
## Bots of round 0, 2, 4 ... (easy) and 1, 3, 5 ... (hard).
@export var easy_bot: BotData
@export var hard_bot: BotData
@export var easy_configs: Array[TankConfig] = []
@export var hard_configs: Array[TankConfig] = []
## Each round the crews' spot times and gun errors are multiplied by this (better
## crews), but never below creep_floor of the round-0 values.
@export var creep_per_round: float = 0.94
@export var creep_floor: float = 0.55
## The team the bots are on (the players are team 0).
@export var bot_team: int = 1
## After a wave is beaten: this long until the next one (s); knocked-out players come
## back at its start.
@export var wave_gap_s: float = 8.0
## Knocked-out bots' tanks are taken away this long after the wave is beaten (their
## wrecks stay) (s).
@export var clear_delay_s: float = 1.0

@export_group("Attack")
## The attacking bots think this often (s).
@export var attack_think_s: float = 3.0
## They drive to firing spots this far from the nearest known player, closer each time
## they arrive, down to attack_min_m (m).
@export var attack_range_m: float = 200.0
@export var attack_min_m: float = 80.0
@export var attack_step_m: float = 40.0
## Firing spots are searched within this of the ideal one (m).
@export var attack_spot_radius_m: float = 60.0
## A known player's position this old still counts (s).
@export var attack_memory_s: float = 60.0

@export_group("Allies")
## Bot tanks on the players' side (main menu "Bot allies", MatchSettings.free_allies):
## their crew and tanks (empty = hard_configs).
@export var ally_bot: BotData
@export var ally_configs: Array[TankConfig] = []
## Each ally makes the waves grow by this share of what a player adds.
@export var ally_wave_weight: float = 0.75
## Allies think this often (s)...
@export var ally_think_s: float = 2.0
## ...go after a known enemy within this (m; firing spots as the waves' attackers)...
@export var ally_engage_m: float = 450.0
## ...else keep beside the nearest living player: this far apart across his heading and
## this far behind (m), moving again when the place drifts more than ally_slack_m.
@export var ally_spacing_m: float = 35.0
@export var ally_behind_m: float = 20.0
@export var ally_slack_m: float = 30.0
