extends SceneTree
## Counts a map scene's glb groups as the game's scripts find them (RoadLook/RoadSurface "Vagar*",
## PropBreak "Valtbart", collision groups): checks a split object glb (geodata dela_glb.py) still has
## every group. Headless:
##   godot --headless --path . --script res://tools/check_map_groups.gd -- <map>

var _scene: Node
var _frames: int = 0


func _initialize() -> void:
	var map: String = OS.get_cmdline_user_args()[0]
	_scene = (load("res://scenes/maps/%s.tscn" % map) as PackedScene).instantiate()
	get_root().add_child(_scene)
	current_scene = _scene
	process_frame.connect(_frame)


func _frame() -> void:
	_frames += 1
	if _frames < 3:
		return
	var roads: Array[Node] = _scene.find_children("Vagar*", "MeshInstance3D", true, false)
	var tris: int = 0
	for n: Node in roads:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for s: int in mesh.get_surface_count():
			tris += mesh.surface_get_array_index_len(s) / 3
	print("GROUPS road meshes (Vagar*): %d, %d triangles" % [roads.size(), tris])
	for prefix: String in ["Byggnader", "Broar", "Valtbart", "Stenlaggning", "Konst", "Kollision"]:
		var groups: Array[Node] = _scene.find_children(prefix + "*", "", true, false)
		print("GROUPS %s: %d nodes" % [prefix, groups.size()])
	var bodies: Array[Node] = _scene.find_children("*", "StaticBody3D", true, false)
	print("GROUPS static bodies: %d" % bodies.size())
	quit()
