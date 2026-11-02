# CLAUDE.md

Projektet bygger Godot 4-världar utifrån öppna geodata: Vikbolandet söder om E851 ner till Slätbaken (huvudområde, i `geodata/` själv) och Vidingsjö i Linköping (`vidingsjo/`). Användaren skriver på svenska. Svara på svenska och skriv kommentarer och utskrifter i koden på svenska.

## Fasta konventioner (ändra inte utan att fråga)
- **Koordinatsystem:** all bearbetning sker i SWEREF 99 TM (EPSG:3006).
- **Spelområdets ruta:** minx 586040, miny 6478956, maxx 592614, maxy 6485950 (EPSG:3006). Samma ruta används i `hamta_lm_data.py`, `klipp_nmd.py` och heightmapen. I WGS84 är rutan ungefär 16.4739, 58.4414, 16.5894, 58.5057. Vägar, vatten, hus och träd tas med i hela rutan; polygonen söder om E851 styr bara terrängmeshen i den fulla glb-filen och platshållarhusen.
- **Vidingsjö:** minx 536120, miny 6469620, maxx 539500, maxy 6472670 (EPSG:3006), byggs i rutläge (`--ruta`).
- **Godot-koordinater:** x = E − (x0 + RES/2), z = (y1 − RES/2) − N, y = höjd i meter. Origo är heightmapens NV-hörn. Pixel (kolumn j, rad i) ligger på (j·RES, i·RES). Värdena för x0, y1 och RES står i `work/grid.json` och `out/heightmap_info.json`.
- **Upplösning:** heightmapen har 2 m (RES). Terrängmeshen har 4 m (STEP = 2 i `step3_build.py`).
- **Havsytan** ligger på y = 0.
- **Färger i glTF är linjära.** Färger skrivs i sRGB och konverteras med `srgb2lin`. Det gäller även vertexfärger.
- **Normaler:** byggnadsytor orienteras uttryckligen med `orient()`. Godot har backface culling.

## Struktur
- `scripts/bygg.py` kör hela pipelinen: `step1_region` → `features` → `step2_terrain` → `step3_build` → `step4_trees`.
- Mellanresultat sparas i `work/` som pickle- och npy-filer. Slutresultatet hamnar i `out/`. Med `--projekt <mapp>` används `<mapp>/data`, `<mapp>/work` och `<mapp>/out` (miljövariablerna `GEO_WORK` och `GEO_NAMN` skickas till stegen).
- Indata finns i `data/`: `export.osm`, `dem.tif` (Copernicus), och vid behov `markhojd_vikbolandet_e851.tif`, `objekthojd_vikbolandet_e851.tif`, `laser/` och `nmd/`.
- `step1_region.py <osm> [minx,miny,maxx,maxy]`. Med ruta (inlandskartor) hoppas E851/kust-logiken över och rutan blir spelområde.
- `step2_terrain.py <dem> [copernicus|lm]`. För `lm` görs ingen kanopikorrigering och bara lätt utjämning, och havet tas från höjdmodellen (sammanhängande ytor under 0,52 m, större än 0,2 km²) i stället för OSM-kustlinjen, som klassade land norr om E851 som hav.
- `step3_build.py <ut> [objekthöjd]`. Med objekthöjd: OSM-hus får takfot (p20) och nock (p95) ur band 1, och nya hus hittas med `laserhus.py`; platshållarhusen används bara utan laser. Vägar och hus slås ihop till en mesh per 250 m-ruta, grupp och material (annars tusentals draw calls).
- `takform.py` + `husgeometri.py`: med laser tolkas varje hus tak ur objekthöjden. Fotavtrycket delas i rektanglar (största rektangeln upprepat, ≥ 90 % täckt, max 4), en del med tydligt trappsteg (två nivåer ≥ 0,8 m isär) delas i två, och varje del får den modell som passar bäst med minsta kvadrat: platt, pulpet, sadel (nock längs eller tvärs), valmat eller tält. Lutande modeller måste ha ≤ 70 % av det platta takets fel, pulpet ≤ 80 % av bästa sadel/valmat-felet. Utan laserträffar: den gamla schablonen (`gable_house`/`flat_building`). Husmeshar har UV i meter (för framtida fasadtexturer).
- `laserhus.py`: tak = höjd 2,5–25 m, utjämnad flerekoandel (3×3) under 20 %, minst 25 m², fyllnadsgrad mot omskrivande rektangel ≥ 0,55 och släthet (median |h − 3×3-median| ≤ 0,35 m, skiljer tak från täta kronor).
- `step4_trees.py <objekthöjd> <ut> [nmd-mapp]` → `trees.bin` (färdiga MultiMesh-transformer, 12 float32 per träd, relativt rutans mitt), `trees_info.json` och `trad_{gran,tall,lov}.glb` (höjd 1, kronradie 1).

