# Vikbolandet → Godot

Projektet bygger en spelbar 3D-värld av området söder om väg E851 på Vikbolandet (Östergötland), ner till Slätbaken. Som underlag används öppna geodata. Resultatet är en glb-scen, en heightmap och tilläggsdata som går att dra in direkt i Godot 4.

## Ny karta från två GPS-punkter

Det enklaste sättet att göra en ny karta. Ange ett namn och två diagonala hörn (lat,lon, t.ex. från Google Maps):

```bash
.venv/bin/python scripts/nytt_omrade.py hackerstad 58.4785,16.5108 58.4645,16.5368
```

Verktyget räknar ut rutan i SWEREF 99 TM, hämtar OpenStreetMap (Overpass), Lantmäteriets höjdmodell och laser (frågar efter inloggning; skriv lösenordet i din egen terminal), klipper NMD-trädslag ur den lokala rikstäckande filen, bygger och importerar till Godot. Resultatet är `scenes/maps/<namn>.tscn`. Allt för området hamnar i `<namn>/` (`omrade.json`, `data/`, `work/`, `out/`).

- Avbryts det kan du köra samma kommando igen; gjorda steg hoppas över. `--om STEG` gör om ett steg och alla efter.
- Utan inloggning till Lantmäteriet används Copernicus DEM 30 m (öppen) i stället: terräng, vägar, vatten och OSM-hus, men inga laserträd, laserhus eller riktiga hushöjder. `--copernicus` gör det direkt, `--utan-laser` hämtar bara höjdmodellen.
- Håll områden runt några km. Laserrutorna är 2,5 km (cirka 80 MB) eller 10 km (cirka 1 GB).
- En befintlig scen skrivs aldrig över; terräng och objekt uppdateras.

## Snabbstart (Vikbolandet för hand)

```bash
sudo apt install python3-venv
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Lägg in följande filer i `data/`:
- `export.osm`: ett OpenStreetMap-utdrag över området, från overpass-turbo.eu (export som rå OSM-data)
- `dem.tif`: Copernicus DEM GLO-30, rutan N58 E016. Ladda ner den från
  `https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N58_00_E016_00_DEM/Copernicus_DSM_COG_10_N58_00_E016_00_DEM.tif`

Bygg sedan:

```bash
python3 scripts/bygg.py
```

Resultatet hamnar i `out/`.

## Bättre data från Lantmäteriet

Lantmäteriets data kräver ett systemkonto på Geotorget som har beställt **Markhöjdmodell Nedladdning** och **Laserdata Nedladdning, skog**. Båda är gratis.

```bash
python3 scripts/hamta_lm_data.py lista --omrade vikbolandet_e851 --data data   # rutor (ingen inloggning)
python3 scripts/hamta_lm_data.py allt --omrade vikbolandet_e851 --data data    # höjd + laser + bearbetning
python3 scripts/bygg.py --dem data/markhojd_vikbolandet_e851.tif --dem-typ lm
```

`hamta_lm_data.py` frågar efter användarnamn och lösenord, eller läser dem från `LM_USER` och `LM_PASS`. Höjdmodellen hämtas som COG, och skriptet läser bara den del som behövs. Katalogen har laserrutor på både 10 km (1–2 GB) och 2,5 km; skriptet tar bara den minsta storleken som täcker området. Avbryter du nedladdningen fortsätter den där den slutade nästa gång du kör samma kommando.

`bearbeta` gör om laserdatan till `data/objekthojd_vikbolandet_e851.tif`. Den filen har samma rutnät som höjdmodellen och tre band:
1. Höjd över mark i decimeter, från den högsta oklassade punkten (klass 1), alltså träd, hus med mera
2. Andel punkter i cellen som inte är sista ekot, i procent. Högt värde tyder på träd, lågt på tak. 255 betyder att cellen saknar punkter.
3. Antal markpunkter (klass 2)

## Trädslag (Naturvårdsverket NMD2023)

Gå till Naturvårdsverkets sida "Ladda ner Nationella marktäckedata" och välj "Tilläggskikt trädslag". Ladda ner skikten för tall, gran, trivial och ekovradel. Klipp sedan ut området:

```bash
python3 scripts/klipp_nmd.py NMD2023_tradslag_tall_v1_1.tif NMD2023_tradslag_gran_v1_1.tif \
    NMD2023_tradslag_trivial_v1_1.tif NMD2023_tradslag_ekovradel_v1_1.tif
