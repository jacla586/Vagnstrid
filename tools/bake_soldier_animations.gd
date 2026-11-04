extends SceneTree
## Bakes animations from Quaternius' Universal Animation Library (CC0, UE-style
## mannequin skeleton, T-pose rest) onto the soldier model's skeleton (Blender-style
## names, rest pose already holding the rifle) and saves them as an AnimationLibrary.
##   godot --headless --path . --script res://tools/bake_soldier_animations.gd
## Writes res://assets/models/soldier/soldier_anims.res. Rerun if the models change.
##
## The rest poses differ too much for rest-relative retargeting, so this matches
## directions: for each mapped bone, top-down, the soldier's bone is turned so that it
## points at its child the way the library's bone points at its child (no twist). The
## pelvis and head copy the library's rotation change from rest; the pelvis also moves
## with it (scaled by the models' heights), so crouching lowers the body.

const SOURCE: String = "res://assets/models/ual/UAL1_Standard.glb"
const TARGET: String = "res://assets/models/soldier/soldier.glb"
const OUT: String = "res://assets/models/soldier/soldier_anims.res"
const FPS: float = 30.0
## Library animation name (Godot drops the "_Loop" ending on import) -> [baked name, loops].
const CLIPS: Dictionary = {
	"Idle": ["idle", true],
	"Walk": ["walk", true],
	"Jog_Fwd": ["jog", true],
	"Sprint": ["sprint", true],
	"Crouch_Idle": ["crouch_idle", true],
	"Crouch_Fwd": ["crouch_walk", true],
	"Fixing_Kneeling": ["kneel", true],
	"Pistol_Aim_Neutral": ["aim", true],
	"Pistol_Shoot": ["shoot", false],
	"Death01": ["death", false],
	"Hit_Chest": ["hit", false],
}
## Soldier bone -> [its child for the direction, library bone, library child].
const DIRECTION_MAP: Dictionary = {
	"spine": ["chest", "spine_01", "spine_03"],
	"chest": ["neck", "spine_03", "neck_01"],
	"neck": ["head", "neck_01", "Head"],
	"shoulder.L": ["arm.L", "clavicle_l", "upperarm_l"],
	"arm.L": ["forearm.L", "upperarm_l", "lowerarm_l"],
	"forearm.L": ["hand.L", "lowerarm_l", "hand_l"],
	"hand.L": ["middle.L", "hand_l", "middle_01_l"],
	"shoulder.R": ["arm.R", "clavicle_r", "upperarm_r"],
	"arm.R": ["forearm.R", "upperarm_r", "lowerarm_r"],
	"forearm.R": ["hand.R", "lowerarm_r", "hand_r"],
	"hand.R": ["middle.R", "hand_r", "middle_01_r"],
	"upleg.L": ["leg.L", "thigh_l", "calf_l"],
	"leg.L": ["foot.L", "calf_l", "foot_l"],
	"foot.L": ["toe.L", "foot_l", "ball_l"],
	"upleg.R": ["leg.R", "thigh_r", "calf_r"],
	"leg.R": ["foot.R", "calf_r", "foot_r"],
	"foot.R": ["toe.R", "foot_r", "ball_r"],
}
## Soldier bone -> library bone, copying the rotation change from rest.
const DELTA_MAP: Dictionary = {"hips": "pelvis", "head": "Head"}
const HIPS: String = "hips"
const DST_FEET: Array[String] = ["foot.L", "foot.R", "toe.L", "toe.R"]
const SRC_FEET: Array[String] = ["foot_l", "foot_r", "ball_l", "ball_r"]
const PELVIS: String = "pelvis"

var _src_skel: Skeleton3D
var _src_player: AnimationPlayer
var _dst_skel: Skeleton3D
var _dst_root: Node
var _height_ratio: float = 1.0
## The pelvis' up/down movement scales with the hip heights (leg lengths differ).
var _hip_ratio: float = 1.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var src: Node3D = (load(SOURCE) as PackedScene).instantiate()
	var dst: Node3D = (load(TARGET) as PackedScene).instantiate()
	root.add_child(src)
	root.add_child(dst)
	await process_frame
	_src_skel = src.find_children("*", "Skeleton3D", true, false)[0]
	_src_player = src.find_children("*", "AnimationPlayer", true, false)[0]
	_dst_skel = dst.find_children("*", "Skeleton3D", true, false)[0]
	_dst_root = dst
	var dst_player: AnimationPlayer = dst.find_children("*", "AnimationPlayer", true, false)[0]
	dst_player.stop()
	var src_h: float = _rest_global(_src_skel, "Head").origin.y
	var dst_h: float = _rest_global(_dst_skel, "head").origin.y
	_height_ratio = dst_h / maxf(src_h, 0.001)
	_hip_ratio = _rest_global(_dst_skel, HIPS).origin.y / maxf(_rest_global(_src_skel, PELVIS).origin.y, 0.001)
	var track_prefix: String = String(dst_player.get_node(dst_player.root_node).get_path_to(_dst_skel))
	var library := AnimationLibrary.new()
	for clip: String in CLIPS:
		if not _src_player.has_animation(clip):
			push_warning("no clip %s in the library" % clip)
			continue
		var anim: Animation = _bake(clip, track_prefix, bool(CLIPS[clip][1]))
		library.add_animation(StringName(CLIPS[clip][0]), anim)
		print("baked %-20s -> %-12s %.2f s" % [clip, CLIPS[clip][0], anim.length])
	var err: Error = ResourceSaver.save(library, OUT)
	print("saved %s (%s), height ratio %.2f" % [OUT, error_string(err), _height_ratio])
	quit()


