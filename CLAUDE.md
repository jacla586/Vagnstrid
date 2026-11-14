# Vagnstrid – tank game (hobby project)

Semi-realistic tank game in the spirit of War Thunder, vs bots (multiplayer later).
Few tanks, lots of feel. Not for publication. Full spec (Swedish):
`Stridsvagnsspel – specifikation (utkast).md` – read it when working on a new area.

**Core idea (USP):** the player is the commander in the cupola. Hatch open = full
360° view and binoculars, but exposed to shrapnel/HE/snipers. Hatch closed = safe,
but narrow periscope view. No markers above enemies in the 3D world; spotting only
shows on the minimap. This is what we test first.

## Engine and language – IMPORTANT

- **Godot 4.7** (4.7.2-stable), Forward+ renderer, **Jolt Physics** (set in project.godot).
- **GDScript only, always statically typed** (`var speed: float = 10.0`, typed
  function args and return values, `:=` where the type is obvious).
- **Godot 4 syntax only.** Much code online is Godot 3. Common traps:
  - `Node3D` not `Spatial`, `CharacterBody3D` not `KinematicBody`
  - `@export`, `@onready` not `export`, `onready`
  - `move_and_slide()` takes no arguments; use the `velocity` property
  - `instantiate()` not `instance()`, `await` not `yield`, `super()` not `.method()`
  - `signal.connect(callable)` not `connect("signal", self, "method")`
  - `deg_to_rad()` not `deg2rad()`, `FileAccess`/`DirAccess` not `File`/`Directory`
- **English throughout:** code, names, comments, commit messages.
- Naming: `snake_case` files, variables, functions; `PascalCase` for `class_name`
  and nodes; `UPPER_SNAKE_CASE` for constants.

## Architecture rules

- **All game data in data files, not in code.** Armour, penetration, speed, optics,
  fire-control level, costs etc. live in custom `Resource` classes saved as `.tres`.
  Code reads them; no magic numbers for balance values.
- **Tanks never read input directly.** Input (player keyboard/mouse, bot AI, later
  network) produces a command (throttle, steering, turret aim, fire, hatch...). The
  tank only acts on commands. This keeps bots and future multiplayer possible.
- **Bots follow the same rules as players** – same vision and spotting, no cheating.
- Fire control and optics are per-tank properties in data, so all levels (none,
  rangefinder, full computer) run on the same code.
- No friendly fire at all: `Tank.team_of()`/`is_friendly()`; shells that hit their
  shooter's team do nothing and `Explosion.detonate()` spares the shooter's team.
- Shells are simulated (gravity, travel time); hit detection by raycasting from the
  previous to the current position each physics frame, not by fast physics bodies.
  MG bullets are Shells too (`mg_bullet.tres`).
- Damage model (`TankDamage`, owned by Tank): structure hp (`TankData.structure_hp`) and
  modules from `TankData.layout` (`ModuleLayoutData`, e.g. `data/tanks/layout_medium.tres`:
  engine, fuel, tracks, turret ring, ammo in the turret rear). A penetration takes
  `ShellData.damage_hp` and damages modules on the shell's path (`module_reach_m`), all three times
  `ShellData.penetration_damage_share`: full with `full_damage_surplus_calibres` (0.5) × calibre of
  penetration to spare, falling to `pen_damage_floor` (0.35) when just through (HE and the squad AT
  round: always full); under 0.7 the shooter reads "WEAK PENETRATION" (`HitResult.weak`). Each
  internal module hit taking `ModuleData.structure_damage_hp` more (engine 20, fuel/ring 15, crew 10); ammo =
  knocked out (never from within `TankData.ammo_safe_front_deg` (40) of straight ahead of the hull:
  then damaged at worst, `TankDamage._from_front`), fuel = fire. Hits that don't penetrate wear their plate cell (`ArmourData`
  wear settings, `ShellData.wear_mm`). Tracks are external: a gun round landing on one breaks
  it if `ShellData.breaks_tracks` (HE, AT rounds), else damages it; HE fragments
  (`ModuleFragmentTarget`) damage them. Effects (`TankDamage.speed_factor/turn_factor/
  traverse_factor`, shares in TankData): engine damaged 50 % speed, destroyed stopped (either way a tall
  black smoke column, `Tank.is_engine_smoking`, `EffectsSetData.engine_smoke`, snapshot flag
  `FLAG_ENGINE_SMOKE`: everyone sees it, though enemy hp is never sent); fire
  stands the tank still, a haze for the player (`FireHaze`), bots see
  `fire_view_range_factor`; ring 50 % / 10 % traverse; damaged track 80 % speed and 55 % turn
  rate, destroyed = immobilised (a braked track stops its own side's travel,
  `Tank._track_hold_force`, so a stuck tank that was turning stops turning). Standing still (no throttle, no steering) `repair_time_s` repairs
  modules (firing and MG hits don't interrupt; a penetrating gun round, an AT round
  (`ShellData.stops_repair_on_hit`) or fire restarts it; a module breaking meanwhile
  takes its full time), then hp creeps back to `repair_hp_max_fraction`. The player sees own hp/modules
  (`DamagePanel`: a see-through top-down tank icon bottom left with the turret turned and
  modules green/yellow/red), never the enemy's; bots stop to repair when they have no target.
  Crew modules (`ModuleData.crew`: `driver` front left in the hull, `gunner` in the turret) are
  only ever wounded (never destroyed or a knock-out), heal `heal_time_s` (60) after the last
  wound whatever the tank does, and don't count for repairs. Wounded, they answer late
  (`CrewLag`, applied by Tank on the host, so bots too; `Tank.get_command()` is the
  controller's command): driver `TankData.driver_wounded_lag_*` (0.3-0.9 s per change),
  gunner `gunner_wounded_lag_*` (0.2-0.5 s, drifting) on aim, gun and coax fire; the own
  client follows the host's turret then instead of predicting. HUD: a WOUNDED line in
  `DamagePanel`.
- Infantry squads (`Squad`, `scripts/squad/`; data `SquadData`, `data/squads/`,
  `TankData.squad`): one unit of 4 soldiers per tank, made by the tank and living in
  the map beside it. Orders only via `TankCommand.squad_order`/`squad_target`
  (move / recall / mine / escort); the tank passes them on. Escort (F, `squad_escort`,
  `Squad.ORDER_ESCORT`): close protection; it gets off if mounted and keeps a line
  (`SquadData.escort_*`: 25 m ahead, 6 m apart) across the tank's attack direction (driving
  forward: where it goes; else where the gun points; swings only past 35°), walks there when
  10+ m off (`escort_slack_m`), so it falls behind a driving tank and catches up when it stops;
  it halts and fights infantry and exposed commanders in reach like a moving squad, finds
  mines as squads do, and withdraws when hit; no "in position" calls. Any other order, a
  recall, mounting or the tank's loss ends it (`Squad._escort`; packet flags bit 6, HUD
  "ESCORTING"); radio "Närskydd!" (`RADIO_ESCORT`) when it starts, after "Avsittning!" if mounted.
  Mounted it rides unseen; sent out it gets
  off behind the tank and walks paths from `TacticalMap.for_scene(scene, tactics)`
  with infantry costs (`data/squads/tactics_infantry.tres`), at most
  `max_distance_from_tank_m` (300) from the tank; recalled or left behind it runs back
  and mounts. Soldiers move one by one: a loose place each on the move (own pace,
  drift; no steeper than `SquadData.max_climb_deg` (45°) uphill and a knee-high wall ray,
  so they go round houses: `Squad._step` turns off to the side; probed only every
  `PROBE_TICKS` ticks via `_probed_step`, walking the checked stretch in between), and when holding each his own spot 4-9 m round the squad's point (covered if
  possible), facing out and kneeling once still. The leader is the
  first living soldier; V (`toggle_squad_view`, `SquadCamera`, `PlayerViews` SQUAD
  mode) looks through his eyes while the squad is off the tank: look and spot only, no
  control, no turret or guns; binoculars on B. Spotting like tank crews (sight lines,
  concealment; all round holding, a cone ahead moving): spotted enemies become team
  marks (`Tank.report_squad_spot`, also signal `squad_contact`). Soldiers have
  `SoldierHitbox` areas (layer 3, fragment targets): any hit puts one down, as does an enemy tank
  driving over him (`Squad._check_run_over`, host: hull footprint, `SquadData.run_over_*`); one is
  "Wilhelm" (10 % scream, 100 m, on Master so the hatch doesn't muffle it:
  `SoundSetData.bus`). Holding still they fire rifles (`rifle_bullet.tres`,
  low accuracy) at exposed commanders and soldiers, and AT rounds (`squad_at.tres`, an HE charge: 30 mm,
  breaks the track it lands on, blast (14 hp, 20 module damage within 1.5 m: an engine hit turns it
  yellow), dirt on the optics, small fragments;
  `ShellData.finishes_only`: knocks out only by taking the last points of a tank already under
  `finish_below_share` (15 %) of its hp before the hit, never the ammo, never sets fire (`sets_fire`):
  rare but possible; credit goes to the squad's tank, `Tank._shooter_tank`, kill feed "Bazooka",
  `ShellData.kill_feed_name` -> `HitRecord.weapon`, `Tank.get_kill_weapon`) at tanks within 150 m, aimed at the track
  facing them (shots allow for drop). The AT gunner stands, turns to the tank, swaps
  his rifle for a plain launcher tube (`SquadData.at_launcher_*`, "aim" animation),
  radios "Skott kommer! Klart bakåt!" (`RADIO_AT_FIRE`, first in the queue) and fires
  `at_aim_time_s` (3 s) later with a back blast (once called, the round always goes: at the
  last seen track if sight is lost, at once if the squad must move; only the gunner's fall
  or the target's knock-out stops it), then "Träff!"/"Miss!" (`RADIO_AT_HIT/MISS`, from
  `Shell.finished`, straight after the call in the queue); clients see it via `rpc_squad_aim`. Drawing detail (`Squad._process`, local): by seen distance (/ zoom) soldiers beyond
  `LOD_NEAR_M` (60) cast no shadow and their AnimationPlayers (manual mode) step at 15 Hz, beyond 250 m at 6 Hz,
  off screen at 2 Hz; nobody is hidden. A destroyed track immobilises the tank
  (`TankData.broken_track_immobilises`) until repaired; tracks take
  `ModuleData.repair_time_min_s..max_s` (20-30 s) standing still, other modules
  `TankData.repair_time_s`. Soldiers see through vegetation crowns
  (`Vision.has_line_of_sight_through`, `SquadData.see_through_ranges_m`: one layer to
  500 m, two to 300 m). On the way to a
  position (MOVING) a squad halts for any enemy that comes within reach of its weapons
  (`Squad._in_reach`: AT range with rounds left, rifle range for commanders/soldiers) and
  walks on `contact_resume_s` after none is left (`_update_contact_halt`, `_resume_goal`);
  enemies in sight when the order came don't stop it (`_order_known`), nor does a recall
  or a withdrawal halt. Being shot at alone doesn't move them; with two men down
  (`SquadData.withdraw_after_losses`) they smoke (`SmokeCloud`, a vision blocker) and run for cover within `fallback_m` or to the
  tank, whichever is nearer (`Squad._withdraw`). Infantry fight (`Squad._update_engagement`, SquadData "Infantry fight"): an enemy squad spotted
  within `engage_range_m` (55 m) is a threat: the squad (3+ men, not recalled,
  withdrawing or escorting) leaves its move order (walks on there afterwards, `_engage_resume`;
  squads are never `_order_known`), closes to rifle reach and fights; over when none of it is seen
  `engage_forget_s`. Fired on by a squad it wasn't fighting (`fired_on_by`) it is surprised
  `surprised_s` (3 s, rifles `surprised_dispersion_factor` wider) and fights back. Downing one of
  theirs before losing a man (`on_foe_soldier_down`) gives the upper hand: `_assault`, a line across
  the attack, pairs (even/odd index) running `assault_leap_m` past each other at
  `assault_speed_factor` while the other pair fires (`assault_overwatch_s`), the squad's point
  following, until `assault_close_m`; no ambush lying meanwhile. Spotting soldiers: within
  `soldier_close_range_m` cover and vegetation hide less ((d/range)²), and every other man of the
  same squad in sight adds `group_spot_share` of a look to each (a group shows).
  Mounted they refill one by one (one a minute);
  wiped out, a full squad is back after `wipe_cooldown_s`. HUD: `SquadPanel`.
  Radio (`Squad.radio` signal, kinds `RADIO_*`: under attack (withdraw), returning, in
  position, armour/infantry contact, AT round coming, mines): `SquadRadio` in the player rig plays the own
  squad's calls one at a time on Master (not muffled), no subtitles (game text is English; the Swedish voices are a bonus); contacts get a
  clock hour from the tank's hull. Lines and recordings in `RadioData`
  (`data/squads/radio_sv.tres`, Swedish, `assets/audio/radio/`: ElevenLabs recordings in
  `geodata/sound/` filtered by `tools/audio/make_elevenlabs.sh` (it also cuts the clock hours);
  the old Piper TTS script `tools/audio/make_radio.sh` would overwrite them). Dismounting radios "Avsittning!"
  (`RADIO_DISMOUNT`), a recall "Uppsittning!"; clients get calls by `rpc_squad_radio`.
  Soldiers use `assets/models/soldier/soldier.glb` (CC-BY, KolosStudios, see its
  CREDITS.md; uniform materials repainted green) with Mixamo rifle animations (FBX on
  Y Bot in `mixamo/`, git-ignored: Mixamo files may not be passed on) baked by
  `tools/bake_soldier_animations.gd` into `assets/models/soldier/soldier_anims.res` (git-ignored like
  `mixamo/`: Mixamo animations may not be redistributed, so a fresh clone must bake it; rerun
  if a model or clip changes): per-bone corrections from two directions at rest (twist
  kept), the right hand matched by the rifle (skinned to it), the left hand IK'd onto the
  fore grip, loops/transitions kept on the spot, deaths keep their travel. Look at them
  with `tools/render_soldier_poses.gd` (needs a window). `SquadData`: `anim_hold`
  (kneel), `anim_prone`, firing poses (`anim_hold_fire`/`anim_prone_fire`, facing the
  shot, `anim_fire_hold_s`), deaths by stance (`anim_deaths_standing`/`_moving`/
  `_kneeling`/`_prone`, "" = stays lying) and `anim_transitions` ("from>to" -> clip, e.g.
  kneel_to_prone; `Squad._animate` queues the target after it). Each soldier lies down up
  to `prone_delay_max_s` late; lying, he gets up on the spot (`anim_get_up`, prone_to_crouch,
  else `anim_get_up_fallback`) before he walks off. Own team's
  squads show on the maps, as do teammates' tanks (`MapView._draw_friends`).
  Network: clients send squad orders by reliable RPC (`rpc_squad_order`); the host
  sends all squads in a 10 Hz unreliable packet (`PACKET_SQUADS`, `Squad.write_net_state`,
  31 B + 4 B per soldier offset) and soldier-down/smoke/shot events by RPC; client
  squads are puppets.
  Being seen (`Squad.soldier_spot_time_factor`/`soldier_spot_range_factor`, used by bots
  and squads alike; the player only by eye): cover as for tanks (viewer's ConcealmentData),
  still or moving (`moving_spot_factor`: running men aren't tanks at speed), uniform
  (`camo_spot_factor`), kneeling/lying (`kneel_/prone_spot_factor`), distance beyond
  `soldier_easy_range_m`; a soldier who just fired shows for `reveal_rifle_s`/`reveal_at_s`
  (back blast) at `reveal_spot_factor`. Ambush is automatic: holding `ambush_after_s` the
  squad lies down (`Squad.is_lying`; `anim_prone` via kneel_to_prone, hitbox
  `SoldierHitbox.set_lying` round `prone_body_ahead_m`) and holds rifle fire
  beyond `ambush_rifle_range_m` until it fired or lost a man; moving ends it. Mines
  (`Mine`, `scripts/squad/mine.gd`, data `MineData`/`data/squads/mine.tres`,
  `SquadData.mine*`): Q map right click (`squad_mine`) = `Squad.ORDER_MINE`: the squad walks
  there, the nearest soldier kneels `mine_lay_time_s` and lays it; one carried
  (`mines_carried`, refilled `mine_refill_s` on the tank), at most `max_mines_out` (another
  removes the oldest; radio "Upprättar minering!" on the order, "Mina armerad!" when laid,
  "Mina utlöst!" when an enemy sets it off, `RADIO_MINE_*`, `Mine.triggered`; on a road it lies on the visible surface, `RoadSurface`: road meshes have no collision). A magnetic fuze: an enemy tank anywhere over it, belly included (host,
  `Mine._track_over`), throws its nearer track
  (`Tank.on_mine` -> `TankDamage.apply_mine`), takes `MineData.blast_hp` (10) and dirties the optics
  (`optics_dirt` 0.8); never a knock-out, nobody scores; signal
  `Tank.mine_hit`, clients `rpc_mine_hit`: the crew calls "Mina! Bandet utslaget!",
  `CrewVoiceData.mine`, instead of "Vi är träffade!"); own team
  drives over safely. Gun rounds of another team landing within `destroy_by_gun_m` (HE
  `destroy_by_he_m`) destroy it (`Mine.shell_landed` from `Shell._on_hit`). Visible but
  discreet (a sunk disc); enemy soldiers within `spot_range_m` in sight find it after
  `spot_time_s` (`Mine.mark_known`): small red crosses on that team's maps (own mines green,
  `MapView._draw_mines`); soldiers can't clear mines. Bots avoid cells round known enemy
  mines (`BotController._known_mine_cells`) and re-plan when one is found near
  (`Mine.version`). Network: `rpc_mine_laid/known/gone` (late joiners get all mines);
  the squad packet's flags byte carries lying, mines carried and out (size unchanged).
  Bots: see and MG enemy squads (no tank target); use their own squad via the command
  only after standing `SQUAD_MIN_STAND_S` near a fight (known enemy within 600 m, alert, or
  `fight_focus`, the zone, within 450 m), not within 45 s of a recall (towards the fight,
  `find_position` with infantry costs), recall it when hurt, left behind or driving on; squad
  contacts reach the crew and (KothBots) its team. Decided rules: memory
  `squad-rules`.
