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
var _blast_bus: int = -1
var _blast_filter: AudioEffectLowPassFilter


func _ready() -> void:
	_bus = AudioServer.get_bus_index(WORLD_BUS)
	if _bus < 0 or tank == null:
		push_warning("HatchMuffle: no '%s' audio bus or no tank" % WORLD_BUS)
		set_process(false)
		return
	_filter = _find_filter(_bus)
	_blast_bus = AudioServer.get_bus_index(SoundFx.BLAST_BUS)
	if _blast_bus >= 0:
		_blast_filter = _find_filter(_blast_bus)
	tank.set_audio_bus(OWN_BUS)


func _process(_delta: float) -> void:
	_apply(smoothstep(0.0, 1.0, tank.get_hatch_progress()))


func _exit_tree() -> void:
	if _bus >= 0:
		_apply(1.0)


## open: 0 = hatch closed (muffled) .. 1 = open (clear).
func _apply(open: float) -> void:
	_muffle(_bus, _filter, AUDIO.muffled_cutoff_hz, AUDIO.muffled_volume_db, open)
	if _blast_bus >= 0:
		_muffle(_blast_bus, _blast_filter, AUDIO.blast_muffled_cutoff_hz,
				AUDIO.blast_muffled_volume_db, open)


static func _muffle(bus: int, filter: AudioEffectLowPassFilter, cutoff_hz: float,
		volume_db: float, open: float) -> void:
	if filter != null:
		# Ears hear pitch logarithmically: sweep the cutoff exponentially.
		var ratio: float = AUDIO.open_cutoff_hz / maxf(cutoff_hz, 1.0)
		filter.cutoff_hz = cutoff_hz * pow(ratio, open)
	AudioServer.set_bus_volume_db(bus, lerpf(volume_db, 0.0, open))


static func _find_filter(bus: int) -> AudioEffectLowPassFilter:
	for i: int in AudioServer.get_bus_effect_count(bus):
		var effect: AudioEffect = AudioServer.get_bus_effect(bus, i)
		if effect is AudioEffectLowPassFilter:
			return effect
	return null
