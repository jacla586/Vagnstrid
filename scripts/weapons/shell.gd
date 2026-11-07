class_name Shell
extends Node3D
## A simulated shell. Flies with Ballistics.integrate() (same model as the sight's
## range ladder) and detects hits by raycasting from its previous to its current
## position every physics frame. Not a physics body.
##
## On a hit it spawns an impact effect and calls
## `on_shell_hit(shell_data, point, normal, velocity, shape)` on the collider if it
## has it. That returns a HitResult (or null for a plain hit), which is passed to
## the shooter's report_shot(). On a ricochet the shell bounces off and flies on.
## Explosive shells never bounce: they detonate on any impact and throw fragments
## (see Explosion); every fragment hit is reported to the shooter too.

## Emitted on the host when the shell bounces off (the net code shows it on clients).
signal ricocheted(from: Vector3, velocity: Vector3)

const MAX_LIFETIME: float = 15.0
## Freed if it somehow gets this far below the world origin (m).
const MIN_HEIGHT: float = -200.0
## Tracer grows wider with age so it stays visible at long range (fun over realism).
const TRACER_GROWTH_PER_SECOND: float = 4.0
const IMPACT_SCENE: PackedScene = preload("res://scenes/effects/impact.tscn")
## Share of speed kept after a ricochet. Tuned for a visible bounce.
const RICOCHET_SPEED_FACTOR: float = 0.5

var _data: ShellData
var _velocity: Vector3 = Vector3.ZERO
var _drag_factor: float = 0.0
var _shooter: CollisionObject3D
## Bodies the hit ray ignores: the shooter, and anything already ricocheted off.
var _exclude: Array[RID] = []
var _age: float = 0.0
var _tracer_base_scale: float = 1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Client copy of a host shell: same flight and impact effect, no damage. The host
## decides hits and sends ricochets as new shells.
var _cosmetic: bool = false
## Enemy tanks this shell passed close to (Tank -> flight direction) and tanks it hit.
var _near: Dictionary = {}
var _hit_tanks: Array[Tank] = []

@onready var _tracer: MeshInstance3D = $Tracer


## Starts the flight. Call after the shell is in the scene tree.
func launch(data: ShellData, start_position: Vector3, velocity: Vector3,
		shooter: CollisionObject3D, cosmetic: bool = false) -> void:
	_data = data
	_cosmetic = cosmetic
	_velocity = velocity
	_drag_factor = Ballistics.drag_factor(data)
	_shooter = shooter
	if shooter != null:
		_exclude.append(shooter.get_rid())
	global_position = start_position
	_orient()
	reset_physics_interpolation()   # starts at the muzzle, not where it was made
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = data.tracer_color
	_tracer.material_override = material
	_tracer_base_scale = data.tracer_scale
	_tracer.scale = Vector3.ONE * _tracer_base_scale


func get_velocity() -> Vector3:
	return _velocity


func get_age() -> float:
	return _age


func _physics_process(delta: float) -> void:
	if _data == null:
		return
	_age += delta
	if _age > MAX_LIFETIME or global_position.y < MIN_HEIGHT:
		_report_near_misses()
		queue_free()
		return
	var from: Vector3 = global_position
	var next: PackedVector3Array = Ballistics.integrate(from, _velocity, _drag_factor, delta)
	var query := PhysicsRayQueryParameters3D.create(from, next[0])
	query.exclude = _exclude
	# Areas too: the exposed commander's hitbox is an Area3D.
	query.collide_with_areas = true
	# Bushes and canopies hide things but don't stop shells.
	query.collision_mask = Vision.SHOT_MASK
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not _cosmetic:
		var end: Vector3 = next[0] if hit.is_empty() else hit["position"]
		Tank.collect_near_misses(get_tree(), from, end, _data, _shooter, _near)
	if not hit.is_empty():
		_on_hit(hit)
		return
	global_position = next[0]
	_velocity = next[1]
	_orient()
	var width: float = 1.0 + _age * TRACER_GROWTH_PER_SECOND
	_tracer.scale = Vector3(width, 1.0, width) * _tracer_base_scale


