class_name TankLooks
extends Node
## A tank's living looks, read from how it moves (so puppets look the same; nothing is
## sent): the paint's weathering (tank_paint.gdshader instance values: dust that builds
## up as the tank drives, wetness in rain, where the mud line is on each part).
## Made by Tank.

## Dust on a clean tank, and how much more per metre driven (times the weather's
## dust_factor); it never quite covers the paint.
const DUST_START: float = 0.15
const DUST_PER_M: float = 1.0 / 1500.0
const DUST_MAX: float = 0.9
## Paint values are updated this often (Hz).
const PAINT_HZ: float = 4.0
## Parts that never get mud (gun, figure, roof MG): their mud line far below.
const NO_MUD_Y: float = -100.0
## Faster than this between two frames is a teleport (respawn), not driving (m/s).
const MAX_PLAUSIBLE_SPEED: float = 60.0

var tank: Tank

var _driven_m: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _paint_clock := PackedFloat32Array([0.0])
var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	_last_position = tank.global_position
	tank.repaired.connect(func() -> void: _driven_m = 0.0)
	_find_meshes.call_deferred()


## Every mesh of the tank's look and its mud line in its own space.
func _find_meshes() -> void:
	var visual: Node3D = tank.get_node("Visual")
	var bottom := Vector3(0.0, -tank.data.hull_size.y * 0.5, 0.0)
	_meshes.clear()
	for mi: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)
		var to_visual := Transform3D.IDENTITY
		var node: Node = mi
		while node != visual and node is Node3D:
			to_visual = (node as Node3D).transform * to_visual
			node = node.get_parent()
		var muddy: bool = not (mi.name in [&"Gun", &"Mantlet", &"CommanderFigure", &"Mount"])
		mi.set_instance_shader_parameter(&"base_y",
				(to_visual.affine_inverse() * bottom).y if muddy else NO_MUD_Y)
	_apply()


func _process(delta: float) -> void:
	var now: Vector3 = tank.global_position
	var step: float = (now - _last_position).length()
	if delta > 0.0 and step / delta <= MAX_PLAUSIBLE_SPEED:
		_driven_m += step
	_last_position = now
	if Ticks.due(_paint_clock, delta, PAINT_HZ):
		_apply()


func _apply() -> void:
	var weather: WeatherData = Weather.current()
	var dust_factor: float = weather.dust_factor if weather != null else 1.0
	var dust: float = minf(DUST_START + _driven_m * DUST_PER_M * dust_factor, DUST_MAX)
	var wet: float = weather.rain_intensity if weather != null else 0.0
	for mi: MeshInstance3D in _meshes:
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter(&"dust_amount", dust)
			mi.set_instance_shader_parameter(&"wetness", wet)
