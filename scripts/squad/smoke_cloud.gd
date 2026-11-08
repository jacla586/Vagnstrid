class_name SmokeCloud
extends Node3D
## A smoke screen (a squad's smoke grenades): grows to `radius_m`, hangs for
## `lifetime_s` and thins out at the end. Blocks sight like bushes do (an area on the
## vision_blocker layer, so Vision and Concealment see it); shells fly through.
## Drifts with the wind (`WeatherData.smoke_drift_share`), following the ground, and
## stretches downwind (puffs drift at slightly different speeds). Host and clients
## drift by the same rule, so no positions are sent.

## Every cloud is in this group (a new round clears them).
const GROUP: StringName = &"smoke_clouds"
## How often the ground under the cloud is probed (s) and how fast it settles to it (m/s).
const GROUND_PROBE_S: float = 0.5
const GROUND_FOLLOW_MPS: float = 3.0
## Puffs stretch downwind for at most this long (s), so the cloud doesn't fall apart.
const STRETCH_MAX_S: float = 15.0

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
var _stretch: Array[float] = []  # per puff: drift speed minus the cloud's, as a share
var _drift: Vector3 = Vector3.ZERO  # m/s
var _ground_timer: float = 0.0
var _ground_y: float = NAN
var _material: StandardMaterial3D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved in _process
	_rng.randomize()
	_drift = Weather.wind() * Weather.current().smoke_drift_share
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
		_stretch.append(_rng.randf_range(-0.25, 0.25))
		add_child(puff)
		_puffs.append(puff)
	_apply(0.0)


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime_s:
		queue_free()
		return
	_move(delta)
	_apply(_age)


func _move(delta: float) -> void:
	if _drift == Vector3.ZERO:
		return
	var p: Vector3 = global_position + _drift * delta
	_ground_timer -= delta
	if _ground_timer <= 0.0:
		_ground_timer = GROUND_PROBE_S
		_ground_y = _probe_ground(p)
	if not is_nan(_ground_y):
		p.y = move_toward(p.y, _ground_y, GROUND_FOLLOW_MPS * delta)
	global_position = p


## Ground height under `p` (terrain, houses, rocks; not trees or tanks), NAN if none.
func _probe_ground(p: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20.0, p + Vector3.DOWN * 40.0, 1)
	var exclude: Array[RID] = []
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for i: int in 4:
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return NAN
		var collider: Object = hit["collider"]
		if collider is TreeField or collider is Tank:
			exclude.append(hit["rid"])
			continue
		return (hit["position"] as Vector3).y
	return NAN


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
	var stretch: Vector3 = _drift * minf(age, STRETCH_MAX_S)
	for i: int in _puffs.size():
		var o: Vector3 = _offsets[i]
		_puffs[i].scale = Vector3.ONE * r * 0.75
		_puffs[i].position = Vector3(o.x * r, o.y * height_m * grow, o.z * r) + stretch * _stretch[i]
