class_name DamagePanel
extends Control
## Own tank's damage, bottom left above the weapon status: a see-through top-down
## picture of the tank (hull forward = up) with the turret turned as it is on the hull
## and every module in its place, coloured green OK, yellow damaged, red destroyed;
## under it a structure bar and FIRE / REPAIRING 12 s / "stand still to repair".
## Enemy hp is never shown. Hidden in the debug view.

@export var views: PlayerViews
@export var font_size: int = 16
## The picture's height on screen (px, the hull's length); width follows the hull.
@export var icon_height_px: float = 130.0
@export var bar_width: float = 180.0
@export var ok_color: Color = Color(0.45, 0.85, 0.4, 0.9)
@export var damaged_color: Color = Color(1.0, 0.8, 0.25, 0.95)
@export var destroyed_color: Color = Color(1.0, 0.25, 0.2, 0.95)
@export var outline_color: Color = Color(0.9, 0.9, 0.85, 0.55)
@export var fill_color: Color = Color(0.0, 0.0, 0.0, 0.28)
## Modules are filled with their colour at this opacity (the outline is full).
@export_range(0.0, 1.0) var module_fill_alpha: float = 0.35
@export var bar_back_color: Color = Color(0.0, 0.0, 0.0, 0.5)
@export var bar_color: Color = Color(0.85, 0.85, 0.8, 0.9)
@export var text_color: Color = Color(0.9, 0.9, 0.85, 1.0)

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 24.0
	offset_right = 24.0 + maxf(bar_width, icon_height_px)
	offset_bottom = -88.0
	offset_top = offset_bottom - (icon_height_px + 22.0 + font_size + 8.0)


func _process(delta: float) -> void:
	_time += delta
	visible = views != null and not views.is_debug_view() and views.get_tank() != null
	queue_redraw()


func _draw() -> void:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == null:
		return
	var font: Font = get_theme_default_font()
	_draw_icon(tank)
	# structure bar (no number: a rough feel, not a hp counter)
	var bar := Rect2(0.0, icon_height_px + 10.0, bar_width, 8.0)
	draw_rect(bar, bar_back_color)
	draw_rect(Rect2(bar.position, Vector2(bar_width * tank.get_hp_fraction(), bar.size.y)), bar_color)
	# status line
	var line: String = ""
	var color: Color = text_color
	if tank.is_knocked_out():
		line = "KNOCKED OUT"
		color = destroyed_color
	elif tank.is_burning():
		line = "FIRE"
		color = Color(destroyed_color, 0.75 + 0.25 * sin(_time * 8.0))
	elif tank.needs_repair():
		var prefix: String = "TRACK THROWN – " if tank.is_immobilised() else ""
		if tank.get_repair_progress() > 0.0:
			line = prefix + ("REPAIRING %d s" % ceili(tank.get_repair_time_left())
					if tank.get_repair_time_left() > 0.0 else "REPAIRING HULL")
		else:
			line = prefix + "STAND STILL TO REPAIR"
			color = Color(text_color, 0.7)
		if tank.is_immobilised():
			color = damaged_color
	if line != "":
		var at := Vector2(0.0, bar.end.y + font_size + 4.0)
		draw_string_outline(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4,
				Color(0.0, 0.0, 0.0, 0.8))
		draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## The tank from above: hull, tracks and hull modules fixed, turret (with its modules
## and the gun) turned by the turret's yaw on the hull.
func _draw_icon(tank: Tank) -> void:
	var data: TankData = tank.data
	var length: float = maxf(data.hull_size.z, 0.1)
	var scale_px: float = icon_height_px / length
	var centre := Vector2(maxf(bar_width, icon_height_px) * 0.5, icon_height_px * 0.5)
	var half := Vector2(data.hull_size.x, data.hull_size.z) * 0.5 * scale_px
	var hull := Rect2(centre - half, half * 2.0)
	draw_rect(hull, fill_color)
	draw_rect(hull, outline_color, false, 1.5)
	var turret_modules: Array[ModuleData] = []
	if data.layout != null:
		for m: ModuleData in data.layout.modules:
			if m.frame == &"turret":
				turret_modules.append(m)
			elif m.id != &"turret_ring":
				var box := Rect2(centre + Vector2(m.center.x - m.size.x * 0.5, m.center.z - m.size.z * 0.5) * scale_px,
						Vector2(m.size.x, m.size.z) * scale_px)
				_draw_module(box, _state_color(tank, m.id))
	# Turret: the ring (its module colour), the turret on it, the gun and turret modules.
	var turret_at: Vector3 = tank.get_turret_local_position()
	var tc: Vector2 = centre + Vector2(turret_at.x, turret_at.z) * scale_px
	var yaw: float = tank.get_turret_yaw()
	var radius: float = data.turret_radius_m * scale_px
	draw_circle(tc, radius, Color(0.0, 0.0, 0.0, 0.35))
	draw_arc(tc, radius, 0.0, TAU, 32, outline_color, 1.5, true)
	if tank.has_module(&"turret_ring"):
		var ring: Color = _state_color(tank, &"turret_ring")
		draw_arc(tc, radius * 0.82, 0.0, TAU, 32, ring, 3.0, true)
	var gun_dir := Vector2(-sin(yaw), -cos(yaw))
	draw_line(tc + gun_dir * radius * 0.6, tc + gun_dir * (radius + data.gun_length_m * scale_px),
			outline_color, maxf(data.barrel_radius_m * 2.0 * scale_px, 2.5), true)
	for m: ModuleData in turret_modules:
		var corners := PackedVector2Array()
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var local := Vector3(m.center.x + c.x * m.size.x * 0.5, 0.0, m.center.z + c.y * m.size.z * 0.5)
			var hull_p: Vector3 = local.rotated(Vector3.UP, yaw)
			corners.append(tc + Vector2(hull_p.x, hull_p.z) * scale_px)
		var color: Color = _state_color(tank, m.id)
		draw_colored_polygon(corners, Color(color, module_fill_alpha))
		draw_polyline(corners + PackedVector2Array([corners[0]]), color, 1.5, true)


func _draw_module(box: Rect2, color: Color) -> void:
	draw_rect(box, Color(color, module_fill_alpha))
	draw_rect(box, color, false, 1.5)


func _state_color(tank: Tank, id: StringName) -> Color:
	match tank.get_module_state(id):
		TankDamage.State.DAMAGED: return damaged_color
		TankDamage.State.DESTROYED: return destroyed_color
	return ok_color
