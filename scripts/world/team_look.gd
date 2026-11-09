class_name TeamLook
extends RefCounted
## Telling friend from foe at a glance, seen from THIS machine's player: tanks and
## soldiers of the viewer's team show UN-blue markings (blue bands, roof panel, blue
## helmets), every other team is camouflaged. Each machine decides for itself, so in a
## network game both sides see their own team in blue and the enemy in camouflage;
## nothing is sent. Tanks and squads poll `version` and repaint when it changes.

const UN_BLUE: Color = Color(0.29, 0.57, 0.86)
const CAMO_SHADER: Shader = preload("res://assets/shaders/camo.gdshader")
## Tanks: friends' two-tone olive or enemies' M90, both weathered (TankLooks feeds it).
const TANK_PAINT_SHADER: Shader = preload("res://assets/shaders/tank_paint.gdshader")

## The local player's team (set by PlayerViews from the own tank); 0 until known.
static var viewer_team: int = 0
## Bumped whenever viewer_team changes.
static var version: int = 0

static var _camo: Dictionary = {}   # pattern scale -> ShaderMaterial
static var _blue: StandardMaterial3D
static var _tank_paint: Dictionary = {}   # enemy (bool) -> ShaderMaterial


static func set_viewer_team(team: int) -> void:
	if team != viewer_team:
		viewer_team = team
		version += 1


static func is_friend(team: int) -> bool:
	return team == viewer_team


## Camouflage for enemy paint; `pattern_scale` = blotches per model-space unit.
static func camo(pattern_scale: float = 0.75) -> ShaderMaterial:
	if not _camo.has(pattern_scale):
		var m := ShaderMaterial.new()
		m.shader = CAMO_SHADER
		m.set_shader_parameter("pattern_scale", pattern_scale)
		_camo[pattern_scale] = m
	return _camo[pattern_scale]


## A tank's paint: friends' weathered two-tone olive, or enemies' weathered M90.
static func tank_paint(enemy: bool) -> ShaderMaterial:
	if not _tank_paint.has(enemy):
		var m := ShaderMaterial.new()
		m.shader = TANK_PAINT_SHADER
		m.set_shader_parameter("enemy", enemy)
		_tank_paint[enemy] = m
	return _tank_paint[enemy]


static func blue() -> StandardMaterial3D:
	if _blue == null:
		_blue = StandardMaterial3D.new()
		_blue.albedo_color = UN_BLUE
		_blue.roughness = 0.6
	return _blue
