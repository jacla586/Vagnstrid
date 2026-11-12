"""Steg 4: enskilda träd ur laserdatan (objekthöjd) med trädslag från NMD.

    python3 scripts/step4_trees.py <objekthojd.tif> <utmapp> [nmd-mapp]

Trädtoppar = lokala maxima i utjämnad kronhöjd (band 1), med ett fönster som växer med höjden.
Typ lottas efter NMD-andelarna (tall, gran, triviallöv, ek/ädellöv) i trädets 10 m-cell; utanför
NMD:s skogsmask (gårdar, åkerholmar) blir det lövträd.

Utdata:
  trees.bin        float32, 16 tal per träd = färdig MultiMesh-transform (3x4, radvis, origo relativt
                   rutans mitt) + färg. Sorterad per ruta och typ (slag_variant).
  trees_info.json  rutor: [typ, rutans mitt x, z, första träd, antal], typer, modellfiler och slag.
  buskar.bin, buskar_info.json  samma format för buskar (laser, OSM-häckar, buskmark, skogsbryn).
  veg_<slag>_<variant>.glb  modellerna (vegetation.json, vegmodeller.py): höjd 1, kronradie 1.
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
CHUNK = 500.0           # m, rutstorlek i Godot (en MultiMesh per ruta, slag och variant)
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
# broar och undergångar (step3/broar.py): inga träd i schakten eller på brobanorna
bro_fil = WORK / 'broar_mask.npy'
bro_mask = np.load(str(bro_fil)) if bro_fil.exists() else None
for extra in ('stenar_mask.npy', 'jarnvag_mask.npy', 'lekplatser_mask.npy', 'idrott_mask.npy'):   # stenblock (orienteringskartan), järnväg (step3)
    if (WORK / extra).exists():
        sm = np.load(str(WORK / extra))
        bro_mask = sm if bro_mask is None else (bro_mask | sm)
if bro_mask is not None:
    bad |= bro_mask[pi, pj]
ground = ndi.map_coordinates(h_final, [(OY - N) / RES, (E - OX) / RES], order=1, mode='nearest')
bad |= ground < 0.3
sys.path.insert(0, str(Path(__file__).resolve().parent))
import korridor   # korridorkarta (korridor.json): bara träd nära rutten, ojämn kant
bad |= ~korridor.inne(WORK, E, N, rng.random(E.size))
keep = ~bad
E, N, ht, ground = E[keep], N[keep], ht[keep], ground[keep]
print('träd efter rensning', E.size)

# ---------- Trädslag från NMD ----------
sys.path.insert(0, str(Path(__file__).resolve().parent))
import vegmodeller
VEG = vegmodeller.KATALOG
SLAG = list(VEG['trad'])                                   # t.ex. gran, tall, bjork, ek
skikt = sorted({k for sp in VEG['trad'].values() for k in sp['nmd']})
nmd_files = {key: glob.glob(str(NMD_DIR / f'*tradslag_{key}_*.tif')) for key in skikt}
shares = {}
if not all(nmd_files.values()):
    print(f'Saknar NMD-trädslag i {NMD_DIR}: använder genomsnittsandelar {VEG["utan_nmd"]}')
for key in (skikt if all(nmd_files.values()) else []):
    f = nmd_files[key]
    with rasterio.open(f[0]) as src_n:
        if src_n.crs != crs_obj and src_n.crs.to_epsg() != 3006:
            sys.exit(f'{f[0]} är inte i SWEREF 99 TM')
        a = src_n.read(1)
        r_, c_ = rasterio.transform.rowcol(src_n.transform, E, N)
        r_ = np.clip(np.asarray(r_), 0, a.shape[0] - 1); c_ = np.clip(np.asarray(c_), 0, a.shape[1] - 1)
        shares[key] = a[r_, c_].astype(np.float32)
utanfor = np.array([VEG['utanfor_skog'].get(sl, 0.0) for sl in SLAG], np.float32)
if shares:
    nod = shares[skikt[0]] == 255
    p = np.stack([sum(np.where(shares[k] == 255, 0, shares[k]) for k in VEG['trad'][sl]['nmd']) for sl in SLAG], 1)
    p[nod] = utanfor
else:
    p = np.tile(np.array([VEG['utan_nmd'].get(sl, 0.0) for sl in SLAG], np.float32), (E.size, 1))
p[p.sum(1) == 0] = utanfor
cum = np.cumsum(p / p.sum(1, keepdims=True), 1)
typ = (rng.random(E.size)[:, None] > cum).sum(1).clip(0, len(SLAG) - 1)
print('fördelning', {sl: int((typ == k).sum()) for k, sl in enumerate(SLAG)})

# ---------- Kronradie: allometri, begränsad av närmaste granne ----------
A = np.array([VEG['trad'][sl]['allometri'] for sl in SLAG])   # r = a + b*h per slag
r_allo = A[typ, 0] + A[typ, 1] * ht
nn, _ = cKDTree(np.c_[E, N]).query(np.c_[E, N], k=2)
crown = np.clip(np.minimum(r_allo, 0.65 * nn[:, 1]), 0.5, None)


# ---------- Skriv MultiMesh-buffert (träd och buskar) ----------
def skriv(namn, grupp, slag_idx, E_, N_, mark, hojd, rx, rz, yaw):
    """Buffert med 16 tal per instans (3x4-transform + färg) per ruta, slag och variant, samt
    info-json med modellfilerna. slag_idx pekar i listan över slag i vegetation.json[grupp]."""
    slaglista = list(VEG[grupp])
    filer = vegmodeller.bygg_modeller(grupp, OUT)
    typer, modeller, typ_slag = [], [], []
    for si, sl in enumerate(slaglista):
        for f in filer[sl]:
            typer.append(f[4:-4]); modeller.append(f); typ_slag.append(si)
    forsta = np.cumsum([0] + [len(filer[sl]) for sl in slaglista])
    antal_var = np.array([len(filer[sl]) for sl in slaglista])
    variant = (rng.random(E_.size) * antal_var[slag_idx]).astype(int)
    t_idx = forsta[slag_idx] + variant
    x = E_ - OX; z = OY - N_
    cx = np.floor(x / CHUNK).astype(int); cz = np.floor(z / CHUNK).astype(int)
    order = np.lexsort((t_idx, cx, cz))
    x, z, mark, hojd, rx, rz, yaw, t_idx, slag_idx, cx, cz = (a[order] for a in
        (x, z, mark, hojd, rx, rz, yaw, t_idx, slag_idx, cx, cz))
    c, s_ = np.cos(yaw), np.sin(yaw)
    mx_ = (cx + 0.5) * CHUNK; mz_ = (cz + 0.5) * CHUNK
    buf = np.zeros((x.size, 16), np.float32)
    buf[:, 0] = c * rx;   buf[:, 2] = s_ * rz;  buf[:, 3] = x - mx_
    buf[:, 5] = hojd;     buf[:, 7] = mark
    buf[:, 8] = -s_ * rx; buf[:, 10] = c * rz;  buf[:, 11] = z - mz_
    # Färg per instans: ljushet och lite grönskiftning, styrt av slagets fargvariation
    var = np.array([VEG[grupp][sl].get('fargvariation', 0.1) for sl in slaglista])[slag_idx]
    ljus = 1 + rng.normal(0, 0.5, x.size) * var
    gron = 1 + rng.normal(0, 0.3, x.size) * var
    buf[:, 12] = np.clip(ljus * (2 - gron), 0.5, 1.5)
    buf[:, 13] = np.clip(ljus * gron, 0.5, 1.5)
    buf[:, 14] = np.clip(ljus, 0.5, 1.5)
    buf[:, 15] = 1.0
    buf.tofile(str(OUT / f'{namn}.bin'))
    key = np.c_[cz, cx, t_idx]
    starts = np.r_[0, np.nonzero(np.any(np.diff(key, axis=0) != 0, axis=1))[0] + 1] if x.size else np.array([], int)
    counts = np.diff(np.r_[starts, x.size])
    chunks = [[int(t_idx[a]), float(mx_[a]), float(mz_[a]), int(a), int(n_)] for a, n_ in zip(starts, counts)]
    json.dump(dict(count=int(x.size), floats_per_tree=16, chunk_m=CHUNK, types=typer, models=modeller,
                   species=[slaglista[i] for i in typ_slag],
                   note='chunks: [typ, mitt_x, mitt_z, första, antal]; transform radvis 3x4 relativt rutans mitt + färg',
                   chunks=chunks), open(str(OUT / f'{namn}_info.json'), 'w'))
    print(f'{namn}: {x.size} st i {len(chunks)} rutor,', {t: int((t_idx == i).sum()) for i, t in enumerate(typer)})


yaw = rng.uniform(0, 2 * math.pi, E.size)
skriv('trees', 'trad', typ, E, N, ground - 0.15, ht, crown, crown, yaw)    # sänk lite så stammen inte svävar

# ---------- Buskar ----------
BUSKAR = list(VEG['buskar'])
bi = {b: i for i, b in enumerate(BUSKAR)}
bE, bN, bH, bR, bL, bY, bT = [], [], [], [], [], [], []

def lagg(E_, N_, h_, r_, l_, y_, typ_):
    n_ = np.size(E_)
    bE.append(np.atleast_1d(E_)); bN.append(np.atleast_1d(N_)); bH.append(np.broadcast_to(h_, n_).astype(float))
    bR.append(np.broadcast_to(r_, n_).astype(float)); bL.append(np.broadcast_to(l_, n_).astype(float))
    bY.append(np.broadcast_to(y_, n_).astype(float)); bT.append(np.full(n_, bi[typ_]))

def ok_plats(E_, N_):
    pj_ = np.clip(np.round((E_ - OX) / RES).astype(int), 0, lc.shape[1] - 1)
    pi_ = np.clip(np.round((OY - N_) / RES).astype(int), 0, lc.shape[0] - 1)
    bra = ~np.isin(lc[pi_, pj_], [LC['hav'], LC['sjö'], LC['väg_asfalt'], LC['väg_grus']])
    if blds:
        bra &= ~bm[pi_, pj_]
    if bro_mask is not None:
        bra &= ~bro_mask[pi_, pj_]
    bra &= korridor.inne(WORK, E_, N_, rng.random(np.size(E_)))
    return bra

# 1) Laserdatan: låg vegetation 0,7–3 m med många flerekon (inte tak, inte träd)
lag = (b1 >= 0.7) & (b1 < 3.0) & has & (frac_s > 30) & ~roof
rr_, cc_ = np.nonzero(lag & (rng.random(lag.shape) < (cres * cres) / 6.0))
E_ = T.c + (cc_ + 0.5) * cres + rng.uniform(-0.4, 0.4, rr_.size)
N_ = T.f - (rr_ + 0.5) * cres + rng.uniform(-0.4, 0.4, rr_.size)
h_ = b1[rr_, cc_] * rng.uniform(0.85, 1.0, rr_.size)
keep_ = ok_plats(E_, N_)
E_, N_, h_ = E_[keep_], N_[keep_], h_[keep_]
r_ = np.clip(0.5 + 0.35 * h_, 0.6, 1.6)
for t_, m_ in (('sly', h_ > 2.0), ('buske', h_ <= 2.0)):
    lagg(E_[m_], N_[m_], h_[m_], r_[m_], r_[m_], rng.uniform(0, 2 * math.pi, m_.sum()), t_)
n_laser = E_.size

# 2) OSM-häckar: en häckbit var 1,5 m längs linjen
n_hack = 0
for line in feat.get('hedges', []):
    L_ = line.length
    if L_ < 1:
        continue
    for d_ in np.arange(0.75, L_, 1.5):
        a_ = line.interpolate(max(d_ - 0.5, 0)); b_ = line.interpolate(min(d_ + 0.5, L_)); m_ = line.interpolate(d_)
        ang = math.atan2(b_.y - a_.y, b_.x - a_.x)
        if ok_plats(np.array([m_.x]), np.array([m_.y]))[0]:
            # transformens x-axel blir (E, N) = (cos, sin): vinkeln i E/N-planet direkt
            lagg(m_.x, m_.y, rng.uniform(1.2, 1.6), 0.5, 0.85, ang, 'hack'); n_hack += 1

# 3) Buskmark (OSM natural=scrub): cirka en buske per 40 m²
n_mark = 0
for gm, cls in feat['landcover']:
    if cls != 'scrub':
        continue
    minx, miny, maxx, maxy = gm.bounds
    n_ = int(gm.area / 40)
    if n_ < 1:
        continue
    pe = rng.uniform(minx, maxx, n_ * 2); pn = rng.uniform(miny, maxy, n_ * 2)
    from shapely import contains_xy
    inne = contains_xy(gm, pe, pn) & ok_plats(pe, pn)
    pe, pn = pe[inne][:n_], pn[inne][:n_]
    hh_ = rng.uniform(1.0, 2.4, pe.size)
    lagg(pe, pn, hh_, np.clip(0.5 + 0.35 * hh_, 0.6, 1.4), np.clip(0.5 + 0.35 * hh_, 0.6, 1.4),
         rng.uniform(0, 2 * math.pi, pe.size), 'buske')
    n_mark += pe.size

# 5) Snår ur orienteringskartan (okarta.py klassa): ljus/mellan/mörk grön = tätare och tätare
n_snar = 0
ok_fil = WORK / 'okarta_klass.npy'
if ok_fil.exists():
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import okarta
    ok_k = np.load(str(ok_fil))
    for kod, m2_per_buske, sly_andel in ((okarta.KODER['snar1'], 30.0, 0.1), (okarta.KODER['snar2'], 14.0, 0.25),
                                         (okarta.KODER['snar3'], 7.0, 0.4)):
        ri_, ci_ = np.nonzero((ok_k == kod) & (rng.random(ok_k.shape) < (RES * RES) / m2_per_buske))
        pe = OX + ci_ * RES + rng.uniform(-RES / 2, RES / 2, ri_.size)
        pn = OY - ri_ * RES + rng.uniform(-RES / 2, RES / 2, ri_.size)
        inne = ok_plats(pe, pn)
        pe, pn = pe[inne], pn[inne]
        hh_ = rng.uniform(1.2, 2.6, pe.size)
        rr_ = np.clip(0.5 + 0.35 * hh_, 0.6, 1.5)
        sly_ = rng.random(pe.size) < sly_andel
        for t_, m_ in (('sly', sly_), ('buske', ~sly_)):
            lagg(pe[m_], pn[m_], hh_[m_], rr_[m_], rr_[m_], rng.uniform(0, 2 * math.pi, m_.sum()), t_)
        n_snar += pe.size
    print('snår ur orienteringskartan:', n_snar, 'buskar')

# 4) Skogsbryn: sly på öppen mark inom 4 m från skog
skog = lc == LC['skog']
oppet = np.isin(lc, [LC['åker'], LC['äng'], LC['mark']])
bryn = oppet & ndi.binary_dilation(skog, iterations=max(int(4 / RES), 1))
ri_, ci_ = np.nonzero(bryn & (rng.random(bryn.shape) < (RES * RES) / 30.0))
pe = OX + ci_ * RES + rng.uniform(-RES / 2, RES / 2, ri_.size)
pn = OY - ri_ * RES + rng.uniform(-RES / 2, RES / 2, ri_.size)
inne = ok_plats(pe, pn)
pe, pn = pe[inne], pn[inne]
hh_ = rng.uniform(1.2, 2.8, pe.size)
lagg(pe, pn, hh_, np.clip(0.5 + 0.35 * hh_, 0.6, 1.5), np.clip(0.5 + 0.35 * hh_, 0.6, 1.5),
     rng.uniform(0, 2 * math.pi, pe.size), 'sly')
n_bryn = pe.size
print(f'buskar: laser {n_laser}, häck {n_hack}, buskmark {n_mark}, skogsbryn {n_bryn}')

if bE:
    bE, bN, bH, bR, bL, bY, bT = (np.concatenate(a) for a in (bE, bN, bH, bR, bL, bY, bT))
    bmark = ndi.map_coordinates(h_final, [(OY - bN) / RES, (bE - OX) / RES], order=1, mode='nearest')
    hogt = bmark >= 0.3
    skriv('buskar', 'buskar', bT[hogt], bE[hogt], bN[hogt], bmark[hogt] - 0.1, bH[hogt], bL[hogt], bR[hogt], bY[hogt])
print('klart')
