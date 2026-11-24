class_name SquadCamera
extends Camera3D
## Looking through the squad leader's eyes (PlayerViews squad view): free look from
## his eye height (lower when the squad kneels), no control over the squad. The leader
## is the squad's first living soldier (Squad.get_leader_eye). Binoculars on the
## "binoculars" action, like the commander's.

## Render layer of the soldier looked through (Squad.set_viewer): this camera doesn't
## draw it, so the view shows only the rifle in his hands (SoldierViewModel).
const OWN_LEADER_LAYER: int = 4

## Higher = zooming in and out happens faster.
@export var fov_sharpness: float = 15.0

## Radians per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.003
@export var tank: Tank

var _yaw: float = 0.0
var _pitch: float = 0.0
var _view_model: SoldierViewModel
## The soldier looked through, where he was a frame ago (for the walk sway).
var _viewing: int = -1
var _last_eye: Vector3 = Vector3.INF
## He fell: following his head down this long yet (s), from this pose.
var _dying: int = -1
var _dying_left: float = 0.0
var _connected_squad: Squad


func _ready() -> void:
	set_cull_mask_value(OWN_LEADER_LAYER, false)
	_view_model = SoldierViewModel.new()
	add_child(_view_model)
	_view_model.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	# Slower mouse when zoomed in, so aim feels the same on screen.
	var zoom_scale: float = fov / tank.squad.data.view_fov_deg if can_view() else 1.0
	_yaw = wrapf(_yaw - GameSettings.look(motion.relative).x * mouse_sensitivity * zoom_scale, -PI, PI)
	_pitch = clampf(_pitch - GameSettings.look(motion.relative).y * mouse_sensitivity * zoom_scale,
			deg_to_rad(-60.0), deg_to_rad(70.0))


func is_binoculars_active() -> bool:
	return current and can_view() and Input.is_action_pressed("binoculars")


## The view is available: the tank has a squad that is off the tank.
func can_view() -> bool:
	if tank == null or tank.squad == null or not is_instance_valid(tank.squad):
		return false
	return tank.squad.is_out() or _dying_left > 0.0   # a wiped squad: the last fall first


## On entering the view: look the way the squad faces.
func start() -> void:
	if can_view():
		var h: Vector3 = tank.squad.get_heading()
		_yaw = atan2(-h.x, -h.z)
		_pitch = 0.0
		fov = tank.squad.data.view_fov_deg
	_process(0.0)


func get_aim_point() -> Vector3:
	return AimRay.cast(self, null)


func _process(delta: float) -> void:
	var squad: Squad = tank.squad if tank != null and is_instance_valid(tank.squad) else null
	_watch(squad)
	if not current or squad == null or not can_view():
		_view_model.visible = false
		if squad != null:
			squad.set_view_hidden(-1)
		_viewing = -1
		_dying_left = 0.0
		return
	var data: SquadData = squad.data
	var target_fov: float = data.binocular_fov_deg if is_binoculars_active() else data.view_fov_deg
	fov = lerpf(fov, target_fov, minf(delta * fov_sharpness, 1.0)) if delta > 0.0 else target_fov
	var look := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	if _dying_left > 0.0:
		# Down with him: his head's place, turning part of the way with it.
		_dying_left -= delta
		squad.set_view_hidden(_dying)
		_view_model.visible = false
		var head: Transform3D = squad.get_head_transform(_dying)
		var t: float = 1.0 - clampf(_dying_left / maxf(data.death_follow_s, 0.01), 0.0, 1.0)
		var turn: Quaternion = look.get_rotation_quaternion().slerp(
				head.basis.orthonormalized().get_rotation_quaternion(),
				data.death_follow_turn_share * smoothstep(0.0, 0.5, t))
		global_transform = Transform3D(Basis(turn), head.origin)
		if _dying_left <= 0.0:
			_last_eye = Vector3.INF   # on to the next man
		return
	_viewing = squad.get_leader_index()
	squad.set_view_hidden(_viewing)
	var eye: Vector3 = _above_cover(squad.get_leader_eye(), data)
	var speed: float = 0.0
	if _last_eye != Vector3.INF and delta > 0.0:
		speed = Vector2(eye.x - _last_eye.x, eye.z - _last_eye.z).length() / delta
	_last_eye = eye
	_view_model.visible = not is_binoculars_active() and fov > data.view_fov_deg * 0.6
	_view_model.step(delta, speed)
	global_transform = Transform3D(look, eye)


## A kneeling or lying leader's eye kept over the vegetation he is in.
func _above_cover(eye: Vector3, data: SquadData) -> Vector3:
	var gc: GroundCover = GroundCover.of(tank)
	if gc == null:
		return eye
	var cover: float = gc.height_at(eye)
	if cover <= 0.0:
		return eye
	var ground: float = gc.ground_y(eye.x, eye.z)
	if is_nan(ground):
		return eye
	var top: float = ground + cover + data.view_above_cover_m
	return Vector3(eye.x, maxf(eye.y, top), eye.z)


## Hears of the squad's falls and shots (once per squad: a new tank brings a new one).
func _watch(squad: Squad) -> void:
	if squad == _connected_squad:
		return
	if _connected_squad != null and is_instance_valid(_connected_squad):
		_connected_squad.soldier_down.disconnect(_on_soldier_down)
		_connected_squad.fired_round.disconnect(_on_fired)
	_connected_squad = squad
	if squad != null:
		squad.soldier_down.connect(_on_soldier_down)
		squad.fired_round.connect(_on_fired)


func _on_soldier_down(index: int, _screamed: bool) -> void:
	if current and index == _viewing and _connected_squad != null:
		_dying = index
		_dying_left = _connected_squad.data.death_follow_s


## The leader fired (host: every round comes through here): the rifle kicks.
func _on_fired(_kind: int, from: Vector3, _velocity: Vector3) -> void:
	if current and _last_eye != Vector3.INF and from.distance_to(_last_eye) < 1.5:
		_view_model.kick()
