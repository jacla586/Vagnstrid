class_name SoundSetData
extends Resource
## One kind of sound (a cannon shot, a ricochet...). A random variant plays each time.
## Loop sets (engine, tracks, MG) play their first stream on repeat.

@export var streams: Array[AudioStream] = []
## Loudness at unit_size_m from the source (dB).
@export var volume_db: float = 0.0
## Distance where the sound is at volume_db; larger = carries further (m).
@export var unit_size_m: float = 10.0
## Not heard beyond this (m).
@export var max_distance_m: float = 2000.0
## Base pitch, and how much each play may vary up or down (share, 0.1 = ±10 %).
@export var pitch_scale: float = 1.0
@export_range(0.0, 0.5) var pitch_variance: float = 0.05
## Repeat the first stream (engine, tracks, MG).
@export var loop: bool = false
## Heard further away than distant_from_m, this set plays instead (a dull boom).
@export var distant: SoundSetData
@export var distant_from_m: float = 600.0
## Audio bus for one-shots of this set ("" = the caller's, usually the muffled World).
## "Master" is heard clearly even with the own hatch shut.
@export var bus: StringName = &""
## A blast loud enough to carry through a closed hull (cannon shots): heard from the
## World bus it plays on bus "Blast", only lightly muffled (AudioData.blast_*).
@export var pierces_hull: bool = false


## A random variant, or null if the set is empty.
func pick(rng: RandomNumberGenerator) -> AudioStream:
	if streams.is_empty():
		return null
	var stream: AudioStream = streams[rng.randi_range(0, streams.size() - 1)]
	if loop and stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	return stream


func random_pitch(rng: RandomNumberGenerator) -> float:
	return pitch_scale * (1.0 + rng.randf_range(-pitch_variance, pitch_variance))


## Sets a 3D player's loudness and range from this set (not the stream).
func apply_to(player: AudioStreamPlayer3D, audio: AudioData) -> void:
	player.volume_db = volume_db
	player.unit_size = unit_size_m
	player.max_distance = max_distance_m
	player.max_db = audio.max_db
	player.attenuation_filter_db = audio.distance_filter_db
