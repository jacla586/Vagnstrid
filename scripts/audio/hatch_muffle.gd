class_name HatchMuffle
extends Node
## Player rig: with the own hatch closed the outside world sounds dull and distant
## (bus "World": low-pass and lower volume, from data/world/audio.tres); opening the
## hatch brings it back. The own tank's sounds move to bus "Own" and stay clear.

const AUDIO: AudioData = preload("res://data/world/audio.tres")
const WORLD_BUS: StringName = &"World"
const OWN_BUS: StringName = &"Own"

@export var tank: Tank

var _bus: int = -1
var _filter: AudioEffectLowPassFilter


func _ready() -> void:
	_bus = AudioServer.get_bus_index(WORLD_BUS)
	if _bus < 0 or tank == null:
		push_warning("HatchMuffle: no '%s' audio bus or no tank" % WORLD_BUS)
		set_process(false)
		return
	for i: int in AudioServer.get_bus_effect_count(_bus):
		var effect: AudioEffect = AudioServer.get_bus_effect(_bus, i)
		if effect is AudioEffectLowPassFilter:
			_filter = effect
	tank.set_audio_bus(OWN_BUS)


func _process(_delta: float) -> void:
	_apply(smoothstep(0.0, 1.0, tank.get_hatch_progress()))


func _exit_tree() -> void:
	if _bus >= 0:
		_apply(1.0)


## open: 0 = hatch closed (muffled) .. 1 = open (clear).
func _apply(open: float) -> void:
	if _filter != null:
		# Ears hear pitch logarithmically: sweep the cutoff exponentially.
		var ratio: float = AUDIO.open_cutoff_hz / maxf(AUDIO.muffled_cutoff_hz, 1.0)
		_filter.cutoff_hz = AUDIO.muffled_cutoff_hz * pow(ratio, open)
	AudioServer.set_bus_volume_db(_bus, lerpf(AUDIO.muffled_volume_db, 0.0, open))
