class_name CrewVoiceData
extends Resource
## The own crew's shouts on the intercom (data/tanks/crew_voice_sv.tres), played to the
## player with the squad's radio (SquadRadio) and shown as a subtitle: a gun round
## hits the tank, or lands or passes close (Tank.struck / Tank.near_missed), or a crew
## member is wounded (Tank.module_changed for driver/gunner, Tank.commander_wounded).

@export var hit: AudioStream
@export var hit_text: String = "Vi är träffade!"
@export var near_miss: AudioStream
@export var near_miss_text: String = "Närträff!"
@export var driver_hit: AudioStream
@export var driver_hit_text: String = "Föraren träffad!"
@export var gunner_hit: AudioStream
@export var gunner_hit_text: String = "Skytten träffad!"
@export var commander_hit: AudioStream
@export var commander_hit_text: String = "Vagnchef träffad!"
@export var volume_db: float = 2.0
## The same call isn't repeated within this long (s).
@export var repeat_cooldown_s: float = 4.0
