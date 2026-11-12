"""Moves a ThunderRoad scenario's checkpoints along the route so their capture zones hold as few
houses as possible (OSM buildings in geodata/<map>/work/features.pkl).

  geodata/.venv/bin/python -I tools/thunder_checkpoints_avoid_houses.py scenes/scenarios/<x>.tscn <map>

Each checkpoint may move up to 90 m along the route (zones are projected onto the route, so only
along-route moves matter), keeps 200 m to the one before and never passes the route's end. Zone size
as in data/modes/thunder_road.tres (capture_half_width_m 160, capture_half_length_m 60). Rewrites the
scene in place; run after thunder_route_from_osm.py.
"""
import json, math, pickle, re, sys
import numpy as np
from shapely.geometry import Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree
if len(sys.argv) < 3:
    sys.exit(__doc__)
scen, karta = sys.argv[1], sys.argv[2]
HW, HL = 160.0, 60.0
info = json.load(open(f'geodata/{karta}/out/heightmap_info.json')); OE, ON = info['origin_sweref_of_pixel_0_0']
feat = pickle.load(open(f'geodata/{karta}/work/features.pkl', 'rb'))
hus = [g for g, _ in feat['buildings']]
tree = STRtree(hus)
t = open(scen).read()
pts = [float(v) for v in re.search(r'"points": PackedVector3Array\(([^)]*)\)', t).group(1).split(',')]
route = np.array([pts[i + 6:i + 9] for i in range(0, len(pts), 9)])   # x, y, z
xz = route[:, [0, 2]]
seg = np.hypot(*np.diff(xz, axis=0).T); cum = np.r_[0, np.cumsum(seg)]; total = cum[-1]
def at(s):
    s = min(max(s, 0), total); i = min(np.searchsorted(cum, s, 'right') - 1, len(seg) - 1)
    f = (s - cum[i]) / seg[i]; p = route[i] + (route[i + 1] - route[i]) * f
    d = (xz[i + 1] - xz[i]) / seg[i]; return p, d
def husandel(s):
    p, d = at(s); n = np.array([-d[1], d[0]])
    c = [p[[0, 2]] + d * a * HL + n * b * HW for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    rect = Polygon([(x + OE, ON - z) for x, z in c])
    nära = [hus[i] for i in tree.query(rect)]
    return unary_union([h.intersection(rect) for h in nära]).area / rect.area if nära else 0.0
cps = [(m.group(1), float(m.group(2)), float(m.group(4))) for m in
       re.finditer(r'\[node name="(CP\d+)"[^\n]*\]\ntransform = Transform3D\(1, 0, 0, 0, 1, 0, 0, 0, 1, ([-\d.]+), ([-\d.]+), ([-\d.]+)\)', t)]
s_cp = [cum[np.argmin(np.hypot(xz[:, 0] - x, xz[:, 1] - z))] for _, x, z in cps]
nya = []
for k, (namn, x, z) in enumerate(cps):
    s0 = s_cp[k]; prev = nya[-1] if nya else 0.0
    best = None
    for ds in range(-90, 91, 10):
        s = s0 + ds
        if s > total or s - prev < 200:
            continue
        a = husandel(s) + abs(ds) / 90 * 0.02   # hellre kvar om det inte gör stor skillnad
        if best is None or a < best[0]:
            best = (a, s)
    a, s = best
    print(f'{namn}: {husandel(s0):.0%} hus -> {husandel(s):.0%} (flyttad {s - s0:+.0f} m, {s:.0f} av {total:.0f} m)')
    nya.append(s)
    p, _ = at(s)
    t = re.sub(r'(\[node name="%s"[^\n]*\]\ntransform = Transform3D\(1, 0, 0, 0, 1, 0, 0, 0, 1, )[-\d.]+, [-\d.]+, [-\d.]+\)' % namn,
               lambda m: m.group(1) + '%.2f, %.2f, %.2f)' % (p[0], p[1] - 0.5, p[2]), t)
open(scen, 'w').write(t)
