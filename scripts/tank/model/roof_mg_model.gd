class_name RoofMgModel
extends RefCounted
## The roof machine gun's look, after a Browning M2 (.50 cal): a boxy receiver with
## spade grips and a butterfly trigger at the back, a perforated barrel jacket, a long
## heavy barrel with a front sight and a carrying handle, an ammunition can on the left,
## on a pintle and cradle. Built once with MeshKit (metal parts DARK, the can DETAIL)
## and shared by every tank. Gun points along -Z from the pitch pivot.

## Barrel tip (m along -Z from the pitch pivot): where the bullets start.
const MUZZLE_Z: float = -1.32
## The RoofMG node sits this far above the turret roof (TankModel "roof_mg", Tank's plain
## box placement): the pintle reaches down to it.
const ROOF_BELOW_M: float = 0.35

static var _cache: Dictionary = {}


## {"gun": ArrayMesh (on the Pitch node), "mount": ArrayMesh (on the RoofMG node, below
## the pivot), "muzzle_z": float}.
static func build() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var gun := MeshKit.new()
	var metal := MeshKit.Mat.DARK
	# Receiver: a long box, a little top cover ridge, the back plate.
	gun.box(Vector3(0.0, 0.0, 0.06), Vector3(0.12, 0.14, 0.42), metal)
	gun.box(Vector3(0.0, 0.08, 0.04), Vector3(0.09, 0.02, 0.3), metal)
	gun.box(Vector3(0.0, 0.0, 0.285), Vector3(0.14, 0.12, 0.03), metal)
	# Spade grips and the butterfly trigger between them.
	for s: float in [-1.0, 1.0]:
		gun.cylinder(Vector3(s * 0.055, -0.04, 0.33), Vector3(s * 0.055, 0.06, 0.33), 0.017, 0.017, 6, metal)
		gun.box(Vector3(s * 0.055, 0.01, 0.31), Vector3(0.02, 0.02, 0.05), metal)
	gun.box(Vector3(0.0, 0.03, 0.33), Vector3(0.05, 0.02, 0.02), metal)
	# Charging handle on the right side.
	gun.box(Vector3(0.075, 0.01, 0.0), Vector3(0.03, 0.025, 0.06), metal)
	# Barrel jacket with cooling holes (dark rings), barrel, front sight, carrying handle.
	gun.cylinder(Vector3(0.0, 0.0, -0.15), Vector3(0.0, 0.0, -0.42), 0.038, 0.038, 10, metal)
	for i: int in 4:
		var z: float = -0.19 - 0.06 * float(i)
		gun.cylinder(Vector3(0.0, 0.0, z), Vector3(0.0, 0.0, z - 0.018), 0.041, 0.041, 10, MeshKit.Mat.TRACK)
	gun.cylinder(Vector3(0.0, 0.0, -0.42), Vector3(0.0, 0.0, MUZZLE_Z), 0.019, 0.017, 8, metal)
	gun.cylinder(Vector3(0.0, 0.0, MUZZLE_Z + 0.04), Vector3(0.0, 0.0, MUZZLE_Z), 0.024, 0.024, 8, metal)
	gun.box(Vector3(0.0, 0.035, MUZZLE_Z + 0.06), Vector3(0.012, 0.03, 0.02), metal)
	gun.box(Vector3(0.0, 0.09, -0.3), Vector3(0.03, 0.02, 0.16), metal)
	for z: float in [-0.23, -0.37]:
		gun.box(Vector3(0.0, 0.065, z), Vector3(0.015, 0.05, 0.015), metal)
	# Rear sight leaf.
	gun.box(Vector3(0.0, 0.1, 0.2), Vector3(0.03, 0.04, 0.01), metal)
	# Ammunition can on the left, a belt feed chute into the receiver.
	gun.box(Vector3(-0.16, -0.06, 0.04), Vector3(0.11, 0.17, 0.27), MeshKit.Mat.DETAIL)
	gun.box(Vector3(-0.16, 0.03, 0.04), Vector3(0.09, 0.015, 0.22), metal)
	gun.box(Vector3(-0.09, 0.03, 0.04), Vector3(0.05, 0.03, 0.08), metal)
	# Cradle under the receiver (turns with the gun).
	gun.box(Vector3(0.0, -0.1, 0.06), Vector3(0.08, 0.06, 0.2), metal)

	var mount := MeshKit.new()
	# Pintle post from the turret roof (ROOF_BELOW_M under the RoofMG node) up to the
	# cradle, with a foot plate and a collar.
	mount.cylinder(Vector3(0.0, -ROOF_BELOW_M, 0.0), Vector3(0.0, 0.22, 0.0), 0.035, 0.03, 8, metal)
	mount.cylinder(Vector3(0.0, -ROOF_BELOW_M, 0.0), Vector3(0.0, 0.03 - ROOF_BELOW_M, 0.0), 0.08, 0.08, 10, metal)
	mount.cylinder(Vector3(0.0, 0.17, 0.0), Vector3(0.0, 0.2, 0.0), 0.05, 0.05, 8, metal)
	_cache = {"gun": gun.build(), "mount": mount.build(), "muzzle_z": MUZZLE_Z}
	return _cache
