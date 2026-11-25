class_name TankData
extends Resource
## All tuning values for one tank type. Code reads these; no balance numbers in code.
## Values are mostly accelerations, so tuning doesn't depend on the tank's mass.

@export var display_name: String = "Unnamed tank"

@export_group("Mass")
@export var mass_kg: float = 30000.0

@export_group("Mobility")
## Top speed driving forward (km/h).
@export var max_forward_speed_kmh: float = 40.0
## Top speed in reverse (km/h).
@export var max_reverse_speed_kmh: float = 8.0
## How fast the tank speeds up (m/s²).
@export var acceleration: float = 1.5
## How fast the tank slows down when throttle is released or reversed (m/s²).
@export var brake_deceleration: float = 4.0
## Rolling out with no throttle when the command coasts (the player letting go of W):
## rolling resistance and engine braking (m/s²). It rocks the hull by its share of
## brake_deceleration, so it dips the nose gently.
@export var coast_deceleration: float = 1.2
## Steepest slope the tracks can still climb (degrees). The tracks cancel gravity on
## slopes up to this; steeper and the tank stalls or slides back.
@export var max_climb_deg: float = 32.0
## Fording (lakes, GroundCover.water_depth at the hull): speed falls with the water's depth,
## by ford_slow_share at ford_depth_m; deeper the tank only crawls (too_deep_speed_factor).
@export var ford_depth_m: float = 1.2
@export var ford_slow_share: float = 0.55
@export var too_deep_speed_factor: float = 0.12
## Deeper than this (m) the water stops the tank like the map edge: it can't drive further
## in and is pushed back towards shallower water (Tank._hold_out_of_deep_water). Lake and
## river bottoms go down to 2 m, so wide water can't be crossed but its shallow rim can.
## 0 = off.
@export var impassable_depth_m: float = 1.6
## Thickest tree trunk this tank can push over (m). Thicker trees stop it.
@export var tree_push_max_diameter_m: float = 0.7
## Hitting a pushable tree at least this fast fells it at once (km/h).
@export var tree_push_min_speed_kmh: float = 6.0
## Share of speed lost when felling a tree on the move (0..1).
@export var tree_push_speed_loss: float = 0.25
## Slower than the minimum speed, keep pushing this long to fell the tree (s).
@export var tree_slow_push_time_s: float = 1.5
## A pushed-over tree falls off to the side of the tank's path, not straight ahead
## (it would block the view): towards the side of the hull's centre line it was struck
## on, this many degrees off the push direction, from min (struck in the middle; side
## by chance) to max (struck at the hull's edge), plus up to ± jitter.
@export var tree_fall_side_min_deg: float = 20.0
@export var tree_fall_side_max_deg: float = 45.0
@export var tree_fall_jitter_deg: float = 8.0
## Max yaw rate when steering fully (degrees/s).
@export var max_turn_rate_deg: float = 30.0
## How fast the yaw rate builds up or stops (degrees/s²).
@export var turn_acceleration_deg: float = 90.0
## Max sideways acceleration the tracks can take before sliding (m/s²).
@export var track_lateral_grip: float = 8.0
## Pressing against another tank or a wreck (low gear, full torque) the tracks pull up to
## this (m/s² of the tank's own mass) instead of `acceleration`: more than a braking
## tank's brake_deceleration, so a tank can shove another one, slowly.
@export var push_accel: float = 6.0
## The extra pull fades to plain `acceleration` at this speed (km/h), so a shoved tank
## (which brakes) or wreck (which drags) only moves at a crawl: a wreck faster.
@export var push_fade_speed_kmh: float = 18.0
## The wreck a knocked-out tank leaves: this share of its mass, with this friction and
## damping, so tanks push it out of the way far more easily than a live tank.
@export var wreck_mass_share: float = 0.35
@export var wreck_friction: float = 0.7
@export var wreck_damp: float = 0.6
## Stuck (Tank._update_unstick): the driver giving throttle or steering for unstick_after_s
## without the hull getting unstick_move_m away or turning unstick_turn_deg (hung on a
## rock, wedged in, on its side) gives a nudge: unstick_lift_mps up and unstick_push_mps
## sideways along the ground, the direction turning each try (the way it tries to go,
## back, left, right). Tilted past unstick_flip_deg it is set upright instead (yaw kept,
## lifted unstick_flip_lift_m). Not when it is meant to stand: knocked out, immobilised,
## move_blocked, in deep water or outside the map edge. 0 s = off.
@export var unstick_after_s: float = 10.0
@export var unstick_move_m: float = 2.0
@export var unstick_turn_deg: float = 25.0
@export var unstick_lift_mps: float = 3.0
@export var unstick_push_mps: float = 3.5
@export var unstick_flip_deg: float = 60.0
@export var unstick_flip_lift_m: float = 1.5

