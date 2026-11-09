class_name GunSmoke
extends Node3D
## The cloud of smoke and dust a main-gun shot leaves at the muzzle
## (EffectsSetData.gun_smoke): it hangs for a few seconds and shows where the shot came
## from. Puffs near the camera fade out (BurstData.near_fade_m), so the own tank's cloud
## in front of the commander's view stays cheap to draw. Frees itself.


## A cloud at `at`, pushed out along the bore `direction` (world, unit).
## render_layer: the shooting tank's gun layer (Tank.get_gun_render_layer): the own
## gunner's sight doesn't render it, so he sees where his round goes (others see the cloud).
static func spawn(parent: Node, at: Vector3, direction: Vector3, calibre_scale: float,
		render_layer: int = 1) -> void:
	var burst: BurstData = EffectFx.SET.gun_smoke
	if parent == null or not parent.is_inside_tree() or burst == null:
		return
	var smoke := GunSmoke.new()
	smoke.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var p: GPUParticles3D = EffectFx.emitter(burst, clampf(calibre_scale, 0.5, 2.5))
	p.one_shot = true
	p.layers = 1 << (clampi(render_layer, 1, 20) - 1)
	smoke.add_child(p)
	parent.add_child(smoke)
	smoke.global_transform = Transform3D(EffectFx.basis_towards(direction), at)
	p.emitting = true
	p.finished.connect(smoke.queue_free)
