"""Stenläggning (step3): hårdgjorda ytor (plattor, asfalt) som egna meshar inom områden i platsdetaljer.json.

Var: orienteringskartans klass `hardgjord` (okarta.py, 2 m) inom `stenlaggning.omraden`, kanterna putsade
med ortofotot på 1 m (NDVI: grönt är gräs, inte sten). Inte på hus, vatten, vägar (de har egna meshar) eller
i `utom`-rutorna. OSM-parkeringar (amenity=parking, ur <data>/export.osm) blir asfalt med P-platslinjer
(rader med 5 m djupa platser, 2,5 m breda, 6 m gata, längs parkeringens längdriktning), resten betongplattor.
Gång- och cykelvägar och parkeringarnas körgångar (`service=parking_aisle`) som ligger inne i stenläggningen
(`overtackt`) får ingen egen mesh: ytan under dem är stenläggningens.
`berakna` (före markvegetationen) sätter marktäcket till `hårdgjord` (inget gräs växer där, träd får stå);
`bygg` lägger ytorna 6 cm över terrängen i glb-gruppen `Stenlaggning` (ingen kollision; vagnarna kör på
marken). Blå havet (`blahavet`): torget vid Kårallen med blå vågor målade på betongen (zonerna ur ortofotot).
"""
import math

import numpy as np
import rasterio
import trimesh
from PIL import Image, ImageDraw
from rasterio.enums import Resampling
from rasterio.features import rasterize
from scipy import ndimage as ndi
from shapely.geometry import Polygon, box as sbox

LYFT_M = 0.06
CELL_M = 1.0
BLOCK_M = 50.0          # en mesh per block (sammanslagningen delar i 250 m-rutor efter mitten)
OKARTA_HARD = 5         # okarta.KODER['hardgjord']
PLATTA_RUTA_M = 4.8     # texturens storlek
NDVI_GRONT = 0.16
GC = ('cycleway', 'footway', 'path', 'pedestrian')
GRUS_YTOR = ('gravel', 'fine_gravel', 'compacted', 'dirt', 'ground', 'earth', 'sand', 'unpaved', 'grass', 'pebblestone',
             'mud', 'woodchips')
GRONA = dict(landuse=('grass', 'meadow', 'flowerbed', 'village_green', 'forest', 'orchard', 'plant_nursery'),
             natural=('scrub', 'grassland', 'wood', 'heath', 'wetland'), leisure=('garden',))
PLATS_B, PLATS_D, GATA_B = 2.5, 5.0, 6.0   # P-platser: bredd, djup, körgata
LINJE_B = 0.12
ASFALT_LYFT_M = LYFT_M + 0.02   # parkeringarnas asfalt ligger över plattorna i kanten
KRONA_O_M, KRONA_NDVI = 1.5, 0.08   # trädöar på parkeringar: gröna kronor i fotot, krympta med


