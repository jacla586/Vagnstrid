# Spela mot varandra över nätet

Den ena spelaren är **värd**: hans dator kör hela spelet (fysik, träffar, botar). Den andra
**ansluter** och skickar bara sina kommandon till värden. Det räcker att värden har en
hyfsad uppkoppling; 1 mot 1 drar ungefär 2 kB/s åt varje håll.

## Snabbstart på en dator (test)

1. Starta spelet två gånger (två fönster). Spelet öppnar en startmeny.
2. Fönster 1: välj karta (Vidingsjö är förvalt) och tryck **Host game**.
3. Fönster 2: låt adressen stå på `127.0.0.1` och tryck **Join game**.

## Med en kompis över internet: Tailscale

Tailscale gör att era datorer kan nå varandra som om de stod i samma nätverk, utan att
någon behöver öppna portar i routern.

1. Båda installerar Tailscale (https://tailscale.com/download) och loggar in.
2. Värden bjuder in kompisen till sitt "tailnet". Admin-sidan → Users → Invite, eller dela
   bara sin dator via **Share** på maskinen.
3. Värden tar reda på sin Tailscale-adress. Den börjar med `100.`: kör `tailscale ip -4`
   eller titta i Tailscale-appen.
4. Värden trycker **Host game**. Kompisen skriver in värdens `100.x.y.z`-adress och trycker
   **Join game**.

Spelet använder UDP-port **24680**. Med Tailscale behövs ingen portöppning. Utan
Tailscale måste värden öppna UDP 24680 i routern och ge kompisen sin publika IP-adress.

## I spelet

- Lagen fördelas automatiskt: värden i lag 0, nästa spelare i lag 1, och så vidare.
- Lag 0 startar där spelarens vagn står i kartan, lag 1 vid kartans första fiendevagn.
- **Bots** (kryssruta vid Host) lägger till kartans botar som ett tredje lag mot alla.
- Utslagen vagn kommer tillbaka vid lagets start efter 10 s.
- Spotting (vänsterklick i chefsvyn) syns på minimappen för hela laget.
- **F3** visar nätverksstatistik: roll, ping, kB/s in och ut, snapshots per sekund.

## Kommandorad (för test och skript)

```
godot --path . -- --host --map vidingsjo [--bots] [--name Jacob]
godot --path . -- --join 100.101.102.103 [--name Kompis]
```

## Känt och begränsat (första versionen)

- Hos den som ansluter reagerar torn, kanon och lucka direkt. Skrovet rör sig först när
  värden svarat, alltså cirka 0,1 s plus ping. Säg till om det känns segt.
- Träffar avgörs på värden mot var vagnarna är där. Med hög ping kan skott mot vagnar i
  full fart missa lite.
- Ingen lobby eller lagval än, och inga spellägen. Det är fri strid med respawn.
- Kartan `hills` stöds inte i nätverksläge, men alla geodatakartor gör det (Vidingsjö,
  Vikbolandet/Hackerstad, Campus, Linghem).

## Om något krånglar

- **"connection failed":** kontrollera adressen och att värden har tryckt Host. Med
  Tailscale: syns båda datorerna i Tailscale-appen?
- **"could not host":** något annat använder port 24680, till exempel ett spel som redan är
  igång. Stäng det.
- **"host left":** värden stängde, eller anslutningen bröts. Den som anslutit kommer
  tillbaka till menyn.
