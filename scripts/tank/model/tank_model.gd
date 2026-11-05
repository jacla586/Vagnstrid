class_name TankModel
extends RefCounted
## Builds a tank's look and its armour shapes from its TankData: the model style (from
## the chassis: light/BT-like, sloped medium/T-34-like, boxy medium/Pz IV-like,
## heavy/KV-like), the measures (hull_size, turret radius and height, gun length and
## bore) and looks from the parts (armour package, muzzle brake, turret variant). Only
## loosely inspired by the real tanks.
##
## The same solids give the collision shapes, so sloped plates really are sloped for
## shells (Armour uses the hit normal). Hull frame: origin mid-hull, -Z forward, track
## bottoms at -H/2, hull roof at +H/2. Turret frame: origin on the hull roof at the
## turret ring. Gun frame: the gun pivot, barrel along -Z.
##
## Result (cached per TankData): "hull", "turret", "mantlet", "gun" meshes;
## "turret_pos", "gun_pivot", "cupola", "roof_mg", "muzzle_z", "track_x",
## "turret_top"; "hull_shapes" / "turret_shapes" (point clouds for convex shapes).

const STYLE_LIGHT: StringName = &"light"
const STYLE_SLOPED: StringName = &"sloped"
const STYLE_BOXY: StringName = &"boxy"
const STYLE_HEAVY: StringName = &"heavy"
const VARIANT_BOX_TURRET: StringName = &"box_turret"

## Plate slopes per style (degrees from vertical) for the garage's effective armour:
## [hull front, hull side, turret front].
const SLOPES: Dictionary = {
	STYLE_LIGHT: [60.0, 25.0, 0.0],
	STYLE_SLOPED: [60.0, 40.0, 30.0],
	STYLE_BOXY: [10.0, 0.0, 10.0],
	STYLE_HEAVY: [30.0, 0.0, 20.0],
}

static var _cache: Dictionary = {}

var W: float
var H: float
var L: float
var R: float
var TH: float
var GL: float
var BR: float
var yb: float
var yt: float
var yk: float   # track top
var yf: float   # hull floor
var tw: float   # track width
var heavy_look: bool
var hull := MeshKit.new()
var turret := MeshKit.new()
var mantlet := MeshKit.new()
var gun := MeshKit.new()
var out: Dictionary = {}
var _hull_groups: Array[String] = []
var _turret_groups: Array[String] = []


static func build(d: TankData) -> Dictionary:
	var key: int = d.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var m := TankModel.new()
	var result: Dictionary = m._build(d)
	_cache[key] = result
	return result


static func has_model(d: TankData) -> bool:
	return d != null and SLOPES.has(d.model_style)


func _build(d: TankData) -> Dictionary:
	W = d.hull_size.x
	H = d.hull_size.y
	L = d.hull_size.z
	R = d.turret_radius_m
	TH = d.turret_height_m
	GL = d.gun_length_m
	BR = d.barrel_radius_m
	yb = -H * 0.5
	yt = H * 0.5
	heavy_look = d.armour_look == &"heavy"
	match d.model_style:
		STYLE_LIGHT:
			_light()
		STYLE_SLOPED:
			_sloped()
		STYLE_BOXY:
			_boxy()
		_:
			_heavy(d.turret_variant == VARIANT_BOX_TURRET)
	_barrel(d.muzzle_brake)
	out["hull"] = hull.build()
	out["turret"] = turret.build()
	out["mantlet"] = mantlet.build()
	out["gun"] = gun.build()
	var hs: Array[PackedVector3Array] = []
	for g: String in _hull_groups:
		hs.append(hull.points(g))
	var ts: Array[PackedVector3Array] = []
	for g: String in _turret_groups:
		ts.append(turret.points(g))
	out["hull_shapes"] = hs
	out["turret_shapes"] = ts
	out["track_x"] = W * 0.5 - tw * 0.5
	return out


# --- Styles ----------------------------------------------------------------------------

