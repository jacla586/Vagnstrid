"""Gravstenar på kyrkogårdar (step3): rader längs häckarna och familjegravar, ur ortofotot.

Svenska kyrkogårdar har gravarna i rader, oftast med en låg klippt häck bakom stenarna (Matteus och
Norra kyrkogården i Norrköping: raka nord-sydliga rader i kvarter, och bågar runt en mittpunkt). Häckarna
syns i ortofotot som smala mörka gröna linjer i gräset:

  1. mörkt (< MORK_ANDEL av omgivningens ljushet) och grönt (NDVI), minus breda mörka ytor (trädkronor och
     deras skuggor, öppning med en skiva), minus laserns träd (objekthöjd > TRAD_M) och OSM:s gångar;
  2. skelett -> sammanhängande linjer, den längsta vägen genom varje, bara jämna linjer (avståndet mellan
     ändarna / längden >= RAKHET; bågar klarar det, trasiga kronkanter inte) längre än MIN_LINJE_M;
  3. stenarna står på den sida av häcken där fotot har flest ljusa prickar (stenar, grus), STEN_FRAN_HACK_M
     ut, var STEG_M (slumpat), med luckor (LUCKA).

Familjegravar: ljusa grusytor (ljust, inte grönt, 4-60 m², nästan rektangulära) får en kantsten runt om,
grus och en bred sten vid den långsida som ligger längst från närmaste gång.

Stenarna är vältbara (valtbart.py, `Gravsten_<form>_<färg>`; spelets PropBreak, små typer); häckarna blir
segment i work/gravhackar.pkl (step4 lägger dem som häckbuskar), kantsten och grus en sammanslagen mesh i
glb-gruppen `Gravar` (ingen kollision). Former och färger: FORMER, FARGER.
"""
import pickle
import zlib
from collections import deque

import numpy as np
import rasterio
import trimesh
from rasterio.features import rasterize
from rasterio.windows import from_bounds
from scipy import ndimage as ndi
from shapely.geometry import LineString, MultiPoint, Point, Polygon, box
from shapely.ops import unary_union
from skimage.morphology import disk, opening, skeletonize

MORK_ANDEL = 0.72        # häck: mörkare än så här mycket av omgivningens ljushet (gauss 2 m)
GRON_NDVI = 0.15
BRED_M = 1.2             # mörka ytor bredare än så här (radie) är kronor/skuggor, inte häckar
TRAD_M = 2.5             # laserns objekthöjd över så här = träd: inga häckar där
MIN_LINJE_M = 8.0
KRON_AVSTAND_M = 1.5   # häckar inte närmare än så här en bred mörk yta (kronkanternas skuggor)
RAKHET = 0.72
STEN_FRAN_HACK_M = 0.75
STEG_M = (1.2, 1.9)
LUCKA = 0.2
HACK_HOJD_M = 0.7
# familjegravar (grusytor)
GRUS_LJUS = 1.15         # ljusare än omgivningen (gauss 6 m)
GRUS_NDVI = 0.06
GRUS_YTA_M2 = (4.0, 60.0)
GRUS_REKTANGEL = 0.65    # ytan / minsta omslutande rektangel
KANT_B, KANT_H = 0.15, 0.15

FARGER = {'gra': ((128, 128, 126), 0.55), 'svart': ((32, 32, 34), 0.25), 'rod': ((120, 70, 62), 0.5)}
FARG_VIKT = {'gra': 0.45, 'svart': 0.35, 'rod': 0.2}
FORM_VIKT = {'rund': 0.38, 'hog': 0.22, 'lag': 0.18, 'kors': 0.1, 'obelisk': 0.06, 'bred': 0.06}


# ---------- formerna (lokalt: x längs raden, y upp, z genom stenen; foten i origo) ----------

def _platta(kontur, tjock):
    """Konvex kontur i xy (x bredd, y höjd) -> platta tjock i z, centrerad."""
    k = np.asarray(kontur, float)   # konvex kontur: skalet runt fram- och baksidan
    return trimesh.convex.convex_hull(np.vstack([np.c_[k, np.full(len(k), z)] for z in (-tjock / 2, tjock / 2)]))


def _sockel(b, d, h=0.1):
    return trimesh.creation.box(extents=[b, h, d], transform=trimesh.transformations.translation_matrix([0, h / 2, 0]))


def _bage(b, h_axel, h_topp, n=8):
    """Kontur med rundad topp: raka sidor till h_axel, båge till h_topp."""
    a = np.linspace(0, np.pi, n)
    return [(-b / 2, 0.0), (b / 2, 0.0)] + [(b / 2 * np.cos(t), h_axel + (h_topp - h_axel) * np.sin(t)) for t in a]


