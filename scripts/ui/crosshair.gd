class_name Crosshair
extends Control
## Small dot at the screen centre showing where the player is aiming.
## Hidden in the gunner's sight, which has its own reticle.

@export var radius: float = 3.0
@export var color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.6)
@export var views: PlayerViews


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(_delta: float) -> void:
	visible = views == null or (not views.is_gunner_view() and not views.is_killcam())


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	draw_circle(centre, radius + 1.0, outline_color)
	draw_circle(centre, radius, color)
