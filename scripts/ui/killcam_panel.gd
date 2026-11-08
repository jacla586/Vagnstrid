class_name KillcamPanel
extends Control
## While the own tank is knocked out by a gun round: the hit picture. The tank's own
## model (its TankData, turret and gun as they were) rendered from above and from the
## side in two small viewports of their own world, with every gun round that struck
## it this life on top (red penetration, yellow no penetration, grey ricochet; a line
## from where it came; the killing one big and ringed), and in words who, from how
## far, with what, and why it went through (HitRecord, Tank.get_hits_this_life).
## English text. Gone on respawn.

const TANK_SCENE: PackedScene = preload("res://scenes/tank/tank.tscn")
const PART_EN: Dictionary = {"hull": "Hull", "turret": "Turret"}
const MODULE_EN: Dictionary = {"engine": "engine", "fuel": "fuel tank",
		"track_left": "left track", "track_right": "right track", "turret_ring": "turret ring",
		"ammo": "ammunition", "driver": "driver", "gunner": "gunner"}
const MAX_LIST: int = 6
## Viewport pixels per panel pixel (sharper pictures).
const RENDER_SCALE: float = 2.0
## Room round the model in the pictures (share of its size).
const MARGIN: float = 1.12

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

var _world: World3D
var _top_vp: SubViewport
var _side_vp: SubViewport
var _top_cam: Camera3D
var _side_cam: Camera3D
var _model: Node3D
## The kill the model was built for (rebuilt for the next one).
var _model_kill: HitRecord


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
	if visible and tank.get_kill_record() != _model_kill:
		_build_model(tank)
	var mode: SubViewport.UpdateMode = SubViewport.UPDATE_ALWAYS if visible \
			else SubViewport.UPDATE_DISABLED
	if _top_vp != null and _top_vp.render_target_update_mode != mode:
		_top_vp.render_target_update_mode = mode
		_side_vp.render_target_update_mode = mode
	if visible:
		queue_redraw()


# --- The pictures --------------------------------------------------------------------

## Top (forward up) and side (forward left) rects, below the text starting at `y`.
func _picture_rects(y: float) -> Array[Rect2]:
	var top := Rect2(Vector2(12.0, y + 8.0), Vector2(icon_px * 0.8, icon_px * 1.25))
	var side_h: float = icon_px * 0.7
	var side := Rect2(Vector2(top.end.x + 24.0, top.get_center().y - side_h * 0.5),
			Vector2(panel_width - top.end.x - 48.0, side_h))
	return [top, side]


func _make_viewports() -> void:
	_world = World3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.66)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_world.environment = env
	var rects: Array[Rect2] = _picture_rects(0.0)
	_top_vp = _make_viewport(rects[0].size)
	_side_vp = _make_viewport(rects[1].size)
	_top_cam = _make_camera(_top_vp)
	_side_cam = _make_camera(_side_vp)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.1
	_top_vp.add_child(sun)


func _make_viewport(px: Vector2) -> SubViewport:
	var vp := SubViewport.new()
	vp.world_3d = _world
	vp.size = Vector2i(roundi(px.x * RENDER_SCALE), roundi(px.y * RENDER_SCALE))
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	return vp


func _make_camera(vp: SubViewport) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.05
	cam.far = 100.0
	vp.add_child(cam)
	cam.current = true
	return cam


## A copy of the tank's look (as the garage builds it), turret and gun as they were,
## in the own team's colours; the cameras framed on it. Tank frame = world here.
func _build_model(tank: Tank) -> void:
	_model_kill = tank.get_kill_record()
	if _top_vp == null:
		_make_viewports()
	if _model != null:
		_model.free()
	var copy: Tank = TANK_SCENE.instantiate()
	copy.data = tank.data
	copy.apply_geometry()
	_model = copy.get_node("Visual")
	_model.get_node("Turret/Cupola/CommanderHitbox").free()
	copy.remove_child(_model)
	copy.free()
	_top_vp.add_child(_model)
	(_model.get_node("Turret") as Node3D).rotation.y = tank.get_turret_yaw()
	(_model.get_node("Turret/GunPivot") as Node3D).rotation.x = tank.get_gun_pitch()
	Tank.paint_visual(_model, true)
	var box: AABB = _model_bounds()
	var c: Vector3 = box.get_center()
	var top_aspect: float = float(_top_vp.size.x) / float(_top_vp.size.y)
	_top_cam.size = maxf(box.size.z, box.size.x / top_aspect) * MARGIN
	_top_cam.look_at_from_position(Vector3(c.x, box.end.y + 20.0, c.z), c, Vector3.FORWARD)
	var side_aspect: float = float(_side_vp.size.x) / float(_side_vp.size.y)
	_side_cam.size = maxf(box.size.y, box.size.z / side_aspect) * MARGIN
	_side_cam.look_at_from_position(Vector3(box.position.x - 20.0, c.y, c.z), c, Vector3.UP)


