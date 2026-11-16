"""Steg 3: carva vägar i terrängen, bygg meshar (terräng, vägar, byggnader, vatten) och exportera."""
from pathlib import Path
import os
ROOT = Path(__file__).resolve().parent.parent
WORK = Path(os.environ.get('GEO_WORK', ROOT / 'work'))   # bygg.py --projekt sätter egen work-mapp
WORK.mkdir(exist_ok=True)
import sys, pickle, json, math, random
import numpy as np
from scipy import ndimage as ndi
from scipy.spatial import cKDTree
from rasterio.transform import from_origin
from rasterio.features import rasterize
from shapely.geometry import LineString, Polygon, Point, MultiPolygon, box
from shapely.ops import unary_union, triangulate
sys.path.insert(0, str(Path(__file__).resolve().parent))
import takform, husgeometri, broar, stenar, okarta, korridor, jarnvag, nvdb, vagmarkering, vagnat, vagyta, trummor, vagkant, lekplatser, valtbart, idrott, landmarken, overfarter, mapillary_objekt, platsdetaljer, stenlaggning
from shapely import affinity
import trimesh
from PIL import Image

OUT = sys.argv[1]
OBJ = sys.argv[2] if len(sys.argv) > 2 and Path(sys.argv[2]).exists() else None   # objekthöjd från laser
g = json.load(open(str(WORK / 'grid.json')))
W, H, RES, X0, Y1 = g['W'], g['H'], g['RES'], g['x0'], g['y1']
T = from_origin(X0, Y1, RES, RES)
h = np.load(str(WORK / 'h_raw.npy')).astype(np.float64)
land = np.load(str(WORK / 'land.npy'))
reg = pickle.load(open(str(WORK / 'region.pkl'), 'rb'))
feat = pickle.load(open(str(WORK / 'features.pkl'), 'rb'))
R_land, R_all, ROAD = reg['region_land'], reg['region'], reg['road']
rng = random.Random(851)
NAMN = os.environ.get('GEO_NAMN', 'vikbolandet_e851')   # filnamn för glb-filerna
BOX = box(X0, Y1 - H * RES, X0 + W * RES, Y1)   # hela spelrutan; vägar, vatten och hus gäller allt land här

# Världskoordinater i Godot: x = öst, z = syd, y = upp. Pixel (rad i, kolumn j) ligger på (j*RES, i*RES).
OX, OY = X0 + RES / 2, Y1 - RES / 2
def to_px(x, y):  # SWEREF -> (kolumn, rad) som flyttal
    return (x - OX) / RES, (OY - y) / RES
def to_world(x, y):
    return x - OX, OY - y

def sample(hh, xs, ys):
    c, r = to_px(np.asarray(xs), np.asarray(ys))
    return ndi.map_coordinates(hh, [r, c], order=1, mode='nearest')

# ---------- Vägar ---------- (vagnat.py: OSM-listan, körbanor genom korsningar, NVDB, harmonisering)
WIDTH, surface_of = vagnat.WIDTH, vagnat.surface_of
GC_MARKTACKE_M = 3.0   # GC-vägar minst så breda blir väg i marktäcket
roads = vagnat.vaglista(feat['roads'], BOX)
print('vägsegment', len(roads), 'total km', round(sum(r['line'].length for r in roads) / 1000, 1))
NV = vagnat.forbered(roads, (X0, Y1 - H * RES, X0 + W * RES, Y1), WORK)
BRO = broar.Broar(roads)   # brobanor och undergångar (broar.py)

# Täta ut mittlinjerna (var 2 m) och jämna ut längsprofilen
samples = []  # x, y, z, halvbredd, vägindex
for k, r in enumerate(roads):
    L = r['line']
    n = max(2, int(L.length / 2) + 1)
    ss = np.linspace(0, L.length, n)
    pts = np.array([L.interpolate(d).coords[0] for d in ss])
    z = sample(h, pts[:, 0], pts[:, 1])
    z = BRO.justera_profil(k, ss, z, lambda xs, ys: sample(h, xs, ys))  # rakt över däck
    z = ndi.gaussian_filter1d(z, sigma=max(1, min(8, n / 6)), mode='nearest')  # ~16 m utjämning
    r['pts'], r['z'], r['s'] = pts, z, ss
    if r['tags']['highway'] in ('path', 'footway'):
        continue  # stigar följer terrängen, ingen schaktning
    pa_dack = BRO.pa_bro(k, ss)
    dike = vagkant.dike_flagga(r)   # landsvägar utanför tätort får diken
    for (x, y), zz, dack, hh in zip(pts, z, pa_dack, r['hw']):
        if not dack:   # under däcken ligger marken kvar på den lägre nivån
            samples.append((x, y, zz, hh, k, dike))
S = np.array(samples)
SHOULDER = 8.0
tree = cKDTree(S[:, :2])
maxr = S[:, 3].max() + SHOULDER + 2.0
road_union = unary_union([r['line'].buffer(r['width'] / 2 + SHOULDER + 2.0) for r in roads
                          if r['tags']['highway'] not in ('path', 'footway')])
m = rasterize([(road_union, 1)], out_shape=(H, W), transform=T).astype(bool)
ii, jj = np.nonzero(m)
cx, cy = OX + jj * RES, OY - ii * RES
d, idx = tree.query(np.c_[cx, cy], distance_upper_bound=maxr)
ok = np.isfinite(d) & ~BRO.dack_raster((H, W), T)[ii, jj]
ii, jj, d, idx = ii[ok], jj[ok], d[ok], idx[ok]
hw = S[idx, 3]
t_ = np.clip((d - hw - 2.0) / SHOULDER, 0, 1)
w = 1 - (t_ * t_ * (3 - 2 * t_))  # smoothstep
h[ii, jj] = h[ii, jj] * (1 - w) + S[idx, 2] * w
# Diken längs landsvägarna (vagkant.py): en mjuk fåra DIKE_AVST_M från vägkanten
dike = S[idx, 5] > 0.5
rel = np.abs(d - hw - vagkant.DIKE_AVST_M) / vagkant.DIKE_HALV_M
prof = np.clip(1 - rel, 0, 1)
prof = prof * prof * (3 - 2 * prof)
h[ii[dike], jj[dike]] -= (vagkant.DIKE_DJUP_M * prof)[dike]
print('schaktade celler', len(ii), 'varav dike', int((dike & (prof > 0)).sum()))

# ---------- Sjöar/dammar: sänk terrängen ----------
water_polys = [part for gm, t in feat['water'] if gm.intersects(BOX)
               for part in getattr(gm.buffer(0), 'geoms', [gm.buffer(0)]) if part.geom_type == 'Polygon' and part.area > 1]
water_levels = []
for wp in water_polys:
    ring = np.array(wp.exterior.coords)
    lvl = float(np.percentile(sample(h, ring[:, 0], ring[:, 1]), 10)) - 0.3
    wm = rasterize([(wp.buffer(-1), 1)], out_shape=(H, W), transform=T).astype(bool) if wp.buffer(-1).area > 0 else None
    if wm is not None and wm.any():
        dist = ndi.distance_transform_edt(wm) * RES
        h[wm] = np.minimum(h[wm], lvl - np.minimum(dist[wm] * 0.15, 2.0))
    water_levels.append(lvl)

