class_name KillcamPanel
extends Control
## While the own tank is knocked out by a gun round: the hit picture. The tank from
## above and from the side with every gun round that struck it this life (red
## penetration, yellow no penetration, grey ricochet; a line from where it came; the
## killing one big and ringed), and in words who, from how far, with what, and why it
## went through (HitRecord, Tank.get_hits_this_life). Gone on respawn.

const PART_SV: Dictionary = {"hull": "Skrov", "turret": "Torn"}
const FACE_SV: Dictionary = {"front": "front", "side": "sida", "rear": "bak", "roof": "tak"}
const MODULE_SV: Dictionary = {"engine": "motor", "fuel": "bränsletank",
		"track_left": "vänster band", "track_right": "höger band", "turret_ring": "tornkrans",
		"ammo": "ammunition", "driver": "förare", "gunner": "skytt"}
const MAX_LIST: int = 6

@export var views: PlayerViews
## Shown once the replay is over or skipped (null: as soon as the killcam isn't running).
@export var killcam: Killcam
@export var font_size: int = 16
@export var panel_width: float = 540.0
@export var icon_px: float = 150.0
@export var back_color: Color = Color(0.0, 0.0, 0.0, 0.55)
@export var outline_color: Color = Color(0.9, 0.9, 0.85, 0.7)
@export var text_color: Color = Color(0.92, 0.92, 0.88, 1.0)
@export var head_color: Color = Color(1.0, 0.45, 0.35, 1.0)
@export var pen_color: Color = Color(1.0, 0.25, 0.2, 1.0)
@export var nopen_color: Color = Color(1.0, 0.8, 0.25, 1.0)
@export var ricochet_color: Color = Color(0.7, 0.7, 0.7, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -panel_width * 0.5
	offset_right = panel_width * 0.5
	offset_top = -230.0
	offset_bottom = 230.0


func _process(_delta: float) -> void:
	var tank: Tank = views.get_tank() if views != null else null
	var replay_over: bool = killcam.has_played() if killcam != null else not views.is_killcam()
	visible = tank != null and tank.is_knocked_out() and tank.get_kill_record() != null \
			and replay_over
	if visible:
		queue_redraw()


func _draw() -> void:
	var tank: Tank = views.get_tank() if views != null else null
	var kill: HitRecord = tank.get_kill_record() if tank != null else null
	if kill == null:
		return
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), back_color)
	var y: float = font_size + 10.0
	_text(font, Vector2(12.0, y), "UTSLAGEN", head_color, font_size + 4)
	y += font_size + 10.0
	var who: String = kill.shooter_label if kill.shooter_label != "" else "okänd"
	_text(font, Vector2(12.0, y), "av %s · %d m · %s %d mm" % [who, roundi(kill.distance_m),
			kill.shell_name, roundi(kill.calibre_mm)], text_color, font_size)
	y += font_size + 6.0
	_text(font, Vector2(12.0, y), _why(kill), text_color, font_size)
	y += font_size + 6.0
	var what: String = _what(kill)
	if what != "":
		_text(font, Vector2(12.0, y), what, text_color, font_size)
		y += font_size + 6.0
	# Pictures: from above (forward up) and from the side (forward left).
	var top := Rect2(Vector2(12.0, y + 8.0), Vector2(icon_px * 0.8, icon_px * 1.25))
	var side := Rect2(Vector2(top.end.x + 24.0, y + 8.0 + icon_px * 0.35),
			Vector2(panel_width - top.end.x - 48.0, icon_px * 0.55))
	_draw_top(tank, kill, top)
	_draw_side(tank, kill, side)
	y = top.end.y + font_size + 12.0
	# Earlier hits, latest first.
	var hits: Array[HitRecord] = tank.get_hits_this_life()
	var shown: int = 0
	for i: int in range(hits.size() - 1, -1, -1):
		var r: HitRecord = hits[i]
		if shown >= MAX_LIST or y > size.y - 6.0:
			break
		var line: String = "%d:%02d  %s – %s" % [floori(r.time_s / 60.0), floori(fmod(r.time_s, 60.0)),
				_outcome(r), _zone(r)]
		_text(font, Vector2(12.0, y), line, _color(r) if r != kill else head_color, font_size - 2)
		y += font_size + 2.0
		shown += 1


## Zone, impact angle and outcome in words.
func _why(r: HitRecord) -> String:
	# Where and at what angle, and the outcome: no thickness or penetration figures.
	return "%s @ %d° – %s" % [_zone(r), roundi(r.angle_deg), _outcome(r)]


