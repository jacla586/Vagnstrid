extends SceneTree
## Bakes Mixamo rifle animations (FBX with Mixamo's Y Bot, in res://mixamo/, not in git:
## Mixamo files may not be passed on) onto the soldier model's skeleton (Blender-style
## names, rest pose already holding the rifle) and saves them as an AnimationLibrary.
##   godot --headless --path . --script res://tools/bake_soldier_animations.gd
## Writes res://assets/models/soldier/soldier_anims.res. Rerun if the models change.
##
## The rest poses differ (T-pose against a rifle stance with a twisted torso), so each
## mapped bone gets a fixed correction found by matching two directions per bone at rest
## (along the bone, and a side direction: hips/shoulders left-right, palm, foot); the
## soldier's bone then turns with the Y Bot's bone, twist included. The rifle is skinned
## to the soldier's right hand, so that hand is matched by the rifle instead (the line
## from right to left hand in an aiming frame), and the left hand is pulled onto the
## rifle's fore grip by a two-bone IK while the Y Bot's hands are in their aiming grip.
## Hips move with the Y Bot's (scaled by hip height); loops and transitions are kept on
## the spot, deaths keep their travel; the body is lifted so its lowest contact joint is
## as high as the Y Bot's (scaled).

const SOURCE_DIR: String = "res://mixamo/"
const SOURCE_ANIM: StringName = &"mixamo_com"
const TARGET: String = "res://assets/models/soldier/soldier.glb"
const OUT: String = "res://assets/models/soldier/soldier_anims.res"
const FPS: float = 30.0
const M: String = "mixamorig_"
## Baked name -> [Mixamo file (no .fbx), loops, keeps its travel, start s, end s (-1: to
## the end)]. Start == end makes a held pose.
const CLIPS: Dictionary = {
	"idle": ["Rifle Idle", true, false, 0.0, -1.0],
	"jog": ["Rifle Run", true, false, 0.0, -1.0],
	"sprint": ["Rifle Run(1)", true, false, 0.0, -1.0],
	"kneel_idle": ["Rifle Kneel Idle", true, false, 0.0, -1.0],
	"crouch_idle": ["Idle Crouching", true, false, 0.0, -1.0],
	"crouch_aim": ["Idle Crouching Aiming", true, false, 0.0, -1.0],
	"prone": ["Prone Idle", true, false, 0.0, -1.0],
	"prone_fire": ["Prone Firing Rifle", true, false, 0.0, -1.0],
	"fire": ["Firing Rifle", true, false, 0.0, -1.0],
	"aim": ["Rifle Aim To Down", true, false, 0.0, 0.0],
	"stand_to_kneel": ["Rifle Stand To Kneel", false, false, 0.0, -1.0],
	"kneel_to_stand": ["Rifle Kneel To Stand", false, false, 0.0, -1.0],
	"kneel_to_prone": ["Rifle Kneel To Prone", false, false, 0.0, -1.0],
	"prone_to_kneel": ["Rifle Prone To Kneel", false, false, 0.0, -1.0],
	"prone_to_crouch": ["Prone To Crouch", false, false, 0.0, -1.0],
	"kneel_to_aim": ["Rifle Kneel To Aim", false, false, 0.0, -1.0],
	"death": ["Rifle Death", false, true, 0.0, -1.0],
	"death_fall": ["Fall Over", false, true, 0.0, -1.0],
	"death_back": ["Rifle Hit To Back", false, true, 0.0, -1.0],
	"death_kneel": ["Rifle Kneel Hit To Back", false, true, 0.0, -1.0],
	"death_run": ["Rifle Run To Dying", false, true, 0.0, -1.0],
}
## The clip and moment whose hands define the aiming grip.
const AIM_FILE: String = "Firing Rifle"
const AIM_TIME_S: float = 0.0
## Soldier bone -> [Y Bot bone, soldier tip, Y Bot tip, side direction key].
const MAP: Dictionary = {
	"hips": ["Hips", "spine", "Spine", "hips"],
	"spine": ["Spine1", "chest", "Spine2", "chest"],
	"chest": ["Spine2", "neck", "Neck", "chest"],
	"neck": ["Neck", "head", "Head", "chest"],
	"head": ["Head", "", "", "same"],
	"shoulder.L": ["LeftShoulder", "arm.L", "LeftArm", "up"],
	"arm.L": ["LeftArm", "forearm.L", "LeftForeArm", "palm.L"],
	"forearm.L": ["LeftForeArm", "hand.L", "LeftHand", "palm.L"],
	"hand.L": ["LeftHand", "middle.L", "LeftHandMiddle1", "palm.L"],
	"thumb.L": ["LeftHandThumb2", "thumb_end.L", "LeftHandThumb4", "palm.L"],
	"index.L": ["LeftHandIndex1", "index_end.L", "LeftHandIndex4", "palm.L"],
	"middle.L": ["LeftHandMiddle1", "middle_end.L", "LeftHandMiddle4", "palm.L"],
	"ring.L": ["LeftHandRing1", "ring_end.L", "LeftHandRing4", "palm.L"],
	"pinky.L": ["LeftHandPinky1", "pinky_end.L", "LeftHandPinky4", "palm.L"],
	"shoulder.R": ["RightShoulder", "arm.R", "RightArm", "up"],
	"arm.R": ["RightArm", "forearm.R", "RightForeArm", "palm.R"],
	"forearm.R": ["RightForeArm", "hand.R", "RightHand", "palm.R"],
	"hand.R": ["RightHand", "middle.R", "RightHandMiddle1", "palm.R"],
	"thumb.R": ["RightHandThumb2", "thumb_end.R", "RightHandThumb4", "palm.R"],
	"index.R": ["RightHandIndex1", "index_end.R", "RightHandIndex4", "palm.R"],
	"middle.R": ["RightHandMiddle1", "middle_end.R", "RightHandMiddle4", "palm.R"],
	"ring.R": ["RightHandRing1", "ring_end.R", "RightHandRing4", "palm.R"],
	"pinky.R": ["RightHandPinky1", "pinky_end.R", "RightHandPinky4", "palm.R"],
	"upleg.L": ["LeftUpLeg", "leg.L", "LeftLeg", "foot.L"],
	"leg.L": ["LeftLeg", "foot.L", "LeftFoot", "foot.L"],
	"foot.L": ["LeftFoot", "toe.L", "LeftToeBase", "up"],
	"upleg.R": ["RightUpLeg", "leg.R", "RightLeg", "foot.R"],
	"leg.R": ["RightLeg", "foot.R", "RightFoot", "foot.R"],
	"foot.R": ["RightFoot", "toe.R", "RightToeBase", "up"],
}
## Side direction key -> [soldier from, soldier to, Y Bot from, Y Bot to] (rest joints).
const SIDES: Dictionary = {
	"hips": ["upleg.R", "upleg.L", "RightUpLeg", "LeftUpLeg"],
	"chest": ["arm.R", "arm.L", "RightArm", "LeftArm"],
	"palm.L": ["pinky.L", "index.L", "LeftHandPinky1", "LeftHandIndex1"],
	"palm.R": ["pinky.R", "index.R", "RightHandPinky1", "RightHandIndex1"],
	"foot.L": ["foot.L", "toe.L", "LeftFoot", "LeftToeBase"],
	"foot.R": ["foot.R", "toe.R", "RightFoot", "RightToeBase"],
}
## Joints that may touch the ground (soldier, Y Bot), for lifting the body.
const CONTACTS: Array = [
	["foot.L", "LeftFoot"], ["foot.R", "RightFoot"], ["toe.L", "LeftToeBase"],
	["toe.R", "RightToeBase"], ["leg.L", "LeftLeg"], ["leg.R", "RightLeg"],
	["forearm.L", "LeftForeArm"], ["forearm.R", "RightForeArm"], ["hand.L", "LeftHand"],
	["hand.R", "RightHand"], ["head", "Head"], ["chest", "Spine2"],
]
const HIPS: String = "hips"
## Left hand IK: full while the Y Bot's left hand is within GRIP_FULL_M of its aiming
## grip (seen from the right hand), none beyond GRIP_NONE_M.
const GRIP_FULL_M: float = 0.10
const GRIP_NONE_M: float = 0.30

