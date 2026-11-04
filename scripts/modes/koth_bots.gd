class_name KothBots
extends Node
## King of the Hill orders for every BotController in the scene: drive to a random
## point inside the zone (or the announced next zone during a gap), hold there a
## while, then pick a new point so bots don't sit still forever; re-order when the zone
## moves or shrinks past them. Knocked-out bots come back at their team's current spawn
## after KothData.bot_respawn_delay_s, instead of being repaired where they died.
## Bots still spot and fight by their own rules on the way. Host/offline only.

## Points are picked within this share of the radius, so bots end up well inside.
const INNER_SHARE: float = 0.6
## A bot holding its point picks a new one after a random time in this range (s).
const HOLD_MIN_S: float = 15.0
const HOLD_MAX_S: float = 35.0
## Speed on the way to the zone.
const ORDER_THROTTLE: float = 0.7
## Bots side by side at a spawn leave one after another this far apart (s), so they
## don't all turn into each other at once.
const DEPART_INTERVAL_S: float = 2.5

@export var mode: KothMode

var _bots: Array[BotController] = []
var _hold: Dictionary = {}  # BotController -> seconds left at the current point
var _respawn: Dictionary = {}  # BotController -> seconds until back at the spawn
var _ordered_radius: Dictionary = {}  # BotController -> zone radius when last ordered
var _depart: Dictionary = {}  # BotController -> seconds until it leaves the spawn
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	if NetRole.is_client() or mode == null:
		set_physics_process(false)
		return
	_rng.randomize()
	mode.zone_moved.connect(func(_c: Vector3) -> void: _order_all())
	_find_bots.call_deferred()


func _find_bots() -> void:
	for node: Node in get_tree().current_scene.find_children("*", "", true, false):
		var bot := node as BotController
		if bot == null or bot.tank == null:
			continue
		_bots.append(bot)
		bot.respawn_delay_s = 0.0   # no repair on the spot: we bring it back at the spawn
		bot.tank.knocked_out.connect(_on_knocked_out.bind(bot))
	var per_team: Dictionary = {}
	for bot: BotController in _bots:
		var n: int = int(per_team.get(bot.tank.team, 0))
		per_team[bot.tank.team] = n + 1
		_depart_later(bot, n * DEPART_INTERVAL_S)


func _physics_process(delta: float) -> void:
	for bot: BotController in _bots:
		if not is_instance_valid(bot) or not is_instance_valid(bot.tank):
			continue
		if _respawn.has(bot):
			_update_respawn(bot, delta)
			continue
		if bot.tank.is_knocked_out():
			continue
		if _depart.has(bot):
			_depart[bot] = float(_depart[bot]) - delta
			if float(_depart[bot]) > 0.0:
				continue
			_depart.erase(bot)
			_order_into_zone(bot)
			continue
		var radius: float = mode.get_radius()
		var shrunk: bool = float(_ordered_radius.get(bot, radius)) > radius / INNER_SHARE
		if bot.has_orders_left():
			if shrunk:
				_order_into_zone(bot)
			continue
		if not _is_inside(bot.tank.global_position, radius):
			_order_into_zone(bot)
			continue
		_hold[bot] = float(_hold.get(bot, HOLD_MAX_S)) - delta
		if float(_hold[bot]) <= 0.0:
			_order_into_zone(bot)


func _order_all() -> void:
	for bot: BotController in _bots:
		if is_instance_valid(bot) and is_instance_valid(bot.tank) and not bot.tank.is_knocked_out() \
				and not _depart.has(bot):
			_order_into_zone(bot)


## Hold at the spawn for a moment, then go (staggered per team).
func _depart_later(bot: BotController, delay: float) -> void:
	bot.order_move([bot.tank.global_position], 0.0)
	_depart[bot] = delay


## Inside the zone's circle (open or announced).
func _is_inside(point: Vector3, radius: float) -> bool:
	var c: Vector3 = mode.get_center()
	return Vector2(point.x - c.x, point.z - c.z).length() <= radius


func _order_into_zone(bot: BotController) -> void:
	var radius: float = mode.get_radius()
	bot.order_path(_random_point(radius * INNER_SHARE), ORDER_THROTTLE)
	_ordered_radius[bot] = radius
	_hold[bot] = _rng.randf_range(HOLD_MIN_S, HOLD_MAX_S)


## Random point inside `radius` of the zone centre, on land, at ground height.
func _random_point(radius: float) -> Vector3:
	var center: Vector3 = mode.get_center()
	var offset: Vector2 = Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * radius
	var point := Vector3(center.x + offset.x, center.y, center.z + offset.y)
	var map: TacticalMap = TacticalMap.for_scene(get_tree().current_scene)
	for i: int in 8:
		var hit: Dictionary = KothMode.ground_hit(mode.get_world_3d(), point)
		var dry: bool = not hit.is_empty() \
				and (hit["position"] as Vector3).y > KothMode.SEA_LEVEL_LIMIT_M
		if dry and (map == null or not map.is_blocked(hit["position"])):
			point.y = (hit["position"] as Vector3).y
			return point
		# Try another random point, a bit closer to the centre each time.
		offset = Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * radius * (1.0 - i / 8.0)
		point = Vector3(center.x + offset.x, center.y, center.z + offset.y)
	return center


func _on_knocked_out(bot: BotController) -> void:
	_respawn[bot] = mode.data.bot_respawn_delay_s


func _update_respawn(bot: BotController, delta: float) -> void:
	_respawn[bot] = float(_respawn[bot]) - delta
	if float(_respawn[bot]) > 0.0:
		return
	_respawn.erase(bot)
	KothMode.place_tank(bot.tank, mode.get_free_spawn(bot.tank.team, bot.tank))
	bot.tank.repair()
	_depart_later(bot, _rng.randf_range(0.0, DEPART_INTERVAL_S))
