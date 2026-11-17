"""Byggnader ur objekthöjdsrastret (band 1 = höjd över mark i dm, band 2 = flerekoandel i %).

Tak är höga ytor där nästan alla laserpunkter är sista ekot (låg flerekoandel), till skillnad
från trädkronor där pulsen delar sig. Allt i SWEREF 99 TM.
"""
import numpy as np, rasterio
from pathlib import Path
from rasterio.features import shapes, geometry_mask
from scipy import ndimage as ndi
from shapely.geometry import shape

MIN_H = 2.5          # m över mark
MAX_FRAC = 20.0      # utjämnad flerekoandel, %
MIN_AREA = 25.0      # m²
MAX_H = 25.0         # högre än så är nästan alltid träd (silos undantagna, få här)
MIN_FILL = 0.55      # yta / omskrivande rektangel; trädklumpar blir oregelbundna
MAX_ROUGH = 0.35     # m, median av |h - 3x3-median|; tak är släta, kronor knottriga
# Träd över tak (rensa_trad): en krona som hänger över ett hus gav huset trädets höjd (Gamla Linköping:
# små hus på 15-24 m), och täta kronor blev laserhus (Vidingsjö, vid Ålerydsrondellen: 31 m², 15 m).
GRON_NDVI = 0.2      # cellen är grön i ortofotots IR-band: krona
GRON_LASERHUS = 0.1  # ett laserhus vars celler i median är grönare än så är en krona
TAK_MIN_KVAR = 0.3   # färre takceller kvar än så (av husets laserträffar): ingen laserhöjd, schablon
LITET_HUS_M2 = 250.0 # mindre hus kan inte resa sig mer än ett brant tak över sin halva bredd:
TAKRES_PER_M = 0.75  # nock <= takfot + TAKRES_PER_M * halva korta sidan + TAKRES_MARGINAL_M
TAKRES_MARGINAL_M = 1.0
VANING_M = 3.2       # med OSM building:levels får det vara minst våningarna högt
TORN = ('church', 'cathedral', 'chapel', 'tower', 'bell_tower', 'water_tower', 'silo', 'chimney', 'transformer_tower')


