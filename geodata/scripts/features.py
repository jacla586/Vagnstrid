"""OSM -> geometrier i SWEREF 99 TM (EPSG:3006)."""
import json
from pathlib import Path
import os
ROOT = Path(__file__).resolve().parent.parent
WORK = Path(os.environ.get('GEO_WORK', ROOT / 'work'))   # bygg.py --projekt sätter egen work-mapp
WORK.mkdir(exist_ok=True)
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from osmload import load
from pyproj import Transformer
from shapely.geometry import LineString, Polygon, Point
from shapely.ops import linemerge, polygonize, unary_union

LANDCOVER_KEYS = {
    ('landuse', 'forest'): 'forest', ('natural', 'wood'): 'forest',
    ('landuse', 'farmland'): 'farmland', ('landuse', 'meadow'): 'meadow',
    ('landuse', 'grass'): 'meadow', ('landuse', 'residential'): 'residential',
    ('landuse', 'farmyard'): 'farmyard', ('landuse', 'cemetery'): 'residential',
    ('natural', 'wetland'): 'wetland', ('natural', 'bare_rock'): 'rock',
    ('natural', 'scrub'): 'scrub', ('natural', 'beach'): 'beach',
    ('natural', 'water'): 'water',
}

# Järnväg i bruk (jarnvag.py); disused/abandoned/museum/tram tas inte med
RAIL_KINDS = ('rail', 'light_rail', 'narrow_gauge')

def landcover_class(t):
    for (k, v), c in LANDCOVER_KEYS.items():
        if t.get(k) == v:
            return c
    return None

def build(osm_path):
    nodes, ntags, ways, rels = load(osm_path)
    tr = Transformer.from_crs(4326, 3006, always_xy=True)
    P = {k: tr.transform(*v) for k, v in nodes.items()}

    def coords(w):
        return [P[k] for k in w['nds'] if k in P]

    out = dict(buildings=[], roads=[], landcover=[], water=[], waterways=[], points=[], hedges=[],
               rails=[], platforms=[], vagpunkter=[], lekplatser=[], lekredskap=[])
    used_in_rel = set()
    for rid, r in rels.items():
        t = r['tags']
        if t.get('type') != 'multipolygon':
            continue
        outer = [LineString(coords(ways[m[1]])) for m in r['members']
                 if m[0] == 'way' and m[1] in ways and m[2] in ('outer', '') and len(coords(ways[m[1]])) > 1]
        inner = [LineString(coords(ways[m[1]])) for m in r['members']
                 if m[0] == 'way' and m[1] in ways and m[2] == 'inner' and len(coords(ways[m[1]])) > 1]
        try:
            op = unary_union(list(polygonize(linemerge(outer)))) if outer else None
            ip = unary_union(list(polygonize(linemerge(inner)))) if inner else None
        except Exception:
            continue
        if op is None or op.is_empty:
            continue
        g = op.difference(ip) if ip is not None and not ip.is_empty else op
        cls = landcover_class(t)
        if 'building' in t:
            out['buildings'].append((g, t))
        elif cls == 'water':
            out['water'].append((g, t))
        elif cls:
            out['landcover'].append((g, cls))
        for m in r['members']:
            if m[0] == 'way' and not ways.get(m[1], {}).get('tags'):
                used_in_rel.add(m[1])

    # <projekt>/broar_bort.json: OSM-vägar (id) som inte ska bli broar, t.ex. långa spänger
    # mitt i skogen som stänger vägen för vagnarna. Vägen blir kvar som vanlig väg på marken.
    bort = WORK.parent / 'broar_bort.json'
    if bort.exists():
        for wid in json.loads(bort.read_text()):
            ways.get(wid, ways.get(str(wid), {})).get('tags', {}).pop('bridge', None)
    # <projekt>/broar_justera.json: {"<OSM-väg-id>": {"utan_pelare": true, "extra_fri_hojd": 1.0}}
    # Bron får inga pelare, och marken under den sänks så mycket mer än vanligt (broar.py).
    justera = WORK.parent / 'broar_justera.json'
    if justera.exists():
        for wid, val in json.loads(justera.read_text()).items():
            t = ways.get(wid, ways.get(int(wid) if wid.isdigit() else wid, {})).get('tags')
            if t is None:
                print(f'broar_justera.json: ingen väg {wid}')
                continue
            if val.get('utan_pelare'):
                t['_utan_pelare'] = 'yes'
            if val.get('extra_fri_hojd'):
                t['_extra_fri_hojd'] = str(float(val['extra_fri_hojd']))

    for wid, w in ways.items():
        t = w['tags']
        c = coords(w)
        if len(c) < 2:
            continue
        closed = w['nds'][0] == w['nds'][-1] and len(c) >= 4
        if 'building' in t and closed:
            out['buildings'].append((Polygon(c).buffer(0), t))
        elif 'highway' in t and t['highway'] not in ('proposed', 'construction', 'platform'):
            out['roads'].append((LineString(c), t))
        elif t.get('railway') in RAIL_KINDS:
            out['rails'].append((LineString(c), t))
        elif t.get('railway') == 'platform' or t.get('public_transport') == 'platform' and t.get('train') == 'yes':
            out['platforms'].append((Polygon(c).buffer(0) if closed else LineString(c), t))
        elif t.get('leisure') == 'playground' and closed:
            out['lekplatser'].append((Polygon(c).buffer(0), t, wid))   # lekplatser.py
        elif t.get('public_transport') == 'platform' and t.get('shelter') == 'yes':
            out['vagpunkter'].append((LineString(c).centroid, {'highway': 'vaderskydd'}))   # vagkant.py
        elif 'waterway' in t:
            out['waterways'].append((LineString(c), t))
        elif t.get('barrier') == 'hedge':
            out['hedges'].append(LineString(c))
        elif closed and landcover_class(t):
            cls = landcover_class(t)
            g = Polygon(c).buffer(0)
            (out['water'] if cls == 'water' else out['landcover']).append((g, t if cls == 'water' else cls))
    for nid, t in ntags.items():
        if 'name' in t and ('place' in t or 'historic' in t):
            out['points'].append((Point(P[nid]), t))
        # vägkanten (vagkant.py): hållplatser, väjnings- och stopplikt, gatlyktor
        if t.get('highway') in ('bus_stop', 'give_way', 'stop', 'street_lamp') and nid in P:
            out['vagpunkter'].append((Point(P[nid]), t))
        elif 'playground' in t and nid in P:
            out['lekredskap'].append((Point(P[nid]), t))   # lekplatser.py: redskap ur OSM
        elif t.get('amenity') == 'shelter' and t.get('shelter_type') == 'public_transport' and nid in P:
            out['vagpunkter'].append((Point(P[nid]), {'highway': 'vaderskydd'}))
    return out
