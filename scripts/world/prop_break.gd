class_name PropBreak
extends Node
## Street furniture tanks knock down (cosmetic, local on every machine, nothing sent):
## - glb group `Valtbart` (geodata valtbart.py): templates `Mall_<kind>` (one mesh child per
##   material, foot at the origin) and one empty node `<kind>__<key>` per prop (street lamps,
##   catenary masts, road signs, bus stop signs with their names, place-name signs, reflector
##   posts, guard rail pieces (2 m, scaled along x), bus shelters). Drawn here as one MultiMesh per kind and `data.cell_m` cell (as many
##   draw calls as the merged meshes before); a prop a tank touches is hidden and a
##   FallenProp topples in its place. A mast `Kontaktstolpe_*__<track>_<i>` drops the
##   catenary spans `Ledning__<track>_<i-1>` and `_<i>` with it.
## - glb group `Lekplatser` (lekplatser.py, one node per piece): a piece a tank touches
##   falls apart into its parts (FallenProp.scatter). Also gives the pieces a material
##   that shows their vertex colours.
## Checked against every tank's hull footprint (group "tanks", puppets too, so every
## machine agrees). ThunderRoad's map reset puts everything back. The node sits in the
## player rig and moves itself to the map scene, so a new rig (tank change) keeps the
## state; a second one frees itself.

static var instance: PropBreak

@export var data: PropBreakData

const GRID_M: float = 16.0
## A tank reaches about this far from its centre (m): wider lookups aren't needed.
const TANK_REACH_M: float = 5.0

# standing props
var _kind_of: PackedInt32Array = PackedInt32Array()
var _xform: Array[Transform3D] = []
var _multimesh: Array[MultiMesh] = []
var _slot: PackedInt32Array = PackedInt32Array()
var _down: PackedByteArray = PackedByteArray()
var _spans_of: Array = []                 # prop -> Array[MeshInstance3D] it drops
var _templates: Array[Mesh] = []
var _kind_names: PackedStringArray = PackedStringArray()
var _kind_margin: PackedFloat32Array = PackedFloat32Array()   # per kind: tank_margin_m + kind_reach_m
# playground pieces
var _pieces: Array[MeshInstance3D] = []
var _boxes: Array[AABB] = []
var _broken: PackedByteArray = PackedByteArray()
var _material: StandardMaterial3D
# wires
var _spans: Array[MeshInstance3D] = []
var _span_xform: Array[Transform3D] = []

var _grid: Dictionary = {}   # Vector2i -> PackedInt32Array (props >= 0, pieces as -1 - i)
var _last_pos: Dictionary = {}   # tank instance id -> Vector3 at the last check
var _clock := PackedFloat32Array([0.0])
var _found: bool = false


func _ready() -> void:
	if is_instance_valid(instance) and instance != self:
		set_physics_process(false)
		queue_free()
		return
	instance = self
	if data == null:
		data = load("res://data/world/prop_break.tres") as PropBreakData
	_move_to_scene.call_deferred()


func _exit_tree() -> void:
	if instance == self and is_queued_for_deletion():
		instance = null


func _move_to_scene() -> void:
	var scene: Node = get_tree().current_scene
	if scene != null and get_parent() != scene and is_inside_tree():
		reparent(scene, false)


func _physics_process(delta: float) -> void:
	if not _found:
		_found = true
		_collect()
		if _kind_of.is_empty() and _pieces.is_empty():
			set_physics_process(false)
			return
	if not Ticks.due(_clock, delta, data.check_hz):
		return
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or tank.data == null:
			continue
		var p: Vector3 = tank.global_position
		var id: int = tank.get_instance_id()
		var moved: Vector3 = p - _last_pos.get(id, p)
		_last_pos[id] = p
		var c := Vector2i(floori(p.x / GRID_M), floori(p.z / GRID_M))
		for dz: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var cell: Variant = _grid.get(c + Vector2i(dx, dz))
				if cell == null:
					continue
				for i: int in cell as PackedInt32Array:
					if i >= 0:
						if _down[i] == 0 and _in_footprint(tank, _xform[i].origin, _kind_margin[_kind_of[i]]):
							_topple(i, _push_dir(moved, p, _xform[i].origin))
					elif _broken[-1 - i] == 0 and _box_touched(tank, _boxes[-1 - i]):
						_break_piece(-1 - i, _push_dir(moved, p, _boxes[-1 - i].get_center()))