# Vattendrag i orienteringskartan som saknas i OSM (okarta.py klassa): läggs till som bäckar,
# men inte där de korsar vägar (där går de i trumma) eller ligger nära ett OSM-vattendrag
OK_VD = WORK / 'okarta_vattendrag.pkl'
OK_LINJER = None   # orienteringskartans vattendrag (buffrade), för att ge OSM-diken vatten
if OK_VD.exists():
    OK_LINJER = unary_union([LineString(xy).buffer(6.0) for xy in pickle.load(open(str(OK_VD), 'rb'))
                             if len(xy) >= 2])
    osm_vd = unary_union([gm for gm, _ in feat['waterways']]).buffer(6.0) if feat['waterways'] else None
    vagar_b = unary_union([r['line'].buffer(r['width'] / 2 + 1.5) for r in roads])
    n_ok = 0
    for xy in pickle.load(open(str(OK_VD), 'rb')):
        ln = LineString(xy).simplify(1.0)
        if ln.length < 20 or (osm_vd is not None and ln.intersection(osm_vd).length > 0.5 * ln.length):
            continue
        rest = ln.difference(vagar_b)
        if osm_vd is not None:
            rest = rest.difference(osm_vd)
        for part in getattr(rest, 'geoms', [rest]):
            if part.geom_type == 'LineString' and part.length >= 10:
                feat['waterways'].append((part, {'waterway': 'stream', 'kalla': 'orienteringskarta'}))
                n_ok += 1
    print('vattendrag ur orienteringskartan:', n_ok)

# Diken och bäckar: smal fåra
for geom, t in feat['waterways']:
    if t.get('tunnel') in ('culvert', 'yes'):
        continue  # trumma under väg: vägen ligger kvar på marken
    gg = geom.intersection(BOX)
    if gg.is_empty:
        continue
    depth = 0.6 if t.get('waterway') == 'ditch' else 1.0
    wm = rasterize([(gg.buffer(1.5), 1)], out_shape=(H, W), transform=T).astype(bool)
    h[wm] -= depth * 0.7
h = ndi.gaussian_filter(h, 0.6) * 0.5 + h * 0.5  # mjuka kanter efter schaktning
overfarter.forma(overfarter.las(WORK.parent), h, OX, OY, RES)   # körbara diken (<projekt>/overfarter.json)
BRO.schakta(h, sample, (H, W), T, OX, OY, RES)   # undergångar: fri höjd under däcken
TRUMMOR = trummor.las((X0, Y1 - H * RES, X0 + W * RES, Y1))   # vägtrummor (trummor.py)
trummor.schakta(TRUMMOR, h, (H, W), T, OX, OY, RES)
BRO.spara_mask(str(WORK / 'broar_mask.npy'), (H, W), T)   # step4: inga träd i schakt och på broar
# Järnväg (jarnvag.py): profil ur den orörda höjdmodellen, banvallen formas sist
BANA = jarnvag.Jarnvag(feat.get('rails', []), feat.get('platforms', []), BOX,
                       np.load(str(WORK / 'h_raw.npy')).astype(np.float64), sample)
BANA.vagportar(roads)   # vägar under järnvägsbroar: murar och däck (jarnvag.py)
BANA.forma(h, (H, W), T, OX, OY, RES)
# Idrottsplatser (idrott.py): löparbanor plattas till, läktare tas ur husen (byggs längre ned)
IDROTT = idrott.Idrott(feat, BOX)
LANDMARKEN = landmarken.Landmarken(feat, BOX)   # landmarken.py: hus som byggs efter sina OSM-delar
PLATS = platsdetaljer.Platsdetaljer(BOX)   # platsdetaljer.py: handplacerade föremål (platsdetaljer.json)
IDROTT.forma(h, (H, W), T, RES)
BANA.spara_mask(str(WORK / 'jarnvag_mask.npy'), (H, W), T)   # step4: inga träd nära spåret


# ---------- Marktäcke ----------
CLASSES = [('hav', (58, 96, 128)), ('mark', (122, 140, 82)), ('skog', (62, 92, 50)), ('åker', (170, 152, 96)),
           ('äng', (132, 160, 80)), ('tomt', (110, 130, 78)), ('gård', (128, 118, 92)), ('våtmark', (96, 112, 80)),
           ('berg', (112, 114, 100)), ('buskmark', (88, 110, 60)), ('strand', (196, 184, 140)), ('sjö', (64, 104, 132)),
           ('väg_asfalt', (70, 70, 72)), ('väg_grus', (150, 138, 116)), ('hårdgjord', (150, 148, 142))]
CIDX = {n: i for i, (n, _) in enumerate(CLASSES)}
cmap = dict(forest='skog', farmland='åker', meadow='äng', residential='tomt', farmyard='gård', wetland='våtmark',
            rock='berg', scrub='buskmark', beach='strand')
lc = np.where(land, CIDX['mark'], CIDX['hav']).astype(np.uint8)
order = ['farmland', 'meadow', 'residential', 'farmyard', 'forest', 'scrub', 'wetland', 'beach', 'rock']
for cls in order:
    gs = [gm for gm, c in feat['landcover'] if c == cls]
    if gs:
        mm = rasterize([(x, 1) for x in gs], out_shape=(H, W), transform=T).astype(bool) & land
        lc[mm] = CIDX[cmap[cls]]
# Orienteringskartan (okarta.py klassa), där den täcker: myr, odlad/öppen/halvöppen mark och snår.
# Tomt, hårdgjort och skog lämnas till OSM; öppen mark blir äng utom där OSM säger åker.
OKARTA_KLASS = WORK / 'okarta_klass.npy'
if OKARTA_KLASS.exists():
    ok_k = np.load(str(OKARTA_KLASS))
    if ok_k.shape == lc.shape:
        K = okarta.KODER
        for kod, klass in ((K['myr'], 'våtmark'), (K['odlad'], 'åker'), (K['halvoppen'], 'mark'),
                           (K['snar1'], 'buskmark'), (K['snar2'], 'buskmark'), (K['snar3'], 'buskmark')):
            lc[(ok_k == kod) & land] = CIDX[klass]
        lc[(ok_k == K['oppen']) & land & (lc != CIDX['åker'])] = CIDX['äng']
        print('orienteringskarta: marktäcke justerat på', int((ok_k != okarta.UTANFOR).sum()), 'celler')
    else:
        print('orienteringskarta: fel storlek, hoppar över', ok_k.shape, lc.shape)
if water_polys:
    lc[rasterize([(x, 1) for x in water_polys], out_shape=(H, W), transform=T).astype(bool)] = CIDX['sjö']
for r in roads:
    if r['tags']['highway'] in ('path', 'footway') and r['width'] < GC_MARKTACKE_M:
        continue   # smala stigar ligger på marken; breda GC-vägar (Märkesbacken) är väg, inget gräs genom dem
    mm = rasterize([(r['line'].buffer(r['width'] / 2), 1)], out_shape=(H, W), transform=T).astype(bool)
    lc[mm] = CIDX['väg_asfalt' if r['surface'] == 'asfalt' else 'väg_grus']
