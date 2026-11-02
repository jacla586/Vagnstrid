"""Modeller för träd och buskar (vegetation.json).

Alla modeller har enheten höjd 1 och kronradie 1 (största vågräta utbredning), med origo vid
stammens fot; MultiMesh-transformen skalar dem till varje träds höjd och kronradie.

Egna modeller ('generera') byggs här i low-poly med vertexfärger och lite slump per variant.
Paketmodeller ('paket', t.ex. CC0 från Quaternius/Kenney) läses med trimesh och normaliseras;
material och texturer behålls.
"""
import json, math
from pathlib import Path
import numpy as np
import trimesh

ROOT = Path(__file__).resolve().parent.parent
KATALOG = json.loads((ROOT / 'vegetation.json').read_text())


# ---------------------------------------------------------------- byggklossar
def _lin(rgb):
    c = np.asarray(rgb, np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _farga(m, rgb, rng, variation=0.06, mork_nere=0.0):
    """Vertexfärger (glTF vill ha linjära) med lite brus och mörkare nertill."""
    v = np.asarray(m.vertices)
    bas = _lin(rgb)
    f = 1 + rng.normal(0, variation, (len(v), 1))
    if mork_nere:
        y = v[:, 1]
        t = (y - y.min()) / max(np.ptp(y), 1e-6)
        f = f * (1 - mork_nere * (1 - t))[:, None]
    col = np.clip(bas * f, 0, 1)
    m.visual = trimesh.visual.ColorVisuals(m, vertex_colors=np.c_[np.round(col * 255), np.full(len(v), 255)].astype(np.uint8))
    return m


def _cyl(r0, r1, y0, y1, sektioner=6):
    m = trimesh.creation.cylinder(radius=1.0, height=1.0, sections=sektioner)
    v = np.asarray(m.vertices).copy()        # z från -0.5 till 0.5
    t = v[:, 2] + 0.5
    r = r0 + (r1 - r0) * t
    m.vertices = np.c_[v[:, 0] * r, y0 + t * (y1 - y0), v[:, 1] * r]
    m.faces = np.asarray(m.faces)[:, ::-1]     # axelbytet speglar: vänd ytorna utåt igen
    return m


def _kon(r, y0, y1, rng, sektioner=8, jitter=0.1):
    m = trimesh.creation.cone(radius=1.0, height=1.0, sections=sektioner)
    v = np.asarray(m.vertices).copy()        # bas z=0, spets z=1
    bas = v[:, 2] < 0.5
    v[bas, 0] *= r * (1 + rng.uniform(-jitter, jitter, bas.sum()))
    v[bas, 1] *= r * (1 + rng.uniform(-jitter, jitter, bas.sum()))
    m.vertices = np.c_[v[:, 0], y0 + v[:, 2] * (y1 - y0), v[:, 1]]
    m.faces = np.asarray(m.faces)[:, ::-1]
    m.apply_transform(trimesh.transformations.rotation_matrix(rng.uniform(0, 2 * math.pi), [0, 1, 0]))
    return m


def _klump(c, rx, ry, rz, rng, jitter=0.12):
    m = trimesh.creation.icosphere(subdivisions=1, radius=1.0)
    v = np.asarray(m.vertices).copy()
    v *= 1 + rng.uniform(-jitter, jitter, (len(v), 1))
    m.vertices = v * [rx, ry, rz] + c
    return m


def _normalisera(m):
    """Höjd 1, kronradie 1, origo vid foten (för egna modeller i en enda mesh)."""
    v = np.asarray(m.vertices).copy()
    v[:, 1] -= v[:, 1].min()
    v[:, 1] /= max(v[:, 1].max(), 1e-6)
    r = np.sqrt(v[:, 0] ** 2 + v[:, 2] ** 2).max()
    v[:, [0, 2]] /= max(r, 1e-6)
    m.vertices = v
    return m


# ---------------------------------------------------------------- egna modeller
BARK = (92, 70, 52); TALLBARK = (150, 92, 58); BJORKBARK = (226, 224, 214)


def gran(rng):
    delar = [_farga(_cyl(0.05, 0.035, 0, 0.22), BARK, rng)]
    n = int(rng.integers(4, 7))
    for i in range(n):
        t = i / (n - 1)
        r = 1.0 - 0.78 * t + rng.uniform(-0.05, 0.05)
        y0 = 0.10 + 0.70 * t
        delar.append(_farga(_kon(r, y0, y0 + 0.34 - 0.08 * t, rng, sektioner=int(rng.integers(7, 10))),
                            (34 + 8 * t, 66 + 14 * t, 40 + 6 * t), rng, mork_nere=0.25))
    delar.append(_farga(_kon(0.12, 0.88, 1.0, rng), (44, 82, 46), rng))
    return _normalisera(trimesh.util.concatenate(delar))


def tall(rng):
    topp = rng.uniform(0.72, 0.82)
    delar = [_farga(_cyl(0.06, 0.04, 0, topp + 0.05), TALLBARK, rng, mork_nere=0.3)]
    for _ in range(int(rng.integers(3, 6))):
        a = rng.uniform(0, 2 * math.pi); d = rng.uniform(0.1, 0.45)
        c = [math.cos(a) * d, rng.uniform(topp, 0.93), math.sin(a) * d]
        delar.append(_farga(_klump(c, rng.uniform(0.3, 0.5), rng.uniform(0.08, 0.14), rng.uniform(0.3, 0.5), rng),
                            (54, 86, 46), rng, mork_nere=0.2))
    return _normalisera(trimesh.util.concatenate(delar))


def bjork(rng):
    stam = _farga(_cyl(0.035, 0.02, 0, 0.75), BJORKBARK, rng, variation=0.02)
    col = np.asarray(stam.visual.vertex_colors).copy()
    flack = rng.random(len(col)) < 0.25
    col[flack, :3] = 40
    stam.visual = trimesh.visual.ColorVisuals(stam, vertex_colors=col)
    delar = [stam]
    for _ in range(int(rng.integers(6, 9))):
        a = rng.uniform(0, 2 * math.pi); d = rng.uniform(0.0, 0.32)
        y = rng.uniform(0.42, 0.9)
        delar.append(_farga(_klump([math.cos(a) * d, y, math.sin(a) * d], rng.uniform(0.2, 0.3),
                                   rng.uniform(0.16, 0.24), rng.uniform(0.2, 0.3), rng),
                            (104, 146, 62), rng, variation=0.08, mork_nere=0.25))
    return _normalisera(trimesh.util.concatenate(delar))


def ek(rng):
    delar = [_farga(_cyl(0.08, 0.05, 0, 0.45), BARK, rng, mork_nere=0.3)]
    for _ in range(int(rng.integers(5, 8))):
        a = rng.uniform(0, 2 * math.pi); d = rng.uniform(0.15, 0.5)
        y = rng.uniform(0.5, 0.82)
        delar.append(_farga(_klump([math.cos(a) * d, y, math.sin(a) * d], rng.uniform(0.32, 0.45),
                                   rng.uniform(0.2, 0.28), rng.uniform(0.32, 0.45), rng),
                            (66, 102, 48), rng, variation=0.08, mork_nere=0.3))
    return _normalisera(trimesh.util.concatenate(delar))


def buske(rng):
    delar = []
    for _ in range(int(rng.integers(3, 6))):
        a = rng.uniform(0, 2 * math.pi); d = rng.uniform(0.0, 0.45)
        delar.append(_farga(_klump([math.cos(a) * d, rng.uniform(0.3, 0.55), math.sin(a) * d],
                                   rng.uniform(0.35, 0.55), rng.uniform(0.3, 0.45), rng.uniform(0.35, 0.55), rng),
                            (70, 106, 50), rng, variation=0.08, mork_nere=0.35))
    return _normalisera(trimesh.util.concatenate(delar))


def sly(rng):
    delar = []
    for _ in range(int(rng.integers(4, 7))):
        a = rng.uniform(0, 2 * math.pi); d = rng.uniform(0.1, 0.55)
        x, z = math.cos(a) * d, math.sin(a) * d
        y = rng.uniform(0.45, 0.8)
        delar.append(_farga(_cyl(0.025, 0.015, 0, y), BARK, rng))
        delar.append(_farga(_klump([x * 0.6, y, z * 0.6], rng.uniform(0.2, 0.3), rng.uniform(0.2, 0.3),
                                   rng.uniform(0.2, 0.3), rng), (88, 122, 58), rng, variation=0.08, mork_nere=0.3))
    return _normalisera(trimesh.util.concatenate(delar))


def hack(rng):
    """Klippt häck: avlång rundad låda, x från -1 till 1 (längs häcken), z från -0,5 till 0,5."""
    m = trimesh.creation.box(extents=[2.0, 1.0, 1.0])
    m = m.subdivide().subdivide()
    v = np.asarray(m.vertices).copy()
    v[:, 1] += 0.5
    v[:, [0, 2]] *= 1 + rng.uniform(-0.03, 0.03, (len(v), 1))
    v[:, 1] *= 1 + rng.uniform(-0.04, 0.04, len(v))
    v[:, 2] *= 0.5
    v[:, 1] = np.clip(v[:, 1], 0, 1)
    m.vertices = v
    return _farga(m, (60, 94, 46), rng, variation=0.07, mork_nere=0.35)


GENERATORER = dict(gran=gran, tall=tall, bjork=bjork, ek=ek, buske=buske, sly=sly, hack=hack)


# ---------------------------------------------------------------- paketmodeller
def normalisera_paket(scene):
    """CC0-paketmodell (trimesh.Scene): höjd 1, kronradie 1, origo vid stammens fot.
    Stammens fot = mitten av de lägsta 5 % av hörnen; kronradien mäts runt den."""
    scene = scene.copy()
    geom = scene.dump(concatenate=False)
    allt = np.vstack([np.asarray(g.vertices) for g in geom])
    y0 = allt[:, 1].min(); hojd = max(np.ptp(allt[:, 1]), 1e-6)
    lag = allt[allt[:, 1] <= y0 + 0.05 * hojd]
    cx, cz = lag[:, 0].mean(), lag[:, 2].mean()
    r = max(np.sqrt((allt[:, 0] - cx) ** 2 + (allt[:, 2] - cz) ** 2).max(), 1e-6)
    ut = trimesh.Scene()
    for i, g in enumerate(geom):
        g = g.copy()
        v = np.asarray(g.vertices).copy()
        g.vertices = np.c_[(v[:, 0] - cx) / r, (v[:, 1] - y0) / hojd, (v[:, 2] - cz) / r]
        ut.add_geometry(g, geom_name=f'del_{i}')
    return ut


# ---------------------------------------------------------------- export
def bygg_modeller(grupp, ut):
    """Bygger alla varianter för 'trad' eller 'buskar'. Returnerar {slag: [filnamn, ...]}."""
    paketmapp = ROOT / KATALOG.get('paketmapp', 'vegetation_paket')
    filer = {}
    for slag, spec in KATALOG[grupp].items():
        filer[slag] = []
        for i, var in enumerate(spec['varianter']):
            namn = f'veg_{slag}_{i}.glb'
            modell = None
            if var.get('paket'):
                kallor = sorted(paketmapp.glob(var['paket']))
                if kallor:
                    modell = normalisera_paket(trimesh.load(str(kallor[0]), force='scene'))
                    print(f'  {namn}: paketmodell {kallor[0].relative_to(paketmapp)}')
                else:
                    print(f'  {namn}: hittar inte {var["paket"]} i {paketmapp}, använder egen modell')
            if modell is None:
                typ = var.get('generera') or var.get('reserv') or slag
                modell = GENERATORER[typ](np.random.default_rng(1000 * i + len(slag)))
            modell.export(str(Path(ut) / namn))
            filer[slag].append(namn)
    return filer