func _bake(clip: String, prefix: String, loops: bool) -> Animation:
	var source: Animation = _src_player.get_animation(clip)
	var anim := Animation.new()
	anim.length = source.length
	anim.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	var tracks: Dictionary = {}  # bone index -> rotation track
	var mapped: Array[String] = []
	mapped.append_array(DIRECTION_MAP.keys())
	mapped.append_array(DELTA_MAP.keys())
	for bone: String in mapped:
		var t: int = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("%s:%s" % [prefix, bone]))
		tracks[_dst_skel.find_bone(bone)] = t
	var hips_track: int = anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hips_track, NodePath("%s:%s" % [prefix, HIPS]))
	_src_player.play(clip)
	var frames: int = maxi(ceili(source.length * FPS), 1)
	for f: int in frames + 1:
		var time: float = minf(f / FPS, source.length)
		_src_player.seek(time, true)
		var locals: Dictionary = _pose_frame()
		for bone: int in tracks:
			anim.rotation_track_insert_key(tracks[bone], time, (locals[bone] as Transform3D).basis.get_rotation_quaternion())
		anim.position_track_insert_key(hips_track, time, (locals[_dst_skel.find_bone(HIPS)] as Transform3D).origin)
	return anim


## The soldier's local bone transforms for the library's current pose.
func _pose_frame() -> Dictionary:
	var globals: Dictionary = {}
	var locals: Dictionary = {}
	for b: int in _dst_skel.get_bone_count():
		var parent: int = _dst_skel.get_bone_parent(b)
		var parent_g: Transform3D = globals[parent] if parent >= 0 else Transform3D.IDENTITY
		var cand: Transform3D = parent_g * _dst_skel.get_bone_rest(b)
		var name: String = _dst_skel.get_bone_name(b)
		var g: Transform3D = cand
		if DIRECTION_MAP.has(name):
			var m: Array = DIRECTION_MAP[name]
			var child: int = _dst_skel.find_bone(m[0])
			var current: Vector3 = (cand.basis * _dst_skel.get_bone_rest(child).origin).normalized()
			var target: Vector3 = (_pose_global(m[2]).origin - _pose_global(m[1]).origin).normalized()
			if current.length() > 0.5 and target.length() > 0.5 and current.dot(target) < 0.99999:
				g.basis = Basis(Quaternion(current, target)) * cand.basis
		elif DELTA_MAP.has(name):
			var src_bone: String = DELTA_MAP[name]
			var delta: Quaternion = _pose_global(src_bone).basis.get_rotation_quaternion() \
					* _rest_global(_src_skel, src_bone).basis.get_rotation_quaternion().inverse()
			var rest_g: Transform3D = _rest_global(_dst_skel, name)
			g.basis = Basis(delta) * rest_g.basis
			if name == HIPS:
				var moved: Vector3 = _pose_global(PELVIS).origin - _rest_global(_src_skel, PELVIS).origin
				g.origin = rest_g.origin + Vector3(moved.x * _height_ratio, moved.y * _hip_ratio,
						moved.z * _height_ratio)
		globals[b] = g
		locals[b] = parent_g.affine_inverse() * g
	# Feet on the ground: the soldier's lowest foot as high above its rest level as the
	# library's (scaled), by moving the pelvis up or down (all else hangs off it).
	var src_lift: float = _lowest(_src_skel, SRC_FEET, true) - _lowest(_src_skel, SRC_FEET, false)
	var dst_now: float = INF
	for foot: String in DST_FEET:
		dst_now = minf(dst_now, (globals[_dst_skel.find_bone(foot)] as Transform3D).origin.y)
	var dst_rest: float = _lowest(_dst_skel, DST_FEET, false)
	var hips: int = _dst_skel.find_bone(HIPS)
	var fix: float = dst_rest + src_lift * _hip_ratio - dst_now
	var parent: int = _dst_skel.get_bone_parent(hips)
	var parent_g: Transform3D = globals[parent] if parent >= 0 else Transform3D.IDENTITY
	var hg: Transform3D = globals[hips]
	hg.origin.y += fix
	locals[hips] = parent_g.affine_inverse() * hg
	return locals


## Lowest of `bones` (posed or at rest) in skeleton space.
func _lowest(skel: Skeleton3D, bones: Array[String], posed: bool) -> float:
	var y: float = INF
	for b: String in bones:
		var i: int = skel.find_bone(b)
		y = minf(y, (skel.get_bone_global_pose(i) if posed else skel.get_bone_global_rest(i)).origin.y)
	return y


func _pose_global(bone: String) -> Transform3D:
	return _src_skel.get_bone_global_pose(_src_skel.find_bone(bone))


func _rest_global(skel: Skeleton3D, bone: String) -> Transform3D:
	return skel.get_bone_global_rest(skel.find_bone(bone))
