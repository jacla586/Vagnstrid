#!/usr/bin/env python3
"""Rutt för en korridorkarta: OSM-vägnätet längs en Google Maps-mätning.

    .venv/bin/python -I scripts/rutt_ur_bild.py <namn> [--bredd 500] [--kant 120]

Läser <namn>/rutt_bild.json ({"px": [[x, y], ...]}: mätpunkterna i skärmbilden från start till
slut, avlästa för hand) och <namn>/omrade.json ("rutt": start/slut lat,lon). Första och sista
punkten georefereras mot start och slut (Web Mercator, ingen vridning, samma skala åt båda håll),
de andra blir en ledlinje. Kortaste väg i OSM (alla highway utom trappor) med kostnad
längd · (1 + (avstånd till ledlinjen / 12 m)²). Skriver <namn>/rutt.json och <namn>/korridor.json.
"""
import argparse, heapq, json, math, sys
import xml.etree.ElementTree as ET
from pathlib import Path

import numpy as np
from pyproj import Transformer

ROOT = Path(__file__).resolve().parent.parent


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('namn')
    ap.add_argument('--bredd', type=float, default=500.0)
    ap.add_argument('--kant', type=float, default=120.0)
    a = ap.parse_args()
    P = ROOT / a.namn
    d = json.load(open(P / 'rutt_bild.json'))['px']
    o = json.load(open(P / 'omrade.json'))['rutt']
    m = Transformer.from_crs(4326, 3857, always_xy=True)
    back = Transformer.from_crs(3857, 3006, always_xy=True)
    s = m.transform(o['start'][1], o['start'][0]); e = m.transform(o['slut'][1], o['slut'][0])
    p0, p1 = d[0], d[-1]
    k = math.hypot(e[0] - s[0], e[1] - s[1]) / math.hypot(p1[0] - p0[0], p1[1] - p0[1])
    guide = np.array([back.transform(s[0] + (x - p0[0]) * k, s[1] - (y - p0[1]) * k) for x, y in d])
    print('ledlinje %.0f m' % np.sum(np.hypot(*np.diff(guide, axis=0).T)))

    def dist_guide(pt):
        a_ = guide[:-1]; ab = guide[1:] - a_
        t = np.clip(((pt - a_) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-9), 0, 1)
        return np.min(np.hypot(*(a_ + ab * t[:, None] - pt).T))

    tr = Transformer.from_crs(4326, 3006, always_xy=True)
    nodes, ways = {}, []
    for _, el in ET.iterparse(P / 'data' / 'export.osm'):
        if el.tag == 'node':
            nodes[el.get('id')] = (float(el.get('lon')), float(el.get('lat')))
        elif el.tag == 'way':
            tags = {t.get('k'): t.get('v') for t in el.findall('tag')}
            if 'highway' in tags:
                ways.append(([n.get('ref') for n in el.findall('nd')], tags, el.get('id')))
            el.clear()
    xy = {}
    def X(n):
        if n not in xy:
            xy[n] = np.array(tr.transform(*nodes[n]))
        return xy[n]
    G = {}
    for refs, tags, wid in ways:
        if tags['highway'] in ('steps', 'proposed', 'construction', 'platform'):
            continue
        for u, v in zip(refs, refs[1:]):
            if u not in nodes or v not in nodes:
                continue
            l = float(np.hypot(*(X(u) - X(v))))
            c = l * (1 + (dist_guide((X(u) + X(v)) / 2) / 12) ** 2)
            G.setdefault(u, []).append((v, c, wid)); G.setdefault(v, []).append((u, c, wid))
    near = lambda p: min(G, key=lambda n: np.hypot(*(X(n) - p)))
    A, B = near(guide[0]), near(guide[-1])
    dist, prev, q = {A: 0}, {}, [(0, A)]
    while q:
        c, n = heapq.heappop(q)
        if n == B:
            break
        if c > dist[n]:
            continue
        for nb, w, wid in G[n]:
            if c + w < dist.get(nb, 1e18):
                dist[nb] = c + w; prev[nb] = (n, wid); heapq.heappush(q, (c + w, nb))
    if B not in dist:
        sys.exit('start och slut hänger inte ihop i vägnätet')
    path, wids = [B], []
    while path[-1] != A:
        n, w = prev[path[-1]]; path.append(n); wids.append(w)
    path.reverse(); wids.reverse()
    pts = np.array([X(n) for n in path])
    print('rutt %.0f m, som mest %.0f m från ledlinjen' % (np.sum(np.hypot(*np.diff(pts, axis=0).T)),
                                                         max(dist_guide(p) for p in pts)))
    info = {w[2]: w[1] for w in ways}
    seen = []
    for w in wids:
        if not seen or seen[-1] != w:
            seen.append(w)
    namn = []
    for w in seen:
        nm = info[w].get('name') or info[w]['highway']
        if not namn or namn[-1] != nm:
            namn.append(nm)
    print(' -> '.join(namn))
    sweref = [[round(float(x), 1), round(float(y), 1)] for x, y in pts]
    json.dump({'sweref': sweref, 'guide': guide.round(1).tolist(), 'ways': seen}, open(P / 'rutt.json', 'w'))
    json.dump({'anm': 'Korridorkarta (scripts/korridor.py): hus, träd och buskar bara inom bredd_m från rutten, '
                      'glesnar ut över kant_m. Rutten ur OSM längs rutt_bild.json (scripts/rutt_ur_bild.py).',
               'bredd_m': a.bredd, 'kant_m': a.kant, 'rutt_sweref': sweref, 'osm_vagar': seen},
              open(P / 'korridor.json', 'w'), ensure_ascii=False)
    print('skrev', P / 'korridor.json')


if __name__ == '__main__':
    main()
