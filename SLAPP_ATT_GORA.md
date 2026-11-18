# Inför släppet och SweClockers-tävlingen

Läget 14 november 2026. Inlämning senast **30 november**, bidraget går att ändra till 1 december.
Röstningen 1–13 december. Om bidraget hamnar topp tre ska underlaget in senast **15 december 23.59**.
Regler: `Tävlingsvillkor.txt`, `Tävling1–3.png`. Bidragstexten: `sweclockers_bidrag.md`. (Ingen av dem ligger i git.)

**Funktionsfrys från 14 november:** bara buggfixar och det som behövs för släppet. Nya idéer skrivs
längst ned under "Efter tävlingen".

## Tidsplan

| Datum | Mål |
|---|---|
| 14–20 nov | Speltest enligt [TESTLISTA.md](TESTLISTA.md), buggar fixas löpande |
| 20 nov | Test på kompisens Windows-dator |
| **22 nov** | **Sista dag för klubbarnas svar om orienteringskartorna**, annars ombyggnad utan dem |
| 23–26 nov | Bilder, trailer, bidragstexten |
| 27–28 nov | Slutligt bygge, sista testvarv, tokenräkning |
| 29 nov | Lämna in (en dag i marginal) |

## Klart

- [x] Ny huvudmeny och garage med eget tema (`MenuTheme`) och renderad, efterbehandlad bakgrundsbild
- [x] Google Maps-skärmdumpen bortrensad ur hela git-historiken (pushat 10 nov; säkerhetskopia
      `../stridsvagn-backup-2026-11-10.bundle`)
- [x] Credits: `CREDITS.md` och knappen Credits i huvudmenyn (`data/ui/credits.txt`)
- [x] `README.md`
- [x] ElevenLabs gratisplan utredd: icke-kommersiellt, kräver "elevenlabs.io" i credits (står där)
- [x] Utkast till bidragstexten, fält för fält efter formuläret
- [x] Hjälpskärm (F1) och tipskort första matchen
- [x] Inställningsmeny: mus, volym (allt/effekter/röster), fönsterläge, grafiknivå med förval
- [x] Kartlistan grupperad under **King of the Hill / Thunder Road / Free fight** med läsbara namn
      (Vidingsjö, Road to Science …); Vikbolandet, hills och Hackerstad borttagna
- [x] Tutorial på Vidingsjö: nio lektioner med instruktörsröst, knapp i huvudmenyn (`TUTORIAL_PLAN.md`)
- [x] Dedikerad server med omröstning om nästa karta (`SERVER_PLAN.md`)
- [x] Exportförinställningar och byggen (`EXPORTERA.md`; senaste: `build/*-2026-11-18-11f38d3.zip`, GitHub-release `v2026-11-18`)
- [x] Skärmdumpar, tävlingsmaterial och privata anteckningar hålls utanför git

## Kvar att göra

### Licenser (måste vara klart före släpp)
- [ ] **Orienteringskartorna:** Jacob har mejlat klubbarna (Linghem, Linköping). Stenblock, snår, myrar
      och bäckar i `vidingsjo`, `linghem`, `road_to_science` och `campus` (sprintkartan och
      Lambohovskartan) kommer därifrån. **Sista dag 22 nov.**
      Nej eller inget svar → bygg om de kartorna utan `okarta.py` (se `geodata/CLAUDE.md`), sedan
      import, `bake_tactical_grid`, `render_map_image` och ett testvarv till. Räkna med en kväll.
      Ja → nämn klubbarna i `CREDITS.md` och `data/ui/credits.txt`.
- [ ] Gå igenom `CREDITS.md` mot allt som finns i bygget (ljud, modeller, texturer, röster, Whisper).

### Test (se [TESTLISTA.md](TESTLISTA.md))
- [ ] En hel match i vart och ett av de tolv scenarierna plus tutorialen.
- [ ] Online: två datorer över Tailscale, minst en match KotH och en Thunder Road.
- [ ] Windows-bygget på kompisens dator (prestanda Low/Medium, att allt laddar, röster, soldaternas animationer).
- [ ] Credits-rutan, inställningar och F1 i det exporterade bygget.
- [ ] Spela tutorialen som en ny spelare: förstår man vad man ska göra utan att fråga?

### Bidraget (`sweclockers_bidrag.md`)
- [ ] Läs igenom mot vad spelet är idag: tutorial, Free fight med bot-allierade, reträtt i Thunder Road,
      dedikerad server, inställningar. Stryk det som inte stämmer (t.ex. "Inga flygplan").
- [ ] Bekräfta grafikkortets modell (datorn säger bara "Navi 10": RX 5600 XT/5700/5700 XT).
- [ ] Ta 1–10 bilder (förslagen står i bidraget). Claude kan rendera flera med `render_views`,
      `render_menu_background` och trailerverktygen (`snap=all`).
- [ ] Uppdatera licensstycket när klubbarna har svarat.
- [ ] Räkna om tokens precis före inlämning och spara en skärmdump:
      `python3 tools/count_tokens.py --since 2026-10-16 --until 2026-11-30`
      (10 nov: 4 933 anrop, ≈ 1 378 miljoner tokens, varav ≈ 24 miljoner ny inmatning och svar).
      Lägg till eventuella claude.ai-chattar; de finns inte i Claude Codes loggar.

### Trailer
- [ ] Filma tagningarna med `tools/trailer/record_all.sh` (opening, turret_toss, playground, column,
      ambush, smoke, kv2_plow, advance) på det slutliga bygget.
- [ ] Klipp ihop dem (ffmpeg-skript efter cue-listorna) med musik/ljud som får användas, 60–90 s.
- [ ] Ladda upp till YouTube (olistad eller publik) och länka i bidraget.

### Städning före släpp
- [ ] `CLAUDE.md` säger fortfarande "Not for publication": ändra.
- [ ] Rotmappen: skärmdumpar, `sparadkonversation.txt` och tävlingsfiler får inte följa med i bygget
      (kontrollera exportens filter) eller i ett publikt repo.
- [ ] Slå ihop `miljo` till `main` och tagga släppversionen (t.ex. `v1.0-sweclockers`).

### Teknik på sikt
- [ ] `assets/maps/vidingsjo/vidingsjo_objekt.glb` är ~52 MB och växer vid varje ombyggnad (GitHub
      stoppar vid 100 MB; packen är 1,1 GB). Flytta kartfilerna till Git LFS eller dela upp glb-filen,
      senast innan repot görs publikt. Inte bråttom om repot förblir privat under tävlingen.

### Om bidraget hamnar topp tre
- [ ] Lägg in SweClockers personliga kod i källkoden eller en commit och visa det med skärmdump/länk.
- [ ] Visa att arbetet gjordes efter 16 oktober: git-historiken (start 1 november) och tokenunderlaget.

## Efter tävlingen (parkerat under funktionsfrysen)

- Indirekt eld, svagare Thunder Road-bottar, bredare checkpoint-zon (se minnesanteckningarna)
- Line-ups (tre vagnar inom en budget), lagbefälhavare som byter bot-roller
