class_name CrewVoiceData
extends Resource
## The own crew's shouts on the intercom (data/tanks/crew_voice_sv.tres), played to the
## player with the squad's radio (SquadRadio), no subtitle: a gun round
## hits the tank, or lands or passes close (Tank.struck / Tank.near_missed), or a crew
## member is wounded (Tank.module_changed for driver/gunner, Tank.commander_wounded),
## or a track runs over a mine (Tank.mine_hit, "Mina! Bandet utslaget!" instead of "Vi är träffade!"), and
## rarely when the optics get dirtied (he_dirt).

@export var hit: AudioStream
@export var near_miss: AudioStream
@export var driver_hit: AudioStream
@export var gunner_hit: AudioStream
@export var commander_hit: AudioStream
@export var mine: AudioStream
## "Vilken jädra smäll!" now and then when an HE burst dirties the optics
## (Tank.optics_dirtied): at he_dirt_chance.
@export var he_dirt: AudioStream
@export var he_dirt_chance: float = 0.02
## Rare stand-ins (humour): "Jävlar, jävlar, jävlar!" for `hit`, the Volvo 240 for `mine`.
@export var hit_rare: AudioStream
@export var hit_rare_chance: float = 0.08
@export var mine_rare: AudioStream
@export var mine_rare_chance: float = 0.25

@export_group("Kill banter")
## Now and then when the own tank knocks one out (ModeRadio, from the kill feed): `kill`
## ("Tjosan din jävel!") at kill_chance; the victim in the zone/checkpoint ("Allemansrätten
## gäller inte här!") `kill_zone` at kill_zone_chance; at most once per banter_cooldown_s.
@export var kill: Array[AudioStream] = []
@export var kill_chance: float = 0.12
@export var kill_zone: Array[AudioStream] = []
@export var kill_zone_chance: float = 0.35
@export var banter_cooldown_s: float = 60.0
@export_group("")

@export var volume_db: float = 2.0
## The same call isn't repeated within this long (s).
@export var repeat_cooldown_s: float = 4.0

@export_group("Crash")
## "Hörru, Rally-Kalle, lugna ner dig lite!" when the own tank hits something hard: its ground
## speed drops by crash_drop_kmh or more within crash_window_s from at least crash_min_kmh
## (SquadRadio watches the own tank's position, so clients hear it too); at most once per
## crash_cooldown_s.
@export var crash: Array[AudioStream] = []
@export var crash_min_kmh: float = 22.0
@export var crash_drop_kmh: float = 15.0
@export var crash_window_s: float = 0.35
@export var crash_cooldown_s: float = 45.0
