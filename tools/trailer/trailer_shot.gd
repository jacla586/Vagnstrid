extends Node
## Base of a scripted trailer shot (tools/trailer/trailer.gd runs it). A shot sets `map`
## and `weather`, makes its actors in setup() and directs them in physics(t) (commands,
## runs at the physics rate before the tanks) and frame(t) (cameras, every frame).
## t = seconds since the action began (game time: slow motion slows it too).
## Tanks only get commands, as everywhere in the game: cmd(tank) is the one it obeys.

const TANK_SCENE: String = "res://scenes/tank/tank.tscn"
const SHELL_SCENE: String = "res://scenes/weapons/shell.tscn"
const CONFIGS: Dictionary = {
	"bt7": "res://data/configs/1_bt7.tres",
	"t34": "res://data/configs/2_t34.tres",
	"pz4": "res://data/configs/3_pz4.tres",
	"kv2": "res://data/configs/4_kv2.tres",
	"sherman": "res://data/configs/5_sherman.tres",
}

var map: String = "vidingsjo"
var weather: String = "clear"
var options: Dictionary = {}
## The player rig (set by the runner): its tank, cameras and HUD; its controller is off.
var rig: Node3D
var player: Tank
var views: PlayerViews
## A free camera for everything that isn't a crew view.
var cam: Camera3D
var t: float = 0.0
var done: bool = false

var _commands: Dictionary = {}
var _cues: PackedStringArray = []
var _start_frame: int = 0
var _fx: EffectsSetData = preload("res://data/effects/effects.tres")
var _rng := RandomNumberGenerator.new()


## Override: the player tank's preset.
func player_config() -> String:
	return CONFIGS["t34"]


## Override: makes the actors.
func setup() -> void:
	pass


## Override: commands, physics rate.
func physics(_delta: float) -> void:
	pass


## Override: cameras, every frame.
func frame(_delta: float) -> void:
	pass


func begin(start_frame: int) -> void:
	_start_frame = start_frame
	_rng.seed = 7
	process_physics_priority = -100
	player = rig.get_node("Tank")
	views = rig.get_node("PlayerViews")
	TeamLook.set_viewer_team(0)
	player.team = 0
	_commands[player] = TankCommand.new()
	player.set_command(_commands[player])
	cam = Camera3D.new()
	cam.name = "TrailerCamera"
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.near = 0.05
	cam.far = 6000.0
	get_parent().add_child(cam)
	cue("ACTION")
	setup()


func is_done() -> bool:
	return done


func _physics_process(delta: float) -> void:
	if player == null:
		return
	physics(delta)


func _process(delta: float) -> void:
	if player == null:
		return
	t += delta
	if t > float(options.get("max_t", "90")):
		push_warning("trailer: shot ran past max_t, stopping")
		done = true
	frame(delta)
	if options.get("snap", "") == "all" and floori(t * 2.0) != floori((t - delta) * 2.0):
		snap("auto")


# --- Tanks -------------------------------------------------------------------------

## A tank of a preset on the map at (x, z), heading in degrees (0 = north, -z; 90 = east).
func spawn(preset: String, team: int, xz: Vector2, heading_deg: float, tank_name: String = "") -> Tank:
	var tank: Tank = (load(TANK_SCENE) as PackedScene).instantiate()
	tank.config = load(CONFIGS[preset])
	tank.team = team
	if tank_name != "":
		tank.name = tank_name
	get_parent().add_child(tank)
	_commands[tank] = TankCommand.new()
	tank.set_command(_commands[tank])
	place(tank, xz, heading_deg)
	return tank


## Puts a tank on the ground at (x, z) facing heading_deg, standing still.
func place(tank: Tank, xz: Vector2, heading_deg: float) -> void:
	var g: Vector3 = ground(xz)
	tank.global_transform = Transform3D(Basis(Vector3.UP, -deg_to_rad(heading_deg)), g + Vector3.UP * 1.5)
	tank.linear_velocity = Vector3.ZERO
	tank.angular_velocity = Vector3.ZERO
	tank.reset_physics_interpolation()
	tank.face_forward()


func cmd(tank: Tank) -> TankCommand:
	return _commands[tank]


