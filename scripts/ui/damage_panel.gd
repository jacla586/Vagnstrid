class_name DamagePanel
extends Control
## Own tank's damage, bottom left above the weapon status: structure bar, one box per
## module (green OK, yellow damaged, red destroyed), and FIRE / REPAIRING 12 s /
## "stand still to repair". Enemy hp is never shown. Hidden in the debug view.

const MODULES: Array[StringName] = [&"engine", &"fuel", &"track_left", &"track_right", &"turret_ring"]
const LABELS: Dictionary = {&"engine": "ENG", &"fuel": "FUEL", &"track_left": "L TRK",
		&"track_right": "R TRK", &"turret_ring": "RING"}

@export var views: PlayerViews
@export var font_size: int = 16
@export var bar_width: float = 260.0
@export var box_size: Vector2 = Vector2(50.0, 22.0)
@export var ok_color: Color = Color(0.45, 0.85, 0.4, 0.9)
@export var damaged_color: Color = Color(1.0, 0.8, 0.25, 0.95)
@export var destroyed_color: Color = Color(1.0, 0.25, 0.2, 0.95)
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
	offset_right = 24.0 + bar_width
	offset_top = -150.0
	offset_bottom = -60.0


func _process(delta: float) -> void:
	_time += delta
	visible = views != null and not views.is_debug_view() and views.get_tank() != null
	queue_redraw()


func _draw() -> void:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == null:
		return
	var font: Font = get_theme_default_font()
	# structure bar (no number: a rough feel, not a hp counter)
	var bar := Rect2(0.0, 0.0, bar_width, 8.0)
	draw_rect(bar, bar_back_color)
	draw_rect(Rect2(bar.position, Vector2(bar_width * tank.get_hp_fraction(), bar.size.y)), bar_color)
	# module boxes
	var x: float = 0.0
	for id: StringName in MODULES:
		if not tank.has_module(id):
			continue
		var color: Color = ok_color
		match tank.get_module_state(id):
			TankDamage.State.DAMAGED: color = damaged_color
			TankDamage.State.DESTROYED: color = destroyed_color
		var box := Rect2(x, 16.0, box_size.x, box_size.y)
		draw_rect(box, Color(color, 0.25))
		draw_rect(box, color, false, 2.0)
		var label: String = LABELS[id]
		var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 4).x
		draw_string(font, Vector2(x + (box.size.x - w) * 0.5, 16.0 + box_size.y * 0.5 + 5.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 4, color)
		x += box_size.x + 2.0
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
		if tank.get_repair_progress() > 0.0:
			line = "REPAIRING %d s" % ceili(tank.get_repair_time_left()) if tank.get_repair_time_left() > 0.0 \
					else "REPAIRING HULL"
		else:
			line = "STAND STILL TO REPAIR"
			color = Color(text_color, 0.7)
	if line != "":
		draw_string_outline(font, Vector2(0.0, 16.0 + box_size.y + font_size + 4.0), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.0, 0.0, 0.0, 0.8))
		draw_string(font, Vector2(0.0, 16.0 + box_size.y + font_size + 4.0), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