## BT-like: small, fast, big road wheels, pointed nose of steep plates, a round turret.
func _light() -> void:
	tw = 0.12 * W
	yk = yb + 0.52 * H
	yf = yb + 0.24 * H
	_tracks(0.46 * (yk - yb), 4, 0.34 * L, false, 0)
	var zf: float = -L * 0.5
	var zr: float = L * 0.5 * 0.97
	_lower_hull(zf, zr, yk, 50.0, 35.0)
	_upper_hull(zf, zr, yk, 60.0, yk + 0.35 * (yt - yk), 40.0, 25.0)
	_visor(zf, yk, 60.0)
	_exhausts(zr, 2, 0.06)
	if heavy_look:
		_glacis_plate(zf, yk, 60.0, 0.035)
	var tz: float = -0.1 * L
	out["turret_pos"] = Vector3(0.0, yt, tz)
	# Turret: a low cone with a bustle at the back.
	turret.cylinder(Vector3.ZERO, Vector3(0.0, TH, 0.0), R, R * 0.82, 14, MeshKit.Mat.PAINT, "t_body")
	turret.block(Vector3(-R * 0.55, TH * 0.1, R * 0.45), Vector3(R * 0.55, TH * 0.8, R * 1.25),
			MeshKit.Mat.PAINT, [[Vector3(0, TH * 0.1, R * 1.25), Vector3(0, -0.6, 1)]], "t_bustle")
	_turret_groups.append_array(["t_body", "t_bustle"])
	turret.cylinder(Vector3(0, TH * 0.42, 0), Vector3(0, TH * 0.68, 0), lerpf(R, R * 0.82, 0.42) + 0.015,
			lerpf(R, R * 0.82, 0.68) + 0.015, 14, MeshKit.Mat.MARK)
	_roof_panel(TH, 0.0)
	if heavy_look:
		turret.cylinder(Vector3(0, TH * 0.15, 0), Vector3(0, TH * 0.85, 0), R * 1.05, R * 0.9, 14,
				MeshKit.Mat.PAINT)
	_turret_common(Vector3(0.0, TH * 0.48, -R * 0.95), Vector3(-R * 0.35, TH, R * 0.2))
	mantlet.block(Vector3(-R * 0.28, -TH * 0.22, -0.28), Vector3(R * 0.28, TH * 0.22, 0.05),
			MeshKit.Mat.PAINT, [[Vector3(0, TH * 0.22, -0.28), Vector3(0, 1, -1)],
			[Vector3(0, -TH * 0.22, -0.28), Vector3(0, -1, -1)]])


