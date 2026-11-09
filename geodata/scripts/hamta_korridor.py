#!/usr/bin/env python3
"""
Hämtar all data för en väg-karta (ThunderRoad): rutan runt vägens start och slut plus en
marginal, så att kartan senare kan byggas som en korridor längs vägen.

    .venv/bin/python scripts/hamta_korridor.py <namn> <start lat,lon> <slut lat,lon> [--marginal 600] \
        [--via lat,lon ...]

--via: punkter där vägen svänger ut längre än ändarna (rutan tar med dem plus marginalen).

Exempel:
    .venv/bin/python scripts/hamta_korridor.py road_to_science 58.379302,15.639765 58.393184,15.572067

Gör så här:
  1. räknar ut rutan (start/slut i SWEREF 99 TM, plus marginalen åt alla håll)
  2. länkar in laserrutor som redan finns i andra områden (samma filnamn = samma ruta),
     så att de inte laddas ner igen
  3. kör scripts/nytt_omrade.py med rutans hörn till och med steget nmd
     (OSM, Lantmäteriets höjdmodell + laser, NMD). Bygget görs separat.
Vägens start och slut sparas i <namn>/omrade.json under "rutt".
Lantmäteriets lösenord skrivs i din egen terminal (eller LM_USER / LM_PASS), aldrig i en chatt.
"""
import argparse, json, os, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # geodata/
S = ROOT / 'scripts'


def punkt(text):
    lat, lon = (float(v) for v in text.replace(' ', '').split(','))
    if not (55 <= lat <= 70 and 10 <= lon <= 25):
        sys.exit(f'{text} ligger inte i Sverige. Har du skrivit lat,lon?')
    return lat, lon


def lanka_laser(laser_dir: Path, ruta) -> None:
    """Länkar befintliga 2,5 km-rutor (y..._EEEE_25) som skär rutan från andra områden."""
    minx, miny, maxx, maxy = ruta
    laser_dir.mkdir(parents=True, exist_ok=True)
    for f in sorted(ROOT.glob('*/data/laser/y*_25.copc.laz')):
        if f.parent == laser_dir or (laser_dir / f.name).exists():
            continue
        try:
            n, e = f.name.split('-')[1].split('_')[:2]
            n0, e0 = int(n) * 100, int(e) * 100
        except ValueError:
            continue
        if e0 + 2500 <= minx or e0 >= maxx or n0 + 2500 <= miny or n0 >= maxy:
            continue
        mål = laser_dir / f.name
        try:
            os.link(f, mål)
            print(f'  {f.name}: länkad från {f.parent.parent.parent.name}')
        except OSError:
            mål.symlink_to(f.resolve())
            print(f'  {f.name}: symlänk till {f.parent.parent.parent.name}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('namn')
    ap.add_argument('start', help='lat,lon där vägen börjar')
    ap.add_argument('slut', help='lat,lon där vägen slutar')
    ap.add_argument('--marginal', type=float, default=600.0, help='meter runt vägens ändar (standard 600)')
    ap.add_argument('--utan-laser', action='store_true')
    ap.add_argument('--via', action='append', default=[], help='lat,lon som också ska med i rutan')
    a, resten = ap.parse_known_args()

    from pyproj import Transformer
    till_sweref = Transformer.from_crs(4326, 3006, always_xy=True)
    till_wgs = Transformer.from_crs(3006, 4326, always_xy=True)
    (la1, lo1), (la2, lo2) = punkt(a.start), punkt(a.slut)
    e1, n1 = till_sweref.transform(lo1, la1)
    e2, n2 = till_sweref.transform(lo2, la2)
    m = a.marginal
    via = [till_sweref.transform(lo, la) for la, lo in (punkt(v) for v in a.via)]
    es = [e1, e2] + [v[0] for v in via]
    ns = [n1, n2] + [v[1] for v in via]
    ruta = [round((min(es) - m) / 10) * 10, round((min(ns) - m) / 10) * 10,
            round((max(es) + m) / 10) * 10, round((max(ns) + m) / 10) * 10]
    print(f'Ruta (SWEREF 99 TM): {ruta}   {(ruta[2] - ruta[0]) / 1000:.2f} × {(ruta[3] - ruta[1]) / 1000:.2f} km')
    lo_sw, la_sw = till_wgs.transform(ruta[0], ruta[1])
    lo_ne, la_ne = till_wgs.transform(ruta[2], ruta[3])
    hörn1, hörn2 = f'{la_sw:.7f},{lo_sw:.7f}', f'{la_ne:.7f},{lo_ne:.7f}'

    mapp = ROOT / a.namn
    (mapp / 'data').mkdir(parents=True, exist_ok=True)
    fil = mapp / 'omrade.json'
    o = json.loads(fil.read_text()) if fil.exists() else {}
    o['rutt'] = {'start': [la1, lo1], 'slut': [la2, lo2], 'start_sweref': [round(e1, 1), round(n1, 1)],
                 'slut_sweref': [round(e2, 1), round(n2, 1)], 'marginal_m': m,
                 'via': [list(punkt(v)) for v in a.via]}
    fil.write_text(json.dumps(o, indent=1, ensure_ascii=False))

    if not a.utan_laser:
        print('Laserrutor som redan finns:')
        lanka_laser(mapp / 'data' / 'laser', ruta)

    cmd = [sys.executable, str(S / 'nytt_omrade.py'), a.namn, hörn1, hörn2, '--till', 'nmd', *resten]
    if a.utan_laser:
        cmd.append('--utan-laser')
    print('>', ' '.join(cmd), flush=True)
    rc = subprocess.run(cmd, cwd=ROOT).returncode
    if rc == 0:
        print(f'\nAll data finns i {mapp}/data. Säg till Claude, så byggs korridorkartan.')
    sys.exit(rc)


if __name__ == '__main__':
    main()
