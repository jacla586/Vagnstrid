"""Steg 4: enskilda träd ur laserdatan (objekthöjd) med trädslag från NMD.

    python3 scripts/step4_trees.py <objekthojd.tif> <utmapp> [nmd-mapp]

Trädtoppar = lokala maxima i utjämnad kronhöjd (band 1), med ett fönster som växer med höjden.
Typ lottas efter NMD-andelarna (tall, gran, triviallöv, ek/ädellöv) i trädets 10 m-cell; utanför
NMD:s skogsmask (gårdar, åkerholmar) blir det lövträd.

Utdata:
  trees.bin        float32, 12 tal per träd = färdig MultiMesh-transform (3x4, radvis), origo relativt
                   rutans mitt. Sorterad per ruta och typ.
  trees_info.json  rutor: [typ, rutans mitt x, z, första träd, antal]; mesh-enhet: höjd 1, kronradie 1.
  trad_gran.glb, trad_tall.glb, trad_lov.glb  low-poly-platshållare (höjd 1, kronradie 1, vertexfärger).
"""
from pathlib import Path
import os
ROOT = Path(__file__).resolve().parent.parent
WORK = Path(os.environ.get('GEO_WORK', ROOT / 'work'))   # bygg.py --projekt sätter egen work-mapp
import sys, json, pickle, glob, math
import numpy as np, rasterio
from rasterio.features import rasterize
from rasterio.transform import from_origin
from scipy import ndimage as ndi
from scipy.spatial import cKDTree
from PIL import Image
import trimesh

OBJ = sys.argv[1]
OUT = Path(sys.argv[2])
NMD_DIR = Path(sys.argv[3]) if len(sys.argv) > 3 else ROOT / 'data' / 'nmd'
CHUNK = 250.0           # m, rutstorlek i Godot
MIN_H = 3.0             # lägre än så räknas som buskar/sly
ROOF_FRAC = 15.0        # utjämnad flerekoandel (%) under detta + hög = tak, inte träd
TYPES = ['gran', 'tall', 'lov']
rng = np.random.default_rng(851)

g = json.load(open(str(WORK / 'grid.json')))
RES, X0, Y1 = g['RES'], g['x0'], g['y1']
OX, OY = X0 + RES / 2, Y1 - RES / 2       # samma origo som heightmapen
h_final = np.load(str(WORK / 'h_final.npy'))
lc = np.array(Image.open(str(OUT / 'landcover_index.png')))
info_lc = json.load(open(str(OUT / 'heightmap_info.json')))['landcover_classes']
LC = {v: int(k) for k, v in info_lc.items()}

# ---------- Kronhöjdsmodell ----------
with rasterio.open(OBJ) as src:
    b1, b2 = src.read(1).astype(np.float32) / 10.0, src.read(2)
    T = src.transform
    crs_obj = src.crs
H, W = b1.shape
cres = T.a
chm = ndi.gaussian_filter(b1, sigma=1.0 / cres)

# Tak: hög och med låg flerekoandel i ett 5x5 m-fönster
has = b2 != 255
num = ndi.uniform_filter(np.where(has, b2, 0).astype(np.float32), 5)
den = ndi.uniform_filter(has.astype(np.float32), 5)
frac_s = np.where(den > 0, num / np.maximum(den, 1e-6), 100.0)
roof = (b1 > 2.5) & (frac_s < ROOF_FRAC)
lab, n = ndi.label(roof)
sizes = ndi.sum(roof, lab, np.arange(1, n + 1))
roof = np.isin(lab, np.nonzero(sizes * cres * cres >= 25)[0] + 1)
roof = ndi.binary_dilation(roof, iterations=2)
print('takceller (utesluts)', int(roof.sum()))

# Lokala maxima med höjdberoende fönster (kronbredd ~ 2.5 + 0.009 h^2 m)
diam = 2.5 + 0.009 * chm ** 2
peaks = np.zeros_like(roof)
for size, lo, hi in ((3, 0, 3.5), (5, 3.5, 5.5), (7, 5.5, 99)):
    mx = ndi.maximum_filter(chm, size=size)
    peaks |= (chm == mx) & (diam >= lo) & (diam < hi)
peaks &= (b1 >= MIN_H) & ~roof
rr, cc = np.nonzero(peaks)
E = T.c + (cc + 0.5) * cres + rng.uniform(-0.3, 0.3, rr.size)
N = T.f - (rr + 0.5) * cres + rng.uniform(-0.3, 0.3, rr.size)
ht = b1[rr, cc]
print('trädtoppar', rr.size)

# ---------- Rensa: hav, sjöar, vägar, OSM-hus ----------
pj = np.clip(np.round((E - OX) / RES).astype(int), 0, lc.shape[1] - 1)
pi = np.clip(np.round((OY - N) / RES).astype(int), 0, lc.shape[0] - 1)
bad = np.isin(lc[pi, pj], [LC['hav'], LC['sjö'], LC['väg_asfalt'], LC['väg_grus']])
feat = pickle.load(open(str(WORK / 'features.pkl'), 'rb'))
blds = [gm.buffer(1.5) for gm, _ in feat['buildings']]
if blds:
    Tg = from_origin(X0, Y1, RES, RES)
    bm = rasterize([(b, 1) for b in blds], out_shape=lc.shape, transform=Tg).astype(bool)
    bad |= bm[pi, pj]
ground = ndi.map_coordinates(h_final, [(OY - N) / RES, (E - OX) / RES], order=1, mode='nearest')
bad |= ground < 0.3
keep = ~bad
E, N, ht, ground = E[keep], N[keep], ht[keep], ground[keep]
print('träd efter rensning', E.size)

