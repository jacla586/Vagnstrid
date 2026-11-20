# Vad som gick fel

Underlag till fältet "Vad gick fel på vägen?" i SweClockers-bidraget (`sweclockers_bidrag.md`, max
4 000 tecken; där står ett urval). Här står felen i detalj: vad som syntes, vad som faktiskt var fel,
hur det hittades och vad som gjordes. Äldre fel (svarta vagnar, frysningar när zonen flyttade, Thunder
Road som aldrig tog slut, osv.) står i bidragstexten och i git-historiken.

## 18 november 2026: inför släppet

Jacob spelade det exporterade Linux-bygget och hittade sakerna i ordning. Claude Code letade, mätte och
rättade.

### Osynliga hus och vägar i King of the Hill på Vidingsjö

- **Syntes:** i det byggda spelet fanns varken hus eller vägar i KotH på Vidingsjö.
- **Första misstanken (fel):** att exporten tappade kartfilerna. Claude listade innehållet i spelets
  paketfil, och allt fanns där: 647 vägbitar och 974 hus, identiska med editorn. Linux- och
  Windows-paketen var byte för byte lika.
- **Verkligt fel:** i scenariot `vidingsjo_koth.tscn` var noden med hela kartans objekt dold
  (`visible = false`), sedan en ändring den 9 november. Troligen ett oavsiktligt klick på "ögat" i
  editorn när zonerna flyttades. Kollisionen fanns kvar, så man kunde krocka med hus man inte såg.
  Bara det scenariot var drabbat, och felet hade lika gärna synts i editorn.
- **Lärdom:** kontrollera antagandet ("exporten är trasig") innan man letar lösningar för det.
  Testet som avgjorde räknade synliga mesher i scenen: 0 av 647.

### Kontrollerna (F1) och tipskortet var tomma i releasen

- Textfilerna `data/ui/controls.txt` och `intro.txt` läses direkt från disk. Exportfiltret tog bara
  med `credits.txt`, så de två fanns inte i spelets paket. Upptäcktes i förbifarten, när paketet
  listades för felet ovan. Nu tas `data/ui/*.txt` med.

### Det fanns ingen avslutaknapp

- Tre veckor in i projektet hade huvudmenyn ingen Quit-knapp. Ingen hade saknat den, eftersom spelet
  alltid startades och stängdes från editorn.

### Bottar som stod bredvid en och inte sköt

- **Syntes:** fienden körde in i zonen, stannade 5–10 m bort och gjorde ingenting. Minst tre vagnar.
- **Hittades** med ett test: en bot och en stillastående måltavla på 8–35 m, framför, bredvid och
  bakom. Huvudkanonen avfyrades i 2 av 9 fall, och bara kulsprutan sköt.
- **Fel:** innan skott kontrollerar botten att kanonen pekar inom en viss vinkel från målet (1° i
  närstrid). Vinkeln mättes från mynningen, men tornet riktas från sin vridpunkt. På långt håll spelar
  det ingen roll, men på 10–20 m skilde det 1–4°, så kontrollen gick aldrig igenom. När målet stod
  nära framför kunde kanonen dessutom inte sänkas tillräckligt (max 8°), fast skottet skulle ha träffat
  skrovet.
- **Rättning:** under 80 m räknas kanonen också som riktad när en stråle längs pipan träffar målvagnen,
  samma bedömning som en spelare gör med siktet. Efter rättningen sköt botten i 12 av 12 testfall.

### Träd som alltid föll rakt fram, och HE som bara fällde ett träd

- Träd som en vagn körde omkull föll exakt i färdriktningen och lade sig över sikten. I skog blev det
  en vägg av stammar. Nu faller de 20–45° åt den sida av skrovet där de träffades.
- "HE fäller bara ett träd" stämde nästan: koden fällde alla träd inom radien, men radien var 3 m för
  en 75 mm-granat. Oftast stod bara ett träd så nära. Radierna är dubblade.