```

De utklippta filerna hamnar i `data/nmd/`. Skikten har 10 m upplösning och värden 0–100, där 255 betyder nodata. Licensen är CC0.

## Utdata (`out/`)

| Fil | Innehåll |
|---|---|
| `vikbolandet_e851.glb` | Terräng (4 m rutnät, vertexfärger efter marktäcke), vägar, byggnader, sjöar och hav |
| `vikbolandet_e851_objekt.glb` | Samma utan terräng (vägar, hus och vatten sammanslagna per 250 m-ruta), används i Godot |
| `trees.bin`, `trees_info.json` | Träd ur laserdatan som färdiga MultiMesh-transformer per 250 m-ruta och trädslag |
| `trad_gran.glb`, `trad_tall.glb`, `trad_lov.glb` | Low-poly-platshållarträd (höjd 1, kronradie 1) |
| `heightmap_16bit.png`, `heightmap.r16` | Heightmap med 2 m upplösning, till exempel för Terrain3D |
| `heightmap_info.json` | Höjdskala, origo, koordinatmappning och källor |
| `landcover_index.png`, `landcover_color.png` | Marktäckeklasser i samma rutnät som heightmapen |
| `roads.json` | Vägarnas mittlinjer med bredd, typ och beläggning, i Godot-koordinater |
| `places.json` | Namngivna platser med position |

**Koordinater:** 1 enhet = 1 m. X är öst, Z är syd, Y är upp. Origo är heightmapens nordvästra hörn, och havsytan ligger på Y = 0.

## Pipeline

| Skript | Gör |
|---|---|
| `step1_region.py` | Tar fram områdespolygonen: E851 som norrgräns och kustlinjen mot Slätbaken från OSM. Sparas i `work/region.pkl` |
| `features.py` | Omvandlar OSM-data till geometrier i SWEREF 99 TM: byggnader, vägar, marktäcke, vatten och platser |
| `step2_terrain.py` | Räknar om höjdmodellen till ett 2 m-rutnät och lägger in hav och mjuka stränder. För Copernicus görs dessutom kanopikorrigering och utjämning |
| `step3_build.py` | Planar marken längs vägar, sänker sjöar och diken, och bygger terräng-, väg-, hus- och vattenmeshar. Exporterar allt till `out/` |
| `step4_trees.py` | Trädtoppar ur objekthöjden (lokala maxima, fönster efter höjd), trädslag lottat efter NMD-andelar, kronradie efter höjd och grannavstånd |
| `laserhus.py` | Hittar tak i objekthöjden och mäter takfot och nock; används av steg 3 |
| `bygg.py` | Kör steg 1–4 i rätt ordning. `--projekt <mapp> --ruta minx,miny,maxx,maxy` bygger ett annat område (t.ex. Vidingsjö) |

## Känt / att göra

- Med laserdata ersätts platshållarhusen av hus ur laserdatan (cirka 500 på Vikbolandet), och OSM-husen får verklig takfots- och nockhöjd. Utan laser används fortfarande påhittade platshållare.
- Träden (cirka 295 000 på Vikbolandet, 76 000 i Vidingsjö) är bara grafik i Godot: ingen kollision och ingen siktblockering ännu.
- Platshållarträden och husen är enkla; husen förenklas till rektanglar med sadeltak eller platt tak.

## Vidingsjö (Linköping)

Ligger i `vidingsjo/` med egna `data/`, `work/` och `out/`. Se `CLAUDE.md` för kommandona.

## Källor och licenser (ange i spelets credits)

- © OpenStreetMap contributors, ODbL
- Copernicus DEM GLO-30: © DLR e.V. 2010–2014 och © Airbus Defence and Space GmbH 2014–2018, tillhandahållen under COPERNICUS av EU och ESA
- Lantmäteriet: Markhöjdmodell Nedladdning och Laserdata Nedladdning, skog. © Lantmäteriet, CC BY 4.0, bearbetad
- NMD, Naturvårdsverket, CC0

## Takformer

Med laserdata får husen sina tak ur laserhöjderna (`scripts/takform.py`, `scripts/husgeometri.py`): platt, pulpet, sadeltak (rätt nockriktning), valmat och tält. L- och T-formade hus delas i delar med var sitt tak, och hus med två höjdnivåer delas vid trappsteget. Kontrollbilder: `forhandsbilder/8_takformer_<karta>.png` (laser till vänster, modell till höger) och `8_tak_godot_*.png`.
