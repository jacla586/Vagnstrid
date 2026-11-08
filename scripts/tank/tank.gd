class_name Tank
extends RigidBody3D
## A tracked vehicle. Acts only on TankCommand; never reads input directly.
##
## Suspension: RayCast3D children of $Suspension act as road wheels. Each grounded
## ray pushes the hull up with a spring + damper force.
## Driving: the command is turned into a target forward speed and yaw rate. The
## needed force/torque (limited by the data's accelerations) is split into a left and
## right track force, applied at the grounded wheels' contact points.
## Turret: turns toward the command's aim point at the data's traverse/elevation speed.
## No stabilization: when the hull turns, the turret has to catch up.
## Hatch: opens/closes toward the command's hatch_open over the data's transition
## time. The commander is exposed whenever the hatch isn't fully closed.
## Gun: fires the data's main shell when the command says fire and it's loaded,
## then reloads. Recoil is an impulse at the muzzle. Switching ammo type empties
## the breech and starts a full reload of the new type.
## Armour: shells call on_shell_hit(); the hit zone comes from the collision shape
## and the hit normal, and Armour decides the outcome. For now one penetration
## knocks the tank out: it ignores commands, turns charred and smokes.
## Damage (TankDamage): penetrations take structure hp and damage the modules on the
## shell's path (engine, tracks, turret ring, fuel = fire, ammo in the turret rear =
## knocked out). Hits that don't penetrate wear the plate locally. Standing still
## repairs modules, then slowly some hp. HE fragments reach the external tracks.
## Network: on the host every tank is simulated as usual and has a net_id. On a client
## each tank is a puppet (net_puppet): frozen, no drive, shots or damage logic; the net
## code sets its pose and status from the host's snapshots. The client's own tank also
## predicts turret, gun, hatch and roof MG from the local command (net_predict).
## Commander: while exposed, a hitbox follows his head. A hit wounds him: the hatch
## slams shut and stays locked for the data's wound time.
## Machine guns: the command's fire_mg fires the roof MG (aimed at mg_aim_point; only
## with the hatch fully open and the commander unhurt) or the coaxial MG (aims with
## the gun). Bullets are Shells like the main gun's, with the MG data's spread.
## Spotting: the command's spot marks spot_point (emits `spotted`), then waits the
## data's spot cooldown.
## Smoke: the command's smoke fires a salvo (TankData.smoke_*: a screen ahead of the
## turret), smoke_salvos per life, smoke_cooldown_s apart. Abandon: the crew bails out (stuck for good): the tank
## counts as knocked out (no one scores it) and respawns like one.
## Respawn (repair): everything as at the first spawn: damage, commander, gun, smoke,
## the squad back on the tank.

## Emitted after a shot leaves the barrel.
signal fired(shell: Shell)
## Emitted when a shell this tank fired lands. `result` is null for a plain hit.
signal shot_landed(result: HitResult)
## Emitted when this tank is knocked out.
signal knocked_out
## A gun round (THREAT_MIN_CALIBER_MM or more) hit this tank: HitResult.Outcome and the
## shell's direction. Also on network clients for their own tank (net_struck).
signal struck(outcome: int, direction: Vector3)
## This tank left a wreck at `at` (turret and gun as given): the host keeps a list for
## players who join later.
signal wreck_left(at: Transform3D, turret_yaw: float, gun_pitch: float)
## Emitted when the exposed commander is hit.
signal commander_wounded
## Emitted when a shell or bullet hits the tank, penetrating or not. `direction` is
## the projectile's flight direction (bots turn towards where it came from).
signal hit_taken(direction: Vector3)
## A gun round (not bullets: at least THREAT_MIN_CALIBER_MM) hit the tank (`hit`) or
## passed or landed within NEAR_MISS_M of it. `direction` is its flight direction.
## Bots count these to decide when to pull back. Host/offline only.
signal shell_threat(direction: Vector3, hit: bool)
## Emitted when a module changes state (TankDamage.State).
signal module_changed(id: StringName, state: int)
## Emitted for every machine-gun bullet fired.
signal mg_fired(bullet: Shell, roof: bool)
## Emitted when the commander spots: `point` is the world position he marked. Also
## for marks the tank's infantry squad makes (report_squad_spot).
signal spotted(point: Vector3)
## Emitted when the tank's squad spots an enemy (a Tank or a Squad) at `at`.
signal squad_contact(enemy: Node3D, at: Vector3)
## A gun round passed or landed within NEAR_MISS_M without hitting (the crew shouts).
## Host/offline from the shell, network clients for their own tank (net_near_miss).
signal near_missed(direction: Vector3)
## A smoke salvo went off: the clouds' ground points (the host sends them to clients).
signal smoke_launched(points: PackedVector3Array)
## Host: an ammo explosion threw the turret (start velocity and spin; clients copy it).
signal turret_tossed(velocity: Vector3, spin: Vector3)

## Rounds of at least this calibre count as a threat to bots (shell_threat); MG and
## rifle bullets don't (mm).
const THREAT_MIN_CALIBER_MM: float = 20.0
## A round passing or landing this close to the hull centre is a near miss (m).
const NEAR_MISS_M: float = 8.0
const KMH_TO_MS: float = 1.0 / 3.6
## After a shot the hull's speed says nothing about driving for this long (s): recoil.
const RECOIL_SETTLE_S: float = 1.5
const SHELL_SCENE: PackedScene = preload("res://scenes/weapons/shell.tscn")
const MUZZLE_FLASH_SCENE: PackedScene = preload("res://scenes/effects/muzzle_flash.tscn")
const BURNING_SCENE: PackedScene = preload("res://scenes/effects/burning.tscn")
## Normals steeper than this (Y in local space) count as roof/belly.
const ROOF_NORMAL_Y: float = 0.94
const CHARRED_COLOR: Color = Color(0.08, 0.08, 0.075)
## A thrown turret (Tank.toss_turret): its mass (kg), how long it ignores its own hull
## (s), and when it is frozen at the latest (s).
const TURRET_WRECK_MASS_KG: float = 4000.0
const TURRET_WRECK_EXCEPTION_S: float = 0.6
const TURRET_WRECK_FREEZE_S: float = 12.0
## Wrecks left on the map (group "wrecks"); beyond this many the oldest goes.
const MAX_WRECKS: int = 150
## A knocked-out puppet that jumps this far has respawned (m)...
const WRECK_JUMP_M: float = 20.0
## ...also this long after it was repaired (s).
const WRECK_PENDING_S: float = 2.0
## The drive effort that rocks the hull is smoothed this fast (1/s).
const ROCK_SMOOTHING: float = 12.0
## Commander hitbox centre sits this far below his eyes (m).
const COMMANDER_HITBOX_DROP: float = 0.35
## The scene's own measures (today's medium tank): geometry from TankData is scaled
## from these (apply_geometry).
const BASE_HULL: Vector3 = Vector3(3.2, 1.4, 6.5)
const BASE_HULL_MESH: Vector3 = Vector3(2.3, 1.2, 6.2)
const BASE_TRACK_MESH: Vector3 = Vector3(0.5, 1.0, 6.5)
const BASE_TRACK_X: float = 1.35
const BASE_TURRET_RADIUS: float = 1.2
const BASE_TURRET_TOP_SHARE: float = 0.875
const BASE_TURRET_Z: float = 0.3
const BASE_CUPOLA: Vector3 = Vector3(-0.5, 0.0, 0.35)
const BASE_ROOF_MG: Vector3 = Vector3(-0.5, 0.0, -0.05)
const BASE_PIVOT_SHARE: float = 0.833
## Hull points (local) bots try to see when spotting, for the scene's size.
const BASE_SPOT_POINTS: Array[Vector3] = [Vector3(0.0, 0.3, 0.0), Vector3(0.0, 1.5, 0.3),
		Vector3(0.0, 0.4, -2.9), Vector3(0.0, 0.4, 2.9)]
## Visual only: how far the hatch lid swings open.
const HATCH_OPEN_ANGLE_DEG: float = 110.0

@export var data: TankData
## Built in the garage: if set, `data` is built from it (TankBuilder) at start.
@export var config: TankConfig
## The player's tank: offline, it is built from the config chosen in the garage
## (TankConfigs.get_selected(): the T-34-like preset unless another is chosen).
@export var use_player_config: bool = false
## Name on the scoreboard (set for network players; empty = made up from the tank).
var display_label: String = ""
## Unused since TeamLook (friend blue / enemy camouflage, per viewer); kept so maps
## that set it still load.
@export var paint_color: Color = Color(0.0, 0.0, 0.0, 0.0)
## Side this tank fights for. Tanks of other teams are enemies (bots use this).
@export var team: int = 0

