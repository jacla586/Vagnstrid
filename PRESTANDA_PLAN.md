# Prestanda: läget och nästa steg

Överlämning 20 november 2026, för att ta vid nästa gång. Arbetet ligger på grenen **`prestanda-cpp`**
(från `undergangar`, commits 3d64c6d och framåt). Inget är sammanslaget med `undergangar` eller `main`.

## Var vi står (Vidingsjö Thunder Orange, RX 5700, Jacobs grafikinställningar, vsync på)

| Lag | FPS | Fysiktick |
|---|---|---|
| 10 mot 10 | 59–60 | cirka 7,5 ms |
| 15 mot 15 | 47–52 | – |
| 20 mot 20 | 18–38 (svänger mycket mellan körningar) | 14–21 ms |

En bildruta i 20 mot 20 tar 30–55 ms, medan ett tick tar 14–21 ms. Över 33 ms per bildruta blir det
flera tick per bildruta, och då finns inga lediga bildrutor kvar att lägga spaningen på.

Per tick i 20 mot 20:
- **Vagnarnas skript:** cirka 5 ms, varav fjädring 1,2 och drivning 0,8 ms.
- **Botarna:** cirka 5 ms. Skanningen tar 2,6 ms: förhämtning 0,95, syn på vagnar 0,57 och syn på
  trupper 0,78 ms.
- **Trupperna:** cirka 4 ms. Soldaternas steg tar 1,6, skanningen 0,5, gången 0,5 och
  överkörningstestet 0,5 ms.
- **Jolt och övrigt:** cirka 4 ms.

## Gjort

- **Lediga bildrutor** (`Ticks.light_frame`): botarnas och truppernas spaning körs i `_process` på
  bildrutor utan fysiktick.
- **Billigare spaning med samma regler.** Billiga kontroller görs först. Fiender långt bort tittas
  på glesare, och tiden mellan blickarna räknas ändå.
- **`SightRays`:** en skannings siktlinjer skjuts samtidigt på `WorkerThreadPool`. Det ger 4–5 gånger
  snabbare strålar, och svaren är kontrollerat identiska.
- **Skanningsintervallet** sträcks i takt med antalet fiendevagnar över 10, upp till dubbelt.
- **`TacticalMap.find_position`** räknas mot planeringsbudgeten.
- **Lugna trupper i halv takt:** ingen fiende inom 300 m och ingen kamera inom 200 m.
- **Knuffkontrollen** körs 5 gånger per sekund.
- **VagnFast (C++, `native/`):**
  - alla vagnars fjädringsstrålar på trådar (1,72 → 1,21 ms)
  - bandkrafterna summerade till en kraft och ett moment (1,21 → 0,81 ms)
  - botarnas förhämtning av siktlinjer (1,19 → 0,95 ms)

  Alla tre är kontrollerat identiska, och GDScript-versionerna finns kvar som reserv.

- **Världsbilden i C++ (21 nov):** `VagnFast._ensure_world` frågar varje vagn och trupp en gång per tick.
  Både botarnas och truppernas förhämtning (`prefetch_squad_sight`, ny) läser den. 0 avvikande svar på
  cirka 310 000 linjer. Headless 20 mot 20: botarnas förhämtning 1,23 → 0,77 ms per tick, truppernas
  0,21 → 0,17 ms. Ungefär 7 % av punkterna flyttas senare i ticket (soldater, lucka som öppnas) och
  får läsarens egen stråle. Slutsats: resten är strålarna, inte frågorna. Nästa vinst kräver färre
  strålar (t.ex. återanvända svar mellan botar med samma öga), inte mer C++.

- **Bildrutans `_process` mätt (21 nov,** `perf_match.gd -- clear size=20 proc`**):** faser som stänger av
  `_process` för Squad, BotController, TankLooks, GroundCover, TankAudio, avgaser/damm, all UI och vädret,
  varvade med basfaser. Ingen av dem sänker bildrutan mätbart: skillnaderna ligger inom matchens egen drift
  (26 → 49 ms under körningen). Bildrutan är fysiktick: 14–20 ms per tick, och över 33 ms blir det två tick
  per bildruta. GPU 14–15 ms och render-CPU 5–6 ms går bredvid. Allt att vinna ligger alltså i ticket.

