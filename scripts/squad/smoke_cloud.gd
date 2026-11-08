class_name SmokeCloud
extends Node3D
## A smoke screen (a squad's smoke grenades): grows to `radius_m`, hangs for
## `lifetime_s` and thins out at the end. Blocks sight like bushes do (an area on the
## vision_blocker layer, so Vision and Concealment see it); shells fly through.

## Every cloud is in this group (a new round clears them).
const GROUP: StringName = &"smoke_clouds"

var radius_m: float = 9.0
var height_m: float = 7.0
var lifetime_s: float = 30.0
var grow_s: float = 3.0
var fade_s: float = 6.0

var _age: float = 0.0
var _area: Area3D
var _shape: CylinderShape3D
var _puffs: Array[MeshInstance3D] = []
var _offsets: Array[Vector3] = []  # per puff: (x, z) share of the radius, y share of the height
var _material: StandardMaterial3D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved in _process
	_rng.randomize()
	_area = Area3D.new()
	_area.collision_layer = Vision.LAYER_VISION_BLOCKER
	_area.collision_mask = 0
	_area.monitoring = false
	_shape = CylinderShape3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	_area.add_child(cs)
	add_child(_area)
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(0.78, 0.78, 0.76, 0.85)
	_material.roughness = 1.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i: int in 9:
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		puff.mesh = sphere
		puff.material_override = _material
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_offsets.append(Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.2, 0.7),
				_rng.randf_range(-0.6, 0.6)))
		add_child(puff)
		_puffs.append(puff)
	_apply(0.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime_s:
		queue_free()
		return
	_apply(_age)


func _apply(age: float) -> void:
	var grow: float = clampf(age / maxf(grow_s, 0.01), 0.05, 1.0)
	var fade: float = clampf((lifetime_s - age) / maxf(fade_s, 0.01), 0.0, 1.0)
	var r: float = radius_m * grow * lerpf(0.6, 1.0, fade)
	_shape.radius = r
	_shape.height = height_m * grow
	(_area.get_child(0) as Node3D).position = Vector3(0.0, _shape.height * 0.5, 0.0)
	# Thin smoke stops blocking sight before it has quite gone.
	_area.collision_layer = Vision.LAYER_VISION_BLOCKER if fade > 0.3 else 0
	_material.albedo_color.a = 0.85 * fade
	for i: int in _puffs.size():
		var o: Vector3 = _offsets[i]
		_puffs[i].scale = Vector3.ONE * r * 0.75
		_puffs[i].position = Vector3(o.x * r, o.y * height_m * grow, o.z * r)
