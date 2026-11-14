# Testlista inför släppet

Spela från huvudmenyn i det **exporterade bygget** när det går (inte F6 i editorn: då saknas lobbyn).
Skriv buggar under "Hittat" längst ned med karta, läge, vad som hände och om det går att upprepa.
F3 visar FPS. Notera FPS i en strid, så ser vi om någon karta sticker ut.

Bocka i en ruta när den är testad och fungerar. Om något är fel, skriv det under "Hittat" och lämna rutan tom.

---

## A. Varje match (gäller alla scenarier)

Kör igenom de här i början av varje match. Det tar ett par minuter.

- [ ] Kartan laddar, lobbyn visar briefing, man kan välja lag och vagn och deploya
- [ ] Vagnen står på marken vid start (inte i marken, inte i luften, inte i ett hus)
- [ ] Minikartan och den stora kartan (M) visar rätt bild, egen vagn och zon/rutt
- [ ] Lucka (H), kikare (B), skyttens sikte, T lägger tornet på blicken
- [ ] Spotta en fiende med musknapp 1 i kommendörsvyn: markering på kartan
- [ ] Skjut AP och HE (byta ammunition), MG (mus 2) med luckan öppen och stängd, rök (X)
- [ ] Truppen: Q-kartan sitter av, G kallar tillbaka, F närskydd, V ledarens ögon, mina (högerklick)
- [ ] Bli utslagen: killcam spelas, bildrutan med träffarna, sedan kamera på en lagkamrat, respawn
- [ ] Esc-menyn: byt vagn, inställningar, tillbaka till matchen
- [ ] Tab visar poängtavlan
- [ ] Matchen tar slut på riktigt: resultat, Play again och Main menu fungerar
- [ ] Bottarna kör iväg, slåss och fastnar inte i klump (titta på kartan efter några minuter)
- [ ] Inga konstiga ljud (fastnade loopar, ljud som saknas, röster som inte stämmer med det som händer)
- [ ] FPS i strid: ____

## B. Per läge

### King of the Hill
- [ ] Zonen öppnar, krymper och stänger; nästa plats syns på kartan i pausen
- [ ] Poängen räknas för egna vagnar i zonen; majoriteten får multiplikatorn
- [ ] Spawnerna flyttas med zonen och hamnar inte nära fienden
- [ ] Mode-radion: zonen öppnar, fler/färre av våra i zonen, nära vinst

### Thunder Road
- [ ] Rond 1: anfallare tar checkpoints genom att vara fler i zonen; "ZONE CAPTURED/LOST"
- [ ] Reträtten: försvarare som lämnas kvar får "LEFT BEHIND", markeras och slås ut efter 40 s
- [ ] Att lämna korridoren: varning, markering, utslagen efter 30 s
- [ ] Vågorna kommer, liv räknas ned; övertid när tiden tar slut med anfallare i zonen
- [ ] Rondpausen: poängtavlan, nedräkning, vagnarna står låsta; kartan återställs (vrak, minor, träd)
- [ ] Rond 2 byter sida; till sist VICTORY/DEFEAT och slutlig poängtavla
- [ ] Ledningsradion: tagen/förlorad, "Fall tillbaka till ÅSA n" med rätt nummer

### Free fight
- [ ] Startplats på öppen mark; vågen syns som cirkel och väntar tills den upptäcker en
- [ ] Våg slagen: ny våg efter pausen, utslagna spelare kommer tillbaka bredvid en lagkamrat
- [ ] Bot-allierade (huvudmenyn): följer med, slåss, räknas när man själv är ute
- [ ] Alla ute: "DEFEATED" och antal vågor

### Tutorial
- [ ] Knappen i huvudmenyn är markerad första gången och inte efter att man har gått igenom den
- [ ] Alla nio lektioner går att klara utan att veta något i förväg
- [ ] Varje lektions cirkel på kartan stämmer med var man ska
- [ ] Backspace i 3 s hoppar över; att bli utslagen eller välta ger återstart där man stod
- [ ] Instruktörens röst spelas för varje steg och inga repliker krockar
- [ ] Slutkortet visas och man kommer tillbaka till menyn

## C. Scenarier

Minst en hel match per rad. Prova olika vagnar och väder över listan, så att alla fem och alla väder blir testade någon gång.

| ✓ | Scenario | Vagn | Väder | FPS | Anteckning |
|---|---|---|---|---|---|
| [ ] | Tutorial (Vidingsjö) | T-34 | | | |
| [ ] | KotH – Vidingsjö | | | | |
| [ ] | KotH – Linghem | | | | |
| [ ] | KotH – Campus | | | | |
| [ ] | Thunder Road – Vidingsjö Red | | | | |
| [ ] | Thunder Road – Vidingsjö Orange | | | | |
| [ ] | Thunder Road – Linghem | | | | |
| [ ] | Thunder Road – Road to Science | | | | |
| [ ] | Thunder Road – Corson | | | | |
| [ ] | Free fight – Vidingsjö | | | | |
| [ ] | Free fight – Linghem | | | | |
| [ ] | Free fight – Campus | | | | |

Vagnar testade: [ ] BT-7 [ ] T-34 [ ] Pz IV [ ] Sherman [ ] KV-2
Väder testade: [ ] clear [ ] overcast [ ] dawn [ ] dusk [ ] fog [ ] rain

Per karta, håll ögonen på: hus utan kollision, träd/hus mitt på vägen, vatten man fastnar i,
broar och undergångar, kartkanten, att bottarna inte fastnar på samma ställe gång på gång.

## D. Online

- [ ] Värd + klient över Tailscale: anslut, välj lag, deploya
- [ ] KotH: en hel match med två spelare och bottar
- [ ] Thunder Road: båda ronderna, rondbyte och kartåterställning på klienten
- [ ] Free fight: två spelare mot vågorna
- [ ] Klienten ser rätt: träffar, rök, truppen, minor, vrak som skjuts undan, kill feed, radio
- [ ] Byta lag och byta vagn i Esc-menyn
- [ ] En spelare lämnar mitt i: en bot tar platsen och matchen fortsätter
- [ ] Ansluta mitt i en match: vrak och minor finns där
- [ ] Dedikerad server (`--dedicated`): match → resultat → omröstning → ny karta, klienterna följer med

## E. Bygget och första intrycket

- [ ] Windows-zippen packas upp och startar på kompisens dator utan Godot
- [ ] Grafikförvalen Low/Medium/High: FPS på kompisens dator ____ / ____ / ____
- [ ] Inställningarna sparas mellan starter (mus, volym, grafik, namn)
- [ ] Credits-rutan, kontrollrutan (huvudmenyn) och F1 i matchen
- [ ] Tipskortet visas första matchen och sedan inte igen
- [ ] Soldaterna har animationer (`soldier_anims.res` kommer med i bygget)
- [ ] Svenska röster spelas och ingen svensk text syns någonstans
- [ ] Inga felrutor eller röda fel i konsolen (Linux: starta från terminalen och läs utskriften)
- [ ] Avsluta från menyn och med fönstrets kryss: inget som hänger sig

---

## Hittat

| Karta / läge | Vad hände | Går att upprepa? | Fixat |
|---|---|---|---|
| | | | |