func _what(r: HitRecord) -> String:
	var parts: PackedStringArray = []
	for m: String in r.modules:
		parts.append(MODULE_SV.get(m, m))
	var line: String = ("Träffade: " + ", ".join(parts)) if not parts.is_empty() else ""
	if r.modules.has("ammo") and r.killed:
		line += " – ammunitionen sprang"
	elif r.set_fire and not r.killed:
		line += (" – " if line != "" else "") + "brand"
	return line


func _zone(r: HitRecord) -> String:
	return "%s %s" % [PART_SV.get(r.part, r.part), FACE_SV.get(r.face, r.face)]


func _outcome(r: HitRecord) -> String:
	match r.outcome:
		HitResult.Outcome.PENETRATION: return "genomslag"
		HitResult.Outcome.NO_PENETRATION: return "inget genomslag"
		HitResult.Outcome.RICOCHET: return "rikoschett"
	return "träff"


func _color(r: HitRecord) -> Color:
	match r.outcome:
		HitResult.Outcome.PENETRATION: return pen_color
		HitResult.Outcome.RICOCHET: return ricochet_color
	return nopen_color


func _draw_top(tank: Tank, kill: HitRecord, box: Rect2) -> void:
	var hull: Vector3 = tank.data.hull_size
	var s: float = minf(box.size.x / maxf(hull.x * 1.6, 0.1), box.size.y / maxf(hull.z * 1.1, 0.1))
	var c: Vector2 = box.get_center()
	var map := func(p: Vector3) -> Vector2: return c + Vector2(p.x, p.z) * s
	var half := Vector2(hull.x, hull.z) * 0.5 * s
	draw_rect(Rect2(c - half, half * 2.0), outline_color, false, 1.5)
	var turret_at: Vector3 = tank.get_turret_local_position()
	draw_arc(map.call(turret_at), tank.data.turret_radius_m * s, 0.0, TAU, 32, outline_color, 1.5, true)
	for r: HitRecord in tank.get_hits_this_life():
		var at: Vector2 = map.call(r.local_point)
		var from := Vector2(r.local_dir.x, r.local_dir.z)
		_hit_mark(at, from, r, r == kill)


func _draw_side(tank: Tank, kill: HitRecord, box: Rect2) -> void:
	var hull: Vector3 = tank.data.hull_size
	var height: float = hull.y + tank.data.turret_radius_m
	var s: float = minf(box.size.x / maxf(hull.z * 1.2, 0.1), box.size.y / maxf(height * 1.4, 0.1))
	var c: Vector2 = box.get_center()
	var map := func(p: Vector3) -> Vector2: return c + Vector2(p.z, -p.y) * s
	var half := Vector2(hull.z, hull.y) * 0.5 * s
	draw_rect(Rect2(c - half, half * 2.0), outline_color, false, 1.5)
	var turret_at: Vector3 = tank.get_turret_local_position()
	var tr: float = tank.data.turret_radius_m
	var turret_rect := Rect2(map.call(turret_at + Vector3(0.0, 0.0, -tr)) - Vector2(0.0, tr * 0.9 * s),
			Vector2(tr * 2.0 * s, tr * 0.9 * s))
	draw_rect(turret_rect, outline_color, false, 1.5)
	for r: HitRecord in tank.get_hits_this_life():
		var at: Vector2 = map.call(r.local_point)
		var from := Vector2(r.local_dir.z, -r.local_dir.y)
		_hit_mark(at, from, r, r == kill)


## A hit dot with a line back along where the round came from.
func _hit_mark(at: Vector2, dir: Vector2, r: HitRecord, is_kill: bool) -> void:
	var color: Color = _color(r)
	if dir.length() > 0.05:
		draw_line(at - dir.normalized() * (40.0 if is_kill else 22.0), at,
				Color(color, 0.8), 2.5 if is_kill else 1.5, true)
	draw_circle(at, 5.5 if is_kill else 3.5, color)
	if is_kill:
		draw_arc(at, 10.0, 0.0, TAU, 24, head_color, 2.0, true)


func _text(font: Font, at: Vector2, line: String, color: Color, fsize: int) -> void:
	draw_string_outline(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, panel_width - 20.0, fsize, 4,
			Color(0.0, 0.0, 0.0, 0.85))
	draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, panel_width - 20.0, fsize, color)
