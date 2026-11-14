# Plan: tutorial-karta

Mål: en ny spelare (och juryn) förstår spelets kärna, alltså vagnchefen i kupolen, på 5–8 minuter,
utan att läsa något först. All text på engelska; svenska instruktörsröster är en bonus, som övriga röster.

## Upplägg

- **Scenario** `scenes/scenarios/vidingsjo_tutorial.tscn` (ärver `vidingsjo.tscn`, så kartan följer med).
  Ett lugnt hörn med öppen åker, en skogsridå och en buske att gömma ett mål i. Bara offline.
- **Huvudmenyn:** en egen grupp "Tutorial" överst (`MainMenu.GROUP_TAGS` + `_tutorial`).
  Första gången spelet startas föreslår menyn tutorialen (en rad med en knapp, inget tvång).
- **Läget** `TutorialMode` (nod i scenariot) kör en lista med steg ur data: `TutorialData` med
  `TutorialStepData` (text, mål, parametrar, markör på kartan, ev. röstklipp). Inga regler i koden.
- **HUD** `TutorialPanel`: instruktion överst med tangenter via `ControlsPanel.expand` ("Press {toggle_hatch}…"),
  en bock när steget är klart, "Step 3 of 9", och en tangent för att hoppa över ett steg.

## Lektionerna (ett steg = ett mål som spelet kan kontrollera)

1. **Kör:** kör till markören (WASD). Mål: inom 15 m.
2. **Luckan:** öppna luckan, se dig om, stäng den. Visa skillnaden: periskop jämfört med fri sikt.
   Mål: luckan öppen, sedan stängd. Kort text: "Open = see everything, but shrapnel and rifles can hit you."
3. **Kikaren:** hitta en vagn vid skogskanten med kikaren. Mål: kikaren använd medan målet är i bild.
4. **Spotta:** markera målet (vänsterklick i kommendantvyn). Mål: `Tank.spotted` på målet; peka på kartan.
5. **Skyttens sikte:** byt till siktet, lägg tornet mot målet och skjut. Målet står still på ~400 m.
   Mål: en träff. Tips om avståndsskalan om första skottet går under.
6. **Ammunition:** AP mot pansar och HE mot band och trupp. En vagn som bara går att stoppa med HE mot
   bandet (eller en trupp i det fria). Mål: målet stoppat eller utslaget.
7. **Truppen:** öppna truppkartan (Q), skicka truppen till en markerad dunge, lägg en mina på en väg,
   kalla hem dem (G). Mål: truppen framme, mina lagd, truppen uppsuttet.
8. **Rök och reträtt:** en fiende börjar skjuta; lägg rök (X) och backa bakom krönet. Mål: rök avfyrad och
   vagnen utom fiendens sikt.
9. **Gesällprov:** två lätta bottar (`bot_easy`), truppen tillgänglig. Vinst = båda utslagna.
   Slut: "TRAINING COMPLETE" och knappar till Bot hunt och huvudmenyn.

## Byggstenar som redan finns

- Mål: `TargetTankController` (står still eller kör en slinga), måltavlorna från prototyp 1.
- Signaler: `Tank.spotted`, `Tank.struck`/`eliminated`, `Squad.radio` (framme, mina armerad), luckans läge,
  `PlayerViews`-läget (sikte, kikare).
- Text och tangenter: `ControlsPanel.expand`, `MenuTheme`, flashstilen från `ThunderPanel._flash`.
- Röster: `SquadRadio.command_call` för instruktörsklipp (svenska), med den engelska texten på skärmen.

## Arbetsordning (ungefär en kväll per punkt)

1. `TutorialData`/`TutorialStepData`, `TutorialMode` med steg 1–2 och `TutorialPanel`, scenariot, menygruppen.
2. Steg 3–6 (kikare, spotta, siktet, ammunition) med mål och placering.
3. Steg 7–8 (trupp, rök och reträtt).
4. Gesällprovet, slutskärmen, förslaget i huvudmenyn första gången.
5. Finslipning: texter, markörer, timing, eventuella röstklipp. Testa med någon som aldrig spelat.

## Beslut (2026-11-14)

- Karta: Vidingsjö.
- Instruktörsröst: ja, ElevenLabs (filer `ElevenLabs_tut-<steg>-….mp3` i `geodata/sound/`), engelsk text på skärmen.
- Varje steg kan hoppas över genom att hålla Backspace (`skip_tutorial_step`) i 3 s, med en ring som fylls
  ("HOLD TO SKIP"), så det aldrig sker av misstag.
- Instruktörens repliker är inspelade (2026-11-14): `assets/audio/radio/tut_*.ogg` (`make_elevenlabs.sh … thunder`),
  bl.a. tut_0_welcome, tut_<steg>_<vad>, tut_5_short (skottet kort), tut_skip, tut_restart (fast/vält).
- Byggd 2026-11-14 (alla nio lektioner, hoppa över, slutskärm, menyknapp). Avvikelser från planen: ingen egen
  karta-markering för dungen (vilken plats som helst godkänns), starten flyttad till (910, 1510) för siktens skull.
