class_name FallingTree
extends Node3D
## A felled laser tree (TreeField) on its way down. Sits at the tree's foot and tips
## its mesh over with the angle growing as t² (slow start), like BreakableTree.
## Stays lying when done.

## Emitted once the tree has come to rest; `tilt` is the final rotation.
signal landed(tilt: Basis)

var _axis: Vector3 = Vector3.RIGHT
var _fall_time: float = 1.6
var _max_angle: float = deg_to_rad(85.0)
var _time: float = 0.0


## `visual` is the tree's own transform relative to its foot (scale and spin).
func setup(mesh: Mesh, visual: Basis, direction: Vector3, data: TreeData,
		cast_shadows: bool) -> void:
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3.FORWARD
	# Rotating "up" around (up × direction) tips the top towards `direction`.
	_axis = Vector3.UP.cross(horizontal.normalized()).normalized()
	_fall_time = maxf(data.fall_time_s, 0.01)
	_max_angle = deg_to_rad(data.fallen_angle_deg)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.basis = visual
	instance.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	add_child(instance)


func _process(delta: float) -> void:
	_time = minf(_time + delta, _fall_time)
	var t: float = _time / _fall_time
	basis = Basis(_axis, _max_angle * t * t)
	if _time >= _fall_time:
		set_process(false)
		landed.emit(basis)
