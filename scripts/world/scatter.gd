@tool
class_name Scatter
extends Node3D
## Editor tool: drops `count` instances of `scene` at random spots within
## `radius_m` of this node, snapped to the terrain, with random yaw and scale.
## Tick "regenerate" in the inspector to (re)build. Same seed = same layout. The
## instances are normal child nodes saved with the scene, so they can be moved or
## deleted one by one afterwards (regenerating replaces them all).

@export var scene: PackedScene
@export var terrain: Terrain3D
@export_range(1, 2000) var count: int = 50
@export var radius_m: float = 100.0
@export var random_seed: int = 1
@export var min_scale: float = 0.8
@export var max_scale: float = 1.3
## Spots steeper than this are skipped (degrees).
@export_range(0.0, 90.0) var max_slope_deg: float = 25.0
## Inspector button: tick to regenerate.
@export var regenerate: bool = false:
	set(value):
		if value:
			regenerate_now()

## Give up after this many tries per requested instance (steep or off-terrain spots).
const MAX_TRIES_PER_INSTANCE: int = 10


## Replaces all children with a fresh layout. Returns how many were placed.
func regenerate_now() -> int:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if scene == null or terrain == null or terrain.data == null:
		push_warning("Scatter '%s' needs a scene and a terrain" % name)
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var scene_owner: Node = owner if owner != null else self
	var max_cos: float = cos(deg_to_rad(max_slope_deg))
	var placed: int = 0
	var tries: int = 0
	while placed < count and tries < count * MAX_TRIES_PER_INSTANCE:
		tries += 1
		var angle: float = rng.randf() * TAU
		var distance: float = sqrt(rng.randf()) * radius_m
		var spot: Vector3 = global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
		var height: float = terrain.data.get_height(spot)
		if is_nan(height) or terrain.data.get_normal(spot).y < max_cos:
			continue
		var instance := scene.instantiate() as Node3D
		add_child(instance)
		instance.owner = scene_owner
		instance.name = "%s%d" % [instance.name, placed]
		instance.global_position = Vector3(spot.x, height, spot.z)
		instance.rotation.y = rng.randf() * TAU
		instance.scale = Vector3.ONE * rng.randf_range(min_scale, max_scale)
		placed += 1
	return placed
