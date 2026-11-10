class_name GroundCover
extends RefCounted
## Ground vegetation (grass, crops, reed, heather): how tall it stands where, and how
## much of a soldier it hides. One per map scene (GroundCover.of(node)), from the map's
## GroundCoverData (data/maps/<map>_groundcover.res) and the classes and rules in
## data/world/ground_cover.tres. The same rule serves bots and squads (Squad's spot
## factors); players only see it, drawn the same height by GroundCoverField (blades near
## the camera) and GroundCoverCanopy (a flat top at the same height beyond), so a man lying
## in a far field is hidden to the eye just as the rule hides him from bots.

const SET_PATH: String = "res://data/world/ground_cover.tres"

static var _cache: Dictionary = {}   # scene root instance id -> GroundCover

var data: GroundCoverData
var rules: GroundCoverSetData
var terrain: Node   # Terrain3D, for ground heights when drawing


## The ground cover of `node`'s scene (null if the map has none).
static func of(node: Node) -> GroundCover:
	if node == null or not node.is_inside_tree():
		return null
	var root: Node = node.get_tree().current_scene
	if root == null:
		return null
	var key: int = root.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var gc: GroundCover = null
	var d: GroundCoverData = GroundCoverData.find_for_scene(root)
	if d != null:
		gc = GroundCover.new()
		gc.data = d
		gc.rules = load(SET_PATH) as GroundCoverSetData
		var terrains: Array[Node] = root.find_children("*", "Terrain3D", true, false)
		gc.terrain = terrains[0] if not terrains.is_empty() else null
	_cache.clear()   # one scene at a time
	_cache[key] = gc
	return gc


func class_at(pos: Vector3) -> GroundCoverClassData:
	var i: int = data.class_at(pos)
	return rules.classes[i] if i < rules.classes.size() else null


func height_at(pos: Vector3) -> float:
	var c: GroundCoverClassData = class_at(pos)
	return c.height_m if c != null else 0.0


## Ground height (Terrain3D), NAN where there is no terrain.
func ground_y(x: float, z: float) -> float:
	if terrain == null:
		return NAN
	var td: Object = terrain.get("data")
	return td.call("get_height", Vector3(x, 0.0, z)) if td != null else NAN


## Water depth (m) over the ground at `pos` in a lake, 0 outside one.
func water_depth(pos: Vector3) -> float:
	var level: float = data.water_level_at(pos)
	if is_nan(level):
		return 0.0
	var g: float = ground_y(pos.x, pos.z)
	return maxf(level - g, 0.0) if not is_nan(g) else 0.0


## Share (0..1) of a body `body_height` m tall at `pos` hidden by the vegetation, seen
## from `viewer`: full along the ground, less when looked down on from above.
func hidden_share(pos: Vector3, body_height: float, viewer: Vector3) -> float:
	var veg: float = height_at(pos)
	var lo: float = rules.min_hiding_height_m
	if veg <= lo or body_height <= lo:
		return 0.0
	var share: float = clampf((veg - lo) / (body_height - lo), 0.0, 1.0)
	var flat: float = Vector2(viewer.x - pos.x, viewer.z - pos.z).length()
	var down_deg: float = rad_to_deg(atan2(viewer.y - (pos.y + body_height * 0.5), maxf(flat, 0.1)))
	var grazing: float = 1.0 - smoothstep(rules.grazing_full_deg, rules.grazing_none_deg, down_deg)
	return share * grazing


func spot_time_factor(hidden: float) -> float:
	return 1.0 + hidden * rules.hide_spot_time_factor


func range_factor(hidden: float) -> float:
	return 1.0 - hidden * rules.hide_range_share


## Body height for a stance (prone/kneel shares 0..1, as Squad keeps them).
func body_height(prone: float, kneel: float) -> float:
	if prone >= 0.5:
		return rules.body_height_prone_m
	if kneel >= 0.5:
		return rules.body_height_kneeling_m
	return rules.body_height_standing_m
