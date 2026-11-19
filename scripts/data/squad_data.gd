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
@export_group("Escort (F)")
## Close protection: the squad walks this far ahead of its tank, in a line across the
## way it attacks (moving forward: where it drives; else where its gun points).
@export var escort_ahead_m: float = 25.0
## Gap between soldiers in the escort line (m).
@export var escort_spacing_m: float = 6.0
## It moves on when its place is this far off (m), and re-aims a walk when the place
## has moved this far (m).
@export var escort_slack_m: float = 10.0
@export var escort_regoal_m: float = 6.0
## The tank's attack direction only swings by more than this (degrees): the line doesn't
## run round the tank every time the turret turns a little.
@export var escort_turn_deg: float = 35.0
@export_group("")
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
## The squad view's eye stays this far above the vegetation he kneels or lies in (m), so
## a lying leader doesn't look into grass blades (bots' and squads' sight ignores the
## viewer's own vegetation anyway).
@export var view_above_cover_m: float = 0.15
## The leader viewed through falls: the view follows his head down this long (s), turning
## this share of the way to how his head turns, then goes to the next leader.
@export var death_follow_s: float = 2.5
@export_range(0.0, 1.0) var death_follow_turn_share: float = 0.6
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
@export var anim_hold: StringName = &"kneel_idle"
## Holding and lying while he fires, and this long (s) after his last shot, facing where
## he shot ("" = the plain hold / prone animation).
@export var anim_hold_fire: StringName = &"crouch_aim"
@export var anim_prone_fire: StringName = &"prone_fire"
@export var anim_fire_hold_s: float = 2.5
## Falling: standing (one at random), on the move, kneeling, lying ("" = he stays as he
## lies). anim_death is the fallback.
@export var anim_death: StringName = &"death"
@export var anim_deaths_standing: Array[StringName] = []
@export var anim_death_moving: StringName = &""
@export var anim_death_kneeling: StringName = &""
@export var anim_death_prone: StringName = &""
## Played between two animations ("from>to" -> clip), e.g. kneeling down or lying down;
## the new animation follows when it ends. Only into still poses (moving blends at once).
@export var anim_transitions: Dictionary = {}
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

@export_group("Ambush")
## Holding this long (s) the squad lies down in ambush (each at his covered spot)...
@export var ambush_after_s: float = 4.0
## ...and holds rifle fire beyond this (m) until it has fired or lost a man.
@export var ambush_rifle_range_m: float = 100.0
## Lying: height of the body (m), the eyes above the ground and ahead of the feet (m),
## time to get down or up (s).
@export var prone_height_m: float = 0.45
@export var eye_height_prone_m: float = 0.35
@export var prone_eye_forward_m: float = 1.5
@export var prone_change_s: float = 1.0
## The lying animation (from model_animations); his body lies centred this far ahead of
## his position (m, for the hitbox).
@export var anim_prone: StringName = &"prone"
@export var prone_body_ahead_m: float = 0.9
## Each soldier lies down up to this long (s, at random) after the squad goes to ground.
@export var prone_delay_max_s: float = 1.5
## Lying, a soldier who has to move first gets up on the spot with this animation (the
## fallback if the library lacks it; "" = none, he blends straight into the move),
## played this much faster.
@export var anim_get_up: StringName = &""
@export var anim_get_up_fallback: StringName = &""
@export var anim_get_up_speed: float = 1.0
## Without a model (a capsule): it is tipped forward this much (degrees) round the feet
## and lifted this much (m).
@export var prone_pitch_deg: float = 85.0
@export var prone_lift_m: float = 0.12

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

@export_group("Being spotted")
## How these soldiers are seen by others (bots and squads; the player only by eye).
## On top of soldier_spot_factor and cover (the viewer's ConcealmentData): the uniform...
@export var camo_spot_factor: float = 1.3
## ...on the move (standing still: the viewer's ConcealmentData stationary factor)...
@export var moving_spot_factor: float = 1.0
## ...kneeling and lying down (times longer)...
@export var kneel_spot_factor: float = 1.5
@export var prone_spot_factor: float = 3.0
## ...and distance: normal up to soldier_easy_range_m, then this much longer per 100 m.
@export var soldier_easy_range_m: float = 150.0
@export var soldier_spot_per_100m: float = 0.8
## Close by, cover and ground vegetation hide less: within this their effect on the spot
## time fades with (distance / this)² (m; a man running through crops 20 m away is seen).
@export var soldier_close_range_m: float = 80.0
## A group shows: each other soldier of the same squad in sight adds this share of a
## look to every one in sight (4 men running: about 4 times as quick to spot).
@export var group_spot_share: float = 1.0
## A soldier who just fired shows: for this long after a rifle shot / an AT round (back
## blast) (s) the factor is only reveal_spot_factor (no cover, stance or distance).
@export var reveal_rifle_s: float = 3.0
@export var reveal_at_s: float = 8.0
@export var reveal_spot_factor: float = 1.0
## An enemy still in sight is marked again for the team this often (s).
@export var mark_interval_s: float = 8.0
## How often the squad looks around (s).
@export var scan_interval_s: float = 0.5