## T-34-like: steep sloped plates all round, wide tracks, five big wheels, a cast
## hexagonal turret well forward.
func _sloped() -> void:
	tw = 0.16 * W
	yk = yb + 0.5 * H
	yf = yb + 0.2 * H
	_tracks(0.43 * (yk - yb), 5, 0.36 * L, false, 0)
	var zf: float = -L * 0.5
	var zr: float = L * 0.5 * 0.97
	_lower_hull(zf, zr, yk - 0.02, 53.0, 45.0)
	_upper_hull(zf, zr, yk - 0.02, 60.0, yk + 0.25 * (yt - yk), 45.0, 40.0)
	_visor(zf, yk - 0.02, 60.0)
	_exhausts(zr, 2, 0.08)
	# External fuel drums on the rear sides.
	for s: float in [-1.0, 1.0]:
		var x: float = s * (W * 0.5 - 0.2)
		hull.cylinder(Vector3(x, yk + 0.18, L * 0.18), Vector3(x, yk + 0.18, L * 0.38), 0.15, 0.15, 10,
				MeshKit.Mat.PAINT)
	if heavy_look:
		_glacis_plate(zf, yk - 0.02, 60.0, 0.04)
	var tz: float = -0.17 * L
	out["turret_pos"] = Vector3(0.0, yt, tz)
	var cuts: Array = [
		[Vector3(R, 0, 0), _n_side(25.0, 1.0)], [Vector3(-R, 0, 0), _n_side(25.0, -1.0)],
		[Vector3(0, 0, -R), Vector3(0, sin(deg_to_rad(30.0)), -cos(deg_to_rad(30.0)))],
		[Vector3(R * 0.62, 0, -R * 0.95), Vector3(0.75, 0.25, -0.62)],
		[Vector3(-R * 0.62, 0, -R * 0.95), Vector3(-0.75, 0.25, -0.62)],
		[Vector3(R * 0.7, 0, R * 1.05), Vector3(0.7, 0.3, 0.65)],
		[Vector3(-R * 0.7, 0, R * 1.05), Vector3(-0.7, 0.3, 0.65)],
		[Vector3(0, TH, R), Vector3(0, 1, 0.6)],
		[Vector3(R * 0.8, TH, 0), Vector3(0.5, 1, 0)], [Vector3(-R * 0.8, TH, 0), Vector3(-0.5, 1, 0)],
	]
	turret.block(Vector3(-R, 0.0, -R * 1.05), Vector3(R, TH, R * 1.15), MeshKit.Mat.PAINT, cuts, "t_body")
	_turret_groups.append("t_body")
	_band(turret, Vector3(-R, 0.0, -R * 1.05), Vector3(R, TH, R * 1.15), cuts, TH * 0.4, TH * 0.62)
	_roof_panel(TH, R * 0.1)
	if heavy_look:
		for s: float in [-1.0, 1.0]:
			turret.block(Vector3(s * R * 0.55 - R * 0.3, TH * 0.15, -R * 0.95),
					Vector3(s * R * 0.55 + R * 0.3, TH * 0.8, -R * 0.75), MeshKit.Mat.PAINT,
					[[Vector3(0, TH * 0.8, -R * 0.95), Vector3(0, 0.5, -1)]])
	_turret_common(Vector3(0.0, TH * 0.45, -R * 0.98), Vector3(-R * 0.4, TH, R * 0.3))
	mantlet.block(Vector3(-R * 0.42, -TH * 0.3, -0.32), Vector3(R * 0.42, TH * 0.3, 0.05),
			MeshKit.Mat.PAINT, [[Vector3(0, TH * 0.3, -0.32), Vector3(0, 1, -0.8)],
			[Vector3(0, -TH * 0.3, -0.32), Vector3(0, -1, -0.8)],
			[Vector3(R * 0.42, 0, -0.32), Vector3(1, 0, -0.6)], [Vector3(-R * 0.42, 0, -0.32), Vector3(-1, 0, -0.6)]])


