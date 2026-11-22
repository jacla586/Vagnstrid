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

@export_group("Debug")
## Prints one line per decision round (headless tests).
@export var log_decisions: bool = false
