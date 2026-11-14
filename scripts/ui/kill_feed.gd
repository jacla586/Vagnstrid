class_name KillFeed
extends VBoxContainer
## The kill feed above the minimap (bottom right): one line per knock-out,
## "<killer> <type>  →  <victim> <type>", the killer first (his squad's AT round: "Bazooka"
## for the type); own team's names in blue,
## the enemy's in red. Lines fade after line_s; at most max_lines.
## Entries are [killer name, killer type, killer team, victim name, victim type, victim
## team]: offline and on the host from every tank's Tank.eliminated (KillFeed.entry_of),
## on clients from the host (NetGame sends rpc_kill_feed; NetGame.on_kill_feed calls
## KillFeed.add_all). Knock-outs without a killer (abandoned) aren't shown.

const GROUP: StringName = &"kill_feed"

## Every line shown (ModeRadio's kill banter listens).
signal entry_added(entry: Array)

@export var views: PlayerViews
@export var font_size: int = 17
@export var max_lines: int = 5
@export var line_s: float = 9.0
@export var fade_s: float = 1.5
@export var own_color: Color = Color(0.45, 0.75, 1.0, 1.0)
@export var enemy_color: Color = Color(1.0, 0.4, 0.33, 1.0)
## Above the minimap: its margin + side + this gap (px from the bottom right).
@export var bottom_px: float = 24.0 + 240.0 + 10.0
@export var right_px: float = 24.0
@export var width_px: float = 520.0

var _connected: Dictionary = {}   # tank instance id -> true
var _ages: Array[float] = []


## Every kill feed in the tree (normally one, the player rig's) shows `entry`.
static func add_all(tree: SceneTree, entry: Array) -> void:
	for node: Node in tree.get_nodes_in_group(GROUP):
		(node as KillFeed).add_entry(entry)


## The entry for `victim` knocked out by `killer`.
static func entry_of(killer: Tank, victim: Tank) -> Array:
	var weapon: String = victim.get_kill_weapon()   # the killer's squad's AT round...
	return [killer.get_player_name(), weapon if weapon != "" else killer.get_type_name(), killer.team,
			victim.get_player_name(), victim.get_type_name(), victim.team]


func _ready() -> void:
	add_to_group(GROUP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_right = -right_px
	offset_bottom = -bottom_px
	offset_left = -right_px - width_px
	offset_top = -bottom_px - (font_size + 10) * max_lines
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_theme_constant_override("separation", 2)


func _process(delta: float) -> void:
	visible = views == null or not views.is_debug_view()
	if not NetRole.is_client() and Engine.get_process_frames() % 30 == 0:
		_connect_tanks()
	for i: int in range(_ages.size() - 1, -1, -1):
		_ages[i] += delta
		var line := get_child(i) as Control
		if _ages[i] >= line_s:
			_ages.remove_at(i)
			remove_child(line)
			line.queue_free()
		elif _ages[i] > line_s - fade_s:
			line.modulate.a = (line_s - _ages[i]) / fade_s


func add_entry(entry: Array) -> void:
	if entry.size() < 6:
		return
	var own: int = TeamLook.viewer_team
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.custom_minimum_size = Vector2(width_px, 0.0)
	line.add_theme_font_size_override("normal_font_size", font_size)
	line.add_theme_constant_override("outline_size", 6)
	line.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	line.text = "[right]%s  [color=#dddddd]→[/color]  %s[/right]" % [
			_who(String(entry[0]), String(entry[1]), int(entry[2]) == own),
			_who(String(entry[3]), String(entry[4]), int(entry[5]) == own)]
	add_child(line)
	_ages.append(0.0)
	entry_added.emit(entry)
	while _ages.size() > max_lines:
		_ages.remove_at(0)
		var oldest: Node = get_child(0)
		remove_child(oldest)
		oldest.queue_free()


func _who(player: String, type: String, own: bool) -> String:
	var c: Color = own_color if own else enemy_color
	return "[color=#%s]%s[/color] [color=#%s]%s[/color]" % [c.to_html(false),
			_escape(player), c.darkened(0.2).to_html(false), _escape(type)]


func _escape(t: String) -> String:
	return t.replace("[", "[lb]")


## Offline and host: hears every tank's knock-outs (tanks come and go: respawns, joins).
func _connect_tanks() -> void:
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or tank.net_puppet or _connected.has(tank.get_instance_id()):
			continue
		_connected[tank.get_instance_id()] = true
		tank.eliminated.connect(func(killer: Tank, _assists: Array[Tank]) -> void:
			if killer != null and is_instance_valid(killer) and is_instance_valid(tank):
				add_entry(entry_of(killer, tank)))