def form_mesh(form):
    s = 0.1   # sockelns höjd
    if form == 'rund':
        m = _platta(_bage(0.6, 0.62, 0.8), 0.14)
        m.apply_translation([0, s, 0])
        return trimesh.util.concatenate([m, _sockel(0.72, 0.32, s)])
    if form == 'hog':
        m = _platta([(-0.25, 0), (0.25, 0), (0.25, 0.95), (0, 1.12), (-0.25, 0.95)], 0.17)
        m.apply_translation([0, s, 0])
        return trimesh.util.concatenate([m, _sockel(0.62, 0.36, s)])
    if form == 'lag':
        m = _platta([(-0.45, 0), (0.45, 0), (0.42, 0.4), (-0.42, 0.46)], 0.2)
        return m
    if form == 'kors':
        m = trimesh.util.concatenate([_platta([(-0.06, 0), (0.06, 0), (0.06, 0.95), (-0.06, 0.95)], 0.1),
                                      _platta([(-0.28, 0.58), (0.28, 0.58), (0.28, 0.7), (-0.28, 0.7)], 0.1)])
        m.apply_translation([0, s + 0.1, 0])
        fot = trimesh.creation.box(extents=[0.4, 0.2, 0.3], transform=trimesh.transformations.translation_matrix([0, s + 0.1, 0]))
        return trimesh.util.concatenate([m, fot, _sockel(0.5, 0.4, s)])
    if form == 'obelisk':
        b0, b1, h = 0.17, 0.11, 1.2
        P = [(x * b0, 0, z * b0) for x in (-1, 1) for z in (-1, 1)] + \
            [(x * b1, h, z * b1) for x in (-1, 1) for z in (-1, 1)] + [(0, h + 0.18, 0)]
        m = trimesh.convex.convex_hull(np.array(P))
        m.apply_translation([0, s, 0])
        return trimesh.util.concatenate([m, _sockel(0.5, 0.5, s)])
    if form == 'bred':
        m = _platta(_bage(1.2, 0.55, 0.85), 0.2)
        m.apply_translation([0, s, 0])
        return trimesh.util.concatenate([m, _sockel(1.35, 0.4, s)])
    raise ValueError(form)


# ---------- hjälp ----------

def _langsta_vag(pix):
    """pix: (n, 2) skelettpixlar i en komponent -> den längsta vägen (två BFS)."""
    idx = {tuple(p): i for i, p in enumerate(pix)}
    grannar = [[idx[(p[0] + di, p[1] + dj)] for di in (-1, 0, 1) for dj in (-1, 0, 1)
                if (di or dj) and (p[0] + di, p[1] + dj) in idx] for p in pix]

    def bfs(s):
        f = np.full(len(pix), -1)
        f[s] = s
        q, sist = deque([s]), s
        while q:
            u = q.popleft()
            sist = u
            for v in grannar[u]:
                if f[v] < 0:
                    f[v] = u
                    q.append(v)
        return sist, f
    a, _ = bfs(0)
    b, f = bfs(a)
    vag = [b]
    while vag[-1] != a:
        vag.append(f[vag[-1]])
    return pix[vag]


