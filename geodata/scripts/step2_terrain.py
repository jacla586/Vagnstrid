"""Steg 2: heightmap i SWEREF 99 TM, 2 m upplösning, med hav, kanopi-korrigering och utjämning."""
from pathlib import Path
import os
ROOT = Path(__file__).resolve().parent.parent
WORK = Path(os.environ.get('GEO_WORK', ROOT / 'work'))   # bygg.py --projekt sätter egen work-mapp
WORK.mkdir(exist_ok=True)
import sys, pickle, json
import numpy as np, rasterio
from rasterio.warp import reproject, Resampling
from rasterio.transform import from_origin
from rasterio.features import rasterize
from scipy import ndimage as ndi

DEM = sys.argv[1]
DEM_TYPE = sys.argv[2] if len(sys.argv) > 2 else 'copernicus'   # 'copernicus' eller 'lm'
RES = 2.0
reg = pickle.load(open(str(WORK / 'region.pkl'), 'rb'))
feat = pickle.load(open(str(WORK / 'features.pkl'), 'rb'))
area = reg['grid_box'] if 'grid_box' in reg else reg['region'].buffer(250)   # rutläge: exakt rutan
minx, miny, maxx, maxy = area.bounds
x0, y1 = np.floor(minx / 10) * 10, np.ceil(maxy / 10) * 10
W = int(np.ceil((maxx - x0) / RES)); H = int(np.ceil((y1 - miny) / RES))
T = from_origin(x0, y1, RES, RES)
print('grid', W, H, 'origin NW', x0, y1)

h = np.zeros((H, W), np.float32)
with rasterio.open(DEM) as src:
    reproject(rasterio.band(src, 1), h, dst_transform=T, dst_crs='EPSG:3006', resampling=Resampling.cubic if DEM_TYPE == 'copernicus' else Resampling.average)

def mask(geoms):
    geoms = [g for g in geoms if not g.is_empty]
    if not geoms:
        return np.zeros((H, W), bool)
    return rasterize([(g, 1) for g in geoms], out_shape=(H, W), transform=T).astype(bool)

land = mask([reg['land'].intersection(area.buffer(500))])
if DEM_TYPE == 'lm' or 'grid_box' in reg:
    # Lantmäteriets markmodell har havet platt på ~0,4–0,5 m (Copernicus ~0 m). Hav = sammanhängande
    # låga ytor större än 0,2 km². Säkrare än OSM-kustlinjen, vars land/hav-klassning slår fel långt
    # från kusten. Gäller även Copernicus i rutläge, där rutan annars räknas som land rakt igenom.
    low = h < 0.52
    lab, n = ndi.label(low)
    sizes = ndi.sum(low, lab, np.arange(1, n + 1)) * RES * RES
    sea = np.isin(lab, np.nonzero(sizes > 0.2e6)[0] + 1)
    land = ~sea
    print('hav enligt höjdmodellen, km²:', round(sea.sum() * RES * RES / 1e6, 2))
forest = mask([g for g, c in feat['landcover'] if c in ('forest',)])
forest &= land

# Copernicus är en ytmodell (DSM): skogen syns som platåer ovanpå marken.
# Skogen ligger ofta på höjder, så en kantjämförelse blandar ihop träd och terräng.
# Vi drar av en fast, typisk DSM-bias för svensk barr-/blandskog (X-band penetrerar delvis).
dist_in = ndi.distance_transform_edt(forest) * RES
canopy = 10.0 if DEM_TYPE == 'copernicus' else 0.0
print('kanopikorrigering (m):', canopy)
ramp = np.clip(dist_in / 40.0, 0, 1)            # mjuk övergång 40 m in i skogen
h = h - canopy * ramp

# Utjämning (tar bort resten av DSM-brus; 30 m-data har ändå inga detaljer under ~30 m)
h = ndi.gaussian_filter(h, sigma=6 if DEM_TYPE == 'copernicus' else 0.75)

# Hav: under kustlinjen lutar botten ner, stranden hamnar strax över 0
d_sea = ndi.distance_transform_edt(~land) * RES
d_land = ndi.distance_transform_edt(land) * RES
if land.all():
    d_land[:] = 1e6   # inget hav i rutan (inlandskarta): edt saknar bakgrund och ger skräp, ingen strandlogik
sea_floor = -0.6 - np.minimum(d_sea, 300) * 0.02   # ner till ca -6.6 m
# Mjuk strand: dra ner landhöjden mot ~0.5 m de sista 80 m mot vattnet
shore_t = np.clip(d_land / 80.0, 0, 1); shore_t = shore_t * shore_t * (3 - 2 * shore_t)
h = np.where(land, 0.5 + (np.maximum(h, 0.5) - 0.5) * shore_t, h)
h = np.where(land, np.maximum(h, 0.4 + np.minimum(d_land, 30) * 0.02), sea_floor)
h = ndi.gaussian_filter(h, sigma=1.5)
h = np.where(land, np.maximum(h, 0.25), np.minimum(h, -0.3))

np.save(str(WORK / 'h_raw.npy'), h)
json.dump(dict(W=W, H=H, RES=RES, x0=x0, y1=y1, canopy=canopy, dem_type=DEM_TYPE), open(str(WORK / 'grid.json'), 'w'))
np.save(str(WORK / 'land.npy'), land)
print('höjd min/max', h.min(), h.max())
