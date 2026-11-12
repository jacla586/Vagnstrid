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
	tank.knocked_out.connect(_on_knocked_out)


## Where the tank started (and comes back outside King of the Hill).
func get_start() -> Transform3D:
	return _start


## Looks after `new_tank` instead (the player changed tank type: TankSwitch); same start.
func set_tank(new_tank: Tank) -> void:
	if is_instance_valid(tank) and tank.knocked_out.is_connected(_on_knocked_out):
		tank.knocked_out.disconnect(_on_knocked_out)
	tank = new_tank
	_timer = -1.0
	tank.knocked_out.connect(_on_knocked_out)


func _on_knocked_out() -> void:
	_timer = delay_s


func _physics_process(delta: float) -> void:
	if _timer < 0.0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = -1.0
	if ThunderRoadMode.instance != null or FreeFight.instance != null:
		return   # ThunderRoad and free fight bring tanks back themselves
	var mode: KothMode = KothMode.instance
	KothMode.place_tank(tank, mode.get_free_spawn(tank.team, tank) if mode != null else _start)
	tank.repair()
