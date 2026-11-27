extends "res://tools/trailer/trailer_shot.gd"
## A mine on the road, one take:
##  0 s     low at the roadside: a soldier of the own squad kneels on the road and lays a
##          mine ("Upprättar minering!" ... "Mina armerad!"), the squad pulls back into
##          the grass
##  then    an enemy tank comes down the road (camera low past the mine, looking up the
##          road); it rolls over the mine: the track goes, the tank slews and stops
##          ("Mina utlöst!")
## The shot finds its own straight bit of road near the tutorial's road circle on
## Vidingsjö. Cheats: the squad starts out beside the road (no dismount or walk), the
## laying is shortened to LAY_S. Options: weather=<preset>, spot=<n>.

const SEARCH_FROM: Vector2 = Vector2(1035.0, 1670.0)
const LAY_S: float = 3.5
const ENEMY_FROM_M: float = 70.0
const ENEMY_GO_AFTER_LAID_S: float = 0.6
const ENEMY_THROTTLE: float = 0.8
const END_AFTER_HIT_S: float = 4.5

var enemy: Tank
var _mine_at: Vector3
var _dir: Vector3      # along the road, the way the enemy drives
var _side: Vector3     # across the road, towards the own tank and squad
var _squad_set: bool = false
var _laid_t: float = -1.0
var _hit_t: float = -1.0
var _mine: Node3D


func _init() -> void:
	map = "vidingsjo"
	weather = "overcast"


func setup() -> void:
	if not _find_road():
		push_warning("no straight road found")
		done = true
		return
	var own: Vector3 = ground_v(_mine_at + _side * 45.0 - _dir * 10.0)
	place(player, Vector2(own.x, own.z), rad_to_deg(atan2(-_side.x, _side.z)))
	protect_commander(player)
	var from: Vector3 = _mine_at - _dir * ENEMY_FROM_M
	enemy = spawn("pz4", 1, Vector2(from.x, from.z), rad_to_deg(atan2(_dir.x, -_dir.z)), "Enemy")
	enemy.mine_hit.connect(func() -> void:
		_hit_t = t
		cue("the mine goes: track thrown"))
	var squad_data: SquadData = player.data.squad
	if squad_data != null:
		squad_data.mine_lay_time_s = LAY_S   # this run only
	use_cam()


## A road point near SEARCH_FROM with a straight stretch of road through it (road
## surface lifted over the ground along the line), open ground to one side.
func _find_road() -> bool:
	var skip: int = int(options.get("spot", "0"))
	var tries: Array[Vector2] = []
	for r: int in range(0, 400, 10):
		for a: int in 24:
			if r == 0 and a > 0:
				break
			tries.append(SEARCH_FROM + Vector2(r, 0).rotated(a * TAU / 24.0))
	for xz: Vector2 in tries:
		if not _is_road(xz):
			continue
		for a2: int in 18:
			var d := Vector3.FORWARD.rotated(Vector3.UP, a2 * PI / 18.0)
			var ok: bool = true
			for k: float in [-80.0, -50.0, -25.0, 15.0, 30.0]:
				var p: Vector3 = Vector3(xz.x, 0.0, xz.y) + d * k
				if not _is_road(Vector2(p.x, p.z)):
					ok = false
					break
			if not ok:
				continue
			var side := d.cross(Vector3.UP).normalized()
			for sd: float in [1.0, -1.0]:
				var own: Vector3 = Vector3(xz.x, 0.0, xz.y) + side * sd * 45.0 - d * 10.0
				var eye: Vector3 = Vector3(xz.x, 0.0, xz.y) + d * 14.0 + side * sd * 8.0
				if open_ground(Vector2(own.x, own.z), 1.6) and open_ground(Vector2(eye.x, eye.z), 1.6) \
						and clear_line(ground(Vector2(eye.x, eye.z)) + Vector3.UP,
						ground(Vector2(xz.x, xz.y) - Vector2(d.x, d.z) * 60.0) + Vector3.UP * 2.0, 1.5, false):
					if skip > 0:
						skip -= 1
						continue
					_mine_at = RoadSurface.on_road(get_tree(), ground(xz))
					_dir = d
					_side = side * sd
					print("mine: road at %s, heading %d" % [_mine_at, a2 * 10])
					return true
	return false


func _is_road(xz: Vector2) -> bool:
	var g: Vector3 = ground(xz)
	return RoadSurface.on_road(get_tree(), g).y > g.y + 0.01


func physics(_delta: float) -> void:
	if enemy == null:
		return
	_place_squad()
	# The enemy waits up the road, then comes down it.
	if _laid_t >= 0.0 and t > _laid_t + ENEMY_GO_AFTER_LAID_S and _hit_t < 0.0:
		var ahead: Vector3 = _mine_at + _dir * 200.0
		drive_to(enemy, ahead, ENEMY_THROTTLE)
		aim(enemy, enemy.global_position + _dir * 300.0 + Vector3.UP * 1.5)
		if once("enemy_go", 0.0):
			cue("the enemy comes down the road")
	else:
		stop(enemy)
	if _laid_t < 0.0:
		_mine = _find_mine()
		if _mine != null:
			_laid_t = t
			cue("mine laid")
			# The squad runs back to its tank (holding by the road it would take the tank
			# on with its AT rounds first).
			player.squad.order(Squad.ORDER_RECALL, Vector3.ZERO)
	if _hit_t >= 0.0 and t > _hit_t + END_AFTER_HIT_S:
		done = true
	if t > 50.0:
		done = true


## The own squad: off the tank at once, beside the road, then the mine order.
func _place_squad() -> void:
	if _squad_set:
		return
	var squad: Squad = player.squad
	if squad == null or not squad.is_inside_tree():
		return
	_squad_set = true
	var near: Vector3 = ground_v(_mine_at + _side * 7.0 + _dir * 2.0)
	squad.order(Squad.ORDER_MOVE, near)
	squad.global_position = near
	squad.set("_heading", -_side)
	squad.call("_snap_soldiers")
	squad.order(Squad.ORDER_MINE, _mine_at)
	cue("mine ordered")


func _find_mine() -> Node3D:
	for n: Node in get_tree().get_nodes_in_group(Mine.GROUP):
		return n as Node3D
	return null


func frame(delta: float) -> void:
	if enemy == null:
		return
	if _laid_t < 0.0 or t < _laid_t + 1.4:
		# Low at the roadside by the mine: the soldier kneels and lays it.
		var eye: Vector3 = ground_v(_mine_at - _side * 3.2 - _dir * 2.6) + Vector3.UP * 0.7
		look_cam(eye, _mine_at + _side * 1.2 + Vector3.UP * 0.4, 40.0)
		return
	if once("road_cam", 0.0):
		cue("road camera")
	# Low past the mine, looking up the road at the tank coming; it holds on the blast.
	var eye2: Vector3 = ground_v(_mine_at + _dir * 14.0 - _side * 7.0) + Vector3.UP * 1.0
	var tank: Vector3 = enemy.get_global_transform_interpolated().origin
	look_cam(eye2, _mine_at.lerp(tank, 0.45) + Vector3.UP * 1.2, 40.0)
