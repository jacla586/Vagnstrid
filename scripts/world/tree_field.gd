@tool
class_name TreeField
extends Node3D
## The laser-derived trees of a real map: drawn as MultiMeshInstance3D cells, with
## trunks and crowns that work like BreakableTree (tree.tscn) in game.
##
## Drawing: each chunk is split into draw cells of draw_cell_m. The tree meshes carry
## detail levels (ImporterMesh LODs made at load), and Godot's mesh LOD picks one per cell
## by the error it would show on screen (rendering/mesh_lod threshold, in pixels), so a
## zoomed view (binoculars, gunner's sight) keeps full detail and trunks only thin out
## when they are below a pixel.
##
## Data comes from geodata/scripts/step4_trees.py: trees.bin holds a ready MultiMesh
## transform (12 floats) per tree, relative to its chunk centre, sorted by chunk and
## type; trees_info.json lists the chunks as [type, centre_x, centre_z, first, count].
## The tree models have height 1 and crown radius 1, so a tree's height and crown
## radius are the lengths of its basis' y and x columns.
##
## In game (not in the editor): trunks on layer "world" stop tanks and shells, crowns
## on "vision_blocker" block sight only (FieldTreePhysics). Tanks push thin trees over
## (TreePush, same rule as BreakableTree), main-gun shells snap them. Felled trees fall
## (FallingTree), lose the trunk collider and keep a lying crown (low cover).
## Runs in the editor too (@tool) to show the trees; the chunks are internal children
## without owner, so they are never saved into the scene file.

## Emitted once when a tree starts to fall (sound, effects, network sync later).
signal tree_felled(at: Vector3, direction: Vector3)
## Same event with the tree's index (the net code sends it to clients).
signal tree_index_felled(tree: int, direction: Vector3)

## Same reach as the push trigger in tree.tscn: trigger radius 0.9 m minus trunk 0.25 m.
const PUSH_REACH_M: float = 0.65
## A shell hit belongs to the nearest trunk within this distance of its axis (m).
const SHELL_HIT_SEARCH_M: float = 1.0
const SNAP_MIN_CALIBER_MM: float = 20.0
## Cell size of the lookup grid for trees near a point (m). Small, so a tank only looks at
## the few trees around it instead of every tree in its chunk (thousands, every tick).
const TREE_CELL_M: float = 8.0

@export_file("*.json") var info_path: String = ""
@export_file("*.bin") var data_path: String = ""
## Data per species is loaded as <data_dir>/<data_prefix><species>.tres when the info file
## lists "species" (and the models from its "models", next to the info file).
@export_dir var data_dir: String = "res://data/world"
@export var data_prefix: String = "field_tree_"
## Old info files without "models"/"species": one model and one data per type, in order.
@export var tree_scenes: Array[PackedScene] = []
@export var tree_data: Array[FieldTreeData] = []
## Off: trees are only drawn.
@export var physics_enabled: bool = true
## Chunks further away than this are hidden. Fog hides the pop-in.
@export var visibility_end_m: float = 1500.0
@export var cast_shadows: bool = true
## Side of a draw cell (m): mesh LOD is chosen per cell from its nearest point, so
## smaller cells let far trees in it drop detail sooner, at more draw calls.
@export var draw_cell_m: float = 250.0

