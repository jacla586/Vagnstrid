class_name Minimap
extends MapView
## Square minimap in the bottom-right corner, north always up, centred on the
## player's tank. Top-left corner: the spot cooldown. Hidden while the big map is open.

## Side of the map on screen (px).
@export var size_px: float = 240.0
## Distance from the screen edges (px).
@export var margin_px: float = 24.0
## World distance across the map (m).
@export var view_range_m: float = 1500.0
@export var cooldown_color: Color = Color(1.0, 0.8, 0.45, 1.0)
@export var big_map: BigMap
@export var squad_map: SquadMap


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	# Anchored to the bottom-right corner, so it stays there when the window resizes.
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_right = -margin_px
	offset_bottom = -margin_px
	offset_left = -margin_px - size_px
	offset_top = -margin_px - size_px


func _process(delta: float) -> void:
	super(delta)
	visible = (big_map == null or not big_map.is_open()) and (squad_map == null or not squad_map.is_open())


func _draw() -> void:
	var tank: Tank = get_tank()
	if tank == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	draw_map(rect, Vector2(tank.global_position.x, tank.global_position.z),
			size.x / view_range_m)
	var font: Font = get_theme_default_font()
	_draw_text(font, Vector2(size.x * 0.5 - 5.0, font_size + 2.0), "N", font_size, text_color)
	_draw_text(font, Vector2(12.0, size.y - 8.0), "grid %d m" % roundi(grid_step_m),
			font_size - 4, Color(text_color, 0.8))
	var cooldown: float = tank.get_spot_cooldown_remaining()
	if cooldown > 0.0:
		_draw_text(font, Vector2(12.0, font_size + 6.0), "SPOT %.1f s" % cooldown,
				font_size - 2, cooldown_color)


func _draw_text(font: Font, at: Vector2, text: String, font_px: int, color: Color) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, 4,
			Color(0.0, 0.0, 0.0, 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, color)
