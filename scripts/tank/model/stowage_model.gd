class_name StowageModel
extends RefCounted
## The crew's kit, so a tank looks lived in: a rack of bars behind the turret holding a
## mix of tarp rolls, packs, crates and jerrycans, and jerrycans on the rear deck. A few
## variants per tank type (picked per tank), built with MeshKit: cans in paint, tarps and
## packs in canvas, crates and bars in darker tones. Looks only.

const VARIANTS: int = 6

static var _cache: Dictionary = {}


## {"turret": ArrayMesh (turret frame), "hull": ArrayMesh (hull frame)} for TankModel
## measures `stow` and a variant 0..VARIANTS-1.
static func build(data_key: int, stow: Dictionary, variant: int) -> Dictionary:
	var key: String = "%d:%d" % [data_key, variant]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var t := MeshKit.new()
	var back: float = stow["back_z"]
	var top: float = stow["top"]
	var w: float = stow["half_w"]
	var depth: float = 0.38
	var y0: float = top * 0.35
	var dark := MeshKit.Mat.DARK
	# The rack: a floor frame, corner posts and a top rail.
	for x: float in [-w, w]:
		t.box(Vector3(x, y0, back + depth * 0.5), Vector3(0.03, 0.03, depth), dark)
		t.box(Vector3(x, y0 + 0.17, back + depth), Vector3(0.03, 0.34, 0.03), dark)
	t.box(Vector3(0.0, y0, back + depth), Vector3(w * 2.0, 0.03, 0.03), dark)
	t.box(Vector3(0.0, y0 + 0.34, back + depth), Vector3(w * 2.0, 0.03, 0.03), dark)
	for i: int in 3:
		t.box(Vector3(0.0, y0, back + depth * (0.2 + 0.3 * float(i))), Vector3(w * 2.0, 0.02, 0.02), dark)
	# Kit along the rack, left to right.
	var x: float = -w + 0.05
	while x < w - 0.15:
		var kind: int = rng.randi_range(0, 3)
		var size: float
		match kind:
			0:   # tarp roll lying across
				size = rng.randf_range(0.45, 0.7)
				var r: float = rng.randf_range(0.09, 0.13)
				t.cylinder(Vector3(x, y0 + r + 0.02, back + depth * 0.5), Vector3(minf(x + size, w), y0 + r + 0.02,
						back + depth * 0.5), r, r, 8, MeshKit.Mat.CANVAS)
			1:   # pack
				size = rng.randf_range(0.3, 0.4)
				t.box(Vector3(x + size * 0.5, y0 + 0.15, back + depth * 0.5), Vector3(size, 0.28, 0.24), MeshKit.Mat.CANVAS)
				t.box(Vector3(x + size * 0.5, y0 + 0.31, back + depth * 0.5), Vector3(size * 0.8, 0.05, 0.2), MeshKit.Mat.DETAIL)
			2:   # ammunition crate
				size = rng.randf_range(0.35, 0.5)
				t.box(Vector3(x + size * 0.5, y0 + 0.12, back + depth * 0.5), Vector3(size, 0.22, 0.3), MeshKit.Mat.DETAIL)
				t.box(Vector3(x + size * 0.5, y0 + 0.235, back + depth * 0.5), Vector3(size * 0.3, 0.02, 0.06), dark)
			_:   # jerrycan standing
				size = 0.18
				_jerrycan(t, Vector3(x + 0.09, y0 + 0.02, back + depth * 0.5), 0.0)
		x += size + rng.randf_range(0.03, 0.08)
	var h := MeshKit.new()
	# Jerrycans at the rear corners of the deck (fewer on some).
	var deck_y: float = stow["deck_y"]
	var dz: float = (stow["deck_z"] as float) - 0.3
	var dw: float = (stow["deck_half_w"] as float) - 0.15
	var cans: int = rng.randi_range(1, 3)
	for i: int in cans:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		_jerrycan(h, Vector3(side * (dw - 0.22 * float(i / 2)), deck_y, dz), PI * 0.5)
	if rng.randf() < 0.5:
		var r: float = 0.11
		h.cylinder(Vector3(-dw * 0.5, deck_y + r, dz - 0.35), Vector3(dw * 0.5, deck_y + r, dz - 0.35), r, r, 8,
				MeshKit.Mat.CANVAS)
	var result: Dictionary = {"turret": t.build(), "hull": h.build()}
	_cache[key] = result
	return result


## A jerrycan standing at `foot`, turned `yaw` (radians), in paint with a dark cap.
static func _jerrycan(kit: MeshKit, foot: Vector3, yaw: float) -> void:
	kit.xform = Transform3D(Basis(Vector3.UP, yaw), foot)
	kit.box(Vector3(0.0, 0.17, 0.0), Vector3(0.16, 0.34, 0.26), MeshKit.Mat.PAINT)
	kit.box(Vector3(0.0, 0.36, -0.06), Vector3(0.04, 0.04, 0.04), MeshKit.Mat.DARK)
	kit.box(Vector3(0.0, 0.355, 0.05), Vector3(0.03, 0.03, 0.1), MeshKit.Mat.DARK)
	kit.xform = Transform3D.IDENTITY
