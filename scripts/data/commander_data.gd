class_name CommanderData
extends Resource
## How a team's bot commander (TeamCommander) reads the fight and decides. One file per
## level, picked by MatchSettings.bot_commander (main menu "Bot commander"): Off, Normal
## (data/bots/commander_normal.tres), Sharp (commander_sharp.tres). Bots only: the
## commander never orders or shows anything to players.

@export var display_name: String = "Normal"
## How often it thinks the fight over (s).
@export var think_interval_s: float = 8.0
## Known enemy positions at most this old count (s; as the team's bots remember them).
@export var memory_s: float = 20.0
## Own losses this recent count in a lane (s).
@export var loss_window_s: float = 90.0
## Tanks this far along the road from the objective (m) are in the fight's picture.
@export var picture_reach_m: float = 700.0

@export_group("Main effort")
## A lane's score (lower = the main effort goes there): known enemies × enemy_weight +
## recent own losses × loss_weight − own tanks there × own_weight.
@export var enemy_weight: float = 1.0
@export var loss_weight: float = 1.5
@export var own_weight: float = 0.2
## A main effort holds at least this long (s), unless its lane lost switch_after_losses
## tanks within loss_window_s.
@export var main_hold_s: float = 45.0
@export var switch_after_losses: int = 2
## This share of the developing attackers goes to the main effort's lane (the rest spread
## over the width, binding the enemy); 0 = even spread as without a commander.
@export_range(0.0, 1.0) var main_share: float = 0.5

@export_group("Threats")
## An own tank knocked out by a known enemy at least this far away (m) marks a sniper.
@export var long_range_m: float = 450.0
## A known enemy this far behind the own team's middle along the road (m) is on its flank.
@export var flank_behind_m: float = 150.0
## Sniper hunt: this many bots (flankers, scouts and harassers first) go round to a spot
## hunt_range_m off a sniper's side, for at most hunt_s; 0 = none.
@export var hunters: int = 1
@export var hunt_range_m: float = 250.0
@export var hunt_s: float = 90.0
## Flank guard: this many bots nearest a flanker turn and hold against it, guard_s; 0 = none.
@export var guards: int = 1
@export var guard_s: float = 30.0

@export_group("Push")
## Gathered push (attackers): with at least gather_waiting tanks waiting for a wave due within
## gather_wave_s, the assault waits for it, and after such a wave lands it waits
## gather_after_wave_s more while they drive up (not when time is short). 0 = off.
@export var gather_waiting: int = 0
@export var gather_wave_s: float = 20.0
@export var gather_after_wave_s: float = 35.0
## The reserve joins an assault that starts with less than ASSAULT_MARGIN + this over the
## known defenders (-1 = never).
@export var commit_reserve_margin: int = 1
## Concentrated storm: this share of the assault (tanks not following a lead) goes into
## the zone on the main effort's side (centre: astride the road) instead of its own side.
@export_range(0.0, 1.0) var storm_main_share: float = 0.0

@export_group("Defence")
## The flank reserve counterattacks only while the defenders in the zone plus the flank
## reserves are at least this share of the attackers known in it (else it holds its post).
@export var counter_min_ratio: float = 0.8
## With this little time left on the checkpoint (s) and attackers in the zone, every
## defender drives into the zone to keep it from being taken (0 = off).
@export var deny_time_s: float = 45.0
## Threatened side: the lane with the most known attackers (at least threat_min_enemies,
## held main_hold_s) draws this share of the defenders' posts to its side of the road,
## posts renewed when it changes. 0 = off.
@export_range(0.0, 1.0) var threat_shift_share: float = 0.0
@export var threat_min_enemies: int = 2

@export_group("Debug")
## Prints one line per decision round (headless tests).
@export var log_decisions: bool = false
