"""Bollplaner och utomhusbad (idrott.py anropar): OSM leisure=pitch (fotboll, tennis) och
leisure=swimming_pool (features.py: 'idrottsplaner', 'bassanger').

Fotboll (sport soccer/football): marken plattas (som löparbanorna), en gräsyta i ränder (klippmönster;
konstgräs mörkare och jämnt), vita linjer efter planens storlek (sidlinjer 1,5 m innanför OSM-ytan,
mittlinje, mittcirkel, straff- och målområden, straffpunkter; skalade på mindre planer), mål vid
kortsidorna (vältbara, `Fotbollsmal`) och belysningsmaster i hörnen på konstgräs eller lit=yes
(`Belysningsmast`).
Tennis: grus (eller hård yta efter surface), linjer för dubbel och singel, nät (`Tennisnat`, vältbart)
och ett 3 m högt nätstängsel runt ytan.
Bad: bassängerna (OSM-ytorna) blir kaklade bassänger med djup efter storlek (stor 1,8 m, mellan 0,9 m,
liten 0,35 m), en klar, halvgenomskinlig vattenyta (eget material, inte sjöarnas shader), simbanor (linjer i botten
och banlinor) i bassänger minst 40 m långa, ett betongdäck BAD_DACK_M runt dem och ett stängsel runt
hela badet. Marken under bassängerna sänks under botten, däcket plattas.
Allt i glb-gruppen `Idrott` (ingen kollision; vagnarna kör på marken), utom vältbara mål, nät och master.
"""
import math

import numpy as np
import rasterio
import rasterio.transform
import trimesh
from rasterio.features import rasterize
from shapely.geometry import Polygon
from shapely.ops import unary_union

FARG = {   # sRGB
    'gras_a': (78, 128, 56), 'gras_b': (66, 112, 48), 'konstgras': (52, 112, 60), 'linje': (240, 240, 236),
    'grus': (176, 92, 62), 'hardplan': (64, 112, 96), 'natstangsel': (60, 66, 62), 'stolpe': (70, 74, 72),
    'dack': (196, 194, 186), 'kakel': (150, 206, 226), 'banlinje': (30, 60, 120), 'mal': (245, 245, 245),
    'mast': (150, 154, 156), 'asfalt': (78, 78, 80), 'fotbollsgrus': (168, 148, 116), 'lampa': (240, 236, 220), 'lina_a': (220, 40, 40), 'lina_b': (240, 240, 240),
}
SIDLINJE_IN_M = 1.5
LINJE_B = 0.12
BAD_DACK_M = 3.5
TENNIS_BANA_B_M = 17.0        # en bana med utrymme runt (bredd); bredare ytor rymmer flera bredvid varandra
PRIVAT_MAX_M2 = 100.0         # bassänger mindre än så (tillsammans): trädgårdspool
STANGSEL_UT_M = 10.0
FOTBOLL_MIN_M2 = 400
TRAD_MAX_ANDEL = 0.2          # mer träd än så (laser) inom en plans OSM-yta: fel läge i OSM, ingen plan
FOTBOLL_MAX_M = (105.0, 68.0)   # fullt mått (FIFA); större OSM-ytor krymps runt mitten


def _rect(poly):
    """(mitt, långaxel, tväraxel, halv längd, halv bredd) ur minsta omslutande rektangeln."""
    r = np.array(poly.minimum_rotated_rectangle.exterior.coords)[:4]
    a, b = r[1] - r[0], r[2] - r[1]
    lang, kort = (a, b) if np.hypot(*a) >= np.hypot(*b) else (b, a)
    ax = lang / np.hypot(*lang)
    return r.mean(0), ax, np.array([-ax[1], ax[0]]), np.hypot(*lang) / 2, np.hypot(*kort) / 2


def _ar_fotboll(t):
    s = t.get('sport', '')
    return 'soccer' in s or ('football' in s and 'american' not in s)


