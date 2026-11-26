class_name SpotMarks
extends Node
## The player's spot marks: spotted enemies (a Tank or a Squad) and how long ago. One
## mark per enemy however many spot it: a new spot moves it to where the enemy is now
## and starts it afresh. Marks stay at the last known position and fade out
## (SpottingData); a knocked-out tank's mark goes. Read by the minimap and the big
## map. Teammates' spots (bots' too) show as well: offline straight from their tanks,
## online sent by the host (NetGame.on_team_spot) with the key (key_of).

@export var views: PlayerViews
@export var spotting: SpottingData


## A spotted enemy: where and how long ago. key > 0 a tank, < 0 a squad (key_of).
class Mark:
	var key: int
	var point: Vector3
	var age: float = 0.0

	func _init(k: int, at: Vector3) -> void:
		key = k
		point = at

	func is_tank() -> bool:
		return key > 0


var _tank: Tank
var _marks: Array[Mark] = []
## Offline: teammates' tanks whose spots we listen to.
var _mates: Dictionary = {}  # instance id -> Tank
var _mate_check: float = 0.0
var _gone_check: float = 0.0


## The same number for the same enemy on every machine: a tank's net id (online) or
## instance id (offline); a squad is minus its tank's. 0 for anything else.
static func key_of(target: Node3D) -> int:
	if target is Tank:
		var t := target as Tank
		return t.net_id if t.net_id > 0 else t.get_instance_id()
	if target is Squad:
		var sq := target as Squad
		return -key_of(sq.tank) if is_instance_valid(sq.tank) else 0
	return 0


func _process(delta: float) -> void:
	_connect_to_tank()
	_mate_check -= delta
	if _mate_check <= 0.0:
		_mate_check = 1.0
		_connect_to_mates()
	for mark: Mark in _marks:
		mark.age += delta
	_gone_check -= delta
	if _gone_check <= 0.0:
		_gone_check = 1.0
		_drop_knocked_out()
	var lifetime: float = spotting.mark_lifetime_s if spotting != null else 25.0
	_marks = _marks.filter(func(m: Mark) -> bool: return m.age < lifetime)


func get_marks() -> Array[Mark]:
	return _marks


## 1 while fresh, fading to 0 over the last mark_fade_s of the lifetime.
func get_alpha(mark: Mark) -> float:
	if spotting == null or spotting.mark_fade_s <= 0.0:
		return 1.0
	return clampf((spotting.mark_lifetime_s - mark.age) / spotting.mark_fade_s, 0.0, 1.0)


func _on_spotted(target: Node3D, point: Vector3) -> void:
	add_mark(key_of(target), point)


## The enemy `key` was seen at `point` (own spot, or a teammate's sent by the host).
func add_mark(key: int, point: Vector3) -> void:
	if key == 0:
		return
	for mark: Mark in _marks:
		if mark.key == key:
			mark.point = point
			mark.age = 0.0
			return
	_marks.append(Mark.new(key, point))


## Marks of tanks that have been knocked out since go.
func _drop_knocked_out() -> void:
	if _marks.is_empty():
		return
	var out: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var t := node as Tank
		if t != null and t.is_knocked_out():
			out[key_of(t)] = true
	if not out.is_empty():
		_marks = _marks.filter(func(m: Mark) -> bool: return not out.has(m.key))


func _connect_to_tank() -> void:
	var tank: Tank = views.get_tank() if views != null else null
	if tank == _tank:
		return
	if _tank != null and _tank.spotted.is_connected(_on_spotted):
		_tank.spotted.disconnect(_on_spotted)
	_tank = tank
	if _tank != null:
		_tank.spotted.connect(_on_spotted)


## Offline: listens to every tank on the own team (they come and go as bots are added).
func _connect_to_mates() -> void:
	if NetRole.is_online() or _tank == null:
		return
	for id: int in _mates.keys():
		var old_v: Variant = _mates[id]
		var old: Tank = (old_v as Tank) if is_instance_valid(old_v) else null
		if not is_instance_valid(old):
			_mates.erase(id)
		elif old.team != _tank.team:
			if old.spotted.is_connected(_on_spotted):
				old.spotted.disconnect(_on_spotted)
			_mates.erase(id)
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var mate := node as Tank
		if mate == null or mate == _tank or mate.team != _tank.team \
				or _mates.has(mate.get_instance_id()):
			continue
		_mates[mate.get_instance_id()] = mate
		mate.spotted.connect(_on_spotted)
