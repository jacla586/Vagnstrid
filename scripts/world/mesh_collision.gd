extends Node3D
## Gives imported map meshes static trimesh collision on the world layer at load.
## Put it on the root of an instanced glb (e.g. the Vikbolandet object glb). Only
## direct children whose names start with one of the prefixes are processed, with
## all MeshInstance3D nodes below them.

@export var collision_prefixes: PackedStringArray = ["Byggnader"]


func _ready() -> void:
	var count: int = 0
	for group: Node in get_children():
		if not _matches(group.name):
			continue
		for mesh: Node in group.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).create_trimesh_collision()
			count += 1
	print_verbose("mesh_collision: %d meshes on %s" % [count, name])


func _matches(node_name: String) -> bool:
	for prefix: String in collision_prefixes:
		if node_name.begins_with(prefix):
			return true
	return false
