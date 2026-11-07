class_name SquadData
extends Resource
## One kind of infantry squad that rides on a tank (TankData.squad). The squad is one
## unit of a few soldiers: sent by clicking the big map, recalled with a key, never
## further than max_distance_from_tank_m from its tank.

@export var display_name: String = "Rifle squad"
@export var soldier_count: int = 4

@export_group("Movement")
## Running speed on open ground (m/s).
@export var run_speed_mps: float = 4.8
## Steepest ground a soldier walks up (degrees). Walls and roofs are far steeper, so
## soldiers go round houses instead of over them.
@export var max_climb_deg: float = 45.0
## Path costs for walking (forest and bushes cheap, open ground dear).
@export var tactics: TacticsData
## Soldiers keep about this far apart in their wedge (m).
@export var spacing_m: float = 4.0
## Orders are cut off at this distance from the tank (m)...
@export var max_distance_from_tank_m: float = 300.0
## ...and if the tank drives more than this beyond it, the squad comes back (m).
@export var leash_margin_m: float = 60.0
## Getting this close to its tank while coming back, the squad mounts (m).
@export var mount_distance_m: float = 8.0
## Soldiers get off this far behind the tank (m).
@export var dismount_behind_m: float = 6.0

@export_group("Look")
## Holding still the soldiers kneel: height as a share of standing...
@export var kneel_height_share: float = 0.6
## ...taking this long to kneel or get up (s).
@export var stance_change_s: float = 0.5
## The leader's eyes, standing and kneeling (m above the ground).
@export var eye_height_standing_m: float = 1.65
@export var eye_height_kneeling_m: float = 1.05
## Field of view through the leader's eyes, and through his binoculars (degrees).
@export var view_fov_deg: float = 70.0
@export var binocular_fov_deg: float = 10.0
## Soldier model (glTF scene). Null = placeholder capsules.
@export var model: PackedScene
## Scale and turn (degrees) to make the model soldier_height_m tall, feet at the
## origin, facing -Z.
@export var model_scale: float = 0.065
@export var model_yaw_deg: float = 180.0
## Model materials repainted in the uniform colour (lighter and darker shades).
@export var uniform_materials: PackedStringArray = PackedStringArray()
## Its pose animation, if any (played once to set the pose; without model_animations).
@export var model_animation: StringName = &""
## Animations for the model (tools/bake_soldier_animations.gd). With them soldiers run,
## crouch and fall instead of being squashed or tipped over.
@export var model_animations: AnimationLibrary
@export var anim_move: StringName = &"jog"
@export var anim_hold: StringName = &"crouch_idle"
@export var anim_death: StringName = &"death"
## The move animation looks right at this speed; faster soldiers play it faster (m/s).
@export var anim_move_speed_mps: float = 3.2
## Blend between animations (s).
@export var anim_blend_s: float = 0.25
## Uniform colour: green or brown, naturally hard to see.
@export var uniform_color: Color = Color(0.29, 0.36, 0.2)
## Enemy camouflage blotches per metre (TeamLook).
@export var camo_pattern_per_m: float = 3.5
## Model materials painted UN blue on friends (the helmet; its material is shared with
## a few other bits) and left as they are on enemies.
@export var friend_blue_materials: PackedStringArray = PackedStringArray()
## Soldier size (m).
@export var soldier_height_m: float = 1.8
@export var soldier_radius_m: float = 0.3

@export_group("Spotting")
## Sees enemy tanks and soldiers this far (m), all round while holding still...
@export var view_range_m: float = 500.0
## Soldiers see through vegetation (bush and tree crowns): entry k is how far they see
## through k + 1 layers (m). [500, 300] = one layer to 500 m, two to 300 m.
@export var see_through_ranges_m: PackedFloat32Array = PackedFloat32Array([500.0, 300.0])
## ...but only in this cone ahead while on the move (degrees, full width).
@export var moving_view_cone_deg: float = 240.0
## Base time to make out an enemy tank in plain view (s); cover, stillness and how
## much of it shows change it like for tank crews (concealment).
@export var spot_time_s: float = 2.0
## Enemy soldiers are small: this many times longer to spot.
@export var soldier_spot_factor: float = 2.5
@export var concealment: ConcealmentData
## An enemy still in sight is marked again for the team this often (s).
@export var mark_interval_s: float = 8.0
## How often the squad looks around (s).
@export var scan_interval_s: float = 0.5