class Flygfoto:
    """Ortofotot (RGB + IR) och laserns objekthöjd för kartan: gräsytor och träd inom en OSM-yta."""

    def __init__(self, data):
        import rasterio
        self.o = rasterio.open(str(next(data.glob('ortofoto_*.tif'))))
        self.l = rasterio.open(str(next(data.glob('objekthojd_*.tif'))))

    def _las(self, poly, pad=2.0):
        from rasterio.windows import from_bounds
        e0, n0, e1, n1 = poly.buffer(pad).bounds
        w = from_bounds(e0, n0, e1, n1, self.o.transform).round_offsets().round_lengths()
        a = self.o.read([1, 4], window=w).astype(np.float32)
        T = self.o.window_transform(w)
        inne = rasterize([(poly, 1)], out_shape=a.shape[1:], transform=T).astype(bool)
        # objekthöjd (m över mark) i ortofotots pixlar
        rr, cc = np.mgrid[0:a.shape[1], 0:a.shape[2]]
        xs, ys = T * (cc + 0.5, rr + 0.5)
        lr, lc = rasterio.transform.rowcol(self.l.transform, xs.ravel(), ys.ravel())
        lw = from_bounds(e0, n0, e1, n1, self.l.transform).round_offsets().round_lengths()
        lh = self.l.read(1, window=lw).astype(np.float32) / 10.0
        lr = np.clip(np.array(lr) - lw.row_off, 0, lh.shape[0] - 1)
        lc = np.clip(np.array(lc) - lw.col_off, 0, lh.shape[1] - 1)
        hojd = lh[lr, lc].reshape(inne.shape)
        ndvi = (a[1] - a[0]) / (a[1] + a[0] + 1.0)
        return ndvi, hojd, inne, T

    def farg(self, poly):
        """(median RGB, median NDVI) inom polygonen."""
        from rasterio.windows import from_bounds
        w = from_bounds(*poly.bounds, self.o.transform).round_offsets().round_lengths()
        a = self.o.read([1, 2, 3, 4], window=w).astype(np.float32)
        inne = rasterize([(poly.buffer(-1.0), 1)], out_shape=a.shape[1:], transform=self.o.window_transform(w)).astype(bool)
        if not inne.any():
            return None, None
        px = a[:, inne]
        return np.median(px[:3], 1), float(np.median((px[3] - px[0]) / (px[3] + px[0] + 1.0)))

    def trad_andel(self, poly):
        _, hojd, inne, _ = self._las(poly, 0.0)
        return float((hojd[inne] > 2.5).mean()) if inne.any() else 0.0

    def grasyta(self, poly):
        return self._storsta_rektangel(poly, gras=True)

    def bar_yta(self, poly):
        """Den största rektangel som ryms i den fria, låga ytan utan växtlighet (grus, asfalt) inom polygonen."""
        return self._storsta_rektangel(poly, gras=False)

    def solbelyst_farg(self, poly):
        """Median-RGB för de ljusare hälften av pixlarna (skuggor från träd bort)."""
        from rasterio.windows import from_bounds
        w = from_bounds(*poly.bounds, self.o.transform).round_offsets().round_lengths()
        a = self.o.read([1, 2, 3], window=w).astype(np.float32)
        inne = rasterize([(poly.buffer(-0.5), 1)], out_shape=a.shape[1:], transform=self.o.window_transform(w)).astype(bool)
        px = a[:, inne]
        if px.shape[1] < 20:
            return None
        lum = px.mean(0)
        return np.median(px[:, lum >= np.median(lum)], 1)

    def _storsta_rektangel(self, poly, gras):
        """Den största rektangel som ryms i den största sammanhängande gräsytan (grönt i IR, även torrt gräs;
        lågt enligt lasern) inom polygonen, riktad som gräsytan; None om för liten."""
        from scipy import ndimage as ndi
        from shapely.geometry import MultiPoint
        ndvi, hojd, inne, T = self._las(poly)
        mask = inne & (hojd < 1.0) & ((ndvi > 0.08) if gras else (ndvi < 0.05))
        gras = ndi.binary_opening(mask, iterations=4)
        lab, n = ndi.label(gras)
        if n == 0:
            return None
        k = np.argmax(ndi.sum(gras, lab, range(1, n + 1))) + 1
        rr, cc = np.nonzero(lab == k)
        if len(rr) < 400:
            return None
        xs, ys = T * (cc + 0.5, rr + 0.5)
        P = np.c_[xs, ys]
        c, ax, tv, _, _ = _rect(MultiPoint(P[::7]).minimum_rotated_rectangle)
        # gräsytans pixlar i rektangelns ram (u längs, v tvärs), 1 m-rutnät
        u = (P - c) @ ax
        v = (P - c) @ tv
        u0, v0 = u.min(), v.min()
        G = np.zeros((int(v.max() - v0) + 2, int(u.max() - u0) + 2), bool)
        G[(v - v0).astype(int), (u - u0).astype(int)] = True
        G = ndi.binary_closing(G, iterations=1)
        # största rektangeln av sanna celler (histogrammetoden)
        hojd_ = np.zeros(G.shape[1], int)
        bast = (0, 0, 0, 0, 0)   # yta, rad, kol0, kol1, höjd
        for r in range(G.shape[0]):
            hojd_ = np.where(G[r], hojd_ + 1, 0)
            stack = []
            for kol in range(len(hojd_) + 1):
                hh = hojd_[kol] if kol < len(hojd_) else 0
                start = kol
                while stack and stack[-1][1] >= hh:
                    s0, sh = stack.pop()
                    yta = sh * (kol - s0)
                    if yta > bast[0]:
                        bast = (yta, r, s0, kol, sh)
                    start = s0
                stack.append((start, hh))
        yta, r, k0, k1, hh = bast
        if yta < 400:
            return None
        ua, ub = u0 + k0 + 0.5, u0 + k1 - 0.5
        va, vb = v0 + (r - hh + 1) + 0.5, v0 + r + 0.5
        rekt = Polygon([c + ax * uu + tv * vv for uu, vv in ((ua, va), (ub, va), (ub, vb), (ua, vb))])
        return rekt if rekt.area > 0.35 * poly.area else None


