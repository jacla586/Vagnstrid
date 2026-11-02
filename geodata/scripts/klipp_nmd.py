#!/usr/bin/env python3
"""
Klipper ut spelområdet ur Naturvårdsverkets rikstäckande NMD-raster (t.ex. trädslagsskikten).

    python3 scripts/klipp_nmd.py NMD2023_tradslag_tall_v1_1.tif NMD2023_tradslag_gran_v1_1.tif ...

Fungerar även med adresser direkt till servern (läser då bara den bit som behövs om servern tillåter):
    python3 scripts/klipp_nmd.py https://.../NMD2023_tradslag_tall_v1_1.tif

Utfiler hamnar i data/nmd/ med samma namn + _e851.tif.

Annat område:  --ruta minx,miny,maxx,maxy  --ut <mapp>   (t.ex. --ut vidingsjo/data/nmd)
"""
import argparse, sys
from pathlib import Path
import rasterio
from rasterio.windows import from_bounds
from rasterio.warp import transform_bounds

ROOT = Path(__file__).resolve().parent.parent
BBOX = (586040, 6478956, 592614, 6485950)  # SWEREF 99 TM, samma som resten av projektet


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('filer', nargs='+')
    ap.add_argument('--ruta', default=None, help='minx,miny,maxx,maxy i SWEREF 99 TM')
    ap.add_argument('--ut', default=None, help='utmapp (standard data/nmd)')
    a = ap.parse_args(argv)
    ruta = tuple(map(float, a.ruta.split(','))) if a.ruta else BBOX
    outdir = Path(a.ut) if a.ut else ROOT / 'data' / 'nmd'
    outdir.mkdir(parents=True, exist_ok=True)
    for p in a.filer:
        src_path = '/vsicurl/' + p if p.startswith('http') else p
        with rasterio.open(src_path) as src:
            bbox = ruta
            if src.crs and src.crs.to_epsg() != 3006:
                print(f'  obs: {p} är i {src.crs}, inte SWEREF 99 TM; klipper med omräknad ruta')
                bbox = transform_bounds('EPSG:3006', src.crs, *ruta)
            win = from_bounds(*bbox, transform=src.transform).round_offsets().round_lengths()
            data = src.read(window=win, boundless=True, fill_value=src.nodata or 0)
            prof = src.profile.copy()
            prof.update(width=data.shape[2], height=data.shape[1], transform=src.window_transform(win),
                        compress='deflate', tiled=False)
            prof.pop('blockxsize', None); prof.pop('blockysize', None)
            out = outdir / (Path(p.split('?')[0]).stem + ('_utklipp.tif' if a.ruta else '_e851.tif'))
            with rasterio.open(out, 'w', **prof) as dst:
                dst.write(data)
        print(f'  {out}  ({data.shape[2]} x {data.shape[1]} px)')


if __name__ == '__main__':
    main(sys.argv[1:])
