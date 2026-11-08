class_name GunnerReticle
extends Control
## Gunner's sight reticle (range-ladder style):
## - thin crosshair lines and a small centre circle (where the gun points);
## - side scale in mrad for leading moving targets / wind;
## - range ladder below the centre: one mark per range step, placed at the shell's
##   drop for that range (from Ballistics), labelled in hundreds of metres;
## - a circle where the mouse wants the gun to go, and a warning while the hatch is open.
## Sizes are fractions of the screen height so the layout scales with resolution;
## angular positions use pixels per mrad at the current zoom.

const SIDE_TICK_MRAD: float = 4.0
const SIDE_LABEL_MRAD: float = 8.0
const SIDE_MAX_MRAD: float = 32.0
## Closest two ladder marks / centre ticks may be drawn (px); closer ones are skipped.
const MIN_MARK_SPACING_PX: float = 3.0

@export var views: PlayerViews
@export var reticle_color: Color = Color(0.03, 0.03, 0.03, 0.95)
@export var desired_aim_color: Color = Color(1.0, 1.0, 1.0, 0.8)
@export var warning_color: Color = Color(1.0, 0.35, 0.2, 1.0)

var _table_shell: ShellData
var _table_ranges: PackedFloat32Array = PackedFloat32Array()
var _table_drops_mrad: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Build the table at load (~50 ms) rather than on first entering the sight.
	if views != null:
		_update_range_table(views.get_tank_data(), views.get_tank().get_loaded_shell())


func _process(_delta: float) -> void:
	visible = views != null and views.is_gunner_view() and not views.is_killcam()
	if visible:
		queue_redraw()


func _draw() -> void:
	var camera: GunnerCamera = views.gunner_camera
	var data: TankData = views.get_tank_data()
	_update_range_table(data, views.get_tank().get_loaded_shell())

	var centre: Vector2 = size * 0.5
	var unit: float = size.y / 1080.0  # 1 px at 1080p
	var line_width: float = maxf(1.5 * unit, 1.0)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = maxi(int(20.0 * unit), 10)
	var px_per_mrad: float = (size.y * 0.5) / tan(deg_to_rad(camera.fov) * 0.5) * 0.001

	# Crosshair lines and centre circle.
	var circle_radius: float = 20.0 * unit
	draw_arc(centre, circle_radius, 0.0, TAU, 48, reticle_color, line_width, true)
	draw_line(Vector2(0.0, centre.y), Vector2(centre.x - circle_radius, centre.y), reticle_color, line_width)
	draw_line(Vector2(centre.x + circle_radius, centre.y), Vector2(size.x, centre.y), reticle_color, line_width)
	draw_line(Vector2(centre.x, 0.0), Vector2(centre.x, centre.y - circle_radius), reticle_color, line_width)
	draw_line(Vector2(centre.x, centre.y + circle_radius), Vector2(centre.x, size.y), reticle_color, line_width)

	_draw_side_scale(centre, unit, line_width, font, font_size, px_per_mrad)
	_draw_range_ladder(data, centre, unit, line_width, font, font_size, px_per_mrad, circle_radius)

	var desired: Vector2 = camera.get_desired_aim_screen_position()
	if desired.is_finite() and desired.distance_to(centre) > 3.0:
		draw_arc(desired, 9.0 * unit, 0.0, TAU, 24, desired_aim_color, line_width, true)

	if views.get_tank().is_commander_exposed():
		draw_string(font, Vector2(0.0, size.y * 0.95), "HATCH OPEN",
				HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, warning_color)


