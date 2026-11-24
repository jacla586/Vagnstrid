class_name Relevance
extends RefCounted
## AI detail by relevance to the human players (2026-11-22, PRESTANDA_PLAN.md): bots and
## squads far from every human player's tank and from the camera think and look round less
## often (BotData/SquadData "Far from players"). Same rules, a slower pace: a living
## battlefield where nobody watches costs less. Human tanks: those of a PlayerController
## or RemoteController (group GROUP); the camera covers spectating, the killcam and deploy.

const GROUP: StringName = &"human_controllers"
## Off: everything at full pace (A/B: tools/perf/growth_probe.gd ab=relevance).
static var enabled: bool = true

static var _frame: int = -1
static var _anchors: PackedVector3Array = PackedVector3Array()


## Distance (m) from `pos` to the nearest human tank or the camera; INF when there is none.
static func distance_to_humans(node: Node3D, pos: Vector3) -> float:
	if not enabled:
		return 0.0
	var frame: int = Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_anchors.clear()
		for c: Node in node.get_tree().get_nodes_in_group(GROUP):
			var t := c.get("tank") as Tank
			if t != null and is_instance_valid(t) and t.is_inside_tree():
				_anchors.append(t.global_position)
		var cam: Camera3D = node.get_viewport().get_camera_3d()
		if cam != null:
			_anchors.append(cam.global_position)
	var best: float = INF
	for a: Vector3 in _anchors:
		best = minf(best, a.distance_to(pos))
	return best


## Far or near with a margin (no flicker at the edge): far beyond far_m + margin_m, near
## again within far_m.
static func is_far(node: Node3D, pos: Vector3, was_far: bool, far_m: float, margin_m: float) -> bool:
	var d: float = distance_to_humans(node, pos)
	return d > far_m if was_far else d > far_m + margin_m