var _meshes: Array[Mesh] = []
## Per type: the mesh with detail levels that is drawn.
var _lod_meshes: Array[Mesh] = []
## FieldTreeData per type (several types can share a species).
var _type_data: Array[FieldTreeData] = []
## Per draw cell: its MultiMeshes (one) and centre.
var _cell_multimeshes: Array = []
var _cell_centre: PackedVector3Array = PackedVector3Array()
## Per tree: its draw cell and its index there.
var _draw_cell: PackedInt32Array = PackedInt32Array()
var _draw_index: PackedInt32Array = PackedInt32Array()
var _chunk_type: PackedByteArray = PackedByteArray()
var _chunk_centre: PackedVector3Array = PackedVector3Array()
var _chunk_first: PackedInt32Array = PackedInt32Array()
var _chunk_count: PackedInt32Array = PackedInt32Array()
## Tree indices per TREE_CELL_M grid cell (Vector2i -> PackedInt32Array), for nearby lookups.
var _tree_grid: Dictionary = {}
## Per tree: foot position relative to its chunk centre, size, type, chunk, felled.
var _position: PackedVector3Array = PackedVector3Array()
var _height: PackedFloat32Array = PackedFloat32Array()
var _crown_radius: PackedFloat32Array = PackedFloat32Array()
var _trunk_diameter: PackedFloat32Array = PackedFloat32Array()
var _type: PackedByteArray = PackedByteArray()
var _chunk_of: PackedInt32Array = PackedInt32Array()
var _felled: PackedByteArray = PackedByteArray()
## Felled tree -> its standing MultiMesh transform (to stand it up again, restore_all).
var _felled_drawn: Dictionary = {}
var _physics: FieldTreePhysics = null
var _push_time: Dictionary = {}  # "tank id:tree" -> seconds pushed slowly


func _ready() -> void:
	set_physics_process(false)
	if info_path.is_empty() or data_path.is_empty():
		return
	for old: Node in get_children(true):
		if old is MultiMeshInstance3D:
			old.free()
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(info_path))
	var floats: PackedFloat32Array = FileAccess.get_file_as_bytes(data_path).to_float32_array()
	var per_tree: int = int(info.floats_per_tree)
	_meshes.clear()
	_type_data.clear()
	if info.has("models"):
		for model: String in info.models:
			_meshes.append(_mesh_from(load(info_path.get_base_dir().path_join(model))))
	else:
		for scene: PackedScene in tree_scenes:
			_meshes.append(_mesh_from(scene))
	_lod_meshes.clear()
	for mesh: Mesh in _meshes:
		_lod_meshes.append(_with_detail_levels(mesh))
	if info.has("species"):
		for species: String in info.species:
			_type_data.append(load(data_dir.path_join(data_prefix + species + ".tres")))
	else:
		_type_data.assign(tree_data)
	_build_chunks(info.chunks, floats, per_tree)
	if Engine.is_editor_hint() or not physics_enabled:
		return
	if _type_data.size() < _meshes.size():
		push_error("TreeField: need one FieldTreeData per tree type")
		return
	_read_trees(floats, per_tree)
	_build_tree_grid()
	_build_physics()
	# Only trees with trunks can be pushed over (bushes are just sight blockers).
	set_physics_process(_type_data.any(func(d: FieldTreeData) -> bool: return d.has_trunk))
	print_verbose("tree_field: %d trees in %d chunks, %d draw cells" % [_position.size(),
			_chunk_first.size(), _cell_centre.size()])


func _exit_tree() -> void:
	if _physics != null:
		_physics.free_all()
		_physics = null


## Tanks push over thin trees they drive into or lean on.
func _physics_process(delta: float) -> void:
	if NetRole.is_client():
		return   # the host fells trees and sends them
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank != null:
			_check_tank(tank, delta)


## Called by Shell when it hits a trunk (this node is every trunk's collider).
func on_shell_hit(shell_data: ShellData, point: Vector3, _normal: Vector3,
		velocity: Vector3, _shape: int = -1) -> HitResult:
	var tree: int = _nearest_standing_tree(to_local(point))
	if tree < 0 or shell_data.caliber_mm < SNAP_MIN_CALIBER_MM \
			or _trunk_diameter[tree] > _type_data[_type[tree]].shell_snap_max_diameter_m:
		return null
	fell_tree(tree, velocity)
	var result := HitResult.new()
	result.note = "TREE DOWN"
	result.target = self
	return result


func get_tree_count() -> int:
	return _position.size()


func is_tree_felled(tree: int) -> bool:
	return _felled[tree] != 0


## Global foot position of a tree.
func get_tree_position(tree: int) -> Vector3:
	return to_global(_chunk_centre[_chunk_of[tree]] + _position[tree])


func get_tree_height(tree: int) -> float:
	return _height[tree]


