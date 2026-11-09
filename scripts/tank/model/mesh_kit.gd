class_name MeshKit
extends RefCounted
## Builds low-poly, flat-shaded meshes out of convex solids, a little like OpenSCAD:
## blocks cut by planes (sloped armour plates), cylinders (wheels, barrels) and
## extruded profiles (track runs). Every solid goes into one surface per material, and
## its corners can be collected into named point groups for convex collision shapes.
## `xform` places what is added next (e.g. inside a turret frame).

## MARK: UN-blue friend markings (enemies get them in camouflage, see TeamLook).
## SKIN: the commander's face and hands (CommanderModel). CANVAS: tarps and packs.
enum Mat { PAINT, TRACK, WHEEL, DARK, DETAIL, MARK, SKIN, CANVAS }

const EPS: float = 0.0005

static var _materials: Dictionary = {}

var xform: Transform3D = Transform3D.IDENTITY
## Set while adding a wheel: (centre y, centre z, 1/radius, 1) goes into every vertex's
## CUSTOM0, so tank_wheel.gdshader can turn it. Zero = doesn't turn.
var spin: Vector4 = Vector4.ZERO
var _verts: Dictionary = {}    # Mat -> PackedVector3Array
var _normals: Dictionary = {}  # Mat -> PackedVector3Array
var _groups: Dictionary = {}   # group name -> PackedVector3Array
var _customs: Dictionary = {}  # Mat -> PackedFloat32Array (4 per vertex), see `spin`
var _spun: Dictionary = {}     # Mat -> true once a spinning solid used it


## The shared materials. PAINT is the one a team colour replaces. WHEEL turns
## (tank_wheel.gdshader) and TRACK shows moving links (tank_track.gdshader).
static func material(m: Mat) -> Material:
	if _materials.is_empty():
		_materials[Mat.PAINT] = _mat(Color(0.36, 0.4, 0.27), 0.85)
		_materials[Mat.TRACK] = _shader_mat(preload("res://assets/shaders/tank_track.gdshader"))
		_materials[Mat.WHEEL] = _shader_mat(preload("res://assets/shaders/tank_wheel.gdshader"))
		_materials[Mat.DARK] = _mat(Color(0.08, 0.08, 0.08), 0.6)
		_materials[Mat.DETAIL] = _mat(Color(0.28, 0.31, 0.21), 0.9)
		_materials[Mat.MARK] = _mat(Color(0.29, 0.57, 0.86), 0.6)
		_materials[Mat.SKIN] = _mat(Color(0.78, 0.6, 0.48), 0.8)
		_materials[Mat.CANVAS] = _mat(Color(0.42, 0.38, 0.27), 1.0)
	return _materials[m]


static func _shader_mat(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


# --- Solids ---------------------------------------------------------------------------

## A convex solid bounded by `planes` (outward normals; inside where n·p <= d).
func planes_solid(planes: Array[Plane], mat: Mat, group: String = "") -> void:
	var raw: PackedVector3Array = Geometry3D.compute_convex_mesh_points(planes)
	var pts: PackedVector3Array = _dedupe(raw)
	if pts.size() < 4:
		return
	for plane: Plane in planes:
		var face: PackedVector3Array = []
		for p: Vector3 in pts:
			if absf(plane.distance_to(p)) < 0.002:
				face.append(p)
		if face.size() >= 3:
			_polygon(_sorted_around(face, plane.normal), plane.normal, mat)
	_collect(pts, group)


## An axis-aligned block from `lo` to `hi`, cut by extra planes (sloped plates).
## Cuts are given as [point on the plate, outward normal] pairs.
func block(lo: Vector3, hi: Vector3, mat: Mat, cuts: Array = [], group: String = "") -> void:
	var planes: Array[Plane] = [
		Plane(Vector3.RIGHT, hi.x), Plane(Vector3.LEFT, -lo.x),
		Plane(Vector3.UP, hi.y), Plane(Vector3.DOWN, -lo.y),
		Plane(Vector3.BACK, hi.z), Plane(Vector3.FORWARD, -lo.z)]
	for c: Array in cuts:
		var n: Vector3 = (c[1] as Vector3).normalized()
		planes.append(Plane(n, n.dot(c[0])))
	planes_solid(planes, mat, group)


## A box centred on `centre`.
func box(centre: Vector3, size: Vector3, mat: Mat, group: String = "") -> void:
	block(centre - size * 0.5, centre + size * 0.5, mat, [], group)


## A (possibly tapered) cylinder from `a` to `b`, radii `ra` and `rb`.
func cylinder(a: Vector3, b: Vector3, ra: float, rb: float, segments: int, mat: Mat,
		group: String = "", rotate_deg: float = 0.0) -> void:
	var axis: Vector3 = (b - a).normalized()
	var u: Vector3 = axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v: Vector3 = axis.cross(u).normalized()
	var ring_a: PackedVector3Array = []
	var ring_b: PackedVector3Array = []
	for i: int in segments:
		var t: float = TAU * float(i) / float(segments) + deg_to_rad(rotate_deg)
		var d: Vector3 = u * cos(t) + v * sin(t)
		ring_a.append(a + d * ra)
		ring_b.append(b + d * rb)
	loft([ring_a, ring_b], mat, group)


## Rings of equal size joined side by side, the end rings capped. Rings must be convex
## and the solid convex (cylinders, frustums, extruded profiles).
func loft(rings: Array, mat: Mat, group: String = "") -> void:
	var all: PackedVector3Array = []
	for r: PackedVector3Array in rings:
		all.append_array(r)
	var centre: Vector3 = _centroid(all)
	for k: int in rings.size() - 1:
		var r0: PackedVector3Array = rings[k]
		var r1: PackedVector3Array = rings[k + 1]
		var n: int = r0.size()
		for i: int in n:
			var j: int = (i + 1) % n
			var quad: PackedVector3Array = [r0[i], r0[j], r1[j], r1[i]]
			var out: Vector3 = (_centroid(quad) - centre)
			_tri(r0[i], r0[j], r1[j], out, mat)
			_tri(r0[i], r1[j], r1[i], out, mat)
	for end: PackedVector3Array in [rings[0], rings[rings.size() - 1]]:
		var c: Vector3 = _centroid(end)
		var out: Vector3 = c - centre
		for i: int in end.size():
			_tri(c, end[i], end[(i + 1) % end.size()], out, mat)
	_collect(all, group)


## A profile in the side (z, y) plane, extruded across x from `x0` to `x1`.
func extrude_x(profile: PackedVector2Array, x0: float, x1: float, mat: Mat, group: String = "") -> void:
	var r0: PackedVector3Array = []
	var r1: PackedVector3Array = []
	for p: Vector2 in profile:
		r0.append(Vector3(x0, p.y, p.x))
		r1.append(Vector3(x1, p.y, p.x))
	loft([r0, r1], mat, group)


# --- Output ----------------------------------------------------------------------------

func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for m: Mat in [Mat.PAINT, Mat.TRACK, Mat.WHEEL, Mat.DARK, Mat.DETAIL, Mat.MARK, Mat.SKIN, Mat.CANVAS]:
		if not _verts.has(m):
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts[m]
		arrays[Mesh.ARRAY_NORMAL] = _normals[m]
		var flags: int = 0
		if _spun.has(m):
			arrays[Mesh.ARRAY_CUSTOM0] = _customs[m]
			flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material(m))
	return mesh


