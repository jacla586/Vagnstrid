class_name TankAudio
extends Node3D
## Engine, track, MG, gun and hatch sounds of one tank (TankData.sounds). Reads the
## tank's state only, so it sounds the same on the host and on client puppets: speed
## comes from how far the tank moved, MG fire from Tank.mg_fired.
## The player rig moves its own tank to bus "Own" (see HatchMuffle).

const KMH_TO_MS: float = 1.0 / 3.6
## Quieter than this is treated as silent (dB).
const SILENT_DB: float = -80.0
## Faster than this between two frames is a teleport (respawn), not driving (m/s).
const MAX_PLAUSIBLE_SPEED: float = 60.0

var tank: Tank
## Audio bus for all of this tank's sounds.
var bus: StringName = SoundFx.WORLD_BUS

var _sounds: TankSoundData
var _idle: AudioStreamPlayer3D
var _drive: AudioStreamPlayer3D
var _tracks: AudioStreamPlayer3D
var _mg: GunfireSound
var _revs: float = 0.0
var _speed: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _last_hatch: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	assert(tank != null, "TankAudio needs its tank")
	_sounds = tank.data.sounds
	_rng.randomize()
	_idle = _make_player(_sounds.engine_idle)
	_drive = _make_player(_sounds.engine_drive)
	_tracks = _make_player(_sounds.tracks)
	# MG shots come from the firing gun's data (coax and roof may differ).
	_mg = GunfireSound.new()
	_mg.bus = bus
	add_child(_mg)
	_last_position = tank.global_position
	_last_hatch = tank.get_hatch_progress()
	tank.mg_fired.connect(_on_mg_fired)


func set_bus(bus_name: StringName) -> void:
	bus = bus_name
	for p: AudioStreamPlayer3D in [_idle, _drive, _tracks, _mg]:
		if p != null:
			p.bus = bus_name


## Main-gun shot at the muzzle (host and clients).
func play_gun(at: Vector3) -> void:
	SoundFx.play_at(self, _sounds.gun_fire, at, bus)


func _process(delta: float) -> void:
	_track_speed(delta)
	if tank.is_knocked_out():
		for p: AudioStreamPlayer3D in [_idle, _drive, _tracks]:
			if p != null and p.playing:
				p.stop()
		_mg.silence()
		_last_hatch = tank.get_hatch_progress()
		return
	_update_engine(delta)
	_update_tracks()
	_update_hatch()


func _track_speed(delta: float) -> void:
	var now: Vector3 = tank.global_position
	var moved: float = (now - _last_position).length()
	_last_position = now
	if delta <= 0.0:
		return
	var speed: float = moved / delta
	if speed > MAX_PLAUSIBLE_SPEED:
		return
	_speed = lerpf(_speed, speed, minf(delta * 8.0, 1.0))


func _update_engine(delta: float) -> void:
	var top: float = maxf(tank.data.max_forward_speed_kmh * KMH_TO_MS, 0.1)
	var throttle: float = absf(tank.get_command().throttle)
	var target: float = clampf(maxf(_speed / top, throttle * 0.6), 0.0, 1.0)
	_revs = lerpf(_revs, target, minf(delta * _sounds.engine_response, 1.0))
	var pitch: float = lerpf(_sounds.engine_pitch_min, _sounds.engine_pitch_max, _revs)
	if _idle != null:
		_ensure_playing(_idle)
		_idle.pitch_scale = pitch
		_idle.volume_db = _sounds.engine_idle.volume_db + _sounds.engine_idle_fade_db * _revs
	if _drive != null:
		_ensure_playing(_drive)
		_drive.pitch_scale = pitch
		_drive.volume_db = lerpf(_sounds.engine_drive_min_db, _sounds.engine_drive.volume_db, _revs)


func _update_tracks() -> void:
	if _tracks == null:
		return
	var top: float = maxf(tank.data.max_forward_speed_kmh * KMH_TO_MS, 0.1)
	var fraction: float = clampf(_speed / top, 0.0, 1.0)
	if _speed < _sounds.tracks_min_speed_kmh * KMH_TO_MS:
		if _tracks.playing:
			_tracks.stop()
		return
	_ensure_playing(_tracks)
	# Loud quickly once moving, then only the pitch keeps rising.
	_tracks.volume_db = _sounds.tracks.volume_db + maxf(linear_to_db(clampf(fraction * 3.0, 0.0, 1.0)), SILENT_DB)
	_tracks.pitch_scale = lerpf(_sounds.tracks_pitch_min, _sounds.tracks_pitch_max, fraction)


func _update_hatch() -> void:
	var hatch: float = tank.get_hatch_progress()
	if _last_hatch <= 0.0 and hatch > 0.0:
		SoundFx.play_at(self, _sounds.hatch_open, tank.get_commander_eye_position(), bus)
	elif _last_hatch > 0.0 and hatch <= 0.0:
		SoundFx.play_at(self, _sounds.hatch_close, tank.get_commander_eye_position(), bus)
	_last_hatch = hatch


func _on_mg_fired(bullet: Shell, roof: bool) -> void:
	var mg: MachineGunData = tank.get_active_mg(roof)
	if mg != null:
		_mg.on_shot(mg.sound_shot, bullet.global_position)


## A player for a loop set, or null when the tank has no such sound.
func _make_player(sounds: SoundSetData) -> AudioStreamPlayer3D:
	if sounds == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.bus = bus
	add_child(p)
	p.stream = sounds.pick(_rng)
	sounds.apply_to(p, SoundFx.AUDIO)
	p.pitch_scale = sounds.pitch_scale
	return p


## Starts a loop at a random point, so several tanks don't drone in step.
func _ensure_playing(p: AudioStreamPlayer3D) -> void:
	if p.playing or p.stream == null:
		return
	p.play(_rng.randf() * maxf(p.stream.get_length() - 0.1, 0.0))
