"""Idrottsplatser (step3): löparbanor (OSM leisure=track som yta) och läktare.

Löparbanan: tartanytan mellan OSM-banans inre och yttre kant (multipolygon med hål, eller en sluten yta
där innerkanten tas `banor` × 1,22 m in), byggd med strålar från mitten (banor är stjärnformade sett
från mitten), vita banlinjer var 1,22 m ut från innerkanten, en vit innerkant (sarg), en mållinje tvärs
över alla banor i slutet av ena långsidan och startlinjer förskjutna i kurvan. Marken under banan och
6 m utanför plattas till en nivå (`forma`, före heightmap-exporten), så banan ligger plant.
Glb-gruppen `Idrott` (ingen kollision: vagnarna kör på marken).

Läktare: OSM `building=grandstand`, eller ett avlångt hus (minst 25 m långt, högst 16 m djupt) som ligger
längs en löparbana (högst 8 m från dess yttre kant, parallellt inom 20°). Det byggs inte som vanligt
hus utan som en läktare: sittsteg i betong som stiger bakåt från banan, färgade sittrader, gavelväggar,
ryggvägg, pelare och ett tak som skjuter ut över sittplatserna. Glb-gruppen `Byggnader_laktare`
(spelet ger den kollision).
"""
import math
import numpy as np
import trimesh
from rasterio.features import rasterize
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

import planer as planer_mod   # bollplaner och utomhusbad

BANBREDD = 1.22
FARG = {   # sRGB
    'tartan': (168, 66, 52), 'linje': (238, 238, 232), 'sarg': (225, 225, 220),
    'betong': (168, 166, 160), 'sits': (40, 78, 140), 'tak': (200, 202, 205), 'pelare': (90, 92, 96),
    'vagg': (150, 146, 138),
}


def _ar_bana(t):
    sport = t.get('sport', '')
    return t.get('leisure') == 'track' and (
        'athletics' in sport or 'running' in sport or t.get('surface') == 'tartan' or 'lanes' in t or not sport)


def banor_ur(feat, box):
    """[(yttre Polygon, inre Polygon, taggar)] för löparbanor i rutan."""
    ut = []
    for g, t, _id in feat.get('idrottsbanor', []):
        if not _ar_bana(t) or not g.intersects(box):
            continue
        g = max(getattr(g, 'geoms', [g]), key=lambda q: q.area)
        if g.area < 2000:   # inte gropar och små rundor
            continue
        yttre = Polygon(g.exterior)
        if g.interiors:
            inre = Polygon(max(g.interiors, key=lambda r: Polygon(r).area))
        else:
            n = int(t.get('lanes', 6)) if str(t.get('lanes', '6')).isdigit() else 6
            inre = yttre.buffer(-(n * BANBREDD + 0.5))
            if inre.is_empty:
                continue
            inre = max(getattr(inre, 'geoms', [inre]), key=lambda q: q.area)
        ut.append((yttre, inre, t))
    return ut


def _langaxel(poly):
    r = np.array(poly.minimum_rotated_rectangle.exterior.coords)[:4]
    a, b = r[1] - r[0], r[2] - r[1]
    lang, kort = (a, b) if np.hypot(*a) >= np.hypot(*b) else (b, a)
    return lang / np.hypot(*lang), np.hypot(*lang), np.hypot(*kort), r.mean(0)


def ar_laktare(gm, t, banor):
    if t.get('building') == 'grandstand' or t.get('building:use') == 'grandstand':
        return True
    if not banor or gm.area < 60:
        return False
    ax, lang, djup, _ = _langaxel(gm)
    if lang < 25 or djup > 16 or lang < 2.5 * djup:
        return False
    for yttre, _, _ in banor:
        if gm.distance(yttre) > 8:
            continue
        bax, *_ = _langaxel(yttre)
        if abs(float(np.dot(ax, bax))) > math.cos(math.radians(20)):
            return True
    return False


