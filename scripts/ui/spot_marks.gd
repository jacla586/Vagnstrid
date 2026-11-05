class_name SpotMarks
extends Node
## The player's spot marks: where the commander spotted and how long ago. Marks stay
## at the spotted point (last known position) and fade out (SpottingData). Read by
## the minimap and the big map. Teammates' spots (bots' too) show as well: offline
## straight from their tanks, online sent by the host (NetGame.on_team_spot).

@export var views: PlayerViews
@export var spotting: SpottingData


## A spotted point and how long ago it was spotted.
class Mark:
	var point: Vector3
	var age: float = 0.0

	func _init(at: Vector3) -> void:
		point = at


var _tank: Tank
var _marks: Array[Mark] = []
## Offline: teammates' tanks whose spots we listen to.
var _mates: Dictionary = {}  # instance id -> Tank
var _mate_check: float = 0.0


func _process(delta: float) -> void:
	_connect_to_tank()
	_mate_check -= delta
	if _mate_check <= 0.0:
		_mate_check = 1.0
		_connect_to_mates()
	for mark: Mark in _marks:
		mark.age += delta
	var lifetime: float = spotting.mark_lifetime_s if spotting != null else 25.0
	_marks = _marks.filter(func(m: Mark) -> bool: return m.age < lifetime)


func get_marks() -> Array[Mark]:
	return _marks


## 1 while fresh, fading to 0 over the last mark_fade_s of the lifetime.
func get_alpha(mark: Mark) -> float:
	if spotting == null or spotting.mark_fade_s <= 0.0:
		return 1.0
	return clampf((spotting.mark_lifetime_s - mark.age) / spotting.mark_fade_s, 0.0, 1.0)


func _on_spotted(point: Vector3) -> void:
	add_mark(point)


## A mark at `point` (own spot, or a teammate's sent by the host).
func add_mark(point: Vector3) -> void:
	_marks.append(Mark.new(point))


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
		var old: Tank = _mates[id]
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