@export_group("Suspension")
## Length of each suspension ray: how far the road wheels reach below the hull (m).
@export var suspension_rest_length: float = 0.6
## Natural bounce frequency of the sprung hull (Hz). Higher = stiffer.
@export var suspension_frequency_hz: float = 1.5
## 1.0 = critically damped (no bounce), lower = bouncier.
@export var suspension_damping_ratio: float = 0.6
## At rest the track bottoms sit this far above the ground (m): the rays start inside
## the hull so the springs' sag brings the tracks down onto it (Tank.ray_origin_y).
@export var track_ground_gap_m: float = 0.04
## The armour shapes of the tracks (and a plain box hull) stop this far above the track
## bottoms (m), so they don't scrape the ground when the hull rocks or crosses bumps.
@export var track_shape_lift_m: float = 0.22
## Speeding up lifts the nose, braking dips it. Full throttle or full braking pitch the
## hull as by a force of mass × pitch_rock_accel this far above the tracks (m), the
## same for speeding up and braking (the share of the tank's own limit counts, not
## m/s²). Bigger = more rocking, so jerky driving spoils the aim. The builder scales
## it with mass (heavier rocks a little more).
@export var pitch_rock_lever_m: float = 3.0
## Extra pitch while the acceleration changes (driving off, starting to brake, coming
## to a halt): a kick that dies away over pitch_rock_kick_time_s, so the hull bobs
## instead of just leaning (m, like pitch_rock_lever_m).
@export var pitch_rock_kick_lever_m: float = 3.0
@export var pitch_rock_kick_time_s: float = 0.5
## The acceleration the rocking acts as at full throttle / full braking (m/s²).
@export var pitch_rock_accel: float = 2.0
## A gun round hitting the hull jolts it: the shell's momentum times this.
@export var hit_jolt_factor: float = 4.0

@export_group("Turret")
## How fast the turret turns relative to the hull (degrees/s).
@export var turret_traverse_speed_deg: float = 20.0
## Gun stabiliser 0..1: the turret and gun drives also take out this share of the hull's
## own pitch and turn (driving rocks the gun less, the turret holds on a turning hull);
## bots' error firing on the move shrinks by the same share.
@export_range(0.0, 1.0) var gun_stabiliser: float = 0.0
## The stabiliser takes out the hull's pitch only up to this rate (deg/s; 0 = no limit):
## it holds the gun through the slow rocking of steady driving, while sharp jolts (a
## throttle kick, braking, a bump) get through and throw the aim off.
@export var gun_stabiliser_max_rate_deg: float = 0.0
## How fast the gun elevates/depresses (degrees/s).
@export var gun_elevation_speed_deg: float = 5.0
## Max gun elevation above the turret's horizontal plane (degrees).
@export var gun_max_elevation_deg: float = 20.0
## Max gun depression below the turret's horizontal plane (degrees, positive number).
@export var gun_max_depression_deg: float = 8.0

@export_group("Optics")
## Time for the commander to open or close the hatch (s).
@export var hatch_transition_time_s: float = 0.8
## Commander's vertical field of view with the hatch open, naked eye (degrees).
@export var commander_fov_deg: float = 70.0
## Binoculars (hatch open only) zoom this many times more than the gunner's
## strongest sight zoom (narrowest gunner_sight_fov_deg).
@export var binocular_zoom_vs_gunner: float = 2.0
## Pitch limits for the commander's head with the hatch open (degrees).
@export var open_pitch_min_deg: float = -40.0
@export var open_pitch_max_deg: float = 60.0
## Vertical field of view through the cupola periscope (degrees).
@export var periscope_fov_deg: float = 45.0
## Size of the periscope's visible window, as fractions of screen width/height.
@export var periscope_window_width: float = 0.55
@export var periscope_window_height: float = 0.22
## Max rotation speed of the periscope (degrees/s). Makes it feel sluggish.
@export var periscope_turn_speed_deg: float = 60.0
## How far the periscope can turn from turret forward (degrees). 180 = all round.
@export var periscope_yaw_limit_deg: float = 180.0
## Pitch limits through the periscope (degrees).
@export var periscope_pitch_min_deg: float = -10.0
@export var periscope_pitch_max_deg: float = 15.0
## Gunner's sight zoom as vertical field of view (degrees): the widest and the narrowest
## of these are the range the mouse wheel zooms through smoothly (GunnerCamera.zoom_step);
## levels between them don't matter any more (2026-11-22: was a step between fixed levels).
@export var gunner_sight_fov_deg: PackedFloat32Array = PackedFloat32Array([30.0, 12.0])
## Gunner's sight range ladder: a mark every step, out to max, labels every label step (m).
@export var sight_range_step_m: float = 100.0
@export var sight_range_max_m: float = 2000.0
@export var sight_range_label_step_m: float = 200.0
## Range where the gunner's sight line crosses the gun's bore (m). The sight sits
## beside the gun; boresighting at this range cancels that gap there and keeps it
## small at other ranges. 0 = sight parallel to the bore.
@export var sight_zero_range_m: float = 800.0