## Steers towards a point on the map; returns the distance left (m).
func drive_to(tank: Tank, point: Vector3, throttle: float) -> float:
	var c: TankCommand = cmd(tank)
	var local: Vector3 = tank.to_local(point)
	var angle: float = atan2(local.x, -local.z)   # + = right
	c.steering = clampf(angle * 2.5, -1.0, 1.0)
	c.throttle = throttle * clampf(1.0 - absf(angle) / PI * 1.5, 0.2, 1.0)
	return Vector2(local.x, local.z).length()


func stop(tank: Tank) -> void:
	cmd(tank).throttle = 0.0
	cmd(tank).steering = 0.0


func aim(tank: Tank, point: Vector3) -> void:
	cmd(tank).aim_point = point
	cmd(tank).has_aim = true


## Aims the main gun so the loaded round lands on `point` (drop allowed for).
func aim_ballistic(tank: Tank, point: Vector3) -> void:
	var from: Vector3 = tank.get_muzzle_transform().origin
	var flat: Vector3 = point - from
	var range_m: float = Vector2(flat.x, flat.z).length()
	var shell: ShellData = tank.get_loaded_shell()
	if shell == null:
		shell = tank.data.ammo[tank.get_ammo_index()]
	var lift: float = tan(Ballistics.superelevation_for_range(shell, range_m)) * range_m
	aim(tank, point + Vector3.UP * lift)


## The ammo index of a round by short name ("AP", "HE"), or 0.
func ammo_index(tank: Tank, short_name: String) -> int:
	for i: int in tank.data.ammo.size():
		if tank.data.ammo[i].short_name == short_name:
			return i
	return 0


## A point at a clock hour from the tank's hull (12 = ahead, 3 = right), `dist` m away.
func at_clock(tank: Tank, hour: float, dist: float) -> Vector3:
	var fwd: Vector3 = -tank.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized().rotated(Vector3.UP, -hour / 12.0 * TAU)
	return ground_v(tank.global_position + fwd * dist)


## The next shot kills: the tank is left with a sliver of hp (knocked out burns).
func make_fragile(tank: Tank) -> void:
	var dmg: TankDamage = tank.get("_damage")
	dmg.hp = 1.0


## The tank's commander can't be hit (the shot decides who gets hurt).
func protect_commander(tank: Tank) -> void:
	var hb: CommanderHitbox = tank.get_commander_hitbox()
	if hb != null:
		hb.collision_layer = 0


## Shakes the crew views (as a hit does), strength 0..1.
func shake(strength: float) -> void:
	var hr: Node = rig.get_node("HitReaction")
	hr.set("_trauma", maxf(float(hr.get("_trauma")), strength))
	hr.set("_seed", Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU))


# --- Views -------------------------------------------------------------------------

func use_cam() -> void:
	views.set_killcam(true)   # hides the optics overlays
	cam.current = true


func use_commander() -> void:
	views.set_killcam(false)
	views.call("_set_mode", PlayerViews.ViewMode.COMMANDER)


func use_gunner(zoom: int = 0) -> void:
	views.set_killcam(false)
	views.call("_set_mode", PlayerViews.ViewMode.GUNNER)
	views.gunner_camera.set("_zoom_index", zoom)


## Commander looks at a world yaw/pitch (degrees; yaw 0 = north, + = left as Godot).
func commander_look(yaw: float, pitch: float) -> void:
	views.commander_camera.set_target_view(yaw, pitch)


## World yaw (radians) of a direction.
static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func pitch_of(dir: Vector3) -> float:
	return asin(clampf(dir.normalized().y, -1.0, 1.0))


func binoculars(on: bool) -> void:
	if on:
		Input.action_press(&"binoculars")
	else:
		Input.action_release(&"binoculars")


func look_cam(eye: Vector3, target: Vector3, fov: float = 60.0, roll: float = 0.0) -> void:
	var b := Basis.looking_at(target - eye, Vector3.UP)
	if roll != 0.0:
		b = b * Basis(Vector3.BACK, roll)
	cam.global_transform = Transform3D(b, eye)
	cam.fov = fov


# --- World -------------------------------------------------------------------------

## The ground (terrain, houses, bridges; not tanks) under (x, z).
func ground(xz: Vector2) -> Vector3:
	var exclude: Array[RID] = []
	for n: Node in get_tree().get_nodes_in_group("tanks"):
		exclude.append((n as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 1500.0, xz.y), Vector3(xz.x, -500.0, xz.y), 1)
	q.exclude = exclude
	var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(q)
	return Vector3(xz.x, float(hit["position"].y) if not hit.is_empty() else 0.0, xz.y)


