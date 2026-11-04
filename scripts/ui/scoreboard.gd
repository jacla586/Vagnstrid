class_name Scoreboard
extends Control
## King of the Hill scoreboard: both teams' tanks with knock-outs, losses and points.
## Shown while the scoreboard key (Tab) is held, and for good when the match ends:
## then with the result, the mouse freed and buttons to play again (offline) or go
## back to the menu. Hidden when the scene has no KothMode.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const REFRESH_S: float = 0.5

@export var views: PlayerViews
@export var own_color: Color = Color(0.45, 0.85, 1.0, 1.0)
@export var enemy_color: Color = Color(1.0, 0.45, 0.35, 1.0)
@export var font_size: int = 18

var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _tables: HBoxContainer
var _buttons: HBoxContainer
var _refresh: float = 0.0
var _was_over: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.05, 0.88)
	style.set_content_margin_all(20)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	_title = _label("", 44, Color.WHITE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_subtitle = _label("", font_size + 4, Color.WHITE)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_subtitle)
	_tables = HBoxContainer.new()
	_tables.add_theme_constant_override("separation", 40)
	box.add_child(_tables)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 20)
	box.add_child(_buttons)
	if not NetRole.is_online():
		_button("Play again", func() -> void: get_tree().reload_current_scene())
	_button("Main menu", _on_menu)
	_buttons.visible = false
	visible = false


func _process(delta: float) -> void:
	var mode: KothMode = KothMode.instance
	var tank: Tank = views.get_tank() if views != null else null
	if mode == null or tank == null:
		visible = false
		return
	var over: bool = mode.is_over()
	var show: bool = over or Input.is_action_pressed("scoreboard")
	if over and not _was_over:
		_was_over = true
		_buttons.visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP   # clicks stay here, not recapturing
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh = 0.0
	if over and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if show and not visible:
		_refresh = 0.0
	visible = show
	if not show:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		_rebuild(mode, tank)


func _rebuild(mode: KothMode, tank: Tank) -> void:
	var own: int = roundi(mode.get_score(tank.team))
	var enemy: int = roundi(mode.get_best_other_score(tank.team))
	if mode.is_over():
		var winner: int = mode.get_winner()
		_title.text = "DRAW" if winner < 0 else ("VICTORY" if winner == tank.team else "DEFEAT")
		_title.add_theme_color_override("font_color",
				Color.WHITE if winner < 0 else (own_color if winner == tank.team else enemy_color))
		_title.visible = true
	else:
		_title.visible = false
	_subtitle.text = "%d  –  %d   (first to %d)" % [own, enemy, roundi(mode.data.score_to_win)]
	for child: Node in _tables.get_children():
		child.queue_free()
	var stats: Array = mode.get_stats()
	_tables.add_child(_table("Your team", stats, func(t: int) -> bool: return t == tank.team, own_color))
	_tables.add_child(_table("Enemy", stats, func(t: int) -> bool: return t != tank.team, enemy_color))


func _table(caption: String, stats: Array, include: Callable, color: Color) -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_child(_label(caption, font_size + 2, color))
	for h: String in ["KO", "Lost", "Points"]:
		grid.add_child(_label(h, font_size, Color(0.7, 0.7, 0.7)))
	for row: Array in stats:
		if not include.call(int(row[1])):
			continue
		grid.add_child(_label(String(row[0]), font_size, color))
		grid.add_child(_label("%d" % int(row[2]), font_size, Color.WHITE))
		grid.add_child(_label("%d" % int(row[3]), font_size, Color.WHITE))
		grid.add_child(_label("%d" % int(row[4]), font_size, Color.WHITE))
	return grid


func _on_menu() -> void:
	if NetRole.is_online():
		NetSession.instance.leave()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


func _label(t: String, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	return l


func _button(t: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(160, 40)
	b.pressed.connect(cb)
	_buttons.add_child(b)
