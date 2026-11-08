class_name GunSmoke
extends Node3D
## The cloud of smoke and dust a main-gun shot leaves at the muzzle: it hangs for a
## few seconds and shows where the shot came from. Frees itself.

const COLOR: Color = Color(0.55, 0.52, 0.47, 0.5)
const LIFETIME_S: float = 5.0
const PUFFS: int = 14
const SPEED_MPS: float = 5.0


## A cloud at `at`, pushed out along the bore `direction` (world, unit).
static func spawn(parent: Node, at: Vector3, direction: Vector3, calibre_scale: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var smoke := GunSmoke.new()
	var size: float = clampf(calibre_scale, 0.5, 2.5)
	var p: GPUParticles3D = SmokePuffs.make(COLOR, 1.0 * size, 5.0 * size, LIFETIME_S)
	p.amount = PUFFS
	p.one_shot = true
	p.explosiveness = 0.95
	var process := p.process_material as ParticleProcessMaterial
	process.direction = Vector3.FORWARD
	process.spread = 35.0
	process.initial_velocity_min = SPEED_MPS * 0.3 * size
	process.initial_velocity_max = SPEED_MPS * size
	process.damping_min = 2.0
	process.damping_max = 3.0
	process.gravity = Vector3(0.0, 0.3, 0.0)
	smoke.add_child(p)
	parent.add_child(smoke)
	smoke.global_position = at
	if direction.length_squared() > 0.001:
		var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		smoke.look_at(at + direction, up)
	p.emitting = true
	p.finished.connect(smoke.queue_free)
