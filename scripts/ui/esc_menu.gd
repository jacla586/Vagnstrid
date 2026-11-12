class_name EscMenu
extends Control
## Esc (release_mouse) frees the mouse and shows this small menu: back to the game,
## change tank (TankSwitch: a respawn at the spawn; a loss unless fresh from a spawn),
## switch team (online: takes a bot's place, else pick a player of the other team to
## ask; NetGame), answer a team swap request, abandon the tank (stuck on a rock: it
## counts as a loss and respawns) or the main menu. The game goes on behind it.
## PlayerController turns "abandon" into the command.

signal abandon_requested

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"

enum Page { MAIN, TANKS, SWAP }

@export var views: PlayerViews
@export var font_size: int = 20

var _panel: PanelContainer
var _box: VBoxContainer
var _page: Page = Page.MAIN
var _abandon: Button
var _tank: Tank
var _game: NetGame
## Swap offers shown on the main page (rebuilt when they change or run out).
var _shown_offers: int = -1
## The tank picker while the TANKS page is open.
var _picker: DeployScreen


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_box)
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	# PlayerViews frees the mouse on the same key; this only shows the menu.
	if event.is_action_pressed("release_mouse"):
		_page = Page.MAIN
		_build()
		visible = true


func _process(_delta: float) -> void:
	_connect_to_tank()
	_connect_to_game()
	if visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		visible = false   # clicked back into the game
	if not visible:
		return
	if _abandon != null:
		_abandon.disabled = _tank == null or _tank.is_knocked_out()
	if _page == Page.MAIN and _game != null and _game.get_swap_offers().size() != _shown_offers:
		_build()


# --- Pages -------------------------------------------------------------------------------

func _build() -> void:
	for child: Node in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_abandon = null
	if _picker != null:
		_picker.queue_free()
		_picker = null
	_panel.visible = true
	match _page:
		Page.MAIN: _build_main()
		Page.TANKS: _build_tanks()
		Page.SWAP: _build_swap()
	_panel.reset_size()


func _build_main() -> void:
	_button("Resume", _close)
	_shown_offers = 0
	if _game != null:
		var offers: Array = _game.get_swap_offers()
		_shown_offers = offers.size()
		for offer: Array in offers:
			var from_peer: int = int(offer[0])
			_label("%s wants to swap teams with you" % str(offer[1]))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			_box.add_child(row)
			_button("Accept", func() -> void: _answer(from_peer, true), row, 155)
			_button("Decline", func() -> void: _answer(from_peer, false), row, 155)
	_button("Change tank…", func() -> void: _go(Page.TANKS))
	if _game != null:
		_button("Switch team", func() -> void:
			_game.swap_choices = []
			_game.request_team_switch(0))
	_abandon = _button("Abandon tank (respawn)", func() -> void:
		abandon_requested.emit()
		_close())
	_button("Main menu", func() -> void:
		if NetRole.is_online():
			NetSession.instance.leave()
		else:
			get_tree().change_scene_to_file(MENU_SCENE))


## The tank picker (DeployScreen's tank page) over the game; the panel hides meanwhile.
func _build_tanks() -> void:
	var line: String = "You respawn at the spawn in the new tank."
	if _tank != null and _tank.is_knocked_out():
		line = "The new tank comes at your respawn."
	elif not TankSwitch.is_fresh(_tank):
		line = "You respawn at the spawn in the new tank. It counts as a loss, like abandoning."
	_panel.visible = false
	_picker = DeployScreen.new()
	add_child(_picker)
	_picker.set_tank_page(line, "Drive this tank", true)
	_picker.show_page(DeployScreen.Page.TANKS)
	_picker.tank_chosen.connect(_pick_tank)
	_picker.back_pressed.connect(func() -> void: _go(Page.MAIN))


func _build_swap() -> void:
	_label("No bot on the other team. Ask a player to swap:")
	for choice: Array in (_game.swap_choices if _game != null else []):
		var peer: int = int(choice[0])
		_button(str(choice[1]), func() -> void:
			_game.swap_choices = []
			_game.request_team_switch(peer)
			_close())
	_button("Back", func() -> void:
		if _game != null:
			_game.swap_choices = []
		_go(Page.MAIN))


func _go(page: Page) -> void:
	_page = page
	_build()


func _close() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null
		_panel.visible = true
	_page = Page.MAIN
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	visible = false


# --- Actions -----------------------------------------------------------------------------

func _pick_tank(cfg: TankConfig) -> void:
	_close()
	if _game != null:
		_game.change_tank(cfg)   # the host decides: now or at the next respawn
		return
	TankConfigs.select(cfg)
	if _tank == null or not TankSwitch.wants_other(_tank, cfg):
		TankSwitch.pending_offline = false
		return
	if not _tank.is_knocked_out():
		TankSwitch.pending_offline = false
		TankSwitch.count_change(_tank)
		TankSwitch.replace_offline(_tank, TankSwitch.offline_spawn_for(_tank))   # frees this rig
		return
	TankSwitch.pending_offline = true
	_notice("%s at the respawn" % cfg.display_name, 4.0)


func _answer(from_peer: int, accept: bool) -> void:
	if _game == null:
		return
	_game.answer_swap(from_peer, accept)
	var notice := get_parent().get_node_or_null("MatchNotice") as MatchNotice
	if notice != null:
		notice.show_text("", 0.0)
	if accept:
		_close()
	else:
		_build()


func _notice(text: String, seconds: float) -> void:
	var notice := get_parent().get_node_or_null("MatchNotice") as MatchNotice
	if notice != null:
		notice.show_text(text, seconds)


## Offline: back from a knock-out with another tank picked meanwhile: that one now.
func _on_repaired() -> void:
	if NetRole.is_online() or not TankSwitch.pending_offline:
		return
	TankSwitch.pending_offline = false
	if TankSwitch.wants_other(_tank, TankConfigs.get_selected()):
		TankSwitch.replace_offline.call_deferred(_tank, _tank.global_transform)


func _connect_to_tank() -> void:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == _tank:
		return
	if _tank != null and is_instance_valid(_tank) and _tank.repaired.is_connected(_on_repaired):
		_tank.repaired.disconnect(_on_repaired)
	_tank = tank
	if _tank != null:
		_tank.repaired.connect(_on_repaired)


func _connect_to_game() -> void:
	var game: NetGame = NetSession.instance.game if NetRole.is_online() else null
	if game == _game:
		return
	if _game != null and is_instance_valid(_game) and _game.menu_changed.is_connected(_on_menu_changed):
		_game.menu_changed.disconnect(_on_menu_changed)
	_game = game
	if _game != null:
		_game.menu_changed.connect(_on_menu_changed)
	if visible:
		_build()


## Swap choices came (open that page) or the offers changed.
func _on_menu_changed() -> void:
	if _game != null and not _game.swap_choices.is_empty() and _page != Page.SWAP:
		_page = Page.SWAP
		visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_build()
	elif visible:
		_build()


func _button(caption: String, cb: Callable, parent: Container = null, width: int = 320) -> Button:
	var b := Button.new()
	b.text = caption
	b.custom_minimum_size = Vector2(width, 44)
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(cb)
	(parent if parent != null else _box).add_child(b)
	return b


func _label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(320, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size - 2)
	_box.add_child(l)
