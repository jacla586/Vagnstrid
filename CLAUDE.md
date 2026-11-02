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
- Shells are simulated (gravity, travel time); hit detection by raycasting from the
  previous to the current position each physics frame, not by fast physics bodies.
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
- Real maps `scenes/maps/vikbolandet.tscn` (6.6 × 7 km) and `scenes/maps/vidingsjo.tscn`
  (3.4 × 3.1 km, Linköping) come from the Python pipeline in `geodata/` (see its
  CLAUDE.md; folder has `.gdignore`). Origin at the map's NW corner, 2 m vertex spacing.
  After rebuilding geodata, rerun `tools/import_geodata_map.gd -- <name> <out dir>`
  (rewrites `terrain/<name>/`, copies object glb, trees and tree models to
  `assets/maps/<name>/`). `tools/build_geodata_scene.gd` made each scene once; don't
  rerun it on a scene that has been edited. Buildings get collision via
  `scripts/world/mesh_collision.gd`. Laser trees (`scripts/world/tree_field.gd`,
  `@tool`, MultiMesh per 250 m chunk) follow the `BreakableTree` rules without nodes:
  `FieldTreePhysics` makes one static body (trunks, layer 1) and one area (crowns,
  layer 5) per chunk in the PhysicsServer3D, with TreeField as collider; `TreePush`
  is a copy of BreakableTree's push rule (keep them in step); felled trees animate
  with `FallingTree`. Sizes per species in `data/world/field_tree_*.tres`
  (`FieldTreeData`). hills.tscn still uses `tree.tscn`/`BreakableTree`.
- Vegetation that matters for gameplay is real scenes (`tree.tscn`, `bush.tscn`),
  placed with the `Scatter` tool node, not the Terrain3D instancer (no collision).

## Controls

- Driving: **WASD**, controlled directly by the player.
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

Later: Terrain3D for real maps (check it supports Godot 4.7 first), damage model,
spotting/minimap, bots, game modes, multiplayer.