@export_group("Crew")
## How long a hit commander stays wounded (s): hatch locked shut meanwhile.
@export var commander_wound_time_s: float = 90.0
## Time between two spots by the commander (s).
@export var spot_cooldown_s: float = 5.0
## A spot picks the enemy (tank, or a squad's soldier) nearest the marked point within
## this angle seen from the tank, at least spot_snap_min_m; it must be in sight of the
## commander or the own squad's leader. Nothing near: nothing is marked.
@export var spot_snap_deg: float = 2.0
@export var spot_snap_min_m: float = 6.0

@export_group("Armour")
@export var armour: ArmourData

@export_group("Damage")
## Hit points of the tank's structure. Penetrations take ShellData.damage_hp; 0 = knocked out.
@export var structure_hp: float = 100.0
## Where the modules (engine, tracks, turret ring, fuel, ammo) sit.
@export var layout: ModuleLayoutData
## Standing still this long (s; firing and MG fire are fine, see TankDamage) repairs all modules (unless a
## module has its own repair time, ModuleData.repair_time_min_s/max_s).
@export var repair_time_s: float = 25.0
## Slower than this counts as standing still (km/h).
@export var repair_max_speed_kmh: float = 1.0
## After the modules, structure hp comes back this fast while standing still (hp/s)...
@export var repair_hp_per_s: float = 0.4
## ...up to this share of structure_hp.
@export var repair_hp_max_fraction: float = 0.5
## A hit fuel tank burns this long (s), taking fire_hp_per_s. No repairs while burning.
@export var fire_duration_s: float = 10.0
@export var fire_hp_per_s: float = 3.0
## Dirt from a near HE burst on the commander's and gunner's optics fades away with
## this time constant (s): exponential, about gone after 3-4 times it.
@export var optics_dirt_fade_s: float = 6.0
## Bots with dirty optics spot this many times slower at full dirt (in proportion).
@export var optics_dirt_spot_factor: float = 2.5
## Rounds coming within this angle of straight from the front (hull's facing, deg) never
## set off the ammo: it can be damaged but not blown up from the front (more fun: a
## frontal duel isn't decided by one lucky round). From the sides and rear it can.
@export var ammo_safe_front_deg: float = 40.0
## While the fuel burns the crew fights the fire: the tank stands still...
@export var fire_immobilises: bool = true
## ...and the smoke cuts the view: bots see this share of their range, the player gets
## a smoke haze over the view (ViewOverlay).
@export var fire_view_range_factor: float = 0.35
## Top speed with a damaged engine, as a share of normal (destroyed = 0).
@export var engine_damaged_speed_factor: float = 0.5
## Turret traverse with a damaged turret ring, as a share of normal.
@export var ring_damaged_traverse_factor: float = 0.5
## ...and with a destroyed one (0 = jammed).
@export var ring_destroyed_traverse_factor: float = 0.1
## A damaged track (AP hits; HE breaks it, ShellData.breaks_tracks): top speed and turn
## rate as a share of normal.
@export var track_damaged_speed_factor: float = 0.8
@export var track_damaged_turn_factor: float = 0.55
## A destroyed track stops the tank altogether (thrown track: no pivoting on the other
## one) until it is repaired.
@export var broken_track_immobilises: bool = true
## A wounded driver (crew module "driver") answers each throttle/steering change this
## much later, rolled per change (s).
@export var driver_wounded_lag_min_s: float = 0.3
@export var driver_wounded_lag_max_s: float = 0.9
## A wounded gunner (crew module "gunner") lays the gun and fires this much later (s; the
## delay drifts between min and max).
@export var gunner_wounded_lag_min_s: float = 0.2
@export var gunner_wounded_lag_max_s: float = 0.5
## An ammo explosion throws the turret this high (m): min + (max - min) * u^bias with u
## random in 0..1, so short throws are common and long ones rare...
@export var turret_toss_min_m: float = 6.0
@export var turret_toss_max_m: float = 60.0
@export var turret_toss_bias: float = 6.0
## ...a little to the side (up to m/s) and tumbling (up to rad/s per axis).
@export var turret_toss_side_mps: float = 2.5
@export var turret_toss_spin_rad_s: float = 2.0