func _model_bounds() -> AABB:
	var box := AABB()
	var first: bool = true
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var b: AABB = _model.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Tank-frame point -> panel point in `rect`, through `cam` of `vp`.
func _project(vp: SubViewport, cam: Camera3D, rect: Rect2, p: Vector3) -> Vector2:
	return rect.position + cam.unproject_position(p) * rect.size / Vector2(vp.size)


func _draw() -> void:
	var tank: Tank = views.get_tank() if views != null else null
	var kill: HitRecord = tank.get_kill_record() if tank != null else null
	if kill == null:
		return
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), back_color)
	var y: float = font_size + 10.0
	_text(font, Vector2(12.0, y), "KNOCKED OUT", head_color, font_size + 4)
	y += font_size + 10.0
	var who: String = kill.shooter_label if kill.shooter_label != "" else "unknown"
	_text(font, Vector2(12.0, y), "by %s · %d m · %s %d mm" % [who, roundi(kill.distance_m),
			kill.shell_name, roundi(kill.calibre_mm)], text_color, font_size)
	y += font_size + 6.0
	_text(font, Vector2(12.0, y), _why(kill), text_color, font_size)
	y += font_size + 6.0
	var what: String = _what(kill)
	if what != "":
		_text(font, Vector2(12.0, y), what, text_color, font_size)
		y += font_size + 6.0
	# Pictures: from above (forward up) and from the side (forward left).
	var rects: Array[Rect2] = _picture_rects(y)
	var top: Rect2 = rects[0]
	if _top_vp != null:
		_draw_picture(tank, kill, rects[0], _top_vp, _top_cam)
		_draw_picture(tank, kill, rects[1], _side_vp, _side_cam)
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
		parts.append(MODULE_EN.get(m, m))
	var line: String = ("Damaged: " + ", ".join(parts)) if not parts.is_empty() else ""
	if r.modules.has("ammo") and r.killed:
		line += " – ammunition exploded"
	elif r.set_fire and not r.killed:
		line += (" – " if line != "" else "") + "set on fire"
	return line


func _zone(r: HitRecord) -> String:
	return "%s %s" % [PART_EN.get(r.part, r.part), r.face]


func _outcome(r: HitRecord) -> String:
	match r.outcome:
		HitResult.Outcome.PENETRATION: return "penetration"
		HitResult.Outcome.NO_PENETRATION: return "no penetration"
		HitResult.Outcome.RICOCHET: return "ricochet"
	return "hit"


func _color(r: HitRecord) -> Color:
	match r.outcome:
		HitResult.Outcome.PENETRATION: return pen_color
		HitResult.Outcome.RICOCHET: return ricochet_color
	return nopen_color


## The rendered model in `rect` with this life's hits on it.
func _draw_picture(tank: Tank, kill: HitRecord, rect: Rect2, vp: SubViewport, cam: Camera3D) -> void:
	draw_texture_rect(vp.get_texture(), rect, false)
	for r: HitRecord in tank.get_hits_this_life():
		var at: Vector2 = _project(vp, cam, rect, r.local_point)
		var dir: Vector2 = _project(vp, cam, rect, r.local_point + r.local_dir) - at
		_hit_mark(at, dir, r, r == kill)


## A hit dot with a line back along where the round came from.
func _hit_mark(at: Vector2, dir: Vector2, r: HitRecord, is_kill: bool) -> void:
	var color: Color = _color(r)
	if dir.length() > 1.5:
		draw_line(at - dir.normalized() * (40.0 if is_kill else 22.0), at,
				Color(color, 0.8), 2.5 if is_kill else 1.5, true)
	draw_circle(at, 5.5 if is_kill else 3.5, color)
	if is_kill:
		draw_arc(at, 10.0, 0.0, TAU, 24, head_color, 2.0, true)


func _text(font: Font, at: Vector2, line: String, color: Color, fsize: int) -> void:
	draw_string_outline(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, panel_width - 20.0, fsize, 4,
			Color(0.0, 0.0, 0.0, 0.85))
	draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, panel_width - 20.0, fsize, color)
