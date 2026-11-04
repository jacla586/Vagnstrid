class_name TankSoundData
extends Resource
## Sounds of one tank type. Played by TankAudio.

@export_group("Engine")
@export var engine_idle: SoundSetData
@export var engine_drive: SoundSetData
## Engine pitch at standstill and at top speed / full throttle.
@export var engine_pitch_min: float = 0.85
@export var engine_pitch_max: float = 1.35
## Drive loop volume at standstill (dB); it rises to the set's volume_db at full revs.
@export var engine_drive_min_db: float = -30.0
## Idle loop fades out by this much at full revs (dB).
@export var engine_idle_fade_db: float = -12.0
## How fast revs follow speed and throttle (1/s).
@export var engine_response: float = 3.0

@export_group("Tracks")
@export var tracks: SoundSetData
## Track loop pitch at a crawl and at top speed.
@export var tracks_pitch_min: float = 0.7
@export var tracks_pitch_max: float = 1.2
## Silent below this speed (km/h).
@export var tracks_min_speed_kmh: float = 0.5

@export_group("Weapons")
## Main-gun shot. Gun sizes share the recordings, tuned by pitch and volume:
## cannon_fire_small / cannon_fire (medium) / cannon_fire_large in data/sounds/.
@export var gun_fire: SoundSetData

@export_group("Hatch")
@export var hatch_open: SoundSetData
@export var hatch_close: SoundSetData