- Ground vegetation (`GroundCover`, `scripts/world/ground_cover/`): grass, crops, reed, scrub and
  heather per 2 m cell (`GroundCoverData`, `data/maps/<map>_groundcover.res`, made at map import
  from geodata `markvegetation.bin`), classes with heights and looks in `data/world/ground_cover.tres`
  (`GroundCoverSetData`/`GroundCoverClassData`). Rule (bots and squads alike, in
  `Squad.soldier_spot_time_factor`/`soldier_spot_range_factor`, which now take the viewer): the share
  of the body (stance heights) below the vegetation, above `min_hiding_height_m` (a lawn hides
  nothing), times a grazing factor (full along the ground, none looked down on from 35°), multiplies
  spot time (`hide_spot_time_factor`) and cuts range (`hide_range_share`). Players see the same:
  `GroundCoverField` (player rig) draws blade clumps (MultiMesh per 24 m cell and class,
  `ground_cover.gdshader`, wind) by "seen" distance = true distance / zoom (camera FOV against
  `reference_fov_deg` 70): all round to `blade_range_m` (130), in a zoomed view's wedge (sight,
  binoculars) to 130 × zoom, at most `max_reach_m` (800). Full density to `full_density_m` (30), then
  the shader keeps clumps of rank (INSTANCE_CUSTOM.r) < (30/d)^`thin_exponent` / zoom^`zoom_thin_exponent`,
  widens survivors (≤ `max_widen`), shrinks those about to drop (no popping) and flattens far colours.
  A cell holds only the share its nearest point needs (levels 1, 1/4, 1/16...: the first tries of one
  fixed sequence, so finer rebuilds add clumps); built by `GroundCoverCellBuild` in slices within
  `build_ms_per_frame` (2 ms), near cells at once after a camera jump; unwanted cells hide, freed after
  `keep_hidden_s`. Note: `PROJECTION_MATRIX[1][1]` is negative in Vulkan (use abs). Beyond,
  `GroundCoverCanopy` shows the baked `assets/maps/<map>/<map>_markvegetation.glb`
  (4 m cells on the ground, class in UV.x; height and colour from the .tres by shader): opaque far,
  dithered in where the blades thin (`canopy_fade_start..end` × blade range, seen distance) and thinned
  when looked down on (same angles as the rule), so a man lying in a far field is hidden to the eye as
  to bots, with nothing marking him. Cost: ~0-0.4 ms normally, ~1-1.3 ms in sight/binoculars over fields.
  So far: Vidingsjö, Linghem, campus, road_to_science. Class 8 'vass' (reed, 1.6 m) belts the lakes' shores (4 m up the land, 6 m
  into the water).
- Water: `WaterLook` (player rig) puts `assets/shaders/water.gdshader` on the map glb's water meshes
  (`Sjo_*`, `Hav_*`, group `Vattendrag`): colour by thickness over the bottom (depth buffer), a pale
  rim at the shore, normal maps drifting with `WeatherData.wind_mps`, rain rings by `rain_intensity`.
  Fording: `GroundCoverData.water_ids/water_levels` (lakes, from geodata `vatten.bin`),
  `GroundCover.water_depth()`; `Tank._ford_factor()` slows the drive by `TankData.ford_slow_share` at
  `ford_depth_m` (1.2 m), deeper `too_deep_speed_factor` (a crawl). Culverts (Trafikverket, state
  roads): pipe ends in hollows at the road banks (geodata `trummor.py`, glb group `Trummor`).
- Sports grounds (geodata `idrott.py`): OSM running tracks get a flat tartan oval with lane lines and a lawn infield (glb group `Idrott`, no collision); a long building beside one (or `building=grandstand`) becomes a roofed grandstand (`Byggnader_laktare`, collision). So far Isovalen on campus.
- Landmarks (geodata `landmarken.py`, `geodata/landmarken.json` by OSM way id): built from their OSM building parts; one part can be a glass tower (taller, V-shaped, floor bands and mullions). Group `Byggnader_landmarken` (collision). So far Mjärdevi Center (campus, road_to_science).
- Roadside (geodata `vagkant.py`, glb group `Vagkant`, no collision): reflector posts on rural roads
  from 70 km/h, street lamps every 32 m in built-up areas, guard rails on high banks, speed signs where
  NVDB's limit changes, give-way/stop signs and bus stop signs from OSM nodes, pedestrian-crossing
  signs (E1, both sides, not at traffic lights) at every zebra (`vagmarkering.py`: NVDB crossings plus
  OSM `highway=crossing` uncontrolled/marked/traffic_signals) (the stop's OSM name on a
  plate below, own atlas), bus shelters from OSM
  (shelter nodes and platforms with shelter=yes); sign faces from a generated atlas (alpha), the face
  6 cm in front of and the grey back 6 cm behind the post, which ends at the sign's middle. Rural
  roads get 0.6 m ditches in the carving.
- Toppling props (`PropBreak`, player rig, moves itself to the map scene; data `PropBreakData`,
  `data/world/prop_break.tres`; cosmetic, local, nothing sent): glb group `Valtbart` (geodata
  `valtbart.py`: templates `Mall_<kind>` + one empty node `<kind>__<key>` per prop) = street lamps,
  catenary masts (no collision any more), road signs (`Skylt_<face>`, bus stops with a name
  `Hallplats_<n>`, place names `Ortnamn_<n>`), reflector posts, guard rail pieces (`Racke`, 2 m,
  scaled along x), bus shelters (`Vaderskydd`, wider reach `kind_reach_m`) and traffic lights
  (`Trafikljus`, `Trafikljus_gang` with a pedestrian light and push button, `Trafikljus_gangstolpe` a
  pedestrian post across the road from it; a repeater `Trafikljus` on the junction's far side for
  every approach; key `<n>_<phase>_<axis>`),
  drawn as a MultiMesh per kind and 250 m cell (small kinds only
  within `small_draw_range_m`). Traffic lights switch: lens materials `Signal_*` get
  `assets/shaders/signal_light.gdshader` (cycle in `PropBreakData` "Traffic lights": red+yellow, green,
  yellow, red; the junction's offset and direction axis as MultiMesh custom data, so a junction's two
  directions take turns and pedestrians walk while their road has red; from TIME, local, nothing
  sent); a toppled one falls dark (the plain materials). Placed by geodata `vagkant.py` from OSM
  `highway=traffic_signals` (stop line towards the nearest junction, `traffic_signals:direction`, or a
  junction-centre node = one per approach) and `crossing=traffic_signals` (both ways mid-block); a tank's
  hull footprint touching one hides it and a `FallenProp` topples (a mast drops its catenary spans
  `Ledning__<track>_<i>`); playground pieces (`Lekplatser`) fall apart into their solids (at most
  `debris_max_parts`, thrown and spinning). Fallen things lie `lie_s` (30 s), sink and are gone until
  ThunderRoad's map reset (`PropBreak.restore_all`).
