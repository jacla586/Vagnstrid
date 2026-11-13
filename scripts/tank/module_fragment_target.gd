class_name ModuleFragmentTarget
extends Node3D
## Lets HE fragments reach one of a tank's external modules (tracks). Made by Tank at
## start, one per external module, placed at the module box's centre. Uses the
## fragment-target interface of Explosion (line of sight + hit roll).

var tank: Tank
var module_id: StringName
var _shooter: Node


func _ready() -> void:
	add_to_group(Explosion.TARGET_GROUP)


func is_fragment_target_active() -> bool:
	return tank != null and not tank.is_knocked_out()


func get_fragment_aim_point() -> Vector3:
	return global_position


func get_fragment_collider() -> CollisionObject3D:
	return tank


## The tank's collider is the whole hull: only count fragments that strike this
## module's box (not the far side's track through the hull).
func fragment_hit_ok(point: Vector3) -> bool:
	return tank.is_point_in_module(module_id, point, 0.3)


## Explosion: who fired the round whose fragments come next (credit for the damage).
func note_fragment_shooter(shooter: Node) -> void:
	_shooter = shooter


func on_fragment_hit(shell_data: ShellData, _distance: float) -> HitResult:
	var shooter: Node = _shooter if is_instance_valid(_shooter) else null
	_shooter = null
	return tank.on_module_fragment(module_id, shell_data, shooter)