@export_group("Rifles")
## HE fragments reach soldiers this much farther than other targets (both the lethal and
## the max radius): men in the open are what HE is for.
@export var fragment_radius_factor: float = 1.25
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
## An enemy commander who comes up out of his hatch draws rifle fire only after this long
## (s, random between the two, drawn each time he shows): noticing him and taking aim.
@export var commander_reaction_min_s: float = 2.4
@export var commander_reaction_max_s: float = 5.0
@export var rifle_sound: SoundSetData

@export_group("AT rounds")
@export var at_round: ShellData
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

@export_group("Mines")
## The mine the squad lays (null = none). The soldiers carry them (loadout); at most
## max_mines_out lie out at a time (another removes the oldest)...
@export var mine: MineData
@export var max_mines_out: int = 2
## ...takes this long to lay one (s), kneeling (animation from model_animations)...
@export var mine_lay_time_s: float = 6.0
@export var anim_lay_mine: StringName = &"kneel_idle"

@export_group("Loadout")
## What a soldier carries besides his rifle: one AT round or one mine, never both, so
## no single man carries the squad's kit.
enum Kit { NONE, AT, MINE }
## Each soldier's kit by index (soldier_count long; missing = NONE). A man who falls
## loses his; the AT gunner and the mine layer are men who carry one.
@export var loadout: Array[Kit] = [Kit.MINE, Kit.AT, Kit.MINE, Kit.AT]
## Mounted, one man missing his kit gets it back this often (s). Men come back slower
## (refill_time_s).
@export var kit_refill_s: float = 20.0

@export_group("Smoke and withdrawal")
## Smoke grenades per sortie (refilled on the tank).
@export var smoke_grenades: int = 1
## With this many men down the squad smokes and pulls back (fewer: it fights on).
@export var withdraw_after_losses: int = 2
## Withdrawing: smoke this far towards the threat, then run for cover at most
## fallback_m away (m), or to the tank if that is nearer or there is none.
@export var smoke_ahead_m: float = 8.0
@export var fallback_m: float = 80.0
## After a halt to fight on the way, walk on once nothing in reach has been in sight
## this long (s).
@export var contact_resume_s: float = 4.0
## No new smoke or withdrawal within this long of the last (s).
@export var withdraw_cooldown_s: float = 15.0
## Grenade smoke: smaller than a tank's salvo cloud (~65 %: TankData.smoke_radius_m/height_m).
@export var smoke_radius_m: float = 6.5
@export var smoke_height_m: float = 5.2
@export var smoke_lifetime_s: float = 30.0

@export_group("Infantry fight")
## An enemy squad spotted within this is a threat: the squad goes for it (it leaves a
## move order for it and walks on afterwards; a recall or a withdrawal are kept) (m).
@export var engage_range_m: float = 55.0
## Out of rifle reach it closes to this share of rifle_range_m from the enemy.
@export_range(0.1, 1.0) var engage_approach_share: float = 0.8
## Only this many men or more start a fight (fewer still shoot back).
@export var engage_min_alive: int = 3
## The fight is over when no soldier of the enemy squad has been seen this long (s).
@export var engage_forget_s: float = 10.0
## Fired on by a squad it wasn't fighting: surprised this long (s), its rifles spread
## this many times wider meanwhile.
@export var surprised_s: float = 3.0
@export var surprised_dispersion_factor: float = 2.5
## The upper hand (it downed one of theirs before losing a man): a fast assault in
## pairs, one pair running assault_leap_m past the other while the other fires...
@export var assault_leap_m: float = 10.0
## ...at this times its running pace...
@export var assault_speed_factor: float = 1.4
## ...the pair in place firing at least this long before the next pair runs (s)...
@export var assault_overwatch_s: float = 1.5
## ...in a line this far apart across the attack...
@export var assault_spacing_m: float = 6.0
## ...until this close to the enemy (m); then it holds and fights there.
@export var assault_close_m: float = 35.0

@export_group("Losses")
## Mounted, one missing soldier comes back this often (s) (his kit after kit_refill_s);
## smoke is topped up when the squad is full again.
@export var refill_time_s: float = 20.0
## A squad that lost everyone is back on the tank, full, after this long (s).
@export var wipe_cooldown_s: float = 60.0
## Fallen soldiers drop where they fell and are gone after this long (s): long enough
## for the death animation, no bodies lying about.
@export var body_time_s: float = 3.0
## An enemy tank going at least this fast (m/s) kills soldiers under its hull...
@export var run_over_min_speed_mps: float = 1.0
## ...counting this much (m) round the hull's footprint.
@export var run_over_margin_m: float = 0.3
## One soldier per squad is "Wilhelm": when he is hit, this chance of his scream,
## heard within the sound set's range (100 m, even with the hatch shut).
@export_range(0.0, 1.0) var scream_chance: float = 0.1
@export var scream_sound: SoundSetData
## Radio calls to the own tank (heard only by its player).
@export var radio: RadioData

