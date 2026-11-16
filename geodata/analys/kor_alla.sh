#!/bin/bash
# Kör alla analysskript för en karta (läser bara; bygger inget, rör inte spelet).
#   geodata/analys/kor_alla.sh [karta]      (standard vidingsjo)
# Utdata i geodata/analys/ut/<karta>_*/ (git-ignorerat). Ortofoto: 16 cm-fotot om det finns
# (ortofoto_<karta>_16cm.tif), annars byggets 0,5 m; utan något hoppas bredd/form/markering/textur över.
set -u
cd "$(dirname "$0")"
PY=../.venv/bin/python
m=${1:-vidingsjo}
echo "== NVDB-inventering";  $PY nvdb_inventering.py $m | tail -n +1 | head -3
echo "== kantsten (laser)";  $PY kantsten_laser.py $m 2>&1 | grep -A4 "^  *kantsten"
if [ -f ../$m/data/ortofoto_$m.tif ] || [ -f ../$m/data/ortofoto_${m}_16cm.tif ]; then
  echo "== bredd (ortofoto)";   $PY vagbredd_orto.py $m 2>&1 | grep -A4 "^  säker"
  echo "== form (ortofoto)";    $PY vagform_orto.py $m 2>&1 | grep -A12 "^plats"
  echo "== markering";          $PY vagmarkering_orto.py $m 2>&1 | grep -A10 "^plats"
  echo "== asfaltstextur";      $PY asfalt_textur.py $m 2>&1 | grep -A12 "^plats"
  echo "== före/efter";         $PY vagkorr_orto.py $m 2>&1 | grep -A14 "^mätta"
else
  echo "(inget ortofoto för $m: bredd, form, markering och textur hoppas över)"
fi
echo "Resultat: $(cd ut && pwd)/${m}_*/"