- **Tidtagning per funktion (21 nov, headless 20 mot 20, Thunder Orange, 1 800 tick).** I ms per tick:
  - Botar 4,5: spaning 2,3, `_order_step` 0,8, `_update_squad` 0,4, `_update_abandon` 0,15, planering ~0,5.
  - Vagnar 4,5: fjädring 1,1, drivning 0,8, `_sync_turret_shapes` 0,34, `_update_damage` 0,34,
    `_update_turret` 0,29, `_update_commander_hitbox` 0,14.
  - Trupper 3,2: `_move_soldiers` 1,1, `_walk` 0,46, spaning 0,43, `_check_run_over` 0,38, minor 0,11.
  - ThunderRoadBots 0,72 och ThunderRoadMode 0,70 (lägesregler varje tick), TankLooks 0,45, TreeField 0,2.

- **Vad som växer under matchen (22 nov,** `tools/perf/growth_probe.gd`**, headless 20 mot 20, Thunder Red):**
  fällda träd. Varje `FallingTree` låg kvar som en egen nod med trädets odelade mesh (inga detaljnivåer,
  ingen räckviddsgräns, skugga): 462 efter 200 s, +780 `MeshInstance3D`. Nu läggs ett liggande träd tillbaka i
  cellens MultiMesh och noden tas bort. Med fönster efter 90 s: 18 → 23 fps, bildruta 57 → 43 ms, draw calls
  7 278 → 6 369, GPU 19,2 → 16,1 ms, tick 18,5 → 16,9 ms. Headless växer ticket inte (12–14 ms hela vägen),
  med fönster gör det fortfarande (13,8 → 16,9 ms på 90 s), och draw calls växer +700 (vrak, minor, decals,
  rök). `GunSmoke` når ~50–100 samtidigt headless (partiklarnas `finished` kanske inte kommer utan renderare).
- **Spaningens takt (22 nov,** `perf_match.gd -- clear <scen> size=20 scan`**, faserna varvade):** halv takt
  för alla botar och trupper sparar ~1 ms per tick, en fjärdedel ~1,6 ms (av ~15). Det är taket för att dela
  strålarna i buntar, så det är inte värt mycket.

- **Soldaternas blickar spridda (22 nov, A/B med** `growth_probe.gd -- ab`**):** en tittares cache för det som inte
  beror på tittaren (`Squad._seen_*`, identiska svar utom vid Concealments 12-ticksgräns) sänkte kostnaden per anrop
  (bot 7,5 → 6,3 µs, trupp 10 → 6,6 µs). Varje fiendesoldat tittas på igen var 4:e runda (`soldier_look_rounds`),
  men alltid inom 100 m, nyss avlossad, MG:ns trupp och truppens fiende. Ostört: 15,08 → 14,93 ms per tick (−1 %).
  Undantagen gör att de flesta blickarna blir färska ändå. Ligger kvar (avstängt med `soldier_look_rounds = 1`).
- **Var ticket går (22 nov,** `growth_probe.gd -- classes`**, headless 20 mot 20, Thunder Red, `--fixed-fps 30`):**

  | Del | ms per tick |
  |---|---|
  | Före skripten (motorns synk och köer) | 1,7 |
  | Skripten | 13,3–13,9 |
  | Jolts steg | 1,7–1,8 |
  | Bildrutans `_process` | 2,0 |

  Skripten per klass:

  | Klass | ms per tick |
  |---|---|
  | BotController | 3,7–4,3 (spaning ~2,5) |
  | Tank | 3,7 |
  | Squad | 2,8–2,9 (spaning ~0,8) |
  | ThunderRoadMode | 0,65 |
  | ThunderRoadBots | 0,5 |
  | TankLooks | 0,3 |
  | Övrigt | 0,9 |

  Jolt är alltså inte problemet. Vagnarnas `contact_monitor` av eller på gav ingen skillnad (A/B `ab=contacts`).

