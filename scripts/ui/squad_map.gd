class_name SquadMap
extends MapView
## The squad orders map ("toggle_squad_map"): 1 km around the own tank, north up,
## with the ring the squad must stay inside (SquadData.max_distance_from_tank_m), the
## squad's soldiers and where they are going. While open the mouse is free and a
## "squad_order" click sends the squad there (PlayerController turns it into the
## tank's command). Opening it closes the big map, and the other way round.

## Emitted on a "squad_order" click on the map: the world point (x, z; y = 0).
signal squad_order_requested(point: Vector3)
## Emitted on a "squad_mine" click (right button): lay a mine there.
signal squad_mine_requested(point: Vector3)

## World distance across the map (m).
@export var view_range_m: float = 1000.0
## Share of the shorter screen side the map may use.
@export var screen_fraction: float = 0.8
@export var dim_color: Color = Color(0.0, 0.0, 0.0, 0.55)
@export var leash_color: Color = Color(0.55, 1.0, 0.45, 0.6)
@export var big_map: BigMap

var _open: bool = false
var _map_rect: Rect2 = Rect2()
var _map_centre: Vector2 = Vector2.ZERO
var _map_scale: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_squad_map"):
		set_open(not _open)
	elif _open and event is InputEventMouseButton and (event.is_action_pressed("squad_order")
			or event.is_action_pressed("squad_mine")):
		var at: Vector2 = (event as InputEventMouseButton).position
		if _map_rect.has_point(at):
			var world: Vector2 = _map_centre + (at - _map_rect.get_center()) / _map_scale
			if event.is_action_pressed("squad_mine"):
				squad_mine_requested.emit(Vector3(world.x, 0.0, world.y))
			else:
				squad_order_requested.emit(Vector3(world.x, 0.0, world.y))
		get_viewport().set_input_as_handled()   # not a click that captures the mouse


func is_open() -> bool:
	return _open


func set_open(open: bool) -> void:
	_open = open
	visible = open
	if open and big_map != null and big_map.is_open():
		big_map.set_open(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED


func _draw() -> void:
	var tank: Tank = get_tank()
	if tank == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), dim_color)
	var side: float = minf(size.x, size.y) * screen_fraction
	var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var centre := Vector2(tank.global_position.x, tank.global_position.z)
	var scale_px: float = side / view_range_m
	_map_rect = rect
	_map_centre = centre
	_map_scale = scale_px
	draw_map(rect, centre, scale_px)
	if tank.squad != null and is_instance_valid(tank.squad):
		var r: float = tank.squad.data.max_distance_from_tank_m * scale_px
		draw_arc(rect.get_center(), r, 0.0, TAU, 96, leash_color, 1.5, true)
	var font: Font = get_theme_default_font()
	var mines: String = ""
	if tank.squad != null and is_instance_valid(tank.squad) and tank.squad.data.mine != null:
		mines = "   right click: lay mine (%d)" % tank.squad.get_mines_carried()
	draw_string(font, Vector2(rect.get_center().x - 6.0, rect.position.y - 8.0), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 4, text_color)
	draw_string(font, Vector2(rect.position.x, rect.end.y + font_size + 6.0),
			"SQUAD ORDERS   click: send squad%s   [G] recall   [Q] close   grid %d m" % [mines, roundi(grid_step_m)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
