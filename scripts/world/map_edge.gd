class_name MapEdge
extends RefCounted
## The invisible edge of a map: MapEdgeData.margin_m inside its picture's world rect
## (MapImageData). Not a physics body (every ray with the default mask would hit one):
## Tank._hold_inside_map takes away a tank's speed outwards past it and pushes it back.
## Bot and squad paths keep inside it (TacticalMap), squad orders are clamped to it,
## spawns stay inside and the maps draw it.

const DATA: MapEdgeData = preload("res://data/world/map_edge.tres")

static var _scene_id: int = 0
static var _rect: Rect2 = Rect2()


## The playable area (x, z) of the current scene; an empty Rect2 if the map has no
## picture (then there is no edge).
static func inner_rect(tree: SceneTree) -> Rect2:
	var scene: Node = tree.current_scene if tree != null else null
	if scene == null:
		return Rect2()
	if scene.get_instance_id() != _scene_id:
		_scene_id = scene.get_instance_id()
		var image: MapImageData = MapImageData.find_for_scene(scene)
		_rect = image.world_rect.grow(-DATA.margin_m) if image != null and image.world_rect.has_area() \
				else Rect2()
	return _rect


## True if (x, z) of `point` is inside the playable area (or the map has no edge).
static func contains(tree: SceneTree, point: Vector3) -> bool:
	var rect: Rect2 = inner_rect(tree)
	return not rect.has_area() or rect.has_point(Vector2(point.x, point.z))


## `point` moved (x, z) into the playable area, shrunk by `inset` metres.
static func clamp_point(tree: SceneTree, point: Vector3, inset: float = 0.0) -> Vector3:
	var rect: Rect2 = inner_rect(tree)
	if not rect.has_area():
		return point
	rect = rect.grow(-minf(inset, minf(rect.size.x, rect.size.y) * 0.45))
	return Vector3(clampf(point.x, rect.position.x, rect.end.x), point.y,
			clampf(point.z, rect.position.y, rect.end.y))
