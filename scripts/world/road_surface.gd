class_name RoadSurface
extends RefCounted
## Height of the visible road surface. Road meshes from the geodata pipeline (glb group
## `Vagar`) lie 0.04-0.2 m above the terrain and have no collision, so ground rays hit
## the terrain under the asphalt. Things laid on the ground that must be seen (mines)
## ask here. Reads the meshes' triangles (cached per mesh on first use, dropped when the
## mesh is gone), so call it for rare events, not every frame.

## Road mesh nodes: the node or one of its parents is named like this.
const GROUP_PREFIX: String = "Vagar"
## A road surface is only taken this far above / below the ground hit (m), so a road
## on a bridge doesn't lift a mine in the underpass below it.
const MAX_ABOVE_M: float = 0.6
const MAX_BELOW_M: float = 0.3

## Road meshes found by the last call: [global AABB, MeshInstance3D].
static var _meshes: Array = []
## MeshInstance3D instance id -> PackedVector3Array of global triangle corners.
static var _faces: Dictionary = {}


## `ground` with its height raised to the road surface if a road mesh covers that point
## close above (or slightly below) it; else `ground` unchanged.
static func on_road(tree: SceneTree, ground: Vector3) -> Vector3:
	_index(tree)
	var best: float = -INF
	var from := Vector3(ground.x, ground.y + MAX_ABOVE_M, ground.z)
	var dir := Vector3.DOWN
	for entry: Array in _meshes:
		var aabb: AABB = entry[0]
		if ground.x < aabb.position.x or ground.x > aabb.end.x \
				or ground.z < aabb.position.z or ground.z > aabb.end.z \
				or ground.y + MAX_ABOVE_M < aabb.position.y or ground.y - MAX_BELOW_M > aabb.end.y:
			continue
		var mi: MeshInstance3D = entry[1]
		if not is_instance_valid(mi):
			continue
		var faces: PackedVector3Array = _faces_of(mi)
		for i: int in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, faces[i], faces[i + 1], faces[i + 2])
			if hit != null:
				var y: float = (hit as Vector3).y
				if y >= ground.y - MAX_BELOW_M and y > best:
					best = y
	if best == -INF:
		return ground
	return Vector3(ground.x, best, ground.z)


## Road meshes are looked up anew per call (mines are rare, and maps come and go).
static func _index(tree: SceneTree) -> void:
	_meshes.clear()
	var seen: Dictionary = {}
	for node: Node in tree.root.find_children(GROUP_PREFIX + "*", "", true, false):
		var all: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
		if node is MeshInstance3D:
			all.append(node)
		for n: Node in all:
			var mi := n as MeshInstance3D
			if mi.mesh == null or seen.has(mi.get_instance_id()):
				continue
			seen[mi.get_instance_id()] = true
			_meshes.append([mi.global_transform * mi.get_aabb(), mi])
	for key: int in _faces.keys():
		if not seen.has(key):
			_faces.erase(key)


static func _faces_of(mi: MeshInstance3D) -> PackedVector3Array:
	var key: int = mi.get_instance_id()
	if _faces.has(key):
		return _faces[key]
	var local: PackedVector3Array = mi.mesh.get_faces()
	var xf: Transform3D = mi.global_transform
	var out := PackedVector3Array()
	out.resize(local.size())
	for i: int in local.size():
		out[i] = xf * local[i]
	_faces[key] = out
	return out
