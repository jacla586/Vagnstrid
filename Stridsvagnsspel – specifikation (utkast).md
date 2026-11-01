# Stridsvagnsspel – specifikation (utkast)

Nov 1, 2026 · @Jacob

## Vision och USP

Ett semirealistiskt stridsvagnsspel i War Thunder-anda, mot bottar och andra spelare, med få vagnar men mycket känsla. Det är ett hobbyprojekt för skojs skull och ska inte publiceras.

**USP:** du är befälhavare i kupolen. Varje gång du öppnar luckan tar du en risk, och utan markeringar i världen är dina ögon ditt viktigaste vapen. Kombinationen lucka upp/ner, inga markeringar och aktiv spotting är kärnan, och det är den som testas först.

## Verktyg och plattform

Motorn blir Godot 4 med GDScript. Det är gratis, lätt att lära sig, och projektet består av textfiler som en AI-assistent kan läsa och ändra direkt.

- **Motor:** Godot 4, med Terrain3D för terrängen.
- **AI-hjälp:** Claude Code med Pro-abonnemang (ca 20 USD/mån). Uppgradera bara om väntan på kvoten stör.
- **3D-modeller:** Blender för egna modeller och justeringar.
- **Versionshantering:** git, med täta sparpunkter.
- **Arbetssätt:** en avgränsad sak i taget, testa, sedan nästa. Börja ny konversation vid nytt delområde.

## Spelarens roll och vyer

Du är befälhavare och växlar till skyttens sikte när du ska skjuta, som i War Thunder. Du styr alltid körningen själv, och en AI-förare utför det.

- **Kupol, lucka nere:** skyddad, men smal och begränsad sikt genom periskop.
- **Kupol, lucka uppe:** fri 360°-sikt och kikare, men befälhavaren kan träffas av splitter, spränggranater och prickskyttar.
- **Skyttens sikte:** för att rikta och skjuta. Luckans läge följer med, så befälhavaren är fortfarande exponerad om luckan står uppe.
- **"Tornet hit":** en knapp som vrider tornet dit befälhavaren tittar.
- **Skadad befälhavare:** sämre sikt eller ingen kupolvy en stund. Det är inte direkt förlust.

## Klasser och anpassning

Det blir fyra klasser med tydliga roller i stället för många vagnar. Artilleri kan komma senare, eftersom det kräver ett eget system och krockar med kupolkänslan.

| Klass | Styrka | Svaghet | Roll i zonstrid |
| --- | --- | --- | --- |
| Lätt | Snabb, små målytor | Svagt pansar, sämre optik | Spanar, intar zoner snabbare |
| Medel | Allround | Inget som sticker ut | Flexibel, fyller luckor |
| Tung | Starkt pansar, bra eldledning | Långsam | Håller zoner |
| Tankjägare | Kraftig kanon | Svagt pansar, ofta inget torn | Prickskytte från skydd |

**Anpassning:** några få val där varje val är en avvägning.

- Kanon: 2–3 alternativ per klass.
- Ammunitionsmix: pansarbrytande och spräng.
- Tilläggspansar, mot lägre fart.
- Kamouflage, som ger en liten bonus vid spotting.

## Epok, eldledning och optik

Epoken är inte bestämd. Eldledning och optik blir egenskaper per vagn som läggs i datafiler, så att alla nivåer kan testas med samma kod. Spelet ska kräva skicklighet och inte bli "peka och klicka".

| Nivå | Ungefärlig epok | Spelaren gör själv | Passar luckmekaniken |
| --- | --- | --- | --- |
| Ingen eldledning | Andra världskriget | Bedömer avstånd, förhållning och kulans fall. Stannar för att skjuta | Mycket bra: periskopen är dåliga, så lucka upp ger stor fördel |
| Avståndsmätare | Kalla kriget, ca 1950–70 | Ställer in en optisk mätare, har tidig stabilisering | Bra |
| Full dator | Modern tid | Hittar mål och positionerar sig. Datorn sköter träffen | Sämre: termisk sikt minskar behovet av att öppna luckan |

Klasserna kan blanda nivåer, till exempel en lätt vagn med enkel optik och en tung med bättre eldledning.

## Skademodell

Skademodellen ligger mitt emellan: enklare än War Thunder, men inte arkadig. Den kommer att kräva mycket testande.

1. **Genomslag:** ungefär åtta pansarzoner per vagn (front, sida, bak och tak för skrov och torn). Effektiv tjocklek räknas från träffvinkeln. Vid flack träff kan skottet rikoschettera. Sedan jämförs tjockleken med granatens genomslag.
2. **Efter genomslag:** en "skadekon" med några få strålar bakåt från träffpunkten. Det de träffar skadas.
3. **Moduler:** motor, transmission, larvband, kanon, optik, bränsle och ammunitionsförråd. Varje modul är hel, skadad eller förstörd.
4. **Besättning:** 4–5 personer. När någon slås ut tar en annan över rollen, men sämre och långsammare.
5. **Utslågen vagn:** när besättningen är borta, när ammunitionen detonerar eller när en brand inte släcks i tid. Det finns ingen hälsomätare.
6. **Skott som inte går igenom:** spränggranater kan förstöra larvband och optik och skada en exponerad befälhavare.

