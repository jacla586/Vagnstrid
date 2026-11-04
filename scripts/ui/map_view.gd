class_name MapView
extends Control
## Base for the minimap and the big map: draws the map picture (MapImageData for the
## current scene's terrain, or a plain background), a grid, the spot marks and the
## own tank, north up. Subclasses pick the centre and scale in _draw().

@export var views: PlayerViews
@export var spot_marks: SpotMarks
## Grid line spacing (m).
@export var grid_step_m: float = 250.0
@export var font_size: int = 16
@export var background_color: Color = Color(0.12, 0.16, 0.11, 0.85)
@export var border_color: Color = Color(0.0, 0.0, 0.0, 0.9)
@export var grid_color: Color = Color(1.0, 1.0, 1.0, 0.12)
@export var own_color: Color = Color(0.45, 0.85, 1.0, 1.0)
@export var mark_color: Color = Color(1.0, 0.15, 0.1, 1.0)
@export var mark_radius_px: float = 7.0
@export var text_color: Color = Color(0.9, 0.9, 0.85, 1.0)
## King of the Hill zone: open zone (edge, fill), the next zone during a gap (dashed),
## and the own team's spawn.
@export var zone_color: Color = Color(1.0, 0.85, 0.2, 0.9)
@export var zone_fill_color: Color = Color(1.0, 0.85, 0.2, 0.12)
@export var zone_next_color: Color = Color(1.0, 0.85, 0.2, 0.7)
@export var spawn_color: Color = Color(0.45, 0.85, 1.0, 0.8)
## Own team's infantry squads (dismounted), and the line to where they are going.
@export var squad_color: Color = Color(0.55, 1.0, 0.45, 1.0)
## Teammates' tanks (the own tank is drawn bigger in own_color).
@export var friend_color: Color = Color(0.3, 0.6, 1.0, 1.0)

var _map_image: MapImageData
var _map_looked_up: bool = false


func _enter_tree() -> void:
	# The map picture has mipmaps; use them when it is drawn smaller.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(_delta: float) -> void:
	if not _map_looked_up:
		_map_looked_up = true
		_map_image = MapImageData.find_for_scene(get_tree().current_scene)
	queue_redraw()


func get_tank() -> Tank:
	return views.get_tank() if views != null else null


## Draws the map inside `rect`, with world point `centre` (x, z) at the rect's
## centre and `scale_px` pixels per metre.
func draw_map(rect: Rect2, centre: Vector2, scale_px: float) -> void:
	draw_rect(rect, background_color)
	if _map_image != null and _map_image.texture != null:
		var world: Rect2 = _map_image.world_rect
		draw_texture_rect(_map_image.texture,
				Rect2(_to_screen(world.position, rect, centre, scale_px), world.size * scale_px),
				false)
	_draw_grid(rect, centre, scale_px)
	_draw_zone(rect, centre, scale_px)
	_draw_squads(rect, centre, scale_px)
	_draw_friends(rect, centre, scale_px)
	if spot_marks != null:
		for mark: SpotMarks.Mark in spot_marks.get_marks():
			var p: Vector2 = _to_screen(Vector2(mark.point.x, mark.point.z), rect, centre, scale_px)
			if not rect.grow(mark_radius_px).has_point(p):
				continue
			var color: Color = mark_color
			color.a *= spot_marks.get_alpha(mark)
			draw_arc(p, mark_radius_px, 0.0, TAU, 24, color, 2.0, true)
			draw_circle(p, 1.5, color)
	var tank: Tank = get_tank()
	if tank != null:
		var own := Vector2(tank.global_position.x, tank.global_position.z)
		var p: Vector2 = _to_screen(own, rect, centre, scale_px)
		if rect.has_point(p):
			_draw_tank(tank, p)
	draw_rect(rect, border_color, false, 2.0)


## The map area in world (x, z), or an empty rect without a map picture.
func get_map_world_rect() -> Rect2:
	return _map_image.world_rect if _map_image != null else Rect2()


func _to_screen(world: Vector2, rect: Rect2, centre: Vector2, scale_px: float) -> Vector2:
	return rect.get_center() + (world - centre) * scale_px