func get_trunk_diameter(tree: int) -> float:
	return _trunk_diameter[tree]


## Fells a tree towards `direction` (horizontal part is used).
func fell_tree(tree: int, direction: Vector3) -> void:
	if _physics == null or _felled[tree] != 0:
		return
	_felled[tree] = 1
	var chunk: int = _chunk_of[tree]
	var shape_index: int = tree - _chunk_first[chunk]
	_physics.disable_trunk(chunk, shape_index)
	var cell: int = _draw_cell[tree]
	var drawn: Transform3D = (_cell_multimeshes[cell][0] as MultiMesh).get_instance_transform(
			_draw_index[tree])
	_felled_drawn[tree] = drawn
	_set_drawn(tree, Transform3D(Basis().scaled(Vector3.ZERO), drawn.origin))
	var falling := FallingTree.new()
	add_child(falling, false, Node.INTERNAL_MODE_BACK)
	falling.position = _cell_centre[cell] + drawn.origin
	falling.setup(_meshes[_type[tree]], drawn.basis, direction, _type_data[_type[tree]],
			cast_shadows)
	var foot: Vector3 = _position[tree]
	falling.landed.connect(func(tilt: Basis) -> void:
		if _physics != null:
			_physics.tip_canopy(chunk, shape_index, tree, foot, tilt))
	tree_felled.emit(get_tree_position(tree), direction)
	tree_index_felled.emit(tree, direction)


## Stands every felled tree up again (a new round on the same map): trunk, crown and
## look as at the start.
func restore_all() -> void:
	for child: Node in get_children(true):
		if child is FallingTree:
			child.free()   # no late "landed" tipping a restored crown
	for tree: int in _felled_drawn:
		var chunk: int = _chunk_of[tree]
		var shape_index: int = tree - _chunk_first[chunk]
		_set_drawn(tree, _felled_drawn[tree])
		if _physics != null:
			_physics.restore(chunk, shape_index, tree)
		_felled[tree] = 0
	_felled_drawn.clear()
	_push_time.clear()


func _build_chunks(chunks: Array, floats: PackedFloat32Array, per_tree: int) -> void:
	_chunk_type.clear()
	_chunk_centre.clear()
	_chunk_first.clear()
	_chunk_count.clear()
	_cell_multimeshes.clear()
	_cell_centre.clear()
	var total: int = floats.size() / per_tree
	_draw_cell.resize(total)
	_draw_index.resize(total)
	for chunk: Array in chunks:
		var type: int = int(chunk[0])
		var first: int = int(chunk[3])
		var count: int = int(chunk[4])
		var centre := Vector3(float(chunk[1]), 0.0, float(chunk[2]))
		_chunk_type.append(type)
		_chunk_centre.append(centre)
		_chunk_first.append(first)
		_chunk_count.append(count)
		# Trees of the chunk by draw cell (foot position relative to the chunk centre).
		var groups: Dictionary = {}
		for i: int in range(first, first + count):
			var o: int = i * per_tree
			var key := Vector2i(floori(floats[o + 3] / draw_cell_m), floori(floats[o + 11] / draw_cell_m))
			# Packed arrays are values: take it out, add, put it back.
			var list: PackedInt32Array = groups.get(key, PackedInt32Array())
			list.append(i)
			groups[key] = list
		for key: Vector2i in groups:
			_build_cell(type, centre, groups[key], floats, per_tree)


