# Plan: dedikerad server

Mål: en server som står och går utan tillsyn. Människor mot människor, bottar fyller ut lagen,
byter bana efter varje match och låter spelarna rösta fritt om nästa. Röster och matcher loggas,
så vi ser vad folk tycker är kul.

## Start

`godot --headless --path . -- --dedicated [--port 24680] [--first <scenario>] [--log-dir <dir>]`
(eller en exporterad server-build). Ingen egen vagn, ingen PlayerRig, ingen grafik.
Ett systemd-skript (`tools/server/vagnstrid-server.service`) startar om servern om den kraschar
och vid omstart av datorn. `SPELA_ONLINE.md` får ett avsnitt om hur man sätter upp den.

## Delar

1. **Serverläget** (`NetSession.dedicated`): värden är ingen spelare. `NetGame` gör ingen egen
   vagn och ingen lobby lokalt; bottar alltid på; lagen fylls till `MatchSettings.team_size`
   (från en serverfil, `data/server/server.tres`: lagstorlek, väder, röstningstid, karttider).
   Lägen som kräver en värdspelare (MatchLobby offline, Esc-menyn) hoppas över.
2. **Byta bana utan att tappa anslutningen** (det saknas i dag): `rpc_change_map(path, weather)`
   till alla klienter, som laddar den nya kartan och gör `rpc_ready` igen; värden river NetGame,
   laddar nästa scen, och gamla `teams`/namn följer med. Klienter som ansluter mitt i en
   kartladdning väntar tills den är klar.
3. **Röstning efter matchen** (`MapVote`, nod i NetGame + `VotePanel` i spelarens HUD): när
   matchen är slut (Scoreboard visas) öppnas en lista med **alla** scenarion (alla lägen och
   kartor, samma lista och namn som huvudmenyn: `MainMenu._scenarios` flyttas till en statisk
   hjälpare), `vote_s` (30 s). Spelaren klickar på en rad (kan ändra sig); antalet röster syns
   per rad. Klienter skickar `rpc_vote(index)`, värden skickar ställningen `rpc_vote_state`.
   Flest röster vinner, **lika: lottning bland de lika**. Inga röster (eller ingen inne): nästa i
   ordningen i listan (servern går runt alla), så den aldrig fastnar på en bana.
4. **Logg** (`ServerLog`, en JSON-rad per händelse i `<log-dir>/server_log.jsonl`, standard
   `user://`): matchstart (scenario, väder, antal människor/bottar), matchslut (längd, vinnare,
   per människa namn/lag/KO/förluster/poäng), varje röstning (alla röster per scenario, vinnaren,
   om det var lottning), anslutningar/avhopp. Ett litet skript `tools/server/vote_stats.py`
   summerar: röster per bana och läge, hur ofta folk stannar en hel match, spelare per timme.
5. **Robusthet:** en match som aldrig tar slut (Free fight utan spelare, KotH utan zoner) byts
   efter `max_match_s`; tom server väntar på bana tills någon ansluter (ingen bottmatch för
   ingen, så datorn vilar); minnet kontrolleras mellan banor (en fri omladdning av scenen).

## Arbetsordning

1. `--dedicated`: servern utan egen spelare, bottar fyller, en match går att spela via Join.
2. Byte av bana med anslutna klienter (det svåraste; testa med två headless-klienter).
3. Röstningen (panel, RPC, lottning, standardordning).
4. Loggen och statistikskriptet.
5. systemd, `max_match_s`, tom-server-läge, dokumentation. Låt den gå ett dygn med bottar och
   en testklient som ansluter och lämnar.

## Öppna frågor

- Ska Bot hunt (spelarna mot vågor, inget motståndarlag) vara med i listan? Den passar inte
  "människor mot människor" men är bra när bara en eller två är inne.
- Lagstorlek på servern: 10 mot 10 som i dina tester, eller mindre för att hålla nere CPU-lasten
  (en server utan grafik orkar fler bottar än din speldator)?
- Var ska den stå: din dator via Tailscale, eller en hyrd server (då behövs en Linux-export)?
