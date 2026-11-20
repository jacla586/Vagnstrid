# Exportera spelet till kompisar

Så här gör du en färdig version av spelet (en `.exe` för Windows, ett program för Linux)
som kompisarna kan starta utan Godot. Hur ni sedan spelar ihop över nätet står i
[SPELA_ONLINE.md](SPELA_ONLINE.md): skicka med den filen.

Kort version: installera exportmallar en gång → (förinställningarna finns redan) →
exportera → zippa mappen → dela zippen → alla spelar på **samma** version.

---

## 1. Installera exportmallar (en gång)

Godot behöver "export templates" för exakt den version du kör (**4.7.2-stable**).

1. Öppna projektet i Godot.
2. **Editor → Manage Export Templates… → Download and Install.**
3. Vänta tills den visar 4.7.2.stable som installerad.

(Om nedladdningen strular: hämta `Godot_v4.7.2-stable_export_templates.tpz` från
godotengine.org/download/archive och välj **Install from File** i samma fönster.)

## 2. Exportförinställningar (redan gjorda)

`export_presets.cfg` i projektroten har redan förinställningarna nedan. Du behöver bara
läsa det här avsnittet om du vill ändra något eller om filen försvunnit. Godot fyller i
övriga inställningar med standardvärden första gången du öppnar **Project → Export…**.

För att göra om dem: **Project → Export… → Add…** och lägg till:

- **Windows Desktop** (de flesta kompisar)
- **Linux** (för dig själv eller kompisar på Linux)

För varje förinställning:

| Inställning | Värde |
|---|---|
| Export Path | `build/windows/Vagnstrid.exe` resp. `build/linux/Vagnstrid.x86_64` |
| Runnable | på |
| Embed PCK | av (spelet är stort, låt `.pck` ligga bredvid) |
| Architecture | `x86_64` |
| Resources → Export Mode | Export all resources in the project |
| Resources → Filters to include | `*.bin` (trädens och buskarnas data, annars saknas all vegetation) |
| Resources → Filters to exclude | `renders/*, build/*, tools/*` |

`geodata/` har en `.gdignore` och följer aldrig med, så rådata, laser och
orienteringskartor stannar hemma.

Tryck **Close**. Godot sparar inställningarna i `export_presets.cfg` i projektroten. Den
filen kan committas, så slipper du göra om steg 2.

## 3. Exportera

**C++-biblioteket VagnFast** (grenen `prestanda-cpp`) ska byggas för båda plattformarna före
exporten, annars kör spelet de långsammare GDScript-versionerna. Godot lägger `.so`/`.dll` bredvid
programmet av sig själv:

```bash
cd native
.venv/bin/scons platform=linux   target=template_release custom_api_file=extension_api.json -j12
.venv/bin/scons platform=windows target=template_release custom_api_file=extension_api.json -j12
cd ..
```

I editorn: **Project → Export… → välj förinställning → Export Project…** och bocka **ur**
"Export With Debug".

Eller från terminalen (projektroten):

```bash
godot --headless --path . --export-release "Windows Desktop" build/windows/Vagnstrid.exe
godot --headless --path . --export-release "Linux"           build/linux/Vagnstrid.x86_64
```

Mappen `build/windows/` innehåller då ungefär:

```
Vagnstrid.exe
Vagnstrid.pck                        <- allt spelinnehåll (kartor, modeller, ljud)
libterrain.windows.release.x86_64.dll <- Terrain3D, MÅSTE följa med
```

Terrain3D-biblioteket kopieras automatiskt. Saknas det blir marken tom och vagnarna
faller genom världen.

## 4. Testa innan du skickar

1. Starta `build/linux/Vagnstrid.x86_64` (eller exe-filen i Windows/Wine) två gånger.
2. Fönster 1: **Host game**. Fönster 2: **Join game** med `127.0.0.1`.
3. Kör en stund på Vidingsjö och testa King of the Hill.

Startar spelet men marken saknas: kontrollera att `.dll`/`.so` ligger bredvid programmet.

## 5. Paketera och dela