var _command: TankCommand = TankCommand.new()
## The controller's command; _command is what the crew makes of it (CrewLag when wounded).
var _input_command: TankCommand = _command
var _crew_lag: CrewLag = CrewLag.new()
var _left_rays: Array[RayCast3D] = []
var _right_rays: Array[RayCast3D] = []
var _track_half_width: float = 1.0
var _hatch_progress: float = 0.0
var _reload_remaining: float = 0.0
## Index into data.ammo of the shell in the breech (or being loaded).
var _ammo_index: int = 0
var _knocked_out: bool = false
## A wreck has been left for the current knock-out (leave_wreck).
var _wreck_left: bool = false
## Only built to leave a wreck (a late joiner's copy, make_wreck_here): no squad, no sound.
var wreck_only: bool = false
## Puppet: repaired but not yet jumped to the spawn: where the wreck goes, and how long
## to wait for the jump (s).
var _wreck_pending_xform: Transform3D
var _wreck_pending_s: float = 0.0
## The pending wreck lost its turret (thrown by an ammo explosion).
var _wreck_pending_no_turret: bool = false
## Smoothed drive effort that pitches the hull (-1 full braking .. 1 full throttle), and
## a slow copy of it: the difference is the kick while the effort changes.
var _rock: float = 0.0
var _rock_slow: float = 0.0
var _commander_wound_remaining: float = 0.0
var _idle_command: TankCommand = TankCommand.new()
var _burning: Node3D
## TeamLook state the paint was last applied for (repaint when either changes).
var _look_version: int = -1
var _look_team: int = -1
var _charred_material: StandardMaterial3D
var _mg_shot_timer: float = 0.0
var _spot_cooldown_remaining: float = 0.0
var _smoke_left: int = 0
## Time.get_ticks_msec() when the next salvo may go (clock time, so clients have it too).
var _smoke_ready_ms: int = 0
var _damage: TankDamage
## Network id (0 = not replicated). Set by the net code.
var net_id: int = 0
## Client side: this tank is shown from the host's snapshots, not simulated here.
var net_puppet: bool = false
## Game mode rule (ThunderRoad: outside the corridor): the gun and MGs don't fire.
var fire_blocked: bool = false
## The turret was thrown off by an ammo explosion (hidden here, flying as its own body).
var _turret_tossed: bool = false
## Client's own tank: turret, gun, hatch and roof MG follow the local command at once.
var net_predict: bool = false
var _net_velocity: Vector3 = Vector3.ZERO
var _net_command: TankCommand = TankCommand.new()
## Time since the main gun fired: the recoil shove doesn't count as moving for repairs.
var _since_fired: float = 999.0
## Slow enough for repairs, as of the last check before a shot's shove.
var _at_rest: bool = false
var _fire_effect: Node3D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Engine, track, gun and hatch sounds (null when the data has none).
var _audio: TankAudio
var _exhaust: TankExhaust
var _gun_render_layer: int = 1
## The infantry squad riding on this tank (null when the data has none).
var squad: Squad

@onready var _suspension: Node3D = $Suspension
@onready var _turret: Node3D = $Visual/Turret
@onready var _gun_pivot: Node3D = $Visual/Turret/GunPivot
@onready var _hatch_hinge: Node3D = $Visual/Turret/Cupola/HatchHinge
@onready var _head_closed: Marker3D = $Visual/Turret/Cupola/HeadClosed
@onready var _head_open: Marker3D = $Visual/Turret/Cupola/HeadOpen
@onready var _gunner_sight: Marker3D = $Visual/Turret/GunPivot/GunnerSight
@onready var _muzzle: Marker3D = $Visual/Turret/GunPivot/Muzzle
@onready var _visual: Node3D = $Visual
@onready var _commander_hitbox: CommanderHitbox = $Visual/Turret/Cupola/CommanderHitbox
@onready var _commander_hitbox_shape: CollisionShape3D = \
		$Visual/Turret/Cupola/CommanderHitbox/Shape
@onready var _hull_shape: CollisionShape3D = $HullShape
@onready var _turret_shape: CollisionShape3D = $TurretShape
## Every collision shape that belongs to the turret (one unless a TankModel adds more).
var _turret_shapes: Array[CollisionShape3D] = []
@onready var _coax_muzzle: Marker3D = $Visual/Turret/GunPivot/CoaxMuzzle
@onready var _roof_mg: Node3D = $Visual/Turret/RoofMG
@onready var _roof_mg_pitch: Node3D = $Visual/Turret/RoofMG/Pitch
@onready var _roof_mg_muzzle: Marker3D = $Visual/Turret/RoofMG/Pitch/Muzzle


func _ready() -> void:
	if config == null and use_player_config and not NetRole.is_online():
		config = TankConfigs.get_selected()
	if config != null:
		var built: TankData = TankBuilder.build(config)
		if built != null:
			data = built
	assert(data != null, "Tank needs a TankData resource")
	add_to_group("tanks")
	mass = data.mass_kg
	apply_geometry()
	var width_sum: float = 0.0
	for child: Node in _suspension.get_children():
		var ray := child as RayCast3D
		if ray == null:
			continue
		ray.add_exception(self)
		ray.target_position = Vector3(0.0, -data.suspension_rest_length, 0.0)
		# Cast once per step by _apply_suspension (force_raycast_update), and not at all on
		# puppets: left enabled, every ray would be cast a second time by the engine.
		ray.enabled = false
		width_sum += absf(ray.position.x)
		if ray.position.x < 0.0:
			_left_rays.append(ray)
		else:
			_right_rays.append(ray)
	var ray_count: int = _left_rays.size() + _right_rays.size()
	assert(ray_count > 0, "Tank needs RayCast3D children under Suspension")
	_track_half_width = maxf(width_sum / ray_count, 0.1)
	_align_gunner_sight()
	_setup_paint()
	_rng.randomize()
	_smoke_left = data.smoke_salvos
	_roof_mg.visible = data.roof_mg != null
	_damage = TankDamage.new(data)
	_damage.module_changed.connect(func(id: StringName, st: TankDamage.State) -> void:
		module_changed.emit(id, st))
	for m: ModuleData in _damage.get_modules():
		if m.external and m.frame == &"hull":
			var target := ModuleFragmentTarget.new()
			target.tank = self
			target.module_id = m.id
			target.position = m.center
			add_child(target)
	if data.squad != null and not wreck_only:
		squad = Squad.new()
		squad.name = "%sSquad" % name
		squad.tank = self
		squad.data = data.squad
		squad.net_puppet = net_puppet
		get_parent().add_child.call_deferred(squad)
	if data.sounds != null and not wreck_only:
		_audio = TankAudio.new()
		_audio.name = "Audio"
		_audio.tank = self
		add_child(_audio)
	if not wreck_only:
		_exhaust = TankExhaust.new()
		_exhaust.name = "Exhaust"
		_exhaust.tank = self
		add_child(_exhaust)