- Sign backs: the glb's `*_bak` materials (road and place-name signs) are the face texture darkened,
  which showed mirrored text; `PropBreak._fix_sign_backs` swaps them at load for
  `assets/shaders/sign_back.gdshader` (plain sheet metal, outline from the face's alpha) on every mesh
  and template (`PropBreakData.sign_back_suffix/shader`).
- Place-name signs (geodata `vagkant.py` `_ortnamn`): where a road passes from one district/village to
  another (OSM place=* by `geodata/scripts/platser.py` -> `work/platser.json`; a point belongs to the
  place nearest relative to its reach by kind), a white sign with black frame and text on the right for
  traffic going in, one each way with the name being entered (`Ortnamn_<n>`, toppleable). Nothing on
  the HUD.
- Playgrounds (geodata `lekplatser.py`): every OSM playground gets equipment (climbing tower with roof,
  net/wall and slide, slide, swing set or basket swing, roundabout, zip line in big parks, sandpit,
  basketball hoop, seesaw, benches, playhouse), unique per park (seeded by its OSM id: choice, count,
  colours, sizes, layout; OSM equipment nodes placed where mapped), sand or rubber under them. One glb
  node per piece in group `Lekplatser` (vertex colours); `PropBreak` (player rig) gives them a
  vertex-colour material and breaks a piece apart when a tank (group "tanks", puppets too) drives into
  it (no collision, nothing sent).
- Changing ammo (Tank._update_gun): with a round in the breech it takes `TankData.ammo_swap_share`
  (0.4) of the reload; while loading (after a shot or mid-change) only the round type changes, the
  time left stays (no way round a reload).
- HE ("disables, AP kills"): never ricochets (`Armour.resolve`); not getting in it still takes
  `ShellData.blast_hp` (75 mm 8, 152 mm 25) and `fragment_module_damage` (75 mm 11) on exposed
  modules within `blast_module_reach_m` of the burst (`ModuleData.blast_exposed`: engine at
  `blast_reach_share` 0.7, turret ring 0.4, from the box surface; two 75 mm bursts make either yellow; `TankDamage._blast`); a track it lands on breaks, fragments damage
  near ones. Bursting within `optics_dirt_radius_m` (75 mm 8 m) of an enemy tank it dirties its optics
  (`Explosion._dirty_optics` -> `Tank.add_optics_dirt`, signal `optics_dirtied`, clients
  `rpc_optics_dirt`): `OpticsDirt` (player rig, `optics_dirt.gdshader`, commander and gunner views)
  fades exponentially (`TankData.optics_dirt_fade_s` 6, gone in ~20 s); bots spot up to
  `optics_dirt_spot_factor` (2.5) slower and lose their lay. Soldiers: fragments reach
  `SquadData.fragment_radius_factor` (1.25) farther. Bots pick rounds (`BotController._choose_ammo`,
  only with one in the breech): AP for a tank whose facing hull plate it gets through
  (`_can_penetrate`), else HE; HE for squads, then the main gun fires at them too
  (`_fire_he_at_squad`).
- Hits and wrecks: a gun round (>= 20 mm) on a tank emits `Tank.struck(outcome, dir)`
  (clients get it for their own tank by `rpc_struck`) and jolts the hull
  (`TankData.hit_jolt_factor`); `HitReaction` in the player rig shakes the commander/gunner
  view (`shake` on the cameras) and plays `data/sounds/ping.tres` on a ricochet
  (`tools/audio/make_ping.py`); `PlayerController` cancels held driving keys until pressed
  again. Reversing steers like a car (steering flipped in PlayerController). Acceleration and
  braking pitch the hull by design only (track forces act at the centre of mass' height):
  the effort as a share of the tank's own limit times `pitch_rock_accel` ×
  `pitch_rock_lever_m`, plus a kick while the effort changes (`pitch_rock_kick_*`); the
  builder scales with mass (`rock_mass_exponent`). Physics interpolation is on: cameras
  read `*_interpolated` poses and are themselves excluded, anything moved in `_process`
  sets its mode OFF, teleports call `reset_physics_interpolation()`, puppets move in
  `_physics_process`.
  An ammo knock-out (`TankDamage.ammo_exploded`) throws the turret (`Tank.toss_turret`: a
  charred RigidBody in group `wrecks`, frozen at rest; height `TankData.turret_toss_*`,
  min + span·u^bias, so mostly short; clients by `rpc_turret_toss`); the wreck has no turret.
  Knocked-out tanks leave a charred wreck (`Tank.leave_wreck`, `Wreck`, group `wrecks`, from
  `KothMode.place_tank` / a puppet's respawn jump) for the whole match. Wrecks can be pushed: on the
  host a RigidBody of `TankData.wreck_mass_share` (0.35) of the tank's mass (`wreck_friction`,
  `wreck_damp`), standing on a track-footprint block; clients' copies are frozen and follow the host
  (`NetGame._send_wreck_moves`, 5 Hz, only moved ones, `rpc_wreck_moves`, keyed by `Wreck.made_at`
  = where it was made, matched within 4 m; late joiners get all poses). Tanks push: pressing against
  a tank or wreck (contacts), the drive may pull `TankData.push_accel` (6 m/s², more than a braking
  tank's 4) fading to plain acceleration at `push_fade_speed_kmh` (18): a wreck goes ~12 km/h, a
  braking tank ~8 km/h, sideways never (lateral grip).
  The host lists wrecks (`Tank.wreck_left`) and sends them to late joiners (`rpc_wreck`:
  a throw-away `wreck_only` tank of the same spec makes the copy, `make_wreck_here`).
- Kill credit: on the host every knock-out emits `Tank.eliminated(killer, assists)`: killer =
  `HitRecord.kill_of`'s shooter (`HitRecord.shooter_id`, host only), assists = other enemies whose
  rounds `dealt_damage()` (penetration, or any hit that harmed a module or took hp: an HE burst
  breaking a track is NO_PENETRATION and counts; `HitRecord.hp_taken`, host only) this life, plus
  tanks whose HE fragments harmed a module from a near miss (`Tank._fragment_damagers`, via
  `ModuleFragmentTarget.note_fragment_shooter`, passed by `Explosion.detonate`); abandoning has no
  killer. Modes count KO and assists from it (KotH rows [name, team, KO, lost, points, assists]:
  an assist also gives `KothData.assist_points` (15) personal points, not team score; ThunderRoad
  rows [name, team, KO, lost, assists, points]); `Scoreboard._table` takes column indices. Kill feed
  (`KillFeed`, player rig HUD, above the minimap): "<name> <type> → <name> <type>", killer first,
  own team blue, enemy red (`TeamLook.viewer_team`), `Tank.get_player_name()` ("You"/"Bot"/player
  name) and `get_type_name()` (config name, e.g. "T-34"; the killing round's `kill_feed_name` instead,
  e.g. "Bazooka"); 5 lines, 9 s; clients get entries by
  `rpc_kill_feed` from NetGame.
- Killcam: the host records every gun round (>= 20 mm) on a tank as a `HitRecord`
  (`Tank.get_hits_this_life`, signal `hit_recorded`; origin from `Shell` via
  `Tank.note_incoming`, killed / set-fire flags; the owner's client gets them by
  `rpc_hit_record`). On the own knock-out `Killcam` (player rig, `data/ui/killcam.tres`)
  replays the killing round (`HitRecord.kill_of`: killing hit, else the one that lit the
  fire, else the last penetration) with a chase camera (`PlayerViews.set_killcam` hides
  the optics), any key skips; then `KillcamPanel` shows the hit picture (English text;
  the tank's own model rendered top and side in two small SubViewports, turret and gun as
  they were, all hits this life drawn on it) until the respawn; behind it (and after any knock-out without a
  replay) `Killcam._spectate` follows the nearest living teammate from behind its turret (`KillcamData` "Spectate";
  `fire` goes to the next), or holds still over the own wreck when none is left. Abandon: none.
- Smoke: `TankCommand.smoke` (key X; bots when too exposed, see below) fires a salvo,
  `TankData.smoke_salvos` (3) per life, `smoke_cooldown_s` (20) apart for players and bots: `smoke_clouds_per_salvo` `SmokeCloud`s
  ahead of the turret. Clients send it (and abandon) by `rpc_tank_action`; the host sends the
  clouds by `rpc_tank_smoke`. Squads have one grenade.
- Abandon: `TankCommand.abandon` (Esc menu `EscMenu`; bots after `BotData.abandon_stuck_s`
  trying to drive without getting `abandon_stuck_m` away): a knock-out nobody scores.
  `Tank.repair()` (respawn) puts everything back as at the first spawn, squad included
  (`Squad.restore_on_tank`).
- Mode voices (`ModeRadio`, player rig HUD, through SquadRadio; data `ModeCallsData` on `KothData.calls` /
  `FreeFightData.calls`, `data/modes/koth_calls_sv.tres`, `free_fight_calls_sv.tres`): crew banter at the start and
  the end; KotH zone open / next zone / more or fewer of ours in the zone (held `count_hold_s`, counted from tank
  positions, so clients too) / closing / near win either side; Bot hunt new wave / wave beaten / teammate lost /
  last one alive. Kill banter in every mode (`CrewVoiceData` "Kill banter", own kills from `KillFeed.entry_added`
  matched by player name; a victim in the KotH zone or a ThunderRoad checkpoint gets the zone lines), and rare
  stand-ins `hit_rare`/`mine_rare`. New recordings: `geodata/.venv/bin/python tools/audio/transcribe.py <files>`
  (faster-whisper, local) prints their text, so they can be named `ElevenLabs_<slug>.mp3` in `geodata/sound/`
  and added to `make_elevenlabs.sh`.
- Crew shouts: `TankData.crew_voice` (`CrewVoiceData`) "Vi är träffade!" on `Tank.struck` (a mine: "Mina! Bandet utslaget!"),
  "Närträff!" on `Tank.near_missed` (clients by `rpc_near_miss`), "Föraren/Skytten träffad!" on a
  crew wound, rarely (`he_dirt_chance` 2 %) "Vilken jädra smäll!" when a burst dirties the optics, "Vagnchef träffad!" on `Tank.commander_wounded`, played by `SquadRadio`. A hard crash (ground speed falling `crash_drop_kmh` within `crash_window_s` from `crash_min_kmh`, read from the own tank's position, so clients too; not right after a hit or mine) gives "Hörru, Rally-Kalle, lugna ner dig lite!" (`CrewVoiceData` "Crash").
  MG/rifle results are `HitResult.bullet`: no hit text for the shooter.
- The open hatch lid stands up behind the commander and shields him from the rear:
  `Tank.hatch_lid_shields(from, to)` (segment through the lid's disc in its real pose) stops bullets
  (< 20 mm, `CommanderHitbox.on_shell_hit`, checked `LID_CHECK_M` back along the path) and HE
  fragments (`fragment_shielded`, optional fragment-target method used by `Explosion`); gun rounds go
  through. No collider (the commander's own sight lines aren't blocked).
- Tanks have a coaxial MG and a roof MG (`TankData.coax_mg`/`roof_mg`). The roof MG
  only works with the hatch fully open, aimed at `TankCommand.mg_aim_point`. Belts:
  `MachineGunData.belt_rounds` (100) then `reload_s` (6) per gun (`Tank.get_mg_rounds_left/
  get_mg_reload_left`; counted on the host and the own client, owner data in the snapshot;
  `WeaponStatus` shows "MG 63" / "MG RELOADING").
- Bots: `BotController` (extends `TargetTankController`, so patrols waypoints) with
  crew skill in `BotData` (`data/bots/*.tres`). Spots only via `Vision` from its own
  commander's eye (hatch open: all round, far, fast; closed: periscope sector),
  scans staggered per bot, tanks beyond `BotData.look_every_2nd/4th_beyond_m` (400/800 m)
  looked at every 2nd/4th scan (not the target), cover cached per target (`Concealment`),
  stops to fire with range/laying errors that shrink per shot, MGs exposed
  commanders, closes the hatch when hit or an enemy is close. `Tank.team` decides
  enemies. `RespawnAtStart` brings a knocked-out tank back (test bench).
- Concealment (`Concealment`, `data/world/concealment.tres`): sight-blocker shapes
  (layer 5: bushes, tree crowns, laser-tree crowns) around a target, and standing
  still, make it slower and shorter-ranged to spot; moving fast makes it easier.
  Bots also spot faster the more of 4 hull points (+ exposed commander) they see.
  A tank's own signature (`Concealment.tank_cover`/`tank_spot_time_factor`, values in
  ConcealmentData "Signature"): a main-gun shot (`Tank.get_fire_reveal`, flash plus a
  `GunSmoke` cloud), MG fire (weaker, `Tank.get_mg_reveal`, `mg_reveal_*`) and heavy exhaust (`TankExhaust`, `ExhaustData`, `Tank.get_exhaust_load`:
  thin at idle, dark under load, a puff on a throttle kick) make cover count less and
  spotting quicker. Players just see the smoke.
- Telling teams apart (`TeamLook`, `scripts/world/team_look.gd`): seen from THIS machine's
  player (`TeamLook.viewer_team`, set by PlayerViews from the own tank), tanks and soldiers
  of the same team show UN blue (blue bands round hull and turret and a roof panel =
  `MeshKit.Mat.MARK`; plain box tanks get a turret band, `Tank._add_plain_marks`; soldiers
  get their helmet material painted blue, `SquadData.friend_blue_materials`), every other
  team is camouflaged (`assets/shaders/camo.gdshader`, an M90-like splinter pattern in
  model space, on paint, markings and uniforms: leaning, stretched Voronoi fields plus a
  finer black layer, borders blended over a pixel, in `m90.gdshaderinc`; soldiers use
  `camo.gdshader`). Tanks are painted with `tank_paint.gdshader` (`TeamLook.tank_paint(enemy)`,
  `Tank.paint_visual`): friends weathered two-tone olive (soft blotches; MARK stays blue),
  enemies weathered M90; weathering = faded patches, rain streaks, dust on upward faces,
  mud and splashes near the tracks, wet in rain. `TankLooks` (made by Tank, reads only how
  the tank moves) sets the instance uniforms: `dust_amount` grows with distance driven ×
  `WeatherData.dust_factor` (reset on repair), `wetness` = rain, `base_y` = each part's mud
  line (none on gun, mantlet, figure, MG mount). Tactical numbers: two `Label3D`s on the
  turret side plates of model tanks (TankModel "number_spots", `Tank.number_labels`), text
  from TankLooks: team digit + two digits (`net_id` online, so every machine agrees; offline
  in order per team), hidden when knocked out. Stowage (`StowageModel`, made in `Tank._add_stowage`): a rack
  behind the turret with tarp rolls, packs, crates and jerrycans, and jerrycans on the rear
  deck; `VARIANTS` per tank type, picked from net_id (online) or the node name.
  `MeshKit.Mat.CANVAS` for tarps and packs. Moving parts (TankLooks, read from how the tank moves, so
  puppets too): each track's travel (hull forward travel ± turn × track half width, at the
  physics rate, blended between ticks) turns the wheels (`tank_wheel.gdshader`: MeshKit
  `spin` puts each wheel's centre and 1/radius in CUSTOM0; bolts show the turning) and
  moves the track links (`tank_track.gdshader`, instance uniforms `wheel_dist_l/r`,
  `track_dist_l/r`); road wheels (MeshKit spin.w 2) and the bottom track run follow the
  ground under each track (`ground_fit`, instance index 7: TankLooks casts two rays a side at
  15 Hz for tanks within 250 m of the camera). Tracks rest on the ground: suspension rays
  start `Tank.ray_origin_y()` (track bottoms + the springs' sag − `TankData.track_ground_gap_m`
  0.04), and hull armour shapes (and a plain box hull) stop `track_shape_lift_m` (0.22) above
  the track bottoms so they don't scrape. Instance uniforms of shaders that share a mesh share its slots: give
  each a fixed `instance_index(n)` (paint 0-2, wheel 3-4, track 5-6, ground 7), or they overwrite
  each other (the hull went black after driving); the antenna whip is its own mesh ("Antenna", TankModel "antenna") and
  sways on a damped spring pushed by the tank's acceleration. Battle marks (`BattleMarks`): every gun round
  (>= 20 mm) striking a tank leaves a scorch Decal (soot round a bright gouge) on the hull or
  turret, from `Shell._play_impact` on every machine (clients' cosmetic shells too, nothing
  sent); at most 16 a tank, cleared by `Tank.repair()`.
  Each machine decides for itself, nothing is sent; tanks/squads repaint when
  `TeamLook.version` or their team changes. `Tank.paint_color` is no longer used.
- Tank models (`scripts/tank/model/`): `TankModel.build(data)` makes the look AND the
  armour shapes from `TankData.model_style` (chassis: light = BT-like, sloped = T-34-like,
  boxy = Pz IV-like, heavy = KV-like, tall = Sherman-like (tall hull, 56° glacis, six small
  wheels in bogies, a rounded cast turret lofted from rings); only loose visual inspiration), the geometry
  fields, `turret_variant` (gun, e.g. box_turret for the 152 mm), `muzzle_brake` and
  `armour_look` (heavy package: skirts/appliqué). `TankModel._details` adds looks only (no
  armour shapes) to every style: headlights, spare links and driver's hatch on the front
  plate, engine grilles and tools on the deck, loader's hatch, periscopes, smoke
  dischargers and an antenna on the turret roof. The roof MG is a Browning M2-like gun on
  every tank (`RoofMgModel`, applied by `Tank._apply_roof_mg_model`; 500 rounds/min).
  The commander is seen in the open hatch (`CommanderModel`, node `CommanderFigure` under
  the cupola, made by `Tank._add_commander_figure`): it rises with the hatch like the
  hitbox, turns with the roof MG, hides when shut or knocked out; uniform PAINT, helmet
  MARK (friends olive with a UN-blue helmet, enemies camouflaged). The own commander's
  view doesn't draw its own figure, roof MG post or hatch lid (render layer `CommanderCamera.OWN_COMMANDER_LAYER` 3,
  `Tank.set_commander_figure_layer`); every other view does. `MeshKit.Mat.SKIN` for faces. `MeshKit` builds flat-shaded convex
  solids (blocks cut by plate planes, cylinders, extruded track profiles) with named
  point groups -> one `ConvexPolygonShape3D` per group (several hull and turret shapes;
  turret shapes follow the turret, `Tank._sync_turret_shapes`). So slopes are real: the
  hit normal gives the angle (plate mm in ArmourData are true thickness; faces: roof only
  when the normal is within ~20° of vertical, `ROOF_NORMAL_Y`). Ricochet angle per
  chassis (`ArmourData.ricochet_angle_deg`: light 63, sloped 66, others 70) so angling
  can bounce shells. Overmatch: from calibre/plate (worn) ratio
  `ArmourData.overmatch_start_ratio` (2.5) the ricochet angle rises towards 90°, and from
  `overmatch_full_ratio` (6) a round never bounces (`Armour.ricochet_angle`). BT-like hull:
  glacis 70°, nose 58°, sides 35°, conical turret; it bounces 37-75 mm angled ~10-20°. `model_style` "" keeps the scene's plain boxes (player_medium,
  test_medium). Paint replaces the PAINT material per surface. Pictures without the game:
  `godot --path . --script res://tools/render_tank_models.gd -- <dir> [preset...]`
  (needs a window; `renders/` is git-ignored).
- Five presets, `data/configs/1_bt7 .. 5_sherman.tres` (main menu, `KothData.bot_configs`,
  `ThunderRoadData.bot_configs`; default T-34), each with a clear strength and weakness:
  BT-7 flanker (fastest, can't get through fronts), T-34 brawler (48 km/h, sloped armour, best
  terrain: climb 36°, fords; weakest optics 22/15°, 76 mm 100 mm pen, strong HE), Pz IV sniper
  (145 mm pen at 700 m/s, 34 dmg, 5.5 s, three sight levels 24/12/8°; 36 km/h, slow traverse,
  50/30 mm turret, 20 mm rear), Sherman all-rounder on the move (39 km/h, gun stabiliser 0.5 up to
  `gun_stabiliser_max_rate_deg` 4°/s of hull pitch: steady driving held, throttle kicks get through;
  traverse ×1.3, 5 s reload, 4 smoke salvos; tall: spotted sooner, `signature_spot_factor` 0.85;
  100 mm pen, 37 dmg), KV-2 breaker. The chassis' character lives in `ChassisData` "Character"
  (`traverse_factor`, `gunner_sight_fov_deg`, `gun_stabiliser` -> `TankData.gun_stabiliser`:
  turret/gun drives also take out that share of the hull's turn and pitch, bots' moving lay error
  shrinks by it; `max_climb_deg`, `ford_slow_share`, `smoke_salvos`, `signature_spot_factor`). Tank builder / garage: `TankConfig` (only part ids: chassis, gun, armour package,
  camouflage) -> `TankBuilder.build()` -> `TankData` (cached per `key()`), from the
  catalogue `data/builder/catalogue.tres` (`ChassisData` light, medium (T-34-like),
  medium_h (Pz IV-like), medium_s (Sherman-like), heavy (KV-like); the tank destroyer is gone; each with its
  `GunData` 37-152 mm and `ArmourPackageData`; coefficients in
  `BuilderRules`: speed and acceleration from kW/t, turn rate from mass, traverse from
  gun mass, hp per tonne capped at `max_structure_hp` 200, camouflage). The chassis' `base` TankData supplies the rest.
  Medium + 75 mm = today's tank. `Tank.apply_geometry()` sizes hull, tracks, turret,
  gun and suspension from `TankData` geometry (scene measures are the reference, consts
  `BASE_*`); `Tank.config` builds the data at start. Camouflage
  (`TankData.camo_spot_factor`) slows bot and squad spotting; spot points scale with the
  hull (`Tank.get_spot_points`). Garage `scenes/menu/garage.tscn` (from the main menu): a
  viewer of the presets only; the tank is chosen in the match (Deploy, below). `TankConfigs` keeps
  presets (`data/configs/`) and the last choice (`user://garage.cfg`); the garage shows effective
  armour for sloped plates (`TankModel.SLOPES`). The player rig's tank
  (`use_player_config`) uses the choice offline; online the host takes the key from `rpc_deploy`
  and spawns carry a spec (`TankBuilder.spec_of`/`apply_spec`: "cfg:<key>"
  or a TankData path). KotH gives placed bot tanks random `KothData.bot_configs`
  (`KothMode._give_bots_configs`, before tanks are ready). Line-ups (three tanks within
  a budget) come later; cost is already computed.
- The player's tank uses `data/tanks/player_medium.tres` (set in `player_rig.tscn`)
  unless a garage tank is chosen; a map's own bot tanks (`test_medium.tres` data) drive a random
  preset (`Tank._ready`: no config, not the player's, not a puppet), so only garage tanks exist. Binoculars zoom `binocular_zoom_vs_gunner` times
  the gunner's strongest sight zoom.
- Bot navigation: `tools/bake_tactical_grid.gd -- <map>` (headless) bakes
  `data/maps/<map>_tactical.res` (`TacticalGridData`, 8 m cells: height, flags for
  house/stone, water (widened, not across roads), steep (also 2 m-scale banks),
  forest, road, wetland, cover, near-obstacle, thick trees; land cover from geodata).
  Rerun after map changes. `TacticalMap.for_scene()` builds an `AStarGrid2D` (costs
  in `TacticsData`, `data/bots/tactics_regular.tres`) and `find_path()` straightens
  the result; tree lines (open cells beside forest/bushes) are cheap and count as
  cover. `BotController.order_path(goal, throttle, urgent)` drives such paths: replans
  when stuck and remembers where (`avoid` cells), steps aside when stuck twice in a
  place, keeps a gap to tanks ahead, and stops briefly to scout (hatch open) before
  long open stretches (`TacticalMap.scout_points`, values in `TacticsData`; skipped
  when urgent or after recent contact). Keep stops short: bots must keep moving.
  KothBots lets bots leave a spawn one by one and orders urgently after respawns,
  between zones and when the zone closes soon. New orders in a crowd (zone moved or shrank) queue up and go out
  one per `KothBots.ORDER_INTERVAL_S`, as do new bounding pairs: all at once they froze the game. Positions: `TacticalMap.find_position()`
  scores candidate spots for cover, hull down (grid heights towards the threat), sight
  lines from the commander's eye and spacing from teammates (weights in TacticsData);
  KothBots uses it with `BotController.get_threat_direction()` (own knowledge only;
  default: the enemy's side of the zone). Bounding (in KothBots, not BotGroup): near the zone or after contact a team's bots pair up and
  move in turns (one watches, one drives to the next `find_position` spot that must
  get closer; the watcher goes anyway after `overwatch_max_s`, a move is never cut
  short). Long drives go by a random flank point (teammates prefer different flanks)
  so routes vary. Shoot and scoot (`TacticsData.shoot_and_scoot`): after a shot a bot
  backs to a spot its target's commander can't see while it reloads, then comes up a
  few metres to the side (only `scoot_chance` of shots). Gun rounds that hit or nearly
  miss (`Tank.shell_threat`: >= 20 mm, passing or landing within 8 m, collected by
  `Shell`) make it react with `relocate_chance_by_hits` (30 % / 85 % / 100 % for 1/2/3 in a row
  within `relocate_window_s`): it stays and shoots if the gun bears on the shooter within
  `answer_time_s` (unless `exposed_hits` came in a row), else backs into a hide spot if
  one is near, and only with neither is it too exposed: smoke and pull back
  (find_position away from the threat, held `relocate_hold_s`; KothBots waits). Firing on the way: a short halt
  only beside cover (`TacticalMap.is_covered`) within `transit_fire_range_m`; in the
  open it fires on the move within `BotData.move_fire_range_m` (looser lay, error per
  m/s), else holds fire. Bots stop to repair only for a destroyed module, a thrown
  track or hp below `BotData.repair_stop_hp_fraction`. Close fight (`TacticsData.close_fight_*`, BotController): a spotted enemy within 50 m becomes
  the target at once and the bot leaves its orders to charge round to its side/rear (14 m off the
  hull, firing on the move, no scoot or relocation), let go past 1.4 × range, then a fresh path to
  its order goal. A knocked-out bot drops its orders, relocation and scoot. Hunting (KothBots, `TacticsData`
  `hunt_*`): bots radio spots to the team and go after known enemies, those in the open
  zone first (any range, no time limit, pressing closer), others near the zone for
  `hunt_max_s`; firing spots for an enemy in the zone are inside it. Needs a baked grid. Without a baked grid bots drive
  straight. Baked so far: vidingsjo, linghem, campus, road_to_science, corson. Spawns avoid blocked cells.
- Bot roles (`BotRoleData`, `data/bots/roles/*.tres`; the chassis' favourite `ChassisData.bot_role`
  -> `TankData.bot_role`; `BotController.get_role()` = `role_override` (a role given for now) or the
  favourite, none = brawler): BT-7 scout (-> harasser in contact: `contact_role`, set by
  `TeamSituation.apply_contact_roles` while known enemies are near the objective), T-34 brawler,
  Pz IV sniper, Sherman flanker, KV-2 breaker. A role has its way in (`axis_spread_deg` off the
  team's side, left/right in turn, widest first), `standoff_*` outside the zone, `enters` (ALWAYS /
  ON_ADVANTAGE (+`enters_on_pressure`) / WITH_LEAD = `follow_m` behind the nearest brawler / NEVER),
  hold times (scouts keep moving), `hunt_engage_m`, squad eagerness (`squad_stand_s`,
  `squad_cooldown_share`), defence `post` (FORWARD / ZONE_FRONT / BEHIND_ZONE / FLANK_RESERVE /
  BEHIND_LEAD) and `mines_first`. Harasser (`hit_and_run`): shows up off the known enemies' flank
  (`pick_harass_range`: mostly 300-500 m, `harass_close_share` closer), fires `shots_per_visit`, then
  `BotController._dash`es `dash_min_m..max_m` sideways (`_relocating`, `dash_hold_s`); `track_he`:
  HE at the facing track (`_track_point`). `avoid_front_duels` (scout, harasser): an enemy laying its
  gun on it (`LAID_ON_DEG`) whose front it can't get through: it dashes away (`_check_dodge`).
  `TeamSituation` (`scripts/ai/`, every `TacticsData.situation_interval_s`, fair knowledge only: own
  tanks, team-known enemies, the public kill feed (`TeamSituation.KnockoutLog`), score and clock):
  `advantage`, `pressure` (behind with time short, or few known defenders while behind/short),
  `pushed_back`, `enemy_centre`; `has_moment`/`holds_outside` (kept `enter_hold_s`; own knock-out
  `own_kill_moment_s`); `ensure_spearhead`: at least `min_spearhead_share` of a team goes in
  (flankers, then snipers, when brawlers are short). KotH (`KothBots`, axes on in both rule sets):
  outside roles are `_support` until their moment; harassers at `_harass_spot`. ThunderRoad
  (`ThunderRoadBots`): attackers by job (`ThunderRoadBots.Job`, `_job_of`; phase per
  checkpoint in `_update_assault`): DEVELOP first (scouts/harassers on the flanks, snipers to firing spots
  `SNIPER_RANGE_*` from the known defenders, the rest bound in pairs, `_develop_step`/`_start_leg`, to their lane
  on a line `DEVELOP_STANDOFF_M` short of the zone), ASSAULT with the upper hand (near the checkpoint >= known
  defenders + `ASSAULT_MARGIN` after `DEVELOP_MIN_S`, a kill run, or time short / overtime; into the zone,
  breakers behind a brawler, snipers closer; back to DEVELOP when the upper hand is lost), and a RESERVE
  (`RESERVE_SHARE`, at least one) `RESERVE_BACK_M` back until time is short), defender posts by `post` (every other ZONE_FRONT brawler posts out on its flank for crossfire,
  breakers follow their lead's side, near-road posts keep `POST_CENTRE_GAP` off the road; BEHIND_ZONE moves to the zone's
  front when `pushed_back`; FLANK_RESERVE counterattacks the attackers in the zone from the side,
  `_update_counter`); `ThunderRoadData.defender_post_*_share` no longer used.
- `BotGroup` moves bots together: column along a route, on the first contact
  (shared to all members) line abreast towards an objective, short halts to fire.
  Bots on an ordered route that get stuck reverse and detour sideways.
- Scenarios are scenes inherited from a map (`scenes/scenarios/*.tscn`, base e.g.
  `vidingsjo.tscn`), so map edits carry over. (The Hackerstad scenario and the
  `test_hackerstad` map were dropped 2026-11-11; raw data kept in `geodata/test_hackerstad/`,
  so `BotGroup` has no scene using it now.)
- King of the Hill (`KothMode`, node `KothZone` in a scenario; its Marker3D children
  are the spots where zones may open; rules in `data/modes/koth_default.tres`,
  `KothData`). Zones one at a time: open at full size, hold, shrink while scoring
  faster; a zone closes when it has paid out its point budget (zone scoring and kill
  bonuses) or at its lifetime; the next spot shows on the map during the gap. First to
  `score_to_win` wins (`zone_count` 0 = no zone limit). Never
  contested: each team scores per own tank in the zone (capped), the team with most
  tanks there gets a multiplier, an in-zone knock-out from inside the zone gives a
  bonus. Each zone moves the spawns (`get_spawn`/`get_free_spawn`): first zone `south_team`
  south, others north; later on an axis through the zone from each team's side, away
  from the other team's centre of mass (`_choose_spawn_axis`), turned if needed to stay
  `spawn_enemy_clear_m` from enemies, `spawn_distance_m` away (closer if
  off-map/water/house). Slots are rows of 12, checked for slope, trees and tanks.
  Tanks go to their spawn at the start; respawns (`RespawnAtStart`, `KothBots`) use the
  current spawn. `KothBots` orders every BotController into the (next) zone. Runs
  offline/host only. HUD: `ScorePanel`; `MapView` draws zone and own spawn.
  Scenarios: `vidingsjo_koth`, `linghem_koth`, `campus_koth` (`scenes/scenarios/`, listed in the main menu (`MainMenu`: only `scenes/scenarios/`, grouped under King of the Hill / Thunder Road / Free fight by the name tags `_koth`/`_thunder`/`_free`, place names with å/ä/ö in `PLACE_NAMES`); a map needs a baked tactical grid, a map image, KothZone with spots, KothBots, PlayerRespawn and at least one placed bot; default 4 v 4). Move a zone by moving its Marker3D; keep them ≥ ~400 m plus the zone radius from map edges where possible. Tanks per team (main menu number, `MatchSettings.team_size`,
  `user://settings.cfg`; offline and hosting with bots): `KothBots._fill_teams` adds copies
  of a placed bot or removes extras; on the host a joining player replaces a bot of his team
  (`KothBots.make_room`, `NetGame.remove_tank`) and a leaving one is replaced
  (`KothBots.refill`, `NetGame.add_bot_tank`). Bots mark enemies they see for the team
  through `TankCommand.spot` (`BotData.spot_remark_s`); SpotMarks shows teammates' spots. Per-tank stats (KO, losses, points) in `KothMode.get_stats()` (sent
  in the net state); `Scoreboard` in the player rig shows them on Tab and at the end
  (result, Play again / Main menu). Network: the host sends `get_net_state()` to
  clients (`rpc_koth_state`, 2 Hz and on zone moves/match end; clients run the clock
  on) and kill bonuses (`rpc_koth_bonus`); NetGame (re)spawns players at the zone
  spawns, and with KotH the bots fill teams 1 and 0 alternately instead of team 2.
  Spawns lift the tank 1.5 m (origin is mid-hull) so it doesn't start in the ground.
  Every placement calls `Tank.face_forward()` (turret and gun straight ahead, `placed_version`
  bumped; a puppet's respawn jump too): commander view, gunner sight and the player's aim snap
  to the hull's front.
  Rule sets: `koth_default.tres` (unused since Vikbolandet went) and `koth_tactical.tres` (Vidingsjö, Linghem, campus:
  slower, less shrink, kill bonus for any knock-out of an enemy in the zone
  (`kill_bonus_needs_shooter_in_zone` false), `zone_placement` ROAMING and bot attack axes).
  ROAMING: after the first (marker) zone, `KothMode._choose_roaming_zone` tries
  `roam_candidates` places `roam_min_m..roam_max_m` from the last zone, one per physics
  frame, mostly along the front near the middle between the teams; fair = similar
  `TacticalMap.path_info` cost and cover from both teams' centres, a cover mix in the zone
  (`area_info`); markers nearby add a bonus. Attack axes (`KothData.bot_attack_axes`, in
  KothBots): per zone each team gets 3 axes round its side (fewer known enemies first),
  pairs per axis (`_mate`) meet at an assembly point `assembly_distance_m` outside the zone
  (wait <= `assembly_wait_max_s`; respawns don't wait), then bound towards their axis'
  entry point; `support_per_team` bots watch from outside and don't hunt. The gap is not
  a hurry then.
- Free fight (`FreeFight`, node in `scenes/scenarios/{vidingsjo,linghem,campus}_free.tscn`; rules
  `data/modes/free_fight.tres`, `FreeFightData`; host/offline, also the bot director): the players (team 0,
  co-op) against waves of bots (`bot_team` 1). Start: a random open spot in a circle round the map's centre
  (`spawn_edge_margin_m` inside the edge). Round r: `start_count` + r/2 bots × (1 + `extra_player_share` per
  extra player), easy (`bot_easy.tres`, BT-7/T-34) on even rounds, hard (`bot_regular.tres`, any preset) on
  odd ones, spot times and gun errors × `creep_per_round`^r (floor `creep_floor`). A wave spawns
  `wave_distance_*_m` from the living players, preferably where none can see (`_seen_by_players`), each bot at a
  `find_position` spot within `wave_radius_m` (moved to the nearest open ground if it isn't: terrain under it and
  nothing solid in a tank-sized box, `KothMode.box_clear`; the grid misses small houses), and holds (DEFEND: no orders; the maps draw its circle,
  `MapView._draw_wave`) until a crew spots a player or is hit (`BotController.contact`): the wave hears of it
  (`share_contact`) and attacks (ATTACK: every `attack_think_s` each bot drives to a `find_position` spot
  `attack_range_m` from the nearest known player, `attack_step_m` closer each arrival, down to `attack_min_m`).
  Beaten: knocked-out players come back beside a living teammate (`spawn_for_new`), next wave after
  `wave_gap_s` (the old bots go then, wrecks stay). All players out: `is_over()` (Scoreboard "DEFEATED", waves
  beaten, KO/assists/lost). HUD `FreeFightPanel`. Bot allies (main menu "Bot allies" in place of Tanks per team for Free fight maps, `MatchSettings.free_allies`, `FreeFightData` "Allies"): bots on the players' team, made beside the first player (`_make_allies`), keeping a place beside the nearest living player (`_ally_place`) until they or a player (`Tank.spotted`) know an enemy within `ally_engage_m`, then firing spots as the wave's attackers (`_ally_fight`); they count for the end (the match goes on while one lives), come back with the players and grow the waves by `ally_wave_weight`. NetGame starts no respawn timers with it; clients get
  `get_net_state()` by `rpc_free_state` (2 Hz and on its signals). The map's placed enemies are removed.
- Tutorial (`TutorialMode`, node `Tutorial` in `scenes/scenarios/vidingsjo_tutorial.tscn`; data `TutorialData` with
  `TutorialStepData` stages, `data/modes/tutorial.tres`; TUTORIAL_PLAN.md): offline only, no lobby (`NetSession.play_offline`
  skips MatchLobby for `*_tutorial`; `MainMenu.find_maps` leaves it out of the map list and the server vote; the menu's
  Tutorial button is highlighted until `user://settings.cfg` tutorial/done). The map's PlayerRig plays, moved to
  `start_position`/`start_yaw_deg`: the grove with a crest south of Vidingsjö's start (905, 1625), facing the open field
  south, the road 100 m east. Stages carry a map `area` (`TutorialStepData.area/area_radius_m/area_label`, drawn as a
  dashed orange circle by `MapView._draw_tutorial_area`): drive marker, target area at the south forest edge, the heavy
  tank at the west edge, the grove for the squad, the road for the mine, the final test's enemy area. Until the final
  test the player's tank is `Tank.damage_immune` (`TankDamage.immune`: hits jolt and ring but harm nothing); the smoke
  lesson's attacker stands ahead of the turret, so the smoke lands between.
  Nine lessons (drive to a beam, hatch, binoculars on a target, spot it, hit it (a short round gets "Kort!"), HE on a KV-2's
  track, squad out / mine / recall, smoke and back away 20 m out of a firing bot's sight, two easy bots); tanks are placed
  in their area (`_find_in_area`, in sight of the commander's eye when possible), else round the tank (`_find_spot`). Hold `skip_tutorial_step` (Backspace) 3 s to skip a lesson (`TutorialPanel` ring).
  Knocked out or overturned: back where it last stood upright. Voices `assets/audio/radio/tut_*.ogg` via SquadRadio.
- Map edge (`MapEdge`, `scripts/world/map_edge.gd`, `data/world/map_edge.tres`): the playable area is the map
  picture's `world_rect` less `margin_m` (50). No physics body (every ray with the default mask would hit
  it): `Tank._hold_inside_map` takes a tank's speed outwards past it and pushes it back in; `TacticalMap`
  closes cells outside (paths, `find_position`, `is_blocked`); squad orders are clamped (`Tank.SQUAD_EDGE_INSET_M`);
  KotH spawns keep `SPAWN_EDGE_INSET_M` inside; the maps darken outside it and draw a line.
- ThunderRoad (a gauntlet; `ThunderRoadMode` node `ThunderRoad` in a scenario with children
  `Route` (Path3D along a road) and `Checkpoints` (Marker3Ds, projected onto the route;
  movable), rules in `data/modes/thunder_road.tres` (`ThunderRoadData`), bots by
  `ThunderRoadBots`). Attackers take the next checkpoint by outnumbering the defender tanks
  inside its zone (`ThunderRoadMode.is_in_checkpoint`: a rectangle square to the road,
  `capture_half_width_m` across, `capture_half_length_m` along); each capture moves the front, adds to the
  attackers' shared lives and brings a wave. Every checkpoint has the same clock, `checkpoint_time_s` (360; fresh at
  the round start and when the hand-over after a capture ends, nothing carries over). Fighting retreat
  (`ThunderRoadData` "Retreat", `retreat_instead_of_pause` on since 2026-11-14, like Battlefield's Breakthrough):
  after every capture but the last, `retreat_s` (40 s; `is_paused`, signals `pause_started`/`pause_ended`, net key
  "pz") the clock and waves stand but nobody stops fighting; the defenders' line jumps at once to
  `retreat_line_past_m` (60, the lost zone's far edge) past the checkpoint taken and stays there; a defender left
  behind within the corridor's width (`is_left_behind`) makes a last stand: may fire, a spot mark for the attackers
  every `retreat_mark_s` (1 s), knocked out by rule at `retreat_s` (HUD "LEFT BEHIND"); attackers advance, no regroup.
  Off, the old ceasefire: `pause_s` (40 s, `pause_blocks_fire`), attackers within `pause_attacker_ahead_m` (50) past
  the checkpoint, defenders back `pause_defender_back_m` (200) past it (at most to the next zone's near edge),
  ThunderRoadBots `_regroup`s attackers. Either way everyone gets fresh orders when it ends (`_on_ceasefire_over`). HUD: "CHECKPOINT n TAKEN – REGROUP" / "FALL BACK TO CHECKPOINT n"; a capture flashes a big
ZONE CAPTURED / ZONE LOST (`ThunderPanel._flash`, `flash_s`; smaller ones for round start, ceasefire over / enemy
advancing, enemy regrouping, 2/1 minutes left). No Swedish subtitles anywhere (the English flash says what happens). Command radio (`ThunderRoadData.calls`,
`ThunderCallsData`, `data/modes/thunder_calls_sv.tres`, recordings `assets/audio/radio/cmd_*.ogg` from
`make_elevenlabs.sh <src> <out> thunder`): ThunderPanel queues them in `SquadRadio.command_call` (after crew
shouts, before squad calls): taken / last one secured, lost + "Fall tillbaka till ÅSA n" (n = the next checkpoint: the recording, which ends on "ÅSA", plus a number cut from the clock hours, cut points in the script), the enemy regrouping mid-ceasefire
(attackers), "Fienden kommer" when it ends (defenders), 2 and 1 min left per side, leaving the corridor, the line
held at the round's end; rare stand-ins (`lost_rare`, `return_rare`, a few %); crew banter on the intercom
(`crew_start/win/loss_*`; fighting retreat: `advance`, `stragglers` (4 s after a capture if any defender is left behind), `next_open`, `enemy_coming_more`, `tank_lost` for a teammate lost behind the line, crew `left_behind`/`left_behind_late`/`made_it_back` for the own tank): a random line when a round gets going (`_start_pending`, once the own tank is
there and the break is over) and on the match's win/loss. Points
  (`ThunderRoadData` "Points", stats column 5, Scoreboard sorted by them, signal `points_scored`): kill 20,
  assist 10, each attacker in the zone when it falls 100, attackers taking it 2/s, defenders in it with
  attackers there 2/s, every living defender when the attackers run out of time or lives 100. Knocked-out attackers wait for the wave (on a
  capture or every `wave_interval_s`, a life each, behind the front); defenders come back
  after `defender_respawn_s` `defender_spawn_checkpoints` past the next checkpoint, never nearer than
  `defender_spawn_min_ahead_m` (470, `defender_spawn_beyond_m` 210; 150 m further back since 2026-11-12) past it (past the road's end, the last checkpoint, the spawn goes
  on straight: `slot_point`, and `project` extrapolates the last segment) (`defender_spawn_checkpoints` 1; at the round start in the first checkpoint's zone,
  `defender_start_in_zone`, to dig in; the route has no checkpoint in its first spacing, a free drive to the fight).
  Waves every `wave_interval_s` (30).
  Time up with a living attacker in the checkpoint's zone: overtime (`is_overtime`, HUD
  "OVERTIME"); the round ends `overtime_grace_s` (3 s) after the last one left or fell.
  Corridors: defenders within `defender_half_width_m` of the road and ahead of the front less
  `defender_behind_front_m` (150; `get_defender_line_s`, so forward defenders fight on when a checkpoint falls),
  attackers within `attacker_half_width_m` and short of `get_attack_limit_s` (`attacker_ahead_of_checkpoint_m`
  100 past the next checkpoint; no rally on to the one after). Outside: `Tank.fire_blocked` (no gun or MG),
  a spot mark for the other team every `outside_mark_s`, knocked out after `outside_knockout_s` (30;
  `Tank.knock_out_by_rule`, a loss nobody scores). Bots never aim to go outside: `BotController.keep_goal` (set by ThunderRoadBots,
  `_keep_inside`) moves every goal they drive to, ordered or their own (dash, relocation, hiding), `INSIDE_MARGIN_M`
  (40) inside the corridor. Corridors 400 m (attackers) / 350 m (defenders) half width since 2026-11-12; attackers
  start with `start_lives_per_tank` × tanks + `start_lives_extra` (5) lives. Round 1 team 0 attacks, round 2 sides swap; more checkpoints wins,
  then more time left. Taking every checkpoint should be rare: the match is meant to be
  won on the count. The `round_break_s` (10 s) pause blocks all fire; after round 1 the
  tanks go to round 2's starts at once (`_setup_round`, repaired, map reset) and stand locked
  (`Tank.move_blocked`: no driving, turret/optics free; bots wait) for the countdown.
  `ThunderPanel` shows ROUND 1 OVER and how it went at the top, the `Scoreboard` in the
  middle (shown through every break) and "ROUND 2 STARTS IN n" at the bottom (round 2's goal counts down in the HUD, `ThunderPanel.target_state`: "2 MORE CHECKPOINTS TO WIN" ->
  "WIN SECURED"; defenders "STOP THEM: 2 MORE AND THEY WIN"); after round 2 a big
  VICTORY/DEFEAT, then the final `Scoreboard` (also on Tab: the rounds, KO/losses from
  `ThunderRoadMode.get_stats`). The fresh map (`_reset_map`: wrecks, mines, smoke go,
  `TreeField.restore_all`, signal `map_reset`) comes with the break; clients reset 1.5 s
  after the round's end. The first round waits for `ThunderRoadBots` to fill the teams
  (`hold_start`/`release_start`). Bots: attackers to a `find_position` spot in the next
  checkpoint; defenders take posts (`defender_post_ahead_share` 0.5 between
  the attackers and the zone, `defender_post_zone_share` 0.3 in it, the rest just behind), move when
  the front moves, and mine all they can (`ThunderRoadBots._mine_step` every 4 s once standing
  (hardly moving, orders or not) and as the front moves: a carried mine goes out, 65 % between the
  next checkpoint's zone and the front, else in the zone, within 240 m along the road of the tank;
  empty, the squad is recalled to refill; BotController doesn't recall a squad out on a mine job) (`BotController.order_squad`). HUD `ThunderPanel`; `MapView._draw_route` draws road,
  own corridor and checkpoints. `RespawnAtStart` leaves respawns to the mode. Online: the
  host runs it, clients get `ThunderRoadMode.get_net_state()` (`rpc_thunder_state`, 2 Hz and
  on checkpoints/rounds/end; per-tank wave/respawn/outside by net_id, stats rows), emit the
  same signals and run the clocks on; round 2's map reset runs on clients too (1.5 s late, so
  puppets' wrecks go). NetGame starts no respawn timers with ThunderRoad and spawns joiners
  by `spawn_for_new`; `ThunderRoadBots` has `make_room`/`refill` like KothBots
  (`NetGame._bots_director`). Both bot directors wait a frame after NetGame so the map's
  own PlayerRig isn't counted when filling teams. Missions: `vidingsjo_thunder_red` (Haningeleden) and
  `vidingsjo_thunder_orange` (Ålerydsvägen + Haningeleden), made by
  `tools/thunder_route_from_osm.py` (named OSM roads between two points -> scene; rerun
  overwrites checkpoint moves; `--join=M` across roundabouts), and `road_to_science_thunder` (Åsmestadsrondellen at
  Lambohovsleden -> Vallastaden past Isovalen -> Campus Valla -> Mjärdevi, 2.5 km, 6 checkpoints; the 5.4 km
  Vidingsjö version was dropped 2026-11-11, raw data in `geodata/road_to_science_lang/`) on the corridor map `road_to_science` (see below), made with
  `--path=geodata/road_to_science/korridor.json` (a ready route of any roads/paths). `corson_thunder` (corridor map
  `corson`, 1.25 × 2.7 km): a short course, a straight line north -> south through Campus Valla (1.5 km, 4
  checkpoints; `geodata/corson/korridor.json` written by hand, not from OSM), checkpoints moved along the route
  off the houses by `tools/thunder_checkpoints_avoid_houses.py`. `linghem_thunder` (whole map, not a corridor):
  south -> north, forest paths, then along Himnavägen, diagonally through the houses to the station (3.2 km,
  7 checkpoints; the last ~260 m before the end so defender spawns stay on the map). Route from a Google Maps
  screenshot by `rutt_ur_bild.py` run in a scratch folder (it writes a korridor.json, which in
  `geodata/linghem/` would trim the next rebuild), simplified (25 m), then `--path=`.
- Sound: `SoundSetData` (`data/sounds/*.tres`, random variant, optional `distant` set
  far away) on `TankData.sounds` (`TankSoundData`: engine, tracks, gun, hatch),
  `ShellData` (hit armour/ground, ricochet; explosive shells add `sound_explosion` on every impact) and `MachineGunData.sound_shot` (one per bullet, `GunfireSound`, polyphonic).
  `TankAudio` (made by Tank) reads only tank state, so puppets sound the same;
  `SoundFx.play_at()` plays one-shots delayed by distance / speed of sound
  (`data/world/audio.tres`). Buses (`default_bus_layout.tres`): `World` is muffled
  while the own hatch is closed (`HatchMuffle` in the player rig), the own tank uses
  `Own`; cannon shots (`SoundSetData.pierces_hull`) go from World to bus `Blast`, only lightly
  muffled (`AudioData.blast_*`). Files in `assets/audio/` (CC0, see `CREDITS.md`; made with `tools/audio/`).
  Headless runs report "leaked at exit" for any playing AudioStreamPlayer: harmless.
- Physics runs at **30 Hz** (`physics/common/physics_ticks_per_second`; a slow tank game needs
  no more, and every `_physics_process`, ray and body costs half; physics interpolation keeps
  it smooth). Never count rates in ticks: use `Ticks.every(hz)` (ticks apart) or
  `Ticks.due(clock, delta, hz)` (time-paced sends); net rates are in Hz (`SNAPSHOT_HZ` 20,
  `NetInput.SEND_HZ` 30, `SQUAD_SEND_HZ` 10). Ballistics is Heun-integrated, so shells land
  where the sight says at any tick rate. `Ballistics.superelevation_for_range` caches angles per shell in 5 m steps
  (bots ask every scan; the bisection cost 3-4 ms a tick in a 10 v 10).
- Per-frame cost (10 v 10 ThunderRoad, 1920x1080 window: 17.2 ms at 60 Hz before 2026-11-09,
  9.0 ms after 30 Hz and the HUD fixes): HUD code must not call `add_theme_*_override`, set
  bus effects or camera properties, or `queue_redraw` every frame when nothing changed
  (maps redraw at `MapView.REDRAW_HZ` 20, panels 10-15 Hz, `CommanderStatus` only while it
  shows something, `HatchMuffle` only when the hatch moves); route/path lookups that run per frame use
  binary search (`ThunderRoadMode._segment_at`); collision shape transforms are only set when
  they change (`Tank._sync_turret_shapes`). Trees have detail levels (below): GPU time in
  the fixed views fell 35-50 % (far view 9.9 -> 5.4 ms).
- Visual effects (cosmetic, local on every machine, nothing sent; bots see through them):
  `EffectFx` plays `EffectData` (`data/effects/*.tres`: `BurstData` particle bursts + a fading
  light) and makes continuous emitters from a `BurstData`; `EffectsSetData`
  (`data/effects/effects.tres`) says which plays where. `Shell._play_impact` picks by surface
  (armour: tanks, commander, wrecks; building: other static bodies; wood: trees; else ground),
  bullets (< 20 mm) their small set, explosive rounds add `explosion`; size = calibre / 75.
  `Tank._muzzle_effects`: flash plus blast dust when the muzzle is within
  `blast_dust_height_m` of the ground. Flash and gun smoke grow as (calibre/75)^
  `muzzle_calibre_exponent` (0.25), the dust takes `blast_dust_calibre_share` of that and
  shrinks with muzzle height (`blast_dust_high_share`). `TankDust` (made by Tank, like TankExhaust) throws dust
  behind the tracks by speed times `WeatherData.dust_factor` (rain 0). `Burning` (burning.tscn)
  is flames + a smoke column (`fire_flames`, `fire_smoke`). `GunSmoke` uses `gun_smoke` (8 puffs,
  `BurstData.near_fade_m` dithers puffs near the camera out: three shots in front of the
  commander's view cost ~0.4 ms GPU instead of ~2). `SmokeCloud` draws 20 camera-facing puffs
  (`EffectFx.puff_texture`, `billboard_keep_scale`) up to the top of its vision-blocking
  cylinder, so the player can't see over what blocks bots. Soft particles are unshaded,
  tinted by the weather's light, with a noise puff texture and proximity fade.
  `EffectFx.prewarm` (WeatherView) plays everything once below the map so shaders compile at
  load. Pictures: `godot --path . --disable-vsync --fixed-fps 60 --script
  res://tools/render_effects.gd -- [map] [label]` -> `renders/effects/<label>/`.
  Measured: no frame time cost in a 10 v 10 match.
- Prototype graphics: simple shapes (boxes, cylinders). Only free, correctly licensed
  assets (Kenney, Sketchfab CC with attribution). Never assets from other games.

## Physics layers and terrain

- Layers (named in project settings): 1 `world` (terrain, hulls, tree trunks),
  2 `vehicles` (tanks, also on 1; watched by tree push triggers),
  3 `commander_hitbox` (exposed commander, Area3D), 5 `vision_blocker` (bushes,
  canopies, Area3D). Anything that "sees" uses `Vision.has_line_of_sight()`;
  shells and fragments use `Vision.SHOT_MASK` and pass through vision blockers.
- Terrain: Terrain3D v1.1.0 in `addons/terrain_3d` (desktop binaries only). Maps
  must use collision mode Full / Game (shells and nests act far from the camera).
  In game modes ray hits report the Terrain3D node as collider.
- The starter `hills` map and Vikbolandet were removed 2026-11-11 (in git history).
- New real maps: `geodata/.venv/bin/python geodata/scripts/nytt_omrade.py <name> <lat,lon> <lat,lon>`
  (fetches OSM, LM/Copernicus, NMD; builds; imports; makes `scenes/maps/<name>.tscn`).
- Corridor maps for ThunderRoad (`geodata/scripts/hamta_korridor.py <name> <start lat,lon> <end lat,lon>`
  fetches the box round both ends plus 600 m, reusing laser tiles of other areas): with
  `geodata/<name>/korridor.json` (route in SWEREF, `bredd_m`, `kant_m`) the build puts houses,
  trees, bushes and stones only near the route (`geodata/scripts/korridor.py`, ragged edge);
  terrain and roads cover the whole box. `road_to_science`: route from OSM along a Google Maps
  measurement (`rutt_bild.json`, `rutt_google.png`, git-ignored), 500 m + 120 m edge (box 3.0 × 1.9 km, so
  nearly all of it has houses). Steps for a new one:
  `hamta_korridor.py` (`--via` for bends wider than the ends; the user runs it, LM login) ->
  points read off the screenshot into `<name>/rutt_bild.json` -> `geodata/scripts/rutt_ur_bild.py
  <name>` (route + korridor.json) -> `nytt_omrade.py` with the stored corners (build, import,
  scene) -> `tools/corridor_map_scene.py <map> <EnemyName>` (bot, respawn, start) ->
  `bake_tactical_grid` -> `thunder_route_from_osm.py --path=` -> `render_map_image`.
- Terrain textures (`tools/terrain_textures.json`: 8 ambientCG CC0 1K textures, land cover
  class -> texture, blend/slope/shoulder rules, material settings): `geodata/.venv/bin/python
  tools/pack_terrain_texture.py` fetches and packs them into `assets/terrain/`;
  `tools/terrain_control.py geodata/<map>/out` writes `terrain_control.r32` (Terrain3D control
  bits per pixel: class textures, soft borders, rock on steep slopes, gravel road shoulders);
  `tools/import_geodata_map.gd -- <map> res://geodata/<map>/out --textures` puts list, material
  (auto shader off, macro variation) and control/colour maps on an imported map without
  touching heights (nor the object glb: run the plain import first). Then rerun `render_map_image`. Done: vidingsjo (others still auto shader).
  Orthophoto (Lantmäteriet, `geodata/scripts/hamta_ortofoto.py`, 0.5 m from the 16 cm 2025 flight): with
  `<out>/ortofoto_tint.png` (`ortofoto_tint.py`: the land cover tint times the photo's variation within each class;
  trees, houses, shadows and forest neutral) and `ortho_tint.enabled` the `--textures` import uses it as the colour
  map. The colour map can only darken, so neutral is encoded at `neutral_linear` (0.55) and every texture's
  `albedo_color` is raised to match; Terrain3D takes albedo_color as sRGB, so the factor is encoded sRGB. Hedges:
  `hackar.py` finds straight lines in each block's grid (direction from OSM house edges and streets per 80 m tile;
  laser 0.5-2.8 m hits projected on 1 m bands, gaps up to 6 m bridged unless a house, road or non-green area is in
  between; green in the IR band, even height, broken where something taller stands) -> `work/hackar.pkl` segments,
  which step4 lays out as rows of low-poly 'hack' bushes (3 tufts, 240 tris, 1 m apart, stretched along the hedge);
  laser bushes in a hedge and not much taller are replaced, big bushes stay. OSM hedges become the same rows.
  Previews `geodata/forhandsbilder/hackar_vidingsjo_*.png`; views 34-38 in `render_views.json`. Cost +0.2 ms
  average (+0.6 max) in Vidingsjö (63k hedge bushes); the first try with full `buske` models cost +0.8/+2.9. Hedges on
  all maps (vidingsjo, linghem, campus, road_to_science, corson; tactical grids rebaked, bushes count as cover); the
  orthophoto colour map only on vidingsjo (the only map with terrain textures).
- House style (types, colours, facades with windows, semi-realistic areas) comes from
  `geodata/stilar.json`; rebuild the map to apply changes.
- Real maps such as `scenes/maps/vidingsjo.tscn`
  (3.4 × 3.1 km, Linköping) come from the Python pipeline in `geodata/` (see its
  CLAUDE.md; folder has `.gdignore`). Origin at the map's NW corner, 2 m vertex spacing.
  After rebuilding geodata, rerun `tools/import_geodata_map.gd -- <name> <out dir>`
  (rewrites `terrain/<name>/`, copies object glb, trees and tree models to
  `assets/maps/<name>/`). `tools/build_geodata_scene.gd` made each scene once; don't
  rerun it on a scene that has been edited. Buildings get collision via
  `scripts/world/mesh_collision.gd`. Laser trees (`scripts/world/tree_field.gd`,
  `@tool`, per-instance colour, models and species from the info file) follow the `BreakableTree` rules without nodes.
  Drawing: each 500 m data chunk is split into `draw_cell_m` (250 m) draw cells; the tree
  meshes get detail levels at load (`ImporterMesh.generate_lods`, lost when `_mesh_from`
  merges a model) and Godot's mesh LOD picks one per cell by on-screen error, so binoculars
  and the gunner's sight (camera FOV) keep full detail. Fixed distance levels were tried and
  dropped: trunks vanished and crowns turned ugly at fighting range in the binoculars.
  A tree's draw cell/index (`_draw_cell`, `_draw_index`) is separate from its physics chunk;
  `_set_drawn` hides/restores it. Physics and the rest:
  tank pushes look up trees in an 8 m grid (`TREE_CELL_M`), never whole chunks;
  `FieldTreePhysics` makes one static body (trunks, layer 1) and one area (crowns,
  layer 5) per chunk in the PhysicsServer3D, with TreeField as collider; `TreePush`
  is a copy of BreakableTree's push rule (keep them in step); felled trees animate
  with `FallingTree`. Sizes per species in `data/world/field_tree_*.tres`
  (`FieldTreeData`). Bushes are a second TreeField (`Bushes`, data `field_bush_*.tres`,
  `has_trunk = false`): crowns block sight (and count as cover), tanks and shells pass.
  `tree.tscn`/`BreakableTree` are no longer used by any map.
- Bridges and underpasses come from the geodata pipeline (`geodata/scripts/broar.py`): glb group
  `Broar` (decks, parapets, pillars, trench floors, retaining walls). `mesh_collision.gd` gives
  `Byggnader`, `Broar`, `Stenar` and `Banhinder` trimesh collision. Underpasses are tank-sized (≥ 5 m wide, 3.8 m clear).
- Roads come from OSM with Trafikverket's NVDB attributes (`geodata/scripts/nvdb.py`: real width, surface,
  speed; `vagmarkering.py`: centre/warning/no-overtaking/edge lines and zebra crossings as thin meshes in
  the glb group `Vagar`). So far rebuilt: vidingsjo, linghem, campus (2026-11-11; with all roadside,
  traffic lights, playgrounds, ground cover).
- Railways come from the geodata pipeline (`geodata/scripts/jarnvag.py`, OSM): banvall shaped in the
  heightmap, glb group `Jarnvag` (ballast, sleepers, rails, catenary wires; no collision, tanks drive
  over) and `Banhinder` (catenary masts, rail bridge decks, platforms; collision). So far only Linghem.
- Orienteering maps (club-owned, private use only, in `geodata/<area>/data/`, outside git) add
  boulders (`Stenar`; `StoneLook` in the player rig gives them `assets/shaders/stone.gdshader`: flat
  facets from screen derivatives, mottled granite, lichen, moss on top, wet in rain), thickets (extra bushes) and marsh/open-land classes: `geodata/scripts/okarta.py`.
- Map pictures (minimap, big map on M): `tools/render_map_image.gd -- <map>` renders
  `scenes/maps/<map>.tscn` from above (needs a window, not `--headless`; add
  `--disable-vsync`) into `assets/maps/<map>/map_image.png` + `data/maps/<map>_map.tres`
  (`MapImageData`). The HUD finds it from the Terrain3D data directory name. Rerun
  after map changes. Spot marks live in `SpotMarks` (player rig), drawn by `MapView`. The own tank shows
  as a hull arrow plus a cone for where the player looks (`PlayerViews.get_view_camera`).
- Main menu and garage (`MainMenu`, `Garage`, built in code, look from `MenuTheme`: dark see-through
  fields, orange primary button, `add_backdrop`/`add_title`; the garage dims the picture; it only shows
  the five presets (no building any more): `TankPreview` (the tank painted as a friend turning on a
  dark disc), `TankSummary` and the stat bars) over `assets/ui/menu_background.jpg`, rendered in the game by
  `godot --path . --disable-vsync --fixed-fps 60 --script res://tools/render_menu_background.gd --
  [map] [weather] [friend|enemy]` (tank, running squad, an HE burst with an extra dirt fountain;
  frames after the burst in `renders/menu/`; the picture is dusk_enemy_0300, kept ungraded in
  `assets/ui/raw/` (.gdignore) and graded HDR-like by `geodata/.venv/bin/python
  tools/grade_menu_background.py [strength]` (default 0.6: local shadow lift, detail, vibrance)). Note the canvas
  stretch: UI sizes are in 1152x648 units.
- Deploy (choosing team and tank in the match): nobody has a tank on arrival. `MatchLobby`
  (`scripts/control/`, added by NetGame on every machine, offline by `NetSession.play_offline` from
  the main menu's Single player; F5/F6 on a scenario has none) shows `DeployScreen` over a camera
  circling the team's tanks (`DeployData`, `data/ui/deploy.tres`): page BRIEFING = the mode's
  `display_name`/`briefing` (`KothData`/`ThunderRoadData`, `{score}` = score_to_win; no mode:
  "Free fight") and both teams' rosters with Join buttons, then page TANKS = the presets list,
  `TankPreview` and `TankSummary` (speed, gun, armour, special: from TankData/ChassisData against the
  middle preset, `DeployData.margin_share`). Online: `NetGame.pick_team` (`rpc_pick_team`; roster
  shows "choosing a tank") and `request_deploy` (`rpc_deploy`, preset keys only:
  `TankConfigs.preset_of_key`) -> the host makes room (director `make_room`), spawns, refills;
  `NetGame.roster` ([team, name, `DeployScreen.Kind`, type, peer]) goes out by `rpc_roster` at
  `ROSTER_HZ` when changed. Directors' `_target_size()` = max(team_size, players on either team), so a
  crowded team's opponents get bots. Offline the lobby takes the map's PlayerRig out after two frames
  (a bot refills) and brings a new rig at the chosen team's spawn (only team 0, "Team 1", outside KotH/ThunderRoad).
  The Esc menu's Change tank uses DeployScreen's tank page. Only presets exist (`TankConfigs.all()` =
  presets; old `user://configs/` builds are ignored).
- Trailer takes (`tools/trailer/`): `tools/trailer/record.sh <shot> [key=value]` films a scripted shot
  (`shots/<shot>.gd`, extends `trailer_shot.gd`: actors made in `setup()`, tanks driven only by
  `TankCommand`s, cameras in `frame()`) with Godot's Movie Maker to `renders/trailer/<shot>.mp4`
  (1080p60 + sound, ffmpeg) and a cue list; `snap=all` instead writes JPGs to check a shot quickly.
  Shots: opening, turret_toss, playground, column, ambush (infantry; its thrown man is a cheat RigidBody),
  smoke (Sherman, four kills, smoke and a cut-away move; reload, sight and wind are cheats),
  kv2_plow (two T-34s, a field of wrecks, a KV-2 that shoves them aside and shrugs off AP; end=flank|kv;
  cheats: reload, AP that pings, light wrecks, a pushed turret, hits that always land), advance (filler: seven
  T-34s and their squads cross the field towards Vallastaden, HE in the field);
  `record_all.sh` films every take.
- Graphics before/after: `godot --path . --disable-vsync --script res://tools/render_views.gd --
  <map> <label> [weather,...]` renders the fixed views in `tools/render_views.json` (1920x1080,
  bots removed, HUD hidden) to `renders/views/<label>/` with frame/GPU ms, draw calls and
  triangles in `results.txt`; `geodata/.venv/bin/python tools/compare_views.py <a> <b>` puts two
  runs above each other. Baselines: `before` (2026-11-09, old terrain, all six weathers),
  `zoom_lod2` (new terrain, light, tree LOD; includes the binocular views 8 and 9).
- Weather (`WeatherData`, presets `data/weather/*.tres`; `Weather.current()` statics):
  `WeatherView` in the player rig dresses the map at runtime (own sky shader
  `assets/shaders/sky.gdshader` with clouds, sun angle/colour, AgX, SSAO, glow, fog density
  from `visibility_m`) on copies of the map's Environment; map scenes are not edited.
  Per preset also colour grading (`contrast`, `brightness`, split toning `grade_*` as a 1D
  colour-correction curve) and `ssao_intensity_factor`; settings common to all weathers
  (sun shadow distance/cascades, SSAO, glow) are in `GraphicsData` (`data/world/graphics.tres`,
  `WeatherView.graphics`; shadows 450 m, cheap since tree LOD).
  Presets: clear, overcast, dawn, dusk, fog (`Weather.PRESETS`); main menu "Weather"
  (`MatchSettings.weather`, "random" default) is fixed per match by `Weather.resolve()`
  (Single player / Host); clients get the host's in `rpc_welcome`. Rules for all:
  bots' and squads' view ranges are cut to `visibility_m` (`Weather.view_range`), spotting
  takes `spot_time_factor` longer (`Concealment.spot_time_factor`, soldiers too). Own gun
  smoke (`GunSmoke`) is on the gun's render layer, so the own gunner's sight sees through it.
  Rain (`rain.tres`, `rain_intensity`): `RainField` (streaks round the camera, no
  collision), `RainGlass` (drops on the optics, `rain_glass.gdshader`, under the optics
  mask), loops from `tools/audio/make_rain.sh` (outside on World, roof drumming on Own,
  louder with the hatch shut), wet terrain (Terrain3D texture assets, put back on exit),
  `hearing_db` turns World/Blast down (HatchMuffle). Wind drifts clouds, exhaust, gun smoke,
  fire smoke (`burning.gd`, `fire_smoke_drift_share`) and `SmokeCloud`s
  (`WeatherData.smoke_drift_share`: they follow the ground and stretch downwind; host and
  clients drift by the same rule, nothing sent). Squad smoke grenades are 65 % of a tank's cloud.
- Vegetation that matters for gameplay is real scenes (`tree.tscn`, `bush.tscn`),
  placed with the `Scatter` tool node, not the Terrain3D instancer (no collision).

## Controls

- Driving: **WASD**, controlled directly by the player.
- Main gun: mouse 1 in the gunner's sight. In the commander view mouse 1 spots an
  enemy, not a place: `Tank.find_spotted` takes the enemy tank or soldier nearest the
  point within `TankData.spot_snap_deg`/`spot_snap_min_m` that the commander or own squad
  leader can see; nothing near = no mark (cooldown `TankData.spot_cooldown_s` either way).
  `Tank.spotted(target, point)`; `SpotMarks` keeps one mark per enemy (`SpotMarks.key_of`:
  net id / instance id, squads negative; `rpc_team_spot(key, point)`), moved and renewed by
  any new spot, gone when the tank is knocked out; tanks a diamond, squads a ring. Marks fade per
  `data/world/spotting.tres`. Commander view: turret holds its hull-relative
  direction; T lays it on the view. MG: mouse 2 (roof MG in the commander view with the hatch
  open, coaxial otherwise). Binoculars: B. Hatch: H.
- Scoreboard: Tab (King of the Hill). Big map: M (view only). Squad orders map: Q (`SquadMap`, 1 km round the tank with
  the 300 m ring; frees the mouse; left click sends the squad, right click lays a mine). Recall squad: G. Squad escorts the tank: F. Squad leader's eyes: V (look and spot only). Statistics (FPS, frame times, draw calls, network): F3.
- Smoke: X. Esc: frees the mouse and opens `EscMenu` (resume, change tank, switch team
  (online), answer a swap request, abandon tank, main menu). Change tank (`TankSwitch`) =
  a respawn at the team's spawn in the new type (a fresh tank can't be rebuilt in place:
  offline a new PlayerRig, online `NetGame.respawn_player`); a loss unless within
  `TankSwitch.FRESH_S` of spawning and unhit; knocked out, it comes at the respawn
  (`Tank.repaired`). Stats follow (`carry_stats`). Switch team (host, `NetGame.on_team_switch`):
  takes a bot's place on the other team (the director refills), else the player picks one
  of the other team to ask (`rpc_team_choices`/`rpc_swap_offer`, notice in `MatchNotice`),
  who accepts or declines in the Esc menu; both respawn on the other side at once.
- Main menu Controls button: `ControlsPanel` (`scripts/ui/controls_panel.gd`) lists sections of keys and a short
  explanation from `data/ui/controls.txt` ("## Heading", "action,action | text", `{action}` in the text = its
  key); key names come from the Input Map (`ControlsPanel.key_of`), so rebinding updates it. Add a line there
  when a new control comes.
- Settings (`SettingsPanel`, from the main menu's Settings and the Esc menu's Settings…; values in `GameSettings`,
  `user://settings.cfg` sections input/audio/video, defaults and presets in `SettingsData`, `data/ui/settings.tres`):
  mouse factor and invert (every camera takes motion through `GameSettings.look`), volumes on buses Master,
  `Effects` (World, Own and Blast send to it; ping and Wilhelm play on it) and `Voice` (SquadRadio), graphics
  presets Low/Medium/High or Custom (render scale with FSR, shadows off/near/normal/far, SSAO, glow,
  anti-aliasing, grass range (`GroundCover` copies its rules at map load), mesh LOD threshold), window mode,
  v-sync, frame cap. `NetSession` applies them at start; `WeatherView` re-applies shadows/SSAO/glow when
  `GameSettings.version` changes. Nothing in it may let a player see more than bots (fog, trees and the far
  vegetation are never offered).
- Help: F1 (`show_help`) shows `ControlsPanel` in the match (`HelpOverlay`, player rig HUD); the first match
  shows a card of tips once (`data/ui/intro.txt`, `user://settings.cfg` help/intro_seen). The free debug camera
  is F2 (`toggle_debug_view`).
- Further bindings are defined in the Input Map (project settings), never hardcoded keys.

## Checking for errors (run these yourself)

- Load/import the project: `godot --headless --path . --import`
- Check one script: `godot --headless --path . --check-only --script res://path/to/file.gd`
- Run a scene briefly: `godot --headless --path . res://path/scene.tscn --quit-after 300`
- Run these after changes and read the output before telling the user something works.
  Feel/visuals still need the user to test in the editor (F5/F6).

## Way of working

- Work in small steps. One limited feature at a time; explain what was changed and why.
- Use plan mode before bigger features.
- After a step works, the user tests in Godot and we commit. Commit often.
- Division of labour: the user places terrain, lights and objects in the editor;
  Claude writes logic and may create scene files.
- Prefer editing `.tscn`/`.tres` files carefully; keep them valid (unique ids, correct
  `ext_resource` paths). Don't edit `project.godot` by hand unless needed.

## Done: Prototype 1

Tank of primitive shapes on a flat test area: WASD driving with raycast suspension,
mouse-aimed turret/gun, hatch with cupola/periscope views, gunner's sight with a
ballistic range ladder (boresighted at a zeroing range), simulated shells with
reload/recoil/tracers, and target boards at known ranges.

## Current milestone: Prototype 2 – something to fight

- damage model, first step: armour and penetration from data, impact angle matters
- an enemy target tank to shoot at (step towards bots)
- first bots (Vidingsjö): patrol, spot by the same rules, shoot back, MG on open
  hatches. Next: tuning, shared spotting/minimap, bots that move to fight.

## Network (two players and up; built for 10v10 / 20v20)

Host-authoritative, Godot ENet, all in `scripts/net/`:
- `Net` autoload (`net.gd`, class `NetSession`; scripts use `NetSession.instance`, plain
  and @tool scripts read `NetRole`). Port 24680, 3 channels. Raw packets
  (`SceneMultiplayer.send_bytes`) for snapshots (host -> client, 20 Hz, unreliable) and
  commands (client -> host, 30 Hz, unreliable, `NetCommandCodec`); everything else is
  reliable RPCs on `/root/Net`. Maps load on a thread and ENet timeouts are 30–60 s, so a
  slow map load doesn't drop the connection. F3 = statistics (FPS and net).
- `NetGame` (added to the loaded map): spawns players once they deploy (`MatchLobby`; team 0
  at the map's PlayerRig, team 1 at its first enemy tank, or the mode's spawns), removes the map's rig/enemies (enemies stay as team-2
  bots on the host if bots are on), respawns players after 10 s, forwards events
  (shells + ricochets, hit results to the shooter, spots to the team, felled trees).
- One packed snapshot per recipient (`NetReplicator`, `TankNetState` ~38 B per tank, plus
  owner-only hp/modules/reload; enemy hp is never sent). `NetRelevance` decides which
  tanks go in (v1: all) – that's where far tanks get a lower rate later.
- Clients: every tank is a puppet (`Tank.net_puppet`: frozen, no simulation),
  interpolated 100 ms behind (`NetPuppets`). The own tank predicts turret, gun, hatch
  and roof MG from the local command (`net_predict`); hull follows the host.
  Shells on clients are cosmetic (`Shell` cosmetic flag); MG fire is a snapshot flag.
- Host drives remote tanks with `RemoteController`. Start menu `scenes/menu/main_menu.tscn`
  (Host: map + bots, Join: IP e.g. Tailscale, Single player; team and tank are chosen in the
  match, `MatchLobby`). Command line after `--`:
  `--host [--map vidingsjo] [--bots]`, `--join <ip>`, `--name N`, `--port N` (default 24680; lets
  a test host run beside a game already hosting).
- Dedicated server (`--dedicated [--map m] [--log-dir d]`, `DedicatedServer`, child of NetSession; data
  `ServerData`, `data/server/server.tres`; SERVER_PLAN.md): the host plays nobody (NetGame adds no lobby/rig),
  bots fill to `team_size`; a match ends when its mode `is_over()` or after `max_match_s`, the result shows
  `result_s`, then every client gets `VotePanel` (rpc_vote_open/state/close, `rpc_vote`) listing every scenario
  (`MainMenu.find_maps`/`scenario_label`); most votes wins, a tie by lot, none = next in the list; nobody
  connected = waits. `NetSession.change_map` sends `rpc_change_map` (clients reload, keep the connection, send
  `rpc_ready` again; the host queues readies that come while it loads, `take_pending_ready`) and the host keeps
  `known_peers` (names, tank keys) for the next NetGame. Log: one JSON line per match/vote/join/leave in
  `server_log.jsonl`; `tools/server/vote_stats.py` sums it up; `tools/server/vagnstrid-server.service`
  (systemd). Testing: `--max-match-s 40` shortens matches and the vote.
- Player guide (Swedish): `SPELA_ONLINE.md` (hosting, joining, Tailscale, F3).
- Measured: ~0.8 kB/s per tank per recipient. Test with two (or three) headless
  instances running scratch scripts (`--script`, the autoload is there), or two windows.
- Not yet: hull prediction, lag compensation, lobby/team choice, game modes, dedicated
  server menu, BreakableTree/MG nests over the network.

Later: Terrain3D for real maps (check it supports Godot 4.7 first), damage model,
spotting/minimap, bots, game modes, multiplayer.
