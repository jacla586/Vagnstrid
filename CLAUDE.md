# Stridsvagn – tank game (hobby project)

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
  `ShellData.damage_hp` and damages modules on the shell's path (`module_reach_m`); ammo =
  knocked out, fuel = fire. Hits that don't penetrate wear their plate cell (`ArmourData`
  wear settings, `ShellData.wear_mm`). Tracks are external: any shell landing on them and HE
  fragments (`ModuleFragmentTarget`) damage them. Standing still `repair_time_s` repairs
  modules, then hp creeps back to `repair_hp_max_fraction`. The player sees own hp/modules
  (`DamagePanel`), never the enemy's; bots stop to repair when they have no target.
- Infantry squads (`Squad`, `scripts/squad/`; data `SquadData`, `data/squads/`,
  `TankData.squad`): one unit of 4 soldiers per tank, made by the tank and living in
  the map beside it. Orders only via `TankCommand.squad_order`/`squad_target`
  (move / recall); the tank passes them on. Mounted it rides unseen; sent out it gets
  off behind the tank and walks paths from `TacticalMap.for_scene(scene, tactics)`
  with infantry costs (`data/squads/tactics_infantry.tres`), at most
  `max_distance_from_tank_m` (300) from the tank; recalled or left behind it runs back
  and mounts. Soldiers move one by one: a loose place each on the move (own pace,
  drift), and when holding each his own spot 4-9 m round the squad's point (covered if
  possible), facing out and kneeling once still. The leader is the
  first living soldier; V (`toggle_squad_view`, `SquadCamera`, `PlayerViews` SQUAD
  mode) looks through his eyes while the squad is off the tank: look and spot only, no
  control, no turret or guns; binoculars on B. Spotting like tank crews (sight lines,
  concealment; all round holding, a cone ahead moving): spotted enemies become team
  marks (`Tank.report_squad_spot`, also signal `squad_contact`). Soldiers have
  `SoldierHitbox` areas (layer 3, fragment targets): any hit puts one down; one is
  "Wilhelm" (10 % scream, 50 m). Holding still they fire rifles (`rifle_bullet.tres`,
  low accuracy) at exposed commanders and soldiers, and AT rounds (`squad_at.tres`,
  `ShellData.cannot_knock_out`: never a kill) at tanks within 150 m. Fired on by a
  tank (hit or `Squad.notify_impact` near miss) they smoke (`SmokeCloud`, a vision
  blocker) and fall back; losses to rifles: fall back. Mounted they refill one by one;
  wiped out, a full squad is back after `wipe_cooldown_s`. HUD: `SquadPanel`.
  Soldiers use `assets/models/soldier/soldier.glb` (CC-BY, KolosStudios, see its
  CREDITS.md; uniform materials repainted green) with animations (jog, crouch, death...)
  from Quaternius' Universal Animation Library (CC0, `assets/models/ual/`), retargeted by
  direction matching with `tools/bake_soldier_animations.gd` into
  `assets/models/soldier/soldier_anims.res` (rerun if a model changes). Own team's
  squads show on the maps.
  Network: clients send squad orders by reliable RPC (`rpc_squad_order`); the host
  sends all squads in a 10 Hz unreliable packet (`PACKET_SQUADS`, `Squad.write_net_state`,
  31 B + 4 B per soldier offset) and soldier-down/smoke/shot events by RPC; client
  squads are puppets.
  Bots: see and MG enemy squads (no tank target); use their own squad via the command
  when the tank stops (look ahead / towards an alert / the enemy, `find_position`
  with infantry costs), recall it when hurt, left behind or driving on; squad
  contacts reach the crew and (KothBots) its team. Decided rules: memory
  `squad-rules`.
- Tanks have a coaxial MG and a roof MG (`TankData.coax_mg`/`roof_mg`). The roof MG
  only works with the hatch fully open, aimed at `TankCommand.mg_aim_point`.
