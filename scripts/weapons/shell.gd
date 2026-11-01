class_name Shell
extends Node3D
## A simulated shell. Flies with Ballistics.integrate() (same model as the sight's
## range ladder) and detects hits by raycasting from its previous to its current
## position every physics frame. Not a physics body.
##
## On a hit it spawns an impact effect and calls
## `on_shell_hit(shell_data, point, normal, velocity)` on the collider if it has it.

const MAX_LIFETIME: float = 15.0
## Freed if it somehow gets this far below the world origin (m).
const MIN_HEIGHT: float = -200.0
## Tracer grows wider with age so it stays visible at long range (fun over realism).
const TRACER_GROWTH_PER_SECOND: float = 4.0
const IMPACT_SCENE: PackedScene = preload("res://scenes/effects/impact.tscn")

var _data: ShellData
var _velocity: Vector3 = Vector3.ZERO
var _drag_factor: float = 0.0
var _shooter: CollisionObject3D
var _age: float = 0.0

@onready var _tracer: MeshInstance3D = $Tracer


## Starts the flight. Call after the shell is in the scene tree.
func launch(data: ShellData, start_position: Vector3, velocity: Vector3,
		shooter: CollisionObject3D) -> void:
	_data = data
	_velocity = velocity
	_drag_factor = Ballistics.drag_factor(data)
	_shooter = shooter
	global_position = start_position
	_orient()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = data.tracer_color
	_tracer.material_override = material


func get_velocity() -> Vector3:
	return _velocity


func get_age() -> float:
	return _age


func _physics_process(delta: float) -> void:
	if _data == null:
		return
	_age += delta
	if _age > MAX_LIFETIME or global_position.y < MIN_HEIGHT:
		queue_free()
		return
	var from: Vector3 = global_position
	var next: PackedVector3Array = Ballistics.integrate(from, _velocity, _drag_factor, delta)
	var query := PhysicsRayQueryParameters3D.create(from, next[0])
	if _shooter != null:
		query.exclude = [_shooter.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_on_hit(hit)
		return
	global_position = next[0]
	_velocity = next[1]
	_orient()
	var width: float = 1.0 + _age * TRACER_GROWTH_PER_SECOND
	_tracer.scale = Vector3(width, 1.0, width)


func _on_hit(hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var effect: Node3D = IMPACT_SCENE.instantiate()
	get_parent().add_child(effect)
	effect.global_position = point
	var collider: Object = hit["collider"]
	if collider != null and collider.has_method("on_shell_hit"):
		collider.on_shell_hit(_data, point, normal, _velocity)
	queue_free()


## Points -Z along the velocity (the tracer is stretched along Z).
func _orient() -> void:
	if _velocity.length_squared() < 0.0001:
		return
	var direction: Vector3 = _velocity.normalized()
	var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD
	global_basis = Basis.looking_at(direction, up)
