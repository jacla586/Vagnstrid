"""Vägtrummor (Trafikverket, Lastkajen-paket 10473, statliga vägar): synliga rörändar i vägbanken.

Linjerna går tvärs under vägen (oftast schablonberäknade ur den inmätta mittpunkten och längden).
I varje ände läggs en kort rörstump (betong, plåt eller plast efter inloppsmaterialet) med
diametern ur datan i en svacka (schakta: marken sänks vid mynningen och ett dike ut), och en mörk
skiva en bit in som djup.
Glb-gruppen `Trummor` (ingen kollision). Utan filen händer inget.
"""
import sqlite3
from pathlib import Path
import numpy as np
import shapely
import trimesh

ROOT = Path(__file__).resolve().parent.parent
FIL = ROOT / 'östergötland' / 'data' / 'lastkajen' / '10473' / 'vagtrummor_linjer_ostergotland.gpkg'
TABELL = 'Östergötlands län'
STUMP_M = 0.6
SANKT = 0.25          # så stor del av diametern ligger under (den nedsänkta) markytan vid mynningen


def _wkb(b):
    flags = b[3]
    env = (flags >> 1) & 7
    return bytes(b[8 + {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}[env]:])


def las(ruta):
    if not FIL.exists():
        print('trummor: ingen fil', FIL)
        return []
    con = sqlite3.connect(f'file:{FIL}?mode=ro', uri=True)
    rader = con.execute(f'select geom, "Inloppsbredd/diameter (mm)", "Utloppsbredd/diameter (mm)", '
                        f'"Inloppsmaterial" from "{TABELL}"').fetchall()
    con.close()
    box = shapely.box(*ruta)
    ut = []
    for g, din, dut, mat in rader:
        if g is None:
            continue
        geom = shapely.force_2d(shapely.from_wkb(_wkb(g)))
        if not geom.intersects(box) or geom.length < 1.0:
            continue
        def mm(v):
            try:
                return float(v) / 1000.0
            except (TypeError, ValueError):
                return 0.0
        d = max(mm(din), mm(dut)) or 0.4
        ut.append((geom, min(max(d, 0.2), 3.0), (mat or '').lower()))
    print(f'trummor: {len(ut)} i rutan')
    return ut


def bygg(trummor, h, sample, to_world, add_merged, mat):
    if not trummor:
        return
    M = dict(betong=mat('Trumma_betong', (138, 136, 130), 0.95), plat=mat('Trumma_plat', (110, 114, 112), 0.6),
             plast=mat('Trumma_plast', (60, 64, 60), 0.7), morker=mat('Trumma_morker', (12, 12, 12), 1.0))
    n = 0
    for geom, d, material in trummor:
        c = np.array(geom.coords)
        for a, b in ((c[0], c[1]), (c[-1], c[-2])):
            ut = a - b
            L = np.linalg.norm(ut)
            if L < 1e-6:
                continue
            ut /= L
            z = float(sample(h, [a[0]], [a[1]])[0])
            r = d / 2
            vagg = max(0.05, d * 0.08)
            mitt_y = z - d * SANKT + r
            # rörstump längs z, vrids till trummans riktning (världen: x = öst, z = −N)
            ror = trimesh.creation.annulus(r_min=r, r_max=r + vagg, height=STUMP_M, sections=16)
            skiva = trimesh.creation.cylinder(radius=r, height=0.02, sections=16)
            skiva.apply_translation([0, 0, -STUMP_M * 0.2])
            dir_w = np.array([ut[0], 0.0, -ut[1]])
            R = trimesh.geometry.align_vectors([0, 0, 1], dir_w)
            wx, wz = to_world(a[0], a[1])
            T = trimesh.transformations.translation_matrix([wx, mitt_y, wz]) @ R
            for msh, m in ((ror, M['plat' if 'plåt' in material or 'stål' in material else
                                  'plast' if 'plast' in material else 'betong']), (skiva, M['morker'])):
                msh = msh.copy()
                msh.apply_transform(T)
                add_merged('Trummor', msh, m)
            n += 1
    print(f'trummor: {n} rörändar')


def schakta(trummor, h, shape, T, OX, OY, RES):
    """Sänker marken vid varje mynning: en grop och ett dike DIKE_M ut från röret, så att trumman
    ligger i en svacka (körs före heightmap-exporten)."""
    if not trummor:
        return
    from scipy.spatial import cKDTree
    n = 0
    for geom, d, _ in trummor:
        c = np.array(geom.coords)
        for a, b in ((c[0], c[1]), (c[-1], c[-2])):
            ut = a - b
            L = np.linalg.norm(ut)
            if L < 1e-6:
                continue
            ut /= L
            djup = d * 0.75
            # punkter längs diket: från mynningen och DIKE_M ut
            s = np.linspace(-0.5, DIKE_M, 12)
            pts = a[None, :] + ut[None, :] * s[:, None]
            rad = d / 2 + 1.5
            jj0 = int((min(pts[:, 0]) - rad - OX) / RES) - 1
            jj1 = int((max(pts[:, 0]) + rad - OX) / RES) + 2
            ii0 = int((OY - max(pts[:, 1]) - rad) / RES) - 1
            ii1 = int((OY - min(pts[:, 1]) + rad) / RES) + 2
            ii0, jj0 = max(ii0, 0), max(jj0, 0)
            ii1, jj1 = min(ii1, shape[0]), min(jj1, shape[1])
            if ii1 <= ii0 or jj1 <= jj0:
                continue
            II, JJ = np.mgrid[ii0:ii1, jj0:jj1]
            X, Y = OX + JJ * RES, OY - II * RES
            dist, k = cKDTree(pts).query(np.c_[X.ravel(), Y.ravel()])
            dist = dist.reshape(X.shape)
            # djupast vid mynningen, grundare ut mot dikets slut
            andel = 1.0 - (s[k.reshape(X.shape)].clip(0, DIKE_M) / DIKE_M) * 0.6
            t = np.clip(1.0 - dist / rad, 0.0, 1.0)
            sank = djup * andel * t * t * (3 - 2 * t)
            h[ii0:ii1, jj0:jj1] -= sank
            n += 1
    print(f'trummor: {n} mynningar nedsänkta')


DIKE_M = 5.0