## Köra och föra in i Godot
- **Ny karta:** `.venv/bin/python scripts/nytt_omrade.py <namn> <lat1,lon1> <lat2,lon2>` gör allt (ruta → OSM via Overpass → LM höjd/laser, annars Copernicus → NMD-klipp → bygg → Godot-import och scen). Stegen hoppar över det som redan finns; `--om STEG` gör om. Områdesmappen `<namn>/` har `omrade.json`. LM-inloggningen skrivs av användaren i egen terminal (eller `LM_USER`/`LM_PASS`), aldrig i chatten.
- `scripts/hamta_lm_data.py` är det enda LM-skriptet: `--ruta`, `--namn`, `--data` (eller `--omrade vidingsjo|vikbolandet_e851`). Laser: bara den minsta rutstorleken som täcker området.
- Copernicus i rutläge använder samma havsregel som LM (låga sammanhängande ytor), annars blir hela rutan land.
- Python-miljö: `.venv/`. Vikbolandet: `.venv/bin/python scripts/bygg.py --dem data/markhojd_vikbolandet_e851.tif --dem-typ lm`.
- Vidingsjö: `.venv/bin/python scripts/bygg.py --projekt vidingsjo --ruta 536120,6469620,539500,6472670 --osm vidingsjo/vidingsjo.osm --dem vidingsjo/data/markhojd_vidingsjo.tif --dem-typ lm --objekt vidingsjo/data/objekthojd_vidingsjo.tif` (NMD klipps med `klipp_nmd.py --ruta ... --ut vidingsjo/data/nmd`).
- `out/<namn>_objekt.glb` är scenen utan terrängrutor. Godot använder den, medan marken kommer från `heightmap.r16` via Terrain3D.
- Havet är ett enda plan på y = 0 med 4 km marginal. Land hålls ≥ 0,25 m.
- Efter ombyggnad, kör från projektroten: `godot --headless --path . --script res://tools/import_geodata_map.gd -- vikbolandet res://geodata/out` (eller `-- vidingsjo res://geodata/vidingsjo/out`) och sedan `godot --headless --path . --import`.
- Förhandsbilder från kontrollerna sparas i `forhandsbilder/` (ignoreras av git).
- Skärmbilder från Godot när skärmen är låst: kör med `--disable-vsync`, annars ger Wayland bara 1 bild/s.

## Datakällor
- **Lantmäteriets STAC:** `https://api.lantmateriet.se/stac-hojd/v1`. Sökningen är öppen. Nedladdning kräver Basic auth med ett systemkonto. Både höjdmodell (COG, `/mhm/`) och laser (LAZ, samlingen Laserdata skog, 10 km-rutor) ligger här.
- **Laserklasser:** 1 = oklassad (vegetation och byggnader), 2 = mark, 9 = vatten, 17 = bro.
- **NMD2023 trädslag:** 10 m, 0–100 = andel, 255 = nodata.

## Att göra (prioritet)
Punkt 1–3 är gjorda (2026-11-02), för både Vikbolandet och Vidingsjö. Träden har kollision, siktblockering och går att fälla i spelet (`tree_field.gd`; stamtjocklek per trädslag i `data/world/field_tree_*.tres`). Kvar: platshållarträden är enkla, prestanda är inte uppmätt på en olåst skärm.

1. ~~**Träd:** lokala maxima i band 1 av `objekthojd_*.tif` (utjämnat, med fönster som beror på höjden). För varje träd ska höjd, kronradie och typ tas fram. Typen avgörs av NMD-trädslag plus flerekoandel (band 2). Spara som kompakt binärfil eller CSV, och skriv ett GDScript som bygger MultiMeshInstance3D per 250 m-ruta med visibility range. Ta också fram enkla low-poly-platshållarträd (gran, tall, löv) som glb.~~
2. ~~**Byggnader från laser:** celler med höjd över 2,5 m och låg flerekoandel (under ~20 %) bildar sammanhängande ytor på minst 25 m². Gör dem till polygoner, förenkla till rektanglar och ge dem höjd från laserdatan. Ersätt platshållarhusen med dessa, men bara på land och utanför vägar.~~
3. ~~**OSM-hus:** sätt verklig höjd på OSM-husen med percentiler av band 1 inom fotavtrycket.~~
4. **Kontroll:** verifiera alltid visuellt, till exempel genom att rendera glb-filen med three.js och Playwright eller ladda den i Godot, och rapportera eventuella brister ärligt.

## Källor som ska stå i credits
OSM (ODbL), Copernicus DEM, Lantmäteriet (CC BY 4.0, bearbetad) och NMD, Naturvårdsverket (CC0).