## Own team's dismounted squads: a dot (and a line to where it's going).
func _draw_squads(rect: Rect2, centre: Vector2, scale_px: float) -> void:
	var tank: Tank = get_tank()
	if tank == null:
		return
	for node: Node in get_tree().get_nodes_in_group("squads"):
		var squad := node as Squad
		if squad == null or not squad.is_out() or squad.get_team() != tank.team:
			continue
		var p: Vector2 = _to_screen(Vector2(squad.global_position.x, squad.global_position.z),
				rect, centre, scale_px)
		var g3: Vector3 = squad.get_goal()
		var g: Vector2 = _to_screen(Vector2(g3.x, g3.z), rect, centre, scale_px)
		if g.distance_to(p) > 2.0:
			var line_color: Color = squad_color
			line_color.a = 0.5
			draw_line(p, g, line_color, 1.0, true)
		if rect.has_point(p):
			draw_circle(p, 4.0, Color.BLACK)
			draw_circle(p, 3.0, squad_color)


## King of the Hill (if the scene has one): the open zone filled, or the announced next
## zone dashed during a gap; and a small square at the own team's spawn.
func _draw_zone(rect: Rect2, centre: Vector2, scale_px: float) -> void:
	var mode: KothMode = KothMode.instance
	if mode == null or mode.is_over():
		return
	var c3: Vector3 = mode.get_center()
	var p: Vector2 = _to_screen(Vector2(c3.x, c3.z), rect, centre, scale_px)
	var r: float = mode.get_radius() * scale_px
	if rect.grow(r).has_point(p):
		if mode.is_zone_open():
			draw_circle(p, r, zone_fill_color)
			draw_arc(p, r, 0.0, TAU, 96, zone_color, 2.0, true)
		else:
			var dashes: int = 48
			for i: int in dashes:
				if i % 2 == 0:
					draw_arc(p, r, TAU * i / dashes, TAU * (i + 1) / dashes, 4, zone_next_color, 2.0, true)
	var tank: Tank = get_tank()
	if tank != null:
		var s3: Vector3 = mode.get_spawn(tank.team).origin
		var s: Vector2 = _to_screen(Vector2(s3.x, s3.z), rect, centre, scale_px)
		if rect.has_point(s):
			draw_rect(Rect2(s - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), spawn_color, false, 2.0)


func _draw_grid(rect: Rect2, centre: Vector2, scale_px: float) -> void:
	var half: Vector2 = rect.size * 0.5 / scale_px
	var x: float = ceilf((centre.x - half.x) / grid_step_m) * grid_step_m
	while x <= centre.x + half.x:
		var sx: float = rect.get_center().x + (x - centre.x) * scale_px
		draw_line(Vector2(sx, rect.position.y), Vector2(sx, rect.end.y), grid_color, 1.0)
		x += grid_step_m
	var z: float = ceilf((centre.y - half.y) / grid_step_m) * grid_step_m
	while z <= centre.y + half.y:
		var sy: float = rect.get_center().y + (z - centre.y) * scale_px
		draw_line(Vector2(rect.position.x, sy), Vector2(rect.end.x, sy), grid_color, 1.0)
		z += grid_step_m


## Arrow along the hull heading, line along the gun.
## Teammates' tanks: small arrows with their gun line; knocked-out ones as a dim cross.
func _draw_friends(rect: Rect2, centre: Vector2, scale_px: float) -> void:
	var own: Tank = get_tank()
	if own == null:
		return
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var t := node as Tank
		if t == null or t == own or not is_instance_valid(t) or not Tank.is_friendly(own, t):
			continue
		var p: Vector2 = _to_screen(Vector2(t.global_position.x, t.global_position.z), rect, centre, scale_px)
		if not rect.has_point(p):
			continue
		if t.is_knocked_out():
			var dim: Color = friend_color
			dim.a = 0.45
			draw_line(p + Vector2(-4, -4), p + Vector2(4, 4), dim, 2.0, true)
			draw_line(p + Vector2(-4, 4), p + Vector2(4, -4), dim, 2.0, true)
			continue
		_draw_tank(t, p, friend_color, 0.7)


func _draw_tank(tank: Tank, at: Vector2, color: Color = Color(0, 0, 0, 0), size: float = 1.0) -> void:
	if color.a == 0.0:
		color = own_color
	var fwd3: Vector3 = -tank.global_basis.z
	var fwd := Vector2(fwd3.x, fwd3.z)
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector2.UP
	var side := Vector2(-fwd.y, fwd.x)
	var yaw: float = tank.get_turret_global_yaw()
	var gun := Vector2(-sin(yaw), -cos(yaw))
	draw_line(at, at + gun * 16.0 * size, color, 2.0, true)
	# Slim arrow with a notch at the back, so the heading reads at a glance.
	var points := PackedVector2Array([at + fwd * 10.0 * size, at + (-fwd * 6.0 + side * 5.0) * size,
			at - fwd * 2.5 * size, at + (-fwd * 6.0 - side * 5.0) * size])
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.BLACK, 1.0, true)