## Sizes the hull, tracks, turret and gun from the data (TankData geometry; the scene
## is today's medium tank, so its own measures are the reference). Shapes and meshes
## are copied first: they are shared by every tank made from the scene. Suspension rays
## spread along the hull, the turret sits on its roof, cupola and roof MG move with the
## turret, the barrel and its muzzle with the gun's length.
func apply_geometry() -> void:
	if TankModel.has_model(data):
		_apply_model()
		return
	# Looked up here (not the @onready fields) so a preview can size a tank out of the tree.
	var hull_shape: CollisionShape3D = $HullShape
	var turret_shape: CollisionShape3D = $TurretShape
	var turret: Node3D = $Visual/Turret
	var roof_mg: Node3D = $Visual/Turret/RoofMG
	var gun_pivot: Node3D = $Visual/Turret/GunPivot
	var muzzle: Marker3D = $Visual/Turret/GunPivot/Muzzle
	var suspension: Node3D = $Suspension
	var hull: Vector3 = data.hull_size
	var s := Vector3(hull.x / BASE_HULL.x, hull.y / BASE_HULL.y, hull.z / BASE_HULL.z)
	var tr: float = data.turret_radius_m / BASE_TURRET_RADIUS
	var th: float = data.turret_height_m
	var box := (hull_shape.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size = hull
	hull_shape.shape = box
	var hull_mesh: MeshInstance3D = $Visual/Hull
	var hm := (hull_mesh.mesh as BoxMesh).duplicate() as BoxMesh
	hm.size = BASE_HULL_MESH * s
	hull_mesh.mesh = hm
	hull_mesh.position = Vector3(0.0, 0.1 * s.y, 0.0)
	for side: float in [-1.0, 1.0]:
		var track: MeshInstance3D = $Visual/TrackLeft if side < 0.0 else $Visual/TrackRight
		var tm := (track.mesh as BoxMesh).duplicate() as BoxMesh
		tm.size = BASE_TRACK_MESH * Vector3(s.x, s.y, s.z)
		track.mesh = tm
		track.position = Vector3(side * BASE_TRACK_X * s.x, -0.2 * s.y, 0.0)
	var turret_pos := Vector3(0.0, hull.y * 0.5 + th * 0.5, BASE_TURRET_Z * s.z)
	turret.position = turret_pos
	turret_shape.position = turret_pos
	var cyl := (turret_shape.shape as CylinderShape3D).duplicate() as CylinderShape3D
	cyl.radius = data.turret_radius_m
	cyl.height = th
	turret_shape.shape = cyl
	var turret_mesh: MeshInstance3D = $Visual/Turret/TurretMesh
	var cm := (turret_mesh.mesh as CylinderMesh).duplicate() as CylinderMesh
	cm.bottom_radius = data.turret_radius_m
	cm.top_radius = data.turret_radius_m * BASE_TURRET_TOP_SHARE
	cm.height = th
	turret_mesh.mesh = cm
	($Visual/Turret/Cupola as Node3D).position = Vector3(BASE_CUPOLA.x * tr, th * 0.5 + 0.15, BASE_CUPOLA.z * tr)
	roof_mg.position = Vector3(BASE_ROOF_MG.x * tr, th * 0.5 + 0.35, BASE_ROOF_MG.z * tr)
	gun_pivot.position = Vector3(0.0, 0.05, -data.turret_radius_m * BASE_PIVOT_SHARE)
	var gun: MeshInstance3D = $Visual/Turret/GunPivot/Gun
	var gm := (gun.mesh as CylinderMesh).duplicate() as CylinderMesh
	gm.height = data.gun_length_m
	gm.top_radius = data.barrel_radius_m * 0.875
	gm.bottom_radius = data.barrel_radius_m * 1.125
	gun.mesh = gm
	gun.position = Vector3(0.0, 0.0, -(0.2 + data.gun_length_m * 0.5))
	muzzle.position = Vector3(0.0, 0.0, -(0.25 + data.gun_length_m))
	_add_plain_marks(turret, data.turret_radius_m, th)
	for child: Node in suspension.get_children():
		var ray := child as RayCast3D
		if ray != null:
			ray.position = Vector3(signf(ray.position.x) * BASE_TRACK_X * s.x, -hull.y * 0.5,
					ray.position.z * s.z)


## A TankModel look: its meshes, part positions and convex armour shapes (several per
## part: hull plates, track runs, skirts; turret body, bin...). Turret shapes follow the
## turret (_sync_turret_shapes). Works out of the tree too (garage preview).
func _apply_model() -> void:
	var m: Dictionary = TankModel.build(data)
	var hull_shape: CollisionShape3D = $HullShape
	var turret_shape: CollisionShape3D = $TurretShape
	var turret: Node3D = $Visual/Turret
	var gun_pivot: Node3D = $Visual/Turret/GunPivot
	var hull_shapes: Array[PackedVector3Array] = m["hull_shapes"]
	var turret_shapes: Array[PackedVector3Array] = m["turret_shapes"]
	for child: Node in get_children():
		if child is CollisionShape3D and child != hull_shape and child != turret_shape:
			remove_child(child)
			child.free()
	_set_convex(hull_shape, hull_shapes[0])
	for i: int in range(1, hull_shapes.size()):
		var cs := CollisionShape3D.new()
		cs.name = "HullShape%d" % (i + 1)
		_set_convex(cs, hull_shapes[i])
		add_child(cs)
	turret.position = m["turret_pos"]
	_set_convex(turret_shape, turret_shapes[0])
	turret_shape.transform = Transform3D(Basis(), turret.position)
	_turret_shapes = [turret_shape]
	for i: int in range(1, turret_shapes.size()):
		var cs := CollisionShape3D.new()
		cs.name = "TurretShape%d" % (i + 1)
		_set_convex(cs, turret_shapes[i])
		cs.transform = turret_shape.transform
		add_child(cs)
		_turret_shapes.append(cs)
	var hull_mesh: MeshInstance3D = $Visual/Hull
	hull_mesh.mesh = m["hull"]
	hull_mesh.position = Vector3.ZERO
	($Visual/TrackLeft as Node3D).visible = false
	($Visual/TrackRight as Node3D).visible = false
	var turret_mesh: MeshInstance3D = $Visual/Turret/TurretMesh
	turret_mesh.mesh = m["turret"]
	turret_mesh.position = Vector3.ZERO
	($Visual/Turret/Cupola as Node3D).position = m["cupola"]
	($Visual/Turret/RoofMG as Node3D).position = m["roof_mg"]
	gun_pivot.position = m["gun_pivot"]
	var mantlet: MeshInstance3D = $Visual/Turret/GunPivot/Mantlet
	mantlet.mesh = m["mantlet"]
	mantlet.position = Vector3.ZERO
	var gun: MeshInstance3D = $Visual/Turret/GunPivot/Gun
	gun.mesh = m["gun"]
	gun.transform = Transform3D.IDENTITY
	($Visual/Turret/GunPivot/Muzzle as Node3D).position = Vector3(0.0, 0.0, m["muzzle_z"])
	var track_x: float = m["track_x"]
	for child: Node in ($Suspension as Node3D).get_children():
		var ray := child as RayCast3D
		if ray != null:
			ray.position = Vector3(signf(ray.position.x) * track_x, -data.hull_size.y * 0.5,
					ray.position.z * data.hull_size.z / BASE_HULL.z)


## Puts the gun and mantlet meshes on render layer `layer` alone. The gunner's sight
## moves its own tank's gun to a layer it doesn't render (GunnerCamera), others stay on 1.
func set_gun_render_layer(layer: int) -> void:
	_gun_render_layer = layer
	for path: String in ["Visual/Turret/GunPivot/Mantlet", "Visual/Turret/GunPivot/Gun"]:
		var mesh := get_node_or_null(path) as MeshInstance3D
		if mesh != null:
			mesh.layers = 1 << (layer - 1)


## Render layer of the gun (and of its own gun smoke, GunSmoke).
func get_gun_render_layer() -> int:
	return _gun_render_layer


## Plain box tanks: a UN-blue band round the round turret and a roof panel (TeamLook).
func _add_plain_marks(turret: Node3D, radius: float, height: float) -> void:
	var old: Node = turret.get_node_or_null("TeamMarks")
	if old != null:
		turret.remove_child(old)
		old.free()
	var kit := MeshKit.new()
	var r_at := func(y: float) -> float:
		return lerpf(radius, radius * BASE_TURRET_TOP_SHARE, y / height + 0.5) + 0.015
	var y0: float = -0.1 * height
	var y1: float = 0.15 * height
	kit.cylinder(Vector3(0, y0, 0), Vector3(0, y1, 0), r_at.call(y0), r_at.call(y1), 20, MeshKit.Mat.MARK)
	kit.box(Vector3(0.0, height * 0.5 + 0.012, 0.15), Vector3(radius * 0.9, 0.024, radius * 0.9), MeshKit.Mat.MARK)
	var marks := MeshInstance3D.new()
	marks.name = "TeamMarks"
	marks.mesh = kit.build()
	turret.add_child(marks)


static func _set_convex(cs: CollisionShape3D, points: PackedVector3Array) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	cs.shape = shape


## Turret armour shapes turn with the turret (plain round turrets don't mind).
func _sync_turret_shapes() -> void:
	for cs: CollisionShape3D in _turret_shapes:
		cs.transform = _turret.transform


## Boresights the gunner's sight: tilts it so its line of sight crosses the gun's
## bore at the zeroing range. Both markers live in GunPivot space.
func _align_gunner_sight() -> void:
	if data.sight_zero_range_m <= 0.0:
		return
	var bore_point: Vector3 = _muzzle.position \
			+ _muzzle.basis * Vector3.FORWARD * data.sight_zero_range_m
	_gunner_sight.basis = Basis.looking_at(bore_point - _gunner_sight.position)


func set_command(command: TankCommand) -> void:
	_input_command = command
	_command = command


## Throttle commanded this frame (-1..1).
func get_throttle() -> float:
	return _command.throttle



## Half size of the hull's collision box (m): x = half width, z = half length.
## Points on the hull (local) that spotters try to see, scaled with the tank's size.
func get_spot_points() -> Array[Vector3]:
	var s: Vector3 = data.hull_size / BASE_HULL
	var out: Array[Vector3] = []
	for p: Vector3 in BASE_SPOT_POINTS:
		out.append(p * s)
	return out


func get_display_label() -> String:
	if display_label != "":
		return display_label
	if use_player_config and not NetRole.is_online():
		return "You"
	return "Bot (%s)" % data.display_name


func get_hull_half_extents() -> Vector3:
	return data.hull_size * 0.5


## Takes `fraction` of the horizontal speed away (e.g. felling a tree). Physics
## contact, not input: the command rule still holds.
func apply_obstacle_drag(fraction: float) -> void:
	var horizontal := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	apply_central_impulse(-horizontal * clampf(fraction, 0.0, 1.0) * mass)


## Bus for this tank's sounds and for hits on it ("Own" for the player's tank).
func get_audio_bus() -> StringName:
	return _audio.bus if _audio != null else SoundFx.WORLD_BUS


func set_audio_bus(bus_name: StringName) -> void:
	if _audio != null:
		_audio.set_bus(bus_name)


## The team something belongs to: a tank, its commander's hitbox, its track targets,
## or anything with get_team() (squads); -1 for neutral things (MG nests, boards...).
## There is no friendly fire: shells and fragments never hurt their shooter's team.
static func team_of(node: Object) -> int:
	if node == null or not is_instance_valid(node):
		return -1
	if node is Tank:
		return (node as Tank).team
	if node is CommanderHitbox:
		var hb := node as CommanderHitbox
		return hb.tank.team if hb.tank != null else -1
	if node is ModuleFragmentTarget:
		var mt := node as ModuleFragmentTarget
		return mt.tank.team if mt.tank != null else -1
	if node.has_method("get_team"):
		return node.get_team()
	return -1


## True if `shooter` and `target` are on the same team (no damage between them).
static func is_friendly(shooter: Object, target: Object) -> bool:
	var team: int = team_of(shooter)
	return team >= 0 and team == team_of(target)


func is_enemy_of(other: Tank) -> bool:
	return other != null and other != self and other.team != team


## True when the roof MG can be used: the tank has one, the hatch is fully open and
## the commander is unhurt.
func can_use_roof_mg() -> bool:
	return data.roof_mg != null and _hatch_progress >= 1.0 and not is_commander_wounded()


## Machine gun the command picks (roof if asked for and usable, else coax), or null.
func get_active_mg(use_roof: bool) -> MachineGunData:
	if use_roof and can_use_roof_mg():
		return data.roof_mg
	return data.coax_mg


## Main gun's muzzle in world space; -Z is the bore direction.
func get_muzzle_transform() -> Transform3D:
	return _muzzle.global_transform


func get_coax_muzzle_transform() -> Transform3D:
	return _coax_muzzle.global_transform


func get_roof_mg_muzzle_transform() -> Transform3D:
	return _roof_mg_muzzle.global_transform


func is_knocked_out() -> bool:
	return _knocked_out


## Structure hp left, 0..1. Only for the own tank's HUD and bots (not shown for enemies).
func get_hp_fraction() -> float:
	return _damage.hp_fraction()


func get_module_state(id: StringName) -> int:
	return _damage.state(id)


func has_module(id: StringName) -> bool:
	return _damage.has_module(id)


## True if the world point lies in a hull module's box (grown by margin m).
func is_point_in_module(id: StringName, point: Vector3, margin: float) -> bool:
	return _damage.point_in_module(id, to_local(point), margin)


func is_burning() -> bool:
	return _damage.is_burning()


func needs_repair() -> bool:
	return _damage.needs_repair()


## A shell flew from `from` to `to` this frame: enemy tanks of its shooter within
## NEAR_MISS_M of that stretch go into `near` (Tank -> flight direction), once each.
## Shell reports them when it is done (Shell._report_near_misses), except tanks it hit.
static func collect_near_misses(tree: SceneTree, from: Vector3, to: Vector3,
		shell_data: ShellData, shooter: Object, near: Dictionary) -> void:
	if shell_data.caliber_mm < THREAT_MIN_CALIBER_MM:
		return
	var direction: Vector3 = (to - from).normalized()
	for node: Node in tree.get_nodes_in_group("tanks"):
		var other := node as Tank
		if other == null or other == shooter or near.has(other) or other.is_knocked_out() \
				or Tank.is_friendly(shooter, other):
			continue
		var closest: Vector3 = Geometry3D.get_closest_point_to_segment(other.global_position, from, to)
		if closest.distance_to(other.global_position) <= NEAR_MISS_M:
			near[other] = direction


## Some module is knocked out (red), not just damaged.
func has_destroyed_module() -> bool:
	for m: ModuleData in _damage.get_modules():
		if _damage.state(m.id) == TankDamage.State.DESTROYED:
			return true
	return false


## 0..1 towards the module repair; 0 while moving, firing, burning or just hit.
func get_repair_progress() -> float:
	return _damage.repair_progress()


func get_repair_time_left() -> float:
	return _damage.repair_time_left()


## A thrown track holds the tank until it is repaired.
func is_immobilised() -> bool:
	return _damage.is_immobilised()


func is_commander_wounded() -> bool:
	return _commander_wound_remaining > 0.0


func get_commander_wound_remaining() -> float:
	return _commander_wound_remaining


func get_commander_hitbox() -> CommanderHitbox:
	return _commander_hitbox


## Centre of the commander's hitbox (head and shoulders) in world space.
func get_commander_hitbox_position() -> Vector3:
	return _commander_hitbox.global_position


## The commander is hurt without a hit (ThunderRoad: too long outside the corridor):
## as a commander hit, the hatch shut for commander_wound_time_s.
func wound_commander() -> void:
	if _knocked_out:
		return
	_commander_wound_remaining = data.commander_wound_time_s
	_hatch_progress = 0.0
	_update_hatch(0.0)
	_update_commander_hitbox()
	commander_wounded.emit()


## Called by the commander hitbox when something hits the exposed commander.
func on_commander_hit(_shell_data: ShellData, _point: Vector3) -> HitResult:
	if not is_commander_exposed():
		return null
	_commander_wound_remaining = data.commander_wound_time_s
	# The hatch slams shut: no second hit while it swings closed.
	_hatch_progress = 0.0
	_update_hatch(0.0)
	_update_commander_hitbox()
	commander_wounded.emit()
	var result := HitResult.new()
	result.outcome = HitResult.Outcome.COMMANDER_HIT
	result.part = "commander"
	result.target = self
	return result


## Called by Shell when a shell hits this tank. Returns what happened.
func on_shell_hit(shell_data: ShellData, point: Vector3, normal: Vector3,
		velocity: Vector3, shape: int = -1) -> HitResult:
	if data.armour == null:
		return null
	var part: String = "hull"
	var frame: Node3D = self
	var hit_node: Node = _shape_node(shape)
	if hit_node == _turret_shape or _turret_shapes.has(hit_node):
		part = "turret"
		frame = _turret
	var to_part: Basis = frame.global_basis.orthonormalized().inverse()
	var face: String = _face_for_normal(to_part * normal)
	var local_point: Vector3 = frame.to_local(point)
	var plate_mm: float = _damage.armour_mm(part, face, local_point)
	var result: HitResult = Armour.resolve(shell_data, velocity.length(), plate_mm,
			Armour.impact_angle(velocity, normal), data.armour.ricochet_angle_deg)
	result.part = part
	result.face = face
	result.target = self
	result.unworn_mm = data.armour.thickness_mm(part, face)
	hit_taken.emit(velocity.normalized())
	if shell_data.caliber_mm >= THREAT_MIN_CALIBER_MM:
		shell_threat.emit(velocity.normalized(), true)
		struck.emit(result.outcome, velocity.normalized())
		# The blow jolts the hull (and the gun with it), more where it lands off-centre.
		apply_impulse(velocity * shell_data.mass_kg * data.hit_jolt_factor, point - global_position)
	var dir: Vector3 = velocity.normalized()
	var hull_basis: Basis = global_basis.orthonormalized().inverse()
	var turret_basis: Basis = _turret.global_basis.orthonormalized().inverse()
	if _damage.apply_hit(shell_data, result, part, face, local_point, to_local(point),
			hull_basis * dir, _turret.to_local(point), turret_basis * dir):
		_knock_out()
	return result


## Host: a mine went off under track `track`: the track is thrown (the tank stands until
## it is repaired), the hull is kicked up. Never a knock-out, nobody scores.
func on_mine(track: StringName, point: Vector3, mine_data: MineData) -> void:
	if _knocked_out or net_puppet:
		return
	_damage.apply_mine(track)
	struck.emit(HitResult.Outcome.HIT, Vector3.UP)
	apply_impulse(Vector3.UP * mass * mine_data.jolt_speed_mps, point - global_position)


## Called by a ModuleFragmentTarget when HE fragments reach an external module.
func on_module_fragment(id: StringName, shell_data: ShellData) -> HitResult:
	if _knocked_out or shell_data.fragment_module_damage <= 0.0:
		return null
	var before: int = _damage.state(id)
	_damage.apply_fragment(id, shell_data)
	if _damage.state(id) == before:
		return null
	var result := HitResult.new()
	result.outcome = HitResult.Outcome.HIT
	result.part = "fragments"
	result.modules.append(String(id))
	result.target = self
	return result


## Called by Shell when a shell this tank fired lands.
func report_shot(result: HitResult) -> void:
	shot_landed.emit(result)


## Undoes a knock-out (respawn, or on the spot on the test bench). A tank moved to a
## spawn has already left its wreck (KothMode.place_tank). A puppet hears of the repair
## before it sees the jump (it shows poses a little late): it leaves the wreck where it
## is now if the jump follows soon.
func repair() -> void:
	if net_puppet and _knocked_out and not _wreck_left:
		_wreck_pending_xform = global_transform
		_wreck_pending_s = WRECK_PENDING_S
		_wreck_pending_no_turret = _turret_tossed
	_knocked_out = false
	_damage.reset()
	# As at the first spawn: the commander unhurt and inside, gun loaded with the first
	# ammo, full smoke, no cooldowns; the squad full and on the tank.
	_commander_wound_remaining = 0.0
	_hatch_progress = 0.0
	_update_hatch(0.0)
	_update_commander_hitbox()
	_reload_remaining = 0.0
	_ammo_index = 0
	_spot_cooldown_remaining = 0.0
	_smoke_left = data.smoke_salvos
	_smoke_ready_ms = 0
	_mg_shot_timer = 0.0
	_since_fired = 999.0
	_at_rest = false
	_rock = 0.0
	_rock_slow = 0.0
	if squad != null and is_instance_valid(squad) and not net_puppet:
		squad.restore_on_tank()
	_set_fire_effect(false)
	if _burning != null:
		_burning.queue_free()
		_burning = null
	_apply_paint(false)
	if _turret_tossed:
		_turret_tossed = false
		_turret.visible = true
		for cs: CollisionShape3D in _turret_shapes:
			cs.disabled = false


func _knock_out() -> void:
	_knocked_out = true
	_wreck_left = false
	_burning = BURNING_SCENE.instantiate()
	add_child(_burning)
	_burning.position = _turret.position
	_apply_paint(true)
	if _damage.ammo_exploded and not net_puppet:
		_toss_turret_random()
	knocked_out.emit()


## Host: the ammo went up: throws the turret turret_toss_min_m..max_m high, short
## throws far more often than long ones.
func _toss_turret_random() -> void:
	var span: float = maxf(data.turret_toss_max_m - data.turret_toss_min_m, 0.0)
	var height: float = data.turret_toss_min_m + span * pow(_rng.randf(), data.turret_toss_bias)
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var side := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
	var velocity: Vector3 = linear_velocity + Vector3.UP * sqrt(2.0 * g * height) \
			+ side.limit_length(1.0) * data.turret_toss_side_mps
	var spin: Vector3 = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0)) * data.turret_toss_spin_rad_s
	toss_turret(velocity, spin)
	turret_tossed.emit(velocity, spin)


