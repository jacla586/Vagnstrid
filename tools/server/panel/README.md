# Vagnstrid server panel

A web page on the LAN to watch and run the dedicated server from another machine, and to see how
popular the game was. Python 3 standard library only; nothing to install, works without internet.

- **Live**: map, match clock, players (ping, kick), bots, tick time, memory; load a map, end the
  match, skip the vote, message every player; start / restart / stop the game server (systemd).
- **Popularity** (from `server_log.jsonl`, any time range): unique players, most at once,
  person-minutes, players online over time, person-minutes by hour, leaderboard (players only:
  knock-outs of players and of bots, losses, K/D, assists, hit %, wins, time, favourite tank),
  tanks and maps picked, fun facts (first blood, nemesis, sharpshooter, ricochet king, ...).
- **Logs**: the server's events in words, and its console (journalctl).
- **Settings**: team size, weather, maps in the vote, times. Saved to `server.cfg`, used from the next match.

## Set up on the server machine

    # the game server, writing its log and settings to ~/vagnstrid-server
    cp tools/server/vagnstrid-server.service ~/.config/systemd/user/
    # the panel beside it
    cp tools/server/panel/vagnstrid-panel.service ~/.config/systemd/user/
    # edit WorkingDirectory in both if the game isn't in ~/stridsvagn
    systemctl --user daemon-reload
    systemctl --user enable --now vagnstrid-server vagnstrid-panel
    loginctl enable-linger $USER                  # runs without anyone logged in
    cat ~/vagnstrid-server/panel_token.txt        # the sign-in token

Open the firewall for the LAN (CachyOS uses ufw by default; adjust the network):

    sudo ufw allow from 192.168.0.0/16 to any port 8080 proto tcp     # panel
    sudo ufw allow 24680/udp                                         # the game

Then open `http://<server IP>:8080/` on your own machine and sign in with the token. Give the server
a fixed address (a DHCP reservation in the router). Never forward port 8080 in the router.

## Safety

- The game server's admin socket listens on 127.0.0.1 only; the panel is what faces the LAN.
- The panel answers only private addresses (`--allow` to change) and only with the token
  (cookie after sign-in, or header `X-Token`); POSTs also need `X-Requested-With: panel`.
- `--trust-localhost` lets requests from the machine itself in without the token (an ssh tunnel).

## Without systemd (testing)

    python3 tools/server/panel/panel.py --log-dir <the server's --log-dir> --console-log <its output file>

Tests: `python3 -m unittest discover tools/server/panel/tests`.