## Pz IV-like: a boxy superstructure with an almost upright front plate, a short glacis
## below it, eight small wheels, a big box turret with a stowage bin; the heavy armour
## package hangs side skirts on hull and turret.
func _boxy() -> void:
	tw = 0.15 * W
	yk = yb + 0.45 * H
	yf = yb + 0.22 * H
	_tracks(0.34 * (yk - yb), 8, 0.36 * L, true, 4)
	var zf: float = -L * 0.5
	var zr: float = L * 0.5 * 0.98
	var nose: float = yk - 0.05
	var ym: float = yk + 0.14 * H
	var w: float = W * 0.5 - tw - 0.02
	# Nose: upright lower plate, shallow glacis up to the superstructure.
	hull.block(Vector3(-w, yf, zf), Vector3(w, ym, zr), MeshKit.Mat.PAINT, [
		[Vector3(0, nose, zf), _n_front(12.0, false)],
		[Vector3(0, nose, zf), _n_front(72.0, true)],
		[Vector3(0, yf, zr), _n_rear(30.0, false)]], "h_lower")
	_hull_groups.append("h_lower")
	var z1: float = zf + (ym - nose) * tan(deg_to_rad(72.0)) + 0.05
	var wu: float = W * 0.5 - 0.03
	var sup_cuts: Array = [
		[Vector3(0, ym, z1), _n_front(10.0, true)],
		[Vector3(0, ym, zr * 0.97), _n_rear(12.0, true)]]
	hull.block(Vector3(-wu, ym, z1), Vector3(wu, yt, zr * 0.97), MeshKit.Mat.PAINT, sup_cuts, "h_upper")
	_hull_groups.append("h_upper")
	var yb0: float = ym + (yt - ym) * 0.4
	_band(hull, Vector3(-wu, ym, z1), Vector3(wu, yt, zr * 0.97), sup_cuts, yb0, yb0 + 0.13)
	# Fenders over the tracks, front and back.
	for s: float in [-1.0, 1.0]:
		var x0: float = minf(s * (W * 0.5 - tw - 0.02), s * W * 0.5)
		var x1: float = maxf(s * (W * 0.5 - tw - 0.02), s * W * 0.5)
		hull.box(Vector3((x0 + x1) * 0.5, yk + 0.02, 0.0), Vector3(x1 - x0, 0.04, L * 0.98), MeshKit.Mat.PAINT)
		# Tool box on the fender.
		hull.box(Vector3(s * (W * 0.5 - tw * 0.5), yk + 0.1, L * 0.3), Vector3(tw * 0.8, 0.14, 0.5),
				MeshKit.Mat.PAINT)
	# Driver's visor and hull MG ball on the front plate; spare track links on the glacis.
	hull.box(Vector3(-W * 0.18, ym + (yt - ym) * 0.6, z1 - 0.02), Vector3(0.35, 0.08, 0.06), MeshKit.Mat.DARK)
	hull.cylinder(Vector3(W * 0.18, ym + (yt - ym) * 0.5, z1 + 0.02), Vector3(W * 0.18, ym + (yt - ym) * 0.5, z1 - 0.06),
			0.09, 0.08, 8, MeshKit.Mat.PAINT)
	for i: int in 3:
		var x: float = (float(i) - 1.0) * 0.38
		hull.box(Vector3(x, (nose + ym) * 0.5 + 0.03, zf + (z1 - zf) * 0.5), Vector3(0.32, 0.05, 0.2), MeshKit.Mat.TRACK)
	# Rear muffler.
	hull.cylinder(Vector3(-W * 0.25, yf + 0.25, zr + 0.12), Vector3(W * 0.25, yf + 0.25, zr + 0.12), 0.11, 0.11, 10,
			MeshKit.Mat.DARK)
	if heavy_look:
		for s: float in [-1.0, 1.0]:
			var x: float = s * (W * 0.5 + 0.08)
			var g: String = "skirt_l" if s < 0.0 else "skirt_r"
			hull.box(Vector3(x, (yb + 0.28 * H + ym + 0.05) * 0.5, L * 0.03),
					Vector3(0.025, ym + 0.05 - (yb + 0.28 * H), L * 0.78), MeshKit.Mat.PAINT, g)
			_hull_groups.append(g)
			for k: int in 2:
				hull.box(Vector3(s * (W * 0.5 + 0.04), ym - 0.02, -L * 0.2 + float(k) * L * 0.4),
						Vector3(0.08, 0.04, 0.04), MeshKit.Mat.DARK)
	var tz: float = -0.03 * L
	out["turret_pos"] = Vector3(0.0, yt, tz)
	var cuts: Array = [
		[Vector3(R, 0, 0), _n_side(18.0, 1.0)], [Vector3(-R, 0, 0), _n_side(18.0, -1.0)],
		[Vector3(0, 0, -R * 0.95), _n_front(10.0, true)],
		[Vector3(R * 0.62, 0, -R * 0.95), Vector3(0.6, 0, -0.8)],
		[Vector3(-R * 0.62, 0, -R * 0.95), Vector3(-0.6, 0, -0.8)],
		[Vector3(0, TH, -R * 0.75), Vector3(0, 1, -0.25)],
	]
	turret.block(Vector3(-R, 0.0, -R * 0.95), Vector3(R, TH, R * 0.95), MeshKit.Mat.PAINT, cuts, "t_body")
	_band(turret, Vector3(-R, 0.0, -R * 0.95), Vector3(R, TH, R * 0.95), cuts, TH * 0.4, TH * 0.6)
	_roof_panel(TH, -R * 0.1)
	# Stowage bin round the back.
	turret.block(Vector3(-R * 0.75, TH * 0.25, R * 0.9), Vector3(R * 0.75, TH * 0.8, R * 1.4),
			MeshKit.Mat.PAINT, [[Vector3(0, TH * 0.8, R * 1.4), Vector3(0, 0.4, 1)]], "t_bin")
	_turret_groups.append_array(["t_body", "t_bin"])
	if heavy_look:
		# Turret skirts: plates round the sides and back.
		for s: float in [-1.0, 1.0]:
			var g: String = "t_skirt_l" if s < 0.0 else "t_skirt_r"
			turret.box(Vector3(s * R * 1.12, TH * 0.45, R * 0.15), Vector3(0.025, TH * 0.75, R * 1.6), MeshKit.Mat.PAINT, g)
			_turret_groups.append(g)
		turret.box(Vector3(0.0, TH * 0.45, R * 1.55), Vector3(R * 2.24, TH * 0.75, 0.025), MeshKit.Mat.PAINT, "t_skirt_b")
		_turret_groups.append("t_skirt_b")
	_turret_common(Vector3(0.0, TH * 0.42, -R * 0.97), Vector3(0.0, TH, R * 0.45))
	mantlet.block(Vector3(-R * 0.5, -TH * 0.28, -0.3), Vector3(R * 0.5, TH * 0.28, 0.05),
			MeshKit.Mat.PAINT, [[Vector3(0, TH * 0.28, -0.3), Vector3(0, 1, -1.2)],
			[Vector3(0, -TH * 0.28, -0.3), Vector3(0, -1, -1.2)]])
	mantlet.cylinder(Vector3(0, 0, -0.3), Vector3(0, 0, -0.55), BR * 2.0, BR * 1.8, 10, MeshKit.Mat.PAINT)


