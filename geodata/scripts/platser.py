"""Ortnamn till ortnamnsskyltarna (vagkant.py): OSM place=* (noder, och ytor/relationer med sin
mittpunkt) inom kartans ruta -> `<projekt>/work/platser.json` ([{namn, typ, E, N, rackvidd}], SWEREF).
En punkt hör till platsen som ligger närmast i förhållande till sin räckvidd (efter typen).

  .venv/bin/python -I scripts/platser.py <projekt> [--osm fil]

<projekt> = mappen med work/grid.json (Vikbolandet: `.`). bygg.py kör det före step3.
"""
import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from pyproj import Transformer

# typ -> räckvidd (m): så långt från punkten räknas man vara "i" platsen. Närmast i förhållande
# till räckvidden vinner, så en stadsdel inne i en förort tar över nära sin punkt.
RACKVIDD = {'city': 3000, 'town': 1800, 'suburb': 1100, 'village': 700, 'quarter': 600,
            'neighbourhood': 550, 'hamlet': 380, 'locality': 320, 'isolated_dwelling': 180, 'farm': 180}


def _osm_for(proj):
    for f in (proj / f'{proj.name}.osm', proj / 'data' / 'export.osm'):
        if f.exists():
            return f
    raise SystemExit(f'hittar ingen osm-fil i {proj}')


def las(osm, grid):
    tr = Transformer.from_crs('EPSG:4326', 'EPSG:3006', always_xy=True)
    rot = ET.parse(osm).getroot()
    noder = {}
    for el in rot.iter('node'):
        noder[el.get('id')] = (float(el.get('lon')), float(el.get('lat')))
    vagar = {}
    for el in rot.iter('way'):
        vagar[el.get('id')] = [nd.get('ref') for nd in el.iter('nd')]
    platser = []
    for el in rot:
        taggar = {t.get('k'): t.get('v') for t in el.iter('tag')}
        typ, namn = taggar.get('place'), taggar.get('name')
        if typ not in RACKVIDD or not namn:
            continue
        if el.tag == 'node':
            pts = [noder[el.get('id')]]
        elif el.tag == 'way':
            pts = [noder[r] for r in vagar.get(el.get('id'), []) if r in noder]
        else:   # relation: medelpunkten av ytterringarnas noder
            pts = []
            for m in el.iter('member'):
                if m.get('type') == 'way' and m.get('role') in ('outer', ''):
                    pts += [noder[r] for r in vagar.get(m.get('ref'), []) if r in noder]
                elif m.get('type') == 'node' and m.get('role') in ('label', 'admin_centre'):
                    pts = [noder[m.get('ref')]] if m.get('ref') in noder else pts
                    break
        if not pts:
            continue
        lon = sum(p[0] for p in pts) / len(pts)
        lat = sum(p[1] for p in pts) / len(pts)
        E, N = tr.transform(lon, lat)
        res = grid['RES']
        x = E - (grid['x0'] + res / 2)
        z = (grid['y1'] - res / 2) - N
        if not (0 <= x <= grid['W'] * res and 0 <= z <= grid['H'] * res):
            continue
        platser.append((namn, typ, E, N, RACKVIDD[typ]))
    # samma namn två gånger (nod + yta): behåll den största typen
    bast = {}
    for p in platser:
        if p[0] not in bast or p[4] > bast[p[0]][4]:
            bast[p[0]] = p
    return sorted(bast.values(), key=lambda p: (-p[4], p[0]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('projekt')
    ap.add_argument('--osm')
    a = ap.parse_args()
    proj = Path(a.projekt).resolve()
    grid = json.loads((proj / 'work' / 'grid.json').read_text())
    osm = Path(a.osm) if a.osm else _osm_for(proj)
    platser = las(osm, grid)
    ut = proj / 'work' / 'platser.json'
    ut.write_text(json.dumps([dict(namn=p[0], typ=p[1], E=round(p[2], 1), N=round(p[3], 1), rackvidd=p[4])
                              for p in platser], ensure_ascii=False, indent=1), encoding='utf-8')
    print(f'platser: {len(platser)} ->', ut)
    for p in platser:
        print(f'  {p[1]:18s} {p[0]}')


if __name__ == '__main__':
    sys.exit(main())
