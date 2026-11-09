#!/usr/bin/env python3
"""Land cover -> Terrain3D control map (which texture where), for geodata maps.

    geodata/.venv/bin/python tools/terrain_control.py <geodata out dir>
    e.g. geodata/vidingsjo/out

Reads <out>/landcover_index.png, heightmap.r16 and heightmap_info.json, and the rules in
tools/terrain_textures.json. Every land cover class gets its texture; borders blend over
blend_sigma_m; slopes steeper than rock_slope_deg turn to rock; roads get a gravel shoulder.
Per pixel the two strongest textures become base and overlay, with their blend.
Writes <out>/terrain_control.r32: one little-endian uint32 per pixel in Terrain3D's control
format (base << 27 | overlay << 22 | blend << 14), the size of the heightmap. Then run
tools/import_geodata_map.gd -- <map> <out> --textures.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / 'tools' / 'terrain_textures.json'
ROAD_CLASSES = ('väg_asfalt', 'väg_grus')
WATER_CLASSES = ('hav', 'sjö')
## Overlays weaker than this are dropped (base only).
MIN_OVERLAY = 0.04


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def main():
    out = Path(sys.argv[1])
    config = json.loads(CONFIG.read_text())
    info = json.loads((out / 'heightmap_info.json').read_text())
    w, h, res = int(info['width_px']), int(info['height_px']), float(info['resolution_m'])
    heights = np.fromfile(out / 'heightmap.r16', '<u2').reshape(h, w).astype(np.float32)
    heights = info['height_min_m'] + heights / 65535.0 * (info['height_max_m'] - info['height_min_m'])
    lc = np.array(Image.open(out / 'landcover_index.png'))
    assert lc.shape == (h, w), (lc.shape, (h, w))
    class_names = {int(k): v for k, v in info['landcover_classes'].items()}
    tex_ids = {t['name']: i for i, t in enumerate(config['textures'])}
    n_tex = len(config['textures'])

    # Texture per pixel from its land cover class; a gravel shoulder beside roads.
    lut = np.zeros(256, np.uint8)
    for idx, name in class_names.items():
        lut[idx] = tex_ids[config['classes'][name]]
    tex = lut[lc]
    by_name = {v: k for k, v in class_names.items()}
    road = np.isin(lc, [by_name[c] for c in ROAD_CLASSES if c in by_name])
    water = np.isin(lc, [by_name[c] for c in WATER_CLASSES if c in by_name])
    shoulder_px = int(round(config['road_shoulder_m'] / res))
    if shoulder_px > 0:
        ring = ndi.binary_dilation(road, iterations=shoulder_px) & ~road & ~water
        tex[ring] = tex_ids['gravel']

    # Soft borders: each texture's share blurred.
    sigma = config['blend_sigma_m'] / res
    weights = np.zeros((n_tex, h, w), np.float32)
    for i in range(n_tex):
        mask = tex == i
        if mask.any():
            weights[i] = ndi.gaussian_filter(mask.astype(np.float32), sigma)

    # Rock on steep ground.
    gy, gx = np.gradient(heights, res)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    lo, hi = config['rock_slope_deg']
    rock = smoothstep(lo, hi, ndi.gaussian_filter(slope, 1.0)).astype(np.float32)
    weights *= 1.0 - rock
    weights[tex_ids['rock']] += rock

    # The two strongest per pixel.
    order = np.argsort(weights, axis=0)
    base = order[-1].astype(np.uint32)
    overlay = order[-2].astype(np.uint32)
    w1 = np.take_along_axis(weights, order[-1][None], 0)[0]
    w2 = np.take_along_axis(weights, order[-2][None], 0)[0]
    share = np.where(w1 + w2 > 0.0, w2 / np.maximum(w1 + w2, 1e-6), 0.0)
    share[share < MIN_OVERLAY] = 0.0
    overlay[share == 0.0] = base[share == 0.0]
    blend = np.round(share * 255.0).astype(np.uint32)
    control = (base << 27) | (overlay << 22) | (blend << 14)
    control.astype('<u4').tofile(out / 'terrain_control.r32')

    names = [t['name'] for t in config['textures']]
    counts = np.bincount(base.ravel(), minlength=n_tex)
    print('base texture share:', ', '.join(f'{names[i]} {100.0 * counts[i] / base.size:.1f} %'
                                           for i in range(n_tex) if counts[i]))
    print(f'blended pixels: {100.0 * (blend > 0).mean():.1f} %  -> {out / "terrain_control.r32"}')


if __name__ == '__main__':
    main()
