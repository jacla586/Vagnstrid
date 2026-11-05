class_name CrewVoiceData
extends Resource
## The own crew's shouts on the intercom (data/tanks/crew_voice_sv.tres), played to the
## player with the squad's radio (SquadRadio) and shown as a subtitle: a gun round
## hits the tank, or lands or passes close (Tank.struck / Tank.near_missed).

@export var hit: AudioStream
@export var hit_text: String = "Vi är träffade!"
@export var near_miss: AudioStream
@export var near_miss_text: String = "Närträff!"
@export var volume_db: float = 2.0
## The same call isn't repeated within this long (s).
@export var repeat_cooldown_s: float = 4.0
