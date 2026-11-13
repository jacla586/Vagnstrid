class_name RadioData
extends Resource
## The squad's radio calls to its own tank (data/squads/radio_sv.tres): the recordings
## (no subtitles: the game's text is English, the Swedish voices are a bonus). Contacts give a clock direction from the tank's hull
## (12 = straight ahead): `armour[h - 1]`, `infantry[h - 1]`.

@export var under_attack: AudioStream
## The squad gets off the tank.
@export var dismount: AudioStream
## Close protection (F): the squad escorts the tank.
@export var escort: AudioStream
@export var returning: AudioStream
@export var in_position: AudioStream
## An AT round is about to be fired (comes before the queue).
@export var at_fire: AudioStream
## How the AT round landed (right after at_fire, never skipped).
@export var at_hit: AudioStream
@export var at_miss: AudioStream
## Mines: the squad sets off to lay one, it is laid, an enemy tank drove over it.
@export var mine_laying: AudioStream
@export var mine_armed: AudioStream
@export var mine_triggered: AudioStream
## Twelve recordings each, one per clock hour (1..12).
@export var armour: Array[AudioStream] = []
@export var infantry: Array[AudioStream] = []
@export var volume_db: float = 0.0
## The same kind of call isn't repeated within this long (s); contacts count per clock hour.
@export var repeat_cooldown_s: float = 10.0
## Calls waiting while one plays; older ones are dropped beyond this.
@export var max_queue: int = 2