### Prestanda: AI:n mätte fel innan den mätte rätt

Jacob tyckte att FPS:en var låg i 10 mot 10. Claude mätte, och på vägen gick det fel flera gånger:

- **Fel tolkning av ett mätvärde.** Godots "physics process time" visade 17 ms per fysiksteg, varav
  skripten bara stod för 5,5. Claude sökte länge efter en dold kostnad på 12 ms i fysikmotorn: tog
  bort trädkronor ur fysiken, stängde av kontaktrapporter och körde 20 vagnar genom skogen. Allt var
  billigt. Till slut visade det sig att mätvärdet är *det sämsta steget under senaste sekunden*, inte
  ett medelvärde. Den dolda kostnaden fanns inte. Det verkliga problemet var just de sämsta stegen:
  6 % av fysikstegen tog över 16 ms, ungefär två hack i sekunden.
- **Trådar.** Jacob frågade om spelet kör allt i en tråd. Det gör det (skripten). Att lägga fysiken på
  en egen tråd provades och gick inte: skripten frågar fysiken tusentals gånger per steg och fick
  `null` tillbaka. Rendering på egen tråd gav ingen mätbar vinst.
- **Vägplaneringen.** En bots väg över 2 km tog upp till 30–60 ms i ett enda steg. Själva A*-sökningen
  (inbyggd C++) tog under 8 ms. Resten gick åt till en GDScript-funktion som rätar ut vägen efteråt och
  provade *alla* 48 möjliga genvägar från varje punkt, fast den bara behövde den längsta. Nu provas de
  bakifrån, och den inre loopen är förenklad: 2–3 gånger snabbare.
  Den nya koden jämfördes mot den gamla på 600 slumpade vägar på tre kartor. Först skilde sig 3 vägar
  i Peking, eftersom den gamla koden räknade med 32-bitars flyttal och den nya med 64-bitars, så
  avrundningen avgjorde åt olika håll i ett par lägen. Med samma precision blev alla 600 identiska.
  Dessutom får bottarna högst 3 ms planering per fysiksteg tillsammans, så att flera bottar inte
  planerar i samma steg. Det gav ~25 % färre långa steg.
- **Ett träd som välte kostade 8 ms, men testet sa 0,08.** Varje träd som en vagn körde omkull gav ett
  hack. Claude mätte fällningen och fick 0,08 ms, men testet kördes utan grafik. I spelet läste koden
  tillbaka trädets position från grafikkortets minne, och då fick processorn vänta på grafikkortet:
  7–9 ms per träd. Nu finns en kopia av trädens data i vanligt minne, och ett fällt träd kostar 0,09 ms.
- **Testet stördes av spelaren.** Under en mätning såg spelarens egna skott ut att kosta 22–25 ms.
  Det visade sig att Jacob satt och körde i testfönstret medan mätningen pågick. Själva skottet
  kostar 0,15 ms.
- **Kvar:** grafikkortet tar ~10–12 ms per bild på höga inställningar, och en enskild lång vägplanering
  kan fortfarande ge ett hack. Nästa steg är att lägga planeringen på bakgrundstrådar, efter
  tävlingen.

### Striderna hamnade alltid i söder

- King of the Hill på Vidingsjö (3,4 × 3,1 km) slumpade första zonen bland fem handplacerade punkter,
  varav fyra låg i mitten eller söder. Nästa zon hamnar 400–700 m från den förra, så striden kom
  sällan norrut. Nu har Vidingsjö, Linghem och campus nio startpunkter i ett 3×3-mönster. Tre punkter
  hamnade fel (en mitt i en sjö) och flyttades till närmaste lämpliga plats.

### Små saker

- "ThunderRoad" stod ihopskrivet i spelets text. Nu "Thunder Road".
- Claudes egna snedsteg under dagen: ett textutbyte i koden lämnade kvar en halv loop (fångades när
  skriptet kontrollerades), och ett testskript tog bort spelarens vagn men inte dess HUD, så testet
  kraschade.

