extends Node3D
## Gives imported map meshes static trimesh collision on the world layer at load.
## Put it on the root of an instanced glb (e.g. the Vikbolandet object glb). Only
## direct children whose names start with one of the prefixes are processed, with
## all MeshInstance3D nodes below them.

@export var collision_prefixes: PackedStringArray = ["Byggnader", "Broar", "Stenar", "Banhinder", "Kollision"]
## Groups with these prefixes are collision only: their meshes are hidden (geodata broar.py: thick invisible
## walls along the bridge railings, which themselves have no collision, so tanks slide along instead of
## getting wedged in thin rails).
@export var hidden_prefixes: PackedStringArray = ["Kollision"]


func _ready() -> void:
	var count: int = 0
	for group: Node in get_children():
		if not _matches(group.name):
			continue
		var hide: bool = _matches_any(group.name, hidden_prefixes)
		for mesh: Node in group.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).create_trimesh_collision()
			if hide:
				(mesh as MeshInstance3D).visible = false   # the static body child keeps colliding
			count += 1
	print_verbose("mesh_collision: %d meshes on %s" % [count, name])


func _matches(node_name: String) -> bool:
	return _matches_any(node_name, collision_prefixes)


func _matches_any(node_name: String, prefixes: PackedStringArray) -> bool:
	for prefix: String in prefixes:
		if node_name.begins_with(prefix):
			return true
	return false