## KV-like: big and square, upright sides, six small wheels and return rollers, a heavy
## turret; the box-turret variant (big howitzer) is a tall slab-sided box.
func _heavy(box_turret: bool) -> void:
	tw = 0.17 * W
	yk = yb + 0.5 * H
	yf = yb + 0.2 * H
	_tracks(0.31 * (yk - yb), 6, 0.38 * L, false, 3)
	var zf: float = -L * 0.5
	var zr: float = L * 0.5 * 0.98
	_lower_hull(zf, zr, yk, 25.0, 30.0)
	_upper_hull(zf + 0.05, zr, yk, 30.0, yk + 0.3 * (yt - yk), 50.0, 0.0)
	_visor(zf + 0.05, yk, 30.0)
	_exhausts(zr, 2, 0.08)
	for s: float in [-1.0, 1.0]:
		hull.box(Vector3(s * (W * 0.5 - tw * 0.5), yk + 0.12, -L * 0.25), Vector3(tw * 0.8, 0.2, 0.7),
				MeshKit.Mat.PAINT)
	if heavy_look:
		_glacis_plate(zf + 0.05, yk, 30.0, 0.05)
	var tz: float = -0.04 * L
	out["turret_pos"] = Vector3(0.0, yt, tz)
	var top: float = TH
	if box_turret:
		top = TH * 1.6
		var box_cuts: Array = [
			[Vector3(0, top, -R * 1.0), _n_front(12.0, true)],
			[Vector3(0, top, R * 1.2), Vector3(0, 1, 0.5)],
			[Vector3(R * 0.95, 0, 0), _n_side(4.0, 1.0)], [Vector3(-R * 0.95, 0, 0), _n_side(4.0, -1.0)]]
		turret.block(Vector3(-R * 0.95, 0.0, -R * 1.0), Vector3(R * 0.95, top, R * 1.2), MeshKit.Mat.PAINT, box_cuts, "t_body")
		_turret_groups.append("t_body")
		_band(turret, Vector3(-R * 0.95, 0.0, -R * 1.0), Vector3(R * 0.95, top, R * 1.2), box_cuts, top * 0.55, top * 0.68)
		_roof_panel(top, R * 0.05)
		if heavy_look:
			for s: float in [-1.0, 1.0]:
				turret.box(Vector3(s * R * 0.99, top * 0.5, R * 0.1), Vector3(0.05, top * 0.7, R * 1.6), MeshKit.Mat.PAINT)
		_turret_common(Vector3(0.0, top * 0.42, -R * 1.02), Vector3(-R * 0.45, top, R * 0.5))
		mantlet.block(Vector3(-R * 0.55, -top * 0.25, -0.3), Vector3(R * 0.55, top * 0.25, 0.05),
				MeshKit.Mat.PAINT, [])
		mantlet.cylinder(Vector3(0, 0, -0.3), Vector3(0, 0, -0.7), BR * 1.7, BR * 1.6, 12, MeshKit.Mat.PAINT)
	else:
		var kv_cuts: Array = [
			[Vector3(R, 0, 0), _n_side(15.0, 1.0)], [Vector3(-R, 0, 0), _n_side(15.0, -1.0)],
			[Vector3(0, 0, -R), _n_front(20.0, true)],
			[Vector3(R * 0.7, 0, -R * 0.95), Vector3(0.7, 0, -0.7)], [Vector3(-R * 0.7, 0, -R * 0.95), Vector3(-0.7, 0, -0.7)],
			[Vector3(R * 0.75, 0, R * 1.0), Vector3(0.7, 0, 0.7)], [Vector3(-R * 0.75, 0, R * 1.0), Vector3(-0.7, 0, 0.7)],
			[Vector3(0, TH, R * 0.9), Vector3(0, 1, 0.5)]]
		turret.block(Vector3(-R, 0.0, -R * 1.0), Vector3(R, TH, R * 1.05), MeshKit.Mat.PAINT, kv_cuts, "t_body")
		_turret_groups.append("t_body")
		_band(turret, Vector3(-R, 0.0, -R * 1.0), Vector3(R, TH, R * 1.05), kv_cuts, TH * 0.42, TH * 0.62)
		_roof_panel(TH, 0.0)
		if heavy_look:
			for s: float in [-1.0, 1.0]:
				turret.block(Vector3(s * R * 0.92 - 0.04, TH * 0.15, -R * 0.6), Vector3(s * R * 0.92 + 0.04, TH * 0.85, R * 0.6),
						MeshKit.Mat.PAINT, [[Vector3(s * R * 0.92, TH * 0.85, 0), _n_side(15.0, s)]])
		_turret_common(Vector3(0.0, TH * 0.45, -R * 1.0), Vector3(-R * 0.45, TH, R * 0.4))
		mantlet.block(Vector3(-R * 0.45, -TH * 0.32, -0.3), Vector3(R * 0.45, TH * 0.32, 0.05),
				MeshKit.Mat.PAINT, [[Vector3(0, TH * 0.32, -0.3), Vector3(0, 1, -0.7)],
				[Vector3(0, -TH * 0.32, -0.3), Vector3(0, -1, -0.7)]])
	out["turret_top"] = top