- Bots: `BotController` (extends `TargetTankController`, so patrols waypoints) with
  crew skill in `BotData` (`data/bots/*.tres`). Spots only via `Vision` from its own
  commander's eye (hatch open: all round, far, fast; closed: periscope sector),
  stops to fire with range/laying errors that shrink per shot, MGs exposed
  commanders, closes the hatch when hit or an enemy is close. `Tank.team` decides
  enemies. `RespawnAtStart` brings a knocked-out tank back (test bench).
- Concealment (`Concealment`, `data/world/concealment.tres`): sight-blocker shapes
  (layer 5: bushes, tree crowns, laser-tree crowns) around a target, and standing
  still, make it slower and shorter-ranged to spot; moving fast makes it easier.
  Bots also spot faster the more of 4 hull points (+ exposed commander) they see.
- Tank builder / garage: `TankConfig` (only part ids: chassis, gun, armour package,
  camouflage) -> `TankBuilder.build()` -> `TankData` (cached per `key()`), from the
  catalogue `data/builder/catalogue.tres` (`ChassisData` light/medium/heavy/tank
  destroyer, each with its `GunData` 37-120 mm and `ArmourPackageData`; coefficients in
  `BuilderRules`: speed and acceleration from kW/t, turn rate from mass, traverse from
  gun mass, hp per tonne, camouflage). The chassis' `base` TankData supplies the rest.
  Medium + 75 mm = today's tank. `Tank.apply_geometry()` sizes hull, tracks, turret,
  gun and suspension from `TankData` geometry (scene measures are the reference, consts
  `BASE_*`); `Tank.config` builds the data at start. Camouflage
  (`TankData.camo_spot_factor`) slows bot and squad spotting; spot points scale with the
  hull (`Tank.get_spot_points`). Garage `scenes/menu/garage.tscn` (from the main menu,
  which also picks the tank); `TankConfigs` keeps presets (`data/configs/`), own configs
  (`user://configs/`) and the choice (`user://garage.cfg`). The player rig's tank
  (`use_player_config`) uses the choice offline; online the client sends its config key
  in `rpc_hello` and spawns carry a spec (`TankBuilder.spec_of`/`apply_spec`: "cfg:<key>"
  or a TankData path). KotH gives placed bot tanks random `KothData.bot_configs`
  (`KothMode._give_bots_configs`, before tanks are ready). Line-ups (three tanks within
  a budget) come later; cost is already computed.
- The player's tank uses `data/tanks/player_medium.tres` (set in `player_rig.tscn`)
  unless a garage tank is chosen; enemies use `test_medium.tres`. Binoculars zoom `binocular_zoom_vs_gunner` times
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
  between zones and when the zone closes soon. Positions: `TacticalMap.find_position()`
  scores candidate spots for cover, hull down (grid heights towards the threat), sight
  lines from the commander's eye and spacing from teammates (weights in TacticsData);
  KothBots uses it with `BotController.get_threat_direction()` (own knowledge only;
  default: the enemy's side of the zone). Bounding (in KothBots, not BotGroup, so
  Hackerstad is unchanged): near the zone or after contact a team's bots pair up and
  move in turns (one watches, one drives to the next `find_position` spot that must
  get closer; the watcher goes anyway after `overwatch_max_s`, a move is never cut
  short). Long drives go by a random flank point (teammates prefer different flanks)
  so routes vary. Shoot and scoot (`TacticsData.shoot_and_scoot`): after a shot a bot
  backs to a spot its target's commander can't see while it reloads, then comes up a
  few metres to the side; hit repeatedly from one side, it relocates (find_position
  away from that threat). Needs a baked grid. Without a baked grid bots drive
  straight. Baked so far: vidingsjo. Spawns avoid blocked cells.
- `BotGroup` moves bots together: column along a route, on the first contact
  (shared to all members) line abreast towards an objective, short halts to fire.
  Bots on an ordered route that get stuck reverse and detour sideways.
