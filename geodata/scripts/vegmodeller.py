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


def _krans(r, y0, y1, rng, sektioner=14, hang=0.35, tagg=0.28):
    """En grankrans: kon vars bas är en stjärna (grenspetsar ut, mellanrum in) och vars
    spetsar hänger ner `hang` av kransens höjd. Ger taggig siluett i stället för slät kon."""
    m = trimesh.creation.cone(radius=1.0, height=1.0, sections=sektioner)
    v = np.asarray(m.vertices).copy()        # bas z=0, spets z=1
    bas = v[:, 2] < 0.5
    vinkel = np.arctan2(v[:, 1], v[:, 0])
    steg = 2 * math.pi / sektioner
    udda = (np.round(vinkel / steg).astype(int) % 2) == 1
    fakt = np.where(udda, 1.0 - tagg, 1.0) * (1 + rng.uniform(-0.08, 0.08, len(v)))
    v[bas, 0] *= r * fakt[bas]
    v[bas, 1] *= r * fakt[bas]
    h = y1 - y0
    z = y0 + v[:, 2] * h
    z = np.where(bas & ~udda, z - hang * h, z)   # spetsarna hänger
    m.vertices = np.c_[v[:, 0], z, v[:, 1]]
    m.faces = np.asarray(m.faces)[:, ::-1]
    m.apply_transform(trimesh.transformations.rotation_matrix(rng.uniform(0, 2 * math.pi), [0, 1, 0]))
    return m


GRAN_MORK = (30, 58, 38); GRAN_LJUS = (44, 76, 46)


def gran(rng):
    """Smal gran: kort synlig stam, 8-11 taggiga, hängande kransar som smalnar av uppåt och
    en tunn topp. Kransarna överlappar så att skogen ser tät ut."""
    delar = [_farga(_cyl(0.045, 0.03, 0, 0.3), BARK, rng)]
    n = int(rng.integers(8, 12))
    for i in range(n):
        t = i / (n - 1)
        r = (1.0 - 0.85 * t) * rng.uniform(0.9, 1.06)
        y0 = 0.08 + 0.78 * t
        hojd = 0.2 - 0.08 * t
        farg = tuple(int(a + (b - a) * t) for a, b in zip(GRAN_MORK, GRAN_LJUS))
        delar.append(_farga(_krans(r, y0, y0 + hojd, rng, sektioner=int(rng.integers(12, 17)),
                                   hang=0.45 - 0.2 * t), farg, rng, variation=0.07, mork_nere=0.35))
    delar.append(_farga(_kon(0.07, 0.9, 1.0, rng, sektioner=6), GRAN_LJUS, rng))
    return _normalisera(trimesh.util.concatenate(delar))


TALL_BARK_NERE = (88, 78, 70)    # gråbrun grov bark nertill
TALL_BARR = (52, 82, 46)
TALL_BARR_LJUS = (66, 96, 52)


def _gren(p0, p1, r, rng, farg):
    """Rak cylinder mellan två punkter (gren eller stambit)."""
    p0 = np.asarray(p0, float); p1 = np.asarray(p1, float)
    if np.linalg.norm(p1 - p0) < 1e-4:
        return None
    return _farga(trimesh.creation.cylinder(radius=r, segment=[p0, p1], sections=6), farg, rng, variation=0.05)


def _pa_linje(pkt, y):
    """Punkten på en brutet linje (stammen) vid höjden y."""
    for a, b in zip(pkt, pkt[1:]):
        if a[1] <= y <= b[1]:
            return a + (b - a) * ((y - a[1]) / max(b[1] - a[1], 1e-6))
    return pkt[-1].copy()


