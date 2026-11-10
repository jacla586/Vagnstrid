class_name CommanderModel
extends RefCounted
## The tank commander seen in his open hatch: a low-poly figure from the waist up with a
## crew helmet and headset, arms resting on the hatch ring and binoculars on his chest.
## Uniform is PAINT and the helmet MARK, so friends wear olive with a UN-blue helmet and
## enemies are camouflaged all over (Tank.paint_visual), like the infantry. Origin at the
## centre of the head (the commander's eye point), facing -Z. Built once, shared.

static var _mesh: ArrayMesh


static func build() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var kit := MeshKit.new()
	var paint := MeshKit.Mat.PAINT
	var skin := MeshKit.Mat.SKIN
	var dark := MeshKit.Mat.DARK
	# Head, neck and face.
	kit.cylinder(Vector3(0.0, -0.13, 0.0), Vector3(0.0, 0.07, 0.0), 0.095, 0.09, 8, skin)
	kit.cylinder(Vector3(0.0, -0.19, 0.0), Vector3(0.0, -0.12, 0.0), 0.055, 0.055, 6, skin)
	# Crew helmet with ear cups and a strap under the chin.
	kit.cylinder(Vector3(0.0, -0.02, 0.01), Vector3(0.0, 0.07, 0.01), 0.125, 0.118, 10, MeshKit.Mat.MARK)
	kit.cylinder(Vector3(0.0, 0.07, 0.01), Vector3(0.0, 0.12, 0.01), 0.118, 0.085, 10, MeshKit.Mat.MARK)
	kit.cylinder(Vector3(0.0, 0.12, 0.01), Vector3(0.0, 0.145, 0.01), 0.085, 0.03, 10, MeshKit.Mat.MARK)
	for s: float in [-1.0, 1.0]:
		kit.cylinder(Vector3(s * 0.09, -0.04, 0.0), Vector3(s * 0.135, -0.04, 0.0), 0.055, 0.05, 8, dark)
	kit.box(Vector3(0.0, -0.13, -0.02), Vector3(0.17, 0.02, 0.03), dark)
	# Torso and shoulders.
	kit.box(Vector3(0.0, -0.47, 0.02), Vector3(0.42, 0.56, 0.26), paint)
	kit.box(Vector3(0.0, -0.22, 0.02), Vector3(0.46, 0.08, 0.24), paint)
	# Arms down and forward, forearms resting on the hatch ring, hands.
	for s: float in [-1.0, 1.0]:
		var shoulder := Vector3(s * 0.22, -0.24, 0.02)
		var elbow := Vector3(s * 0.27, -0.55, -0.14)
		var hand := Vector3(s * 0.17, -0.58, -0.36)
		kit.cylinder(shoulder, elbow, 0.055, 0.05, 6, paint)
		kit.cylinder(elbow, hand, 0.05, 0.045, 6, paint)
		kit.box(hand + Vector3(0.0, 0.0, -0.04), Vector3(0.07, 0.05, 0.09), skin)
	# Binoculars on the chest.
	for s: float in [-1.0, 1.0]:
		kit.cylinder(Vector3(s * 0.04, -0.37, -0.12), Vector3(s * 0.04, -0.37, -0.24), 0.03, 0.03, 6, dark)
	_mesh = kit.build()
	return _mesh