# --- Parts -----------------------------------------------------------------------------

## Track runs (one convex profile per side), road wheels showing on the outside,
## sprocket and idler, optional return rollers.
func _tracks(rw: float, wheels: int, span: float, sprocket_front: bool, rollers: int) -> void:
	var rise: float = yk - yb
	var a: float = 0.4 * L
	var profile := PackedVector2Array([
		Vector2(-a, yb), Vector2(a, yb), Vector2(L * 0.5, yb + 0.5 * rise),
		Vector2(L * 0.5 - 0.12, yk), Vector2(-L * 0.5 + 0.12, yk), Vector2(-L * 0.5, yb + 0.5 * rise)])
	for s: float in [-1.0, 1.0]:
		var g: String = "track_l" if s < 0.0 else "track_r"
		var x_in: float = s * (W * 0.5 - tw)
		var x_out: float = s * W * 0.5
		hull.extrude_x(profile, minf(x_in, x_out), maxf(x_in, x_out), MeshKit.Mat.TRACK, g)
		_hull_groups.append(g)
		for i: int in wheels:
			var z: float = lerpf(-span, span, float(i) / float(maxi(wheels - 1, 1)))
			_wheel(s, z, yb + rw + 0.03, rw)
		var rs: float = 0.22 * rise
		var z_drive: float = (-1.0 if sprocket_front else 1.0) * (L * 0.5 - 0.1 - rs)
		_wheel(s, z_drive, yb + 0.5 * rise + 0.04, rs)
		_wheel(s, -z_drive, yb + 0.5 * rise + 0.02, rs * 0.9)
		for i: int in rollers:
			var z: float = lerpf(-span * 0.75, span * 0.75, float(i) / float(maxi(rollers - 1, 1)))
			_wheel(s, z, yk - 0.07, 0.06)


