extends SceneTree
## Renders views of a geodata map scene placed by SWEREF coordinates, to check hand-placed details
## (geodata platsdetaljer.py) or anything else against photos. Needs a window (not --headless).
##   godot --path . --disable-vsync --script res://tools/render_spots.gd -- <map> <out dir> \
##       "name:E,N,dy:E,N,dy:fov" ...
## Each view: camera at (E, N) dy m above the terrain, looking at (E, N) dy m above the terrain, field of
## view in degrees. The map's origin comes from geodata/<map>/work/grid.json (x = E - x0 - RES/2,
## z = y1 - RES/2 - N). The map's players and bots are removed; PNGs go to <out dir>/<name>.png.
## With --rig anywhere among the views the map's PlayerRig stays (HUD hidden), so the ground vegetation
## (grass blades, the far canopy) and the weather look are drawn as in the game.

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -- <map> <out dir> \"name:E,N,dy:E,N,dy:fov\" ...")
		quit(1)
		return
	var keep_rig: bool = args.has("--rig")
	if keep_rig:
		args.remove_at(args.find("--rig"))
	var map: String = args[0]
	var grid_path: String = ProjectSettings.globalize_path("res://geodata/%s/work/grid.json" % map)
	var grid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(grid_path))
	if grid.is_empty():
		push_error("no grid: " + grid_path)
		quit(1)
		return
	var res: float = float(grid["RES"])
	var x0: float = float(grid["x0"]) + res / 2.0
	var z0: float = float(grid["y1"]) - res / 2.0
	get_root().size = Vector2i(1280, 720)
	var scene: Node = (load("res://scenes/maps/%s.tscn" % map) as PackedScene).instantiate()
	get_root().add_child(scene)
	current_scene = scene   # the rig's looks (RoadLook, StoneLook) dress current_scene
	for n: Node in scene.find_children("*", "", true, false):
		if n.name.begins_with("Enemy") or (not keep_rig and (n is CharacterBody3D or n is RigidBody3D
				or n.name.begins_with("PlayerRig"))):
			n.queue_free()
	if keep_rig:
		for layer: Node in scene.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
	var terrain: Node = scene.find_children("*", "Terrain3D", true, false)[0]
	var cam := Camera3D.new()
	cam.far = 4000.0
	get_root().add_child(cam)
	cam.current = true
	terrain.call("set_camera", cam)
	for k in 30:
		await process_frame
	for i in range(2, args.size()):
		var p: PackedStringArray = args[i].split(":")
		var a: PackedFloat64Array = p[1].split_floats(",")
		var t: PackedFloat64Array = p[2].split_floats(",")
		var pa := Vector3(a[0] - x0, 0.0, z0 - a[1])
		var pt := Vector3(t[0] - x0, 0.0, z0 - t[1])
		pa.y = terrain.get("data").call("get_height", pa) + a[2]
		pt.y = terrain.get("data").call("get_height", pt) + t[2]
		cam.fov = float(p[3])
		cam.look_at_from_position(pa, pt)
		cam.current = true
		for k in 40:
			await process_frame
		get_root().get_texture().get_image().save_png(args[1] + "/" + p[0] + ".png")
	quit()