var _dst_skel: Skeleton3D
var _src_skel: Skeleton3D
var _src_player: AnimationPlayer
## Soldier bone index -> correction K (soldier global rotation = Y Bot global * K).
var _k: Dictionary = {}
## Soldier bone index -> Y Bot bone index.
var _src_of: Dictionary = {}
var _children: Dictionary = {}  # soldier bone -> Array of child bones
var _ratio: float = 1.0
var _hand_r: int
var _hand_l: int
var _arm_l: int
var _forearm_l: int
## The soldier's left hand seen from his right hand at rest (on the rifle).
var _left_in_right: Transform3D
## The Y Bot's left hand position seen from its right hand when aiming (m).
var _grip_ref: Vector3


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var dst: Node3D = (load(TARGET) as PackedScene).instantiate()
	root.add_child(dst)
	var aim_src: Node3D = (load(_fbx(AIM_FILE)) as PackedScene).instantiate()
	root.add_child(aim_src)
	await process_frame
	_dst_skel = dst.find_children("*", "Skeleton3D", true, false)[0]
	var dst_player: AnimationPlayer = dst.find_children("*", "AnimationPlayer", true, false)[0]
	dst_player.stop()
	for b: int in _dst_skel.get_bone_count():
		_children[b] = []
	for b: int in _dst_skel.get_bone_count():
		var p: int = _dst_skel.get_bone_parent(b)
		if p >= 0:
			(_children[p] as Array).append(b)
	_use_source(aim_src)
	_calibrate()
	var track_prefix: String = String(dst_player.get_node(dst_player.root_node).get_path_to(_dst_skel))
	aim_src.queue_free()
	var library := AnimationLibrary.new()
	for clip: String in CLIPS:
		var spec: Array = CLIPS[clip]
		var path: String = _fbx(spec[0])
		if not ResourceLoader.exists(path):
			push_warning("missing %s" % path)
			continue
		var src: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(src)
		await process_frame
		_use_source(src)
		if not _src_player.has_animation(SOURCE_ANIM):
			push_warning("no %s in %s" % [SOURCE_ANIM, path])
			src.queue_free()
			continue
		var anim: Animation = _bake(track_prefix, spec)
		library.add_animation(StringName(clip), anim)
		print("baked %-16s <- %-26s %.2f s" % [clip, spec[0], anim.length])
		src.queue_free()
	var err: Error = ResourceSaver.save(library, OUT)
	print("saved %s (%s), hip ratio %.2f" % [OUT, error_string(err), _ratio])
	quit()


