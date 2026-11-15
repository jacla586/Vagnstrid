"""Ortofoto- och laserutsnitt med koordinatrutnät, för att läsa av lägen till platsdetaljer.json.

    .venv/bin/python -I scripts/ortobild.py <projekt> <E,N | lat,lon> <halv sida m> <ut.png> [--forstoring 6]
        [--steg 10] [--laser] [--markera E,N ...]

Utsnittet ur <projekt>/data/ortofoto_<projekt>.tif (0,5 m) förstoras; gula streck var `--steg` meter i
kanterna med E/N:s sista tre siffror. `--laser`: laserns objekthöjd (gråskala, 0-20 m) i stället. Punkter
som `--markera` (SWEREF eller lat,lon) ritas som röda ringar. Lat,lon känns igen på att talen är små.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent


def till_sweref(s):
    a, b = (float(v) for v in s.split(','))
    if abs(a) < 90 and abs(b) < 180:   # lat,lon
        from pyproj import Transformer
        E, N = Transformer.from_crs(4326, 3006, always_xy=True).transform(b, a)
        return E, N
    return a, b


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('projekt')
    ap.add_argument('mitt')
    ap.add_argument('halv', type=float)
    ap.add_argument('ut')
    ap.add_argument('--forstoring', type=int, default=6)
    ap.add_argument('--steg', type=int, default=10)
    ap.add_argument('--laser', action='store_true')
    ap.add_argument('--markera', nargs='*', default=[])
    a = ap.parse_args()
    E, N = till_sweref(a.mitt)
    E0, N0, E1, N1 = E - a.halv, N - a.halv, E + a.halv, N + a.halv
    d = ROOT / a.projekt / 'data'
    k = a.forstoring
    if a.laser:
        with rasterio.open(d / f'objekthojd_{a.projekt}.tif') as r:
            w = rasterio.windows.from_bounds(E0, N0, E1, N1, r.transform)
            h = r.read(1, window=w).astype(float) / 10.0
            tr = r.window_transform(w)
        im = Image.fromarray(np.clip(h / 20.0 * 255, 0, 255).astype(np.uint8)).convert('RGB')
    else:
        with rasterio.open(d / f'ortofoto_{a.projekt}.tif') as r:
            w = rasterio.windows.from_bounds(E0, N0, E1, N1, r.transform)
            img = r.read(window=w)[:3]
            tr = r.window_transform(w)
        im = Image.fromarray(np.moveaxis(img, 0, -1)).convert('RGB')
    im = im.resize((im.width * k, im.height * k), Image.NEAREST if a.laser else Image.LANCZOS)
    dr = ImageDraw.Draw(im)
    for e in range(int(E0) // a.steg * a.steg + a.steg, int(E1), a.steg):
        c, _ = ~tr * (e, N1)
        dr.line([c * k, 0, c * k, 12], fill=(255, 255, 0))
        dr.text((c * k + 2, 14), str(e % 1000), fill=(255, 255, 0))
    for n in range(int(N0) // a.steg * a.steg + a.steg, int(N1), a.steg):
        _, rw = ~tr * (E0, n)
        dr.line([0, rw * k, 12, rw * k], fill=(255, 255, 0))
        dr.text((14, rw * k - 5), str(n % 1000), fill=(255, 255, 0))
    for m in a.markera:
        me, mn = till_sweref(m)
        c, rw = ~tr * (me, mn)
        dr.ellipse([c * k - 6, rw * k - 6, c * k + 6, rw * k + 6], outline=(255, 0, 0), width=2)
    im.save(a.ut)
    print(f'{a.ut}: {im.width}x{im.height}, mitt {E:.1f} {N:.1f}, {k if a.laser else 2 * k} px/m')


if __name__ == '__main__':
    sys.exit(main())
