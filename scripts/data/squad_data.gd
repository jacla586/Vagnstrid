class_name SquadData
extends Resource
## One kind of infantry squad that rides on a tank (TankData.squad). The squad is one
## unit of a few soldiers: sent by clicking the big map, recalled with a key, never
## further than max_distance_from_tank_m from its tank.

@export var display_name: String = "Rifle squad"
@export var soldier_count: int = 4

@export_group("Movement")
## Running speed on open ground (m/s).
@export var run_speed_mps: float = 4.0
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
## Soldier size (m).
@export var soldier_height_m: float = 1.8
@export var soldier_radius_m: float = 0.3

@export_group("Spotting")
## Sees enemy tanks and soldiers this far (m), all round while holding still...
@export var view_range_m: float = 400.0
## ...but only in this cone ahead while on the move (degrees, full width).
@export var moving_view_cone_deg: float = 140.0
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
## Fires at enemy tanks within this (m)...
@export var at_range_m: float = 150.0
## ...with this spread (mrad): ~70 % at 100 m, ~30 % at 150 m against a tank...
@export var at_dispersion_mrad: float = 18.0
## ...this many times wider against a tank moving faster than at_fast_target_kmh.
@export var at_moving_factor: float = 2.0
@export var at_fast_target_kmh: float = 15.0
## Between two AT rounds (s).
@export var at_interval_s: float = 8.0
@export var at_sound: SoundSetData

@export_group("Smoke and withdrawal")
## Smoke grenades per sortie (refilled on the tank).
@export var smoke_grenades: int = 2
## A tank shell landing this close to a soldier counts as being fired on (m).
@export var near_miss_m: float = 15.0
## Fired on by a tank: smoke this far towards the threat, then fall back this far
## towards the own tank (m).
@export var smoke_ahead_m: float = 8.0
@export var fallback_m: float = 80.0
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
## Fallen soldiers lie where they fell this long (s).
@export var body_time_s: float = 20.0
## One soldier per squad is "Wilhelm": when he is hit, this chance of his scream,
## heard within the sound set's range (50 m).
@export_range(0.0, 1.0) var scream_chance: float = 0.1
@export var scream_sound: SoundSetData
## Radio calls to the own tank (heard only by its player).
@export var radio: RadioData