class Gravar:
    def __init__(self, kyrkogardar, orto_mappar, objekt_tif, roads, buildings, work, inne=None):
        """kyrkogardar: [(Polygon SWEREF, taggar, id)]; orto_mappar: ortofoton att pröva i ordning
        (16 cm först); inne(E, N) -> bool (korridorkartor)."""
        self.kyrk = [k for k in kyrkogardar if inne is None or inne(*k[0].centroid.coords[0])]
        self.orto = next((p for p in orto_mappar if p.exists()), None)
        self.objekt = objekt_tif
        self.vagar = [r for r in roads]
        self.hus = buildings
        self.work = work
        self.stenar = []    # (E, N, tx, tn, form, färg)
        self.hackar = []    # [E0, N0, E1, N1, höjd]
        self.familj = []    # (Polygon, stenens E, N, tx, tn)

    def __bool__(self):
        return bool(self.kyrk and self.orto is not None)

    def berakna(self):
        for poly, t, kid in self.kyrk:
            self._en(poly, zlib.crc32(str(kid).encode()))
        print(f'gravar: {len(self.kyrk)} kyrkogårdar, {len(self.stenar)} stenar, {len(self.hackar)} häcksegment, '
              f'{len(self.familj)} familjegravar')
        pickle.dump(dict(segment=np.array(self.hackar, float).reshape(-1, 5)), open(self.work / 'gravhackar.pkl', 'wb'))

    def _en(self, poly, fro):
        rng = np.random.default_rng(fro)
        minx, miny, maxx, maxy = poly.bounds
        minx, miny, maxx, maxy = minx - 4, miny - 4, maxx + 4, maxy + 4
        with rasterio.open(self.orto) as src:
            R = max(0.32, src.res[0])
            W, H = int((maxx - minx) / R), int((maxy - miny) / R)
            a = src.read([1, 2, 3, 4], window=from_bounds(minx, miny, maxx, maxy, src.transform),
                         out_shape=(4, H, W)).astype(np.float32)
        T = rasterio.transform.from_origin(minx, maxy, R, R)
        gray = a[:3].mean(0)
        ndvi = (a[3] - a[0]) / np.maximum(a[3] + a[0], 1)
        trad = np.zeros((H, W), bool)
        if self.objekt and self.objekt.exists():
            with rasterio.open(self.objekt) as src:
                oh = src.read(1, window=from_bounds(minx, miny, maxx, maxy, src.transform), out_shape=(H, W)) / 10.0
            trad = ndi.binary_dilation(oh > TRAD_M, iterations=int(1.0 / R))
        inne = rasterize([(poly.buffer(-1.0), 1)], out_shape=(H, W), transform=T).astype(bool)
        gangar = [r['line'].buffer(r['width'] / 2 + 0.4) for r in self.vagar
                  if r['line'].intersects(poly)]
        stopp = np.zeros((H, W), bool)
        if gangar:
            stopp |= rasterize([(g, 1) for g in gangar], out_shape=(H, W), transform=T).astype(bool)
        hus = [g for g, _ in self.hus if g.intersects(poly)]
        if hus:
            stopp |= rasterize([(g.buffer(0.5), 1) for g in hus], out_shape=(H, W), transform=T).astype(bool)
        px = lambda E, N: (int((maxy - N) / R), int((E - minx) / R))
        sweref = lambda i, j: (minx + (j + 0.5) * R, maxy - (i + 0.5) * R)

        # --- häckarna ---
        loc = ndi.gaussian_filter(gray, 2.0 / R)
        mork = (gray < MORK_ANDEL * loc) & (ndvi > GRON_NDVI)
        bred = opening(mork, disk(max(1, int(BRED_M / R))))
        tunn = mork & ~ndi.binary_dilation(bred, iterations=max(2, int(KRON_AVSTAND_M / R))) & ~trad & inne & ~stopp
        sk = skeletonize(tunn)
        lab, n = ndi.label(sk, structure=np.ones((3, 3)))
        ljus = gray > 1.25 * loc
        for k, sl in enumerate(ndi.find_objects(lab), 1):
            pix = np.argwhere(lab[sl] == k) + [sl[0].start, sl[1].start]
            if len(pix) * R < MIN_LINJE_M:
                continue
            vag = _langsta_vag(pix)
            L = len(vag) * R
            if L < MIN_LINJE_M:
                continue
            pts = np.array([sweref(i, j) for i, j in vag])
            if np.linalg.norm(pts[-1] - pts[0]) / L < RAKHET:
                continue
            ln = LineString(pts).simplify(0.3)
            if ln.length < MIN_LINJE_M:
                continue
            c = np.array(ln.coords)
            for p0, p1 in zip(c[:-1], c[1:]):
                self.hackar.append([p0[0], p0[1], p1[0], p1[1], HACK_HOJD_M])
            # sidan med flest ljusa prickar (stenar)
            sida_n = []
            for sida in (1, -1):
                ant = 0
                for s in np.arange(0.5, ln.length, 1.0):
                    q = np.array(ln.interpolate(s).coords[0])
                    t_ = np.array(ln.interpolate(min(s + 0.5, ln.length)).coords[0]) - np.array(ln.interpolate(max(s - 0.5, 0)).coords[0])
                    t_ /= max(np.linalg.norm(t_), 1e-6)
                    nrm = np.array([-t_[1], t_[0]]) * sida
                    for d in (0.5, 0.9, 1.3):
                        i, j = px(*(q + nrm * d))
                        if 0 <= i < H and 0 <= j < W and ljus[i, j]:
                            ant += 1
                sida_n.append(ant)
            sida = 1 if sida_n[0] >= sida_n[1] else -1
            s = rng.uniform(0.4, 1.0)
            while s < ln.length - 0.3:
                q = np.array(ln.interpolate(s).coords[0])
                t_ = np.array(ln.interpolate(min(s + 0.5, ln.length)).coords[0]) - np.array(ln.interpolate(max(s - 0.5, 0)).coords[0])
                t_ /= max(np.linalg.norm(t_), 1e-6)
                nrm = np.array([-t_[1], t_[0]]) * sida
                p = q + nrm * STEN_FRAN_HACK_M
                i, j = px(*p)
                if rng.random() > LUCKA and 0 <= i < H and 0 <= j < W and not stopp[i, j] and inne[i, j]:
                    form = rng.choice(list(FORM_VIKT), p=np.array(list(FORM_VIKT.values())) / sum(FORM_VIKT.values()))
                    farg = rng.choice(list(FARG_VIKT), p=np.array(list(FARG_VIKT.values())))
                    self.stenar.append((p[0], p[1], t_[0], t_[1], str(form), str(farg)))
                s += rng.uniform(*STEG_M)

        # --- familjegravarna (grus) ---
        loc6 = ndi.gaussian_filter(gray, 6.0 / R)
        grus = (gray > GRUS_LJUS * loc6) & (ndvi < GRUS_NDVI) & inne & ~stopp & ~trad
        grus = ndi.binary_opening(grus, iterations=2)
        glab, gn = ndi.label(grus)
        alla_gangar = unary_union(gangar) if gangar else None
        for k, sl in enumerate(ndi.find_objects(glab), 1):
            pix = np.argwhere(glab[sl] == k) + [sl[0].start, sl[1].start]
            yta = len(pix) * R * R
            if not (GRUS_YTA_M2[0] <= yta <= GRUS_YTA_M2[1]):
                continue
            pts = np.array([sweref(i, j) for i, j in pix])
            rekt = MultiPoint([tuple(p) for p in pts]).minimum_rotated_rectangle
            if rekt.geom_type != 'Polygon' or yta / max(rekt.area, 1e-6) < GRUS_REKTANGEL:
                continue
            c = np.array(rekt.exterior.coords)[:4]
            kanter = [(c[i], c[(i + 1) % 4]) for i in range(4)]
            langa = sorted(kanter, key=lambda e: -np.linalg.norm(e[1] - e[0]))[:2]
            if alla_gangar is not None:
                langa.sort(key=lambda e: -alla_gangar.distance(Point((e[0] + e[1]) / 2)))
            a_, b_ = langa[0]
            mitt = (a_ + b_) / 2
            t_ = (b_ - a_) / max(np.linalg.norm(b_ - a_), 1e-6)
            inat = np.array(rekt.centroid.coords[0]) - mitt
            inat /= max(np.linalg.norm(inat), 1e-6)
            p = mitt + inat * 0.35
            farg = rng.choice(list(FARG_VIKT), p=np.array(list(FARG_VIKT.values())))
            self.familj.append(rekt)
            self.stenar.append((p[0], p[1], t_[0], t_[1], 'bred' if rng.random() < 0.75 else 'hog', str(farg)))

    def bygg(self, sample, h, to_world, add_merged, mat, valt):
        mallar = {}
        for form, farg in {(s[4], s[5]) for s in self.stenar}:
            typ = f'Gravsten_{form}_{farg}'
            rgb, rough = FARGER[farg]
            valt.mall(typ, [(form_mesh(form), mat(f'Granit_{farg}', rgb, rough))])
        for E, N, tE, tN, form, farg in self.stenar:
            wx, wz = to_world(E, N)
            y = float(sample(h, [E], [N])[0]) - 0.03
            valt.placera(f'Gravsten_{form}_{farg}', (wx, y, wz), (tE, -tN))
        if self.familj:
            grus_m, kant_m = mat('Gravgrus', (196, 184, 160), 0.95), mat('Gravkant', (150, 150, 146), 0.6)
            for rekt in self.familj:
                c = np.array(rekt.exterior.coords)[:4]
                y = float(np.min(sample(h, c[:, 0], c[:, 1])))
                V = np.array([[*to_world(*p)] for p in c])
                # gruset: en tunn platta
                yta = trimesh.Trimesh(np.array([[v[0], y + 0.04, v[1]] for v in V]), [[0, 2, 1], [0, 3, 2]], process=False)
                if np.dot(yta.face_normals[0], [0, 1, 0]) < 0:
                    yta.invert()
                add_merged('Gravar', yta, grus_m)
                # kantstenen runt om
                for i in range(4):
                    a_, b_ = V[i], V[(i + 1) % 4]
                    L = float(np.linalg.norm(b_ - a_))
                    d = (b_ - a_) / max(L, 1e-6)
                    M = np.eye(4)
                    M[:3, 0] = [d[0], 0, d[1]]
                    M[:3, 1] = [0, 1, 0]
                    M[:3, 2] = np.cross(M[:3, 0], [0, 1, 0])
                    M[:3, 3] = [(a_[0] + b_[0]) / 2, y + KANT_H / 2 - 0.05, (a_[1] + b_[1]) / 2]
                    add_merged('Gravar', trimesh.creation.box(extents=[L + KANT_B, KANT_H + 0.05, KANT_B], transform=M), kant_m)