- **Spaningen på trådar (22 nov,** `ScanBatch`**, `scripts/ai/scan_batch.gd`):** botarnas och truppernas blickrundor
  körs tillsammans en gång per bildruta, först i `_process`.
  - **BEGIN** (huvudtråden): vilka mål som ska tittas på, och alla vagnars och soldaters globala transformer räknas
    ut. Node3D räknar dem lat, och två trådar samtidigt läste fel i 5 av 2 400 fall i ett test.
  - **JOBB**: en blick per mål, på 11 `Worker`-noder i undertrådsgrupper. Varje jobb skjuter sina egna strålar, så
    ingen förhämtning behövs.
  - **END** (huvudtråden): bokföring, signaler och målval.

  `WorkerThreadPool` kan inte användas, eftersom bara trådgrupper får läsa noder. Delade cacher har lås:
  `Concealment._cache_lock` och `Squad._seen_lock`. Kontrollerat: 281 461 jobb körda om på huvudtråden, 0 avvikelser.
  A/B (`growth_probe.gd -- ab=threads`, 240 s, tick + bildrutans `_process`): 17,47 → 16,85 och 17,29 → 16,39 ms,
  alltså −0,6 till −0,9 ms.

  **Taket:** GDScript som läser objekt skalar dåligt på trådar. Varje objektreferens valideras mot ObjectDB, som
  har ett globalt spinnlås, och referensräknarna delas. Mikrotest med 20 000 nodläsningar per tråd: 2,1 ms på en
  tråd, 6,7 ms per tråd med 11 trådar, alltså ~3,5 gånger genomströmningen. Det gäller även ett exporterat
  release-bygge. Rena beräkningar skalar fint (0,9 → 1,4 ms). Trådarnas sammanlagda arbetstid blir 4–7 ms för det
  som tar ~2,5 ms på en tråd. `PhysicsRayQueryParameters3D.new()` per stråle registrerar dessutom ett objekt varje gång.

- **Botarnas tänkande i 15 Hz (22 nov,** `BotController.think_hz`**):** order, sikte, eld och trupp varannan tick
  (botarna turas om). Däremellan går vagnen på det senaste kommandot, utan engångsdelarna (skott, rök, order,
  spotting). A/B (`ab=think`, 240 s): tick 12,50 → 11,89 ms, alltså −0,6 ms. Spaningen behåller sin egen takt.
- **AI-detalj efter relevans (22 nov,** `Relevance`**, `scripts/ai/relevance.gd`):** botar och trupper längre än
  `far_m` (400 m, marginal 100 m) från varje mänsklig spelares vagn (PlayerController/RemoteController, gruppen
  `human_controllers`) och kameran tänker i `far_think_hz` (7,5) och spanar `far_scan_factor` (2) gånger så sällan,
  med samma regler (`BotData`/`SquadData` "Far from players"). A/B (`ab=relevance`, testspelaren stilla vid
  anfallarnas start): 600 m −0,27 ms, 300 m −0,44 ms (tick + bildruta). Litet, eftersom båda lagen samlas kring
  zonen, och spelaren är där.
- **Mönstret från sökningen (22 nov):** billiga test först, glesare koll på avstånd (World of Tanks 9.16), och
  AI-LOD efter relevans för spelaren. Vi gör alla tre nu. Återstår: förberäknad synlighet mellan rutor (minne och
  3D-höjder gör den svår) och delad spaning (bryter regeln om egna ögon).
- **Läget efter 22 nov:** kostnaden är utspridd. Vagnarna ~3,7–4 ms, truppernas gång ~2,1, botarnas tänkande ~1,8,
  spaningen ~1,5–1,9 (trådad), lägena ~1,1, motorns köer ~1,7, Jolt ~1,7 och bildrutans `_process` ~2. Ingen enskild
  del ger mer än någon ms.

## Provat utan effekt och borttaget

- **Återanvända fjädringsstrålar för stillastående vagnar, i GDScript:** 37 % färre strålar, men
  listorna med svaren kostade lika mycket.
- **Trådbatch av fjädringsstrålar i GDScript:** att samla och dela ut svaren åt upp vinsten.
- **Fysik på egen tråd** (18 nov): skripten fick `null` från fysikvärlden.

## Lärdom

Det dyra är inte matematiken utan att **fråga GDScript-objekten**: `is_enemy_of`,
`get_spot_points`, `is_soldier_exposed` och så vidare, och **motorns strålar**. Båda kostar ungefär
lika mycket från C++ som från GDScript. C++ lönar sig bara när datan också finns i C++.

