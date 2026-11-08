class_name Mine
extends Node3D
## An anti-tank mine (MineData) laid by a squad. On the host it watches enemy tanks:
## a track over it is thrown (Tank.on_mine; never a knock-out) and the mine is gone.
## Gun rounds landing close destroy it (shell_landed). Enemy soldiers who see it mark
## it for their team (mark_known): a red cross on their maps. Clients only show it
## (NetGame sends laying, finding and removal). No friendly fire: own team's tanks and
## rounds leave it alone.

## A mine was found by `team` (host and clients).
signal known(team: int)
## The mine is gone: blown up (true) or just removed (false, its squad laid another).
signal gone(exploded: bool)

const GROUP: StringName = &"mines"
const IMPACT_SCENE: PackedScene = preload("res://scenes/effects/impact.tscn")
## Tanks are checked this often (physics ticks), staggered per mine.
const CHECK_TICKS: int = 6
## Only tanks this close (m, centre to mine) are checked against their tracks.
const NEAR_M: float = 8.0
## Without a track layout: the hull's half width and half length (m).
const PLAIN_HALF_WIDTH_M: float = 1.6
const PLAIN_HALF_LENGTH_M: float = 3.2

## Bumped whenever a mine is found or gone (bots re-plan on a change).
static var version: int = 0
static var _next_id: int = 1

var data: MineData
var team: int = -1
var net_id: int = 0
## Client: shown from the host, no logic.
var net_puppet: bool = false

var _known_by: Dictionary = {}  # team -> true
var _age: float = 0.0
var _tick: int = 0
var _done: bool = false


## Host: a new mine for `team` at ground point `at`, added under `parent`. On a road it
## lies on the visible surface (road meshes have no collision; RoadSurface).
static func lay(parent: Node, mine_data: MineData, mine_team: int, at: Vector3) -> Mine:
	var mine := Mine.new()
	mine.data = mine_data
	mine.team = mine_team
	mine.net_id = _next_id
	_next_id += 1
	parent.add_child(mine)
	mine.global_position = RoadSurface.on_road(parent.get_tree(), at)
	return mine


## Client: the host's mine `id`.
static func make_puppet(parent: Node, mine_data: MineData, mine_team: int, at: Vector3,
		id: int) -> Mine:
	var mine := Mine.new()
	mine.data = mine_data
	mine.team = mine_team
	mine.net_id = id
	mine.net_puppet = true
	parent.add_child(mine)
	mine.global_position = at
	return mine


static func find(tree: SceneTree, id: int) -> Mine:
	for node: Node in tree.get_nodes_in_group(GROUP):
		var mine := node as Mine
		if mine != null and mine.net_id == id:
			return mine
	return null


## Host: a shell of `shooter_team` landed at `point`: mines of other teams close enough
## are destroyed (gun rounds only; bullets do nothing).
static func shell_landed(tree: SceneTree, point: Vector3, shell: ShellData, shooter_team: int) -> void:
	if shell == null or shell.caliber_mm < Tank.THREAT_MIN_CALIBER_MM:
		return
	for node: Node in tree.get_nodes_in_group(GROUP):
		var mine := node as Mine
		if mine == null or mine.net_puppet or mine._done or (shooter_team >= 0 and mine.team == shooter_team):
			continue
		var reach: float = mine.data.destroy_by_he_m if shell.is_explosive() else mine.data.destroy_by_gun_m
		if mine.global_position.distance_to(point) <= reach:
			mine.blow_up()


func _ready() -> void:
	add_to_group(GROUP)
	_tick = randi() % CHECK_TICKS
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = data.disc_radius_m
	cylinder.bottom_radius = data.disc_radius_m
	cylinder.height = data.disc_height_m
	cylinder.radial_segments = 12
	cylinder.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = data.color
	material.roughness = 0.95
	cylinder.material = material
	disc.mesh = cylinder
	disc.position = Vector3(0.0, data.disc_height_m * 0.5 - data.sink_m, 0.0)
	add_child(disc)
	version += 1


func get_team() -> int:
	return team


func get_known_teams() -> PackedInt32Array:
	var teams := PackedInt32Array()
	for t: int in _known_by.keys():
		teams.append(t)
	return teams


func is_known_by(viewer_team: int) -> bool:
	return viewer_team == team or _known_by.has(viewer_team)


## `viewer_team` found it (soldiers on the host, or the host's news on a client).
func mark_known(viewer_team: int) -> void:
	if viewer_team == team or _known_by.has(viewer_team):
		return
	_known_by[viewer_team] = true
	version += 1
	known.emit(viewer_team)


func _physics_process(delta: float) -> void:
	if net_puppet or _done:
		return
	_age += delta
	_tick += 1
	if _age < data.arm_time_s or _tick % CHECK_TICKS != 0:
		return
	for node: Node in get_tree().get_nodes_in_group("tanks"):
		var tank := node as Tank
		if tank == null or tank.team == team or tank.is_knocked_out() or tank.net_puppet:
			continue
		if tank.global_position.distance_to(global_position) > NEAR_M:
			continue
		var track: StringName = _track_over(tank)
		if track != &"":
			tank.on_mine(track, global_position, data)
			blow_up()
			return


## Which of `tank`'s tracks is over the mine (&"" = none).
func _track_over(tank: Tank) -> StringName:
	var local: Vector3 = tank.to_local(global_position)
	if absf(local.y) > 3.0:
		return &""
	var m: float = data.trigger_margin_m
	if tank.data.layout != null:
		for module: ModuleData in tank.data.layout.modules:
			if not module.external or module.frame != &"hull":
				continue
			if absf(local.x - module.center.x) <= module.size.x * 0.5 + m \
					and absf(local.z - module.center.z) <= module.size.z * 0.5 + m:
				return module.id
		return &""
	if absf(local.x) <= PLAIN_HALF_WIDTH_M + m and absf(local.z) <= PLAIN_HALF_LENGTH_M + m:
		return &"track_right" if local.x > 0.0 else &"track_left"
	return &""


## Goes off (a tank, a shell): blast effect and sound, then gone.
func blow_up() -> void:
	if _done:
		return
	_done = true
	show_blast()
	version += 1
	gone.emit(true)
	queue_free()


## Taken away quietly (its squad laid another, or the host says it is gone).
func remove() -> void:
	if _done:
		return
	_done = true
	version += 1
	gone.emit(false)
	queue_free()


## The blast's look and sound (also on clients when the host says it went off).
func show_blast() -> void:
	if not is_inside_tree():
		return
	var effect: Node3D = IMPACT_SCENE.instantiate()
	get_parent().add_child(effect)
	effect.global_position = global_position
	effect.scale = Vector3.ONE * data.effect_scale
	var light: OmniLight3D = effect.get_node_or_null("Light") as OmniLight3D
	if light != null:
		light.omni_range *= data.effect_scale
	SoundFx.play_at(self, data.sound_explosion, global_position)
