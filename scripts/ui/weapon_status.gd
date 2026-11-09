class_name WeaponStatus
extends Label
## Bottom-left gun status: "AP – LOADED" or "HE – RELOADING 3.4 s", and the smoke
## salvos left ("SMOKE 2 (X)"). Hidden in the debug view.

@export var views: PlayerViews
@export var font_size: int = 22
@export var loaded_color: Color = Color(0.75, 1.0, 0.7, 1.0)
@export var reloading_color: Color = Color(1.0, 0.8, 0.45, 1.0)

## The colour shown: 1 loaded, 0 reloading, -1 none yet.
var _shown_loaded: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	position += Vector2(24.0, -48.0)
	add_theme_font_size_override("font_size", font_size)
	add_theme_constant_override("outline_size", 6)
	add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))


func _process(_delta: float) -> void:
	visible = views != null and not views.is_debug_view()
	if not visible:
		return
	var tank: Tank = views.get_tank()
	var shell: ShellData = tank.get_loaded_shell()
	var prefix: String = (shell.short_name + " – ") if shell != null else ""
	var smoke: String = "    SMOKE %d" % tank.get_smoke_left() if tank.data.smoke_salvos > 0 else ""
	var smoke_wait: float = tank.get_smoke_cooldown()
	if smoke != "" and smoke_wait > 0.0 and tank.get_smoke_left() > 0:
		smoke += " (%d s)" % ceili(smoke_wait)
	var loaded: bool = tank.is_loaded()
	text = prefix + ("LOADED" if loaded else "RELOADING %.1f s" % tank.get_reload_remaining()) + smoke
	# A theme override re-lays the label out even when unchanged: only on a change.
	if int(loaded) != _shown_loaded:
		_shown_loaded = int(loaded)
		add_theme_color_override("font_color", loaded_color if loaded else reloading_color)