class Planer:
    def __init__(self, feat, box, data=None):
        self.foto = None
        if data is not None and any(data.glob('ortofoto_*.tif')) and any(data.glob('objekthojd_*.tif')):
            self.foto = Flygfoto(data)
        self.fotboll, self.tennis = [], []
        for g, t, wid in feat.get('idrottsplaner', []):
            if not g.intersects(box) or g.geom_type != 'Polygon':
                continue
            if _ar_fotboll(t) and g.area >= FOTBOLL_MIN_M2:
                namn = t.get('name') or wid
                if self.foto is not None and self.foto.trad_andel(g) > TRAD_MAX_ANDEL:
                    print(f'planer: {namn}: träd på {self.foto.trad_andel(g):.0%} av OSM-ytan (fel läge i OSM), hoppar över')
                    continue
                stor = g.area / g.minimum_rotated_rectangle.area < 0.9 or max(_rect(g)[3:]) * 2 > FOTBOLL_MAX_M[0] + 7
                if stor and self.foto is not None and t.get('surface') not in ('artificial_turf', 'asphalt', 'gravel'):
                    ny = self.foto.grasyta(g)
                    if ny is not None:
                        print(f'planer: {namn}: anpassad efter flygfotot ({g.area:.0f} -> {ny.area:.0f} m²)')
                        g = ny
                rekt = _rect(g)
                c, ax, tv, hl, hb = rekt
                if 2 * hl > FOTBOLL_MAX_M[0] + 2 * SIDLINJE_IN_M + 4 or 2 * hb > FOTBOLL_MAX_M[1] + 2 * SIDLINJE_IN_M + 4:
                    # OSM-ytan tar ofta med gräset runt planen: planen i mitten, högst fullt mått
                    hl = min(hl, FOTBOLL_MAX_M[0] / 2 + SIDLINJE_IN_M)
                    hb = min(hb, FOTBOLL_MAX_M[1] / 2 + SIDLINJE_IN_M)
                    rekt = (c, ax, tv, hl, hb)
                    g = Polygon([c + ax * su * hl + tv * sv * hb for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
                self.fotboll.append(dict(poly=g, t=t, id=wid, rekt=rekt, yta=self._fotbollsyta(g, t)))
            elif 'tennis' in t.get('sport', ''):
                if self.foto is not None and (g.area / g.minimum_rotated_rectangle.area < 0.9 or g.area > 900):
                    ny = self.foto.bar_yta(g)   # OSM-ytan tar med omgivningen: banorna på den fria ytan
                    if ny is not None and ny.area > 300:
                        print(f'planer: tennis {wid}: anpassad efter flygfotot ({g.area:.0f} -> {ny.area:.0f} m²)')
                        g = ny
                rekt = _rect(g)
                lang, bred = 2 * rekt[3], 2 * rekt[4]
                antal = max(1, int(round(bred / TENNIS_BANA_B_M))) if lang >= 28 else 1
                if lang < 30 or bred < antal * 16:   # bara spelytan i OSM (24 x 11 m): ytan runt med
                    c_, ax_, tv_ = rekt[:3]
                    rekt = (c_, ax_, tv_, max(rekt[3], 18.0), max(rekt[4], antal * 8.6))
                    g = Polygon([c_ + ax_ * su * rekt[3] + tv_ * sv * rekt[4]
                                 for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
                    lang, bred = 2 * rekt[3], 2 * rekt[4]
                hard = t.get('surface') in ('asphalt', 'concrete', 'acrylic', 'hard', 'paved', 'tartan')
                if t.get('surface') in (None, 'clay') and self.foto is not None:   # rödgrus eller hård (grön/grå)
                    rgb = self.foto.solbelyst_farg(g)
                    hard = rgb is not None and not (rgb[0] > rgb[1] + 8 and rgb[0] > rgb[2] + 15)
                if t.get('surface') == 'clay':
                    hard = False
                print(f"planer: tennis {wid}: {antal} {'bana' if antal == 1 else 'banor'}, {'hård' if hard else 'grus'}, "
                      f"{lang:.0f} x {bred:.0f} m")
                self.tennis.append(dict(poly=g, t=t, id=wid, rekt=rekt, hard=hard, antal=antal))
        self.bassanger = [dict(poly=g, t=t, id=wid) for g, t, wid in feat.get('bassanger', [])
                          if g.intersects(box) and g.geom_type == 'Polygon' and g.area >= 20]
        for b in self.bassanger:
            a = b['poly'].area
            b['djup'] = 1.8 if a > 400 else (0.9 if a > 120 else 0.35)
            b['rund'] = b['poly'].area / b['poly'].minimum_rotated_rectangle.area < 0.86
        # bad: bassänger närmare än 25 m varandra är ett bad
        self.bad = []
        for b in self.bassanger:
            for bad in self.bad:
                if any(b['poly'].distance(o['poly']) < 25 for o in bad['bassanger']):
                    bad['bassanger'].append(b)
                    break
            else:
                self.bad.append(dict(bassanger=[b]))
        for bad in self.bad:
            u = unary_union([b['poly'] for b in bad['bassanger']])
            bad['privat'] = u.area < PRIVAT_MAX_M2   # en trädgårdspool: smalt däck, inget stängsel
            if bad['privat']:
                for b in bad['bassanger']:
                    b['djup'] = 1.4
            bad['dack'] = u.buffer(0.8 if bad['privat'] else BAD_DACK_M, join_style=2)
            bad['stangsel'] = u.convex_hull.buffer(1.0 if bad['privat'] else STANGSEL_UT_M, join_style=2)
        self.nivaer = {}
        for f in self.fotboll:
            L, B = f['rekt'][3] * 2, f['rekt'][4] * 2
            print(f"planer: fotboll {f['t'].get('name', f['id'])} {L:.0f} x {B:.0f} m ({f['t'].get('surface', 'gräs')})")
        for b in self.bassanger:
            _, _, _, hl, hb = _rect(b['poly'])
            print(f"planer: bassäng {2 * hl:.1f} x {2 * hb:.1f} m{' (rund)' if b['rund'] else ''}, djup {b['djup']} m")
        print(f'planer: {len(self.fotboll)} fotbollsplaner, {len(self.tennis)} tennisbanor, {len(self.bad)} bad')

    def _fotbollsyta(self, g, t):
        """'konst', 'asfalt', 'grus' eller 'gras': OSM:s surface, annars flygfotot (inget växer = grus)."""
        yta = t.get('surface', '')
        if yta == 'artificial_turf':
            return 'konst'
        if yta in ('asphalt', 'concrete', 'paved'):
            return 'asfalt'
        if yta in ('gravel', 'fine_gravel', 'sand', 'dirt', 'ground', 'compacted', 'clay'):
            return 'grus'
        if self.foto is not None:
            rgb, ndvi = self.foto.farg(g)
            if ndvi is not None and ndvi < 0.0:   # torrt sommargräs ligger kring 0,03, grus -0,2
                print(f"planer: {t.get('name') or ''}: inget växer i flygfotot (NDVI {ndvi:.2f}), grusplan")
                return 'grus'
        return 'gras'

    def __bool__(self):
        return bool(self.fotboll or self.tennis or self.bad)

    # ------------------------------------------------------------ till step3
    def ytor(self):
        """Inga laserhus, träd eller buskar här."""
        return ([f['poly'] for f in self.fotboll] + [t['poly'].buffer(1.0) for t in self.tennis]
                + [b['stangsel'] for b in self.bad])

    def harda(self):
        """Ytor utan växtlighet: tennisbanor och badets däck och bassänger."""
        return [t['poly'] for t in self.tennis] + [b['dack'] for b in self.bad]

    def gras(self):
        """Klippt gräs: fotbollsplanerna."""
        return [f['poly'] for f in self.fotboll]

    def forma(self, h, shape, T, RES):
        from scipy import ndimage as ndi
        ytor = [('f', i, f['poly']) for i, f in enumerate(self.fotboll)] + \
               [('t', i, t['poly']) for i, t in enumerate(self.tennis)] + \
               [('b', i, b['dack']) for i, b in enumerate(self.bad)]
        for typ, i, poly in ytor:
            inne = rasterize([(poly.buffer(3.0), 1)], out_shape=shape, transform=T).astype(bool)
            if not inne.any():
                continue
            under = rasterize([(poly, 1)], out_shape=shape, transform=T).astype(bool)
            niva = float(np.median(h[under])) if under.any() else float(np.median(h[inne]))
            avst = ndi.distance_transform_edt(~inne) * RES
            vikt = np.clip(1.0 - avst / 10.0, 0.0, 1.0)
            vikt = vikt * vikt * (3 - 2 * vikt)
            h[:] = h * (1 - vikt) + niva * vikt
            self.nivaer[(typ, i)] = niva
            if typ == 'b':   # bassängerna: marken under botten (och en cell utanför, under däcket)
                for b in self.bad[i]['bassanger']:
                    m = rasterize([(b['poly'].buffer(1.0), 1)], out_shape=shape, transform=T).astype(bool)
                    h[m] = np.minimum(h[m], niva - b['djup'] - 0.4)

    # ------------------------------------------------------------ meshar
    def bygg(self, sample, h, to_world, add_merged, mat, valt=None):
        if not self:
            return
        m = {k: mat(f'Plan_{k}', c, 0.9) for k, c in FARG.items()}
        m['natstangsel'] = trimesh.visual.material.PBRMaterial(
            name='Plan_natstangsel', baseColorFactor=[0.24, 0.27, 0.25, 0.45], alphaMode='BLEND',
            doubleSided=True, roughnessFactor=0.8)
        m['nat'] = trimesh.visual.material.PBRMaterial(
            name='Plan_nat', baseColorFactor=[0.92, 0.92, 0.92, 0.4], alphaMode='BLEND', doubleSided=True,
            roughnessFactor=0.9)
        # bassängvatten: klart och ljust över kaklet (sjöarnas vattenshader gör djupa bassänger mörka)
        m['vatten'] = trimesh.visual.material.PBRMaterial(
            name='Vatten_bassang', baseColorFactor=[0.32, 0.72, 0.86, 0.5], alphaMode='BLEND', metallicFactor=0.0,
            roughnessFactor=0.05, doubleSided=False)
        if valt is not None:
            self._mallar(valt, m)

        def niva(typ, i, poly):
            v = self.nivaer.get((typ, i))
            return v if v is not None else float(np.median(sample(h, *np.array(poly.exterior.coords).T)))
        for i, f in enumerate(self.fotboll):
            self._fotboll(f, niva('f', i, f['poly']), to_world, add_merged, m, valt)
        for i, t in enumerate(self.tennis):
            self._tennis(t, niva('t', i, t['poly']), to_world, add_merged, m, valt)
        # nätstängsel runt varje grupp av banor (banor kant i kant delar stängsel)
        if self.tennis:
            u = unary_union([t['poly'].buffer(0.05) for t in self.tennis])
            for i_g, grupp in enumerate(getattr(u, 'geoms', [u])):
                nv = float(np.median(sample(h, *np.array(grupp.exterior.coords).T)))
                ring = np.array(grupp.exterior.coords)
                V, F = [], []
                for k in range(len(ring) - 1):
                    base = len(V)
                    for r_ in (ring[k], ring[k + 1]):
                        x, z = to_world(*r_)
                        V += [[x, nv - 0.3, z], [x, nv + 3.0, z]]
                    F += [[base, base + 2, base + 3], [base, base + 3, base + 1]]
                add_merged('Idrott', trimesh.Trimesh(np.array(V), np.array(F), process=False), m['natstangsel'])
        for i, b in enumerate(self.bad):
            self._bad(b, niva('b', i, b['dack']), to_world, add_merged, m)

    # hjälp: lokala koordinater (u längs, v tvärs) -> världen
    @staticmethod
    def _lokal(rekt):
        c, ax, tv, _, _ = rekt
        return lambda u, v: c + ax * u + tv * v

    def _quad(self, P, y, to_world, add_merged, mat, grupp='Idrott', uv=None):
        V = []
        for q in P:
            x, z = to_world(*q)
            V.append([x, y, z])
        msh = trimesh.Trimesh(np.array(V), np.array([[0, 1, 2], [0, 2, 3]]), process=False)
        if msh.face_normals[:, 1].mean() < 0:
            msh.faces = msh.faces[:, ::-1]
        add_merged(grupp, msh, mat)

    def _linje(self, L, a, b, bredd, y, to_world, add_merged, mat):
        a, b = L(*a), L(*b)
        d = (b - a) / max(np.hypot(*(b - a)), 1e-9)
        n = np.array([-d[1], d[0]]) * bredd / 2
        self._quad([a + n, b + n, b - n, a - n], y, to_world, add_merged, mat)

    def _bage(self, L, cu, cv, r, a0, a1, y, to_world, add_merged, mat, n=24):
        ang = np.linspace(a0, a1, n + 1)
        for k in range(n):
            self._linje(L, (cu + r * math.cos(ang[k]), cv + r * math.sin(ang[k])),
                        (cu + r * math.cos(ang[k + 1]), cv + r * math.sin(ang[k + 1])), LINJE_B, y, to_world,
                        add_merged, mat)

    def _fotboll(self, f, niva, to_world, add_merged, m, valt):
        rekt = f['rekt']
        L = self._lokal(rekt)
        hl, hb = rekt[3], rekt[4]
        yta = f.get('yta', 'gras')
        konst = yta == 'konst'
        y = niva + 0.04
        # yta: ränder tvärs över (klippmönster), konstgräs jämnt
        n = max(2, int(round(2 * hl / 6.0)))
        for k in range(n):
            u0, u1 = -hl + 2 * hl * k / n, -hl + 2 * hl * (k + 1) / n
            mt = {'konst': m['konstgras'], 'asfalt': m['asfalt'], 'grus': m['fotbollsgrus']}.get(
                yta, m['gras_a'] if k % 2 == 0 else m['gras_b'])
            self._quad([L(u0, -hb), L(u1, -hb), L(u1, hb), L(u0, hb)], y, to_world, add_merged, mt)
        yl = y + 0.015
        a, b = hl - SIDLINJE_IN_M, hb - SIDLINJE_IN_M
        sk = min(1.0, (2 * b) / 68.0)   # mindre planer: skalade områden
        for p, q in (((-a, -b), (a, -b)), ((a, -b), (a, b)), ((a, b), (-a, b)), ((-a, b), (-a, -b)), ((0, -b), (0, b))):
            self._linje(L, p, q, LINJE_B, yl, to_world, add_merged, m['linje'])
        self._bage(L, 0, 0, 9.15 * sk, 0, 2 * math.pi, yl, to_world, add_merged, m['linje'], 36)
        for s in (1, -1):
            ex = s * a
            for djup, bredd in ((16.5 * sk, 40.32 * sk), (5.5 * sk, 18.32 * sk)):
                bredd = min(bredd, 2 * b - 2)
                inn = ex - s * djup
                for p, q in (((ex, -bredd / 2), (inn, -bredd / 2)), ((inn, -bredd / 2), (inn, bredd / 2)),
                             ((inn, bredd / 2), (ex, bredd / 2))):
                    self._linje(L, p, q, LINJE_B, yl, to_world, add_merged, m['linje'])
            spot = ex - s * 11.0 * sk
            self._linje(L, (spot - 0.12, 0), (spot + 0.12, 0), 0.24, yl, to_world, add_merged, m['linje'])
            # straffområdets båge
            r = 9.15 * sk
            d = 16.5 * sk - 11.0 * sk
            if r > d:
                v = math.acos(d / r)
                mitt = math.pi if s > 0 else 0.0
                self._bage(L, spot, 0, r, mitt - v, mitt + v, yl, to_world, add_merged, m['linje'], 12)
        if valt is None:
            return
        for s in (1, -1):   # mål: x mot planens mitt, nätet bakom
            q = L(s * a, 0)
            inat = -rekt[1] * s
            x, z = to_world(*q)
            w = np.array(to_world(q[0] + inat[0], q[1] + inat[1])) - np.array([x, z])
            valt.placera('Fotbollsmal', [x, niva, z], w)
        if konst or f['t'].get('lit') == 'yes':
            for su in (1, -1):
                for sv in (1, -1):
                    q = L(su * (hl + 3.0), sv * (hb + 3.0))
                    x, z = to_world(*q)
                    mitt = np.array(to_world(*rekt[0]))
                    valt.placera('Belysningsmast', [x, niva, z], mitt - np.array([x, z]))

    def _tennis(self, t, niva, to_world, add_merged, m, valt):
        rekt = t['rekt']
        L = self._lokal(rekt)
        hl, hb = rekt[3], rekt[4]
        hard = t.get('hard', False)
        y = niva + 0.05
        self._quad([L(-hl, -hb), L(hl, -hb), L(hl, hb), L(-hl, hb)], y, to_world, add_merged,
                   m['hardplan'] if hard else m['grus'])
        yl = y + 0.012
        a, bd, bs, serv = 23.77 / 2, 10.97 / 2, 8.23 / 2, 6.40
        n = t.get('antal', 1)
        mitter = [(-hb + 2 * hb * (k + 0.5) / n) for k in range(n)]   # banorna bredvid varandra (tvärs)
        for vm in mitter:
            for p, q in (((-a, -bd), (a, -bd)), ((-a, bd), (a, bd)), ((-a, -bd), (-a, bd)), ((a, -bd), (a, bd)),
                         ((-a, -bs), (a, -bs)), ((-a, bs), (a, bs)), ((-serv, -bs), (-serv, bs)),
                         ((serv, -bs), (serv, bs)), ((-serv, 0), (serv, 0))):
                self._linje(L, (p[0], p[1] + vm), (q[0], q[1] + vm), 0.06, yl, to_world, add_merged, m['linje'])
        if valt is not None:
            for vm in mitter:
                q = L(0, vm)
                x, z = to_world(*q)
                w = np.array(to_world(q[0] + rekt[1][0], q[1] + rekt[1][1])) - np.array([x, z])
                valt.placera('Tennisnat', [x, niva + 0.05, z], w)

    def _bad(self, bad, niva, to_world, add_merged, m):
        yd = niva + 0.05
        # däck: ytan runt bassängerna (triangulerad, hål för bassängerna)
        dack = bad['dack'].difference(unary_union([b['poly'] for b in bad['bassanger']]))
        self._polygon(dack, yd, to_world, add_merged, m['dack'])
        for b in bad['bassanger']:
            p = b['poly']
            golv = niva - b['djup']
            self._polygon(p, golv, to_world, add_merged, m['kakel'])
            # väggar (insidan), ned till botten
            ring = np.array(p.exterior.coords)
            V, F = [], []
            for k in range(len(ring) - 1):
                base = len(V)
                for r_ in (ring[k], ring[k + 1]):
                    x, z = to_world(*r_)
                    V += [[x, golv, z], [x, yd, z]]
                tri = [[base, base + 2, base + 3], [base, base + 3, base + 1]]
                # normalen in mot bassängens mitt
                mitt = np.array(to_world(*np.array(p.centroid.coords[0])))
                pa, pb, pc = np.array(V[base]), np.array(V[base + 2]), np.array(V[base + 3])
                n_ = np.cross(pb - pa, pc - pa)
                ut = np.array([pa[0] - mitt[0], 0.0, pa[2] - mitt[1]])
                if np.dot(n_, ut) > 0:
                    tri = [[base, base + 3, base + 2], [base, base + 1, base + 3]]
                F += tri
            add_merged('Idrott', trimesh.Trimesh(np.array(V), np.array(F), process=False), m['kakel'])
            # vattenyta (spelets vattenshader: gruppen Vattendrag)
            self._polygon(p, yd - 0.15, to_world, add_merged, m['vatten'])
            # simbanor i långa bassänger
            c, ax, tv, hl, hb = _rect(p)
            if 2 * hl >= 40 and not b['rund']:
                L = self._lokal((c, ax, tv, hl, hb))
                n = max(4, min(10, int(2 * hb / 2.5)))
                for k in range(1, n):
                    v = -hb + 2 * hb * k / n
                    self._linje(L, (-hl + 2.0, v - 1.25 + 1.25), (hl - 2.0, v), 0.25, golv + 0.01, to_world,
                                add_merged, m['banlinje'])
                    for j, u0 in enumerate(np.arange(-hl + 0.3, hl - 0.3, 1.0)):   # banlinor på ytan
                        self._linje(L, (u0, v), (u0 + 0.9, v), 0.12, yd - 0.12, to_world, add_merged,
                                    m['lina_a'] if (j // 5) % 2 == 0 else m['lina_b'])
        if bad['privat']:
            return
        # stängsel runt badet
        ring = np.array(bad['stangsel'].exterior.coords)
        V, F = [], []
        for k in range(len(ring) - 1):
            base = len(V)
            for r_ in (ring[k], ring[k + 1]):
                x, z = to_world(*r_)
                V += [[x, niva - 0.5, z], [x, niva + 1.8, z]]
            F += [[base, base + 2, base + 3], [base, base + 3, base + 1]]
        add_merged('Idrott', trimesh.Trimesh(np.array(V), np.array(F), process=False), m['natstangsel'])

    def _polygon(self, poly, y, to_world, add_merged, mat, grupp='Idrott'):
        """Plan polygon (med hål) på höjden y, normalen uppåt."""
        for g in getattr(poly, 'geoms', [poly]):
            if g.is_empty or g.area < 0.5:
                continue
            import shapely
            tris = [t_ for t_ in shapely.constrained_delaunay_triangles(g).geoms if g.contains(t_.centroid)]
            if not tris:
                continue
            V = []
            for t_ in tris:
                for q in list(t_.exterior.coords)[:3]:
                    x, z = to_world(*q)
                    V.append([x, y, z])
            F = np.arange(len(V)).reshape(-1, 3)
            msh = trimesh.Trimesh(np.array(V), F, process=False)
            up = msh.face_normals[:, 1] < 0
            msh.faces[up] = msh.faces[up][:, ::-1]
            add_merged(grupp, msh, mat)

    def _mallar(self, valt, m):
        from jarnvag import ladar
        from valtbart import lador_mesh

        def lada(cx, cz, hx, hz, y0, y1):
            return lador_mesh(ladar([[cx, cz]], [[1.0, 0.0]], hx, hz, y0, y1), botten=True)
        cat = trimesh.util.concatenate
        if not valt.har_mall('Fotbollsmal'):   # x mot planen, nätet bakom (-x)
            ram = cat([lada(0, z, 0.06, 0.06, 0, 2.44) for z in (-3.72, 3.72)] + [lada(0, 0, 0.06, 3.78, 2.38, 2.5)])
            bak = cat([lada(-1.8, z, 0.03, 0.03, 0, 1.0) for z in (-3.72, 3.72)] + [lada(-1.8, 0, 0.03, 3.75, 0, 0.06)]
                      + [lada(-0.9, z, 0.9, 0.02, 2.4, 2.44) for z in (-3.72, 3.72)])
            nat = cat([_plan([(0, 2.44, -3.72), (0, 2.44, 3.72), (-1.8, 0.9, 3.72), (-1.8, 0.9, -3.72)]),
                       _plan([(-1.8, 0.9, -3.72), (-1.8, 0.9, 3.72), (-1.8, 0, 3.72), (-1.8, 0, -3.72)]),
                       _plan([(0, 2.44, -3.72), (-1.8, 0.9, -3.72), (-1.8, 0, -3.72), (0, 0, -3.72)]),
                       _plan([(0, 2.44, 3.72), (-1.8, 0.9, 3.72), (-1.8, 0, 3.72), (0, 0, 3.72)])])
            valt.mall('Fotbollsmal', [(ram, m['mal']), (bak, m['stolpe']), (nat, m['nat'])])
        if not valt.har_mall('Belysningsmast'):   # x mot planen: lamporna lutar ditåt
            valt.mall('Belysningsmast', [(lada(0, 0, 0.18, 0.18, -0.5, 18.0), m['mast']),
                                         (lada(0.25, 0, 0.12, 1.4, 17.2, 18.4), m['stolpe']),
                                         (lada(0.39, 0, 0.03, 1.3, 17.3, 18.3), m['lampa'])])
        if not valt.har_mall('Tennisnat'):   # x längs banan, nätet tvärs (z)
            valt.mall('Tennisnat', [(cat([lada(0, z, 0.04, 0.04, 0, 1.07) for z in (-6.4, 6.4)]), m['stolpe']),
                                    (lada(0, 0, 0.02, 6.4, 0.85, 0.92), m['mal']),
                                    (_plan([(0, 0.88, -6.4), (0, 0.88, 6.4), (0, 0.05, 6.4), (0, 0.05, -6.4)]), m['nat'])])


def _plan(P):
    """En fyrhörning (lokala x, y, z), dubbelsidig (nät)."""
    V = np.array(P, float)
    return trimesh.Trimesh(V, np.array([[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]]), process=False)
