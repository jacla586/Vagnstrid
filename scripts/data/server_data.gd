class_name ServerData
extends Resource
## The dedicated server (`DedicatedServer`, `--dedicated`; data/server/server.tres): the
## match it runs, the vote between matches and the log. These are the defaults: the
## server's `server.cfg` (ServerConfig, written on first start) overrides them per machine.

## Tanks per team (bots fill what players don't).
@export var team_size: int = 10
## Weather preset id for every match, or "random".
@export var weather: String = "random"
## Scenarios to vote between (res:// paths); empty = every scenario the main menu lists.
@export var scenarios: PackedStringArray = []
## After a match ends the result shows this long (s), then the vote runs vote_s.
@export var result_s: float = 15.0
@export var vote_s: float = 30.0
## A match running longer than this (s) ends and goes to the vote.
@export var max_match_s: float = 2700.0
