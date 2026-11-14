class_name VotePanel
extends CanvasLayer
## The dedicated server's vote for the next match (NetSession rpc_vote_open/state/close):
## every scenario as a button with its votes; a click votes (again to change), the time
## left counts down. Frees the mouse while it shows; the last pick shows when it closes.

const LAYER: int = 90

var _buttons: Array[Button] = []
var _labels: Array = []
var _counts: Array = []
var _mine: int = -1
var _left: float = 0.0
var _title: Label
var _list: VBoxContainer


func open(labels: Array, seconds: float, counts: Array, current: int) -> void:
	layer = LAYER
	_labels = labels
	_left = seconds
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
	MenuTheme.add_title(box, "VOTE FOR THE NEXT MATCH", 22)
	_title = box.get_child(box.get_child_count() - 1) as Label
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func set_counts(counts: Array) -> void:
	_counts = counts
	for i: int in _buttons.size():
		var n: int = int(counts[i]) if i < counts.size() else 0
		_buttons[i].text = "%s%s" % [_labels[i], "   ·   %d" % n if n > 0 else ""]
		_buttons[i].set_pressed_no_signal(i == _mine)


## The vote is over: the winner for a moment, then gone (the map change follows).
func close(winner: String) -> void:
	_list.visible = false
	if _title != null:
		_title.text = "NEXT: %s" % winner.to_upper()
	get_tree().create_timer(3.0).timeout.connect(queue_free)


func _vote(i: int) -> void:
	_mine = i
	set_counts(_counts)
	NetSession.instance.rpc_id(1, "rpc_vote", i)


func _process(delta: float) -> void:
	_left = maxf(_left - delta, 0.0)
	if _title != null and _list.visible:
		_title.text = "VOTE FOR THE NEXT MATCH   ·   %d s" % ceili(_left)
	if _list.visible and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
