class_name AudioData
extends Resource
## World-wide sound settings (data/world/audio.tres).

## Sounds reach the listener after distance / this (m/s). Fun bonus: count from the
## muzzle flash to the bang to judge range.
@export var speed_of_sound_mps: float = 343.0
## Own hatch closed: world sounds (bus "World") are low-passed to this (Hz)...
@export var muffled_cutoff_hz: float = 900.0
## ...and turned down by this much (dB).
@export var muffled_volume_db: float = -8.0
## Loud blasts (SoundSetData.pierces_hull: cannon shots) go to bus "Blast" instead,
## which the closed hatch muffles only this much: they carry through the hull (Hz, dB).
@export var blast_muffled_cutoff_hz: float = 3500.0
@export var blast_muffled_volume_db: float = -2.0
## Own hatch open: the low-pass sits here (Hz, ~no effect).
@export var open_cutoff_hz: float = 20000.0
## Godot dulls 3D sounds with distance (attenuation filter, default -24 dB). Weaker
## here so far blasts and MGs stay crisp (fun over realism).
@export var distance_filter_db: float = -6.0
## Loudest a 3D sound may get up close (dB; Godot's limit is +6).
@export var max_db: float = 6.0