- Scenarios are scenes inherited from a map (`scenes/scenarios/*.tscn`, base e.g.
  `vikbolandet.tscn`), so map edits carry over. `hackerstad.tscn`: player at
  Hackerstad, 6 bots advance from Ring along the road (Vikbolandet).
- King of the Hill (`KothMode`, node `KothZone` in a scenario; its Marker3D children
  are the spots where zones may open; rules in `data/modes/koth_default.tres`,
  `KothData`). Zones one at a time: open at full size, hold, shrink while scoring
  faster; a zone closes when it has paid out its point budget (zone scoring and kill
  bonuses) or at its lifetime; the next spot shows on the map during the gap. First to
  `score_to_win` wins (`zone_count` 0 = no zone limit). Never
  contested: each team scores per own tank in the zone (capped), the team with most
  tanks there gets a multiplier, an in-zone knock-out from inside the zone gives a
  bonus. Each zone moves the spawns (`get_spawn`/`get_free_spawn`): `south_team` south
  of it, other teams north, `spawn_distance_m` away (closer if off-map/water/house).
  Tanks go to their spawn at the start; respawns (`RespawnAtStart`, `KothBots`) use the
  current spawn. `KothBots` orders every BotController into the (next) zone. Runs
  offline/host only. HUD: `ScorePanel`; `MapView` draws zone and own spawn.
  Scenario: `vidingsjo_koth.tscn`. Network: the host sends `get_net_state()` to
  clients (`rpc_koth_state`, 2 Hz and on zone moves/match end; clients run the clock
  on) and kill bonuses (`rpc_koth_bonus`); NetGame (re)spawns players at the zone
  spawns, and with KotH the bots fill teams 1 and 0 alternately instead of team 2.
  Spawns lift the tank 1.5 m (origin is mid-hull) so it doesn't start in the ground.