func _fbx(name: String) -> String:
	return SOURCE_DIR + name + ".fbx"


func _use_source(src: Node) -> void:
	_src_skel = src.find_children("*", "Skeleton3D", true, false)[0]
	_src_player = src.find_children("*", "AnimationPlayer", true, false)[0]
	for name: String in MAP:
		_src_of[_dst_skel.find_bone(name)] = _src_skel.find_bone(M + String(MAP[name][0]))


## Corrections per bone, the hip ratio and the rifle grip, from the rest poses and the
## aiming frame.
func _calibrate() -> void:
	_ratio = _s_rest(HIPS).origin.y / maxf(_m_rest("Hips").origin.y, 0.001)
	for name: String in MAP:
		var m: Array = MAP[name]
		var b: int = _dst_skel.find_bone(name)
		var s_rest: Basis = _s_rest(name).basis.orthonormalized()
		var m_rest: Basis = _m_rest(m[0]).basis.orthonormalized()
		var turn := Basis.IDENTITY
		if m[3] != "same":
			var s_main: Vector3 = _s_rest(m[1]).origin - _s_rest(name).origin
			var m_main: Vector3 = _m_rest(m[2]).origin - _m_rest(m[0]).origin
			var s_side := Vector3.UP
			var m_side := Vector3.UP
			if m[3] != "up":
				var side: Array = SIDES[m[3]]
				s_side = _s_rest(side[1]).origin - _s_rest(side[0]).origin
				m_side = _m_rest(side[3]).origin - _m_rest(side[2]).origin
			turn = _frame(m_main, m_side) * _frame(s_main, s_side).inverse()
		_k[b] = Quaternion(m_rest.inverse() * turn * s_rest)
	_hand_r = _dst_skel.find_bone("hand.R")
	_hand_l = _dst_skel.find_bone("hand.L")
	_arm_l = _dst_skel.find_bone("arm.L")
	_forearm_l = _dst_skel.find_bone("forearm.L")
	# The rifle: soldier at rest and the Y Bot aiming, each from right hand to left.
	_src_player.play(SOURCE_ANIM)
	_src_player.seek(AIM_TIME_S, true)
	var m_rh: Transform3D = _m_pose("RightHand")
	var m_lh: Transform3D = _m_pose("LeftHand")
	var s_rh: Transform3D = _s_rest("hand.R")
	var s_lh: Transform3D = _s_rest("hand.L")
	var rifle_m: Basis = _frame(m_lh.origin - m_rh.origin, Vector3.UP)
	var rifle_s: Basis = _frame(s_lh.origin - s_rh.origin, Vector3.UP)
	_k[_hand_r] = Quaternion(m_rh.basis.orthonormalized().inverse() * rifle_m
			* rifle_s.inverse() * s_rh.basis.orthonormalized())
	_left_in_right = s_rh.orthonormalized().affine_inverse() * s_lh.orthonormalized()
	_grip_ref = (m_rh.orthonormalized().affine_inverse() * m_lh).origin
	print("aim grip: hands %.2f m apart (Y Bot), %.2f m (soldier)" % [
			m_rh.origin.distance_to(m_lh.origin), s_rh.origin.distance_to(s_lh.origin) / _ratio])