func _on_hit(hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var effect: Node3D = IMPACT_SCENE.instantiate()
	get_parent().add_child(effect)
	effect.global_position = point
	effect.scale = Vector3.ONE * _data.impact_scale
	var light: OmniLight3D = effect.get_node_or_null("Light") as OmniLight3D
	if light != null:
		light.omni_range *= _data.impact_scale
	var collider: Object = hit["collider"]
	if _cosmetic:
		_play_hit_sound(collider, point)
		queue_free()
		return
	var result: HitResult = null
	# No friendly fire: a hit on the shooter's own team does nothing (the shell stops).
	if collider != null and collider.has_method("on_shell_hit") and not Tank.is_friendly(_shooter, collider):
		result = collider.on_shell_hit(_data, point, normal, _velocity, int(hit["shape"]))
		_report(result)
		if collider is Tank:
			_hit_tanks.append(collider)
	if _data.is_explosive() or result == null or result.outcome != HitResult.Outcome.RICOCHET:
		_play_hit_sound(collider, point)
	if _data.is_explosive():
		_rng.randomize()
		for fragment_result: HitResult in Explosion.detonate(get_world_3d(), get_tree(), point,
				normal, _data, _rng, Tank.team_of(_shooter)):
			_report(fragment_result)
		_report_near_misses()
		queue_free()
		return
	if result != null and result.outcome == HitResult.Outcome.RICOCHET:
		_ricochet(point, normal, hit["rid"])
		return
	_report_near_misses()
	queue_free()


## Done flying: tanks it passed or landed close to (and didn't hit) feel a near miss.
func _report_near_misses() -> void:
	for key: Variant in _near.keys():
		if is_instance_valid(key) and not _hit_tanks.has(key):
			(key as Tank).report_near_miss(_near[key])
	_near.clear()


## Tells the shooter what a hit did. Null results (nothing of note) aren't reported.
func _report(result: HitResult) -> void:
	if result != null and is_instance_valid(_shooter) and _shooter.has_method("report_shot"):
		result.bullet = _data.caliber_mm < Tank.THREAT_MIN_CALIBER_MM
		_shooter.report_shot(result)


## Impact sound: armour clang or ground thud, plus the detonation for explosive
## shells (whatever they hit). A hit on the player's own tank plays on its bus, so
## it's loud inside with the hatch closed. Hitboxes (areas) get no clang or thud.
func _play_hit_sound(collider: Object, point: Vector3) -> void:
	var tank := collider as Tank
	var bus_name: StringName = tank.get_audio_bus() if tank != null else SoundFx.WORLD_BUS
	if _data.is_explosive():
		SoundFx.play_at(self, _data.sound_explosion, point, bus_name)
	if collider is Area3D:
		return
	if tank != null:
		SoundFx.play_at(self, _data.sound_hit_armour, point, bus_name)
	else:
		SoundFx.play_at(self, _data.sound_hit_ground, point)


## Bounces off the plate and keeps flying; never hits the same body again.
func _ricochet(point: Vector3, normal: Vector3, body: RID) -> void:
	var tank := instance_from_id(PhysicsServer3D.body_get_object_instance_id(body)) as Tank
	SoundFx.play_at(self, _data.sound_ricochet, point,
			tank.get_audio_bus() if tank != null else SoundFx.WORLD_BUS)
	_exclude.append(body)
	_velocity = _velocity.bounce(normal) * RICOCHET_SPEED_FACTOR
	global_position = point + normal * 0.05
	_orient()
	ricocheted.emit(global_position, _velocity)


## Points -Z along the velocity (the tracer is stretched along Z).
func _orient() -> void:
	if _velocity.length_squared() < 0.0001:
		return
	var direction: Vector3 = _velocity.normalized()
	var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD
	global_basis = Basis.looking_at(direction, up)
