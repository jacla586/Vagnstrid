#!/usr/bin/env python3
"""
Gör ortofotot till en nyanskarta för terrängen: <projekt>/out/ortofoto_tint.png (2 m, samma rutnät som
heightmapen), som import_geodata_map.gd lägger som Terrain3D-färgkarta i stället för marktäckets färger.

    .venv/bin/python -I scripts/ortofoto_tint.py vidingsjo [--styrka 0.7]

Texturerna ger marken dess utseende; fotot ger bara variationen: per marktäcksklass delas varje pixel
med klassens medianfärg (linjärt ljus), så en brun åker, en sliten gräsplan eller en torr äng syns
men klassens textur behåller sin grundton. Träd, hus och buskar (laserns objekthöjd) och skuggor
(mörkare än `SKUGGA` × klassens median) visar inte marken: de fylls från omgivande mark (viktad
utjämning), långt från mark blir det neutralt. Kvoten begränsas och tas med `--styrka`.
Grundtonen är marktäckets nyans som utan fotot (tint_strength/tint_gain).
Färgkartan kan bara mörka (shadern: albedo × färg), så neutralt kodas som `neutral_linear`
(terrain_textures.json "ortho_tint") och importen ljusar alla texturer med 1/neutral.
Indata: <projekt>/data/ortofoto_<projekt>.tif (hamta_ortofoto.py, 0.5 m), objekthojd_<projekt>.tif,
out/landcover_index.png, out/heightmap_info.json.
"""
import argparse, json, sys
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from scipy import ndimage as ndi
from PIL import Image

GEO = Path(__file__).resolve().parent.parent
CONFIG = GEO.parent / "tools" / "terrain_textures.json"
OBJEKT_M = 0.8      # högre än så över marken = inte mark (träd, hus, buskar)
HOG_M = 2.5         # så höga objekt vidgas VIDGA_PX (hus lutar i fotot, kronorna är bredare)
VIDGA_PX = 2
FARG_ANDEL = 0.5    # färgskiftningen (kvot mot ljusheten) tas med så här mycket ...
MAX_FARG = 0.15     # ... och högst så här mycket (log-kvot): tak, bilar och pooler ger annars blått
SKUGGA = 0.6        # ljusare än så av klassens median, annars skugga
FYLL_SIGMA_PX = 3   # utjämning när maskade pixlar fylls (2 m-pixlar)
MAX_KVOT = 1.8      # största ljusning/mörkning före styrkan
NEUTRALA = {0, 11, 12, 13}  # hav, sjö, vägar: under vatten- och vägmesharna


def srgb2lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin2srgb(c):
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.maximum(c, 0), 1 / 2.4) - 0.055)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("projekt")
    ap.add_argument("--styrka", type=float, default=0.7)
    a = ap.parse_args()
    p = GEO / a.projekt
    info = json.loads((p / "out" / "heightmap_info.json").read_text())
    W, H, res = info["width_px"], info["height_px"], info["resolution_m"]
    e0, n0 = info["origin_sweref_of_pixel_0_0"]
    bounds = (e0 - res / 2, n0 - (H - 0.5) * res, e0 + (W - 0.5) * res, n0 + res / 2)
    cfg = json.loads(CONFIG.read_text())
    neutral = float(cfg["ortho_tint"]["neutral_linear"])

    def las(fil, band, resampling):
        with rasterio.open(fil) as d:
            win = rasterio.windows.from_bounds(*bounds, transform=d.transform)
            return d.read(band, window=win, out_shape=(len(band), H, W), resampling=resampling, boundless=True)

    rgb = srgb2lin(las(p / "data" / f"ortofoto_{a.projekt}.tif", [1, 2, 3], Resampling.average) / 255.0)
    rgb = np.moveaxis(rgb, 0, -1).astype(np.float32)
    hojd = las(p / "data" / f"objekthojd_{a.projekt}.tif", [1], Resampling.max)[0] / 10.0
    klass = np.array(Image.open(p / "out" / "landcover_index.png"))
    if klass.shape != (H, W):
        sys.exit(f"landcover_index.png är {klass.shape}, heightmapen {(H, W)}")

    luma = rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    mark = ~((hojd > OBJEKT_M) | ndi.binary_dilation(hojd > HOG_M, iterations=VIDGA_PX))
    mark &= luma > 0.0
    median = {}
    for k in np.unique(klass):
        sel = (klass == k) & mark
        if k in NEUTRALA or sel.sum() < 200:
            continue
        median[k] = np.median(rgb[sel], axis=0)
        ljus = luma[sel]
        mark[(klass == k)] &= luma[klass == k] > SKUGGA * np.median(ljus)
    ref = np.ones_like(rgb)
    giltig = mark.copy()
    for k, m in median.items():
        ref[klass == k] = m
    giltig &= np.isin(klass, list(median))
    giltig = ndi.binary_opening(giltig, np.ones((3, 3), bool))  # bara sammanhängande mark (inte luckor i kronorna)
    logk = np.log(np.clip(rgb / np.maximum(ref, 1e-4), 1 / MAX_KVOT, MAX_KVOT))
    ljus_k = logk.mean(-1, keepdims=True)
    logk = ljus_k + np.clip((logk - ljus_k) * FARG_ANDEL, -MAX_FARG, MAX_FARG)
    logk[~giltig] = 0.0

    w = ndi.gaussian_filter(giltig.astype(np.float32), FYLL_SIGMA_PX)
    fylld = np.stack([ndi.gaussian_filter(logk[..., c], FYLL_SIGMA_PX) for c in range(3)], -1) / np.maximum(w, 1e-6)[..., None]
    fylld *= np.clip(w / 0.15, 0, 1)[..., None]          # långt från mark: mot neutralt
    ut = np.where(giltig[..., None], logk, fylld)
    ut = np.stack([ndi.gaussian_filter(ut[..., c], 0.6) for c in range(3)], -1)
    ut[np.isin(klass, list(NEUTRALA))] = 0.0
    # Grundtonen som förut: marktäckets nyans som importen gör den (_tint_image), fotot ger variationen.
    lc = np.asarray(Image.open(p / "out" / "landcover_color.png").convert("RGB"), np.float32) / 255.0
    grund = srgb2lin(1.0 + (np.minimum(lc * cfg["tint_gain"], 1.0) - 1.0) * cfg["tint_strength"])
    tint = grund * np.exp(a.styrka * ut) * neutral
    bild = (np.clip(lin2srgb(np.clip(tint, 0, 1)), 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(bild).save(p / "out" / "ortofoto_tint.png")
    print(f"Klar: {p / 'out' / 'ortofoto_tint.png'}  {W} × {H}, mark {giltig.mean() * 100:.0f} %, "
          f"klasser {sorted(int(k) for k in median)}, styrka {a.styrka}")
    forh = GEO / "forhandsbilder"
    forh.mkdir(exist_ok=True)
    Image.fromarray(bild).save(forh / f"ortofoto_tint_{a.projekt}.png")


if __name__ == "__main__":
    main()