```bash
cd build
cp ../SPELA_ONLINE.md windows/
mkdir -p windows/CREDITS
cp ../assets/models/soldier/CREDITS.md windows/CREDITS/soldat.md
cp ../assets/audio/CREDITS.md          windows/CREDITS/ljud.md
zip -r Vagnstrid-windows-$(git rev-parse --short HEAD).zip windows/
```

Zippen blir
några hundra MB, så dela den via Google Drive, Dropbox, OneDrive eller liknande, inte som
e-postbilaga.

Sätt gärna datum eller commit i filnamnet (`git rev-parse --short HEAD`). Då är det lätt
att se att alla har samma version.

## 6. Till kompisarna (klistra in i chatten)

> 1. Ladda ner zippen och **packa upp hela mappen** (starta inte exe-filen inifrån zippen).
> 2. Dubbelklicka på `Vagnstrid.exe`.
> 3. Windows SmartScreen säger "Windows skyddade datorn": klicka **Mer info → Kör ändå**
>    (spelet är inte signerat, det är normalt för hobbyspel).
> 4. Brandväggen frågar om nätverksåtkomst: tillåt (privata nätverk räcker med Tailscale).
> 5. Följ SPELA_ONLINE.md: installera Tailscale och anslut till värdens `100.x.y.z`-adress.

## Viktigt att komma ihåg

- **Alla måste ha samma version.** Nätverkspaketen har ingen versionskontroll. Olika
  versioner ger konstiga fel eller avbrutna anslutningar. Gör en ny zip och be alla byta
  efter varje ändring som rör nätet, vagnar eller kartor.
- **Värden behöver bara spelet.** Godot behövs inte hos någon.
- **Sparade inställningar** (vagnval, egna vagnar, lagstorlek) hamnar hos kompisarna i
  `%APPDATA%\Godot\app_userdata\Vagnstrid\` på Windows och i
  `~/.local/share/godot/app_userdata/Vagnstrid/` på Linux.
- **Grafikkort:** Windows använder D3D12. Om spelet kraschar direkt eller visar svart skärm
  kan kompisen prova Vulkan. Skapa en genväg till exe-filen och lägg till
  `--rendering-driver vulkan` sist i "Mål".

## Banor som inte följer med

Exportfiltret (`exclude_filter` i `export_presets.cfg`) lämnar bort Peking (`peking_thunder`),
som är dold i menyn tills den har gjorts om (~115 MB mindre). Ta bort Peking-raderna i filtret
och namnet i `MainMenu.HIDDEN_SCENARIOS` när den ska tillbaka.

## Licenser och credits

Spelet delas bara privat, men vissa tillgångar kräver ändå attribution. Lägg med:

- `assets/models/soldier/CREDITS.md`: soldatmodellen (CC-BY, KolosStudios)
- `assets/audio/CREDITS.md`: ljud
- kartdata: OSM (ODbL), Lantmäteriet (CC BY 4.0), Copernicus DEM och NMD (Naturvårdsverket)

Kopiera dem till exportmappen, till exempel som `build/windows/CREDITS/`.

**Orienteringskartorna:** kartorna Vidingsjö, Linghem och Campus har stenblock, snår och
bäckar som har tolkats ur klubbarnas orienteringskartor. Själva kartbilderna följer inte med
(`geodata/` exporteras inte), men det som tolkats ur dem är inbakat i kartorna. Att visa det
för några kompisar är privat bruk. Lägg inte zippen offentligt (itch.io, öppna länkar och
liknande).

## Felsökning

| Problem | Trolig orsak |
|---|---|
| "No export template found" | Steg 1 är inte gjort, eller mallarna är för en annan Godot-version |
| Marken saknas, vagnar faller | Terrain3D-`.dll`/`.so` saknas bredvid programmet |
| Inga träd eller buskar | `*.bin` saknas i Filters to include, exportera igen (Linux-bygget får samma fel) |
| Spelet startar inte alls i Windows | Zippen är inte uppackad, eller så har SmartScreen eller antivirus blockerat filen |
| Kompisen kan inte ansluta | Se SPELA_ONLINE.md (Tailscale, port 24680, värden måste ha tryckt Host) |
| Ansluter men konstigt beteende | Olika versioner av spelet: skicka ny zip till alla |
