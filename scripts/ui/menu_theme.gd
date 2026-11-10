class_name MenuTheme
extends RefCounted
## The look of the menus (main menu, later the garage): dark see-through fields, a
## warm accent for the main action, small muted captions. Built in code, once.

const ACCENT: Color = Color(0.86, 0.55, 0.22)
const ACCENT_HOVER: Color = Color(0.95, 0.64, 0.3)
const TEXT: Color = Color(0.93, 0.91, 0.86)
const MUTED: Color = Color(0.7, 0.68, 0.62)
const FIELD: Color = Color(0.06, 0.06, 0.07, 0.72)
const FIELD_HOVER: Color = Color(0.12, 0.12, 0.13, 0.82)
const EDGE: Color = Color(1.0, 1.0, 1.0, 0.14)

const BACKGROUND: String = "res://assets/ui/menu_background.jpg"
const SHADE: Color = Color(0.02, 0.02, 0.03)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _make()
	return _theme


## The menu picture (cropped to fill), with a shade over it: `side` darkens the left
## side for a column of text, else the whole picture by `amount`.
static func add_backdrop(parent: Control, side: bool, amount: float = 0.8) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	var picture := TextureRect.new()
	picture.texture = load(BACKGROUND)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(picture)
	if not side:
		var dim := ColorRect.new()
		dim.color = Color(SHADE, amount)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(dim)
		return
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.52])
	gradient.colors = PackedColorArray([Color(SHADE, 0.9), Color(SHADE, 0.72), Color(SHADE, 0.0)])
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = gradient
	shade_texture.width = 256
	shade_texture.height = 4
	var shade := TextureRect.new()
	shade.texture = shade_texture
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)


## A big spaced-out heading with a short accent bar under it.
static func add_title(box: Container, text: String, size: int) -> void:
	var title := Label.new()
	title.text = text
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.6
	font.spacing_glyph = maxi(size / 10, 2)
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", size)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(title)
	var bar := ColorRect.new()
	bar.color = ACCENT
	bar.custom_minimum_size = Vector2(52, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(bar)


## A caption above a field: small, muted, upper case.
static func caption(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", MUTED)
	return l


## The big button for the main action, in the accent colour.
static func make_primary(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(ACCENT, Color.TRANSPARENT))
	b.add_theme_stylebox_override("hover", _box(ACCENT_HOVER, Color.TRANSPARENT))
	b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.2), Color.TRANSPARENT))
	b.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, TEXT))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color(0.08, 0.06, 0.04))
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size.y = 40


static func _make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	var field := _box(FIELD, EDGE)
	var hover := _box(FIELD_HOVER, Color(1.0, 1.0, 1.0, 0.3))
	var pressed := _box(FIELD_HOVER, ACCENT)
	var focus := _box(Color.TRANSPARENT, Color(ACCENT, 0.8))
	for type: String in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("disabled", type, _box(Color(FIELD, 0.4), EDGE))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, TEXT)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.4))
	t.set_color("font_color", "Label", TEXT)
	# Check boxes and switches: no box behind them.
	var none := StyleBoxEmpty.new()
	for type: String in ["CheckBox", "CheckButton"]:
		for s: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_stylebox(s, type, none)
		t.set_color("font_color", type, MUTED)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
	# Panels and lists: the same dark glass as the fields.
	var panel := _box(FIELD, EDGE)
	panel.set_content_margin_all(12)
	t.set_stylebox("panel", "PanelContainer", panel)
	var list := _box(FIELD, EDGE)
	list.set_content_margin_all(4)
	t.set_stylebox("panel", "ItemList", list)
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	var row_hover := _box(Color(1.0, 1.0, 1.0, 0.06), Color.TRANSPARENT)
	var row_selected := _box(Color(ACCENT, 0.28), Color.TRANSPARENT)
	t.set_stylebox("hovered", "ItemList", row_hover)
	t.set_stylebox("selected", "ItemList", row_selected)
	t.set_stylebox("selected_focus", "ItemList", row_selected)
	t.set_stylebox("hovered_selected", "ItemList", row_selected)
	t.set_stylebox("hovered_selected_focus", "ItemList", row_selected)
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_hovered_color", "ItemList", Color.WHITE)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("guide_color", "ItemList", Color.TRANSPARENT)
	t.set_constant("v_separation", "ItemList", 6)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1.0, 1.0, 1.0, 0.1)
	track.set_corner_radius_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(1)
	t.set_stylebox("background", "ProgressBar", track)
	t.set_stylebox("fill", "ProgressBar", fill)
	var popup := _box(Color(0.08, 0.08, 0.09, 0.97), EDGE)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.35), Color.TRANSPARENT))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	return t


static func _box(fill: Color, edge: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.border_color = edge
	b.set_border_width_all(1 if edge.a > 0.0 else 0)
	b.set_corner_radius_all(3)
	b.content_margin_left = 10
	b.content_margin_right = 10
	b.content_margin_top = 5
	b.content_margin_bottom = 5
	return b