func _wheel(s: float, z: float, y: float, r: float) -> void:
	var xo: float = s * W * 0.5
	hull.cylinder(Vector3(xo - s * 0.14, y, z), Vector3(xo + s * 0.03, y, z), r, r, 14, MeshKit.Mat.WHEEL)
	hull.cylinder(Vector3(xo + s * 0.03, y, z), Vector3(xo + s * 0.07, y, z), r * 0.35, r * 0.3, 8, MeshKit.Mat.DARK)


## The hull between the tracks, from the floor to the track tops; sloped lower plates.
func _lower_hull(zf: float, zr: float, nose_y: float, front_deg: float, rear_deg: float) -> void:
	var w: float = W * 0.5 - tw - 0.02
	hull.block(Vector3(-w, yf, zf), Vector3(w, yk + 0.01, zr), MeshKit.Mat.PAINT, [
		[Vector3(0, nose_y, zf), _n_front(front_deg, false)],
		[Vector3(0, nose_y, zr), _n_rear(rear_deg, false)]], "h_lower")
	_hull_groups.append("h_lower")


## The hull above the tracks, out over them: glacis from the nose, sloped rear and
## (side_deg > 0) sloped sides.
func _upper_hull(zf: float, zr: float, nose_y: float, glacis_deg: float, rear_y: float,
		rear_deg: float, side_deg: float) -> void:
	var w: float = W * 0.5 - 0.02
	var cuts: Array = [
		[Vector3(0, nose_y, zf), _n_front(glacis_deg, true)],
		[Vector3(0, rear_y, zr), _n_rear(rear_deg, true)]]
	if side_deg > 0.0:
		cuts.append([Vector3(w, yk, 0), _n_side(side_deg, 1.0)])
		cuts.append([Vector3(-w, yk, 0), _n_side(side_deg, -1.0)])
	hull.block(Vector3(-w, yk, zf), Vector3(w, yt, zr), MeshKit.Mat.PAINT, cuts, "h_upper")
	_hull_groups.append("h_upper")
	var y0: float = yk + (yt - yk) * 0.45
	_band(hull, Vector3(-w, yk, zf), Vector3(w, yt, zr), cuts, y0, y0 + 0.13)


## Driver's visor on a glacis sloped `deg` from vertical through (0, nose_y, zf).
func _visor(zf: float, nose_y: float, deg: float) -> void:
	var rise: float = (yt - nose_y) * 0.75
	var z: float = zf + rise * tan(deg_to_rad(deg))
	var n: Vector3 = _n_front(deg, true)
	var c := Vector3(-W * 0.15, nose_y + rise, z) + n * 0.02
	hull.cylinder(c - n * 0.03, c + n * 0.03, 0.12, 0.1, 6, MeshKit.Mat.DARK, "", 30.0)


## Appliqué armour: a slab laid on the glacis.
func _glacis_plate(zf: float, nose_y: float, deg: float, thick: float) -> void:
	var n: Vector3 = _n_front(deg, true)
	var through := Vector3(0, nose_y, zf)
	var w: float = W * 0.5 - tw - 0.1
	var planes: Array[Plane] = [
		Plane(n, n.dot(through) + thick), Plane(-n, -n.dot(through) + 0.002),
		Plane(Vector3.RIGHT, w), Plane(Vector3.LEFT, w),
		Plane(Vector3.UP, nose_y + (yt - nose_y) * 0.8), Plane(Vector3.DOWN, -(nose_y + (yt - nose_y) * 0.15))]
	hull.planes_solid(planes, MeshKit.Mat.PAINT, "h_plate")
	_hull_groups.append("h_plate")