## Hides the turret and throws a charred copy of it (a rigid body in group "wrecks")
## with `velocity` and `spin`; it freezes where it comes to rest. Also on clients
## (cosmetic, from the host's event). repair() puts the turret back.
func toss_turret(velocity: Vector3, spin: Vector3) -> void:
	if _turret_tossed or not is_inside_tree():
		return
	_turret_tossed = true
	var root: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	var body := RigidBody3D.new()
	body.name = "TurretWreck"
	body.collision_layer = 1
	body.collision_mask = 1
	body.mass = TURRET_WRECK_MASS_KG
	body.continuous_cd = true
	body.add_to_group(&"wrecks")
	body.add_collision_exception_with(self)   # it starts sitting on the hull
	root.add_child(body)
	body.global_transform = Transform3D(_turret.global_basis.orthonormalized(),
			_turret.global_position)
	body.reset_physics_interpolation()
	var to_body: Transform3D = body.global_transform.affine_inverse()
	for mi: MeshInstance3D in _turret.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.material_override = _charred_material
		body.add_child(copy)
		copy.transform = to_body * mi.global_transform
	for cs: CollisionShape3D in _turret_shapes:
		if cs.shape == null:
			continue
		var shape := CollisionShape3D.new()
		shape.shape = cs.shape.duplicate()
		body.add_child(shape)
		shape.transform = to_body * cs.global_transform
		cs.set_deferred("disabled", true)
	_turret.visible = false
	body.linear_velocity = velocity
	body.angular_velocity = spin
	# Back on the hull it may land on it; at rest it turns static (cheap, stays put).
	get_tree().create_timer(TURRET_WRECK_EXCEPTION_S).timeout.connect(func() -> void:
		if is_instance_valid(body) and is_instance_valid(self):
			body.remove_collision_exception_with(self))
	body.sleeping_state_changed.connect(func() -> void:
		if body.sleeping:
			body.set_deferred("freeze", true))
	get_tree().create_timer(TURRET_WRECK_FREEZE_S).timeout.connect(func() -> void:
		if is_instance_valid(body):
			body.freeze = true)