def tall(rng):
    """Yvig tall som i Vidingsjö, byggd i meter (21 m hög) och normaliserad sist: lite krokig
    stam (grå nertill, orange spegelbark uppåt) som delar sig i 2-3 toppskott vid ca 70 %;
    stor, klumpig och oregelbunden krona av 12-16 platta tussar från ca 45 %, ensidig;
    några döda grenstumpar under kronan."""
    H = 21.0
    gaffel = H * rng.uniform(0.66, 0.74)
    pkt = [np.zeros(3)]
    a = rng.uniform(0, 2 * math.pi)
    for i in range(1, 5):
        a += rng.uniform(-0.9, 0.9)
        pkt.append(np.array([math.cos(a) * 0.5 * i / 4, gaffel * i / 4, math.sin(a) * 0.5 * i / 4]))
    delar = [_gren(pkt[i], pkt[i + 1], 0.22 * (1 - 0.6 * i / 4), rng,
                   TALLBARK if i >= 2 else TALL_BARK_NERE) for i in range(4)]
    skott = []
    for _ in range(int(rng.integers(2, 4))):
        a = rng.uniform(0, 2 * math.pi); d = rng.uniform(1.0, 2.2)
        s = pkt[-1] + [math.cos(a) * d, rng.uniform(3.0, 4.5), math.sin(a) * d]
        delar.append(_gren(pkt[-1], s, 0.11, rng, TALLBARK))
        skott.append(s)
    sida = rng.uniform(0, 2 * math.pi)                  # kronan väger åt ett håll
    sx, sz = math.cos(sida) * 0.9, math.sin(sida) * 0.9
    for k in range(int(rng.integers(12, 17))):
        a = rng.uniform(0, 2 * math.pi)
        if k < len(skott) or rng.random() < 0.45:       # tuss i toppskotten (minst en per skott)
            d = rng.uniform(0.3, 1.6)
            c = skott[k if k < len(skott) else int(rng.integers(len(skott)))] + [
                math.cos(a) * d + sx, rng.uniform(-1.2, 0.3), math.sin(a) * d + sz]
        else:                                           # tuss på en gren ut från stammen
            bas = _pa_linje(pkt, rng.uniform(H * 0.45, gaffel + 1.0))
            d = rng.uniform(1.2, 3.2)
            c = bas + [math.cos(a) * d + sx, rng.uniform(0.3, 0.9), math.sin(a) * d + sz]
            delar.append(_gren(bas, c, 0.07, rng, TALLBARK))
        r = rng.uniform(1.0, 1.9)
        farg = TALL_BARR if rng.random() < 0.6 else TALL_BARR_LJUS
        delar.append(_farga(_klump(c, r, r * rng.uniform(0.45, 0.65), r * rng.uniform(0.7, 1.2), rng, jitter=0.22),
                            farg, rng, variation=0.09, mork_nere=0.35))
    for _ in range(int(rng.integers(1, 4))):            # döda grenstumpar
        a = rng.uniform(0, 2 * math.pi)
        s = _pa_linje(pkt, rng.uniform(H * 0.25, H * 0.42))
        delar.append(_gren(s, s + [math.cos(a) * 0.7, 0.15, math.sin(a) * 0.7], 0.04, rng, TALL_BARK_NERE))
    return _normalisera(trimesh.util.concatenate([d for d in delar if d is not None]))


BJORK_LOV = (108, 150, 66); BJORK_LOV_LJUS = (128, 166, 78)
EK_LOV = (62, 98, 46); EK_LOV_LJUS = (78, 114, 54)


def _flackig_stam(stam, rng, andel=0.25):
    """Björkstam: vit med svarta fläckar (vertexfärger)."""
    col = np.asarray(stam.visual.vertex_colors).copy()
    flack = rng.random(len(col)) < andel
    col[flack, :3] = 40
    stam.visual = trimesh.visual.ColorVisuals(stam, vertex_colors=col)
    return stam


def bjork(rng):
    """Björk, byggd i meter (16 m hög) och normaliserad sist: smal, lite lutande vit stam med
    svarta fläckar, 4-6 uppåtriktade grenar och en luftig, hög krona av 14-20 mindre tussar
    (stammen syns mellan dem)."""
    H = 16.0
    luta = np.array([rng.uniform(-0.4, 0.4), 0.0, rng.uniform(-0.4, 0.4)])
    topp = np.array([0.0, H * 0.82, 0.0]) + luta
    delar = [_flackig_stam(_gren([0, 0, 0], topp * 0.5, 0.18, rng, BJORKBARK), rng),
             _flackig_stam(_gren(topp * 0.5, topp, 0.11, rng, BJORKBARK), rng)]
    fasten = []
    for _ in range(int(rng.integers(4, 7))):
        y = rng.uniform(0.35, 0.7)
        bas = topp * y
        a = rng.uniform(0, 2 * math.pi); d = rng.uniform(1.4, 2.6)
        spets = bas + [math.cos(a) * d, rng.uniform(1.8, 3.2), math.sin(a) * d]
        delar.append(_gren(bas, spets, 0.06, rng, BJORKBARK))
        fasten.append(spets)
    fasten.append(topp)
    for k in range(int(rng.integers(14, 21))):
        a = rng.uniform(0, 2 * math.pi)
        if rng.random() < 0.6:
            c = fasten[int(rng.integers(len(fasten)))] + [math.cos(a) * rng.uniform(0.2, 1.4),
                                                          rng.uniform(-1.0, 0.8), math.sin(a) * rng.uniform(0.2, 1.4)]
        else:
            y = rng.uniform(0.45, 0.95)
            c = topp * y + [math.cos(a) * rng.uniform(0.8, 2.6), rng.uniform(-0.5, 0.5), math.sin(a) * rng.uniform(0.8, 2.6)]
        r = rng.uniform(0.9, 1.6)
        farg = BJORK_LOV if rng.random() < 0.6 else BJORK_LOV_LJUS
        delar.append(_farga(_klump(c, r, r * rng.uniform(0.7, 0.95), r * rng.uniform(0.85, 1.1), rng, jitter=0.2),
                            farg, rng, variation=0.08, mork_nere=0.3))
    return _normalisera(trimesh.util.concatenate([d for d in delar if d is not None]))


