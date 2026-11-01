class_name TargetBoard
extends StaticBody3D
## Practice target. Shows its range above it and leaves a mark where shells hit.

## Oldest marks are removed beyond this many.
const MAX_MARKS: int = 30
## Big and bright so hits can be seen through the sight at range (fun over realism).
const MARK_RADIUS: float = 0.25

## Text shown above the board, e.g. "500 m".
@export var range_label: String = ""

var hit_count: int = 0
## Last hit relative to the board's centre (board local space).
var last_hit_local: Vector3 = Vector3.ZERO

var _marks: Array[Node3D] = []
var _mark_mesh: SphereMesh
var _mark_material: StandardMaterial3D

@onready var _board: Node3D = $Board
@onready var _label: Label3D = $Label


func _ready() -> void:
	_label.text = range_label
	_mark_mesh = SphereMesh.new()
	_mark_mesh.radius = MARK_RADIUS
	_mark_mesh.height = MARK_RADIUS * 2.0
	_mark_material = StandardMaterial3D.new()
	_mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_material.albedo_color = Color(0.95, 0.1, 0.05)


## Hook called by Shell on impact. Boards have no armour: always a plain HIT.
func on_shell_hit(_shell_data: ShellData, point: Vector3, _normal: Vector3,
		_velocity: Vector3, _shape: int = -1) -> HitResult:
	hit_count += 1
	last_hit_local = _board.to_local(point)
	var mark := MeshInstance3D.new()
	mark.mesh = _mark_mesh
	mark.material_override = _mark_material
	_board.add_child(mark)
	mark.global_position = point
	_marks.append(mark)
	if _marks.size() > MAX_MARKS:
		_marks.pop_front().queue_free()
	var result := HitResult.new()
	result.target = self
	return result