## Leaves a burnt-out copy of the tank where it stands, for the rest of the match: solid
## for shells, tanks and sight, but without any logic. Called before a knocked-out
## tank is moved to its spawn (KothMode.place_tank, repair, a puppet's jump); once per
## knock-out.
func leave_wreck() -> void:
	if not _knocked_out or _wreck_left or not is_inside_tree():
		return
	_wreck_left = true
	_make_wreck(global_transform)
	wreck_left.emit(global_transform, _turret.rotation.y, _gun_pivot.rotation.x)


## A wreck_only tank (in the tree, placed): turns turret and gun, leaves its wreck and
## goes. For players who join after the wreck was made.
func make_wreck_here(turret_yaw: float, gun_pitch: float) -> void:
	_turret.rotation.y = turret_yaw
	_gun_pivot.rotation.x = gun_pitch
	_sync_turret_shapes()
	_make_wreck(global_transform)
	remove_from_group("tanks")
	queue_free()


func _make_wreck(at: Transform3D, no_turret: bool = false) -> void:
	var to_tank: Transform3D = global_transform.affine_inverse()
	var wreck := StaticBody3D.new()
	wreck.name = "Wreck"
	wreck.collision_layer = 1
	wreck.collision_mask = 0
	wreck.add_to_group(&"wrecks")
	var root: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	root.add_child(wreck)
	wreck.global_transform = at
	wreck.reset_physics_interpolation()
	for mi: MeshInstance3D in _visual.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if no_turret and _turret.is_ancestor_of(mi):
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.material_override = _charred_material
		wreck.add_child(copy)
		copy.transform = to_tank * mi.global_transform
	for child: Node in get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.disabled or cs.shape == null:
			continue
		if no_turret and _turret_shapes.has(cs):
			continue
		var shape := CollisionShape3D.new()
		shape.shape = cs.shape.duplicate()
		wreck.add_child(shape)
		shape.transform = to_tank * cs.global_transform
	var wrecks: Array[Node] = get_tree().get_nodes_in_group(&"wrecks")
	if wrecks.size() > MAX_WRECKS:
		wrecks[0].queue_free()


## Smoke and flames while the fuel tank burns (the knock-out has its own).
func _set_fire_effect(on: bool) -> void:
	if on and _fire_effect == null:
		_fire_effect = BURNING_SCENE.instantiate()
		add_child(_fire_effect)
		_fire_effect.position = Vector3(0.0, 0.6, 1.1)
		_fire_effect.scale = Vector3.ONE * 0.6
	elif not on and _fire_effect != null:
		_fire_effect.queue_free()
		_fire_effect = null


func _update_damage(delta: float) -> void:
	_since_fired += delta
	# The gun's recoil shoves the hull past the speed limit for a moment: repairs go on
	# through a shot, with the verdict from just before it.
	if _since_fired > RECOIL_SETTLE_S:
		_at_rest = absf(get_forward_speed()) < data.repair_max_speed_kmh * KMH_TO_MS
	# Held by a thrown track, the crew repairs whatever the driver does with the controls.
	var driving: bool = absf(_command.throttle) >= 0.05 or absf(_command.steering) >= 0.05
	var still: bool = _at_rest and (not driving or _damage.is_immobilised())
	_damage.tick(delta, still)
	_set_fire_effect(_damage.is_burning() and not _knocked_out)
	if _damage.knocked_out and not _knocked_out:
		_knock_out()


func _shape_node(shape: int) -> Node:
	if shape < 0:
		return null
	var owner_id: int = shape_find_owner(shape)
	return shape_owner_get_owner(owner_id) as Node


## Zone face from a normal in the part's own space (forward is -Z).
func _face_for_normal(local_normal: Vector3) -> String:
	if absf(local_normal.y) > ROOF_NORMAL_Y:
		return "roof"
	var angle: float = absf(rad_to_deg(atan2(local_normal.x, -local_normal.z)))
	if angle <= 45.0:
		return "front"
	if angle >= 135.0:
		return "rear"
	return "side"


func _setup_paint() -> void:
	_charred_material = StandardMaterial3D.new()
	_charred_material.albedo_color = CHARRED_COLOR
	_charred_material.roughness = 1.0
	_apply_paint(false)


## Team look (TeamLook, seen from this machine's player): friends keep paint and
## UN-blue markings, enemies get camouflage on paint and markings; charred on all.
func _apply_paint(charred: bool) -> void:
	_look_version = TeamLook.version
	_look_team = team
	paint_visual(_visual, TeamLook.is_friend(team), _charred_material if charred else null)


## Paints a tank's Visual: friends keep paint and blue markings, enemies are
## camouflaged all over; `charred` (if given) covers everything.
static func paint_visual(visual: Node3D, friend: bool, charred: Material = null) -> void:
	var camo: Material = TeamLook.camo()
	# The hull's first surface is the paint (the scene's own on plain box tanks).
	var hull_mesh: Mesh = (visual.get_node("Hull") as MeshInstance3D).mesh
	var paints: Array[Material] = [MeshKit.material(MeshKit.Mat.PAINT), MeshKit.material(MeshKit.Mat.MARK)]
	if hull_mesh != null:
		paints.append(hull_mesh.surface_get_material(0))
	for mesh_instance: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		mesh_instance.material_override = charred
		if mesh_instance.mesh == null:
			continue
		for i: int in mesh_instance.mesh.get_surface_count():
			var painted: bool = paints.has(mesh_instance.mesh.surface_get_material(i))
			mesh_instance.set_surface_override_material(i,
					camo if painted and not friend and charred == null else null)


## Speed along the hull's forward axis (m/s), negative when reversing.
func get_forward_speed() -> float:
	return linear_velocity.dot(-global_basis.z)


## Turret angle relative to the hull (radians, positive = left).
## The turret's place on the hull (hull space).
func get_turret_local_position() -> Vector3:
	return _turret.position


func get_turret_yaw() -> float:
	return _turret.rotation.y


## Gun angle relative to the turret (radians, positive = up).
func get_gun_pitch() -> float:
	return _gun_pivot.rotation.x


## Turret heading in world space (radians, same convention as Node3D rotation.y).
func get_turret_global_yaw() -> float:
	var forward: Vector3 = -_turret.global_basis.z
	return atan2(-forward.x, -forward.z)


## 0 = hatch closed, 1 = fully open.
func get_hatch_progress() -> float:
	return _hatch_progress