# --- Collecting ---------------------------------------------------------------------

func _collect() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		return
	for group: Node in root.find_children("Valtbart", "", true, false):
		_collect_props(group)
	for group: Node in root.find_children("Lekplatser", "", true, false):
		_collect_playground(group)
	var mode: ThunderRoadMode = ThunderRoadMode.instance
	if mode != null and not mode.map_reset.is_connected(restore_all):
		mode.map_reset.connect(restore_all)


func _collect_props(group: Node) -> void:
	var kinds: Dictionary = {}   # kind name -> index
	var span_by_key: Dictionary = {}
	var props: Array = []   # [kind name, key, Transform3D]
	for child: Node in group.get_children():
		var n: String = child.name
		if n.begins_with("Mall_"):
			var mesh := _template_mesh(child)
			if mesh != null:
				kinds[n.substr(5)] = _templates.size()
				_templates.append(mesh)
				_kind_names.append(n.substr(5))
				var margin: float = data.tank_margin_m
				for prefix: Variant in data.kind_reach_m:
					if n.substr(5).begins_with(String(prefix)):
						margin += float(data.kind_reach_m[prefix])
				_kind_margin.append(margin)
			continue
		var split: int = n.find("__")
		if split < 0:
			continue
		var kind: String = n.substr(0, split)
		var key: String = n.substr(split + 2)
		if kind == "Ledning":
			var mi := child.find_children("*", "MeshInstance3D", true, false)
			var span: MeshInstance3D = child as MeshInstance3D
			if span == null and not mi.is_empty():
				span = mi[0] as MeshInstance3D
			if span != null:
				if data.draw_range_m > 0.0:
					span.visibility_range_end = data.draw_range_m
				span_by_key[key] = span
				_spans.append(span)
				_span_xform.append(span.global_transform)
			continue
		props.append([kind, key, (child as Node3D).global_transform if child is Node3D else Transform3D()])
	# one MultiMesh per kind and cell
	var batches: Dictionary = {}   # Vector3i(kind, cx, cz) -> Array[int]
	for row: Array in props:
		if not kinds.has(row[0]):
			continue
		var i: int = _kind_of.size()
		var xf: Transform3D = row[2]
		_kind_of.append(kinds[row[0]])
		_xform.append(xf)
		_down.append(0)
		_slot.append(0)
		_multimesh.append(null)
		var spans: Array[MeshInstance3D] = []
		if String(row[0]).begins_with("Kontaktstolpe"):
			var parts: PackedStringArray = String(row[1]).split("_")
			if parts.size() == 2:
				for j: int in [int(parts[1]) - 1, int(parts[1])]:
					var key := "%s_%d" % [parts[0], j]
					if span_by_key.has(key):
						spans.append(span_by_key[key])
		_spans_of.append(spans)
		var b := Vector3i(kinds[row[0]], floori(xf.origin.x / data.cell_m), floori(xf.origin.z / data.cell_m))
		if not batches.has(b):
			batches[b] = []
		batches[b].append(i)
		_add_to_grid(xf.origin, i)
	for b: Vector3i in batches:
		var list: Array = batches[b]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _templates[b.x]
		mm.instance_count = list.size()
		for k: int in list.size():
			var i: int = list[k]
			mm.set_instance_transform(k, _xform[i])
			_multimesh[i] = mm
			_slot[i] = k
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [_kind_names[b.x], b.y, b.z]
		mmi.multimesh = mm
		var reach: float = data.draw_range_m
		for prefix: String in data.small_kinds:
			if _kind_names[b.x].begins_with(prefix):
				reach = data.small_draw_range_m
		if reach > 0.0:
			mmi.visibility_range_end = reach
			mmi.visibility_range_end_margin = 30.0
		add_child(mmi)
	# the empties and templates are read: drop them
	for child: Node in group.get_children():
		if child.name.begins_with("Mall_") or (child.name.contains("__") and not child.name.begins_with("Ledning")):
			child.queue_free()


## A template: its mesh children merged into one mesh (a surface per material).
func _template_mesh(node: Node) -> Mesh:
	var out := ArrayMesh.new()
	var instances: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		instances.push_front(node)
	for n: Node in instances:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var local: Transform3D = (node as Node3D).global_transform.affine_inverse() * mi.global_transform
		for s: int in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			if local != Transform3D.IDENTITY:
				var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for k: int in v.size():
					v[k] = local * v[k]
				arrays[Mesh.ARRAY_VERTEX] = v
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			out.surface_set_material(out.get_surface_count() - 1, mat)
	return out if out.get_surface_count() > 0 else null


