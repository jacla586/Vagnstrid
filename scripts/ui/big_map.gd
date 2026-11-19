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
## Mouse wheel zoom (about the cursor) up to this many times the whole map, this
## factor per notch; drag with a mouse button to move a zoomed map.
@export var max_zoom: float = 8.0
@export var zoom_step: float = 1.25

var _open: bool = false
var _zoom: float = 1.0
## World point (x, z) at the map's centre while zoomed.
var _centre: Vector2 = Vector2.ZERO
var _dragging: bool = false
## Last draw: the map's rect on screen and its pixels per metre.
var _rect: Rect2 = Rect2()
var _scale: float = 1.0
var _panel: MapPanel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_panel = MapPanel.make_for(self)


## Mouse buttons belong to the open map: before the sight's zoom (wheel) or PlayerViews
## (which captures the mouse on any button).
func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion and _dragging:
		_centre -= (event as InputEventMouseMotion).relative / _scale
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	get_viewport().set_input_as_handled()
	if button.button_index != MOUSE_BUTTON_WHEEL_UP and button.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		_dragging = button.pressed and _zoom > 1.0
		return
	if not button.pressed or not _rect.has_point(button.position):
		return
	var factor: float = zoom_step if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / zoom_step
	var zoom: float = clampf(_zoom * factor, 1.0, max_zoom)
	var from_centre: Vector2 = button.position - _rect.get_center()
	var under: Vector2 = _centre + from_centre / _scale   # stays under the cursor
	var new_scale: float = _scale * zoom / _zoom
	_zoom = zoom
	_centre = under - from_centre / new_scale
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		set_open(not _open)


func set_open(open: bool) -> void:
	_open = open
	visible = open
	_dragging = false
	if open:
		_zoom = 1.0
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
	var fit: float = minf(available.x / world.size.x, available.y / world.size.y)
	var map_size: Vector2 = world.size * fit
	var rect := Rect2((size - map_size) * 0.5, map_size)
	var scale_px: float = fit * _zoom
	if _zoom <= 1.0:
		_centre = world.get_center()
	# A zoomed view stays on the map.
	var half: Vector2 = rect.size * 0.5 / scale_px
	_centre = _centre.clamp(world.position + half, world.end - half)
	_rect = rect
	_scale = scale_px
	_panel.position = rect.position
	_panel.size = rect.size
	_panel.centre = _centre
	_panel.scale_px = scale_px
	_panel.queue_redraw()
	var font: Font = get_theme_default_font()
	var top: Vector2 = Vector2(rect.get_center().x - 6.0, rect.position.y - 8.0)
	draw_string(font, top, "N", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size + 4, text_color)
	draw_string(font, Vector2(rect.position.x, rect.end.y + font_size + 6.0),
			"grid %d m   wheel: zoom, drag: move   [M] close   [Q] squad orders" % roundi(grid_step_m),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