### Bottarnas minor försvann innan de lades (KotH)

- **Uppgift:** bottarna skulle mina vägarna in mot zonen i King of the Hill, som de redan gör i Thunder Road.
- **Syntes:** första testmatchen gav noll minor på fyra minuter. Bottarna skickade ut trupperna, men
  ingen mina lades.
- **Fel:** botens egen truppstyrning skickar truppen mot striden när den står still. I KotH ligger
  striden alltid vid zonen, så ordern "gå mot striden" kom några sekunder efter minordern och skrev
  över den. I Thunder Road syntes det inte, eftersom försvararna där oftast står långt från striden.
- **Rättning:** en trupp på minuppdrag får jobba klart. Därefter lades 2–5 minor under första zonen,
  nästan alla på vägar 115–195 m från zonens mitt.
- **Samtidigt:** trupperna bär nu två pansarvärnsraketer och två minor, en pryl per soldat. Den som
  stupar tappar sin.

## 20 november 2026: 20 mot 20 och C++

### För mycket GDScript sätter taket för stora strider

- **Syntes:** 10 mot 10 gick att få upp till 60 FPS (19 nov). 20 mot 20 gick i 9–23 FPS. Ett
  fysiksteg tog 22–28 ms, och över 33 ms per bildruta tvingas spelet köra flera fysiksteg per
  bildruta för att hinna ikapp. Då blir det ännu segare: en nedåtspiral.
- **Fel:** nästan all spellogik är skriven i GDScript, och varje bot frågar varje vagn och soldat
  om allt. Med dubbelt så många vagnar blir det fyra gånger så mycket spaning: dubbelt så många som
  tittar och dubbelt så många att titta på. Claude hade uppskattat 35–45 FPS. Det blev 9–23.
- **Hur det hittades:** tidtagning runt varje del av vagnarnas, botarnas och truppernas fysiksteg,
  utslaget per tick. Botarnas spaning tog 7,6 ms, vagnarnas egna skript 5,2 och trupperna 5,1.
- **Vad som provades, och vad det gav:**
  - **Spaning i takt med antalet fiender**, och dyra platssökningar inom en tidsbudget: botarna
    halverades. Det gav störst effekt.
  - **Siktlinjerna på flera kärnor:** Jacob påpekade att trådar avfärdats dagen innan, och ett nytt
    försök visade att det går. Fysiken flyttas inte till en egen tråd, utan huvudtråden delar ut
    färdiga strålfrågor medan fysiken står still. Strålarna blev 4–5 gånger snabbare med identiska
    svar, men de var bara en liten del av kostnaden.
  - **C++ (en GDExtension):** fjädringen blev bara 3 % snabbare i första försöket. Kostnaden låg i
    motorns strålar, inte i GDScript. Med alla vagnars strålar på trådar i C++ blev den 30 %
    snabbare. Bandkrafterna i C++ gav 33 %. Botarnas siktförhämtning gav 20 %, eftersom C++-koden
    ändå måste fråga GDScript-objekten om lag, punkter och lägen, och varje sådan fråga kostar
    ungefär lika mycket därifrån.
  - **Två försök med fjädringen i GDScript** (återanvända strålar, samla dem i en batch) gav ingenting
    och togs bort. Att lagra och läsa svaren kostade lika mycket som de sparade strålarna.
- **Var det står:** 20 mot 20 cirka 18–38 FPS, 15 mot 15 47–52 FPS och 10 mot 10 59–60 FPS.
- **Lärdom:** mät vad tiden faktiskt går till innan något skrivs om: motorns egna anrop, ren
  GDScript-logik eller frågor mellan objekten. För mycket logik i GDScript sätter taket, men C++
  hjälper bara om datan också finns i C++. Nästa steg är en "världsbild" i C++ som varje vagn och
  soldat fyller i en gång per tick och alla botar läser ur (`PRESTANDA_PLAN.md`).