func _draw_side_scale(centre: Vector2, unit: float, line_width: float, font: Font,
		font_size: int, px_per_mrad: float) -> void:
	# Label every SIDE_LABEL_MRAD, doubled until the labels don't overlap.
	var label_step: float = SIDE_LABEL_MRAD
	var widest: float = font.get_string_size(str(int(SIDE_MAX_MRAD)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	while label_step * px_per_mrad < widest + 6.0 * unit and label_step < SIDE_MAX_MRAD:
		label_step *= 2.0
	var mrad: float = SIDE_TICK_MRAD
	while mrad <= SIDE_MAX_MRAD + 0.001:
		var is_long: bool = is_zero_approx(fmod(mrad, SIDE_LABEL_MRAD))
		var half: float = (9.0 if is_long else 5.0) * unit
		for side: float in [-1.0, 1.0]:
			var x: float = centre.x + side * mrad * px_per_mrad
			draw_line(Vector2(x, centre.y - half), Vector2(x, centre.y + half), reticle_color, line_width)
			if is_zero_approx(fmod(mrad, label_step)):
				var text: String = str(int(mrad))
				var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				draw_string(font, Vector2(x - text_width * 0.5, centre.y - 18.0 * unit), text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, reticle_color)
		mrad += SIDE_TICK_MRAD


func _draw_range_ladder(data: TankData, centre: Vector2, unit: float, line_width: float,
		font: Font, font_size: int, px_per_mrad: float, circle_radius: float) -> void:
	if _table_ranges.is_empty():
		return
	var ladder_right: float = centre.x - 255.0 * unit
	var long_left: float = centre.x - 332.0 * unit
	var short_left: float = centre.x - 315.0 * unit
	var label_right: float = long_left - 6.0 * unit
	# Marks are closest together at short range (drop grows faster than linearly),
	# so the first step decides how sparse marks and labels must be at this zoom.
	var first_step_px: float = _table_drops_mrad[0] * px_per_mrad
	var base_step: float = data.sight_range_step_m
	var mark_every: int = _nice_multiple(MIN_MARK_SPACING_PX / maxf(first_step_px, 0.001))
	var label_every: int = _nice_multiple(maxf(
			float(font_size) * 0.95 / maxf(first_step_px, 0.001),
			data.sight_range_label_step_m / base_step))
	label_every = maxi(label_every, mark_every)
	# Which shell the ladder is for, above its top end.
	if _table_shell != null:
		var name_width: float = font.get_string_size(_table_shell.short_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(ladder_right - name_width, centre.y - font_size * 0.6),
				_table_shell.short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, reticle_color)
	if label_every % mark_every != 0:
		label_every *= mark_every  # every labelled range must also be a drawn mark
	for i: int in _table_ranges.size():
		var index: int = i + 1  # range = index × step
		if index % mark_every != 0:
			continue
		var range_m: float = _table_ranges[i]
		var y: float = centre.y + _table_drops_mrad[i] * px_per_mrad
		if y > size.y:
			break
		var is_long: bool = index % label_every == 0
		draw_line(Vector2(long_left if is_long else short_left, y), Vector2(ladder_right, y),
				reticle_color, line_width)
		# Matching tick on the vertical line, outside the centre circle.
		if y - centre.y > circle_radius + 2.0 * unit:
			var half: float = (8.0 if is_long else 5.0) * unit
			draw_line(Vector2(centre.x - half, y), Vector2(centre.x + half, y), reticle_color, line_width)
		if is_long:
			var text: String = str(int(round(range_m / 100.0)))
			var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_string(font, Vector2(label_right - text_width, y + font_size * 0.35), text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, reticle_color)


## Smallest of 1, 2, 5, 10, 20, 50… that is at least `minimum`.
static func _nice_multiple(minimum: float) -> int:
	var magnitude: int = 1
	while true:
		for factor: int in [1, 2, 5]:
			if float(factor * magnitude) >= minimum:
				return factor * magnitude
		magnitude *= 10
	return 1


## Rebuilds the range → drop table when the loaded shell (or tank) changes.
func _update_range_table(data: TankData, shell: ShellData) -> void:
	if shell == _table_shell and not _table_ranges.is_empty():
		return
	_table_shell = shell
	_table_ranges.clear()
	_table_drops_mrad.clear()
	if _table_shell == null or data.sight_range_step_m <= 0.0:
		return
	var range_m: float = data.sight_range_step_m
	while range_m <= data.sight_range_max_m + 0.001:
		_table_ranges.append(range_m)
		_table_drops_mrad.append(Ballistics.superelevation_for_range(_table_shell, range_m) * 1000.0)
		range_m += data.sight_range_step_m
