extends SceneTree
## Renders pictures of a map's vegetation for review, without starting the game:
## a model sheet (every tree and bush model at the map's median size per species, beside
## a 1.8 m person), and views from inside and above the densest stand of each species.
## Also prints per-species counts and height/crown percentiles.
##   godot --path . --disable-vsync --script res://tools/render_vegetation.gd -- <map> <out dir>
## Needs a window (not --headless). Reads res://scenes/maps/<map>.tscn and
## res://assets/maps/<map>/{trees,buskar}{.bin,_info.json}.

const SIZE: Vector2i = Vector2i(1400, 800)
## Side of the cells used to find dense stands (m).
const STAND_CELL_M: float = 60.0
## Eye height for the ground views (about a commander in the cupola).
const EYE_M: float = 2.6
const SETTLE_FRAMES: int = 12
const PERSON_M: float = 1.8

var _map: String = ""
var _out: String = ""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <map> <out dir>")
		quit(1)
		return
	_map = args[0]
	_out = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


## One field's trees: species name, world position, height, crown radius, tint per tree.
class Field:
	var models: PackedStringArray
	var species_of_type: PackedStringArray
	var type: PackedInt32Array
	var position: PackedVector3Array
	var height: PackedFloat32Array
	var radius: PackedFloat32Array
	var tint: PackedColorArray


func _load_field(prefix: String) -> Field:
	var dir: String = "res://assets/maps/%s/" % _map
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + prefix + "_info.json"))
	var floats: PackedFloat32Array = FileAccess.get_file_as_bytes(dir + prefix + ".bin").to_float32_array()
	var per: int = int(info.floats_per_tree)
	var f := Field.new()
	for m: Variant in info.models:
		f.models.append(dir + str(m))
	for s: Variant in info.species:
		f.species_of_type.append(str(s))
	for chunk: Array in info.chunks:
		var t: int = int(chunk[0])
		var centre := Vector3(float(chunk[1]), 0.0, float(chunk[2]))
		for i: int in range(int(chunk[3]), int(chunk[3]) + int(chunk[4])):
			var o: int = i * per
			f.type.append(t)
			f.position.append(centre + Vector3(floats[o + 3], floats[o + 7], floats[o + 11]))
			f.height.append(Vector3(floats[o + 1], floats[o + 5], floats[o + 9]).length())
			f.radius.append(Vector3(floats[o], floats[o + 4], floats[o + 8]).length())
			f.tint.append(Color(floats[o + 12], floats[o + 13], floats[o + 14]) if per >= 16 else Color.WHITE)
	return f


func _run() -> void:
	var trees: Field = _load_field("trees")
	var bushes: Field = _load_field("buskar")
	var report: PackedStringArray = []
	var medians: Dictionary = {}  # species -> [height, radius, tint]
	for f: Field in [trees, bushes]:
		_stats(f, report, medians)
	var text: String = "\n".join(report)
	print(text)
	FileAccess.open(_out + "/stats.txt", FileAccess.WRITE).store_string(text + "\n")

	await _model_sheet(trees, bushes, medians)
	await _stand_views(trees)
	print("wrote pictures to %s" % ProjectSettings.globalize_path(_out))
	quit()


# ------------------------------------------------------------------ statistics
func _stats(f: Field, report: PackedStringArray, medians: Dictionary) -> void:
	var by_species: Dictionary = {}
	for i: int in f.type.size():
		var s: String = f.species_of_type[f.type[i]]
		if not by_species.has(s):
			by_species[s] = [[], [], []]
		(by_species[s][0] as Array).append(f.height[i])
		(by_species[s][1] as Array).append(f.radius[i])
		(by_species[s][2] as Array).append(f.tint[i])
	var total: int = f.type.size()
	report.append("%-6s %7s %6s | height m p10/p50/p90 (max) | crown radius m p10/p50/p90"
			% ["", "count", "share"])
	for s: String in by_species:
		var h := PackedFloat32Array(by_species[s][0])
		var r := PackedFloat32Array(by_species[s][1])
		h.sort()
		r.sort()
		var tints: Array = by_species[s][2]
		var mid_tint: Color = tints[tints.size() / 2]
		medians[s] = [_pct(h, 0.5), _pct(r, 0.5), mid_tint]
		report.append("%-6s %7d %5.1f%% | %5.1f %5.1f %5.1f (%5.1f) | %4.1f %4.1f %4.1f" % [s, h.size(),
				100.0 * h.size() / total, _pct(h, 0.1), _pct(h, 0.5), _pct(h, 0.9), h[h.size() - 1],
				_pct(r, 0.1), _pct(r, 0.5), _pct(r, 0.9)])
	report.append("")


