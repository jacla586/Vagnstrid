class_name RespawnAtStart
extends Node
## Brings a knocked-out tank back, repaired, after a delay: where it started, or at
## its team's current spawn in King of the Hill (spawns follow the zone).

@export var tank: Tank
## Seconds after the knock-out until the tank is back at its start.
@export var delay_s: float = 10.0

var _start: Transform3D
var _timer: float = -1.0


func _ready() -> void:
	if tank == null:
		return
	_start = tank.global_transform
	tank.knocked_out.connect(func() -> void: _timer = delay_s)


func _physics_process(delta: float) -> void:
	if _timer < 0.0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = -1.0
	if ThunderRoadMode.instance != null:
		return   # ThunderRoad brings tanks back itself (waves, respawn points)
	var mode: KothMode = KothMode.instance
	KothMode.place_tank(tank, mode.get_free_spawn(tank.team, tank) if mode != null else _start)
	tank.repair()