## True whenever the hatch isn't fully closed.
func is_commander_exposed() -> bool:
	return _hatch_progress > 0.0


## Commander's eye in world space: rises out of the cupola as the hatch opens.
func get_commander_eye_position() -> Vector3:
	return _head_closed.global_position.lerp(_head_open.global_position,
			smoothstep(0.0, 1.0, _hatch_progress))


## Gunner's sight in world space. Fixed to the gun: follows traverse and elevation.
func get_gunner_sight_transform() -> Transform3D:
	return _gunner_sight.global_transform


## The same as shown on screen this frame (physics interpolation): cameras use these,
## so the view moves as smoothly as the hull is drawn.
func get_gunner_sight_transform_interpolated() -> Transform3D:
	return _gunner_sight.get_global_transform_interpolated()


func get_commander_eye_position_interpolated() -> Vector3:
	return _head_closed.get_global_transform_interpolated().origin.lerp(
			_head_open.get_global_transform_interpolated().origin, smoothstep(0.0, 1.0, _hatch_progress))


func is_loaded() -> bool:
	return _reload_remaining <= 0.0


## Seconds until the gun is loaded again (0 when loaded).
func get_reload_remaining() -> float:
	return _reload_remaining


## Shell in the breech, or the one being loaded. Null if the tank has no ammo.
func get_loaded_shell() -> ShellData:
	if _ammo_index < 0 or _ammo_index >= data.ammo.size():
		return null
	return data.ammo[_ammo_index]


func get_ammo_index() -> int:
	return _ammo_index


func _physics_process(delta: float) -> void:
	_sync_turret_shapes()
	if _look_version != TeamLook.version or _look_team != team:
		_apply_paint(_knocked_out)
	if net_puppet:
		_puppet_process(delta)
		return
	if _knocked_out:
		_command = _idle_command
	else:
		_command = _crew_lag.apply(_input_command, delta, data, is_crew_wounded(&"driver"),
				is_crew_wounded(&"gunner"))
	_update_turret(delta)
	_commander_wound_remaining = maxf(_commander_wound_remaining - delta, 0.0)
	_update_hatch(delta)
	_update_commander_hitbox()
	_update_gun(delta)
	_update_roof_mg(delta)
	_update_mg(delta)
	_update_spotting(delta)
	_update_smoke()
	_update_squad_order()
	_update_damage(delta)
	if _command.abandon and not _knocked_out:
		_knock_out()   # the crew bails out: a loss, but nobody's kill
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(get_rid())
	if state == null:
		return
	var ray_count: int = _left_rays.size() + _right_rays.size()
	var left_points: Array[Vector3] = []
	var left_normals: Array[Vector3] = []
	var right_points: Array[Vector3] = []
	var right_normals: Array[Vector3] = []
	_apply_suspension(state, _left_rays, ray_count, left_points, left_normals)
	_apply_suspension(state, _right_rays, ray_count, right_points, right_normals)

	var grounded: int = left_points.size() + right_points.size()
	if grounded == 0:
		return
	_apply_drive(state, delta, left_points, left_normals, right_points, right_normals)

	# Tracks resist sideways sliding, in proportion to how many wheels touch ground.
	var right_dir: Vector3 = global_basis.x
	var lateral_speed: float = linear_velocity.dot(right_dir)
	var lateral_accel: float = clampf(-lateral_speed / delta,
			-data.track_lateral_grip, data.track_lateral_grip)
	lateral_accel *= float(grounded) / float(ray_count)
	apply_central_force(right_dir * lateral_accel * mass)


func _update_turret(delta: float) -> void:
	if not _command.has_aim:
		return
	# Yaw: aim point in the turret's parent (hull) space; forward is -Z, positive = left.
	var hull_local: Vector3 = (_turret.get_parent() as Node3D).to_local(_command.aim_point)
	var target_yaw: float = atan2(-hull_local.x, -hull_local.z)
	var yaw_step: float = deg_to_rad(data.turret_traverse_speed_deg) * delta * _damage.traverse_factor()
	var yaw_diff: float = wrapf(target_yaw - _turret.rotation.y, -PI, PI)
	_turret.rotation.y = wrapf(_turret.rotation.y + clampf(yaw_diff, -yaw_step, yaw_step), -PI, PI)

	# Pitch: aim point in turret space, measured from the gun pivot.
	var from_pivot: Vector3 = _turret.to_local(_command.aim_point) - _gun_pivot.position
	var horizontal: float = Vector2(from_pivot.x, from_pivot.z).length()
	var target_pitch: float = clampf(atan2(from_pivot.y, horizontal),
			-deg_to_rad(data.gun_max_depression_deg), deg_to_rad(data.gun_max_elevation_deg))
	var pitch_step: float = deg_to_rad(data.gun_elevation_speed_deg) * delta
	_gun_pivot.rotation.x += clampf(target_pitch - _gun_pivot.rotation.x, -pitch_step, pitch_step)


func _update_hatch(delta: float) -> void:
	var target: float = 1.0 if _command.hatch_open and not is_commander_wounded() else 0.0
	_hatch_progress = move_toward(_hatch_progress, target,
			delta / maxf(data.hatch_transition_time_s, 0.01))
	_hatch_hinge.rotation.x = deg_to_rad(HATCH_OPEN_ANGLE_DEG) * _hatch_progress


## Keeps the commander's hitbox on his head; only collides while he's exposed.
func _update_commander_hitbox() -> void:
	_commander_hitbox.position = _head_closed.position.lerp(_head_open.position,
			smoothstep(0.0, 1.0, _hatch_progress)) - Vector3(0.0, COMMANDER_HITBOX_DROP, 0.0)
	_commander_hitbox_shape.disabled = not is_commander_exposed()


func _update_gun(delta: float) -> void:
	var wanted: int = _command.ammo_select
	if wanted >= 0 and wanted < data.ammo.size() and wanted != _ammo_index:
		_ammo_index = wanted
		_reload_remaining = data.reload_time_s
	_reload_remaining = maxf(_reload_remaining - delta, 0.0)
	if _command.fire and not fire_blocked and is_loaded() and get_loaded_shell() != null:
		_fire()


## Time until the commander can spot again (s), 0 when ready.
func get_spot_cooldown_remaining() -> float:
	return _spot_cooldown_remaining


## The squad saw `enemy` at `at`: a mark for the team (like a commander's spot) and a
## contact for the crew (bots use it).
func report_squad_spot(enemy: Node3D, at: Vector3) -> void:
	spotted.emit(at)
	squad_contact.emit(enemy, at)


## Passes the command's squad order on to the squad (it acts on it once).
func _update_squad_order() -> void:
	if squad != null and is_instance_valid(squad) and _command.squad_order != Squad.ORDER_NONE:
		squad.order(_command.squad_order, _command.squad_target)


func _update_spotting(delta: float) -> void:
	_spot_cooldown_remaining = maxf(_spot_cooldown_remaining - delta, 0.0)
	if _command.spot and _spot_cooldown_remaining <= 0.0:
		_spot_cooldown_remaining = data.spot_cooldown_s
		spotted.emit(_command.spot_point)


## Smoke salvos left this life.
func get_smoke_left() -> int:
	return _smoke_left


## Seconds until the next salvo may go (0 = now).
func get_smoke_cooldown() -> float:
	return maxf((_smoke_ready_ms - Time.get_ticks_msec()) * 0.001, 0.0)