func _pct(a: PackedFloat32Array, q: float) -> float:
	return a[clampi(int(q * (a.size() - 1)), 0, a.size() - 1)]


# ------------------------------------------------------------------ model sheet
func _model_sheet(trees: Field, bushes: Field, medians: Dictionary) -> void:
	var vp: SubViewport = _studio()
	var cam: Camera3D = vp.get_node("Camera") as Camera3D
	var groups: Array = [[trees, "trees"], [bushes, "bushes"]]
	for g: Array in groups:
		var f: Field = g[0]
		var holder := Node3D.new()
		vp.add_child(holder)
		var x: float = 0.0
		var widest: float = 0.0
		var tallest: float = 0.0
		var last: String = ""
		for t: int in f.models.size():
			var s: String = f.species_of_type[t]
			var h: float = medians[s][0]
			var r: float = medians[s][1]
			if last != "" and s != last:
				x += 3.0  # gap between species
			last = s
			x += r
			var node := _model(f.models[t], h, r, medians[s][2])
			node.position = Vector3(x, 0.0, 0.0)
			holder.add_child(node)
			x += r + 1.0
			tallest = maxf(tallest, h)
			widest = x
		var person := _person()
		person.position = Vector3(-2.0, 0.0, 1.0)
		holder.add_child(person)
		var mid := Vector3((widest - 3.0) * 0.5, tallest * 0.45, 0.0)
		var dist: float = maxf(widest * 0.95, tallest * 1.7)
		cam.position = mid + Vector3(0.0, tallest * 0.12, dist)
		cam.look_at(mid)
		await _frames(SETTLE_FRAMES)
		_save(vp, "sheet_%s.png" % g[1])
		# Close-up per species (all its variants), still at median size.
		for s: String in medians:
			if not f.species_of_type.has(s):
				continue
			var lo: float = INF
			var hi: float = -INF
			for c: Node in holder.get_children():
				if c.has_meta("species") and c.get_meta("species") == s:
					lo = minf(lo, (c as Node3D).position.x - float(medians[s][1]))
					hi = maxf(hi, (c as Node3D).position.x + float(medians[s][1]))
			var hh: float = medians[s][0]
			var centre := Vector3((lo + hi) * 0.5, hh * 0.5, 0.0)
			var d: float = maxf((hi - lo) * 1.05, hh * 1.6) + 2.0
			person.position = Vector3(lo - 1.0, 0.0, 1.0)
			cam.position = centre + Vector3(0.0, hh * 0.05, d)
			cam.look_at(centre)
			await _frames(SETTLE_FRAMES)
			_save(vp, "model_%s.png" % s)
		holder.free()
	vp.free()


func _studio() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.66, 0.74, 0.82)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.40, 0.44, 0.31)
	plane.material = gm
	ground.mesh = plane
	vp.add_child(ground)
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = 35.0
	cam.far = 2000.0
	vp.add_child(cam)
	cam.current = true
	return vp


## A model as the TreeField draws it: x/z scaled by crown radius, y by height, tinted.
func _model(path: String, height: float, radius: float, tint: Color) -> Node3D:
	var scene: Node = (load(path) as PackedScene).instantiate()
	var holder := Node3D.new()
	holder.set_meta("species", path.get_file().get_basename().trim_prefix("veg_").rsplit("_", true, 1)[0])
	for part: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := part as MeshInstance3D
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		var rel: Transform3D = Transform3D.IDENTITY
		var walker: Node = mi
		while walker != scene and walker is Node3D:
			rel = (walker as Node3D).transform * rel
			walker = walker.get_parent()
		copy.transform = rel
		for i: int in mi.mesh.get_surface_count():
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.albedo_color = tint
			mat.roughness = 1.0
			copy.set_surface_override_material(i, mat)
		holder.add_child(copy)
	scene.free()
	holder.scale = Vector3(radius, height, radius)
	var outer := Node3D.new()
	outer.set_meta("species", holder.get_meta("species"))
	outer.add_child(holder)
	return outer