BANA.marktacke(lc, CIDX['väg_grus'], (H, W), T)
if IDROTT.planer():   # innerplanerna: gräsmatta (tomt), tartanen under banan: grus
    lc[rasterize([(p_, 1) for p_ in IDROTT.planer()], out_shape=(H, W), transform=T).astype(bool)] = CIDX['tomt']
    lc[rasterize([(p_, 1) for p_ in IDROTT.tartan()], out_shape=(H, W), transform=T).astype(bool)] = CIDX['väg_grus']
# Stenläggning (stenlaggning.py): hårdgjorda ytor inom platsdetaljer.json:s områden -> marktäcke 'hårdgjord'
STEN = stenlaggning.Stenlaggning(PLATS.conf.get('stenlaggning'), WORK, WORK.parent / 'data', NAMN)
STEN.berakna(lc, CIDX, to_px, RES, [gm for gm, t in feat['buildings'] if t.get('building') not in ('roof', 'carport')],
             water_polys, roads, karta=(X0, Y1 - H * RES, X0 + W * RES, Y1),
             byggnader_t=[(gm, t) for gm, t in feat['buildings'] if t.get('building') not in ('roof',)])
             # öppna tak (cykeltak) står på stenen
# Markvegetation för spelet (markvegetation.py): klass per 2 m-cell
import markvegetation
MV = markvegetation.bygg(lc, CIDX, T, (H, W), WORK.parent / 'data' if WORK.name == 'work' and WORK.parent != ROOT else ROOT / 'data',
                    [gm for gm, _ in feat['buildings']] + IDROTT.tartan() + [l for l, _, _ in IDROTT.laktare], OUT,
                    str(ROOT / 'forhandsbilder' / f'markvegetation_{NAMN}.png'), water_polys, RES,
                    [x[0] for x in feat.get('lekplatser', [])] + IDROTT.planer())   # gräsmatta
markvegetation.vatten(water_polys, water_levels, T, (H, W), OUT)   # sjöarnas nivåer för vadningen

# ---------- Markytor karvar ur terrängen (regel för allt som ritas som yta på marken) ----------
# GC-vägar (alla bredder), stenläggning och parkeringar är meshar några cm över h. Terrängen
# (Terrain3D delar rutorna i trianglar på sitt sätt, och vägarnas meshar har hörn bara i kanterna) kunde
# sticka upp genom dem, med gräs ovanpå. Därför: under varje ritad yta sänks den exporterade terrängen
# KARVA_M (bara celler vars mitt ligger på ytan: kanten lutar ned in under ytan, ingen synlig grop),
# och där växer inga grässtrån (markvegetation 0). Meshar och h_final (träd, föremål) använder det
# okarvade h, så ytorna ligger kvar där de låg.
KARVA_M = 0.10
# Bilvägar ligger redan 0,15 m över en planad profil (och vagnarna kör på terrängen): de karvas inte,
# men får inget gräs heller.
_ras = lambda gs: (rasterize([(g_, 1) for g_ in gs], out_shape=(H, W), transform=T).astype(bool)
                   if gs else np.zeros((H, W), bool))
_lag = [r['line'].buffer(r['width'] / 2) for r in roads if broar.lyft(r['tags']) < 0.1]
# Vägytan (vagyta.py): en sammanhängande yta med rundade korsningar och fyllda mittremsor
VY = vagyta.Vagyta(roads, BRO, [gm for gm, t in feat['buildings'] if gm.intersects(BOX)] + water_polys,
                   overtackt=STEN.overtackt, rutnat=(OX, OY))
YTMASK = _ras(_lag) | STEN.raster((H, W), OX, OY, RES)
YTMASK &= ~BRO.dack_raster((H, W), T)   # under broar ligger marken redan lägre
YTOR_ALLA = YTMASK | STEN.raster((H, W), OX, OY, RES, nagon=True) | _ras([r['line'].buffer(r['width'] / 2) for r in roads])   # allt som ritas som markyta (minsta del)
YTOR_ALLA |= VY.mask(_ras)
np.save(str(WORK / 'vagyta_mask.npy'), VY.mask(_ras, alla=True))   # step4: inga träd på vägytan
MV[YTOR_ALLA] = 0
MV.tofile(f'{OUT}/markvegetation.bin')
h_ut = h.copy()
h_ut[YTMASK] -= KARVA_M
print('markytor: terrängen karvad', KARVA_M, 'm under', int(YTMASK.sum()), 'celler')

# ---------- Heightmap-export ----------
hmin, hmax = float(h_ut.min()), float(h_ut.max())
u16 = np.round((h_ut - hmin) / (hmax - hmin) * 65535).astype(np.uint16)
Image.fromarray(u16).save(f'{OUT}/heightmap_16bit.png')
u16.astype('<u2').tofile(f'{OUT}/heightmap.r16')
np.save(str(WORK / 'h_final.npy'), h)
pal = np.array([c for _, c in CLASSES], np.uint8)
Image.fromarray(lc).save(f'{OUT}/landcover_index.png')
Image.fromarray(pal[lc]).save(f'{OUT}/landcover_color.png')

