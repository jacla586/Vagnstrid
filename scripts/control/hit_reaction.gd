class_name HitReaction
extends Node
## What the player feels when a gun round hits the own tank (Tank.struck): the view
## (commander's or gunner's) shakes hard, and a round that bounces off rings with a
## clear PING inside the tank. (PlayerController cancels held driving keys.)

@export var views: PlayerViews
## Played when a round ricochets off the own tank (heard with the hatch shut too).
@export var ping_sound: SoundSetData
## How long a shake lasts (s), and how fast it trembles (Hz).
@export var shake_time_s: float = 0.8
@export var shake_frequency_hz: float = 16.0
## Biggest swing as a share of the view's field of view, so a zoomed sight shakes as
## hard on screen as the naked eye; plus a roll (degrees).
@export var shake_fov_share: float = 0.06
@export var shake_roll_deg: float = 4.0
## Strength per outcome (penetration hits hardest).
@export var penetration_strength: float = 1.0
@export var no_penetration_strength: float = 0.8
@export var ricochet_strength: float = 0.6

var _tank: Tank
var _trauma: float = 0.0
var _time: float = 0.0
var _seed: Vector3 = Vector3.ZERO
var _ping_player: AudioStreamPlayer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


var _still: bool = false

func _ready() -> void:
	_rng.randomize()
	_ping_player = AudioStreamPlayer.new()
	add_child(_ping_player)


func _process(delta: float) -> void:
	_connect_to_tank()
	_time += delta
	_trauma = maxf(_trauma - delta / maxf(shake_time_s, 0.01), 0.0)
	var amount: float = _trauma * _trauma
	# At rest: the cameras already hold a zero shake.
	if amount == 0.0 and _still:
		return
	_still = amount == 0.0
	for cam: Camera3D in [views.commander_camera, views.gunner_camera]:
		if cam == null:
			continue
		var swing: float = deg_to_rad(cam.fov * shake_fov_share) * amount
		var w: float = TAU * shake_frequency_hz * _time
		var offset := Vector3(
				swing * sin(w + _seed.x) * cos(w * 0.37 + _seed.z),
				swing * sin(w * 1.13 + _seed.y),
				deg_to_rad(shake_roll_deg) * amount * sin(w * 0.71 + _seed.z))
		cam.set("shake", offset)


func _on_struck(outcome: int, _direction: Vector3) -> void:
	var strength: float = no_penetration_strength
	match outcome:
		HitResult.Outcome.PENETRATION: strength = penetration_strength
		HitResult.Outcome.RICOCHET: strength = ricochet_strength
	_trauma = clampf(maxf(_trauma, strength), 0.0, 1.0)
	_seed = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
	if outcome == HitResult.Outcome.RICOCHET and ping_sound != null:
		var stream: AudioStream = ping_sound.pick(_rng)
		if stream != null:
			_ping_player.stream = stream
			_ping_player.volume_db = ping_sound.volume_db
			_ping_player.pitch_scale = ping_sound.random_pitch(_rng)
			_ping_player.bus = ping_sound.bus if ping_sound.bus != &"" else GameSettings.EFFECTS_BUS
			_ping_player.play()


## Follows the player's current tank (connects once it exists).
func _connect_to_tank() -> void:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == _tank:
		return
	if _tank != null and is_instance_valid(_tank) and _tank.struck.is_connected(_on_struck):
		_tank.struck.disconnect(_on_struck)
	_tank = tank
	if _tank != null:
		_tank.struck.connect(_on_struck)