def ek(rng):
    """Ek, byggd i meter (15 m hög) och normaliserad sist: grov kort stam som delar sig i 2-3
    tjocka, utåtlutande grenar vid ca 35 %, och en bred, klumpig krona av 12-16 stora tussar."""
    H = 15.0
    gaffel = np.array([rng.uniform(-0.3, 0.3), H * rng.uniform(0.3, 0.4), rng.uniform(-0.3, 0.3)])
    delar = [_gren([0, 0, 0], gaffel, 0.42, rng, BARK)]
    lemmar = []
    for j in range(int(rng.integers(2, 4))):
        a = rng.uniform(0, 2 * math.pi) if j == 0 else lemmar_a + (2 * math.pi / 3) * j + rng.uniform(-0.4, 0.4)
        if j == 0:
            lemmar_a = a
        d = rng.uniform(2.5, 4.0)
        spets = gaffel + [math.cos(a) * d, rng.uniform(3.0, 4.5), math.sin(a) * d]
        delar.append(_gren(gaffel, spets, 0.24, rng, BARK))
        lemmar.append(spets)
    for k in range(int(rng.integers(12, 17))):
        a = rng.uniform(0, 2 * math.pi)
        bas = lemmar[k % len(lemmar)]
        c = bas + [math.cos(a) * rng.uniform(0.5, 2.4), rng.uniform(-0.6, 2.4), math.sin(a) * rng.uniform(0.5, 2.4)]
        r = rng.uniform(1.6, 2.6)
        farg = EK_LOV if rng.random() < 0.6 else EK_LOV_LJUS
        delar.append(_farga(_klump(c, r, r * rng.uniform(0.65, 0.85), r * rng.uniform(0.85, 1.1), rng, jitter=0.2),
                            farg, rng, variation=0.08, mork_nere=0.35))
    return _normalisera(trimesh.util.concatenate([d for d in delar if d is not None]))


def buske(rng):
    """Buske: 7-11 oregelbundna tussar i en låg, bred hög (ljusare upptill)."""
    delar = []
    for _ in range(int(rng.integers(7, 12))):
        a = rng.uniform(0, 2 * math.pi); d = rng.uniform(0.0, 0.55)
        r = rng.uniform(0.28, 0.45)
        delar.append(_farga(_klump([math.cos(a) * d, rng.uniform(0.25, 0.6), math.sin(a) * d],
                                   r, r * rng.uniform(0.75, 1.0), r * rng.uniform(0.85, 1.1), rng, jitter=0.22),
                            (70, 106, 50) if rng.random() < 0.6 else (84, 120, 58), rng,
                            variation=0.08, mork_nere=0.4))
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
    """Häckbuske: 3 tussar i en tät, jämnhög klump (få trianglar: häckar är tiotusentals buskar i rad,
    step4 ställer dem tätt så att de flyter ihop). Jämn färg, mörkare nertill."""
    delar = []
    for k in range(3):
        a = 2 * math.pi * k / 3 + rng.uniform(-0.4, 0.4); d = rng.uniform(0.2, 0.35)
        r = rng.uniform(0.42, 0.5)
        delar.append(_farga(_klump([math.cos(a) * d, rng.uniform(0.45, 0.55), math.sin(a) * d],
                                   r, rng.uniform(0.5, 0.58), r, rng, jitter=0.15),
                            (62, 98, 46), rng, variation=0.05, mork_nere=0.4))
    return _normalisera(trimesh.util.concatenate(delar))


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