**För testandet:** alla värden ligger i datafiler, och det finns en testbana med röntgenvy som visar exakt vad varje skott gjorde.

## Kartor och miljö

Kartorna är halvstora, ungefär 2 × 2 km. Strider sker mellan 100 och 1 500 meter, och det ska finnas utrymme att manövrera, gömma sig, spana och prickskjuta.

Varje karta blandar olika terräng:

- **By eller gård:** närstrid och korta avstånd.
- **Skog och dungar:** skydd men dålig sikt.
- **Öppna fält med åsar:** prickskytte från skydd bakom krön.
- **Flod eller dike med få överfarter:** flaskhalsar.
- **2–3 flankvägar**, så att striden inte blir en enda frontlinje.

Första kartan kan vara svensk landsbygd: åkrar, granskog, stenmurar, röda stugor och en kyrka på en kulle.

## Spotting och sikt

Det finns inga markeringar ovanför fiender i 3D-världen. Spotting sker bara på minikartan.

- **Aktiv spotting:** du tittar på fienden, gärna med kikare, och trycker på en knapp. Markeringen syns då på minikartan för hela laget.
- **Senast kända position:** markeringen följer inte efter fienden och bleknar efter 20–30 sekunder.
- **Noggrannhet:** med luckan uppe och kikare blir positionen exakt och du ser vagntypen. Genom periskopet blir det bara "fordon" med ungefärlig position.
- **Besättningen ropar ut** ("Stridsvagn, klockan två!"), lite fördröjt och ibland fel.
- **Synlighet:** buskar och skog döljer. En stillastående vagn är svårare att upptäcka. Körning ger damm och avgasrök. Kamouflage ger en liten bonus.
- **Bottarna följer samma regler** och fuskar inte.

## Spellägen och vinstvillkor

Det blir två lägen, King of the Hill och Conquest, båda med poängsystem i War Thunder-stil. En match tar ungefär 10–15 minuter.

**Gemensamt**

- En zon intas genom att stå i den. Om båda lagen är där är den omstridd.
- Fler vagnar intar snabbare, upp till en gräns. Lätta vagnar intar snabbast.
- Varje lag har en poängpott. Att hålla fler zoner dränerar motståndarens poäng, och utslågna vagnar kostar också poäng.
- Laget som når noll förlorar. Om tiden tar slut vinner laget med flest poäng. Att slå ut alla fiender ger alltid vinst.

**King of the Hill:** en zon med skydd inuti (byggnader, murar, terrängveck) och flera vägar dit, så att man inte kan vinna enbart på långt håll. Zonen kan flytta sig ett par gånger per match.

**Conquest:** tre zoner, A, B och C, i olika terräng: by, skog och öppet fält. Då måste laget fördela sig och använda olika klasser.

## Uppställning och liv

Inför matchen väljer du tre vagnar. När alla tre är förstörda är du ute.

- **Poängbudget:** tunga vagnar kostar mer, så man kan till exempel inte ta tre tunga.
- **Du väljer startvagn**, och efter varje förlust väljer du nästa utifrån läget.
- **Framåtflyttad start (idé):** man kan starta närmare striden när laget håller en zon.
- **När du är ute (idé):** du tittar genom en lagkamrats kupol.

## Bottar och multiplayer

Spelet byggs först mot bottar. Multiplayer kommer senare, men koden ska från start byggas så att det går att lägga till.

- **Bottarna** väljer zon, tar sig dit genom skydd, försvarar och anfaller. De följer samma sikt- och spottingregler som spelare.
- **Multiplayer** blir med Godots inbyggda nätverksstöd. Lagstorlek och om tomma platser fylls med bottar är inte bestämt.

## Resurser och regler

Vi använder bara gratis och korrekt licensierade resurser. Modeller ur andra spel, till exempel War Thunder, används inte.

- **Prototyp:** enkla former (lådor och cylindrar) för skrov, torn och kanon.
- **Modeller:** Sketchfab (Creative Commons, ange upphovsperson) och Kenney.nl.
- **Egna justeringar:** Blender.
- Licensen kontrolleras för varje modell innan den läggs in.

## Öppna frågor och nästa steg

Nästa session fortsätter med grafik och ljud, arbetssätt och etapper. Prototypens första mål är att testa luckmekaniken.

- [ ] Grafikstil: stiliserad lågpoly eller så realistiskt som möjligt?
- [ ] Ljud: motor, skott, träffar och besättningens utrop. Var hämtar vi dem?
- [ ] Multiplayer: lagstorlek, och spel över internet eller lokalt nätverk?
- [ ] Epok: väljs efter test av eldledningsnivåerna.
- [ ] Etapper: vad ska fungera i prototypen, version 1 och senare?
- [ ] Prototyp 1: en enkel vagn som kör, torn som roterar, lucka upp/ner och skyttens sikte.