class Objekthojd:
    def __init__(self, path, orto=None):
        with rasterio.open(path) as src:
            self.h = src.read(1).astype(np.float32) / 10.0
            self.frac = src.read(2)
            self.T = src.transform
            self.crs = src.crs
        self.ndvi = self._ndvi(orto) if orto is not None and Path(orto).exists() else None
        self.res = self.T.a
        has = self.frac != 255
        num = ndi.uniform_filter(np.where(has, self.frac, 0).astype(np.float32), 3)
        den = ndi.uniform_filter(has.astype(np.float32), 3)
        self.frac_s = np.where(den > 0, num / np.maximum(den, 1e-6), 100.0)

    def _ndvi(self, orto):
        """Ortofotots NDVI ((IR - R) / (IR + R)) på laserns rutnät."""
        from rasterio.warp import reproject, Resampling
        band = []
        with rasterio.open(orto) as src:
            for b in (1, 4):
                dst = np.zeros(self.h.shape, np.float32)
                reproject(rasterio.band(src, b), dst, dst_transform=self.T, dst_crs=self.crs,
                          resampling=Resampling.average)
                band.append(dst)
        r, ir = band
        return (ir - r) / np.maximum(ir + r, 1.0)

    def _fonster(self, poly, shrink=0.8):
        inner = poly.buffer(-shrink)
        geom = inner if not inner.is_empty and inner.area > 4 else poly
        minx, miny, maxx, maxy = geom.bounds
        r0, c0 = rasterio.transform.rowcol(self.T, minx, maxy)
        r1, c1 = rasterio.transform.rowcol(self.T, maxx, miny)
        r0, c0 = max(r0, 0), max(c0, 0)
        r1, c1 = min(r1 + 1, self.h.shape[0]), min(c1 + 1, self.h.shape[1])
        if r1 <= r0 or c1 <= c0:
            return None
        win_T = self.T * rasterio.Affine.translation(c0, r0)
        return (slice(r0, r1), slice(c0, c1)), geometry_mask([geom], out_shape=(r1 - r0, c1 - c0),
                                                             transform=win_T, invert=True)

    def rensa_trad(self, hus):
        """Tar bort trädkronor ur laserhöjden inom husens fotavtryck (hus: [(polygon, taggar)]), så att
        heights_in och takformen (takform.laserceller) bara ser taket: celler som är gröna i ortofotot eller
        har hög flerekoandel, och i små hus allt högre än takfoten + ett brant tak över halva bredden.
        Blir för lite tak kvar nollas hela fotavtrycket (schablonhus). Torn och kyrkor rörs inte."""
        andrade = schablon = 0
        orord = self.h.copy()   # besluten på den orörda höjden: överlappande OSM-hus påverkar inte varandra
        for poly, t in hus:
            if t.get('building') in TORN or t.get('man_made') in ('tower', 'water_tower', 'silo', 'chimney') \
                    or 'tower:type' in t:
                continue
            f = self._fonster(poly, 0.0)
            if f is None:
                continue
            sl, m = f
            h = orord[sl]
            ut = self.h[sl]
            sel = m & (h > 1.5)
            if sel.sum() < 4:
                continue
            tak = sel & (self.frac_s[sl] < 30.0)
            if self.ndvi is not None:
                tak &= self.ndvi[sl] < GRON_NDVI
            if tak.sum() < max(4, TAK_MIN_KVAR * sel.sum()):
                ut[m] = 0.0
                schablon += 1
                continue
            if poly.area <= LITET_HUS_M2:
                c = np.array(poly.minimum_rotated_rectangle.exterior.coords)[:4]
                kort = min(np.linalg.norm(c[1] - c[0]), np.linalg.norm(c[2] - c[1]))
                takfot = float(np.percentile(h[tak], 20))
                tak_max = takfot + TAKRES_PER_M * kort / 2 + TAKRES_MARGINAL_M
                try:
                    tak_max = max(tak_max, float(t.get('building:levels', 0)) * VANING_M + TAKRES_PER_M * kort / 2)
                except ValueError:
                    pass
                tak &= h <= tak_max
            bort = sel & ~tak
            if bort.any():
                ut[bort] = 0.0
                andrade += 1
        print(f'laserhus: träd bort ur {andrade} hus, {schablon} helt under träd (schablon)')

    def heights_in(self, poly, shrink=0.8):
        """(takfot, nock) i meter över mark inom fotavtrycket, eller None om data saknas."""
        inner = poly.buffer(-shrink)
        geom = inner if not inner.is_empty and inner.area > 4 else poly
        minx, miny, maxx, maxy = geom.bounds
        r0, c0 = rasterio.transform.rowcol(self.T, minx, maxy)
        r1, c1 = rasterio.transform.rowcol(self.T, maxx, miny)
        r0, c0 = max(r0, 0), max(c0, 0)
        r1, c1 = min(r1 + 1, self.h.shape[0]), min(c1 + 1, self.h.shape[1])
        if r1 <= r0 or c1 <= c0:
            return None
        win_T = self.T * rasterio.Affine.translation(c0, r0)
        m = geometry_mask([geom], out_shape=(r1 - r0, c1 - c0), transform=win_T, invert=True)
        v = self.h[r0:r1, c0:c1][m]
        n_yta = v.size
        v = v[v > 1.5]
        # glesa träffar (under 20 % av ytan) är en kran, fåglar eller brus, inte ett tak
        if v.size < max(4, 0.2 * n_yta):
            return None
        return float(np.percentile(v, 20)), float(np.percentile(v, 95))

    def detect(self, exclude=None):
        """Lista med (rektangel, polygon) för takytor. exclude: shapely-geometri att hoppa över."""
        roof = (self.h > MIN_H) & (self.h < MAX_H) & (self.frac_s < MAX_FRAC)
        roof = ndi.binary_opening(roof, iterations=1)
        roof = ndi.binary_fill_holes(roof)
        lab, n = ndi.label(roof)
        sizes = ndi.sum(roof, lab, np.arange(1, n + 1)) * self.res ** 2
        rough = np.abs(self.h - ndi.median_filter(self.h, size=3))
        inner = ndi.binary_erosion(roof)               # kanterna är alltid ojämna
        ids = np.arange(1, n + 1)
        med = np.asarray(ndi.median(rough, np.where(inner, lab, 0), ids), dtype=np.float32)
        med = np.nan_to_num(med, nan=0.0)
        ok = ids[(sizes >= MIN_AREA) & (med <= MAX_ROUGH)]
        lab = np.where(np.isin(lab, ok), lab, 0).astype(np.int32)
        out = []
        for geom, val in shapes(lab, mask=lab > 0, transform=self.T):
            poly = shape(geom).buffer(0)
            if poly.area < MIN_AREA:
                continue
            rect = poly.minimum_rotated_rectangle
            if poly.area / rect.area < MIN_FILL:
                continue
            if exclude is not None and rect.intersects(exclude):
                continue
            if self.ndvi is not None:   # en tät trädkrona, inte ett tak
                f = self._fonster(poly, 0.0)
                if f is not None and np.median(self.ndvi[f[0]][f[1]]) > GRON_LASERHUS:
                    continue
            out.append((rect, poly))
        return out
