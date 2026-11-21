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

## Provat utan effekt och borttaget

- **Återanvända fjädringsstrålar för stillastående vagnar, i GDScript:** 37 % färre strålar, men
  listorna med svaren kostade lika mycket.
- **Trådbatch av fjädringsstrålar i GDScript:** att samla och dela ut svaren åt upp vinsten.
- **Fysik på egen tråd** (18 nov): skripten fick `null` från fysikvärlden.

## Lärdom

Det dyra är inte matematiken utan att **fråga GDScript-objekten**: `is_enemy_of`,
`get_spot_points`, `is_soldier_exposed` och så vidare, och **motorns strålar**. Båda kostar ungefär
lika mycket från C++ som från GDScript. C++ lönar sig bara när datan också finns i C++.

## Nästa steg, i ordning

1. ~~**Profilera det som inte är fysik i en bildruta i 20 mot 20.**~~ Gjort 21 nov: inget att hämta där.
   Kandidater:
   - `Squad._process` (animationsdetaljer för 160 soldater)
   - HUD och kartor
   - `TankLooks` (hjul, band och strålar mot marken)
   - `GroundCoverField`
   - `TankAudio`

   Gör det med `tools/perf/perf_match.gd` och en fas som stänger av `_process` per klass. En sådan
   finns inte än, bara `_physics_process` (`OFF`), så lägg till den.
2. **Världsbilden i C++.** Varje tick fyller varje vagn och trupp i sitt läge en gång i VagnFast.
   Alla botar och trupper läser sedan därifrån, istället för att fråga 40 vagnar var.
   - Per vagn: id, lag, utslagen, position, de synliga punkterna i världen, vagnchef utsatt och
     hjässans position, hjässans id samt vagnens id.
   - Per soldat: trupp-id, lag, utsatt, siktpunkt, hitbox-id, och kanske växtlighetens
     dold-andel per tittare. Den senare är svårare, eftersom den beror på tittaren.
   - Läsare: `BotController._prefetch_sight` (nu C++, men den frågar GDScript), `_look_at`,
     `_scan_squads` och `Squad._prefetch_sight` / `_scan`.
   - Uppskattning: 3–5 ms per tick i 20 mot 20, inte mätt. Kontrollera identiska svar med samma
     teknik som förut: räkna avvikelser mot den gamla koden under en headless-match.
3. **Därefter** soldaternas steg (`Squad._move_soldiers` med väggkontroller) och vagnens
   småfunktioner (`_sync_turret_shapes`, `_update_turret`, `_update_damage`).

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
