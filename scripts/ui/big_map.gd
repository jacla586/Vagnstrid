class_name BigMap
extends MapView
## The whole map, north up, opened and closed with "toggle_map". Shows the map
## picture, grid, spot marks and the own tank. Without a map picture it shows the
## area around the tank (fallback_range_m across). While open the mouse is free:
## "squad_order" (left click) on the map asks to send the infantry squad there.

## Emitted on a "squad_order" click on the map: the world point (x, z; y = 0).
signal squad_order_requested(point: Vector3)

## Share of the shorter screen side the map may use.
@export var screen_fraction: float = 0.88
@export var dim_color: Color = Color(0.0, 0.0, 0.0, 0.55)
@export var fallback_range_m: float = 4000.0

var _open: bool = false
## Where the map was last drawn, for turning clicks into world points.
var _map_rect: Rect2 = Rect2()
var _map_centre: Vector2 = Vector2.ZERO
var _map_scale: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		_open = not _open
		visible = _open
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _open else Input.MOUSE_MODE_CAPTURED
	elif _open and event.is_action_pressed("squad_order") and event is InputEventMouseButton:
		var at: Vector2 = (event as InputEventMouseButton).position
		if _map_rect.has_point(at):
			var world: Vector2 = _map_centre + (at - _map_rect.get_center()) / _map_scale
			squad_order_requested.emit(Vector3(world.x, 0.0, world.y))
		get_viewport().set_input_as_handled()   # not a click that captures the mouse


func is_open() -> bool:
	return _open


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), dim_color)
	var world: Rect2 = get_map_world_rect()
	if world.size.x <= 0.0 or world.size.y <= 0.0:
		var tank: Tank = get_tank()
		if tank == null:
			return
		var centre := Vector2(tank.global_position.x, tank.global_position.z)
		world = Rect2(centre - Vector2.ONE * fallback_range_m * 0.5,
				Vector2.ONE * fallback_range_m)
	var available: Vector2 = size * screen_fraction
	var scale_px: float = minf(available.x / world.size.x, available.y / world.size.y)
	var map_size: Vector2 = world.size * scale_px
	var rect := Rect2((size - map_size) * 0.5, map_size)
	_map_rect = rect
	_map_centre = world.get_center()
	_map_scale = scale_px
	draw_map(rect, world.get_center(), scale_px)
	var font: Font = get_theme_default_font()
	var top: Vector2 = Vector2(rect.get_center().x - 6.0, rect.position.y - 8.0)
	draw_string(font, top, "N", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 4, text_color)
	draw_string(font, Vector2(rect.position.x, rect.end.y + font_size + 6.0),
			"grid %d m   click: send squad   [G] recall squad   [M] close" % roundi(grid_step_m),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