@export_group("Armament")
## Main-gun ammunition types, in selection-key order (1, 2, ...). The first is
## loaded at start. The sight's range ladder follows the loaded type.
@export var ammo: Array[ShellData] = []
## Time to reload the main gun after a shot (s).
@export var reload_time_s: float = 6.0
## Changing round type with one in the breech (unload, load the other) takes this share
## of reload_time_s; while loading anyway the change costs nothing and saves nothing.
@export_range(0.0, 1.0) var ammo_swap_share: float = 0.4
## Backward impulse on the tank when firing (N·s). Tuned for feel, not history.
@export var recoil_impulse_ns: float = 30000.0
## Machine gun beside the main gun; aims with it. Null = none.
@export var coax_mg: MachineGunData
## Machine gun on the cupola, aimed by the commander with the hatch open. Null = none.
## Uses traverse_speed_deg from its data.
@export var roof_mg: MachineGunData


@export_group("Smoke")
## Smoke salvos per life (back to full on respawn). A salvo lays a screen of
## smoke_clouds_per_salvo clouds smoke_distance_m ahead of the turret, spread over
## smoke_spread_deg.
@export var smoke_salvos: int = 3
## At least this long between salvos (s).
@export var smoke_cooldown_s: float = 20.0
@export var smoke_clouds_per_salvo: int = 3
@export var smoke_distance_m: float = 30.0
@export var smoke_spread_deg: float = 50.0
@export var smoke_radius_m: float = 10.0
@export var smoke_height_m: float = 8.0
@export var smoke_lifetime_s: float = 45.0
## Played at the turret when a salvo goes off. Null = silent.
@export var smoke_sound: SoundSetData

@export_group("Geometry")
## Hull with tracks: width, height, length (m). Today's medium tank by default.
@export var hull_size: Vector3 = Vector3(3.2, 1.4, 6.5)
@export var turret_radius_m: float = 1.2
@export var turret_height_m: float = 0.8
## Barrel length from the gun pivot and its outer radius (m).
@export var gun_length_m: float = 3.6
@export var barrel_radius_m: float = 0.08

## Look and armour shapes (TankModel): "" = the scene's plain boxes, else a style
## (light, sloped, boxy, heavy) set by the builder from the chassis.
@export var model_style: StringName = &""
## From the gun: a turret variant (e.g. box_turret) and a muzzle brake.
@export var turret_variant: StringName = &""
@export var muzzle_brake: bool = false
## From the armour package: its id (heavy adds skirts/appliqué plates).
@export var armour_look: StringName = &"standard"

@export_group("Camouflage")
## Enemies take this many times longer to spot the tank (1 = no camouflage).
@export var camo_spot_factor: float = 1.0
## Builder bookkeeping: what the tank cost in the garage (0 = not built).
@export var cost: int = 0

@export_group("Infantry")
## The squad riding on this tank. Null = none.
@export var squad: SquadData

@export_group("Bots")
## How bots drive this tank (BotRoleData, from the chassis; null = a brawler).
@export var bot_role: BotRoleData

@export_group("Sound")
## Engine, tracks, gun and hatch sounds. Null = silent tank.
@export var sounds: TankSoundData
## The crew's shouts to the player (hit, near miss). Null = quiet crew.
@export var crew_voice: CrewVoiceData

@export_group("Looks")
## Exhaust smoke (null = data/tanks/exhaust_default.tres).
@export var exhaust: ExhaustData


## Vertical field of view through the binoculars (degrees).
func binocular_fov_deg() -> float:
	var narrowest: float = commander_fov_deg
	for fov: float in gunner_sight_fov_deg:
		narrowest = minf(narrowest, fov)
	var half: float = deg_to_rad(narrowest) * 0.5
	return rad_to_deg(2.0 * atan(tan(half) / maxf(binocular_zoom_vs_gunner, 1.0)))
