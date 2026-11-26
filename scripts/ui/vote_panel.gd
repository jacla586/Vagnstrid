class_name VotePanel
extends CanvasLayer
## The dedicated server's vote for the next match (NetSession rpc_vote_open/state/close):
## every scenario as a button with its votes; a click votes (again to change). The time
## left counts down in the title and in a bar that empties. When it closes the winner
## stays highlighted (DedicatedServer.REVEAL_S) until the map change frees the panel.
## Frees the mouse while it shows.

const LAYER: int = 90
## Bar colour when time is nearly up, and from how many seconds left.
const HURRY_COLOR: Color = Color(0.9, 0.3, 0.25)
const HURRY_S: float = 5.0
## Fallback: gone this long after closing if no map change came.
const CLOSE_FALLBACK_S: float = 6.0

var _buttons: Array[Button] = []
var _labels: Array = []
var _counts: Array = []
var _mine: int = -1
var _left: float = 0.0
var _total: float = 1.0
var _closed: bool = false
var _title: Label
var _time: Label
var _bar: ProgressBar
var _bar_fill: StyleBoxFlat
var _list: VBoxContainer
var _shown_s: int = -1


func open(labels: Array, seconds: float, counts: Array, current: int) -> void:
	layer = LAYER
	_labels = labels
	_left = seconds
	_total = maxf(seconds, 0.01)
	var shade := ColorRect.new()
	shade.color = Color(MenuTheme.SHADE, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.theme = MenuTheme.get_theme()
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 520)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_box)
	MenuTheme.add_title(title_box, "VOTE FOR THE NEXT MATCH", 22)
	_title = title_box.get_child(0) as Label   # add_title: the label, then an accent bar
	_time = Label.new()
	_time.add_theme_font_size_override("font_size", 26)
	_time.add_theme_color_override("font_color", MenuTheme.TEXT)
	head.add_child(_time)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.custom_minimum_size = Vector2(0, 8)
	var back := StyleBoxFlat.new()
	back.bg_color = MenuTheme.FIELD
	_bar.add_theme_stylebox_override("background", back)
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.bg_color = MenuTheme.ACCENT
	_bar.add_theme_stylebox_override("fill", _bar_fill)
	box.add_child(_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	for i: int in labels.size():
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.pressed.connect(_vote.bind(i))
		_list.add_child(b)
		_buttons.append(b)
		if i == current:
			b.tooltip_text = "Just played"
	set_counts(counts)
	_update_clock()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_counts(counts: Array) -> void:
	_counts = counts
	for i: int in _buttons.size():
		var n: int = int(counts[i]) if i < counts.size() else 0
		_buttons[i].text = "%s%s" % [_labels[i], "   ·   %d" % n if n > 0 else ""]
		if not _closed:
			_buttons[i].set_pressed_no_signal(i == _mine)


## The vote is over: the winner stays highlighted, the rest dimmed, until the map change
## (NetSession.rpc_change_map) frees the panel.
func close(winner: String, index: int = -1) -> void:
	_closed = true
	_title.text = "NEXT: %s" % winner.to_upper()
	_time.text = ""
	_bar.visible = false
	for i: int in _buttons.size():
		var b: Button = _buttons[i]
		b.disabled = true
		var won: bool = i == index
		b.set_pressed_no_signal(won)
		b.modulate = Color.WHITE if won else Color(1.0, 1.0, 1.0, 0.35)
		if won:
			var lit := StyleBoxFlat.new()
			lit.bg_color = MenuTheme.ACCENT
			lit.set_corner_radius_all(4)
			lit.set_content_margin_all(8)
			for state: String in ["normal", "pressed", "disabled", "hover", "hover_pressed"]:
				b.add_theme_stylebox_override(state, lit)
			b.add_theme_color_override("font_disabled_color", Color.WHITE)
			b.text = "▶  " + b.text
			(_list.get_parent() as ScrollContainer).ensure_control_visible.call_deferred(b)
	get_tree().create_timer(CLOSE_FALLBACK_S).timeout.connect(queue_free)


func _vote(i: int) -> void:
	if _closed:
		return
	_mine = i
	set_counts(_counts)
	NetSession.instance.rpc_id(1, "rpc_vote", i)


func _process(delta: float) -> void:
	if _closed:
		return
	_left = maxf(_left - delta, 0.0)
	_update_clock()
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The bar every frame (it slides), the seconds and colour only when they change.
func _update_clock() -> void:
	_bar.value = _left / _total
	var s: int = ceili(_left)
	if s == _shown_s:
		return
	_shown_s = s
	_time.text = "%d s" % s
	var hurry: bool = _left <= HURRY_S
	_bar_fill.bg_color = HURRY_COLOR if hurry else MenuTheme.ACCENT
	_time.add_theme_color_override("font_color", HURRY_COLOR if hurry else MenuTheme.TEXT)