# ---------- Trädslag från NMD ----------
names = dict(tall='tall', gran='gran', trivial='trivial', ekovradel='ekovradel')
shares = {}
for key in names:
    f = glob.glob(str(NMD_DIR / f'*tradslag_{key}_*.tif'))
    if not f:
        sys.exit(f'Saknar NMD-skiktet {key} i {NMD_DIR}')
    with rasterio.open(f[0]) as s:
        if s.crs != crs_obj and s.crs.to_epsg() != 3006:
            sys.exit(f'{f[0]} är inte i SWEREF 99 TM')
        a = s.read(1)
        r_, c_ = rasterio.transform.rowcol(s.transform, E, N)
        r_ = np.clip(np.asarray(r_), 0, a.shape[0] - 1); c_ = np.clip(np.asarray(c_), 0, a.shape[1] - 1)
        shares[key] = a[r_, c_].astype(np.float32)
nod = shares['tall'] == 255
p = np.stack([shares['gran'], shares['tall'], shares['trivial'] + shares['ekovradel']], 1)
p[nod] = [0, 0, 1]
p = np.where(p == 255, 0, p)
p[p.sum(1) == 0] = [0, 0, 1]
cum = np.cumsum(p / p.sum(1, keepdims=True), 1)
typ = (rng.random(E.size)[:, None] > cum).sum(1).clip(0, 2)
print('fördelning', {t: int((typ == k).sum()) for k, t in enumerate(TYPES)})

# ---------- Kronradie: allometri, begränsad av närmaste granne ----------
A = np.array([[0.40, 0.08], [0.60, 0.09], [0.80, 0.15]])   # r = a + b*h per typ
r_allo = A[typ, 0] + A[typ, 1] * ht
nn, _ = cKDTree(np.c_[E, N]).query(np.c_[E, N], k=2)
crown = np.clip(np.minimum(r_allo, 0.65 * nn[:, 1]), 0.5, None)

# ---------- MultiMesh-buffert per ruta och typ ----------
x = E - OX; z = OY - N
cx = np.floor(x / CHUNK).astype(int); cz = np.floor(z / CHUNK).astype(int)
order = np.lexsort((typ, cx, cz))
x, z, ground, ht, crown, typ, cx, cz = (a[order] for a in (x, z, ground, ht, crown, typ, cx, cz))
yaw = rng.uniform(0, 2 * math.pi, x.size)
c, s = np.cos(yaw), np.sin(yaw)
mx_ = (cx + 0.5) * CHUNK; mz_ = (cz + 0.5) * CHUNK
buf = np.zeros((x.size, 12), np.float32)
buf[:, 0] = c * crown;  buf[:, 2] = s * crown;  buf[:, 3] = x - mx_
buf[:, 5] = ht;         buf[:, 7] = ground - 0.15                     # sänk lite så stammen inte svävar
buf[:, 8] = -s * crown; buf[:, 10] = c * crown; buf[:, 11] = z - mz_
buf.tofile(str(OUT / 'trees.bin'))
key = np.c_[cz, cx, typ]
starts = np.r_[0, np.nonzero(np.any(np.diff(key, axis=0) != 0, axis=1))[0] + 1]
counts = np.diff(np.r_[starts, x.size])
chunks = [[int(typ[a]), float(mx_[a]), float(mz_[a]), int(a), int(n_)] for a, n_ in zip(starts, counts)]
json.dump(dict(count=int(x.size), floats_per_tree=12, chunk_m=CHUNK, types=TYPES,
               note='chunks: [typ, mitt_x, mitt_z, första, antal]; transform radvis 3x4 relativt rutans mitt',
               chunks=chunks), open(str(OUT / 'trees_info.json'), 'w'))
print('rutor', len(chunks), 'fil MB', round(buf.nbytes / 1e6, 1))


# ---------- Platshållarträd (höjd 1, kronradie 1) ----------
def srgb2lin(rgb):
    c = np.asarray(rgb, np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def colored(mesh, rgb):
    col = np.r_[np.round(srgb2lin(rgb) * 255), 255].astype(np.uint8)
    mesh.visual = trimesh.visual.ColorVisuals(mesh, vertex_colors=np.tile(col, (len(mesh.vertices), 1)))
    return mesh

def cyl(r, y0, y1, sections=6):
    m = trimesh.creation.cylinder(radius=r, height=y1 - y0, sections=sections)
    m.apply_transform(trimesh.transformations.rotation_matrix(-math.pi / 2, [1, 0, 0]))
    m.apply_translation([0, (y0 + y1) / 2, 0]); return m

def cone(r, y0, y1, sections=7):
    m = trimesh.creation.cone(radius=r, height=y1 - y0, sections=sections)
    m.apply_transform(trimesh.transformations.rotation_matrix(-math.pi / 2, [1, 0, 0]))
    m.apply_translation([0, y0, 0]); return m

def blob(ry, yc, sub=1):
    m = trimesh.creation.icosphere(subdivisions=sub, radius=1.0)
    m.apply_scale([1.0, ry, 1.0]); m.apply_translation([0, yc, 0]); return m

BARK = (92, 70, 52); PINE_BARK = (150, 96, 60)
models = dict(
    gran=[colored(cyl(0.05, 0, 0.2), BARK)] + [colored(cone(r, y0, y1), (40, 74, 44))
          for r, y0, y1 in ((1.0, 0.08, 0.55), (0.78, 0.35, 0.8), (0.52, 0.6, 1.0))],
    tall=[colored(cyl(0.06, 0, 0.8), PINE_BARK), colored(blob(0.16, 0.84), (58, 88, 48))],
    lov=[colored(cyl(0.07, 0, 0.45), BARK), colored(blob(0.33, 0.66), (78, 112, 54))],
)
for name, parts in models.items():
    m = trimesh.util.concatenate(parts)
    m.export(str(OUT / f'trad_{name}.glb'))
print('klart')