## True when a round (or an eye) gets from `a` to `b` with nothing solid between, tanks
## left out; `width` > 0 also checks two lines that far to each side.
## see_through = false: tree crowns and bushes count too (for cameras).
func clear_line(a: Vector3, b: Vector3, width: float = 0.0, see_through: bool = true) -> bool:
	var exclude: Array[RID] = []
	for n: Node in get_tree().get_nodes_in_group("tanks"):
		exclude.append((n as CollisionObject3D).get_rid())
	var side: Vector3 = (b - a).cross(Vector3.UP).normalized() * width
	for off: Vector3 in ([Vector3.ZERO, side, -side] if width > 0.0 else [Vector3.ZERO]):
		var q := PhysicsRayQueryParameters3D.create(a + off, b + off,
				Vision.SHOT_MASK if see_through else 0xFFFFFFFF)
		q.exclude = exclude
		q.collide_with_areas = not see_through
		if not get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty():
			return false
	return true


## True when (x, z) is open ground: the terrain itself, not a roof or a bridge, and flat
## enough for a tank (within `max_step` m over its length).
func open_ground(xz: Vector2, max_step: float = 1.2) -> bool:
	var q := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 1500.0, xz.y), Vector3(xz.x, -500.0, xz.y), 1)
	var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(q)
	if hit.is_empty() or not (hit["collider"] is Terrain3D):
		return false
	var y: float = float(hit["position"].y)
	for d: Vector2 in [Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
		if absf(ground(xz + d).y - y) > max_step:
			return false
	return true


func ground_v(p: Vector3) -> Vector3:
	return ground(Vector2(p.x, p.z))


## Fires a round of `shell` from `from` so it lands on `target` (a straight line is fine
## under ~300 m), with `shooter` as the firer (its team is spared).
func launch_shell(shell: ShellData, from: Vector3, target: Vector3, shooter: CollisionObject3D) -> Shell:
	var s := (load(SHELL_SCENE) as PackedScene).instantiate() as Shell
	get_parent().add_child(s)
	var flat: Vector3 = target - from
	var range_m: float = Vector2(flat.x, flat.z).length()
	var dir: Vector3 = flat.normalized()
	var up: float = Ballistics.superelevation_for_range(shell, range_m)
	dir = (dir + Vector3.UP * tan(up)).normalized()
	s.launch(shell, from, dir * shell.muzzle_velocity_mps, shooter)
	return s


func effect(kind: StringName, at: Vector3, scale: float = 1.0, out: Vector3 = Vector3.UP) -> void:
	EffectFx.play(_fx.get(kind), get_parent(), at, out, scale)


## Plays a sound flat (radio, crew) on Master.
func say(path: String, volume_db: float = 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.bus = &"Master"
	p.volume_db = volume_db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# --- Timing ------------------------------------------------------------------------

## True once, on the first call at or after `at` seconds; give each moment its own key.
var _fired: Dictionary = {}
func once(key: String, at: float) -> bool:
	if t < at or _fired.has(key):
		return false
	_fired[key] = true
	return true


func cue(text: String) -> void:
	var movie_s: float = float(Engine.get_frames_drawn()) / 60.0
	var line: String = "%7.2f s in the film  (shot t=%6.2f)  %s" % [movie_s, t, text]
	print("[cue] ", line)
	_cues.append(line)
	if options.has("snap"):
		snap(text)


## Saves what the screen shows now to renders/trailer/snaps/ (checking a shot without a film).
func snap(label: String) -> void:
	var dir: String = ProjectSettings.globalize_path("res://renders/trailer/snaps")
	DirAccess.make_dir_recursive_absolute(dir)
	var file: String = "%s/%s_%05.2f_%s.jpg" % [dir, get_script().resource_path.get_file().get_basename(),
			t, label.validate_filename().replace(" ", "_").left(30)]
	get_viewport().get_texture().get_image().save_jpg(file, 0.85)


func write_cues(dir: String) -> void:
	if dir == "":
		return
	var f := FileAccess.open(dir.path_join("cues.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_cues) + "\n")


static func ease_in_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## 0..1 over [a, b] seconds.
func span(a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)
