class_name DeployScreen
extends Control
## The in-match deploy screen, UI only (MatchLobby and EscMenu drive it). Page BRIEFING:
## the game mode in a few lines and the two teams with who is on them, a Join button
## under each. Page TANKS: the tanks to choose from on the left, the chosen one turning
## on the right (TankPreview) with its strengths and weaknesses (TankSummary).

signal team_chosen(team: int)
signal tank_chosen(cfg: TankConfig)
signal leave_pressed
signal back_pressed

enum Page { BRIEFING, TANKS }
## Roster row kinds (MatchLobby.roster_rows, NetGame.roster).
enum Kind { PLAYER, CHOOSING, BOT }

const PANEL_WIDTH: float = 700.0
const LIST_WIDTH: float = 230.0
const TEAM_COLUMN_WIDTH: float = 300.0

var _briefing: Control
var _tanks: Control
var _title: Label
var _map_label: Label
var _rules: Label
var _team_headers: Array[Label] = []
var _team_lists: Array[VBoxContainer] = []
var _join_buttons: Array[Button] = []
var _others: Label
var _tank_note: Label
var _tank_list: ItemList
var _tank_name: Label
var _summary: VBoxContainer
var _preview: TankPreview
var _deploy: Button
var _back: Button
var _status: Label
var _configs: Array[TankConfig] = []
var _chosen: TankConfig


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MenuTheme.get_theme()
	_briefing = _build_briefing()
	add_child(_briefing)
	_tanks = _build_tanks()
	add_child(_tanks)
	show_page(Page.BRIEFING)


func show_page(page: Page) -> void:
	_briefing.visible = page == Page.BRIEFING
	_tanks.visible = page == Page.TANKS
	if page == Page.TANKS:
		set_busy("")


## The mode's name, the map's and the rules (one rule a line).
func set_briefing(title: String, map_name: String, rules: String) -> void:
	_title.text = title.to_upper()
	_map_label.text = map_name
	var lines: PackedStringArray = []
	for line: String in rules.split("\n", false):
		lines.append("•  " + line.strip_edges())
	_rules.text = "\n".join(lines)


## Team headers ("Team 1 (attacking)") and which teams may be joined.
func set_teams(labels: Array[String], joinable: Array[bool]) -> void:
	for i: int in 2:
		_team_headers[i].text = labels[i] if i < labels.size() else "Team %d" % (i + 1)
		_join_buttons[i].disabled = i >= joinable.size() or not joinable[i]


## Who is where: rows [team, name, kind, tank type].
func set_roster(rows: Array) -> void:
	var others: int = 0
	for i: int in 2:
		for child: Node in _team_lists[i].get_children():
			_team_lists[i].remove_child(child)
			child.queue_free()
	var bots: Array[int] = [0, 0]
	for row: Array in rows:
		var team: int = int(row[0])
		if team < 0 or team > 1:
			others += 1
			continue
		var kind: int = int(row[2])
		if kind == Kind.BOT:
			bots[team] += 1
			continue
		var l := Label.new()
		l.text = str(row[1]) + ("   (choosing a tank)" if kind == Kind.CHOOSING
				else "   %s" % str(row[3]) if str(row[3]) != "" else "")
		l.add_theme_font_size_override("font_size", 15)
		_team_lists[team].add_child(l)
	for i: int in 2:
		if bots[i] > 0:
			var l := Label.new()
			l.text = "Bot" if bots[i] == 1 else "%d bots" % bots[i]
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", MenuTheme.MUTED)
			_team_lists[i].add_child(l)
		if _team_lists[i].get_child_count() == 0:
			var l := Label.new()
			l.text = "Empty"
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", MenuTheme.MUTED)
			_team_lists[i].add_child(l)
	_others.text = "" if others == 0 else \
			"%d bot%s fight everyone" % [others, "" if others == 1 else "s"]


## The tank page: a line above the list (or ""), the confirm button's text and whether
## Back shows.
func set_tank_page(note: String, confirm: String, can_go_back: bool) -> void:
	_tank_note.text = note
	_tank_note.visible = note != ""
	_deploy.text = confirm
	_back.visible = can_go_back


## A waiting line under the buttons ("" = ready again).
func set_busy(text: String) -> void:
	_status.text = text
	_deploy.disabled = text != ""


# --- Layout -----------------------------------------------------------------------