## A rotation whose Y is along `main` and X along `side` (made square to it).
static func _frame(main: Vector3, side: Vector3) -> Basis:
	var y: Vector3 = main.normalized()
	var x: Vector3 = (side - y * side.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


func _bake(prefix: String, spec: Array) -> Animation:
	var source: Animation = _src_player.get_animation(SOURCE_ANIM)
	var loops: bool = spec[1]
	var travels: bool = spec[2]
	var t0: float = clampf(spec[3], 0.0, source.length)
	var t1: float = source.length if float(spec[4]) < 0.0 else clampf(spec[4], t0, source.length)
	var held: bool = t1 <= t0
	var anim := Animation.new()
	anim.length = 0.5 if held else t1 - t0
	anim.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	var tracks: Dictionary = {}
	for name: String in MAP:
		var t: int = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("%s:%s" % [prefix, name]))
		tracks[_dst_skel.find_bone(name)] = t
	var hips_track: int = anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(hips_track, NodePath("%s:%s" % [prefix, HIPS]))
	_src_player.play(SOURCE_ANIM)
	_src_player.seek(t0, true)
	var start: Vector3 = _m_pose("Hips").origin
	_src_player.seek(t1, true)
	var end: Vector3 = _m_pose("Hips").origin
	var frames: int = 1 if held else maxi(ceili((t1 - t0) * FPS), 1)
	for f: int in frames + 1:
		var time: float = minf(f / FPS, anim.length) if not held else anim.length * f
		var at: float = t0 if held else t0 + time
		_src_player.seek(at, true)
		# On the spot: the travel (straight from first to last frame) taken out; sway kept.
		var share: float = 0.0 if held else time / maxf(t1 - t0, 0.001)
		var drift: Vector3 = start if travels else start.lerp(end, share)
		drift.y = _m_rest("Hips").origin.y
		var globals: Dictionary = _pose_frame(drift)
		for bone: int in tracks:
			var parent: int = _dst_skel.get_bone_parent(bone)
			var local: Transform3D = (globals[parent] as Transform3D).affine_inverse() * globals[bone] \
					if parent >= 0 else globals[bone]
			anim.rotation_track_insert_key(tracks[bone], time, local.basis.get_rotation_quaternion())
		anim.position_track_insert_key(hips_track, time, (globals[_dst_skel.find_bone(HIPS)] as Transform3D).origin)
	return anim


## The soldier's global bone transforms for the Y Bot's current pose; `drift` is the
## Y Bot hip position that counts as standing on the spot.
func _pose_frame(drift: Vector3) -> Dictionary:
	var rots: Dictionary = {}
	for b: int in _k:
		rots[b] = _src_skel.get_bone_global_pose(_src_of[b]).basis.get_rotation_quaternion() * (_k[b] as Quaternion)
	var hips_pos: Vector3 = _s_rest(HIPS).origin + (_m_pose("Hips").origin - drift) * _ratio
	var globals: Dictionary = _build(rots, hips_pos)
	# Left hand onto the fore grip while the Y Bot holds the rifle that way.
	var m_rel: Vector3 = (_m_pose("RightHand").orthonormalized().affine_inverse() * _m_pose("LeftHand")).origin
	var w: float = 1.0 - smoothstep(GRIP_FULL_M, GRIP_NONE_M, m_rel.distance_to(_grip_ref))
	if w > 0.0:
		_left_ik(rots, globals, w)
		globals = _build(rots, hips_pos)
	# Lift: the Y Bot's lowest contact joint decides how high the soldier's must be.
	var low_m: float = INF
	var pair: Array = []
	for c: Array in CONTACTS:
		var y: float = _m_pose(c[1]).origin.y
		if y < low_m:
			low_m = y
			pair = c
	var lift: float = low_m * _ratio - (globals[_dst_skel.find_bone(pair[0])] as Transform3D).origin.y
	for b: int in globals:
		var g: Transform3D = globals[b]
		g.origin.y += lift
		globals[b] = g
	return globals