@export_group("Rifles")
@export var rifle_bullet: ShellData
## Each soldier fires bursts of this many shots, this often (s), while holding still.
@export var rifle_burst_shots: int = 3
@export var rifle_burst_interval_s: float = 2.5
@export var rifle_shot_gap_s: float = 0.15
## Fires at exposed commanders and enemy soldiers within this (m)...
@export var rifle_range_m: float = 300.0
## ...with this random spread (mrad, radius): low accuracy (about 5-10 % per burst at
## a commander 200 m off).
@export var rifle_dispersion_mrad: float = 9.0
@export var rifle_sound: SoundSetData

@export_group("AT rounds")
@export var at_round: ShellData
## Rounds per sortie (refilled on the tank).
@export var at_rounds: int = 2
## Fires at enemy tanks within this (m), aimed at the track facing the squad (a hit
## throws it: the tank stands until it is repaired)...
@export var at_range_m: float = 150.0
## ...with this spread (mrad): ~70 % at 100 m, ~30 % at 150 m against a tank...
@export var at_dispersion_mrad: float = 18.0
## ...this many times wider against a tank moving faster than at_fast_target_kmh.
@export var at_moving_factor: float = 2.0
@export var at_fast_target_kmh: float = 15.0
## Between two AT rounds (s).
@export var at_interval_s: float = 8.0
## The gunner stands, turns to the tank, calls "Skott kommer! Klart bakåt!" on the
## radio and fires this long after (s)...
@export var at_aim_time_s: float = 3.0
## ...then keeps the launcher on his shoulder this long (s).
@export var at_hold_after_s: float = 1.5
## Animation while aiming the launcher (from model_animations).
@export var anim_at_aim: StringName = &"aim"
## The launcher: a plain tube on the right shoulder, its middle at this point in the
## soldier's space (m, forward = -Z), and its size and colour.
@export var at_launcher_offset: Vector3 = Vector3(0.13, 1.64, -0.1)
@export var at_launcher_length_m: float = 1.1
@export var at_launcher_radius_m: float = 0.06
@export var at_launcher_color: Color = Color(0.25, 0.3, 0.2)
## Model meshes of the rifle, hidden while he holds the launcher (find_children pattern).
@export var rifle_mesh_pattern: String = "M4*"
@export var at_sound: SoundSetData

@export_group("Smoke and withdrawal")
## Smoke grenades per sortie (refilled on the tank).
@export var smoke_grenades: int = 1
## A soldier down: smoke this far towards the threat, then run for cover at most
## fallback_m away (m), or to the tank if that is nearer or there is none.
@export var smoke_ahead_m: float = 8.0
@export var fallback_m: float = 80.0
## After a halt to fight on the way, walk on once nothing in reach has been in sight
## this long (s).
@export var contact_resume_s: float = 4.0
## No new smoke or withdrawal within this long of the last (s).
@export var withdraw_cooldown_s: float = 15.0
@export var smoke_radius_m: float = 9.0
@export var smoke_lifetime_s: float = 30.0

@export_group("Losses")
## Mounted, one missing soldier comes back this often (s); AT rounds and smoke are
## topped up when the squad is full again.
@export var refill_time_s: float = 20.0
## A squad that lost everyone is back on the tank, full, after this long (s).
@export var wipe_cooldown_s: float = 60.0
## Fallen soldiers drop where they fell and are gone after this long (s): long enough
## for the death animation, no bodies lying about.
@export var body_time_s: float = 3.0
## One soldier per squad is "Wilhelm": when he is hit, this chance of his scream,
## heard within the sound set's range (100 m, even with the hatch shut).
@export_range(0.0, 1.0) var scream_chance: float = 0.1
@export var scream_sound: SoundSetData
## Radio calls to the own tank (heard only by its player).
@export var radio: RadioData

