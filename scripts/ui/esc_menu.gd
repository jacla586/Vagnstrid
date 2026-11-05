class_name EscMenu
extends Control
## Esc (release_mouse) frees the mouse and shows this small menu: back to the game,
## abandon the tank (stuck on a rock: it counts as a loss and respawns) or the main
## menu. The game goes on behind it. PlayerController turns "abandon" into the command.

signal abandon_requested

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"

@export var views: PlayerViews
@export var font_size: int = 20

var _panel: PanelContainer
var _abandon: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	_button(box, "Resume", func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		visible = false)
	_abandon = _button(box, "Abandon tank (respawn)", func() -> void:
		abandon_requested.emit()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		visible = false)
	_button(box, "Main menu", func() -> void:
		if NetRole.is_online():
			NetSession.instance.leave()
		else:
			get_tree().change_scene_to_file(MENU_SCENE))
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	# PlayerViews frees the mouse on the same key; this only shows the menu.
	if event.is_action_pressed("release_mouse"):
		visible = true


func _process(_delta: float) -> void:
	if visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		visible = false   # clicked back into the game
	if visible:
		var tank: Tank = views.get_tank() if views != null else null
		_abandon.disabled = tank == null or tank.is_knocked_out()


func _button(box: Container, caption: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = caption
	b.custom_minimum_size = Vector2(320, 44)
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(cb)
	box.add_child(b)
	return b