def _srgb2lin(c):
    c = np.asarray(c, float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _plattor():
    """Betongplattor 0,6 x 0,6 och 1,2 x 0,6 m i förband, grå med variation, mörkare fogar."""
    px = 50   # per meter
    n = int(PLATTA_RUTA_M * px)
    rng = np.random.default_rng(7)
    im = Image.new('RGB', (n, n), (150, 148, 142))
    d = ImageDraw.Draw(im)
    rad_h = int(0.6 * px)
    for r in range(int(PLATTA_RUTA_M / 0.6)):
        y0 = r * rad_h
        x = -(r % 2) * int(0.3 * px)
        while x < n:
            w = int((1.2 if rng.random() < 0.5 else 0.6) * px)
            g = int(rng.normal(168, 9))
            col = (g, g - 2, g - 8)
            for xx in (x, x - n):   # sömlöst över kanten
                d.rectangle([xx + 3, y0 + 3, xx + w - 3, y0 + rad_h - 3], fill=col)
            x += w
    a = np.asarray(im).astype(float)
    a += rng.normal(0, 2.5, a.shape[:2])[..., None]   # ytstruktur
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


class Stenlaggning:
    def __init__(self, conf, work, data_dir, namn):
        self.conf = conf or {}
        self.omraden = [sbox(*r) for r in self.conf.get('omraden', [])]
        self.utom = [sbox(*r) for r in self.conf.get('utom', [])]
        # tvinga: ytor som alltid är sten (där kartan och fotot är gamla, t.ex. en byggplats som blivit torg)
        self.tvinga = [Polygon(t['yta']) for t in self.conf.get('tvinga', [])]
        self.hav = self.conf.get('blahavet')
        self.okarta = work / 'okarta_klass.npy'
        self.ortofoto = data_dir / f'ortofoto_{namn}.tif'
        self.ytor = []   # (E0, N1, mask (nN, nE), asfalt (nN, nE))
        self.havmask = None
        self.osm = data_dir / 'export.osm'
        self.parkeringar = []
        self.p_ytor = []   # (OSM-ytan, asfaltsytan) per parkering
        self.grona, self.grus = [], []   # OSM: aldrig sten (grus blir grus i marktäcket)
        self.overtackta = set()   # id(r) för GC-vägar inne i stenläggningen

    def __bool__(self):
        return bool(self.omraden) and self.okarta.exists() and self.ortofoto.exists()

    # ------------------------------------------------------------------ var
    def _ortho(self, E0, N0, E1, N1, nN, nE):
        with rasterio.open(self.ortofoto) as r:
            w = rasterio.windows.from_bounds(E0, N0, E1, N1, r.transform)
            a = r.read(window=w, out_shape=(r.count, nN, nE), resampling=Resampling.average,
                       boundless=True, fill_value=0).astype(float)
        rgb, nir = a[:3], a[3] if a.shape[0] > 3 else None
        ljus = rgb.mean(0)
        ndvi = (nir - a[0]) / (nir + a[0] + 1e-6) if nir is not None else np.zeros_like(ljus)
        return ljus, ndvi, rgb

    @staticmethod
    def _tradoar(ndvi):
        """Gräsöar under trädkronor (1 m-rutor): gröna fläckar i fotot (NDVI > KRONA_NDVI; lasern ser inte de
        planterade träden: band 1 är oklassade punkter), KRONA_O_M innanför kronans kant (kronorna hänger ut
        över asfalten), öar under 6 m² bort."""
        krona = ndi.binary_opening(ndi.binary_closing(ndvi > KRONA_NDVI, iterations=2), iterations=1)
        o = ndi.distance_transform_edt(krona) * CELL_M > KRONA_O_M
        lab, n = ndi.label(o)
        if n:
            o &= np.isin(lab, 1 + np.nonzero(ndi.sum(o, lab, range(1, n + 1)) >= 6)[0])
        return o

    def _parkeringsytor(self, byggnader, vatten, roads):
        """Parkeringarna som polygoner: OSM-ytan minus hus, vatten, bilvägar (egna meshar), OSM:s gröna ytor och
        grus och trädöarna (_tradoar ur fotot, vektoriserade och rundade). -> [(OSM-ytan, asfaltsytan)]"""
        from rasterio.features import shapes
        from shapely.geometry import shape
        from shapely.ops import unary_union
        bil = [r['line'].buffer(r['width'] / 2) for r in roads if not self._under_sten(r)]
        ut = []
        for g in self.parkeringar:
            E0, N0, E1, N1 = g.bounds
            E0, N0, E1, N1 = math.floor(E0) - 2, math.floor(N0) - 2, math.ceil(E1) + 2, math.ceil(N1) + 2
            nE, nN = int(E1 - E0), int(N1 - N0)
            _, ndvi, _ = self._ortho(E0, N0, E1, N1, nN, nE)
            oar = self._tradoar(ndvi)
            T1 = rasterio.transform.from_origin(E0, N1, CELL_M, CELL_M)
            # öarna rundade: pixeltrapporna bort (förenkla 1 m, sedan rundade hörn)
            hinder = [shape(geo).simplify(1.0).buffer(-1.0).buffer(1.6).buffer(-0.6)
                      for geo, _ in shapes(oar.astype(np.uint8), mask=oar, transform=T1)]
            hinder = [x for x in hinder if not x.is_empty]
            hinder += [b.buffer(0.3) for b in byggnader if b.intersects(g)]
            hinder += [x for x in vatten + self.grona + self.grus + self.utom + bil if x.intersects(g)]
            yta = g.difference(unary_union(hinder)) if hinder else g
            yta = unary_union([p for p in getattr(yta, 'geoms', [yta])
                               if p.geom_type == 'Polygon' and p.area >= 8.0])
            ut.append((g, yta))
        return ut

    def _las_osm(self):
        """Ur OSM inom områdena (SWEREF): parkeringar på marken (asfalt), gröna ytor (gräs, rabatter, häckar,
        snår: aldrig sten) och grus (byggarbetsplatser, grusparkeringar, grusytor och grusgångar: aldrig sten,
        marktäcket blir grus). -> (parkeringar, grona, grus)"""
        if not self.osm.exists():
            return [], [], []
        import xml.etree.ElementTree as ET
        from pyproj import Transformer
        from shapely.geometry import LineString
        t = Transformer.from_crs(4326, 3006, always_xy=True)
        rot = ET.parse(str(self.osm)).getroot()
        noder = {n.get('id'): (float(n.get('lon')), float(n.get('lat'))) for n in rot.iter('node')}
        pk, gron, grus = [], [], []
        for w in rot.iter('way'):
            tg = {x.get('k'): x.get('v') for x in w.findall('tag')}
            ref = [nd.get('ref') for nd in w.findall('nd')]
            if not tg or len(ref) < 2 or any(r not in noder for r in ref):
                continue
            ll = np.array([noder[r] for r in ref])
            E, N = t.transform(ll[:, 0], ll[:, 1])
            sluten = ref[0] == ref[-1] and len(ref) >= 4
            g = Polygon(np.column_stack([E, N])).buffer(0) if sluten else LineString(np.column_stack([E, N]))
            if not any(g.intersects(o) for o in self.omraden):
                continue
            ytan = tg.get('surface', '')
            if tg.get('amenity') == 'parking' and sluten:
                if tg.get('parking') in ('underground', 'multi-storey', 'rooftop'):
                    continue
                if ytan in GRUS_YTOR:
                    grus.append(g)
                elif g.area > 60:
                    pk.append(g)
            elif tg.get('landuse') == 'construction' and sluten:
                grus.append(g)
            elif sluten and (tg.get('landuse') in GRONA['landuse'] or tg.get('natural') in GRONA['natural']
                             or tg.get('leisure') in GRONA['leisure']
                             or (tg.get('leisure') == 'pitch' and ytan == 'grass')):
                gron.append(g)
            elif tg.get('barrier') == 'hedge':
                gron.append(g if sluten else g.buffer(0.6))
            elif 'highway' in tg and ytan in GRUS_YTOR:
                if sluten and tg.get('area') == 'yes' or tg.get('highway') == 'pedestrian' and sluten:
                    grus.append(g)
                elif not sluten:
                    grus.append(g.buffer(1.0))
        return pk, gron, grus

    def raster(self, shape, OX, OY, RES, nagon=False):
        """Heightmapens celler (mitten) som ligger på stenläggningen (bool, shape). `nagon`: celler som stenen
        täcker någon del av (hörnen och mitten provas), t.ex. för att inget gräs ska sticka upp vid kanterna."""
        if nagon:
            ut = np.zeros(shape, bool)
            d = RES / 2 - 0.25
            for dx, dy in ((0, 0), (-d, -d), (-d, d), (d, -d), (d, d)):
                ut |= self.raster(shape, OX + dx, OY + dy, RES)
            return ut
        H, W = shape
        ut = np.zeros(shape, bool)
        ytor_pk = [y for _, y in getattr(self, 'p_ytor', []) if not y.is_empty]
        if ytor_pk:   # parkeringarna: alla celler de nuddar (marken sänks under hela asfalten)
            T = rasterio.transform.from_origin(OX - RES / 2, OY + RES / 2, RES, RES)
            ut |= rasterize([(y, 1) for y in ytor_pk], out_shape=shape, transform=T, all_touched=True).astype(bool)
        for E0, N1, m, _ in getattr(self, 'ytor', []):
            nN, nE = m.shape
            j0, j1 = max(0, int((E0 - OX) / RES)), min(W, int((E0 + nE * CELL_M - OX) / RES) + 1)
            i0, i1 = max(0, int((OY - N1) / RES)), min(H, int((OY - (N1 - nN * CELL_M)) / RES) + 1)
            if j0 >= j1 or i0 >= i1:
                continue
            jj, ii = np.meshgrid(np.arange(j0, j1), np.arange(i0, i1))
            c = ((OX + jj * RES - E0) / CELL_M).astype(int)
            r = ((N1 - (OY - ii * RES)) / CELL_M).astype(int)
            ok = (c >= 0) & (c < nE) & (r >= 0) & (r < nN)
            ut[ii[ok], jj[ok]] = m[r[ok], c[ok]]
        return ut

    def berakna(self, lc, CIDX, to_px, RES, byggnader, vatten, roads):
        if not self:
            return
        ok = np.load(str(self.okarta))
        self.parkeringar, self.grona, self.grus = self._las_osm()
        self.p_ytor = self._parkeringsytor(byggnader, vatten, roads)
        grusandel = np.zeros(lc.shape, float)
        vagar = np.isin(lc, [CIDX['sjö'], CIDX['hav']])
        H, W = lc.shape
        andel = np.zeros(lc.shape, float)
        for omr in self.omraden:
            E0, N0, E1, N1 = omr.bounds
            nE, nN = int(round((E1 - E0) / CELL_M)), int(round((N1 - N0) / CELL_M))
            Ec = E0 + (np.arange(nE) + 0.5) * CELL_M
            Nc = N1 - (np.arange(nN) + 0.5) * CELL_M
            EE, NN = np.meshgrid(Ec, Nc)
            c, r = to_px(EE, NN)
            ci, ri = np.clip(np.round(c).astype(int), 0, W - 1), np.clip(np.round(r).astype(int), 0, H - 1)
            hard = ok[ri, ci] == OKARTA_HARD if ok.shape == lc.shape else np.zeros(EE.shape, bool)
            ljus, ndvi, rgb = self._ortho(E0, N0, E1, N1, nN, nE)
            gront = ndvi > NDVI_GRONT
            # kanterna: i en 2 m-zon runt kartans yta avgör fotot
            inre = ndi.binary_erosion(hard, iterations=2)
            kant = ndi.binary_dilation(hard, iterations=2) & ~inre
            m = inre | (kant & ~gront & (ljus > 70))
            T1 = rasterio.transform.from_origin(E0, N1, CELL_M, CELL_M)
            pk_omr = [(g, y) for g, y in self.p_ytor if g.intersects(omr)]
            # OSM:s gräsytor, rabatter, häckar och grusytor är aldrig sten (orienteringskartan tar ofta med dem)
            inte = [g for g in self.grona + self.grus if g.intersects(omr)]
            if inte:
                m &= ~rasterize([(g, 1) for g in inte], out_shape=m.shape, transform=T1).astype(bool)
            gr = [g for g in self.grus if g.intersects(omr)]
            if gr:
                gm = rasterize([(g, 1) for g in gr], out_shape=m.shape, transform=T1).astype(bool) & hard
                np.add.at(grusandel, (ri[gm], ci[gm]), 1.0)
            if pk_omr:   # parkeringarna är egna polygoner (asfalt): inga plattor helt inne i dem
                inne = [g.buffer(-0.71) for g, _ in pk_omr]
                inne = [g for g in inne if not g.is_empty]
                if inne:
                    m &= ~rasterize([(g, 1) for g in inne], out_shape=m.shape, transform=T1).astype(bool)
            tv = [g for g in self.tvinga if g.intersects(omr)]
            if tv:
                m |= rasterize([(g, 1) for g in tv], out_shape=m.shape, transform=T1).astype(bool)
            hinder = [g.buffer(0.3) for g in byggnader if g.intersects(omr)] + [g for g in vatten if g.intersects(omr)]
            hinder += [g for g in self.utom if g.intersects(omr)]
            if hinder:
                m &= ~rasterize([(g, 1) for g in hinder], out_shape=m.shape, transform=T1).astype(bool)
            m &= ~vagar[ri, ci]
            bilvagar = [r['line'].buffer(r['width'] / 2) for r in roads
                        if not self._under_sten(r) and r['line'].intersects(omr)]
            if bilvagar:   # bilvägarna har egna meshar; GC-vägarna täcks av stenläggningen
                m &= ~rasterize([(g, 1) for g in bilvagar], out_shape=m.shape, transform=T1).astype(bool)
            m = ndi.binary_opening(m, iterations=1)
            lab, n = ndi.label(m)
            if n:
                st = ndi.sum(m, lab, range(1, n + 1))
                m &= np.isin(lab, 1 + np.nonzero(st >= 8)[0])
            self.ytor.append((E0, N1, m, np.zeros(m.shape, bool)))
            np.add.at(andel, (ri[m], ci[m]), 1.0)
            ytor_pk = [y for _, y in pk_omr if not y.is_empty]
            if ytor_pk:   # marktäcket under asfalten
                pa = rasterize([(y, 1) for y in ytor_pk], out_shape=m.shape, transform=T1).astype(bool) & ~m
                np.add.at(andel, (ri[pa], ci[pa]), 1.0)
        # GC-vägar och körgångar på parkeringar som till minst 80 % går i stenläggningen ritas inte själva
        for r in roads:
            if not self._under_sten(r):
                continue
            L = r['line']
            if not any(L.intersects(o) for o in self.omraden):
                continue
            pts = [L.interpolate(d) for d in np.arange(0, L.length + 0.01, 2.0)]
            # på stenen eller inne i en parkering (gräsöarna bryter inte körgångarna)
            andel = np.mean([self.ar_sten(p.x, p.y) or any(g.contains(p) for g in self.parkeringar)
                             for p in pts]) if pts else 0.0
            # körvägar (infarter, körgångar) räcker det att hälften ligger i parkeringen: annars ligger en
            # mörkare stump ovanpå asfalten
            if andel >= (0.5 if r['tags']['highway'] == 'service' else 0.8):
                self.overtackta.add(id(r))
        # marktäcket: celler som till minst hälften är sten
        if 'hårdgjord' in CIDX:
            fyll = andel >= 0.5 * (RES / CELL_M) ** 2
            fyll &= ~np.isin(lc, [CIDX['väg_asfalt'], CIDX['väg_grus'], CIDX['sjö'], CIDX['hav']])
            lc[fyll] = CIDX['hårdgjord']
            # grus: hårdgjort enligt orienteringskartan men grus enligt OSM (byggplatser, grusparkeringar)
            gfyll = (grusandel >= 0.5 * (RES / CELL_M) ** 2) & ~fyll
            gfyll &= ~np.isin(lc, [CIDX['väg_asfalt'], CIDX['sjö'], CIDX['hav']])
            lc[gfyll] = CIDX['väg_grus']
        print('stenläggning:', sum(int(m.sum()) for *_, m, _ in self.ytor), 'm² plattor, asfalt',
              int(sum(y.area for _, y in self.p_ytor)), '; parkeringar', len(self.parkeringar), '; OSM grönt/grus', len(self.grona), len(self.grus),
              '; GC-vägar under stenen', len(self.overtackta))
        if self.hav:
            self._blahavet_zoner()

    def _under_sten(self, r):
        """Vägar som stenläggningen täcker: GC-vägar och körgångar på parkeringarna (service=parking_aisle,
        eller service-väg som till minst 70 % ligger på en parkering)."""
        t = r['tags']
        if t['highway'] in GC:
            return True
        if t['highway'] != 'service':
            return False
        if t.get('service') == 'parking_aisle':
            return True
        L = r['line']
        pa = sum(L.intersection(g).length for g in self.parkeringar if L.intersects(g))
        return L.length > 0 and pa / L.length >= 0.7

    def ar_sten(self, E, N):
        import shapely
        if any(shapely.contains_xy(y, E, N) for _, y in getattr(self, 'p_ytor', [])):
            return True
        for E0, N1, m, _ in self.ytor:
            j, i = int((E - E0) / CELL_M), int((N1 - N) / CELL_M)
            if 0 <= i < m.shape[0] and 0 <= j < m.shape[1] and m[i, j]:
                return True
        return False

    def overtackt(self, r):
        return id(r) in self.overtackta

    def tradfritt(self):
        """(E, N) för celler där träd och buskar inte ska stå (Blå havet: torget byggdes efter laserskanningen)."""
        if self.havmask is None:
            return []
        E0, N0, E1, N1 = self.hav['ruta']
        ii, jj = np.nonzero(self.havmask)
        return list(zip(E0 + (jj + 0.5) * CELL_M, N1 - (ii + 0.5) * CELL_M))

    # ------------------------------------------------------------------ meshar
    def bygg(self, sample, h, to_world, add_merged, mat):
        if not self.ytor:
            return
        platta = trimesh.visual.material.PBRMaterial(name='Stenlaggning', baseColorTexture=_plattor(),
                                                     metallicFactor=0.0, roughnessFactor=0.85)
        asfalt = mat('Stenlaggning_asfalt', (82, 82, 84), 0.9)
        for E0, N1, m, asf in self.ytor:
            nN, nE = m.shape
            blk = int(BLOCK_M / CELL_M)
            for bi in range(0, nN, blk):
                for bj in range(0, nE, blk):
                    for sort, mm in (('platta', m & ~asf), ('asfalt', asf)):
                        sub = mm[bi:bi + blk, bj:bj + blk]
                        if sub.any():
                            msh, uv = self._yta(sub, E0 + bj * CELL_M, N1 - bi * CELL_M, sample, h, to_world,
                                                hel=m, off=(bi, bj))   # grannar: båda ytorna
                            if sort == 'platta':
                                add_merged('Stenlaggning', msh, platta, uv)
                            else:
                                add_merged('Stenlaggning', msh, asfalt)
        for _, y in self.p_ytor:
            if not y.is_empty:
                add_merged('Stenlaggning', self._poly_yta(y, sample, h, to_world, ASFALT_LYFT_M), asfalt)
        if self.hav:
            self._bygg_blahavet(sample, h, to_world, add_merged)
        self._plinjer(sample, h, to_world, add_merged, mat)

    @staticmethod
    def _poly_yta(poly, sample, h, to_world, lyft, steg=2.0):
        """Polygon -> mesh med exakta kanter: delad i steg × steg-rutor (så att den följer terrängen),
        varje bit trianguleras (constrained Delaunay), draperad lyft över terrängen, normalen uppåt."""
        import shapely
        E0, N0, E1, N1 = poly.bounds
        xs = np.arange(math.floor(E0 / steg) * steg, E1, steg)
        ys = np.arange(math.floor(N0 / steg) * steg, N1, steg)
        X, Y = np.meshgrid(xs, ys)
        rutor = shapely.box(X.ravel(), Y.ravel(), X.ravel() + steg, Y.ravel() + steg)
        bitar = shapely.intersection(rutor, poly)
        bitar = shapely.get_parts(bitar[~shapely.is_empty(bitar)])
        bitar = bitar[shapely.get_type_id(bitar) == 3]   # bara polygoner
        tri = shapely.get_parts(shapely.constrained_delaunay_triangles(bitar))
        P = shapely.get_coordinates(tri).reshape(-1, 4, 2)[:, :3]   # triangelns tre hörn (sista = första)
        nyck, inv = np.unique(np.round(P.reshape(-1, 2), 3), axis=0, return_inverse=True)
        y = sample(h, nyck[:, 0], nyck[:, 1]) + lyft
        x, z = to_world(nyck[:, 0], nyck[:, 1])
        msh = trimesh.Trimesh(np.column_stack([x, y, z]), inv.reshape(-1, 3), process=False)
        ned = msh.face_normals[:, 1] < 0
        msh.faces[ned] = msh.faces[ned][:, ::-1]
        return msh

    def _rader_ur_fotot(self, g):
        """Parkeringsradernas riktning och mittlinjer ur ortofotot: tunna ljusa linjer (top-hat), den riktning
        där deras projektion får skarpast toppar. -> (u, v, [v-lägen för mittlinjerna]) eller None."""
        from shapely.geometry import Point
        E0, N0, E1, N1 = g.bounds
        nE, nN = int((E1 - E0) / 0.5), int((N1 - N0) / 0.5)
        if nE < 20 or nN < 20:
            return None
        ljus, ndvi, _ = self._ortho(E0, N0, E1, N1, nN, nE)
        topp = ljus - ndi.grey_opening(ljus, size=(5, 5))
        T1 = rasterio.transform.from_origin(E0, N1, 0.5, 0.5)
        inne = rasterize([(g.buffer(-1.0), 1)], out_shape=ljus.shape, transform=T1).astype(bool)
        sel = inne & (topp > np.percentile(topp[inne], 90)) & (ndvi < NDVI_GRONT) if inne.any() else inne
        if sel.sum() < 50:
            return None
        ii, jj = np.nonzero(sel)
        x = E0 + (jj + 0.5) * 0.5
        y = N1 - (ii + 0.5) * 0.5
        vikt = topp[ii, jj]
        # bara parkeringens två huvudriktningar (±3°): den med tydligast 16 m-period (dubbelrad + gata)
        rekt = np.array(g.minimum_rotated_rectangle.exterior.coords)[:3]
        bas = math.degrees(math.atan2(*(rekt[1] - rekt[0])[::-1]))
        period = 2 * PLATS_D + GATA_B
        bast = None
        for grad in [bas + a + d for a in (0.0, 90.0) for d in (-3, -1.5, 0, 1.5, 3)]:
            t = math.radians(grad)
            vv = -math.sin(t) * x + math.cos(t) * y
            hist, kant = np.histogram(vv, bins=np.arange(vv.min(), vv.max() + 0.5, 0.5), weights=vikt)
            if len(hist) < 2 * period / 0.5:
                continue
            hist = ndi.gaussian_filter1d(hist, 1.0)
            h0 = hist - hist.mean()
            lag = int(period / 0.5)
            mått = float((h0[:-lag] * h0[lag:]).sum() / max((h0 ** 2).sum(), 1e-9))
            if bast is None or mått > bast[0]:
                bast = (mått, t, hist, kant)
        if bast is None or bast[0] < 0.05:
            return None
        _, t, hist, kant = bast
        u = np.array([math.cos(t), math.sin(t)])
        v = np.array([-math.sin(t), math.cos(t)])
        mitt = (kant[:-1] + kant[1:]) / 2
        k5 = int(PLATS_D / 0.5)   # mall: radens bakkanter 5 m på var sida om mittlinjen
        mall = hist.copy()
        mall[k5:] += hist[:-k5]
        mall[:-k5] += hist[k5:]
        toppar = []
        for k in np.argsort(mall)[::-1]:   # mittlinjer: starka toppar minst 12 m isär
            if mall[k] < 0.4 * mall.max():
                break
            if all(abs(mitt[k] - q) >= 12.0 for q in toppar):
                toppar.append(float(mitt[k]))
        toppar = sorted(toppar)
        # luckor: fotot ser inte alla rader (skuggor, bilar); fyll i med radavståndet mellan de funna
        if len(toppar) >= 2:
            d = float(np.median(np.diff(toppar)))
            d = d if 12.0 <= d <= 20.0 else period
            fylld = [toppar[0]]
            for q in toppar[1:]:
                n = int(round((q - fylld[-1]) / d))
                fylld += [fylld[-1] + (q - fylld[-1]) * k / n for k in range(1, n)] if n > 1 else []
                fylld.append(q)
            toppar = fylld
        return u, v, toppar

    def _plinjer(self, sample, h, to_world, add_merged, mat):
        """P-platslinjer. Raderna ur ortofotot (_rader_ur_fotot): en mittlinje per dubbelrad och tvärstreck
        var 2,5 m, 5 m åt var sida; annars rader längs parkeringens längdriktning (5 m platser, 6 m gata)."""
        from shapely.geometry import LineString
        vit = mat('P_linje', (236, 236, 230), 0.6)
        n = 0

        def lagg(a, b, tvars, yta, min_l):
            # klipps mot asfaltsytan: en linje över en gräsö blir två bitar
            seg = LineString([a, b]).intersection(yta)
            k = 0
            for bit in getattr(seg, 'geoms', [seg]):
                if bit.is_empty or bit.geom_type != 'LineString' or bit.length < min_l:
                    continue
                self._linje(np.array(bit.coords[0]), np.array(bit.coords[-1]), tvars, sample, h, to_world,
                            add_merged, vit)
                k += 1
            return k
        for g, asfalt_yta in self.p_ytor:
            yta = asfalt_yta.buffer(-0.4)
            if yta.is_empty:
                continue
            rader = self._rader_ur_fotot(g)
            c = np.array(g.centroid.coords[0])
            ext = math.hypot(g.bounds[2] - g.bounds[0], g.bounds[3] - g.bounds[1])
            if rader and rader[2]:
                u, v, toppar = rader
                for vc in toppar:
                    mitt = v * vc + u * (u @ c)   # punkten på mittlinjen närmast parkeringens mitt
                    n += lagg(mitt - u * ext, mitt + u * ext, v, yta, 4.0)   # mittlinjen
                    for uu in np.arange(-ext, ext, PLATS_B):
                        q = mitt + u * uu
                        n += lagg(q - v * PLATS_D, q + v * PLATS_D, u, yta, PLATS_D)
                continue
            # utan linjer i fotot: rader längs längdriktningen
            rekt = np.array(g.minimum_rotated_rectangle.exterior.coords)[:4]
            k0, k1 = rekt[1] - rekt[0], rekt[2] - rekt[1]
            u_vek, v_vek = (k0, k1) if np.hypot(*k0) >= np.hypot(*k1) else (k1, k0)
            Lu, Lv = np.hypot(*u_vek), np.hypot(*v_vek)
            u, v = u_vek / Lu, v_vek / Lv
            c = rekt.mean(0)
            if Lv < PLATS_D + GATA_B:
                continue
            period = 2 * PLATS_D + GATA_B
            n_mod = max(1, int((Lv + 0.01) // period))
            v_start = -n_mod * period / 2
            for k in range(n_mod):
                b0 = v_start + k * period
                for v0, v1 in ((b0, b0 + PLATS_D), (b0 + PLATS_D + GATA_B, b0 + period)):
                    for uu in np.arange(-Lu / 2, Lu / 2 + 0.01, PLATS_B):
                        n += lagg(c + u * uu + v * v0, c + u * uu + v * v1, u, yta, PLATS_D * 0.8)
        if n:
            print('P-platslinjer:', n)

    @staticmethod
    def _linje(p0, p1, tvars, sample, h, to_world, add_merged, material):
        """En målad linje, delad var 1 m så att den följer terrängen som asfalten (annars sjunker långa
        linjer in under den där marken buktar)."""
        d = tvars * LINJE_B / 2
        n = max(1, int(math.ceil(np.hypot(*(p1 - p0)) / 1.0)))
        t = np.linspace(0.0, 1.0, n + 1)[:, None]
        C = p0 + t * (p1 - p0)
        P = np.vstack([C - d, C + d])   # 0..n vänster, n+1..2n+1 höger
        y = sample(h, P[:, 0], P[:, 1]) + ASFALT_LYFT_M + 0.015
        x, z = to_world(P[:, 0], P[:, 1])
        k = np.arange(n)
        F = np.vstack([np.column_stack([k, k + n + 1, k + n + 2]), np.column_stack([k, k + n + 2, k + 1])])
        msh = trimesh.Trimesh(np.column_stack([x, y, z]), F, process=False)
        ned = msh.face_normals[:, 1] < 0
        msh.faces[ned] = msh.faces[ned][:, ::-1]
        add_merged('Stenlaggning', msh, material)

    @staticmethod
    def _yta(sub, E0, N1, sample, h, to_world, tex_m=PLATTA_RUTA_M, hel=None, off=(0, 0)):
        """Celler -> mesh med delade hörn, draperad över terrängen, normalen uppåt; UV i världen.
        Trappsteg i kanten blir diagonaler: en cell vars två grannar åt ett hörn (t.ex. norr och väster) saknas
        men de motsatta finns får det hörnet avskuret (`hel` = hela masken, så att blockgränserna inte syns)."""
        ii, jj = np.nonzero(sub)
        horn = {}
        V, F = [], []
        M = np.pad(hel if hel is not None else sub, 1)
        oi, oj = (off[0] + 1, off[1] + 1) if hel is not None else (1, 1)

        def hrn(i, j):
            k = (i, j)
            if k not in horn:
                horn[k] = len(V)
                V.append((E0 + j * CELL_M, N1 - i * CELL_M))
            return horn[k]
        for i, j in zip(ii, jj):
            a, b, c, d = hrn(i, j), hrn(i, j + 1), hrn(i + 1, j + 1), hrn(i + 1, j)
            n_, s_ = M[i + oi - 1, j + oj], M[i + oi + 1, j + oj]
            w_, e_ = M[i + oi, j + oj - 1], M[i + oi, j + oj + 1]
            if not n_ and not w_ and s_ and e_:
                F.append([b, d, c])          # nordvästra hörnet bort
            elif not n_ and not e_ and s_ and w_:
                F.append([a, d, c])          # nordöstra
            elif not s_ and not e_ and n_ and w_:
                F.append([a, d, b])          # sydöstra
            elif not s_ and not w_ and n_ and e_:
                F.append([a, c, b])          # sydvästra
            else:
                F += [[a, c, b], [a, d, c]]
        EN = np.array(V)
        y = sample(h, EN[:, 0], EN[:, 1]) + LYFT_M
        x, z = to_world(EN[:, 0], EN[:, 1])
        W3 = np.column_stack([x, y, z])
        F = np.array(F)
        msh = trimesh.Trimesh(W3, F, process=False)
        ned = msh.face_normals[:, 1] < 0
        msh.faces[ned] = msh.faces[ned][:, ::-1]
        uv = np.column_stack([EN[:, 0] / tex_m, EN[:, 1] / tex_m]) if tex_m else None
        return msh, uv

    # ------------------------------------------------------------------ Blå havet
    def _blahavet_zoner(self):
        E0, N0, E1, N1 = self.hav['ruta']
        nE, nN = int(round((E1 - E0) / CELL_M)), int(round((N1 - N0) / CELL_M))
        ljus, ndvi, rgb = self._ortho(E0, N0, E1, N1, nN, nE)
        m = (ndvi < NDVI_GRONT) & (ljus > 90)
        if self.hav.get('scen'):
            s0, t0, s1, t1 = self.hav['scen']
            T1 = rasterio.transform.from_origin(E0, N1, CELL_M, CELL_M)
            m &= ~rasterize([(sbox(s0, t0, s1, t1), 1)], out_shape=m.shape, transform=T1).astype(bool)
        m = ndi.binary_opening(m, iterations=1)
        self.havmask = m
        # zoner i fotot på 0,5 m: blått överskott = målat hav, ljusare band = skum
        n2E, n2N = nE * 2, nN * 2
        _, _, rgb2 = self._ortho(E0, N0, E1, N1, n2N, n2E)
        bla = ndi.gaussian_filter(rgb2[2] - (rgb2[0] + rgb2[1]) / 2, 2.0)
        self.havzon = bla > np.percentile(bla[ndi.zoom(m, 2, order=0)], 45)

    def _bygg_blahavet(self, sample, h, to_world, add_merged):
        if self.havmask is None or not self.havmask.any():
            return
        E0, N0, E1, N1 = self.hav['ruta']
        px = 10   # per meter
        Wt, Ht = int((E1 - E0) * px), int((N1 - N0) * px)
        zon = np.asarray(Image.fromarray(self.havzon.astype(np.uint8) * 255).resize((Wt, Ht), Image.BILINEAR)) > 127
        bas = np.where(zon[..., None], np.array([34, 96, 172]), np.array([118, 172, 214])).astype(float)
        yy, xx = np.mgrid[0:Ht, 0:Wt] / px
        rng = np.random.default_rng(3)
        # vågkammar: böljande linjer (1,3 m mellan), ljusa i djupet, vita i det ljusa bandet
        fas = 2 * math.pi * (yy / 1.3 + 0.35 * np.sin(2 * math.pi * xx / 7.0 + 0.8 * np.sin(2 * math.pi * yy / 11.0)))
        kam = np.cos(fas) > 0.86
        brus = rng.normal(0, 5, bas.shape[:2])[..., None]
        ljus_kam = np.where(zon[..., None], np.array([92, 158, 222]), np.array([214, 232, 244]))
        tex = np.where(kam[..., None], ljus_kam, bas) + brus
        im = Image.fromarray(np.clip(tex, 0, 255).astype(np.uint8))
        material = trimesh.visual.material.PBRMaterial(name='Blahavet', baseColorTexture=im,
                                                       metallicFactor=0.0, roughnessFactor=0.75)
        msh, _ = self._yta(self.havmask, E0, N1, sample, h, to_world, tex_m=None)
        # UV: hela rutan är en textur
        ox, oz = to_world(0.0, 0.0)   # to_world är en förskjutning: x = E + ox, z = oz - N
        E = msh.vertices[:, 0] - ox
        N = oz - msh.vertices[:, 2]
        uv = np.column_stack([(E - E0) / (E1 - E0), (N - N0) / (N1 - N0)])
        add_merged('Stenlaggning', msh, material, uv)
        print('Blå havet:', int(self.havmask.sum()), 'm² målat hav')