## Nästa steg, i ordning (ny strategi 22 nov)

Gallring av spaningen ger högst några procent, eftersom undantagen behövs för spelets skull. Kostnaden är
GDScript per mål, och den kan inte göras mycket billigare. Den kan däremot köras **parallellt**.

1. ~~**Spaningen på trådar.**~~ Gjort 22 nov (se ovan): −0,6 till −0,9 ms. Taket är GDScripts objektåtkomst.
   **Nästa steg för spaningen är C++:** jobbens blick (`BotController._look_compute`, `_squad_look_compute`,
   `Squad._look_compute`) i VagnFast från världsbilden. Den behöver då också skyddet (Concealment: en
   formfråga per mål och 12 tick), soldaternas ställning, rörelse, avslöjande och växtlighet (`GroundCover`-rutnätet
   kopierat till C++), och en parallell loop i C++ utan ObjectDB. Uppskattat: jobben ~2,5 ms CPU → ~0,3 ms vägg.
2. **Botarnas tänkande i 15 Hz,** halva botarna varje tick: `_order_step`, `_update_squad`, `pick_target` och
   `_update_abandon`. Uppskattat ~0,9 ms. Styrningen räcker: 13 m/s är 0,9 m på två tick.
3. **ThunderRoad-lägena** (1,1 ms) i 10 Hz där reglerna tål det, t.ex. korridorkontroller och skyltar.
4. **Vagnens småfunktioner** (`_sync_turret_shapes`, `_update_damage`, `_update_turret`) och soldaternas steg
   (`Squad._move_soldiers`), som förut.
5. Uppskjutet: täckning cachad längre för stillastående mål, och hela vagnsblicken i C++.

## Mäta

- **Helhet:** `godot --path . --script res://tools/perf/perf_match.gd -- clear size=20 vsync`, eller
  `size=10`/`15`, utan `vsync` för okapade tider. Det öppnar ett fönster, så kör inte samtidigt som du
  spelar.
- **Per funktion:** tillfällig tidtagning med `Time.get_ticks_usec()` runt anropen, summerad i en
  statisk `Dictionary` och skriven ut per tick. Ta alltid bort den efteråt och kontrollera med
  `grep PROF`. Det gjordes för hand med ett Python-skript den här gången.
- **Identiska svar:** kör den gamla vägen bredvid den nya och räkna avvikelser under en headless-match
  med `MatchSettings.team_size = 20`.

## Bygga VagnFast

```bash
cd native
godot --headless --dump-extension-api          # extension_api.json (git-ignorerad), efter Godot-uppdatering
.venv/bin/scons platform=linux   target=template_debug   custom_api_file=extension_api.json -j12   # editorn
.venv/bin/scons platform=linux   target=template_release custom_api_file=extension_api.json -j12   # export
.venv/bin/scons platform=windows target=template_release custom_api_file=extension_api.json -j12   # mingw-w64
.venv/bin/scons platform=windows target=template_debug   custom_api_file=extension_api.json -j12
```

**Windows 11 och osignerade DLL:er (20 nov):** på grabbens dator stoppade Smart App Control
`libvagnfast.windows.template_release.x86_64.dll` med felet "Felaktig minnesavbildning … 0xc0e90002".
DLL:en är giltig, men den är osignerad och ny, så Windows har inget rykte att gå på. Godot och
Terrain3D släpps igenom. Beslut: spelarna får avblockera zippen före uppackning.
`WINDOWS_AVBLOCKERA.txt` följer med i Windows-zippen (`EXPORTERA.md`). Saknas DLL:en går spelet
ändå, med GDScript-versionerna (kontrollerat: ett exporterat bygge utan biblioteket startar och
skriver bara tre felrader). Signering med kodsigneringscertifikat kostar flera tusen kronor per år
och är inte aktuellt. Den inlämnade versionen byggs från `undergangar`, som saknar DLL:en.

Biblioteken hamnar i `bin/`, som är git-ignorerad. En ny klon kör GDScript-versionerna tills någon
bygger. Första bygget tar cirka 1,5 minuter, mest godot-cpp, och därefter sekunder.
