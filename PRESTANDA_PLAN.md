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

1. **Profilera det som inte är fysik i en bildruta i 20 mot 20.** Det är billigt och omätt.
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

Biblioteken hamnar i `bin/`, som är git-ignorerad. En ny klon kör GDScript-versionerna tills någon
bygger. Första bygget tar cirka 1,5 minuter, mest godot-cpp, och därefter sekunder.
