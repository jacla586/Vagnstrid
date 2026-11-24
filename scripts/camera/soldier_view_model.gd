class_name SoldierViewModel
extends Node3D
## The squad view's "first person" look (SquadCamera): two forearms and hands holding an
## AK-like rifle low in the bottom right, made of simple solids, a child of the camera.
## It sways with the leader's walk and kicks when he fires. Only shown while the squad
## view is the current camera, so no other view ever sees it. Looks only.

## Where the rifle sits in front of the eye (camera space, m) and how it is turned.
const REST := Vector3(0.17, -0.19, -0.42)
const REST_TURN := Vector3(deg_to_rad(2.0), deg_to_rad(4.0), 0.0)
## Walk sway: metres of bob per m/s of the leader's speed, and steps per metre.
const BOB_M_PER_MPS: float = 0.006
const BOB_STEPS_PER_M: float = 0.9
## A shot: kick back and up, settling this fast (1/s).
const KICK_BACK_M: float = 0.05
const KICK_UP_RAD: float = 0.06
const KICK_SETTLE: float = 14.0

var _kick: float = 0.0
var _walk: float = 0.0


func _ready() -> void:
	var metal := _material(Color(0.09, 0.09, 0.1), 0.45, 0.7)
	var wood := _material(Color(0.36, 0.19, 0.09), 0.7, 0.0)
	var sleeve := _material(Color(0.25, 0.3, 0.2), 0.95, 0.0)
	var skin := _material(Color(0.78, 0.6, 0.48), 0.8, 0.0)
	var glove := _material(Color(0.2, 0.17, 0.13), 0.9, 0.0)
	var rifle := Node3D.new()
	rifle.name = "Rifle"
	add_child(rifle)
	# Along -Z: stock at the back (+z), muzzle ahead.
	_box(rifle, Vector3(0.05, 0.07, 0.24), Vector3(0.0, -0.005, 0.0), metal)        # receiver
	_box(rifle, Vector3(0.045, 0.025, 0.2), Vector3(0.0, 0.04, 0.0), metal)         # top cover
	_box(rifle, Vector3(0.055, 0.06, 0.16), Vector3(0.0, -0.005, -0.2), wood)       # handguard
	_box(rifle, Vector3(0.045, 0.03, 0.14), Vector3(0.0, 0.04, -0.19), wood)        # upper guard
	_cylinder(rifle, 0.011, 0.36, Vector3(0.0, 0.015, -0.42), metal)                # barrel
	_cylinder(rifle, 0.008, 0.28, Vector3(0.0, 0.045, -0.36), metal)                # gas tube
	_box(rifle, Vector3(0.012, 0.045, 0.02), Vector3(0.0, 0.05, -0.56), metal)      # front sight
	_box(rifle, Vector3(0.03, 0.02, 0.03), Vector3(0.0, 0.062, -0.08), metal)       # rear sight
	_box(rifle, Vector3(0.045, 0.075, 0.26), Vector3(0.0, -0.025, 0.25), wood,
			Vector3(deg_to_rad(-8.0), 0.0, 0.0))                                       # stock
	_box(rifle, Vector3(0.04, 0.09, 0.04), Vector3(0.0, -0.075, 0.07), wood,
			Vector3(deg_to_rad(-20.0), 0.0, 0.0))                                      # grip
	for k: int in 4:   # curved magazine
		_box(rifle, Vector3(0.035, 0.055, 0.06),
				Vector3(0.0, -0.06 - k * 0.045, -0.045 - k * 0.012), metal,
				Vector3(deg_to_rad(10.0 + k * 9.0), 0.0, 0.0))
	# Right hand on the grip, left under the handguard; forearms back to the eye.
	_box(rifle, Vector3(0.06, 0.07, 0.09), Vector3(0.012, -0.085, 0.085), glove)
	_box(rifle, Vector3(0.065, 0.05, 0.1), Vector3(-0.01, -0.045, -0.21), glove)
	_arm(rifle, Vector3(0.02, -0.1, 0.12), Vector3(0.14, -0.2, 0.5), sleeve, skin)
	_arm(rifle, Vector3(-0.015, -0.06, -0.2), Vector3(-0.16, -0.22, 0.32), sleeve, skin)
	position = REST
	rotation = REST_TURN


## Each frame: sway from the leader's speed (m/s), settle the kick.
func step(delta: float, speed_mps: float) -> void:
	_walk += speed_mps * delta * BOB_STEPS_PER_M * TAU
	var bob: float = minf(speed_mps, 4.0) * BOB_M_PER_MPS
	_kick = move_toward(_kick, 0.0, _kick * KICK_SETTLE * delta + delta * 0.2)
	position = REST + Vector3(sin(_walk * 0.5) * bob, -absf(sin(_walk)) * bob, _kick * KICK_BACK_M)
	rotation = REST_TURN + Vector3(_kick * KICK_UP_RAD, 0.0, sin(_walk * 0.5) * bob * 2.0)


func kick() -> void:
	_kick = 1.0


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, turn: Vector3 = Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add(parent, mesh, at, turn, mat)


func _cylinder(parent: Node3D, radius: float, length: float, at: Vector3, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1
	_add(parent, mesh, at, Vector3(deg_to_rad(90.0), 0.0, 0.0), mat)


## A forearm from the hand at `from` back towards `to` (rifle space): sleeve and wrist.
func _arm(parent: Node3D, from: Vector3, to: Vector3, sleeve: Material, skin: Material) -> void:
	var along: Vector3 = to - from
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.042
	mesh.bottom_radius = 0.034
	mesh.height = along.length()
	mesh.radial_segments = 10
	mesh.rings = 1
	var arm := MeshInstance3D.new()
	arm.mesh = mesh
	arm.material_override = sleeve
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(arm)
	# The cylinder's axis is +Y: turn it along the arm.
	var y: Vector3 = along.normalized()
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	arm.transform = Transform3D(Basis(x, y, x.cross(y)), from + along * 0.5)
	var wrist := MeshInstance3D.new()
	var wrist_mesh := CylinderMesh.new()
	wrist_mesh.top_radius = 0.03
	wrist_mesh.bottom_radius = 0.03
	wrist_mesh.height = 0.04
	wrist_mesh.radial_segments = 8
	wrist.mesh = wrist_mesh
	wrist.material_override = skin
	wrist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(wrist)
	wrist.transform = Transform3D(arm.transform.basis, from + y * 0.03)


func _add(parent: Node3D, mesh: Mesh, at: Vector3, turn: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = at
	mi.rotation = turn
	parent.add_child(mi)
