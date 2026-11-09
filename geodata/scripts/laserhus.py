"""Byggnader ur objekthöjdsrastret (band 1 = höjd över mark i dm, band 2 = flerekoandel i %).

Tak är höga ytor där nästan alla laserpunkter är sista ekot (låg flerekoandel), till skillnad
från trädkronor där pulsen delar sig. Allt i SWEREF 99 TM.
"""
import numpy as np, rasterio
from rasterio.features import shapes, geometry_mask
from scipy import ndimage as ndi
from shapely.geometry import shape

MIN_H = 2.5          # m över mark
MAX_FRAC = 20.0      # utjämnad flerekoandel, %
MIN_AREA = 25.0      # m²
MAX_H = 25.0         # högre än så är nästan alltid träd (silos undantagna, få här)
MIN_FILL = 0.55      # yta / omskrivande rektangel; trädklumpar blir oregelbundna
MAX_ROUGH = 0.35     # m, median av |h - 3x3-median|; tak är släta, kronor knottriga


class Objekthojd:
    def __init__(self, path):
        with rasterio.open(path) as src:
            self.h = src.read(1).astype(np.float32) / 10.0
            self.frac = src.read(2)
            self.T = src.transform
        self.res = self.T.a
        has = self.frac != 255
        num = ndi.uniform_filter(np.where(has, self.frac, 0).astype(np.float32), 3)
        den = ndi.uniform_filter(has.astype(np.float32), 3)
        self.frac_s = np.where(den > 0, num / np.maximum(den, 1e-6), 100.0)

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
            out.append((rect, poly))
        return out
