"""Snabbtest av vägnätet utan att bygga om kartan: ritar vägytor och markeringar uppifrån för ett område.

    .venv/bin/python -I scripts/vagtest.py vidingsjo 1290,1935 150 haninge_vidingsjogatan
    (projekt, mitt i Godot-koordinater x,z, halv sida i m, namn) -> forhandsbilder/vagtest_<namn>.png

Kör samma kod som step3 (vagnat.forbered, vagmarkering) på work/features.pkl och NVDB-cachen
(work/nvdb.pkl), tar några sekunder. Höjder ignoreras. x åt höger = öst, uppåt = norr.
"""
import sys, json, pickle
from pathlib import Path
import numpy as np
from shapely.geometry import box
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vagnat, vagmarkering

ROOT = Path(__file__).resolve().parent.parent
FARG = {'asfalt': '#3c3c40', 'grus': '#968a74', 'stig': '#76644c'}


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    projekt, mitt, halv, namn = sys.argv[1], [float(v) for v in sys.argv[2].split(',')], float(sys.argv[3]), sys.argv[4]
    work = ROOT / projekt / 'work' if projekt != 'vikbolandet' else ROOT / 'work'
    g = json.load(open(work / 'grid.json'))
    W, H, RES, X0, Y1 = g['W'], g['H'], g['RES'], g['x0'], g['y1']
    OX, OY = X0 + RES / 2, Y1 - RES / 2
    BOX = box(X0, Y1 - H * RES, X0 + W * RES, Y1)
    feat = pickle.load(open(work / 'features.pkl', 'rb'))
    roads = vagnat.vaglista(feat['roads'], BOX)
    NV = vagnat.forbered(roads, (X0, Y1 - H * RES, X0 + W * RES, Y1), work)
    to_world = lambda x, y: (np.asarray(x) - OX, OY - np.asarray(y))
    fonster = box(OX + mitt[0] - halv * 1.5, OY - mitt[1] - halv * 1.5, OX + mitt[0] + halv * 1.5, OY - mitt[1] + halv * 1.5)
    for r in roads:   # samma punkter som step3
        L = r['line']
        n = max(2, int(L.length / 2) + 1)
        r['s'] = np.linspace(0, L.length, n)
        r['pts'] = np.array([L.interpolate(d).coords[0] for d in r['s']])
        dv = np.gradient(r['pts'], axis=0)
        dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
        r['nrm'] = np.c_[-dv[:, 1], dv[:, 0]]
        r['zm'] = np.zeros(n)
        r['z'] = np.zeros(n)
    ytor, farger = [], []
    for r in roads:
        if not r['line'].intersects(fonster):
            continue
        hw = r['hw'][:, None]
        Lp, Rp = r['pts'] + r['nrm'] * hw, r['pts'] - r['nrm'] * hw
        poly = np.vstack([Lp, Rp[::-1]])
        x, z = to_world(poly[:, 0], poly[:, 1])
        ytor.append(np.c_[x, z])
        farger.append(FARG.get(r['surface'], '#555'))
    linjer = []
    def add_merged(grupp, mesh, mat):
        V = np.asarray(mesh.vertices)
        for f in np.asarray(mesh.faces):
            linjer.append(V[f][:, [0, 2]])
    mark = vagmarkering.Markering(roads, NV)
    mark.bygg(add_merged, lambda n, c, r=0.9: None, to_world)
    fig, ax = plt.subplots(figsize=(12, 12), dpi=130)
    ax.set_facecolor('#8a9a5a')
    ax.add_collection(PolyCollection(ytor, facecolors=farger, edgecolors='#202024', linewidths=0.3, alpha=0.95))
    ax.add_collection(PolyCollection(linjer, facecolors='white', edgecolors='none'))
    k = mark.korsningar
    if len(k):
        kx, kz = to_world(k[:, 0], k[:, 1])
        ax.scatter(kx, kz, s=12, c='orange', zorder=5, label='korsning')
    for r in roads:
        if r['line'].intersects(fonster) and r['tags']['highway'] not in vagnat.WIDTH or False:
            pass
    ax.set_xlim(mitt[0] - halv, mitt[0] + halv)
    ax.set_ylim(mitt[1] + halv, mitt[1] - halv)   # z söderut: norr uppåt
    ax.set_aspect('equal')
    ax.set_title(f'{projekt} {namn}  ({mitt[0]:.0f}, {mitt[1]:.0f}) ±{halv:.0f} m')
    ut = ROOT / 'forhandsbilder' / f'vagtest_{namn}.png'
    ut.parent.mkdir(exist_ok=True)
    fig.savefig(ut, bbox_inches='tight')
    print('->', ut)


if __name__ == '__main__':
    main()
