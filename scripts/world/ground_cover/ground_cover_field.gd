class_name GroundCoverField
extends Node3D
## Draws the ground vegetation (GroundCover) round the active camera: square cells of
## GroundCoverSetData.cell_m within draw_radius_m, one MultiMesh per class and cell,
## placed on the terrain with a fixed random pattern per cell (the same grass every
## time). Cells are built a few per frame as the camera moves and dropped when far.
## Lives in the player rig; purely cosmetic and local (bots use GroundCover's rule).

## Cells built per frame at most (spreads the cost when the camera jumps).
@export var cells_per_frame: int = 2

var _gc: GroundCover
var _cells: Dictionary = {}   # Vector2i -> Node3D
var _tried: bool = false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY   # instances are placed in world coordinates
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(_delta: float) -> void:
	if _gc == null:
		if _tried and Engine.get_process_frames() % 60 != 0:
			return
		_tried = true
		_gc = GroundCover.of(self)
		if _gc == null:
			return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var p: Vector3 = cam.global_position
	var cell: float = _gc.rules.cell_m
	var reach: float = _gc.rules.draw_radius_m + cell * 0.75
	var c0 := Vector2i(floori(p.x / cell), floori(p.z / cell))
	var n: int = ceili(reach / cell)
	var wanted: Array[Vector2i] = []
	for dz: int in range(-n, n + 1):
		for dx: int in range(-n, n + 1):
			var c := Vector2i(c0.x + dx, c0.y + dz)
			var centre := Vector2((c.x + 0.5) * cell, (c.y + 0.5) * cell)
			if centre.distance_to(Vector2(p.x, p.z)) <= reach:
				wanted.append(c)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - c0).length_squared() < (b - c0).length_squared())
	var built: int = 0
	# The camera jumped (spawn, view change): everything at once, else a few per frame.
	var limit: int = wanted.size() if not _cells.has(c0) else cells_per_frame
	for c: Vector2i in wanted:
		if _cells.has(c):
			continue
		_cells[c] = _build_cell(c)
		built += 1
		if built >= limit:
			break
	if built > 0 and OS.has_environment("GC_DEBUG"):
		print("gcfield built ", built, " at ", c0, " cells ", _cells.size(), " cam ", cam.get_path())
	var keep: Dictionary = {}
	for c: Vector2i in wanted:
		keep[c] = true
	for c: Vector2i in _cells.keys():
		if not keep.has(c) and (c - c0).length() > n + 1.5:
			var node: Node3D = _cells[c]
			_cells.erase(c)
			if node != null:
				node.queue_free()


func _build_cell(c: Vector2i) -> Node3D:
	var rules: GroundCoverSetData = _gc.rules
	var cell: float = rules.cell_m
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	var max_density: float = 0.0
	for k: GroundCoverClassData in rules.classes:
		if k != null:
			max_density = maxf(max_density, k.density)
	if max_density <= 0.0:
		return null
	var per_class: Dictionary = {}   # class index -> Array[Transform3D, Color]
	var tries: int = int(cell * cell * max_density)
	var x0: float = c.x * cell
	var z0: float = c.y * cell
	for i: int in tries:
		var x: float = x0 + rng.randf() * cell
		var z: float = z0 + rng.randf() * cell
		var r1: float = rng.randf()
		var r2: float = rng.randf()
		var r3: float = rng.randf()
		var ci: int = _gc.data.class_at(Vector3(x, 0.0, z))
		if ci <= 0 or ci >= rules.classes.size():
			continue
		var k: GroundCoverClassData = rules.classes[ci]
		if k == null or k.density <= 0.0 or r1 * max_density > k.density:
			continue
		var y: float = _gc.ground_y(x, z)
		if is_nan(y):
			continue
		var h: float = k.height_m * (1.0 + (r2 * 2.0 - 1.0) * k.height_jitter)
		var t := Transform3D(Basis(Vector3.UP, r3 * TAU).scaled(Vector3(1.0, h, 1.0)), Vector3(x, y - 0.02, z))
		if not per_class.has(ci):
			per_class[ci] = []
		per_class[ci].append([t, k.color_a.lerp(k.color_b, r2).srgb_to_linear()])
	var node := Node3D.new()
	node.name = "Cell_%d_%d" % [c.x, c.y]
	add_child(node)
	for ci: int in per_class:
		node.add_child(GroundCoverField.make_instances(rules.classes[ci], per_class[ci], rules))
	return node


## A MultiMeshInstance3D of `list` ([Transform3D, Color] pairs) of class `k`.
static func make_instances(k: GroundCoverClassData, list: Array, rules: GroundCoverSetData) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = GroundCoverMesh.mesh_for(k)
	mm.instance_count = list.size()
	for i: int in list.size():
		mm.set_instance_transform(i, list[i][0])
		mm.set_instance_color(i, list[i][1])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = GroundCoverMesh.material(rules)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	return mi
