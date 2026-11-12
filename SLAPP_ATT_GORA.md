# Inför släppet och SweClockers-tävlingen

Läget 11 november 2026. Inlämning senast **30 november**, bidraget går att ändra till 1 december.
Röstningen 1–13 december. Om bidraget hamnar topp tre ska underlaget in senast **15 december 23.59**.
Regler: `Tävlingsvillkor.txt`, `Tävling1–3.png` (inte i git). Bidragstexten: `sweclockers_bidrag.md`.

## Klart

- [x] Ny huvudmeny och garage med eget tema (`MenuTheme`) och renderad, efterbehandlad bakgrundsbild
- [x] Google Maps-skärmdumpen bortrensad ur hela git-historiken (pushat 10 nov; säkerhetskopia
      `../stridsvagn-backup-2026-11-10.bundle`)
- [x] Credits: `CREDITS.md` och knappen Credits i huvudmenyn (`data/ui/credits.txt`)
- [x] `README.md`
- [x] ElevenLabs gratisplan utredd: icke-kommersiellt, kräver "elevenlabs.io" i credits (står där)
- [x] Utkast till bidragstexten, fält för fält efter formuläret

## Kvar att göra

### Licenser (måste vara klart före släpp)
- [ ] **Orienteringskartorna:** Jacob har mejlat klubbarna (Linghem, Linköping). Stenblock, snår, myrar
      och bäckar i `vidingsjo`, `linghem`, `road_to_science` och `campus` (Campus: sprintkartan och Lambohovskartan, nya 11 nov) kommer därifrån.
      Nej eller inget svar → bygg om de kartorna utan `okarta.py` (se `geodata/CLAUDE.md`).
      Ja → nämn klubbarna i `CREDITS.md` och `data/ui/credits.txt`.

### Kartlistan i huvudmenyn (Jacob sover på saken)
- [ ] Bestäm vilka kartor/scenarier som ska bort och vilken som ska justeras.
- [ ] Gruppera listan under rubriker: **Thunder Road**, **King of the Hill**, **Test drive / Bot hunt**,
      med läsbara namn i stället för filnamn.

### Nya spelare och juryn
- [ ] **Hjälpskärm** med kontroller (F1) och en kort text första gången om luckan uppe/nere.
- [ ] **Tutorial-karta** som lär ut kupolen, siktet och truppen (byggs senare).
- [ ] **Inställningsmeny:** musens känslighet, volym, helskärm, grafiknivå (gräs, skuggor, siktavstånd).

### Test
- [ ] Exportera Windows-bygget och spela med kompisen på hans dator (prestanda, nätverk, att allt laddar).
- [ ] En hel match per läge och karta; skriv ned allt som går sönder.
- [ ] Kontrollera att Credits-rutan fungerar i det exporterade bygget.

### Bidraget (`sweclockers_bidrag.md`)
- [ ] Bekräfta grafikkortets modell (datorn säger bara "Navi 10": RX 5600 XT/5700/5700 XT).
- [ ] Räkna om tokens precis före inlämning och spara en skärmdump:
      `python3 tools/count_tokens.py --since 2026-10-16 --until 2026-11-30`
      (10 nov: 4 933 anrop, ≈ 1 378 miljoner tokens, varav ≈ 24 miljoner ny inmatning och svar).
      Lägg till eventuella claude.ai-chattar; de finns inte i Claude Codes loggar.
- [ ] Ta 1–10 bilder (förslagen står i bidraget). Claude kan rendera flera av dem med verktygen.
- [ ] Uppdatera licensstycket när klubbarna har svarat.
- [ ] Läs igenom tonen och strykningarna (t.ex. "Inga flygplan").

### Trailer
- [ ] Regisserad trailer till YouTube (inte påbörjad).

### Teknik på sikt
- [ ] `assets/maps/vidingsjo/vidingsjo_objekt.glb` är ~52 MB och växer vid varje ombyggnad (GitHub
      stoppar vid 100 MB). Flytta kartfilerna till Git LFS eller dela upp glb-filen, senast innan
      repot görs publikt.

### Om bidraget hamnar topp tre
- [ ] Lägg in SweClockers personliga kod i källkoden eller en commit och visa det med skärmdump/länk.
- [ ] Visa att arbetet gjordes efter 16 oktober: git-historiken (start 1 november) och tokenunderlaget.
