class_name BattleMarks
extends RefCounted
## Scorch marks where gun rounds (>= 20 mm) struck a tank: a sooty crater with bright
## metal in the middle, as a Decal on the hull or turret (so it turns with the turret).
## Every machine adds them from the impacts it already shows (Shell._play_impact; clients'
## shells are cosmetic copies), nothing is sent. At most MAX_MARKS a tank (the oldest go);
## cleared when the tank is repaired (respawn).

const MAX_MARKS: int = 16
## Mark size for a 75 mm round (m); scales with the calibre.
const SIZE_M: float = 0.42
## How deep the decal box reaches into and out of the plate (m).
const DEPTH_M: float = 0.3
## Marks fade out beyond this distance (m).
const FADE_M: float = 160.0
const GROUP_META: StringName = &"battle_marks"

static var _texture: ImageTexture


## A mark at `point` (world) on a plate facing `normal`, for a round of `calibre_mm`.
static func add(tank: Tank, point: Vector3, normal: Vector3, calibre_mm: float) -> void:
	var visual: Node3D = tank.get_node_or_null("Visual")
	if visual == null:
		return
	# On the turret if the hit is above the hull roof (the turret, mantlet and gun).
	var local: Vector3 = tank.to_local(point)
	var parent: Node3D = visual.get_node("Turret") if local.y > tank.data.hull_size.y * 0.5 - 0.02 \
			else visual.get_node("Hull")
	var decal := Decal.new()
	var size: float = SIZE_M * clampf(calibre_mm / 75.0, 0.5, 2.0)
	decal.size = Vector3(size, DEPTH_M, size)
	decal.texture_albedo = _mark_texture()
	decal.albedo_mix = 1.0
	decal.upper_fade = 0.0
	decal.lower_fade = 0.3
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = FADE_M
	decal.distance_fade_length = 20.0
	parent.add_child(decal)
	var up: Vector3 = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var helper: Vector3 = Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x: Vector3 = helper.cross(up).normalized()
	# A random turn round the normal so marks don't all look alike.
	var b := Basis(x, up, x.cross(up)).rotated(up, randf() * TAU)
	decal.global_transform = Transform3D(b, point)
	var marks: Array = tank.get_meta(GROUP_META, [])
	marks.append(decal)
	while marks.size() > MAX_MARKS:
		var old: Node = marks.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	tank.set_meta(GROUP_META, marks)


## Removes every mark (the tank is repaired).
static func clear(tank: Tank) -> void:
	for mark: Variant in tank.get_meta(GROUP_META, []):
		if is_instance_valid(mark):
			(mark as Node).queue_free()
	tank.set_meta(GROUP_META, [])


## Soot round a bright gouge, ragged at the edge.
static func _mark_texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var size: int = 128
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.06
	var image := Image.create_empty(size, size, true, Image.FORMAT_RGBA8)
	for y: int in size:
		for x: int in size:
			var d: float = Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var n: float = noise.get_noise_2d(x, y) * 0.5 + 0.5
			var edge: float = d + (n - 0.5) * 0.35
			var soot: float = clampf(1.0 - smoothstep(0.45, 1.0, edge), 0.0, 1.0)
			var metal: float = clampf(1.0 - smoothstep(0.08, 0.2, d + (n - 0.5) * 0.12), 0.0, 1.0)
			var rim: float = clampf(1.0 - absf(d - 0.22) / 0.06, 0.0, 1.0) * 0.6
			var c: Color = Color(0.05, 0.045, 0.04).lerp(Color(0.62, 0.6, 0.56), metal)
			c = c.lerp(Color(0.02, 0.02, 0.02), rim * (1.0 - metal))
			image.set_pixel(x, y, Color(c.r, c.g, c.b, maxf(soot * 0.92, metal)))
	image.generate_mipmaps()
	_texture = ImageTexture.create_from_image(image)
	return _texture
