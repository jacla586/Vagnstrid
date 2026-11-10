class_name PlaceBanner
extends Control
## The name of the district or village the own tank drives into, shown for a while in
## the upper middle of the screen (with the wider place round it below, e.g. the suburb
## of a neighbourhood). Names from PlaceNamesData (data/maps/<map>_places.tres, OSM). A
## place must hold for `settle_s` before it shows, and the same name doesn't come back
## within `repeat_after_s`, so driving along a border doesn't flicker. Not while
## knocked out or in a mode break.

@export var views: PlayerViews
@export var font_size: int = 34
@export var sub_font_size: int = 18
@export var color: Color = Color(0.96, 0.94, 0.86, 1.0)
@export var sub_color: Color = Color(0.85, 0.85, 0.8, 1.0)
## Distance from the top of the screen (px), below the mode panels and notices.
@export var top_px: float = 240.0
## How often the tank's place is looked up (Hz).
@export var check_hz: float = 2.0
## A new place must hold this long before it shows (s).
@export var settle_s: float = 1.5
## Shown this long (s), fading in and out over fade_s.
@export var show_s: float = 4.0
@export var fade_s: float = 0.8
## The same place isn't shown again within this long (s).
@export var repeat_after_s: float = 90.0

var _data: PlaceNamesData
var _looked: bool = false
var _clock := PackedFloat32Array([0.0])
var _current: int = -1
var _candidate: int = -1
var _candidate_s: float = 0.0
var _shown_at: Dictionary = {}   # place index -> Time.get_ticks_msec() when shown
var _title: String = ""
var _sub: String = ""
var _left: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not _looked:
		_looked = true
		_data = PlaceNamesData.find_for_scene(get_tree().current_scene)
	if _data == null:
		set_process(false)
		return
	if _left > 0.0:
		_left -= delta
		var a: float = clampf(minf(_left, show_s - _left) / maxf(fade_s, 0.01), 0.0, 1.0)
		if absf(modulate.a - a) > 0.02 or _left <= 0.0:
			modulate.a = a if _left > 0.0 else 0.0
			queue_redraw()
	if Ticks.due(_clock, delta, check_hz):
		_check(1.0 / check_hz)


func _check(step: float) -> void:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == null or tank.is_knocked_out():
		_candidate = -1
		return
	var p := Vector2(tank.global_position.x, tank.global_position.z)
	var place: int = _data.place_at(p)
	if place == _current:
		_candidate = -1
		return
	if place != _candidate:
		_candidate = place
		_candidate_s = 0.0
		return
	_candidate_s += step
	if _candidate_s < settle_s:
		return
	_current = place
	_candidate = -1
	if place < 0 or _in_break():
		return
	var now: int = Time.get_ticks_msec()
	if _shown_at.has(place) and now - int(_shown_at[place]) < int(repeat_after_s * 1000.0):
		return
	_shown_at[place] = now
	_title = _data.names[place]
	var outer: int = _data.around(p, place)
	_sub = _data.names[outer] if outer >= 0 and _data.names[outer] != _title else ""
	_left = show_s
	modulate.a = 0.0
	queue_redraw()


func _in_break() -> bool:
	var mode: ThunderRoadMode = ThunderRoadMode.instance
	return mode != null and (mode.is_in_break() or mode.is_over())


func _draw() -> void:
	if _left <= 0.0 or _title == "":
		return
	var font: Font = get_theme_default_font()
	var cx: float = size.x * 0.5
	var y: float = top_px
	_text(font, Vector2(cx, y), _title, font_size, color)
	if _sub != "":
		_text(font, Vector2(cx, y + font_size * 0.5 + sub_font_size + 2.0), _sub, sub_font_size, sub_color)


func _text(font: Font, at: Vector2, line: String, px: int, c: Color) -> void:
	var w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var pos := Vector2(at.x - w * 0.5, at.y)
	draw_string_outline(font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, Color(0, 0, 0, 0.8))
	draw_string(font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, px, c)
