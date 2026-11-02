"""OSM -> geometrier i SWEREF 99 TM (EPSG:3006)."""
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

    out = dict(buildings=[], roads=[], landcover=[], water=[], waterways=[], points=[], hedges=[])
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
    return out