## Corners of every solid added with `group` (in the kit's space, xform applied).
func points(group: String) -> PackedVector3Array:
	return _groups.get(group, PackedVector3Array())


# --- Internals -------------------------------------------------------------------------

func _polygon(face: PackedVector3Array, out: Vector3, mat: Mat) -> void:
	for i: int in range(1, face.size() - 1):
		_tri(face[0], face[i], face[i + 1], out, mat)


## One triangle, wound so it faces `out` (Godot: clockwise seen from the front).
func _tri(a: Vector3, b: Vector3, c: Vector3, out: Vector3, mat: Mat) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(out) > 0.0:
		var t: Vector3 = b
		b = c
		c = t
		n = -n
	var wa: Vector3 = xform * a
	var wb: Vector3 = xform * b
	var wc: Vector3 = xform * c
	var wn: Vector3 = -(xform.basis * n).normalized()
	# Packed arrays are values: take, append, put back.
	var v: PackedVector3Array = _verts.get(mat, PackedVector3Array())
	var nn: PackedVector3Array = _normals.get(mat, PackedVector3Array())
	v.append_array([wa, wb, wc])
	nn.append_array([wn, wn, wn])
	_verts[mat] = v
	_normals[mat] = nn
	var cu: PackedFloat32Array = _customs.get(mat, PackedFloat32Array())
	for k: int in 3:
		cu.append_array([spin.x, spin.y, spin.z, spin.w])
	_customs[mat] = cu
	if spin.w > 0.0:
		_spun[mat] = true


func _collect(pts: PackedVector3Array, group: String) -> void:
	if group == "":
		return
	if not _groups.has(group):
		_groups[group] = PackedVector3Array()
	var g: PackedVector3Array = _groups[group]
	for p: Vector3 in pts:
		g.append(xform * p)
	_groups[group] = g


static func _dedupe(pts: PackedVector3Array) -> PackedVector3Array:
	var out: PackedVector3Array = []
	for p: Vector3 in pts:
		var seen: bool = false
		for q: Vector3 in out:
			if p.distance_squared_to(q) < EPS * EPS:
				seen = true
				break
		if not seen:
			out.append(p)
	return out


static func _centroid(pts: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p: Vector3 in pts:
		c += p
	return c / maxf(pts.size(), 1)


## Face corners in order round the face normal.
static func _sorted_around(face: PackedVector3Array, normal: Vector3) -> PackedVector3Array:
	var c: Vector3 = _centroid(face)
	var u: Vector3 = (face[0] - c).normalized()
	var v: Vector3 = normal.cross(u).normalized()
	var items: Array = []
	for p: Vector3 in face:
		var d: Vector3 = p - c
		items.append([atan2(d.dot(v), d.dot(u)), p])
	items.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var out: PackedVector3Array = []
	for it: Array in items:
		out.append(it[1])
	return out