func _collect_playground(group: Node) -> void:
	if _material == null:
		# the pieces carry their colours as vertex colours (linear), which the glTF import doesn't use
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.75
	for child: Node in group.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var i: int = _pieces.size()
		_pieces.append(mi)
		_boxes.append(mi.global_transform * mi.get_aabb())
		_broken.append(0)
		mi.visibility_range_end = data.playground_draw_range_m
		mi.material_override = _material
		_add_to_grid(_boxes[i].get_center(), -1 - i)


func _add_to_grid(p: Vector3, entry: int) -> void:
	var c := Vector2i(floori(p.x / GRID_M), floori(p.z / GRID_M))
	var cell: PackedInt32Array = _grid.get(c, PackedInt32Array())
	cell.append(entry)
	_grid[c] = cell


# --- Hits ---------------------------------------------------------------------------

func _in_footprint(tank: Tank, p: Vector3, m: float) -> bool:
	if tank.global_position.distance_squared_to(p) > TANK_REACH_M * TANK_REACH_M + 25.0:
		return false
	var local: Vector3 = tank.global_transform.affine_inverse() * p
	var half: Vector3 = tank.data.hull_size * 0.5
	return absf(local.x) <= half.x + m and absf(local.z) <= half.z + m and local.y > -half.y - 3.0 \
			and local.y < half.y + 2.0


## The tank's hull footprint (a rectangle) against a piece's box, on the ground plane.
func _box_touched(tank: Tank, box: AABB) -> bool:
	var p: Vector3 = tank.global_position
	if absf(p.y - box.position.y) > 4.0:
		return false
	var q := Vector3(clampf(p.x, box.position.x, box.end.x), p.y, clampf(p.z, box.position.z, box.end.z))
	if q.distance_to(p) > TANK_REACH_M:
		return false
	# the box corner or edge nearest the tank's centre, in the tank's frame
	var local: Vector3 = tank.global_transform.affine_inverse() * q
	var half: Vector3 = tank.data.hull_size * 0.5
	var m: float = data.tank_margin_m
	if absf(local.x) <= half.x + m and absf(local.z) <= half.z + m:
		return true
	# the tank's nose or corner inside the box
	for corner: Vector3 in [Vector3(half.x, 0, half.z), Vector3(-half.x, 0, half.z),
			Vector3(half.x, 0, -half.z), Vector3(-half.x, 0, -half.z)]:
		var w: Vector3 = tank.global_transform * corner
		if w.x >= box.position.x and w.x <= box.end.x and w.z >= box.position.z and w.z <= box.end.z:
			return true
	return false


func _push_dir(moved: Vector3, tank_pos: Vector3, at: Vector3) -> Vector3:
	var flat := Vector3(moved.x, 0.0, moved.z)
	if flat.length() > 0.15:
		return flat.normalized()
	var away := Vector3(at.x - tank_pos.x, 0.0, at.z - tank_pos.z)
	return away.normalized() if away.length_squared() > 0.0001 else Vector3.FORWARD


func _topple(i: int, direction: Vector3) -> void:
	_down[i] = 1
	_multimesh[i].set_instance_transform(_slot[i], Transform3D(Basis.from_scale(Vector3.ZERO),
			_xform[i].origin))
	var fallen := FallenProp.new()
	add_child(fallen)
	fallen.topple(_templates[_kind_of[i]], _xform[i], direction, data)
	for span: MeshInstance3D in _spans_of[i]:
		if not span.visible:
			continue
		span.visible = false
		var box: AABB = span.global_transform * span.get_aabb()
		var wire := FallenProp.new()
		add_child(wire)
		wire.drop(span.mesh, span.global_transform, box.position.y - _xform[i].origin.y - 0.3, data)


func _break_piece(i: int, direction: Vector3) -> void:
	_broken[i] = 1
	var mi: MeshInstance3D = _pieces[i]
	mi.visible = false
	var parts: Array[Mesh] = []
	var centres := PackedVector3Array()
	_split(mi, parts, centres)
	if parts.is_empty():
		return
	var debris := FallenProp.new()
	add_child(debris)
	debris.scatter(parts, centres, _material, direction, _boxes[i].position.y, i, data)


