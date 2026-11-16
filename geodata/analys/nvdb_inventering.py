"""NVDB-inventering för en karta (analys, inte en del av bygget).

  geodata/.venv/bin/python geodata/analys/nvdb_inventering.py <karta>

Listar varje lager i länsfilen som har objekt inom kartans ruta: antal objekt och, för sträckobjekt,
hur stor del av vägnätets längd (Net_VAG_Link inom rutan) lagret täcker, samt de vanligaste värdena i
de första egenskapskolumnerna. Markerar lager som pipelinen redan läser (nvdb.LAGER).
Skriver också analys/ut/<karta>_nvdb.txt.
"""
import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path

import shapely
from shapely.geometry import box

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))
import nvdb   # noqa: E402  (bara konstanter och _wkb, inget byggs)

SKIP_KOL = {'geom', 'id', 'fid', 'ELEMENT_ID', 'VALID_FROM', 'VALID_TO', 'START_MEASURE', 'END_MEASURE',
            'EXTENT_LENGTH', 'MEASURE', 'DIRECTION', 'SIDE', 'ROLE'}


def ruta_for(karta):
    g = json.load(open(ROOT / karta / 'work' / 'grid.json'))
    x0, y1 = g['x0'], g['y1']
    return x0, y1 - g['H'] * g['RES'], x0 + g['W'] * g['RES'], y1


def langd_inom(con, tabell, ruta):
    """(antal, total längd inom rutan, rader) för lagrets objekt i rutan."""
    rt = f'rtree_{tabell}_geom'
    try:
        rader = con.execute(f'select t.* from "{tabell}" t join "{rt}" r on t.id = r.id '
                            f'where r.maxx >= ? and r.minx <= ? and r.maxy >= ? and r.miny <= ?',
                            (ruta[0], ruta[2], ruta[1], ruta[3])).fetchall()
    except sqlite3.OperationalError:
        return 0, 0.0, [], []
    kol = [d[1] for d in con.execute(f'pragma table_info("{tabell}")')]
    gi = kol.index('geom') if 'geom' in kol else None
    rb = box(*ruta)
    L = 0.0
    behall = []
    for rad in rader:
        if gi is None or rad[gi] is None:
            continue
        try:
            g = shapely.from_wkb(nvdb._wkb(rad[gi]))
        except Exception:
            continue
        g = g.intersection(rb)
        if g.is_empty:
            continue
        L += g.length
        behall.append(rad)
    return len(behall), L, behall, kol


def main():
    karta = sys.argv[1] if len(sys.argv) > 1 else 'vidingsjo'
    ruta = ruta_for(karta)
    con = sqlite3.connect(f'file:{nvdb.NVDB_FIL}?mode=ro', uri=True)
    tabeller = [r[0] for r in con.execute('select table_name from gpkg_contents')]
    _, natet, _, _ = langd_inom(con, 'Net_VAG_Link', ruta)
    rader_ut = [f'NVDB-inventering {karta}: vägnätet (Net_VAG_Link) {natet / 1000:.1f} km inom rutan', '']
    rader_ut.append(f'{"lager":46} {"obj":>5} {"km":>6} {"täcker":>6}  vanligaste värden')
    for t in sorted(tabeller):
        if t.startswith('Net_'):
            continue
        n, L, rader, kol = langd_inom(con, t, ruta)
        if not n:
            continue
        egen = [i for i, k in enumerate(kol) if k not in SKIP_KOL][:3]
        vanliga = []
        for i in egen:
            c = Counter(str(r[i]) for r in rader if r[i] not in (None, ''))
            if c:
                topp = ', '.join(f'{v} ({m})' for v, m in c.most_common(3))
                vanliga.append(f'{kol[i]}: {topp}')
        andel = f'{100 * L / natet:5.0f}%' if natet and L > 0 else '     -'
        flagga = '*' if t in nvdb.LAGER else ' '
        rader_ut.append(f'{flagga}{t:45} {n:5} {L / 1000:6.1f} {andel}  ' + ' | '.join(vanliga))
    rader_ut += ['', '* = läses redan av pipelinen (nvdb.LAGER)']
    con.close()
    text = '\n'.join(rader_ut)
    print(text)
    ut = ROOT / 'analys' / 'ut'
    ut.mkdir(parents=True, exist_ok=True)
    (ut / f'{karta}_nvdb.txt').write_text(text + '\n')


if __name__ == '__main__':
    main()
