class_name SquadPanel
extends Label
## Bottom-left infantry squad status, above the gun status: soldiers left, AT rounds,
## smoke, and what the squad is doing (on the tank, out, coming back, refilling,
## wiped out with the time until a new squad). Hidden without a squad.

@export var views: PlayerViews
@export var font_size: int = 18
@export var ok_color: Color = Color(0.7, 1.0, 0.65, 1.0)
@export var warn_color: Color = Color(1.0, 0.75, 0.4, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	position += Vector2(24.0, -84.0)
	add_theme_font_size_override("font_size", font_size)
	add_theme_constant_override("outline_size", 6)
	add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))


func _process(_delta: float) -> void:
	var tank: Tank = views.get_tank() if views != null else null
	var squad: Squad = tank.squad if tank != null else null
	visible = squad != null and is_instance_valid(squad) and not views.is_debug_view()
	if not visible:
		return
	var count: int = squad.data.soldier_count
	var alive: int = squad.get_alive_count()
	var men: String = "●".repeat(alive) + "○".repeat(count - alive)
	var doing: String
	match squad.get_state():
		Squad.State.MOUNTED:
			var refill: float = squad.get_refill_time_left()
			doing = "ON TANK" if refill <= 0.0 else "REFILLING %d s" % ceili(refill)
		Squad.State.MOVING:
			doing = "MOVING"
		Squad.State.HOLDING:
			doing = "HOLDING"
		Squad.State.RETURNING:
			doing = "COMING BACK"
		Squad.State.WIPED:
			doing = "WIPED OUT – new squad in %d s" % ceili(squad.get_wipe_time_left())
	var where: String = ""
	if squad.is_out():
		where = "  %d m" % roundi(Squad._flat(squad.global_position - tank.global_position).length())
	text = "SQUAD %s  AT %d  SMOKE %d  %s%s" % [men, squad.get_at_rounds_left(),
			squad.get_smoke_left(), doing, where]
	add_theme_color_override("font_color", warn_color if squad.get_state() == Squad.State.WIPED
			or alive < count else ok_color)
