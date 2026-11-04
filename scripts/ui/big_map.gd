class_name BigMap
extends MapView
## The whole map, north up, opened and closed with "toggle_map". Shows the map
## picture, grid, spot marks and the own tank. Without a map picture it shows the
## area around the tank (fallback_range_m across). The mouse is free while it is open.
## Opening it closes the squad orders map (SquadMap), and the other way round.

## Share of the shorter screen side the map may use.
@export var screen_fraction: float = 0.88
@export var dim_color: Color = Color(0.0, 0.0, 0.0, 0.55)
@export var fallback_range_m: float = 4000.0
@export var squad_map: SquadMap

var _open: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		set_open(not _open)


func set_open(open: bool) -> void:
	_open = open
	visible = open
	if open and squad_map != null and squad_map.is_open():
		squad_map.set_open(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


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
	draw_map(rect, world.get_center(), scale_px)
	var font: Font = get_theme_default_font()
	var top: Vector2 = Vector2(rect.get_center().x - 6.0, rect.position.y - 8.0)
	draw_string(font, top, "N", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 4, text_color)
	draw_string(font, Vector2(rect.position.x, rect.end.y + font_size + 6.0),
			"grid %d m   [M] close   [Q] squad orders" % roundi(grid_step_m),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