func _update_smoke() -> void:
	if not _command.smoke or _smoke_left <= 0 or data.smoke_clouds_per_salvo <= 0 \
			or get_smoke_cooldown() > 0.0:
		return
	_smoke_left -= 1
	_start_smoke_cooldown()
	var points := PackedVector3Array()
	var forward: Vector3 = -_turret.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var n: int = data.smoke_clouds_per_salvo
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for i: int in n:
		var share: float = float(i) / float(n - 1) - 0.5 if n > 1 else 0.0
		var dir: Vector3 = forward.rotated(Vector3.UP, deg_to_rad(data.smoke_spread_deg) * share)
		var p: Vector3 = global_position + dir * data.smoke_distance_m
		var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 60.0, p + Vector3.DOWN * 60.0, 1)
		query.exclude = [get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		points.append(hit["position"] if not hit.is_empty() else Vector3(p.x, global_position.y - 1.0, p.z))
	show_smoke(points)
	smoke_launched.emit(points)


## Lays smoke clouds at `points` (ground). Also on network clients from the host.
func show_smoke(points: PackedVector3Array) -> void:
	var root: Node = get_parent()
	for p: Vector3 in points:
		var cloud := SmokeCloud.new()
		cloud.radius_m = data.smoke_radius_m
		cloud.height_m = data.smoke_height_m
		cloud.lifetime_s = data.smoke_lifetime_s
		root.add_child(cloud)
		cloud.global_position = p
	if data.smoke_sound != null:
		SoundFx.play_at(self, data.smoke_sound, _turret.global_position)


## Network client: the host's tank fired smoke (the own tank counts its salvos down).
func net_show_smoke(points: PackedVector3Array) -> void:
	if net_predict:
		_smoke_left = maxi(_smoke_left - 1, 0)
		_start_smoke_cooldown()
	show_smoke(points)


func _start_smoke_cooldown() -> void:
	_smoke_ready_ms = Time.get_ticks_msec() + int(data.smoke_cooldown_s * 1000.0)


## A gun round passed or landed close without hitting (Shell, host/offline).
func report_near_miss(direction: Vector3) -> void:
	shell_threat.emit(direction, false)
	near_missed.emit(direction)


## Network client, own tank: the host says a round landed close.
func net_near_miss(direction: Vector3) -> void:
	near_missed.emit(direction)


## Swings the roof MG towards the command's MG aim point while it's in use.
func _update_roof_mg(delta: float) -> void:
	if not _command.mg_use_roof or not can_use_roof_mg():
		return
	var local: Vector3 = _turret.to_local(_command.mg_aim_point) - _roof_mg.position
	var target_yaw: float = atan2(-local.x, -local.z)
	var target_pitch: float = atan2(local.y, Vector2(local.x, local.z).length())
	var step: float = deg_to_rad(data.roof_mg.traverse_speed_deg) * delta
	_roof_mg.rotation.y = wrapf(_roof_mg.rotation.y
			+ clampf(wrapf(target_yaw - _roof_mg.rotation.y, -PI, PI), -step, step), -PI, PI)
	_roof_mg_pitch.rotation.x += clampf(target_pitch - _roof_mg_pitch.rotation.x, -step, step)


func _update_mg(delta: float) -> void:
	var roof: bool = _command.mg_use_roof and can_use_roof_mg()
	var mg: MachineGunData = data.roof_mg if roof else data.coax_mg
	if not _command.fire_mg or fire_blocked or mg == null or mg.bullet == null:
		_mg_shot_timer = 0.0
		return
	_mg_shot_timer -= delta
	var interval: float = 60.0 / maxf(mg.rounds_per_minute, 1.0)
	var muzzle: Marker3D = _roof_mg_muzzle if roof else _coax_muzzle
	while _mg_shot_timer <= 0.0:
		_mg_shot_timer += interval
		_fire_bullet(mg, muzzle, roof)


# --- Network --------------------------------------------------------------------------

## Makes this tank a client-side puppet. predict = it's the local player's own tank.
func set_net_puppet(predict: bool) -> void:
	net_puppet = true
	net_predict = predict
	if squad != null:
		squad.net_puppet = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	if not predict:
		_command = _net_command
		_input_command = _net_command


## The controller's command, before any wounded crew's delay (the net code sends the
## local player's to the host).
func get_command() -> TankCommand:
	return _input_command


## A crew member (&"driver", &"gunner") is wounded: he answers late.
func is_crew_wounded(id: StringName) -> bool:
	return _damage != null and _damage.is_wounded(id)


## Seconds until a wounded crew member is fit again (0 when he is).
func get_crew_heal_time_left(id: StringName) -> float:
	return _damage.heal_time_left(id) if _damage != null else 0.0


## Exhaust smoke 0 (idle) .. 1 (full load or a throttle burst): shows over cover.
func get_exhaust_load() -> float:
	return _exhaust.get_spot_load() if _exhaust != null else 0.0


## 1 just after a main-gun shot, falling to 0 over `duration_s` (flash, smoke, dust).
func get_fire_reveal(duration_s: float) -> float:
	return clampf(1.0 - _since_fired / maxf(duration_s, 0.01), 0.0, 1.0)


## State for one snapshot. for_owner adds hp, modules, reload etc. (never sent to others).
func get_net_state(for_owner: bool) -> TankNetState:
	var s := TankNetState.new()
	s.net_id = net_id
	s.position = global_position
	s.rotation = global_basis.orthonormalized().get_rotation_quaternion()
	s.velocity = linear_velocity
	s.turret_yaw = _turret.rotation.y
	s.gun_pitch = _gun_pivot.rotation.x
	s.hatch = _hatch_progress
	s.roof_mg_yaw = _roof_mg.rotation.y
	s.roof_mg_pitch = _roof_mg_pitch.rotation.x
	if _knocked_out: s.flags |= TankNetState.FLAG_KNOCKED_OUT
	if _damage.is_burning(): s.flags |= TankNetState.FLAG_BURNING
	var roof: bool = _command.mg_use_roof and can_use_roof_mg()
	if _command.fire_mg and not fire_blocked and not _knocked_out and get_active_mg(roof) != null:
		s.flags |= TankNetState.FLAG_MG_FIRING
	if roof: s.flags |= TankNetState.FLAG_MG_ROOF
	if is_commander_wounded(): s.flags |= TankNetState.FLAG_WOUNDED
	if for_owner:
		s.flags |= TankNetState.FLAG_OWNER_DATA
		s.hp_fraction = _damage.hp_fraction()
		for id: StringName in TankNetState.MODULES:
			s.module_states.append(_damage.state(id))
		s.reload_s = _reload_remaining
		s.ammo_index = _ammo_index
		s.repair_left_s = _damage.repair_time_left()
		s.repair_total_s = _damage.repair_total()
		s.spot_cooldown_s = _spot_cooldown_remaining
		s.wound_s = _commander_wound_remaining
	return s


## Puppet: pose interpolated by the net code, every frame.
func net_set_pose(xform: Transform3D, turret_yaw: float, gun_pitch: float, hatch: float,
		roof_yaw: float, roof_pitch: float, velocity: Vector3) -> void:
	if xform.origin.distance_to(global_position) > WRECK_JUMP_M:
		# Respawned on the host: the wreck stays where it burnt out.
		if _knocked_out:
			leave_wreck()
		elif _wreck_pending_s > 0.0:
			_wreck_pending_s = 0.0
			_make_wreck(_wreck_pending_xform, _wreck_pending_no_turret)
		global_transform = xform
		reset_physics_interpolation()   # a jump, not a glide across the map
	global_transform = xform
	_net_velocity = velocity
	if net_predict and not _knocked_out:
		# Own tank: keep the predicted turret unless it drifted far from the host's.
		if is_crew_wounded(&"gunner"):
			_turret.rotation.y = turret_yaw
			_gun_pivot.rotation.x = gun_pitch
		else:
			if absf(wrapf(turret_yaw - _turret.rotation.y, -PI, PI)) > deg_to_rad(3.0):
				_turret.rotation.y = lerp_angle(_turret.rotation.y, turret_yaw, 0.2)
			if absf(gun_pitch - _gun_pivot.rotation.x) > deg_to_rad(3.0):
				_gun_pivot.rotation.x = lerpf(_gun_pivot.rotation.x, gun_pitch, 0.2)
		return
	_turret.rotation.y = turret_yaw
	_gun_pivot.rotation.x = gun_pitch
	_hatch_progress = hatch
	_hatch_hinge.rotation.x = deg_to_rad(HATCH_OPEN_ANGLE_DEG) * _hatch_progress
	_roof_mg.rotation.y = roof_yaw
	_roof_mg_pitch.rotation.x = roof_pitch


## Puppet: flags and (own tank) hp/modules/reload from the newest snapshot.
func net_set_status(s: TankNetState) -> void:
	var ko: bool = s.has(TankNetState.FLAG_KNOCKED_OUT)
	if ko and not _knocked_out:
		_knock_out()
	elif not ko and _knocked_out:
		repair()
	_net_command.fire_mg = s.has(TankNetState.FLAG_MG_FIRING)
	_net_command.mg_use_roof = s.has(TankNetState.FLAG_MG_ROOF)
	var wounded: bool = s.has(TankNetState.FLAG_WOUNDED)
	if wounded and not is_commander_wounded():
		_commander_wound_remaining = maxf(s.wound_s, 1.0)
		commander_wounded.emit()
	elif not wounded:
		_commander_wound_remaining = 0.0
	if s.has(TankNetState.FLAG_OWNER_DATA):
		_reload_remaining = s.reload_s
		_ammo_index = s.ammo_index
		_spot_cooldown_remaining = s.spot_cooldown_s
		if wounded:
			_commander_wound_remaining = s.wound_s
		_damage.set_net(s.hp_fraction, s.module_states, s.has(TankNetState.FLAG_BURNING),
				s.repair_left_s, s.repair_total_s)
	else:
		_damage.set_net_burning(s.has(TankNetState.FLAG_BURNING))
	_set_fire_effect(_damage.is_burning() and not _knocked_out)


## Puppet: a main-gun shell the host fired (or a ricochet), shown here without effect.
func net_show_shell(shell_index: int, from: Vector3, velocity: Vector3, flash: bool) -> void:
	var shell_data: ShellData = data.ammo[shell_index] if shell_index >= 0 and shell_index < data.ammo.size() \
			else get_loaded_shell()
	if shell_data == null:
		return
	var shell := SHELL_SCENE.instantiate() as Shell
	get_parent().add_child(shell)
	shell.launch(shell_data, from, velocity, self, true)
	if flash:
		var fx: Node3D = MUZZLE_FLASH_SCENE.instantiate()
		get_parent().add_child(fx)
		fx.global_position = from
		GunSmoke.spawn(get_parent(), from, velocity.normalized(), _gun_smoke_scale(),
				_gun_render_layer)
		if _audio != null:
			_audio.play_gun(from)
	else:
		# No flash = the host's shell bounced off something.
		SoundFx.play_at(self, shell_data.sound_ricochet, from)


## Network client, own tank: the host says a gun round hit it (see struck).
func net_struck(outcome: int, direction: Vector3) -> void:
	struck.emit(outcome, direction)


func _puppet_process(delta: float) -> void:
	_wreck_pending_s = maxf(_wreck_pending_s - delta, 0.0)
	_damage.tick_heal(delta)   # the HUD's heal countdown (the host decides the state)
	if net_predict and not _knocked_out:
		# A wounded gunner answers late on the host: follow its turret, don't predict.
		if not is_crew_wounded(&"gunner"):
			_update_turret(delta)
		_update_hatch(delta)
		_update_roof_mg(delta)
	_update_commander_hitbox()
	_commander_wound_remaining = maxf(_commander_wound_remaining - delta, 0.0)
	_reload_remaining = maxf(_reload_remaining - delta, 0.0)
	_spot_cooldown_remaining = maxf(_spot_cooldown_remaining - delta, 0.0)
	if not _knocked_out:
		_update_mg(delta)   # cosmetic bullets: own command, or the host's "firing" flag


func _fire_bullet(mg: MachineGunData, muzzle: Marker3D, roof: bool) -> void:
	# Random point in a disc of radius dispersion around the barrel's axis.
	var radius: float = sqrt(_rng.randf()) * mg.dispersion_mrad * 0.001
	var angle: float = _rng.randf() * TAU
	var muzzle_basis: Basis = muzzle.global_basis
	var direction: Vector3 = (-muzzle_basis.z + muzzle_basis.x * cos(angle) * radius
			+ muzzle_basis.y * sin(angle) * radius).normalized()
	var bullet := SHELL_SCENE.instantiate() as Shell
	get_parent().add_child(bullet)
	var carry: Vector3 = _net_velocity if net_puppet else linear_velocity
	bullet.launch(mg.bullet, muzzle.global_position,
			direction * mg.bullet.muzzle_velocity_mps + carry, self, net_puppet)
	mg_fired.emit(bullet, roof)


func _fire() -> void:
	var direction: Vector3 = -_muzzle.global_basis.z
	var muzzle_position: Vector3 = _muzzle.global_position
	var shell := SHELL_SCENE.instantiate() as Shell
	get_parent().add_child(shell)
	# The tank's own motion carries over to the shell: firing on the move costs accuracy.
	var shell_data: ShellData = get_loaded_shell()
	shell.launch(shell_data, muzzle_position,
			direction * shell_data.muzzle_velocity_mps + linear_velocity, self)
	var flash: Node3D = MUZZLE_FLASH_SCENE.instantiate()
	get_parent().add_child(flash)
	flash.global_position = muzzle_position
	GunSmoke.spawn(get_parent(), muzzle_position, direction, _gun_smoke_scale(),
			_gun_render_layer)
	if _audio != null:
		_audio.play_gun(muzzle_position)
	apply_impulse(-direction * data.recoil_impulse_ns, muzzle_position - global_position)
	_reload_remaining = data.reload_time_s
	_since_fired = 0.0
	fired.emit(shell)


## Gun smoke cloud size: 1 for a 75 mm gun, more for bigger ones.
func _gun_smoke_scale() -> float:
	var shell_data: ShellData = get_loaded_shell()
	var calibre: float = shell_data.caliber_mm if shell_data != null else 75.0
	return sqrt(maxf(calibre, 10.0) / 75.0)


func _apply_suspension(state: PhysicsDirectBodyState3D, rays: Array[RayCast3D],
		ray_count: int, points: Array[Vector3], normals: Array[Vector3]) -> void:
	var omega: float = TAU * data.suspension_frequency_hz
	var stiffness: float = mass * omega * omega / ray_count
	var damping: float = 2.0 * data.suspension_damping_ratio * mass * omega / ray_count
	var com_global: Vector3 = global_position + state.center_of_mass
	for ray: RayCast3D in rays:
		ray.force_raycast_update()
		if not ray.is_colliding():
			continue
		var point: Vector3 = ray.get_collision_point()
		var up: Vector3 = ray.global_basis.y
		var compression: float = data.suspension_rest_length - ray.global_position.distance_to(point)
		var point_velocity: Vector3 = linear_velocity + angular_velocity.cross(point - com_global)
		var force: float = stiffness * compression - damping * point_velocity.dot(up)
		apply_force(up * maxf(force, 0.0), point - global_position)
		points.append(point)
		normals.append(ray.get_collision_normal())


func _apply_drive(state: PhysicsDirectBodyState3D, delta: float,
		left_points: Array[Vector3], left_normals: Array[Vector3],
		right_points: Array[Vector3], right_normals: Array[Vector3]) -> void:
	var forward: Vector3 = -global_basis.z
	var up: Vector3 = global_basis.y

	# Longitudinal: chase the target speed, limited by acceleration / braking.
	var throttle: float = clampf(_command.throttle, -1.0, 1.0)
	var top_speed_kmh: float = data.max_forward_speed_kmh if throttle >= 0.0 else data.max_reverse_speed_kmh
	var target_speed: float = throttle * top_speed_kmh * KMH_TO_MS * _damage.speed_factor()
	var speed: float = linear_velocity.dot(forward)
	var speeding_up: bool = target_speed * speed >= 0.0 and absf(target_speed) > absf(speed)
	var accel_limit: float = data.acceleration if speeding_up else data.brake_deceleration
	var accel: float = clampf((target_speed - speed) / delta, -accel_limit, accel_limit)
	# The tracks also cancel gravity along the slope (uphill pull, downhill push),
	# up to what the steepest climbable slope needs.
	var gravity_along: float = state.total_gravity.dot(forward)
	var traction_limit: float = maxf(state.total_gravity.length()
			* sin(deg_to_rad(data.max_climb_deg)), accel_limit)
	var drive_force: float = mass * clampf(accel - gravity_along, -traction_limit, traction_limit)
	# Speeding up lifts the nose, braking dips it; the hull rocks on its springs, and
	# the gun with it (no stabiliser), so jerky driving spoils the aim.
	# The share of the tank's own limit counts, so driving off rocks as much as stopping.
	var driving: bool = _damage.speed_factor() > 0.0 and not _damage.is_immobilised()
	var effort: float = clampf(accel / maxf(accel_limit, 0.01), -1.0, 1.0) if driving else 0.0
	_rock = lerpf(_rock, effort, 1.0 - exp(-ROCK_SMOOTHING * delta))
	_rock_slow = lerpf(_rock_slow, _rock, 1.0 - exp(-delta / maxf(data.pitch_rock_kick_time_s, 0.01)))
	apply_torque(global_basis.x * mass * data.pitch_rock_accel
			* (_rock * data.pitch_rock_lever_m + (_rock - _rock_slow) * data.pitch_rock_kick_lever_m))

	# Yaw: chase the target turn rate. Positive yaw (around +Y) turns left.
	var steering: float = clampf(_command.steering, -1.0, 1.0)
	var target_yaw_rate: float = -steering * deg_to_rad(data.max_turn_rate_deg) * _damage.turn_factor()
	var yaw_rate: float = angular_velocity.dot(up)
	var turn_limit: float = deg_to_rad(data.turn_acceleration_deg)
	var yaw_accel: float = clampf((target_yaw_rate - yaw_rate) / delta, -turn_limit, turn_limit)
	var yaw_inertia: float = 1.0 / maxf((state.inverse_inertia_tensor * up).dot(up), 1e-9)
	var yaw_torque: float = yaw_accel * yaw_inertia
	if _damage.speed_factor() <= 0.0:
		yaw_torque = 0.0   # dead engine: no drive at all

	# Skid steer: right track pushing harder turns the tank left, and vice versa.
	var track_split: float = yaw_torque / (2.0 * _track_half_width)
	# A destroyed track gives no drive on its side, but drags like a brake (it doesn't
	# roll freely): the tank can only pivot round it, and still holds on slopes.
	var hold_force: float = 0.5 * mass * clampf(
			clampf(-speed / delta, -data.brake_deceleration, data.brake_deceleration) - gravity_along,
			-traction_limit, traction_limit)
	var left_force: float = drive_force * 0.5 - track_split
	var right_force: float = drive_force * 0.5 + track_split
	if _damage.track_factor(-1) <= 0.0 or _damage.is_immobilised():
		left_force = hold_force
	if _damage.track_factor(1) <= 0.0 or _damage.is_immobilised():
		right_force = hold_force
	var com_global: Vector3 = global_position + state.center_of_mass
	_apply_track_force(left_force, forward, up, com_global, left_points, left_normals)
	_apply_track_force(right_force, forward, up, com_global, right_points, right_normals)


## Track forces act at the wheels' places along and across the hull but at the centre
## of mass' height: they turn the tank but don't pitch it. The pitch from driving and
## braking is the designed rocking alone (pitch_rock_*), the same for every chassis.
func _apply_track_force(force: float, forward: Vector3, up: Vector3, com_global: Vector3,
		points: Array[Vector3], normals: Array[Vector3]) -> void:
	if points.is_empty():
		return
	var per_wheel: float = force / points.size()
	for i: int in points.size():
		var normal: Vector3 = normals[i]
		var direction: Vector3 = (forward - normal * forward.dot(normal)).normalized()
		var at: Vector3 = points[i] + up * (com_global - points[i]).dot(up)
		apply_force(direction * per_wheel, at - global_position)