## One draw cell: its trees' transforms moved to the cell centre, in a MultiMesh per
## detail level (and a shadow-only one for the near level).
func _build_cell(type: int, chunk_centre: Vector3, trees: PackedInt32Array,
		floats: PackedFloat32Array, per_tree: int) -> void:
	var cell: int = _cell_centre.size()
	var offset := Vector3.ZERO
	for i: int in trees:
		offset += Vector3(floats[i * per_tree + 3], 0.0, floats[i * per_tree + 11])
	offset = (offset / trees.size()).snapped(Vector3.ONE)
	var buffer := PackedFloat32Array()
	buffer.resize(trees.size() * per_tree)
	for k: int in trees.size():
		var o: int = trees[k] * per_tree
		for f: int in per_tree:
			buffer[k * per_tree + f] = floats[o + f]
		buffer[k * per_tree + 3] -= offset.x
		buffer[k * per_tree + 11] -= offset.z
		_draw_cell[trees[k]] = cell
		_draw_index[trees[k]] = k
	var shadow: GeometryInstance3D.ShadowCastingSetting = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var multimeshes: Array[MultiMesh] = [_add_cell_instance(_lod_meshes[type], buffer, per_tree,
			chunk_centre + offset, shadow)]
	_cell_multimeshes.append(multimeshes)
	_cell_centre.append(chunk_centre + offset)


func _add_cell_instance(mesh: Mesh, buffer: PackedFloat32Array, per_tree: int, at: Vector3,
		shadow: GeometryInstance3D.ShadowCastingSetting) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	# 16 floats per instance: transform + colour (per-tree tint).
	multimesh.use_colors = per_tree >= 16
	multimesh.mesh = mesh
	multimesh.instance_count = buffer.size() / per_tree
	multimesh.buffer = buffer
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.position = at
	instance.visibility_range_end = visibility_end_m
	instance.visibility_range_end_margin = 50.0
	instance.cast_shadow = shadow
	add_child(instance, false, Node.INTERNAL_MODE_BACK)
	return multimesh


## Sets a tree's drawn transform (relative to its draw cell) in every detail level.
func _set_drawn(tree: int, xform: Transform3D) -> void:
	for multimesh: MultiMesh in _cell_multimeshes[_draw_cell[tree]]:
		multimesh.set_instance_transform(_draw_index[tree], xform)


## The tree model with detail levels for Godot's mesh LOD (merging the model's parts in
## _mesh_from drops the ones the importer made).
func _with_detail_levels(mesh: Mesh) -> Mesh:
	var importer := ImporterMesh.new()
	for surface: int in mesh.get_surface_count():
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface), [], {},
				mesh.surface_get_material(surface))
	importer.generate_lods(25.0, 60.0, [])
	return importer.get_mesh()


## Unpacks size and position of every tree from the MultiMesh transforms.
func _read_trees(floats: PackedFloat32Array, per_tree: int) -> void:
	var total: int = floats.size() / per_tree
	_position.resize(total)
	_height.resize(total)
	_crown_radius.resize(total)
	_trunk_diameter.resize(total)
	_type.resize(total)
	_chunk_of.resize(total)
	_felled.resize(total)
	_felled.fill(0)
	for c: int in _chunk_first.size():
		var type: int = _chunk_type[c]
		var data: FieldTreeData = _type_data[type]
		for i: int in range(_chunk_first[c], _chunk_first[c] + _chunk_count[c]):
			var o: int = i * per_tree
			# Row-major 3x4: column x = (o, o+4, o+8), column y = (o+1, o+5, o+9).
			var h: float = Vector3(floats[o + 1], floats[o + 5], floats[o + 9]).length()
			_position[i] = Vector3(floats[o + 3], floats[o + 7], floats[o + 11])
			_height[i] = h
			_crown_radius[i] = Vector3(floats[o], floats[o + 4], floats[o + 8]).length()
			_trunk_diameter[i] = data.trunk_diameter_for(h)
			_type[i] = type
			_chunk_of[i] = c


func _build_physics() -> void:
	var origins: Array[Transform3D] = []
	for centre: Vector3 in _chunk_centre:
		origins.append(global_transform * Transform3D(Basis(), centre))
	_physics = FieldTreePhysics.new()
	_physics.build(get_world_3d().space, get_instance_id(), origins, _chunk_first, _chunk_count,
			_position, _height, _crown_radius, _trunk_diameter, _type_data, _type)