## The piece's mesh split into its connected solids (vertices at the same place count as
## joined), grouped by place into at most data.debris_max_parts parts. Each part's mesh is
## centred on its own middle (world `centres`), so it spins round itself.
func _split(mi: MeshInstance3D, parts: Array[Mesh], centres: PackedVector3Array) -> void:
	var xf: Transform3D = mi.global_transform
	var verts := PackedVector3Array()
	var colours := PackedColorArray()
	var tris := PackedInt32Array()
	for s: int in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var c: Variant = arrays[Mesh.ARRAY_COLOR]
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var base: int = verts.size()
		for k: int in v.size():
			verts.append(xf * v[k])
			colours.append((c as PackedColorArray)[k] if c != null and (c as PackedColorArray).size() == v.size()
					else Color.WHITE)
		if idx != null and (idx as PackedInt32Array).size() > 0:
			for k: int in (idx as PackedInt32Array):
				tris.append(base + k)
		else:
			for k: int in v.size():
				tris.append(base + k)
	if tris.size() < 3:
		return
	# union-find over triangles and shared positions
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for k: int in verts.size():
		parent[k] = k
	var at_place: Dictionary = {}
	for k: int in verts.size():
		var key := Vector3i((verts[k] * 200.0).round())
		if at_place.has(key):
			_union(parent, k, at_place[key])
		else:
			at_place[key] = k
	for t: int in range(0, tris.size() - 2, 3):
		_union(parent, tris[t], tris[t + 1])
		_union(parent, tris[t], tris[t + 2])
	# solids -> their middle
	var solid_of: Dictionary = {}   # root -> solid index
	var solid_sum: Array[Vector3] = []
	var solid_n := PackedInt32Array()
	var vert_solid := PackedInt32Array()
	vert_solid.resize(verts.size())
	for k: int in verts.size():
		var r: int = _find(parent, k)
		if not solid_of.has(r):
			solid_of[r] = solid_sum.size()
			solid_sum.append(Vector3.ZERO)
			solid_n.append(0)
		var si: int = solid_of[r]
		vert_solid[k] = si
		solid_sum[si] += verts[k]
		solid_n[si] += 1
	# group solids by place until few enough
	var group_of := PackedInt32Array()
	group_of.resize(solid_sum.size())
	var cell: float = 0.4
	var groups: int = 0
	while true:
		var keys: Dictionary = {}
		for si: int in solid_sum.size():
			var mid: Vector3 = solid_sum[si] / float(solid_n[si])
			var key := Vector3i((mid / cell).floor())
			if not keys.has(key):
				keys[key] = keys.size()
			group_of[si] = keys[key]
		groups = keys.size()
		if groups <= data.debris_max_parts or cell > 50.0:
			break
		cell *= 1.5
	# one mesh per group, centred
	var tools: Array[SurfaceTool] = []
	var sums: Array[Vector3] = []
	var counts := PackedInt32Array()
	for g: int in groups:
		sums.append(Vector3.ZERO)
		counts.append(0)
	for k: int in verts.size():
		var g: int = group_of[vert_solid[k]]
		sums[g] += verts[k]
		counts[g] += 1
	for g: int in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
		centres.append(sums[g] / float(maxi(counts[g], 1)))
	for t: int in range(0, tris.size() - 2, 3):
		var g: int = group_of[vert_solid[tris[t]]]
		for k: int in 3:
			var vi: int = tris[t + k]
			tools[g].set_color(colours[vi])
			tools[g].add_vertex(verts[vi] - centres[g])
	for g: int in groups:
		tools[g].generate_normals()
		parts.append(tools[g].commit())


func _find(parent: PackedInt32Array, k: int) -> int:
	while parent[k] != k:
		parent[k] = parent[parent[k]]
		k = parent[k]
	return k


func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra != rb:
		parent[ra] = rb


# --- Reset --------------------------------------------------------------------------

## Everything stands again (ThunderRoad's map reset).
func restore_all() -> void:
	for child: Node in get_children():
		if child is FallenProp:
			child.queue_free()
	for i: int in _down.size():
		if _down[i] != 0:
			_down[i] = 0
			_multimesh[i].set_instance_transform(_slot[i], _xform[i])
	for i: int in _spans.size():
		_spans[i].visible = true
		_spans[i].global_transform = _span_xform[i]
	for i: int in _broken.size():
		if _broken[i] != 0:
			_broken[i] = 0
			_pieces[i].visible = true