- Sound: `SoundSetData` (`data/sounds/*.tres`, random variant, optional `distant` set
  far away) on `TankData.sounds` (`TankSoundData`: engine, tracks, gun, hatch),
  `ShellData` (hit armour/ground, ricochet; explosive shells add `sound_explosion` on every impact) and `MachineGunData.sound_shot` (one per bullet, `GunfireSound`, polyphonic).
  `TankAudio` (made by Tank) reads only tank state, so puppets sound the same;
  `SoundFx.play_at()` plays one-shots delayed by distance / speed of sound
  (`data/world/audio.tres`). Buses (`default_bus_layout.tres`): `World` is muffled
  while the own hatch is closed (`HatchMuffle` in the player rig), the own tank uses
  `Own`. Files in `assets/audio/` (CC0, see `CREDITS.md`; made with `tools/audio/`).
  Headless runs report "leaked at exit" for any playing AudioStreamPlayer: harmless.
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
- `tools/generate_hills.gd` and `tools/build_hills_scene.gd` made the starter
  `scenes/maps/hills.tscn` once; the map is now edited in the editor. Don't rerun
  them (they overwrite the user's edits).
- New real maps: `geodata/.venv/bin/python geodata/scripts/nytt_omrade.py <name> <lat,lon> <lat,lon>`
  (fetches OSM, LM/Copernicus, NMD; builds; imports; makes `scenes/maps/<name>.tscn`).
- House style (types, colours, facades with windows, semi-realistic areas) comes from
  `geodata/stilar.json`; rebuild the map to apply changes.
- Real maps `scenes/maps/vikbolandet.tscn` (6.6 × 7 km) and `scenes/maps/vidingsjo.tscn`
  (3.4 × 3.1 km, Linköping) come from the Python pipeline in `geodata/` (see its
  CLAUDE.md; folder has `.gdignore`). Origin at the map's NW corner, 2 m vertex spacing.
  After rebuilding geodata, rerun `tools/import_geodata_map.gd -- <name> <out dir>`
  (rewrites `terrain/<name>/`, copies object glb, trees and tree models to
  `assets/maps/<name>/`). `tools/build_geodata_scene.gd` made each scene once; don't
  rerun it on a scene that has been edited. Buildings get collision via
  `scripts/world/mesh_collision.gd`. Laser trees (`scripts/world/tree_field.gd`,
  `@tool`, MultiMesh per 250 m chunk, per-instance colour, models and species from the info file) follow the `BreakableTree` rules without nodes:
  `FieldTreePhysics` makes one static body (trunks, layer 1) and one area (crowns,
  layer 5) per chunk in the PhysicsServer3D, with TreeField as collider; `TreePush`
  is a copy of BreakableTree's push rule (keep them in step); felled trees animate
  with `FallingTree`. Sizes per species in `data/world/field_tree_*.tres`
  (`FieldTreeData`). Bushes are a second TreeField (`Bushes`, data `field_bush_*.tres`,
  `has_trunk = false`): crowns block sight (and count as cover), tanks and shells pass.
  hills.tscn still uses `tree.tscn`/`BreakableTree`.
- Bridges and underpasses come from the geodata pipeline (`geodata/scripts/broar.py`): glb group
  `Broar` (decks, parapets, pillars, trench floors, retaining walls). `mesh_collision.gd` gives
  `Byggnader`, `Broar` and `Stenar` trimesh collision. Underpasses are tank-sized (≥ 5 m wide, 3.8 m clear).
- Orienteering maps (club-owned, private use only, in `geodata/<area>/data/`, outside git) add
  boulders (`Stenar`), thickets (extra bushes) and marsh/open-land classes: `geodata/scripts/okarta.py`.
- Map pictures (minimap, big map on M): `tools/render_map_image.gd -- <map>` renders
  `scenes/maps/<map>.tscn` from above (needs a window, not `--headless`; add
  `--disable-vsync`) into `assets/maps/<map>/map_image.png` + `data/maps/<map>_map.tres`
  (`MapImageData`). The HUD finds it from the Terrain3D data directory name. Rerun
  after map changes. Spot marks live in `SpotMarks` (player rig), drawn by `MapView`.
- Vegetation that matters for gameplay is real scenes (`tree.tscn`, `bush.tscn`),
  placed with the `Scatter` tool node, not the Terrain3D instancer (no collision).

## Controls

- Driving: **WASD**, controlled directly by the player.
- Main gun: mouse 1 in the gunner's sight. In the commander view mouse 1 spots
  (red mark on the minimap, cooldown `TankData.spot_cooldown_s`, marks fade per
  `data/world/spotting.tres`). Commander view: turret holds its hull-relative
  direction; T lays it on the view. MG: mouse 2 (roof MG in the commander view with the hatch
  open, coaxial otherwise). Binoculars: B. Hatch: H.
- Big map: M (view only). Squad orders map: Q (`SquadMap`, 1 km round the tank with
  the 300 m ring; frees the mouse; left click sends the squad). Recall squad: G. Squad leader's eyes: V (look and spot only). Network statistics: F3.
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
  slow map load doesn't drop the connection. F3 = net statistics.
- `NetGame` (added to the loaded map): spawns from the map (team 0 at its PlayerRig,
  team 1 at its first enemy tank), removes the map's rig/enemies (enemies stay as team-2
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
  (Host: map + bots, Join: IP e.g. Tailscale, Single player). Command line after `--`:
  `--host [--map vidingsjo] [--bots]`, `--join <ip>`, `--name N`, `--port N` (default 24680; lets
  a test host run beside a game already hosting).
- Player guide (Swedish): `SPELA_ONLINE.md` (hosting, joining, Tailscale, F3).
- Measured: ~0.8 kB/s per tank per recipient. Test with two (or three) headless
  instances running scratch scripts (`--script`, the autoload is there), or two windows.
- Not yet: hull prediction, lag compensation, lobby/team choice, game modes, dedicated
  server menu, BreakableTree/MG nests (hills.tscn) over the network.

Later: Terrain3D for real maps (check it supports Godot 4.7 first), damage model,
spotting/minimap, bots, game modes, multiplayer.
