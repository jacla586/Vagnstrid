class_name PlaygroundBreak
extends Node
## Playground equipment (geodata lekplatser.py: glb group `Lekplatser`, one node per piece
## named Lek_<park>_<nr>_<type>) gets pressed flat when a tank drives over it: it doesn't
## stop the tank, it just crumples (squashed, tipped a little). Checked a few times a second
## against every tank's footprint (group "tanks", puppets too, so every machine agrees
## without sending anything). Also gives the pieces a material that shows their vertex
## colours. Lives in the player rig; cosmetic and local.

const CHECK_HZ: float = 6.0
const CELL_M: float = 16.0
## A tank reaches this far from its centre (m) when crushing.
const TANK_RADIUS_M: float = 3.2

var _pieces: Array[Node3D] = []
var _boxes: Array[AABB] = []
var _broken: PackedByteArray = PackedByteArray()
var _grid: Dictionary = {}   # Vector2i -> Array[int]
var _clock := PackedFloat32Array([0.0])
var _found: bool = false
var _material: StandardMaterial3D


func _physics_process(delta: float) -> void:
	if not _found:
		_found = true
		_collect()
		if _pieces.is_empty():
			set_physics_process(false)
			return
	if not Ticks.due(_clock, delta, CHECK_HZ):
		return
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Node3D
		if tank == null:
			continue
		var p: Vector3 = tank.global_position
		var c := Vector2i(floori(p.x / CELL_M), floori(p.z / CELL_M))
		for dz: int in range(-1, 2):
			for dx: int in range(-1, 2):
				for i: int in _grid.get(c + Vector2i(dx, dz), []):
					if _broken[i] == 0 and _touches(_boxes[i], p):
						_crush(i)


func _collect() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		return
	# the pieces carry their colours as vertex colours (linear), which the glTF import doesn't use
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.75
	for group: Node in root.find_children("Lekplatser", "", true, false):
		for child: Node in group.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			var box: AABB = mi.global_transform * mi.get_aabb()
			mi.visibility_range_end = 450.0
			mi.material_override = _material
			var i: int = _pieces.size()
			_pieces.append(mi)
			_boxes.append(box)
			var c := Vector2i(floori(box.get_center().x / CELL_M), floori(box.get_center().z / CELL_M))
			if not _grid.has(c):
				_grid[c] = []
			_grid[c].append(i)
	_broken.resize(_pieces.size())


func _touches(box: AABB, p: Vector3) -> bool:
	var q := Vector2(clampf(p.x, box.position.x, box.end.x), clampf(p.z, box.position.z, box.end.z))
	return q.distance_to(Vector2(p.x, p.z)) < TANK_RADIUS_M and absf(p.y - box.position.y) < 4.0


func _crush(i: int) -> void:
	_broken[i] = 1
	var mi: Node3D = _pieces[i]
	var base: Vector3 = _boxes[i].get_center()
	base.y = _boxes[i].position.y
	# squash towards the ground at the piece's foot, with a small random tip
	var rng := RandomNumberGenerator.new()
	rng.seed = i
	var squash := Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.15, 0.15), 0.0,
			rng.randf_range(-0.15, 0.15))).scaled(Vector3(1.05, 0.12, 1.05)), Vector3.ZERO)
	var to_base := Transform3D(Basis(), base)
	mi.global_transform = to_base * squash * to_base.affine_inverse() * mi.global_transform