func _build_briefing() -> Control:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(MenuTheme.SHADE, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	box.add_child(head)
	var title_box := VBoxContainer.new()
	head.add_child(title_box)
	MenuTheme.add_title(title_box, "", 28)
	_title = title_box.get_child(0) as Label
	_map_label = MenuTheme.caption("")
	head.add_child(_map_label)
	_rules = Label.new()
	_rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules.custom_minimum_size.x = PANEL_WIDTH - 44.0
	_rules.add_theme_font_size_override("font_size", 15)
	_rules.add_theme_color_override("font_color", MenuTheme.TEXT)
	box.add_child(_rules)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)
	box.add_child(MenuTheme.caption("Choose your team"))
	var teams := HBoxContainer.new()
	teams.add_theme_constant_override("separation", 24)
	teams.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(teams)
	for i: int in 2:
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(TEAM_COLUMN_WIDTH, 0)
		column.add_theme_constant_override("separation", 6)
		var header := Label.new()
		header.add_theme_font_size_override("font_size", 19)
		header.add_theme_color_override("font_color", MenuTheme.ACCENT)
		column.add_child(header)
		var list := VBoxContainer.new()
		list.custom_minimum_size.y = 130
		list.add_theme_constant_override("separation", 3)
		column.add_child(list)
		var join := Button.new()
		join.text = "Join team %d" % (i + 1)
		join.custom_minimum_size.y = 40
		MenuTheme.make_primary(join)
		join.pressed.connect(func() -> void: team_chosen.emit(i))
		column.add_child(join)
		teams.add_child(column)
		_team_headers.append(header)
		_team_lists.append(list)
		_join_buttons.append(join)
	_others = MenuTheme.caption("")
	box.add_child(_others)
	var leave := Button.new()
	leave.text = "Leave match"
	leave.flat = true
	leave.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	leave.add_theme_color_override("font_color", MenuTheme.MUTED)
	leave.pressed.connect(func() -> void: leave_pressed.emit())
	box.add_child(leave)
	return page


func _build_tanks() -> Control:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(MenuTheme.SHADE, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	page.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	left.add_theme_constant_override("separation", 9)
	row.add_child(left)
	MenuTheme.add_title(left, "CHOOSE TANK", 26)
	_tank_note = MenuTheme.caption("")
	_tank_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_tank_note)
	_tank_list = ItemList.new()
	_tank_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tank_list.add_theme_font_size_override("font_size", 17)
	_configs = TankConfigs.presets()
	for c: TankConfig in _configs:
		_tank_list.add_item(c.display_name)
	_tank_list.item_selected.connect(func(i: int) -> void: _show_tank(_configs[i]))
	_tank_list.item_activated.connect(func(i: int) -> void:
		_show_tank(_configs[i])
		if not _deploy.disabled:
			tank_chosen.emit(_chosen))
	left.add_child(_tank_list)
	_deploy = Button.new()
	_deploy.text = "Deploy"
	_deploy.custom_minimum_size.y = 44
	MenuTheme.make_primary(_deploy)
	_deploy.pressed.connect(func() -> void:
		if _chosen != null:
			tank_chosen.emit(_chosen))
	left.add_child(_deploy)
	_back = Button.new()
	_back.text = "Back"
	_back.pressed.connect(func() -> void: back_pressed.emit())
	left.add_child(_back)
	_status = MenuTheme.caption("")
	left.add_child(_status)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_preview = TankPreview.new()
	frame.add_child(_preview)
	var name_margin := MarginContainer.new()
	name_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top"]:
		name_margin.add_theme_constant_override("margin_" + side, 14)
	_tank_name = Label.new()
	_tank_name.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tank_name.add_theme_font_size_override("font_size", 28)
	_tank_name.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	name_margin.add_child(_tank_name)
	frame.add_child(name_margin)
	right.add_child(frame)
	_summary = VBoxContainer.new()
	_summary.add_theme_constant_override("separation", 8)
	right.add_child(_summary)

	var start: int = 0
	var selected: TankConfig = TankConfigs.get_selected()
	for i: int in _configs.size():
		if selected != null and _configs[i].resource_path == selected.resource_path:
			start = i
	if not _configs.is_empty():
		_tank_list.select(start)
		_show_tank(_configs[start])
	return page


func _show_tank(cfg: TankConfig) -> void:
	_chosen = cfg
	_tank_name.text = cfg.display_name
	TankSummary.fill(_summary, cfg, 17)
	_preview.show_tank(TankBuilder.build(cfg))