def _srgb2lin(c):
    c = np.asarray(c, float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


class Idrott:
    def __init__(self, feat, box):
        self.banor = banor_ur(feat, box)
        self.laktare = []   # (polygon, taggar, närmaste banans mitt)
        kvar = []
        for gm, t in feat['buildings']:
            if gm.intersects(box) and ar_laktare(gm, t, self.banor):
                mitt = min(self.banor, key=lambda b: gm.distance(b[0]))[0].centroid if self.banor else None
                self.laktare.append((gm, t, mitt))
            else:
                kvar.append((gm, t))
        feat['buildings'] = kvar   # läktarna byggs här, inte som hus
        self.nivaer = []
        import os
        from pathlib import Path
        work = os.environ.get('GEO_WORK')
        self.plan = planer_mod.Planer(feat, box, Path(work).parent / 'data' if work else None)
        print(f'idrott: {len(self.banor)} löparbanor, {len(self.laktare)} läktare')

    def __bool__(self):
        return bool(self.banor or self.laktare or self.plan)

    def ytor(self):
        """Allt som inte ska bli laserhus, buskar eller träd."""
        return [y for y, _, _ in self.banor] + [l.buffer(1.0) for l, _, _ in self.laktare] + self.plan.ytor()

    def tartan(self):
        return [y.difference(i) for y, i, _ in self.banor] + self.plan.harda()

    def planer(self):
        """Innerplanerna (gräsmatta)."""
        return [i for _, i, _ in self.banor] + self.plan.gras()

    def forma(self, h, shape, T, RES):
        """Marken under banan plattas till medianhöjden innanför den: plant 10 m ut, sedan mjukt över
        20 m (Terrain3D:s grova detaljnivåer på avstånd tar annars med högre mark utanför och lägger
        den över banan), och under tartanen 8 cm lägre så att ytan alltid ligger ovanpå."""
        from scipy import ndimage as ndi
        self.plan.forma(h, shape, T, RES)
        for yttre, inre, _ in self.banor:
            inne = rasterize([(yttre.buffer(10.0), 1)], out_shape=shape, transform=T).astype(bool)
            if not inne.any():
                self.nivaer.append(None)
                continue
            under = rasterize([(yttre, 1)], out_shape=shape, transform=T).astype(bool)
            niva = float(np.median(h[under])) if under.any() else float(np.median(h[inne]))
            avst = ndi.distance_transform_edt(~inne) * RES
            vikt = np.clip(1.0 - avst / 20.0, 0.0, 1.0)
            vikt = vikt * vikt * (3 - 2 * vikt)
            h[:] = h * (1 - vikt) + niva * vikt
            ring = rasterize([(yttre.difference(inre.buffer(-1.0)), 1)], out_shape=shape, transform=T).astype(bool)
            h[ring] = niva - 0.08
            self.nivaer.append(niva)

    def mask(self, shape, T):
        if not self:
            return np.zeros(shape, bool)
        return rasterize([(y.buffer(2.0), 1) for y in self.ytor()], out_shape=shape, transform=T).astype(bool)

    # ------------------------------------------------------------------ meshar
    def bygg(self, sample, h, to_world, add_merged, mat, valt=None):
        self.plan.bygg(sample, h, to_world, add_merged, mat, valt)
        m = {k: mat(f'Idrott_{k}', c, 0.85 if k != 'tak' else 0.5) for k, c in FARG.items()}
        for (yttre, inre, t), niva in zip(self.banor, self.nivaer or [None] * len(self.banor)):
            if niva is None:
                niva = float(np.median(sample(h, *np.array(yttre.exterior.coords).T)))
            self._bana(yttre, inre, t, niva, to_world, add_merged, m)
        for gm, t, mitt in self.laktare:
            self._laktare(gm, mitt, sample, h, to_world, add_merged, m)

    @staticmethod
    def _strale(poly, c, ang, R):
        """Avstånd från c längs riktningen ang till polygonens kant (sista skärningen)."""
        d = np.array([math.cos(ang), math.sin(ang)])
        s = LineString([c, c + d * R]).intersection(poly.exterior)
        pts = [q for q in getattr(s, 'geoms', [s]) if not q.is_empty and q.geom_type == 'Point']
        if not pts:
            return None
        return max(Point(c).distance(q) for q in pts)

    def _bana(self, yttre, inre, t, niva, to_world, add_merged, m):
        c = np.array(inre.centroid.coords[0])
        R = math.sqrt(yttre.area) * 3
        n = 720
        V, F = [], []
        y0 = niva + 0.06
        for k in range(n):
            a = 2 * math.pi * k / n
            ri, ry = self._strale(inre, c, a, R), self._strale(yttre, c, a, R)
            if ri is None or ry is None:
                ri = ry = 0.0
            d = np.array([math.cos(a), math.sin(a)])
            for r_ in (ri, max(ry, ri)):
                x, z = to_world(*(c + d * r_)); V.append([x, y0, z])
        for k in range(n):
            a0, b0 = 2 * k, 2 * k + 1
            a1, b1 = 2 * ((k + 1) % n), 2 * ((k + 1) % n) + 1
            F += [[a0, a1, b0], [b0, a1, b1]]
        self._lagg(add_merged, 'Idrott', V, F, m['tartan'])
        # banlinjer: förskjutna innerkanter
        banor = int(t['lanes']) if str(t.get('lanes', '')).isdigit() else \
            max(4, min(9, int(round((math.sqrt(yttre.area) - math.sqrt(inre.area)) / BANBREDD / 1.2))))
        for k in range(1, banor + 1):
            ring = inre.buffer(k * BANBREDD, resolution=24).exterior
            if not yttre.buffer(0.3).contains(ring):
                break
            self._band(ring, 0.05, y0 + 0.01, to_world, add_merged, m['linje'])
        # sargen: en låg vit kant längs innerkanten
        self._band(inre.exterior, 0.10, y0 + 0.06, to_world, add_merged, m['sarg'], sida=0.06)
        # mållinje och startlinjer: tvärs banan i slutet av långsidan (där innerkantens långaxel slutar)
        ax, lang, _, mitt = _langaxel(inre)
        tv = np.array([-ax[1], ax[0]])
        bas = mitt + ax * (lang / 2 - lang * 0.18)
        # mållinjen på läktarens sida om det finns en, annars +tv
        sida = 1.0
        if self.laktare:
            lc = np.array(min(self.laktare, key=lambda l: l[0].distance(yttre))[0].centroid.coords[0])
            sida = 1.0 if np.dot(lc - mitt, tv) > 0 else -1.0
        start = None
        for r_ in np.arange(0, 80, 0.25):
            q = bas + tv * sida * r_
            if not inre.contains(Point(q)):
                start = q
                break
        if start is not None:
            slut = start + tv * sida * banor * BANBREDD
            self._linje(start, slut, 0.05, y0 + 0.012, to_world, add_merged, m['linje'])
            self._linje(start - ax * 0.6, slut - ax * 0.6, 0.05, y0 + 0.012, to_world, add_merged, m['linje'])

    def _band(self, ring, bredd, y, to_world, add_merged, mat, sida=0.0):
        L = LineString(ring.coords)
        n = max(8, int(L.length / 0.8))
        P = np.array([L.interpolate(L.length * k / n).coords[0] for k in range(n)])
        dv = np.roll(P, -1, 0) - np.roll(P, 1, 0)
        dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
        nr = np.c_[-dv[:, 1], dv[:, 0]] * bredd / 2
        A, B = P + nr, P - nr
        V, F = [], []
        for k in range(n):
            for q in (A[k], B[k]):
                x, z = to_world(*q); V.append([x, y, z])
        for k in range(n):
            a0, b0, a1, b1 = 2 * k, 2 * k + 1, 2 * ((k + 1) % n), 2 * ((k + 1) % n) + 1
            F += [[a0, a1, b0], [b0, a1, b1]]
        if sida > 0:   # sidor ned till marken (sargen)
            m0 = len(V)
            for k in range(n):
                for q in (A[k], B[k]):
                    x, z = to_world(*q); V.append([x, y - sida, z])
            for k in range(n):
                k1 = (k + 1) % n
                for o in (0, 1):
                    t0, t1 = 2 * k + o, 2 * k1 + o
                    F += [[t0, m0 + t0, t1], [t1, m0 + t0, m0 + t1]]
        self._lagg(add_merged, 'Idrott', V, F, mat, dubbel=sida > 0)

    def _linje(self, a, b, bredd, y, to_world, add_merged, mat):
        d = (b - a) / max(np.hypot(*(b - a)), 1e-9)
        nr = np.array([-d[1], d[0]]) * bredd / 2
        V = []
        for q in (a + nr, a - nr, b + nr, b - nr):
            x, z = to_world(*q); V.append([x, y, z])
        self._lagg(add_merged, 'Idrott', V, [[0, 2, 1], [1, 2, 3]], mat)

    @staticmethod
    def _lagg(add_merged, grupp, V, F, mat, dubbel=False):
        msh = trimesh.Trimesh(np.array(V, float), np.array(F), process=False)
        if dubbel:
            msh = trimesh.Trimesh(msh.vertices, np.r_[msh.faces, msh.faces[:, ::-1]], process=False)
        elif msh.face_normals[:, 1].mean() < 0:
            msh.faces = msh.faces[:, ::-1]
        add_merged(grupp, msh, mat)

    # ------------------------------------------------------------------ läktare
    def _laktare(self, gm, mitt, sample, h, to_world, add_merged, m):
        ax, lang, djup, c = _langaxel(gm)
        fram = np.array([-ax[1], ax[0]])
        if mitt is not None and np.dot(np.array(mitt.coords[0]) - c, fram) < 0:
            fram = -fram   # fram = mot banan
        ring = np.array(gm.exterior.coords)
        bas = float(np.min(sample(h, ring[:, 0], ring[:, 1])))
        djup = max(5.0, min(djup, 16.0))
        rader = max(4, int((djup - 1.5) / 0.85))
        steg_d, steg_h = (djup - 1.5) / rader, 0.42
        V, F, M = [], [], []

        def lada(cx, cz, bx, bz, y0, y1, mat_):
            """Låda i läktarens egna koordinater (u längs, v bakåt från framkanten)."""
            hor = []
            for du, dv in ((-bx, -bz), (bx, -bz), (bx, bz), (-bx, bz)):
                p = c + ax * (cx + du) - fram * (cz + dv)
                hor.append(to_world(*p))
            b = trimesh.creation.box(extents=(1, 1, 1))
            v = []
            for x_, y_, z_ in b.vertices:
                i = (0 if x_ < 0 else 1) + (0 if z_ < 0 else 2)
                i = [0, 1, 3, 2][i]
                v.append([hor[i][0], y0 if y_ < 0 else y1, hor[i][1]])
            msh = trimesh.Trimesh(np.array(v), b.faces, process=False)
            msh.fix_normals()
            add_merged('Byggnader_laktare', msh, mat_)

        halv = lang / 2
        v_fram = -djup / 2   # framkant i v (v mot baksidan)
        # sittsteg: betongsteg och en sittrad på varje
        for k in range(rader):
            v0 = v_fram + 0.75 + k * steg_d
            topp = bas + 0.6 + (k + 1) * steg_h
            vm = (v0 + djup / 2) / 2
            lada(0, vm, halv, (djup / 2 - v0) / 2, bas, topp, m['betong'])
            lada(0, v0 + steg_d * 0.55, halv - 0.4, 0.22, topp, topp + 0.38, m['sits'])
        # framkant: en låg mur mot banan
        lada(0, v_fram + 0.35, halv, 0.15, bas, bas + 1.1, m['betong'])
        topp = bas + 0.6 + rader * steg_h
        # ryggvägg och gavlar
        lada(0, djup / 2 - 0.15, halv, 0.15, bas, topp + 2.6, m['vagg'])
        for s in (-1, 1):
            lada(s * (halv - 0.15), 0.3, 0.15, djup / 2 - 0.3, bas, topp + 1.0, m['vagg'])
        # pelare längs baksidan och taket (sluttar lätt mot banan, skjuter ut över framkanten)
        tak_bak, tak_fram = topp + 3.6, topp + 2.6
        n_p = max(2, int(lang / 12) + 1)
        for k in range(n_p):
            u = -halv + 0.6 + k * (lang - 1.2) / (n_p - 1)
            lada(u, djup / 2 - 0.6, 0.18, 0.18, bas, tak_bak, m['pelare'])
        tak_d = djup + 1.5
        # taket som en tunn lutande skiva: bygg som låda och luta via vertexhöjder
        hor = []
        for du, dv in ((-halv - 0.5, djup / 2), (halv + 0.5, djup / 2), (halv + 0.5, djup / 2 - tak_d),
                       (-halv - 0.5, djup / 2 - tak_d)):
            hor.append(to_world(*(c + ax * du - fram * dv)))
        yb = [tak_bak, tak_bak, tak_fram, tak_fram]
        Vt = [[hor[i][0], yb[i], hor[i][1]] for i in range(4)] + [[hor[i][0], yb[i] - 0.25, hor[i][1]] for i in range(4)]
        Ft = [[0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6]]
        for i in range(4):
            j = (i + 1) % 4
            Ft += [[i, i + 4, j], [j, i + 4, j + 4]]
        msh = trimesh.Trimesh(np.array(Vt), np.array(Ft), process=False)
        msh.fix_normals()
        add_merged('Byggnader_laktare', msh, m['tak'])
