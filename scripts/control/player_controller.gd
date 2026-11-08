class_name PlayerController
extends Node
## Turns the local player's input into a TankCommand for the controlled tank.
##
## Commander view: the turret holds its direction relative to the hull, so it turns
## with the hull. "turret_to_view" lays it on the point under the screen centre, and
## it then keeps that hull-relative direction.
## Gunner's sight and debug view: the turret follows the view's aim every frame; on
## leaving them the last aim is kept relative to the hull.
## "fire" (main gun) only works in the gunner's sight and debug view. In the
## commander view the same button is "spot": it marks the point under the screen
## centre (sky doesn't count) on the minimap.
## "fire_mg" fires the roof MG at the screen centre in the commander view with the
## hatch open, otherwise the coaxial MG (wherever the gun points).

## Input actions that pick ammo type 0, 1, ... (TankData.ammo order).
const AMMO_ACTIONS: Array[StringName] = [&"select_ammo_1", &"select_ammo_2"]
## Driving keys. A hit on the own tank cancels the ones held: they must be pressed again.
const DRIVE_ACTIONS: Array[StringName] = [&"move_forward", &"move_backward", &"turn_left", &"turn_right"]

@export var tank: Tank
@export var views: PlayerViews
## Clicks on the squad orders map send the tank's infantry squad.
@export var squad_map: SquadMap
## Its "abandon tank" button bails the crew out (TankCommand.abandon).
@export var esc_menu: EscMenu

var _command: TankCommand = TankCommand.new()
var _hatch_wanted: bool = false
var _turret_to_view_requested: bool = false
var _spot_requested: bool = false
var _fire_armed: bool = false
var _ammo_requested: int = -1
var _smoke_requested: bool = false
var _abandon_requested: bool = false
## Squad order waiting for the next physics frame (Squad.ORDER_*).
var _squad_order: int = 0
var _squad_target: Vector3 = Vector3.ZERO
## Driving keys cancelled by a hit, ignored until released.
var _cancelled: Dictionary = {}
var _struck_tank: Tank


func _ready() -> void:
	if squad_map != null:
		squad_map.squad_order_requested.connect(func(point: Vector3) -> void:
			_squad_order = Squad.ORDER_MOVE
			_squad_target = point)
		squad_map.squad_mine_requested.connect(func(point: Vector3) -> void:
			_squad_order = Squad.ORDER_MINE
			_squad_target = point)
	if esc_menu != null:
		esc_menu.abandon_requested.connect(func() -> void: _abandon_requested = true)
## Last aim point in the hull's local space (used in the commander view).
var _hull_local_aim: Vector3 = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hatch"):
		_hatch_wanted = not _hatch_wanted
	elif event.is_action_pressed("turret_to_view"):
		_turret_to_view_requested = true
	elif event.is_action_pressed("squad_recall"):
		_squad_order = Squad.ORDER_RECALL
	elif event.is_action_pressed("smoke"):
		_smoke_requested = true
	elif event.is_action_pressed("spot") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_spot_requested = true
	else:
		for i: int in AMMO_ACTIONS.size():
			if event.is_action_pressed(AMMO_ACTIONS[i]):
				_ammo_requested = i


func _physics_process(_delta: float) -> void:
	if tank == null:
		return
	_follow_struck()
	_command.throttle = _drive_axis(&"move_backward", &"move_forward")
	_command.steering = _drive_axis(&"turn_left", &"turn_right")
	# Reversing steers like a car: the key turns the rear that way.
	if _command.throttle < 0.0:
		_command.steering = -_command.steering
	# A wounded commander drops back inside; he doesn't pop up again on recovery. Nor
	# does a new tank start with the hatch open.
	if tank.is_commander_wounded() or tank.is_knocked_out():
		_hatch_wanted = false
	_command.hatch_open = _hatch_wanted
	if views != null and (views.drives_turret() or _turret_to_view_requested):
		# Ray queries are done here (physics frame), not in the input callback.
		_command.aim_point = views.get_aim_point()
		_command.has_aim = true
		_hull_local_aim = tank.to_local(_command.aim_point)
	elif _command.has_aim:
		# Follow the hull: same hull-relative direction as when last laid.
		_command.aim_point = tank.to_global(_hull_local_aim)
	_turret_to_view_requested = false
	_update_spot()
	_command.fire = _wants_fire()
	_command.fire_mg = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and Input.is_action_pressed("fire_mg") and views != null and not views.is_squad_view()
	_command.mg_use_roof = views != null and not views.drives_turret() \
			and tank.is_commander_exposed()
	if _command.mg_use_roof:
		_command.mg_aim_point = views.get_aim_point()
	_command.ammo_select = _ammo_requested
	_ammo_requested = -1
	_command.squad_order = _squad_order
	_command.squad_target = _squad_target
	_squad_order = 0
	_command.smoke = _smoke_requested
	_command.abandon = _abandon_requested
	_smoke_requested = false
	_abandon_requested = false
	tank.set_command(_command)


## Like Input.get_axis, but keys cancelled by a hit count as released until they are.
func _drive_axis(negative: StringName, positive: StringName) -> float:
	for action: StringName in DRIVE_ACTIONS:
		if _cancelled.has(action) and not Input.is_action_pressed(action):
			_cancelled.erase(action)
	var value: float = 0.0
	if not _cancelled.has(positive):
		value += Input.get_action_strength(positive)
	if not _cancelled.has(negative):
		value -= Input.get_action_strength(negative)
	return value


## Listens to the controlled tank's hits (it can change on network respawns).
func _follow_struck() -> void:
	if tank == _struck_tank:
		return
	if _struck_tank != null and is_instance_valid(_struck_tank) \
			and _struck_tank.struck.is_connected(_on_struck):
		_struck_tank.struck.disconnect(_on_struck)
	_struck_tank = tank
	if tank != null:
		tank.struck.connect(_on_struck)


## A hit throws the driver off: held driving keys stop counting until pressed again.
func _on_struck(_outcome: int, _direction: Vector3) -> void:
	for action: StringName in DRIVE_ACTIONS:
		if Input.is_action_pressed(action):
			_cancelled[action] = true


## Spots only from the commander view or the squad leader's eyes, and only on
## something solid (not the sky).
func _update_spot() -> void:
	_command.spot = false
	if _spot_requested and views != null and (views.get_mode() == PlayerViews.ViewMode.COMMANDER
			or views.get_mode() == PlayerViews.ViewMode.SQUAD):
		var point: Vector3 = views.get_aim_point()
		var eye: Vector3 = views.squad_camera.global_position if views.is_squad_view() \
				else views.commander_camera.global_position
		if eye.distance_to(point) < AimRay.RANGE - 1.0:
			_command.spot = true
			_command.spot_point = point
	_spot_requested = false


## Fire while the button is held, but only presses that start with the mouse
## captured and in a view that fires count, so the click that captures the mouse
## (or a spot click held into the gunner's sight) doesn't also fire.
func _wants_fire() -> bool:
	var can_fire: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and views != null and views.drives_turret()
	var pressed: bool = Input.is_action_pressed("fire")
	if not can_fire:
		_fire_armed = false
	elif not pressed:
		_fire_armed = true
	return can_fire and pressed and _fire_armed
