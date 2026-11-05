class_name SoundFx
extends AudioStreamPlayer3D
## A one-shot 3D sound placed in the world (shot, impact, hatch...). It starts after
## distance / speed of sound, so far shots are heard after their flash, plays a
## "distant" variant when far away, and frees itself when done.

const AUDIO: AudioData = preload("res://data/world/audio.tres")
const WORLD_BUS: StringName = &"World"

static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _delay: float = 0.0


## Plays a variant of `sounds` at `at`. Returns the player, or null when nothing plays
## (no set, empty set, or beyond its range).
static func play_at(context: Node, sounds: SoundSetData, at: Vector3,
		bus_name: StringName = WORLD_BUS) -> SoundFx:
	if sounds == null or context == null or not context.is_inside_tree():
		return null
	var distance: float = 0.0
	var camera: Camera3D = context.get_viewport().get_camera_3d()
	if camera != null:
		distance = camera.global_position.distance_to(at)
	var chosen: SoundSetData = sounds
	if sounds.distant != null and distance > sounds.distant_from_m:
		chosen = sounds.distant
	if distance > chosen.max_distance_m:
		return null
	var stream: AudioStream = chosen.pick(_rng)
	if stream == null:
		return null
	var fx := SoundFx.new()
	fx.stream = stream
	chosen.apply_to(fx, AUDIO)
	fx.pitch_scale = chosen.random_pitch(_rng)
	fx.bus = chosen.bus if chosen.bus != &"" else bus_name
	fx._delay = distance / maxf(AUDIO.speed_of_sound_mps, 1.0)
	context.get_tree().root.add_child(fx)
	fx.global_position = at
	return fx


func _ready() -> void:
	finished.connect(queue_free)
	if _delay <= 0.0:
		play()
		set_process(false)


func _process(delta: float) -> void:
	_delay -= delta
	if _delay <= 0.0:
		play()
		set_process(false)