## Globals from global rotations (mapped bones) and rest offsets (the rest).
func _build(rots: Dictionary, hips_pos: Vector3) -> Dictionary:
	var globals: Dictionary = {}
	for b: int in _dst_skel.get_bone_count():
		_global_of(b, rots, hips_pos, globals)
	return globals


func _global_of(b: int, rots: Dictionary, hips_pos: Vector3, globals: Dictionary) -> Transform3D:
	if globals.has(b):
		return globals[b]
	var parent: int = _dst_skel.get_bone_parent(b)
	var rest: Transform3D = _dst_skel.get_bone_rest(b)
	var parent_g: Transform3D = _global_of(parent, rots, hips_pos, globals) if parent >= 0 \
			else Transform3D.IDENTITY
	var g: Transform3D = parent_g * rest
	if rots.has(b):
		g.basis = Basis(rots[b] as Quaternion)
	if b == _dst_skel.find_bone(HIPS):
		g.origin = hips_pos
	globals[b] = g
	return g


## Turns bone `b` and everything below it by `turn` (global rotations in `rots`).
func _turn_branch(b: int, turn: Quaternion, rots: Dictionary) -> void:
	if rots.has(b):
		rots[b] = turn * (rots[b] as Quaternion)
	for c: int in _children[b]:
		_turn_branch(c, turn, rots)


## Two-bone IK: the left hand to its place on the rifle (weight `w`), the elbow kept in
## the plane the animation bends it in.
func _left_ik(rots: Dictionary, globals: Dictionary, w: float) -> void:
	var a: Vector3 = (globals[_arm_l] as Transform3D).origin
	var b: Vector3 = (globals[_forearm_l] as Transform3D).origin
	var c: Vector3 = (globals[_hand_l] as Transform3D).origin
	var goal_t: Transform3D = (globals[_hand_r] as Transform3D) * _left_in_right
	var goal: Vector3 = c.lerp(goal_t.origin, w)
	var upper: float = a.distance_to(b)
	var lower: float = b.distance_to(c)
	var reach: Vector3 = goal - a
	var d: float = clampf(reach.length(), absf(upper - lower) + 0.001, upper + lower - 0.001)
	var dir: Vector3 = reach.normalized()
	var pole: Vector3 = (b - a) - dir * (b - a).dot(dir)
	if pole.length() < 0.0001:
		pole = Vector3.DOWN - dir * Vector3.DOWN.dot(dir)
	pole = pole.normalized()
	var along: float = (upper * upper - lower * lower + d * d) / (2.0 * d)
	var elbow: Vector3 = a + dir * along + pole * sqrt(maxf(upper * upper - along * along, 0.0))
	var turn1 := Quaternion((b - a).normalized(), (elbow - a).normalized())
	_turn_branch(_arm_l, turn1, rots)
	var fore_now: Vector3 = turn1 * (c - b)
	var turn2 := Quaternion(fore_now.normalized(), (a + dir * d - elbow).normalized())
	_turn_branch(_forearm_l, turn2, rots)
	var hand_now: Quaternion = rots[_hand_l]
	var hand_goal: Quaternion = goal_t.basis.get_rotation_quaternion()
	_turn_branch(_hand_l, hand_now.slerp(hand_goal, w) * hand_now.inverse(), rots)


func _m_pose(bone: String) -> Transform3D:
	return _src_skel.get_bone_global_pose(_src_skel.find_bone(M + bone))


func _m_rest(bone: String) -> Transform3D:
	return _src_skel.get_bone_global_rest(_src_skel.find_bone(M + bone))


func _s_rest(bone: String) -> Transform3D:
	return _dst_skel.get_bone_global_rest(_dst_skel.find_bone(bone))
