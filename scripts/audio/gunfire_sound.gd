class_name GunfireSound
extends AudioStreamPlayer3D
## Machine-gun sound: every bullet plays one shot (a random variant from the gun's
## set), so the sound always matches the rate of fire. Shots overlap through a
## polyphonic stream, so their tails ring into each other. Used by tanks and MG nests.

## Most shots ringing at once.
const POLYPHONY: int = 8

var _playback: AudioStreamPlaybackPolyphonic
var _set: SoundSetData
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = POLYPHONY
	stream = poly
	_rng.randomize()


## A bullet left the muzzle at `at`. `sounds` is the gun's shot set.
func on_shot(sounds: SoundSetData, at: Vector3) -> void:
	if sounds == null:
		return
	if sounds != _set:
		_set = sounds
		sounds.apply_to(self, SoundFx.AUDIO)
	global_position = at
	if not playing or _playback == null:
		play()
		_playback = get_stream_playback() as AudioStreamPlaybackPolyphonic
	var shot: AudioStream = sounds.pick(_rng)
	if _playback != null and shot != null:
		_playback.play_stream(shot, 0.0, 0.0, sounds.random_pitch(_rng))


func silence() -> void:
	stop()
	_playback = null