## Checks the standing trees around the tank's hull with the push rule.
func _check_tank(tank: Tank, delta: float) -> void:
	var half: Vector3 = tank.get_hull_half_extents()
	var reach: float = Vector2(half.x, half.z).length() + PUSH_REACH_M + 0.5
	var to_tank: Transform3D = tank.global_transform.affine_inverse()
	var centre: Vector3 = to_local(tank.global_position)
	for i: int in _trees_near(centre, reach):
		if _felled[i] != 0:
			continue
		var p: Vector3 = _chunk_centre[_chunk_of[i]] + _position[i]
		if Vector2(p.x - centre.x, p.z - centre.z).length_squared() > reach * reach:
			continue
		var tree_global: Vector3 = to_global(p)
		var local: Vector3 = to_tank * tree_global
		var dx: float = maxf(absf(local.x) - half.x, 0.0)
		var dz: float = maxf(absf(local.z) - half.z, 0.0)
		if sqrt(dx * dx + dz * dz) - _trunk_diameter[i] * 0.5 > PUSH_REACH_M:
			continue
		var key: String = "%d:%d" % [tank.get_instance_id(), i]
		var direction: Vector3 = TreePush.push_direction(tank, tree_global,
				_trunk_diameter[i], delta, _push_time, key)
		if direction != Vector3.ZERO:
			fell_tree(i, direction)


## Standing tree whose trunk axis is nearest to `point` (TreeField space), or -1.
func _nearest_standing_tree(point: Vector3) -> int:
	var best: int = -1
	var best_distance: float = INF
	for i: int in _trees_near(point, SHELL_HIT_SEARCH_M + 1.0):
		if _felled[i] != 0:
			continue
		var p: Vector3 = _chunk_centre[_chunk_of[i]] + _position[i]
		var distance: float = Vector2(p.x - point.x, p.z - point.z).length() \
				- _trunk_diameter[i] * 0.5
		if distance < best_distance:
			best = i
			best_distance = distance
	return best if best_distance <= SHELL_HIT_SEARCH_M else -1


## Trees whose grid cell lies within `radius` of `point` (TreeField space).
func _trees_near(point: Vector3, radius: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	var low: Vector2i = _cell_of(point - Vector3(radius, 0.0, radius))
	var high: Vector2i = _cell_of(point + Vector3(radius, 0.0, radius))
	for x: int in range(low.x, high.x + 1):
		for z: int in range(low.y, high.y + 1):
			var cell := Vector2i(x, z)
			if _tree_grid.has(cell):
				result.append_array(_tree_grid[cell])
	return result


## Puts every tree in its TREE_CELL_M cell (after _read_trees).
func _build_tree_grid() -> void:
	_tree_grid.clear()
	for i: int in _position.size():
		var cell: Vector2i = _cell_of(_chunk_centre[_chunk_of[i]] + _position[i])
		var list: PackedInt32Array = _tree_grid.get(cell, PackedInt32Array())
		list.append(i)
		_tree_grid[cell] = list


func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / TREE_CELL_M), floori(point.z / TREE_CELL_M))


## Turns an imported model (glb) into one mesh: all MeshInstance3D parts are merged with
## their transforms. Surfaces without a texture get a vertex-colour material; textured ones
## (CC0 packs) keep theirs. Either way the material takes the per-instance colour.
func _mesh_from(scene: PackedScene) -> Mesh:
	var root: Node = scene.instantiate()
	var out := ArrayMesh.new()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var relative: Transform3D = Transform3D.IDENTITY
		var walker: Node = part
		while walker != root and walker is Node3D:
			relative = (walker as Node3D).transform * relative
			walker = walker.get_parent()
		for surface: int in part.mesh.get_surface_count():
			var tool := SurfaceTool.new()
			tool.append_from(part.mesh, surface, relative)
			tool.index()   # indexed, so detail levels can be made from it
			tool.commit(out)
			var source: Material = part.get_active_material(surface)
			out.surface_set_material(out.get_surface_count() - 1, _material_for(source))
	root.free()
	return out


func _material_for(source: Material) -> Material:
	var textured := source as BaseMaterial3D
	if textured != null and textured.albedo_texture != null:
		var copy := textured.duplicate() as BaseMaterial3D
		copy.vertex_color_use_as_albedo = true   # instance colour tints it
		return copy
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	return material
