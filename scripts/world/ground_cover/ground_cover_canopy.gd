class_name GroundCoverCanopy
extends Node3D
## The far ground vegetation: a flat top at the vegetation's height in its colour where
## grass, crops, reed or scrub stand tall enough to hide a lying man, so to the player's
## eye a far field hides him just as GroundCover's rule hides him from bots, without
## marking where he is. The mesh is baked by the geodata pipeline
## (markvegetation.lager_glb: 4 m cells on the ground, class index in UV.x) into
## assets/maps/<map>/<map>_markvegetation.glb; height and colour per class come from
## data/world/ground_cover.tres through the shader. Pieces near the blade field
## (GroundCoverField), or all of them when the camera is high above the ground, use the
## dithered material (fades in under the outer blades, thins when looked down on);
## the rest the cheap opaque one. Lives in the player rig; cosmetic and local.

const NEAR_SHADER: String = "res://assets/shaders/ground_cover_canopy.gdshader"
const FAR_SHADER: String = "res://assets/shaders/ground_cover_canopy_far.gdshader"
## Pieces closer than the blade radius + this use the dithered material.
const NEAR_MARGIN_M: float = 30.0
## With the camera this high above the ground everything is dithered (thins from above).
const HIGH_CAMERA_M: float = 8.0
const UPDATE_EVERY_FRAMES: int = 10

var _gc: GroundCover
var _tried: bool = false
var _pieces: Array[MeshInstance3D] = []
var _boxes: Array[AABB] = []
var _near_mat: ShaderMaterial
var _far_mat: ShaderMaterial


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY   # the baked mesh is in world coordinates
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(_delta: float) -> void:
	if _gc == null:
		if _tried:
			return
		_tried = true
		_gc = GroundCover.of(self)
		if _gc == null or not _load():
			set_process(false)
			return
	if Engine.get_process_frames() % UPDATE_EVERY_FRAMES != 0:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var p: Vector3 = cam.global_position
	var ground: float = _gc.ground_y(p.x, p.z)
	var high: bool = not is_nan(ground) and p.y - ground > HIGH_CAMERA_M
	var near_r: float = _gc.rules.draw_radius_m + NEAR_MARGIN_M
	for i: int in _pieces.size():
		var b: AABB = _boxes[i]
		var q := Vector3(clampf(p.x, b.position.x, b.end.x), p.y, clampf(p.z, b.position.z, b.end.z))
		var mat: ShaderMaterial = _near_mat if high or q.distance_to(p) < near_r else _far_mat
		if _pieces[i].material_override != mat:
			_pieces[i].material_override = mat


func _load() -> bool:
	var dir: String = String(_gc.terrain.get("data_directory")) if _gc.terrain != null else ""
	var map_name: String = dir.get_file()
	var path: String = "res://assets/maps/%s/%s_markvegetation.glb" % [map_name, map_name]
	if map_name.is_empty() or not ResourceLoader.exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	var root: Node = scene.instantiate()
	add_child(root)
	var heights := PackedFloat32Array()
	var colors := PackedVector3Array()
	for i: int in 8:
		var k: GroundCoverClassData = _gc.rules.classes[i] if i < _gc.rules.classes.size() else null
		heights.append(k.height_m if k != null else 0.0)
		# the blades' colour seen from afar: mostly tips, a little shadow between them
		var c: Color = (k.color_a.lerp(k.color_b, 0.4) * 0.85).srgb_to_linear() if k != null else Color.BLACK
		colors.append(Vector3(c.r, c.g, c.b))
	_near_mat = _material(NEAR_SHADER, heights, colors)
	_near_mat.set_shader_parameter("fade_in_start", _gc.rules.draw_radius_m - _gc.rules.fade_m - 3.0)
	_near_mat.set_shader_parameter("fade_in_end", _gc.rules.draw_radius_m - _gc.rules.fade_m)
	_near_mat.set_shader_parameter("grazing_full_deg", _gc.rules.grazing_full_deg)
	_near_mat.set_shader_parameter("grazing_none_deg", _gc.rules.grazing_none_deg)
	_far_mat = _material(FAR_SHADER, heights, colors)
	for mi: Node in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		m.material_override = _far_mat
		# room for the class heights the shader adds
		m.extra_cull_margin = 1.5
		_pieces.append(m)
		_boxes.append(m.global_transform * m.get_aabb())
	return not _pieces.is_empty()


func _material(shader_path: String, heights: PackedFloat32Array, colors: PackedVector3Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	m.set_shader_parameter("class_height", heights)
	m.set_shader_parameter("class_color", colors)
	return m