def srgb2lin_early(c):
    c = np.asarray(c, np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

# ---------- Terrängmesh (6 m rutnät, i rutor om ~600 m) ----------
STEP = 2
keep = rasterize([(R_all.buffer(150), 1)], out_shape=(H, W), transform=T).astype(bool)
scene = trimesh.Scene()
col_rgb = pal[lc].astype(np.float32)
col_rgb = ndi.uniform_filter(col_rgb, size=(STEP, STEP, 1))
TILE = 128  # vertexar per ruta
gi = np.arange(0, H, STEP); gj = np.arange(0, W, STEP)
ntiles = 0
terrain_tiles = []
for ti in range(0, len(gi) - 1, TILE):
    for tj in range(0, len(gj) - 1, TILE):
        ri = gi[ti:ti + TILE + 1]; rj = gj[tj:tj + TILE + 1]
        sub_keep = keep[np.ix_(ri, rj)]
        if not sub_keep.any():
            continue
        Z = h[np.ix_(ri, rj)]
        JJ, II = np.meshgrid(rj, ri)
        V = np.c_[JJ.ravel() * RES, Z.ravel(), II.ravel() * RES]
        C = np.c_[np.round(srgb2lin_early(col_rgb[np.ix_(ri, rj)].reshape(-1, 3)) * 255), np.full(V.shape[0], 255)].astype(np.uint8)
        nr, nc = len(ri), len(rj)
        a = (np.arange(nr - 1)[:, None] * nc + np.arange(nc - 1)[None, :])
        qk = sub_keep[:-1, :-1] | sub_keep[1:, 1:] | sub_keep[1:, :-1] | sub_keep[:-1, 1:]
        a = a[qk]
        F = np.r_[np.c_[a, a + nc, a + 1], np.c_[a + 1, a + nc, a + nc + 1]]
        mesh = trimesh.Trimesh(V, F, vertex_colors=C, process=False)
        mesh.remove_unreferenced_vertices()
        terrain_tiles.append((f'Terrang_{ti // TILE}_{tj // TILE}', mesh))  # läggs i scenen vid exporten
        ntiles += 1
print('terrängrutor', ntiles)

def srgb2lin(c):
    c = np.asarray(c, np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def mat(name, rgb, rough=0.9):
    # glTF anger färger linjärt; vi skriver färgerna i sRGB och konverterar
    return trimesh.visual.material.PBRMaterial(name=name, baseColorFactor=[*srgb2lin(rgb), 1.0], roughnessFactor=rough, metallicFactor=0.0)

# ---------- Sammanslagning per ruta och material ----------
# Tusentals små meshar blir tusentals draw calls i Godot. Vägar och hus samlas därför i en mesh
# per 250 m-ruta, grupp och material. Läggs i scenen av flush_merged() innan exporten.
MERGE_TILE = 250.0
merged = {}

def add_merged(group, mesh, material, uv=None):
    tx, tz = (mesh.vertices[:, [0, 2]].mean(0) // MERGE_TILE).astype(int)
    e = merged.setdefault((group, int(tx), int(tz), material.name), dict(V=[], F=[], UV=[], n=0, mat=material))
    e['V'].append(np.asarray(mesh.vertices)); e['F'].append(np.asarray(mesh.faces) + e['n']); e['UV'].append(uv)
    e['n'] += len(mesh.vertices)

def flush_merged():
    for (group, tx, tz, mname), e in sorted(merged.items()):
        m = trimesh.Trimesh(np.vstack(e['V']), np.vstack(e['F']), process=False)
        uv = np.vstack(e['UV']) if all(u is not None for u in e['UV']) else None
        m.visual = trimesh.visual.TextureVisuals(uv=uv, material=e['mat'])
        name = f'{group}_{tx}_{tz}_{mname}'
        scene.add_geometry(m, node_name=f'{group}/{name}', geom_name=name, parent_node_name=group)
    print('sammanslagna meshar', len(merged))

# ---------- Vägmeshar ----------
ROADMAT = dict(asfalt=mat('Vag_asfalt', (62, 62, 64), 0.8), grus=mat('Vag_grus', (150, 138, 116)), stig=mat('Stig', (118, 100, 76)))
# Asfaltens ålder: beläggningsåret ur NVDB (statliga vägar), annars stabilt slumpat per väg
ASFALT_ALDER = [(4, mat('Vag_asfalt_ny', (46, 46, 49), 0.75)), (12, ROADMAT['asfalt']),
                (999, mat('Vag_asfalt_gammal', (74, 73, 72), 0.85))]
def asfalt_mat(r):
    ar = r['bel_ar'][np.isfinite(r['bel_ar'])]
    if len(ar):
        alder = 2026 - float(np.median(ar))
    else:   # samma gata (namn/vägnummer) får samma ålder, så nyansen inte byter mitt på gatan
        import zlib
        nyckel = r['tags'].get('name') or r['tags'].get('ref') or '%.0f,%.0f' % r['line'].coords[0]
        alder = [2, 8, 8, 8, 16][zlib.crc32(nyckel.encode()) % 5]
    return next(m for grans, m in ASFALT_ALDER if alder < grans)
road_json = []
scene.graph.update(frame_to='Vagar', frame_from=scene.graph.base_frame)
for k, r in enumerate(roads):
    pts = r['pts']
    if len(pts) < 2:
        continue
    dvec = np.gradient(pts, axis=0)
    dvec /= np.maximum(np.linalg.norm(dvec, axis=1, keepdims=True), 1e-9)
    nrm = np.c_[-dvec[:, 1], dvec[:, 0]]
    hw = r['hw'][:, None]
    L = pts + nrm * hw; Rr = pts - nrm * hw
    lift = broar.lyft(r['tags'])
    if r['tags']['highway'] in ('path', 'footway') and r['width'] < GC_MARKTACKE_M:
        zl = sample(h, L[:, 0], L[:, 1]) + lift; zr = sample(h, Rr[:, 0], Rr[:, 1]) + lift
    else:
        zc = np.maximum(sample(h, pts[:, 0], pts[:, 1]), np.maximum(sample(h, L[:, 0], L[:, 1]), sample(h, Rr[:, 0], Rr[:, 1])))
        zl = zr = zc + lift
    dack = VY.pa_dack(k, r['s'])
    zd = np.maximum(r['z'] + lift, VY.tak_hojd(pts, k)) if dack.any() else r['z'] + lift   # aldrig under tunneltaken
    zl = np.where(dack, zd, zl); zr = np.where(dack, zd, zr)  # brobanans yta
    r['zm'], r['nrm'] = (zl + zr) / 2, nrm   # vägmarkeringarna (vagmarkering.py)
    cw = np.array([to_world(*p) for p in pts[::2]] + ([to_world(*pts[-1])] if (len(pts) - 1) % 2 else []))
    cz = np.r_[r['z'][::2], [r['z'][-1]] if (len(pts) - 1) % 2 else []]
    road_json.append(dict(name=r['name'], highway=r['tags']['highway'], ref=r['tags'].get('ref'), surface=r['surface'],
                          width_m=r['width'], osm_name=r['tags'].get('name'),
                          points=[[round(float(x), 2), round(float(z), 2), round(float(y), 2)] for (x, y), z in zip(cw, cz)]))
VY.bygg(h, sample, to_world, add_merged, asfalt_mat, ROADMAT, vit=mat('Vagmarkering', (232, 232, 226), 0.6), matfn=mat)
VY.refuger(feat.get('vagpunkter', []), h, sample, to_world, add_merged, mat)   # öar vid övergångsställen   # ytorna (vagyta.py) i stället för band per väg
MARK = vagmarkering.Markering(roads, NV, feat.get('vagpunkter', []))
MARK.bygg(add_merged, mat, to_world)
scene.graph.update(frame_to='Broar', frame_from=scene.graph.base_frame)
BRO.bygg_meshar(h, sample, to_world, add_merged, mat('Betong', (150, 148, 142), 0.95),
                mat('Tra', (120, 88, 58), 0.9), mat('Racke', (72, 74, 76), 0.6), mat=mat)
# Vägkanten (vagkant.py): kantstolpar, lyktor, räcken, skyltar, hållplatser
scene.graph.update(frame_to='Vagkant', frame_from=scene.graph.base_frame)
VALT = valtbart.Samling()   # vältbart (lyktstolpar, kontaktledning): glb-gruppen Valtbart
vagkant.Vagkant(roads, MARK.korsningar, feat.get('vagpunkter', []), h, np.load(str(WORK / 'h_raw.npy')).astype(np.float64),
                sample, to_world, add_merged, mat, valt=VALT, overgangar=MARK.overgangar,
                mly=mapillary_objekt.MlyObjekt(WORK.parent / 'data'),   # verkliga lyktor och skyltar
                platser=json.loads((WORK / 'platser.json').read_text()) if (WORK / 'platser.json').exists() else None
                ).bygg()   # platser.json: platser.py (ortnamnsskyltarna)
# Lekplatser (lekplatser.py): redskap i OSM:s lekplatsytor, unika per park
scene.graph.update(frame_to='Lekplatser', frame_from=scene.graph.base_frame)
scene.graph.update(frame_to='Lekplatsunderlag', frame_from=scene.graph.base_frame)
_lek_stopp = np.isin(lc, [CIDX['väg_asfalt'], CIDX['väg_grus'], CIDX['sjö'], CIDX['hav']])
if feat['buildings']:
    _lek_stopp |= rasterize([(gm.buffer(1.0), 1) for gm, _ in feat['buildings']], out_shape=(H, W), transform=T).astype(bool)
def _lek_hinder(E, N):
    c, r_ = to_px(E, N)
    i_, j_ = int(round(r_)), int(round(c))
    return not (0 <= i_ < H and 0 <= j_ < W) or bool(_lek_stopp[i_, j_])
_lek = lekplatser.bygg([x for x in feat.get('lekplatser', []) if x[0].intersects(BOX)], feat.get('lekredskap', []),
                       sample, h, to_world, scene, add_merged, mat, _lek_hinder)
_lek_mask = np.zeros((H, W), bool)   # step4: inga träd eller buskar på redskapen
for _poly, _pts in _lek:
    for _p in _pts:
        c, r_ = to_px(*_p)
        _lek_mask[max(int(r_) - 2, 0):int(r_) + 3, max(int(c) - 2, 0):int(c) + 3] = True
# Platsdetaljer (platsdetaljer.py): konst, lampor, Studenthuset ...; träd och buskar hålls borta via lekplatsmasken
if STEN:
    scene.graph.update(frame_to='Stenlaggning', frame_from=scene.graph.base_frame)
    STEN.bygg(sample, h, to_world, add_merged, mat)
if PLATS.lista:
    for grupp in ('Byggnader_konst', 'Konst'):
        scene.graph.update(frame_to=grupp, frame_from=scene.graph.base_frame)
    _laser_tidig = None
    if OBJ:
        from laserhus import Objekthojd
        _laser_tidig = Objekthojd(OBJ)
    PLATS.bygg(sample, h, to_world, add_merged, mat, valt=VALT, laser=_laser_tidig)
    for _E, _N in STEN.tradfritt():   # Blå havet: inga (gamla) laserträd på torget
        PLATS.punkter.append((_E, _N, 0.6))
    for _E, _N, _r in PLATS.punkter:
        c, r_ = to_px(_E, _N)
        _k = int(math.ceil(_r / RES))
        _lek_mask[max(int(r_) - _k, 0):int(r_) + _k + 1, max(int(c) - _k, 0):int(c) + _k + 1] = True
_lek_mask |= STEN.asfalt_mask((H, W), T)   # inga träd på parkeringarnas asfalt (step4)
np.save(str(WORK / 'lekplatser_mask.npy'), _lek_mask)
# Löparbanor och läktare (idrott.py)
if IDROTT:
    for grupp in ('Idrott', 'Byggnader_laktare'):
        scene.graph.update(frame_to=grupp, frame_from=scene.graph.base_frame)
    IDROTT.bygg(sample, h, to_world, add_merged, mat, valt=VALT)
np.save(str(WORK / 'idrott_mask.npy'), IDROTT.mask((H, W), T))   # step4: inga träd eller buskar
if LANDMARKEN.lista:
    scene.graph.update(frame_to='Byggnader_landmarken', frame_from=scene.graph.base_frame)
    LANDMARKEN.bygg(sample, h, to_world, add_merged)
# Vägtrummor (trummor.py, Trafikverket): rörändar i vägbankarna
scene.graph.update(frame_to='Trummor', frame_from=scene.graph.base_frame)
trummor.bygg(TRUMMOR, h, sample, to_world, add_merged, mat)
if BANA:
    for grupp in ('Jarnvag', 'Banhinder'):
        scene.graph.update(frame_to=grupp, frame_from=scene.graph.base_frame)
    BANA.bygg_meshar(h, sample, to_world, add_merged, mat, valt=VALT)

# ---------- Stenblock ur orienteringskartan (stenar.py) ----------
STEN_FIL = WORK / 'okarta_stenar.npy'
sten_mask = np.zeros((H, W), bool)
if STEN_FIL.exists():
    hus_r = rasterize([(gm.buffer(2.0), 1) for gm, _ in feat['buildings']], out_shape=(H, W),
                      transform=T).astype(bool) if feat['buildings'] else np.zeros((H, W), bool)
    bro_r = np.load(str(WORK / 'broar_mask.npy')) if (WORK / 'broar_mask.npy').exists() else np.zeros((H, W), bool)
    stopp = hus_r | bro_r | np.isin(lc, [CIDX['väg_asfalt'], CIDX['väg_grus'], CIDX['sjö'], CIDX['hav']])
    stopp |= ndi.binary_dilation(YTOR_ALLA, iterations=1)   # inga stenblock på (eller vid kanten av) någon markyta
    def sten_hinder(E, N):
        c, r_ = to_px(E, N)
        i_, j_ = int(round(r_)), int(round(c))
        return not (0 <= i_ < H and 0 <= j_ < W) or bool(stopp[i_, j_]) or not korridor.inne(WORK, E, N)[0]
    scene.graph.update(frame_to='Stenar', frame_from=scene.graph.base_frame)
    auto = np.load(str(STEN_FIL))
    inmatta = []
    if (WORK.parent / 'stenar_manuellt.json').exists():
        inmatta, auto = stenar.manuella(str(WORK.parent / 'stenar_manuellt.json'), auto)
    lagda = stenar.bygg_stenar(auto, sample, h, to_world, add_merged,
                               mat('Sten', (128, 126, 120), 0.95), sten_hinder, inmatta)
    for E, N, rad in lagda:   # inga träd eller buskar på stenarna (step4)
        c, r_ = to_px(E, N)
        n_ = int(np.ceil(rad / RES)) + 1
        i_, j_ = int(round(r_)), int(round(c))
        sten_mask[max(i_ - n_, 0):i_ + n_ + 1, max(j_ - n_, 0):j_ + n_ + 1] = True
np.save(str(WORK / 'stenar_mask.npy'), sten_mask)
json.dump(dict(coordinate_note='Godot-koordinater [x, y(höjd), z] i meter; x=öst, z=syd. Se heightmap_info.json',
               roads=road_json), open(f'{OUT}/roads.json', 'w'), ensure_ascii=False)

# ---------- Byggnader ----------
# Husen samlas först (add_building) och byggs i bygg_alla_hus(): takform ur laserdatan (takform.py),
# hustyp och stil ur stilar.json (husstil.py), fasader med fönster ur en atlas (husgeometri.py).
import husstil, husfarger
husstil.satt_mat(mat)
MAT_ROOF_TIN = mat('Tak_plat', (90, 92, 94), 0.5)
LUTANDE = ('sadel', 'valmat', 'talt')
# Schablon utan laserträffar: takfotshöjd (m) och takvinkel (grader, 0 = platt) per hustyp
SCHABLON = dict(villa=(4.2, 35), radhus=(5.4, 30), flerbostadshus=(9.0, 0), kontor=(10.0, 0), butik=(5.0, 0),
                industri=(7.0, 0), gard=(4.6, 38), lada=(5.0, 28), uthus=(2.4, 25), kyrka=(8.5, 45))
LANDSBYGD_GRANNAR = 8       # färre hus än så inom 100 m = landsbygd
TAKSTAT = {}; HUSSTAT = {}
HUS = []                    # (polygon, OSM-taggar, grupp, laserhöjder (takfot, nock) eller None)

def orient(V, faces, roof, ctr):
    out = []
    for f in faces:
        a_, b_, c_ = V[f[0]], V[f[1]], V[f[2]]
        n = np.cross(b_ - a_, c_ - a_)
        if roof:
            bad = n[1] < 0
        else:
            fc = (a_ + b_ + c_) / 3
            bad = n[0] * (fc[0] - ctr[0]) + n[2] * (fc[2] - ctr[1]) < 0
        out.append([f[0], f[2], f[1]] if bad else list(f))
    return out

def add_building(poly, taggar, group, heights=None):
    HUS.append((poly, taggar or {}, group, heights))

def add_part(group, V, UV, faces, roof, ctr, material, plan=False):
    """Lägger en grupp trianglar i sammanslagningen. plan=True: UV i meter (tak), skalade
    med materialets uv_skala om det har en (semirealistiska takpannor)."""
    if not faces:
        return
    F = np.array(orient(V, faces, roof, ctr))
    used, inv = np.unique(F, return_inverse=True)
    Vs = V[used]; Fs = inv.reshape(F.shape)
    if plan:
        uv = husgeometri.plan_uv(Vs, Fs)
        if getattr(material, 'uv_skala', None):
            uv = uv * material.uv_skala
    else:
        uv = UV[used]
    add_merged(group, trimesh.Trimesh(Vs, Fs, process=False), material, uv)

MAT_TAKUNDER = mat('Takunder', (92, 80, 68), 0.9)   # takfotens undersida (målade brädor)

def add_takunder(group, V, faces, ctr):
    """Takets undersida: samma trianglar vända nedåt, så att takutsprånget syns underifrån
    (Godot ritar inte baksidor)."""
    if not faces:
        return
    F = np.array([[a_, c_, b_] for a_, b_, c_ in orient(V, faces, True, ctr)])
    used, inv = np.unique(F, return_inverse=True)
    add_merged(group, trimesh.Trimesh(V[used], inv.reshape(F.shape), process=False), MAT_TAKUNDER)

def schablontak(delar, hustyp, heights):
    """Tak utan laserträffar: schablon per hustyp, eller laserhöjderna (takfot, nock) om de finns."""
    takfot, vinkel = SCHABLON[hustyp]
    if heights is not None:
        takfot = float(np.clip(heights[0], 2.0, 40.0))
        vinkel = vinkel if heights[1] - takfot > 0.8 else 0
    ut = []
    for d in delar:
        mitt, u, v, a, b = takform.ram(d)
        if vinkel and b <= 8.0:
            topp = takfot + math.tan(math.radians(vinkel)) * b
            if heights is not None:
                topp = max(float(heights[1]), takfot + 1.0)
            ut.append(takform.Tak('sadel', mitt, u, v, a, b, takfot, topp))
        else:
            ut.append(takform.Tak('platt', mitt, u, v, a, b, takfot, takfot))
    return ut

def takfarg(t, stil):
    if t.modell == 'platt':
        return 'papp'
    if t.modell == 'pulpet':
        return stil['tak_namn'] if stil['tak_namn'].startswith(('plat', 'papp')) else 'plat_svart'
    return stil['tak_namn']

def semi_omrade():
    """Områden (stilar.json 'semirealistiskt') där husen får den semirealistiska fasaden."""
    delar = []
    for o in husstil.KATALOG.get('semirealistiskt', []):
        if o.get('karta') not in (NAMN, None):
            continue
        linjer = [r['line'] for r in roads if r['name'] == o['vag']]
        if linjer:
            delar.append(unary_union(linjer).buffer(o.get('avstand_m', 40)))
    return unary_union(delar) if delar else None

def bygg_alla_hus():
    if not HUS:
        return
    mitter = np.array([[p.centroid.x, p.centroid.y] for p, *_ in HUS])
    grannar = cKDTree(mitter).query_ball_point(mitter, 100.0, return_length=True)
    semi_ytor = semi_omrade()
    planer = []
    # Verkliga färger (husfarger.py): taken ur ortofotot, fasaderna ur Mapillary (husfarger.json)
    data_mapp = WORK.parent / 'data'
    tak_rgb = husfarger.tak_fran_ortofoto(data_mapp / f'ortofoto_{WORK.parent.name}.tif', [p_[0] for p_ in HUS])
    fasader = husfarger.fasadfarger(data_mapp)
    n_tak = sum(1 for c in tak_rgb if c is not None)
    n_fasad = 0
    for k, (poly, taggar, group, heights) in enumerate(HUS):
        tak_fam = None if taggar.get('roof:colour') else husfarger.familj(tak_rgb[k])   # OSM:s färg går före
        f_nyckel = husfarger.nyckel(poly, taggar) if fasader else None
        if f_nyckel in fasader and not taggar.get('building:colour'):
            taggar = dict(taggar, **{'building:colour': fasader[f_nyckel]})
            n_fasad += 1
        taggar = PLATS.justera_hus(poly, taggar)   # platsdetaljer.json hus_justera: fasadstil
        poly = poly.buffer(0)
        if poly.geom_type == 'MultiPolygon':
            poly = max(poly.geoms, key=lambda q: q.area)
        if poly.is_empty or poly.area < 4:
            continue
        ring = np.array(poly.exterior.coords)
        gz = np.r_[sample(h, ring[:, 0], ring[:, 1]), sample(h, [poly.centroid.x], [poly.centroid.y])]
        delar = takform.dela_i_rektanglar(poly)
        tak = []
        if laser is not None:
            tolkade = [takform.tolka_delar(d, laser) for d in delar]
            giltiga = [t for ts in tolkade for t in ts]
            if giltiga:
                for d, ts in zip(delar, tolkade):
                    if not ts:
                        mitt, u, v, a, b = takform.ram(d)
                        ts = [takform.Tak('platt', mitt, u, v, a, b, giltiga[0].takfot, giltiga[0].takfot)]
                    tak += ts
        landsbygd = grannar[k] < LANDSBYGD_GRANNAR
        hojd = max((t.topp for t in tak), default=float(heights[1]) if heights is not None else 0.0)
        hustyp = husstil.klassa(taggar, poly.area, hojd, landsbygd)
        if not tak:
            tak = schablontak(delar, hustyp, heights)
        stil = husstil.valj_stil(hustyp, taggar, (round(poly.centroid.x), round(poly.centroid.y)))
        semi = semi_ytor is not None and semi_ytor.contains(poly.centroid)
        planer.append((poly, group, gz, tak, stil, semi, tak_fam))
        HUSSTAT[hustyp] = HUSSTAT.get(hustyp, 0) + 1
        for t in tak:
            TAKSTAT[t.modell] = TAKSTAT.get(t.modell, 0) + 1
    print(f'husfärger: tak ur ortofotot {n_tak}/{len(HUS)}, fasader ur Mapillary {n_fasad}')
    atlas = husstil.Atlas(bara={p[4]['id'] for p in planer if not p[5]})
    semi_ids = {p[4]['id'] for p in planer if p[5]}
    atlas_semi = husstil.Atlas(semi=True, bara=semi_ids) if semi_ids else None
    for poly, group, gz, tak, stil, semi, tak_fam in planer:
        at = atlas_semi if semi else atlas
        ref = gz.mean(); bas = gz.min() - 0.6
        storsta = max(range(len(tak)), key=lambda i: tak[i].halv_l * tak[i].halv_b)
        for i, t in enumerate(tak):
            fasad = dict(atlas=at, variant=stil['id'], vaning_m=stil['vaning_m'], fack_m=husstil.FACK_M,
                         dorr=i == storsta, knutar=stil['knutar'],
                         skorsten=stil['skorsten'] and i == storsta and t.modell in LUTANDE)
            V, UV, grupper = husgeometri.bygg_del(t, to_world, ref, bas, fasad)
            ctr = to_world(*t.mitt)
            for namn, (faces, gctr, roof) in grupper.items():
                if namn == 'tak':
                    tnamn = husfarger.tak_namn(tak_fam, t.modell, stil['tak_namn']) if tak_fam else takfarg(t, stil)
                    add_part(group, V, UV, faces, True, ctr, husstil.tak(tnamn, semi), plan=True)
                    if t.modell in ('sadel', 'valmat', 'talt'):   # de har takutsprång
                        add_takunder(group, V, faces, ctr)
                else:
                    add_part(group, V, UV, faces, roof, gctr or ctr, at.material())
    print('hustyper:', dict(sorted(HUSSTAT.items(), key=lambda x: -x[1])),
          f"semirealistiska {sum(1 for p in planer if p[5])}")
    print('takformer (delar):', TAKSTAT)
    atlas.albedo.save(f'{OUT}/fasadatlas.png')
    if atlas_semi:
        atlas_semi.albedo.save(f'{OUT}/fasadatlas_semi.png')

scene.graph.update(frame_to='Byggnader_OSM', frame_from=scene.graph.base_frame)
laser = None
if OBJ:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from laserhus import Objekthojd
    laser = Objekthojd(OBJ)
osm_b = [(gm, t) for gm, t in feat['buildings'] if BOX.intersects(gm)
         and korridor.inne(WORK, gm.centroid.x, gm.centroid.y)[0]]   # korridorkarta: bara nära rutten
bpolys = []
n_h = 0
for k, (gm, t) in enumerate(osm_b):
    hh = laser.heights_in(gm) if laser else None
    n_h += hh is not None
    bpolys.append(gm)
    if LANDMARKEN.ar(t) or PLATS.ar(t):
        continue   # byggs av landmarken.py / platsdetaljer.py
    add_building(gm, t, 'Byggnader_OSM', hh)
print('OSM-byggnader', len(osm_b), 'varav med laserhöjd', n_h)

if laser:
    # Hus ur laserdatan: bara på land, inte på vägar, i vatten eller där OSM redan har hus
    scene.graph.update(frame_to='Byggnader_laser', frame_from=scene.graph.base_frame)
    excl = unary_union([b.buffer(1.0) for b in bpolys]
                       + [r['line'].buffer(r['width'] / 2 + 1.0) for r in roads if r['tags']['highway'] not in ('path', 'footway')]
                       + water_polys + IDROTT.ytor() + PLATS.fotavtryck())   # platsdetaljer.py bygger egna hus där
    n_l = 0
    for rect, poly in laser.detect(exclude=excl):
        c_, r_ = to_px(rect.centroid.x, rect.centroid.y)
        if not land[int(np.clip(round(r_), 0, H - 1)), int(np.clip(round(c_), 0, W - 1))]:
            continue
        if not korridor.inne(WORK, rect.centroid.x, rect.centroid.y)[0]:
            continue
        hh = laser.heights_in(poly)
        add_building(poly, {}, 'Byggnader_laser', hh)
        n_l += 1
    print('laserbyggnader', n_l)

def placeholders():
    """Påhittade hus där OSM saknar hus; används bara utan laserdata."""
    scene.graph.update(frame_to='Byggnader_platshallare', frame_from=scene.graph.base_frame)
    # Platshållare där OSM saknar hus: tomter, gårdar och namngivna gårdar/torp
    road_lines = unary_union([r['line'] for r in roads])
    occupied = unary_union(bpolys) if bpolys else Polygon()
    roadbuf = unary_union([r['line'].buffer(r['width'] / 2 + 4) for r in roads])
    water_u = unary_union(water_polys) if water_polys else Polygon()
    placed = []

    def try_place(cx, cy, kind, dims, near_road=True):
        blocked = unary_union([occupied, roadbuf, water_u] + [p.buffer(5) for p in placed])
        # rikta huset mot närmaste väg
        pt = Point(cx, cy)
        ang = 0.0
        if near_road and not road_lines.is_empty:
            d0 = road_lines.project(pt) if road_lines.geom_type == 'LineString' else None
            nearest = min(getattr(road_lines, 'geoms', [road_lines]), key=lambda l: l.distance(pt))
            s = nearest.project(pt); a_ = nearest.interpolate(max(0, s - 3)); b_ = nearest.interpolate(min(nearest.length, s + 3))
            ang = math.degrees(math.atan2(b_.y - a_.y, b_.x - a_.x))
        L_, B_ = dims
        rect = affinity.rotate(box(cx - L_ / 2, cy - B_ / 2, cx + L_ / 2, cy + B_ / 2), ang + rng.uniform(-6, 6), origin=(cx, cy))
        if rect.intersects(blocked) or not R_land.buffer(-3).contains(rect):
            return False
        add_building(rect, {'building': dict(hus='house', lada='barn', bod='shed')[kind]}, 'Byggnader_platshallare')
        placed.append(rect)
        return True

    def scatter(poly, kind, dims, n_target, tries=60):
        minx, miny, maxx, maxy = poly.bounds
        got = 0
        for _ in range(tries):
            if got >= n_target:
                break
            x = rng.uniform(minx, maxx); y = rng.uniform(miny, maxy)
            if poly.buffer(-4).contains(Point(x, y)) and try_place(x, y, kind, dims):
                got += 1
        return got

    HOUSE = lambda: (rng.uniform(10, 14), rng.uniform(7, 8.5))
    BARN = lambda: (rng.uniform(22, 34), rng.uniform(11, 15))
    SHED = lambda: (rng.uniform(4, 7), rng.uniform(3, 4.5))
    for gm, c in feat['landcover']:
        if c not in ('residential', 'farmyard') or not R_land.intersects(gm):
            continue
        gm = gm.intersection(R_land)
        if gm.is_empty or gm.intersects(occupied.buffer(2)) and c == 'farmyard':
            continue
        if c == 'farmyard':
            scatter(gm, 'hus', HOUSE(), 1); scatter(gm, 'lada', BARN(), 1); scatter(gm, 'bod', SHED(), 1)
        else:
            existing = sum(1 for b in bpolys if gm.intersects(b))
            target = int(np.clip(gm.area / 3000, 1, 8)) - existing
            if target > 0:
                n_ = scatter(gm, 'hus', HOUSE(), target, tries=40 * target)
                scatter(gm, 'bod', SHED(), max(1, n_ // 2), tries=20 * max(1, n_))
    for pt, t in feat['points']:
        if t.get('place') not in ('isolated_dwelling', 'farm', 'hamlet') or not R_land.contains(pt):
            continue
        if occupied.distance(pt) < 60 or any(p.distance(pt) < 60 for p in placed):
            continue
        nh = dict(isolated_dwelling=1, farm=1, hamlet=3)[t['place']]
        for _ in range(nh):
            for _try in range(25):
                if try_place(pt.x + rng.uniform(-35, 35), pt.y + rng.uniform(-35, 35), 'hus', HOUSE()):
                    break
        if t['place'] == 'farm':
            for _try in range(25):
                if try_place(pt.x + rng.uniform(-50, 50), pt.y + rng.uniform(-50, 50), 'lada', BARN()):
                    break
    print('platshållare', len(placed))

if laser is None:
    placeholders()
bygg_alla_hus()

# ---------- Vatten ----------
MAT_SEA = mat('Hav', (40, 78, 108), 0.15); MAT_LAKE = mat('Sjo', (44, 84, 110), 0.15)
# Havsyta: ett enda plan på y = 0 över hela rutnätet plus marginal. Land ligger alltid
# minst 0,25 m över havet, så strandlinjen blir där terrängen skär planet.
SEA_MARGIN = 4000.0
x_lo, z_lo = -SEA_MARGIN, -SEA_MARGIN
x_hi, z_hi = (W - 1) * RES + SEA_MARGIN, (H - 1) * RES + SEA_MARGIN
Vs = np.array([[x_lo, 0, z_lo], [x_hi, 0, z_lo], [x_hi, 0, z_hi], [x_lo, 0, z_hi]])
Fs = np.array([[0, 2, 1], [0, 3, 2]])
sea = trimesh.Trimesh(Vs, Fs, process=False)
if sea.face_normals[:, 1].mean() < 0:
    sea.faces = sea.faces[:, ::-1]
sea.visual = trimesh.visual.TextureVisuals(material=MAT_SEA)
scene.add_geometry(sea, node_name='Hav_niva0', geom_name='Hav_niva0')
for k, (wp, lvl) in enumerate(zip(water_polys, water_levels)):
    wp2 = wp.intersection(R_all.buffer(150))
    for part in getattr(wp2, 'geoms', [wp2]):
        if part.geom_type != 'Polygon' or part.area < 4:
            continue
        verts, faces = [], []
        for tri in triangulate(part):
            if not part.contains(tri.centroid):
                continue
            n0 = len(verts)
            for p in list(tri.exterior.coords)[:3]:
                q = to_world(*p); verts.append([q[0], lvl, q[1]])
            faces.append([n0, n0 + 1, n0 + 2])
        if faces:
            msh = trimesh.Trimesh(verts, faces, process=False)
            if msh.face_normals[:, 1].mean() < 0:
                msh.faces = msh.faces[:, ::-1]
            msh.visual = trimesh.visual.TextureVisuals(material=MAT_LAKE)
            scene.add_geometry(msh, node_name=f'Sjo_{k}', geom_name=f'Sjo_{k}')

# Bäckar och åar: en vattenyta i den utgrävda fåran (trummor och tunnlar hoppas över)
VATTENDRAG_BREDD = dict(stream=1.6, river=5.0, canal=4.0)
n_vd = 0
for geom, t in feat['waterways']:
    if t.get('tunnel'):
        continue
    if t.get('waterway') not in VATTENDRAG_BREDD:
        # diken med vatten: där orienteringskartan ritar ett heldraget vattendrag
        if t.get('waterway') not in ('ditch', 'drain') or OK_LINJER is None \
                or geom.intersection(OK_LINJER).length < 0.5 * geom.length:
            continue
        t = dict(t, waterway='stream')
    gg = geom.intersection(BOX)
    for part in getattr(gg, 'geoms', [gg]):
        if part.geom_type != 'LineString' or part.length < 6:
            continue
        n_ = max(2, int(part.length / 2) + 1)
        pts = np.array([part.interpolate(d).coords[0] for d in np.linspace(0, part.length, n_)])
        dv = np.gradient(pts, axis=0)
        dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
        nrm = np.c_[-dv[:, 1], dv[:, 0]]
        bw = VATTENDRAG_BREDD[t['waterway']] / 2
        botten = sample(h, pts[:, 0], pts[:, 1])
        kant = np.minimum(sample(h, *(pts + nrm * (bw + 1.0)).T), sample(h, *(pts - nrm * (bw + 1.0)).T))
        niva = ndi.gaussian_filter1d(botten + 0.25, 1.5, mode='nearest')
        niva = np.clip(niva, botten + 0.08, np.maximum(kant - 0.1, botten + 0.08))
        Lw = np.array([to_world(*q) for q in pts + nrm * bw]); Rw = np.array([to_world(*q) for q in pts - nrm * bw])
        V = np.empty((2 * n_, 3)); V[0::2] = np.c_[Lw[:, 0], niva, Lw[:, 1]]; V[1::2] = np.c_[Rw[:, 0], niva, Rw[:, 1]]
        a_ = np.arange(n_ - 1) * 2
        msh = trimesh.Trimesh(V, np.r_[np.c_[a_, a_ + 1, a_ + 2], np.c_[a_ + 1, a_ + 3, a_ + 2]], process=False)
        if msh.face_normals[:, 1].mean() < 0:
            msh.faces = msh.faces[:, ::-1]
        add_merged('Vattendrag', msh, MAT_LAKE)
        n_vd += 1
scene.graph.update(frame_to='Vattendrag', frame_from=scene.graph.base_frame)
print('vattendrag med vattenyta', n_vd)

flush_merged()
VALT.skriv(scene)
markvegetation.lager_glb(MV, h, RES, f'{OUT}/{NAMN}_markvegetation.glb')   # växtlagret på avstånd
# Först utan terrängrutor, för Godot där Terrain3D står för marken, sedan hela scenen
scene.export(f'{OUT}/{NAMN}_objekt.glb')
for name, mesh in terrain_tiles:
    scene.add_geometry(mesh, node_name=name, geom_name=name)
scene.export(f'{OUT}/{NAMN}.glb')

# ---------- Platser och metadata ----------
places = []
for pt, t in feat['points']:
    if BOX.contains(pt):
        x, z = to_world(pt.x, pt.y)
        places.append(dict(name=t['name'], type=t.get('place') or t.get('historic'),
                           position=[round(x, 1), round(float(sample(h, [pt.x], [pt.y])[0]), 1), round(z, 1)]))
json.dump(places, open(f'{OUT}/places.json', 'w'), ensure_ascii=False, indent=1)
info = dict(
    crs='SWEREF 99 TM (EPSG:3006)', resolution_m=RES, width_px=W, height_px=H,
    origin_sweref_of_pixel_0_0=[OX, OY],
    godot_mapping='x = E - origin_E, z = origin_N - N, y = höjd i meter. Pixel (kolumn j, rad i) ligger på x=j*RES, z=i*RES.',
    height_min_m=round(hmin, 3), height_max_m=round(hmax, 3),
    png16_to_meters='h = height_min_m + (pixel/65535) * (height_max_m - height_min_m)',
    sea_level_m=0.0, size_m=[round(W * RES), round(H * RES)],
    sources=[('Höjd: Lantmäteriet, Markhöjdmodell Nedladdning (CC BY 4.0, bearbetad)' if g.get('dem_type') == 'lm' else
              'Höjd: Copernicus DEM GLO-30 (© DLR e.V. 2010-2014 och © Airbus Defence and Space GmbH 2014-2018, tillhandahållen under COPERNICUS av EU och ESA)'),
             'Vägar, byggnader, marktäcke, vatten, ortnamn: © OpenStreetMap contributors, ODbL'],
    landcover_classes={i: n for i, (n, _) in enumerate(CLASSES)},
)
json.dump(info, open(f'{OUT}/heightmap_info.json', 'w'), ensure_ascii=False, indent=1)
print('klart', info['size_m'], hmin, hmax)