func _person() -> Node3D:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.25
	cap.height = PERSON_M
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.2, 0.15)
	cap.material = m
	mi.mesh = cap
	mi.position.y = PERSON_M * 0.5
	var n := Node3D.new()
	n.add_child(mi)
	return n


# ------------------------------------------------------------------ stands in the map
func _stand_views(trees: Field) -> void:
	var packed := load("res://scenes/maps/%s.tscn" % _map) as PackedScene
	var scene: Node = packed.instantiate()
	for node: Node in scene.find_children("*", "", true, false):
		if node is Tank or node is CanvasLayer:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			node.set("visible", false)
	root.add_child(scene)
	await _frames(10)
	var terrain: Node = scene.find_children("*", "Terrain3D", true, false)[0]
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 3000.0
	vp.add_child(cam)
	cam.current = true
	terrain.call("set_camera", cam)

	# Densest cell per species (by count of that species, needing it to dominate).
	var cells: Dictionary = {}  # Vector2i -> {species: count, "all": count}
	for i: int in trees.type.size():
		var p: Vector3 = trees.position[i]
		var c := Vector2i(floori(p.x / STAND_CELL_M), floori(p.z / STAND_CELL_M))
		if not cells.has(c):
			cells[c] = {"all": 0}
		var d: Dictionary = cells[c]
		var s: String = trees.species_of_type[trees.type[i]]
		d[s] = int(d.get(s, 0)) + 1
		d["all"] = int(d["all"]) + 1
	var species: PackedStringArray = []
	for s: String in trees.species_of_type:
		if not species.has(s):
			species.append(s)
	var spots: Array = []  # [name, Vector2 centre]
	for s: String in species:
		var best: Vector2i = Vector2i.ZERO
		var best_n: int = -1
		for c: Vector2i in cells:
			var d: Dictionary = cells[c]
			var n: int = int(d.get(s, 0))
			if n > best_n and n * 2 >= int(d["all"]):
				best_n = n
				best = c
		if best_n > 0:
			spots.append([s, (Vector2(best) + Vector2(0.5, 0.5)) * STAND_CELL_M, best_n])
	# Plus the densest mixed cell.
	var dense: Vector2i = Vector2i.ZERO
	var dense_n: int = -1
	for c: Vector2i in cells:
		if int(cells[c]["all"]) > dense_n:
			dense_n = int(cells[c]["all"])
			dense = c
	spots.append(["tatast", (Vector2(dense) + Vector2(0.5, 0.5)) * STAND_CELL_M, dense_n])

	var data: Object = terrain.get("data")
	for spot: Array in spots:
		var name: String = spot[0]
		var c: Vector2 = spot[1]
		print("stand %s at (%.0f, %.0f): %d trees in %.0f m cell" % [name, c.x, c.y, spot[2], STAND_CELL_M])
		var ground: float = float(data.call("get_height", Vector3(c.x, 0.0, c.y)))
		# Inside: eye height, looking north, then east.
		for dir: Array in [["n", Vector3(0, 0, -1)], ["o", Vector3(1, 0, 0)]]:
			cam.position = Vector3(c.x, ground + EYE_M, c.y)
			var ahead: Vector3 = cam.position + (dir[1] as Vector3) * 50.0
			ahead.y = float(data.call("get_height", ahead)) + EYE_M + 2.0
			cam.look_at(ahead)
			await _frames(SETTLE_FRAMES)
			_save(vp, "stand_%s_inne_%s.png" % [name, dir[0]])
		# From the stand's edge: 120 m south, low, looking at it.
		var out := Vector3(c.x, 0.0, c.y + 120.0)
		out.y = float(data.call("get_height", out)) + EYE_M
		cam.position = out
		cam.look_at(Vector3(c.x, ground + 8.0, c.y))
		await _frames(SETTLE_FRAMES)
		_save(vp, "stand_%s_utifran.png" % name)
		# Oblique from above.
		cam.position = Vector3(c.x - 60.0, ground + 90.0, c.y + 110.0)
		cam.look_at(Vector3(c.x, ground, c.y))
		await _frames(SETTLE_FRAMES)
		_save(vp, "stand_%s_ovan.png" % name)
	vp.free()


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _save(vp: SubViewport, file: String) -> void:
	vp.get_texture().get_image().save_png(_out + "/" + file)
