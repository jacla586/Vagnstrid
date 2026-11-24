extends SceneTree
## Tactical-grid flags, ground height and lake water depth at points of a map (why do bots stall here?).
##   godot --headless --path . --script res://tools/ai/grid_probe.gd -- <map scene> x,z [x,z ...] [line=x0,z0:x1,z1:n]
## line= samples n points from (x0, z0) to (x1, z1).

var _points: Array[Vector2] = []
var _scene: Node
var _frames: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = "res://scenes/maps/%s.tscn" % args[0]
	for a: String in args.slice(1):
		if a.begins_with("line="):
			var parts: PackedStringArray = a.substr(5).split(":")
			var p0: PackedFloat64Array = parts[0].split_floats(",")
			var p1: PackedFloat64Array = parts[1].split_floats(",")
			var n: int = int(parts[2])
			for i: int in n:
				var t: float = float(i) / maxf(n - 1, 1)
				_points.append(Vector2(lerpf(p0[0], p1[0], t), lerpf(p0[1], p1[1], t)))
		else:
			var v: PackedFloat64Array = a.split_floats(",")
			_points.append(Vector2(v[0], v[1]))
	_scene = (load(path) as PackedScene).instantiate()
	get_root().add_child(_scene)
	current_scene = _scene
	process_frame.connect(_frame)


func _frame() -> void:
	_frames += 1
	if _frames < 5:
		return
	var map: TacticalMap = TacticalMap.for_scene(_scene)
	var gc: GroundCover = GroundCover.of(_scene)
	var names: Dictionary = {1: "BLOCKED", 2: "concealed", 4: "forest", 8: "ROAD", 16: "wet", 32: "WATER",
			64: "HOUSE", 128: "STEEP", 256: "near", 512: "thick"}
	for p: Vector2 in _points:
		var pos := Vector3(p.x, 0.0, p.y)
		var g: float = gc.ground_y(p.x, p.y) if gc != null else NAN
		var flags: int = map.grid.flags_at(map.grid.cell_of(pos)) if map != null else -1
		var list: Array[String] = []
		for bit: int in names:
			if flags & bit:
				list.append(names[bit])
		var hits: Array[String] = []
		var space: PhysicsDirectSpaceState3D = _scene.get_viewport().get_world_3d().direct_space_state
		var from := Vector3(p.x, g + 40.0, p.y)
		var exclude: Array[RID] = []
		for k: int in 4:
			var q := PhysicsRayQueryParameters3D.create(from, Vector3(p.x, g - 2.0, p.y), 1, exclude)
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty():
				break
			var col: Object = hit["collider"]
			hits.append("%s@%.2f" % [(col as Node).name if col is Node else str(col), hit["position"].y])
			exclude.append(hit["rid"])
		print("RAYS (%.0f, %.0f): %s" % [p.x, p.y, ", ".join(hits)])
		print("PROBE (%.0f, %.0f) ground=%.2f water=%.2f blocked=%s flags=%s" % [p.x, p.y, g,
				gc.water_depth(Vector3(p.x, g, p.y)) if gc != null else -1.0,
				str(map.is_blocked(pos)) if map != null else "?", ",".join(list)])
	quit()
