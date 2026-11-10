class_name FallenProp
extends Node3D
## Something PropBreak knocked down: a toppling lamp or mast (tips over round its foot,
## the angle growing as t²), a catenary span dropping to the track, or a playground
## piece falling apart (parts thrown off, spinning, until they reach the ground). Lies
## `lie_s`, sinks into the ground and frees itself. Moved in _process (cosmetic).

enum Kind { TOPPLE, DROP, DEBRIS }

const GRAVITY: float = 9.8

var _data: PropBreakData
var _kind: Kind = Kind.TOPPLE
var _time: float = 0.0
var _axis: Vector3 = Vector3.RIGHT
var _drop_m: float = 0.0
var _start: Vector3 = Vector3.ZERO
var _sink_from_y: float = NAN
# debris: per part
var _parts: Array[MeshInstance3D] = []
var _vel: Array[Vector3] = []
var _spin: Array[Vector3] = []
var _rest_y: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## A standing prop (mesh at `xform`, its foot at the origin) tipping towards `direction`.
func topple(mesh: Mesh, xform: Transform3D, direction: Vector3, data: PropBreakData) -> void:
	_data = data
	_kind = Kind.TOPPLE
	position = xform.origin
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() < 0.0001:
		horizontal = Vector3.FORWARD
	_axis = Vector3.UP.cross(horizontal.normalized()).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.basis = xform.basis
	add_child(mi)


## A mesh (world `xform`) dropping `drop_m` straight down.
func drop(mesh: Mesh, xform: Transform3D, drop_m: float, data: PropBreakData) -> void:
	_data = data
	_kind = Kind.DROP
	_drop_m = maxf(drop_m, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	transform = xform
	_start = position


## A piece falling apart: `parts` are meshes with their centres (world) in `centres`;
## they come to rest at `ground_y`.
func scatter(parts: Array[Mesh], centres: PackedVector3Array, material: Material,
		direction: Vector3, ground_y: float, seed_value: int, data: PropBreakData) -> void:
	_data = data
	_kind = Kind.DEBRIS
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var push := Vector3(direction.x, 0.0, direction.z)
	push = push.normalized() if push.length_squared() > 0.0001 else Vector3.FORWARD
	for i: int in parts.size():
		var mi := MeshInstance3D.new()
		mi.mesh = parts[i]
		mi.material_override = material
		mi.position = centres[i]
		add_child(mi)
		_parts.append(mi)
		var side := push.cross(Vector3.UP) * rng.randf_range(-1.2, 1.2)
		_vel.append(push * rng.randf_range(data.debris_push_min_mps, data.debris_push_max_mps)
				+ side + Vector3.UP * rng.randf_range(data.debris_up_min_mps, data.debris_up_max_mps))
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		_spin.append(axis.normalized() * rng.randf_range(0.5, data.debris_spin_max))
		# rests when its centre is this high: half its smallest size above the ground
		var box: AABB = parts[i].get_aabb()
		var thin: float = minf(box.size.x, minf(box.size.y, box.size.z))
		_rest_y.append(maxf(ground_y + thin * 0.5, minf(centres[i].y, ground_y + 0.05)))


func _process(delta: float) -> void:
	_time += delta
	match _kind:
		Kind.TOPPLE:
			var t: float = minf(_time / maxf(_data.fall_time_s, 0.01), 1.0)
			basis = Basis(_axis, deg_to_rad(_data.fallen_angle_deg) * t * t)
		Kind.DROP:
			var t: float = minf(_time / maxf(_data.wire_drop_s, 0.01), 1.0)
			position = _start + Vector3.DOWN * _drop_m * t * t
		Kind.DEBRIS:
			_move_parts(delta)
	var settle: float = _data.fall_time_s if _kind != Kind.DROP else _data.wire_drop_s
	var sinking: float = _time - settle - _data.lie_s
	if sinking > 0.0:
		if is_nan(_sink_from_y):
			_sink_from_y = position.y
		position.y = _sink_from_y - _data.sink_depth_m * minf(sinking / maxf(_data.sink_s, 0.01), 1.0)
		if sinking >= _data.sink_s:
			queue_free()


func _move_parts(delta: float) -> void:
	if _time > _data.fall_time_s + 4.0:
		return   # all down by now
	for i: int in _parts.size():
		if _vel[i] == Vector3.ZERO:
			continue
		var mi: MeshInstance3D = _parts[i]
		_vel[i].y -= GRAVITY * delta
		mi.position += _vel[i] * delta
		mi.rotate(_spin[i].normalized(), _spin[i].length() * delta)
		if mi.position.y <= _rest_y[i] and _vel[i].y < 0.0:
			mi.position.y = _rest_y[i]
			_vel[i] = Vector3.ZERO
