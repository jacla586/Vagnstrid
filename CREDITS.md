# Credits

Vagnstrid is a hobby game by Jacob. The code was written with
[Claude Code](https://claude.com/claude-code) (Anthropic). Everything listed here is free to use
under the licence given; the full source lists are linked.

## Map data
The maps are built from open data by the pipeline in `geodata/`.

- **OpenStreetMap** contributors, [ODbL](https://www.openstreetmap.org/copyright): roads, houses,
  railways, water, playgrounds, signs, traffic lights, place names.
- **Lantmäteriet**, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/): elevation model,
  laser point clouds (terrain, single trees and their heights) and orthophoto (ground colour), processed.
- **Naturvårdsverket**, Nationella marktäckedata (NMD), CC0: land cover.
- **Trafikverket**, NVDB (road widths, surfaces, speed limits, crossings) and culverts, open data.
- **Jordbruksverket**, field blocks and crops (what grows in each field), open data.
- **Copernicus DEM**: produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus
  Defence and Space GmbH 2014-2018, provided under COPERNICUS by the European Union and ESA.

## Models and animation
- Soldier: "Soldier" by **KolosStudios** ([Poly Pizza](https://poly.pizza/m/XT8jgwSesV),
  [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)), uniforms repainted. Details:
  [`assets/models/soldier/CREDITS.md`](assets/models/soldier/CREDITS.md).
- Soldier animations: [Mixamo](https://www.mixamo.com) (Adobe), baked into the game; the source
  files are not distributed.
- Tanks, houses, bridges, trees, road furniture and playgrounds are generated in code.

## Sound and voices
- Sound effects from [Freesound](https://freesound.org) (CC0) and
  [Kenney](https://kenney.nl/assets/impact-sounds) (CC0); every file and author is listed in
  [`assets/audio/CREDITS.md`](assets/audio/CREDITS.md).
- Voices: **[elevenlabs.io](https://elevenlabs.io)** (free plan: attribution required,
  non-commercial use only).
- Earlier radio voice: [Piper TTS](https://github.com/rhasspy/piper), voice `sv_SE-nst-medium`
  (KBLab, CC0).

## Textures
- Terrain textures from [ambientCG](https://ambientcg.com) (CC0).

## Engine and libraries
- [Godot Engine](https://godotengine.org) (MIT) with [Jolt Physics](https://github.com/jrouwe/JoltPhysics) (MIT).
- [Terrain3D](https://github.com/TokisanGames/Terrain3D) by Cory Petkovsek, Roope Palmroos and
  contributors (MIT).

The in-game list (main menu → Credits) is `data/ui/credits.txt`; keep the two in step.
