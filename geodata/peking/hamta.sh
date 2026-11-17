#!/usr/bin/env bash
# Hämtar all data till korridorkartan "peking" (Thunder Road genom Norrköping:
# Finspångsvägen -> Norra Promenaden -> Centralen -> Drottninggatan -> Vasaparken).
#
#   cd geodata && bash peking/hamta.sh
#
# Frågar EN gång efter Lantmäteriets systemkonto (höjd, laser och ortofoto) i din egen
# terminal; lösenordet skrivs aldrig i en chatt. Steg som redan är gjorda hoppas över,
# så det går att avbryta och köra igen.
set -euo pipefail
cd "$(dirname "$0")/.."                 # geodata/
PY=.venv/bin/python
START=58.595877,16.157361               # Riksvägen/Finspångsvägen
SLUT=58.583414,16.193777                # Vasaparken

if [[ -z "${LM_USER:-}" ]]; then read -rp "Lantmäteriet systemkonto, användarnamn: " LM_USER; fi
if [[ -z "${LM_PASS:-}" ]]; then read -rsp "Lösenord: " LM_PASS; echo; fi
export LM_USER LM_PASS

echo "=== 1/5 Ruta, OSM, LM höjdmodell + laser, NMD"
$PY scripts/hamta_korridor.py peking "$START" "$SLUT"

echo "=== 2/5 Ortofoto 0,5 m (bygget: markfärg, häckar, takfärger, parkeringar)"
[[ -f peking/data/ortofoto_peking.tif ]] || $PY scripts/hamta_ortofoto.py hamta --omrade peking

echo "=== 3/5 Ortofoto 16 cm (vägbreddsmätningen i analys/)"
[[ -f peking/data/ortofoto_peking_16cm.tif ]] || \
    $PY scripts/hamta_ortofoto.py hamta --omrade peking --upplosning 0.16 --suffix 16cm

echo "=== 4/5 Jordbruksverket (öppet)"
[[ -f peking/data/jordbruk_skiften.geojson ]] || $PY scripts/hamta_jordbruk.py peking

echo "=== 5/5 Mapillary-objekt (gatlyktor, skyltar; nyckeln i mapillary.txt)"
[[ -f peking/data/mapillary_objekt.geojson ]] || $PY scripts/hamta_mapillary.py objekt peking

echo
echo "Klart. Säg till Claude, så tas rutten fram (rutt_ur_bild.py) och kartan byggs."
