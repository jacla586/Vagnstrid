extends SceneTree
## Records one scripted trailer shot. Use tools/trailer/record.sh, which runs:
##   godot --path . --disable-vsync --fixed-fps 60 --resolution 1920x1080 \
##       --write-movie <dir>/frame.png --script res://tools/trailer/trailer.gd -- <shot> [key=value ...]
## <shot> is a script in tools/trailer/shots/ (extends trailer_shot.gd). Options:
##   weather=<preset>  overrides the shot's weather
##   hud=1             keeps the whole HUD (default: only the optics: sight, periscope, binoculars)
##   cam=<name>        a shot's camera variant, if it has any
##   map=<map>         another map, for shots that find their own spot
##   size=<W>x<H>      film size (default 1920x1080)
##   max_t=<s>         stops a shot that runs away (default 90 s)
##   snap=1 / snap=all a JPG in renders/trailer/snaps/ at every cue / every half second
## The screen is black while the map loads and the actors settle (SETTLE_FRAMES); the cue list (printed and written next to the
## frames as cues.txt) says from which second the action runs.

const SHOTS_DIR: String = "res://tools/trailer/shots/%s.gd"
const RIG_SCENE: String = "res://scenes/player/player_rig.tscn"
## Frames the map gets to settle (trees, ground cover, shaders) before the shot's setup.
const LOAD_FRAMES: int = 200
## Frames between the setup and the action, still black: spawned tanks drop onto their
## springs and settle, soldiers snap into place (it showed as a jolt at the start).
const SETTLE_FRAMES: int = 120
## HUD nodes that stay visible without hud=1: the optics themselves.
const KEEP_HUD: Array[String] = ["RainGlass", "OpticsDirt", "ViewOverlay", "FireHaze", "GunnerReticle"]

var _shot: Node
var _frame: int = 0
var _options: Dictionary = {}
var _black: ColorRect
var _out_dir: String = ""


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("trailer: give a shot name (tools/trailer/shots/<name>.gd)")
		quit(1)
		return
	for i: int in range(1, args.size()):
		var kv: PackedStringArray = args[i].split("=", true, 1)
		_options[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var script: GDScript = load(SHOTS_DIR % args[0])
	if script == null:
		push_error("trailer: no shot %s" % args[0])
		quit(1)
		return
	_shot = script.new()
	_shot.name = "TrailerShot"
	_shot.set("options", _options)
	_out_dir = _options.get("out", "")
	# The project's window is 1152x648; the film is 1920x1080 (size=WxH to change).
	var wh: PackedStringArray = String(_options.get("size", "1920x1080")).split("x")
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	var weather: String = _options.get("weather", _shot.get("weather"))
	Weather.set_current(Weather.load_preset(weather))
	randomize()
	seed(int(_options.get("seed", "1")))
	_shot.set("map", _options.get("map", _shot.get("map")))
	change_scene_to_file("res://scenes/maps/%s.tscn" % _shot.get("map"))
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.add_child(_black)
	root.add_child.call_deferred(layer)


func _process(_delta: float) -> bool:
	_frame += 1
	if _shot == null:
		return true
	if _frame == 2:
		_prepare_map()
	if _frame == LOAD_FRAMES:
		current_scene.add_child(_shot)
		_shot.call("begin", _frame)
	if _frame == LOAD_FRAMES + SETTLE_FRAMES:
		_black.visible = false
		_shot.call("go")
	if _frame > LOAD_FRAMES + SETTLE_FRAMES and bool(_shot.call("is_done")):
		_shot.call("write_cues", _out_dir)
		return true
	return false


## Takes out the map's bots and respawn logic and puts in a fresh player rig with the
## shot's tank (its scripts are switched off: the shot drives it).
func _prepare_map() -> void:
	var scene: Node = current_scene
	for n: String in ["Enemies", "PlayerRespawn"]:
		var node: Node = scene.get_node_or_null(n)
		if node != null:
			node.free()
	var old: Node3D = scene.get_node_or_null("PlayerRig")
	var at: Transform3D = old.global_transform if old != null else Transform3D.IDENTITY
	if old != null:
		old.free()
	var rig: Node3D = (load(RIG_SCENE) as PackedScene).instantiate()
	rig.name = "PlayerRig"
	var tank: Tank = rig.get_node("Tank")
	tank.config = load(_shot.call("player_config"))
	tank.use_player_config = false
	rig.get_node("PlayerController").process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(rig)
	rig.global_transform = at
	if _options.get("hud", "0") != "1":
		for c: Node in rig.get_node("HUD").get_children():
			if c is CanvasItem and not KEEP_HUD.has(c.name):
				(c as CanvasItem).modulate = Color(1, 1, 1, 0)
				(c as CanvasItem).self_modulate = Color(1, 1, 1, 0)   # some fade modulate themselves
	_shot.set("rig", rig)
	EffectFx.prewarm(scene)
