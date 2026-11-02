"""Steg 1: områdespolygon i SWEREF 99 TM.

    step1_region.py <osm>                      # Vikbolandet: söder om E851 ner till Slätbaken
    step1_region.py <osm> minx,miny,maxx,maxy  # rutläge: hela rutan är spelområde
"""
from pathlib import Path
import os
ROOT = Path(__file__).resolve().parent.parent
WORK = Path(os.environ.get('GEO_WORK', ROOT / 'work'))   # bygg.py --projekt sätter egen work-mapp
WORK.mkdir(exist_ok=True)
import sys, pickle
sys.path.insert(0, str(Path(__file__).resolve().parent))
from osmload import load
from pyproj import Transformer
from shapely.geometry import LineString, Polygon, box, Point
from shapely.ops import linemerge, polygonize, unary_union
import numpy as np

OSM = sys.argv[1]
if len(sys.argv) > 2:
    # Rutläge (inlandskartor): spelområdet är rutan själv, ingen väg- eller kustlogik.
    minx, miny, maxx, maxy = map(float, sys.argv[2].split(','))
    ruta = box(minx, miny, maxx, maxy)
    pickle.dump(dict(road=None, land=ruta, region_land=ruta, region=ruta, poly=ruta, work=ruta, grid_box=ruta),
                open(str(WORK / 'region.pkl'), 'wb'))
    print('rutläge: spelområde', [round(v) for v in ruta.bounds], 'km2', round(ruta.area / 1e6, 2))
    sys.exit(0)
nodes, ntags, ways, rels = load(OSM)
tr = Transformer.from_crs(4326, 3006, always_xy=True)
P = {k: tr.transform(*v) for k, v in nodes.items()}

def line(wid):
    return LineString([P[k] for k in ways[wid]['nds'] if k in P])

# E851 (de två tertiary-delarna)
e851 = [i for i, w in ways.items() if w['tags'].get('ref') == 'E 851']
road = linemerge([line(i) for i in e851])
assert road.geom_type == 'LineString', road.geom_type
c = list(road.coords)
if c[0][0] > c[-1][0]:
    c = c[::-1]           # väst -> öst
west, east = c[0], c[-1]
print('E851 väst', west, 'öst', east, 'längd m', round(road.length))

# Kustlinje -> land/hav-ytor inom en arbetsruta
minx, miny = min(west[0], east[0]) - 1500, min(west[1], east[1]) - 6000
maxx, maxy = max(west[0], east[0]) + 1500, max(west[1], east[1]) + 1500
work = box(minx, miny, maxx, maxy)
coast = [line(i) for i, w in ways.items() if w['tags'].get('natural') == 'coastline']
coast = [g for g in coast if g.intersects(work)]
coast_u = unary_union(coast)
faces = list(polygonize(unary_union([coast_u.intersection(work), work.exterior])))
# OSM: land ligger till vänster om kustlinjens riktning
segs = []
for g in coast:
    cc = np.array(g.coords)
    for a, b in zip(cc[:-1], cc[1:]):
        segs.append((a, b))
segs = np.array(segs)  # (n,2,2)
def is_land(pt):
    p = np.array([pt.x, pt.y])
    a, b = segs[:, 0], segs[:, 1]
    ab = b - a
    t = np.clip(((p - a) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-9), 0, 1)
    proj = a + ab * t[:, None]
    i = np.argmin(((p - proj) ** 2).sum(1))
    cross = ab[i, 0] * (p[1] - a[i, 1]) - ab[i, 1] * (p[0] - a[i, 0])
    return cross > 0
land = unary_union([f for f in faces if is_land(f.representative_point())])
print('land-yta km2', round(land.area / 1e6, 2))

# Polygon söder om vägen: vägen + raka linjer söderut från ändarna
south_y = miny
poly = Polygon(c + [(east[0], south_y), (west[0], south_y)])
if not poly.is_valid:
    poly = poly.buffer(0)
# Behåll bara landbiten som hänger ihop med vägen (inte öar långt ut)
region_land = poly.intersection(land)
if region_land.geom_type == 'MultiPolygon':
    parts = sorted(region_land.geoms, key=lambda g: g.area, reverse=True)
    main = [g for g in parts if g.distance(road) < 50][0]
    parts = [g for g in parts if g is not main]
    # ta med öar/holmar som ligger nära (< 400 m från huvudlandet)
    keep = [main] + [g for g in parts if g.distance(main) < 400 and g.area > 200 and g.centroid.y > main.bounds[1] - 100]
    region_land = unary_union(keep)
print('område land km2', round(region_land.area / 1e6, 2), 'bounds', [round(v) for v in region_land.bounds])

# Hav som ingår i spelområdet: 300 m ut från stranden, inom polygonen
sea_strip = poly.intersection(region_land.buffer(300)).difference(region_land)
region = unary_union([region_land, sea_strip])

pickle.dump(dict(road=road, land=land, region_land=region_land, region=region, poly=poly,
                 work=work), open(str(WORK / 'region.pkl'), 'wb'))
for n, t in ntags.items():
    if t.get('name') in ('Å', 'Ursvik') or t.get('historic') == 'ruins':
        pt = Point(P[n]); print(t.get('name'), 'i området:', region_land.contains(pt))