func _exhausts(zr: float, count: int, r: float) -> void:
	for i: int in count:
		var x: float = (float(i) - (count - 1) * 0.5) * W * 0.35
		var y: float = yk + 0.08
		hull.cylinder(Vector3(x, y, zr - 0.05), Vector3(x, y, zr + 0.12), r, r, 8, MeshKit.Mat.DARK)


## Gun pivot and cupola place (turret frame); turret top for spot points and hatches.
func _turret_common(pivot: Vector3, cupola_base: Vector3) -> void:
	out["gun_pivot"] = pivot
	out["cupola"] = cupola_base + Vector3(0.0, 0.15, 0.0)
	out["roof_mg"] = cupola_base + Vector3(0.0, 0.35, -0.45)
	if not out.has("turret_top"):
		out["turret_top"] = cupola_base.y


func _barrel(brake: bool) -> void:
	var start: float = -0.15
	var end: float = -(0.2 + GL)
	gun.cylinder(Vector3(0, 0, start), Vector3(0, 0, start - GL * 0.22), BR * 1.45, BR * 1.35, 12, MeshKit.Mat.PAINT)
	gun.cylinder(Vector3(0, 0, start - GL * 0.22), Vector3(0, 0, end), BR * 1.12, BR * 0.92, 12, MeshKit.Mat.PAINT)
	if brake:
		var blen: float = maxf(BR * 4.0, 0.25)
		gun.cylinder(Vector3(0, 0, end + blen), Vector3(0, 0, end + blen * 0.55), BR * 1.75, BR * 1.75, 10, MeshKit.Mat.PAINT)
		gun.cylinder(Vector3(0, 0, end + blen * 0.4), Vector3(0, 0, end), BR * 1.75, BR * 1.75, 10, MeshKit.Mat.PAINT)
	out["muzzle_z"] = end - 0.05


# --- Friend markings (UN blue, see TeamLook) -------------------------------------------

## A band round a solid: the same block and plate cuts grown by `grow`, cut to y0..y1.
func _band(kit: MeshKit, lo: Vector3, hi: Vector3, cuts: Array, y0: float, y1: float,
		grow: float = 0.015) -> void:
	var grown: Array = []
	for c: Array in cuts:
		var n: Vector3 = (c[1] as Vector3).normalized()
		grown.append([(c[0] as Vector3) + n * grow, n])
	kit.block(Vector3(lo.x - grow, y0, lo.z - grow), Vector3(hi.x + grow, y1, hi.z + grow),
			MeshKit.Mat.MARK, grown)


## A square panel on the turret roof (seen from above and from the cupola).
func _roof_panel(top: float, z: float) -> void:
	turret.box(Vector3(0.0, top + 0.012, z), Vector3(R * 0.9, 0.024, R * 0.9), MeshKit.Mat.MARK)


# --- Plate normals ---------------------------------------------------------------------

## A front plate leaning back `deg` from vertical: up = the top leans back (glacis),
## else the bottom does (lower nose plate).
static func _n_front(deg: float, up: bool) -> Vector3:
	var a: float = deg_to_rad(deg)
	return Vector3(0.0, sin(a) * (1.0 if up else -1.0), -cos(a))


static func _n_rear(deg: float, up: bool) -> Vector3:
	var a: float = deg_to_rad(deg)
	return Vector3(0.0, sin(a) * (1.0 if up else -1.0), cos(a))


## A side plate leaning in `deg` from vertical on side `s` (-1 left, +1 right).
static func _n_side(deg: float, s: float) -> Vector3:
	var a: float = deg_to_rad(deg)
	return Vector3(s * cos(a), sin(a), 0.0)
