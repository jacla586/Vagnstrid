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
import takform, husgeometri
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

# ---------- Vägar ----------
WIDTH = dict(trunk=8, primary=7.5, secondary=7, tertiary=6.5, unclassified=5, residential=5,
             service=3.5, track=3.0, path=1.2, footway=1.5, cycleway=2.5)
def surface_of(t):
    s = t.get('surface')
    if s in ('asphalt', 'paved', 'concrete'):
        return 'asfalt'
    if s in ('unpaved', 'gravel', 'compacted', 'fine_gravel', 'dirt', 'ground'):
        return 'grus' if t['highway'] not in ('path', 'footway') else 'stig'
    if t['highway'] in ('trunk', 'primary', 'secondary', 'tertiary'):
        return 'asfalt'
    if t['highway'] in ('path', 'footway'):
        return 'stig'
    return 'grus'

clip_area = BOX
roads = []
for geom, t in feat['roads']:
    is_e851 = t.get('ref') == 'E 851'
    gg = geom if is_e851 else geom.intersection(clip_area)
    if gg.is_empty:
        continue
    for part in getattr(gg, 'geoms', [gg]):
        if part.geom_type != 'LineString' or part.length < 4:
            continue
        roads.append(dict(line=part, tags=t, width=WIDTH.get(t['highway'], 3.0), surface=surface_of(t),
                          name=t.get('name') or t.get('ref') or t['highway']))
print('vägsegment', len(roads), 'total km', round(sum(r['line'].length for r in roads) / 1000, 1))

# Täta ut mittlinjerna (var 2 m) och jämna ut längsprofilen
samples = []  # x, y, z, halvbredd, vägindex
for k, r in enumerate(roads):
    L = r['line']
    n = max(2, int(L.length / 2) + 1)
    pts = np.array([L.interpolate(d).coords[0] for d in np.linspace(0, L.length, n)])
    z = sample(h, pts[:, 0], pts[:, 1])
    z = ndi.gaussian_filter1d(z, sigma=max(1, min(8, n / 6)), mode='nearest')  # ~16 m utjämning
    if r['tags']['highway'] in ('path', 'footway'):
        r['pts'], r['z'] = pts, z
        continue  # stigar följer terrängen, ingen schaktning
    r['pts'], r['z'] = pts, z
    for (x, y), zz in zip(pts, z):
        samples.append((x, y, zz, r['width'] / 2, k))
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
ok = np.isfinite(d)
ii, jj, d, idx = ii[ok], jj[ok], d[ok], idx[ok]
hw = S[idx, 3]
t_ = np.clip((d - hw - 2.0) / SHOULDER, 0, 1)
w = 1 - (t_ * t_ * (3 - 2 * t_))  # smoothstep
h[ii, jj] = h[ii, jj] * (1 - w) + S[idx, 2] * w
print('schaktade celler', len(ii))

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

# Diken och bäckar: smal fåra
for geom, t in feat['waterways']:
    gg = geom.intersection(BOX)
    if gg.is_empty:
        continue
    depth = 0.6 if t.get('waterway') == 'ditch' else 1.0
    wm = rasterize([(gg.buffer(1.5), 1)], out_shape=(H, W), transform=T).astype(bool)
    h[wm] -= depth * 0.7
h = ndi.gaussian_filter(h, 0.6) * 0.5 + h * 0.5  # mjuka kanter efter schaktning

# ---------- Heightmap-export ----------
hmin, hmax = float(h.min()), float(h.max())
u16 = np.round((h - hmin) / (hmax - hmin) * 65535).astype(np.uint16)
Image.fromarray(u16).save(f'{OUT}/heightmap_16bit.png')
u16.astype('<u2').tofile(f'{OUT}/heightmap.r16')
np.save(str(WORK / 'h_final.npy'), h)

# ---------- Marktäcke ----------
CLASSES = [('hav', (58, 96, 128)), ('mark', (122, 140, 82)), ('skog', (62, 92, 50)), ('åker', (170, 152, 96)),
           ('äng', (132, 160, 80)), ('tomt', (110, 130, 78)), ('gård', (128, 118, 92)), ('våtmark', (96, 112, 80)),
           ('berg', (112, 114, 100)), ('buskmark', (88, 110, 60)), ('strand', (196, 184, 140)), ('sjö', (64, 104, 132)),
           ('väg_asfalt', (70, 70, 72)), ('väg_grus', (150, 138, 116))]
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
if water_polys:
    lc[rasterize([(x, 1) for x in water_polys], out_shape=(H, W), transform=T).astype(bool)] = CIDX['sjö']
for r in roads:
    if r['tags']['highway'] in ('path', 'footway'):
        continue
    mm = rasterize([(r['line'].buffer(r['width'] / 2), 1)], out_shape=(H, W), transform=T).astype(bool)
    lc[mm] = CIDX['väg_asfalt' if r['surface'] == 'asfalt' else 'väg_grus']
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
road_json = []
scene.graph.update(frame_to='Vagar', frame_from=scene.graph.base_frame)
for k, r in enumerate(roads):
    pts = r['pts']
    if len(pts) < 2:
        continue
    dvec = np.gradient(pts, axis=0)
    dvec /= np.maximum(np.linalg.norm(dvec, axis=1, keepdims=True), 1e-9)
    nrm = np.c_[-dvec[:, 1], dvec[:, 0]]
    hw = r['width'] / 2
    L = pts + nrm * hw; Rr = pts - nrm * hw
    lift = 0.15 if r['tags']['highway'] not in ('path', 'footway') else 0.04
    if r['tags']['highway'] in ('path', 'footway'):
        zl = sample(h, L[:, 0], L[:, 1]) + lift; zr = sample(h, Rr[:, 0], Rr[:, 1]) + lift
    else:
        zc = np.maximum(sample(h, pts[:, 0], pts[:, 1]), np.maximum(sample(h, L[:, 0], L[:, 1]), sample(h, Rr[:, 0], Rr[:, 1])))
        zl = zr = zc + lift
    wl = np.array([to_world(*p) for p in L]); wr = np.array([to_world(*p) for p in Rr])
    V = np.empty((2 * len(pts), 3))
    V[0::2] = np.c_[wl[:, 0], zl, wl[:, 1]]
    V[1::2] = np.c_[wr[:, 0], zr, wr[:, 1]]
    n = len(pts)
    a = np.arange(n - 1) * 2
    F = np.r_[np.c_[a, a + 1, a + 2], np.c_[a + 1, a + 3, a + 2]]
    s = np.cumsum(np.r_[0, np.linalg.norm(np.diff(pts, axis=0), axis=1)])
    uv = np.empty((2 * n, 2)); uv[0::2] = np.c_[np.zeros(n), s / r['width']]; uv[1::2] = np.c_[np.ones(n), s / r['width']]
    mesh = trimesh.Trimesh(V, F, process=False)
    # se till att normalerna pekar uppåt
    if mesh.face_normals[:, 1].mean() < 0:
        mesh.faces = mesh.faces[:, ::-1]
    add_merged('Vagar', mesh, ROADMAT[r['surface']], uv)
    cw = np.array([to_world(*p) for p in pts[::2]] + ([to_world(*pts[-1])] if (len(pts) - 1) % 2 else []))
    cz = np.r_[r['z'][::2], [r['z'][-1]] if (len(pts) - 1) % 2 else []]
    road_json.append(dict(name=r['name'], highway=r['tags']['highway'], ref=r['tags'].get('ref'), surface=r['surface'],
                          width_m=r['width'], osm_name=r['tags'].get('name'),
                          points=[[round(float(x), 2), round(float(z), 2), round(float(y), 2)] for (x, y), z in zip(cw, cz)]))
json.dump(dict(coordinate_note='Godot-koordinater [x, y(höjd), z] i meter; x=öst, z=syd. Se heightmap_info.json',
               roads=road_json), open(f'{OUT}/roads.json', 'w'), ensure_ascii=False)

# ---------- Byggnader ----------
MAT_WALL_RED = mat('Vagg_falurod', (128, 38, 28)); MAT_WALL_WHITE = mat('Vagg_vit', (226, 222, 210))
MAT_WALL_YELLOW = mat('Vagg_gul', (214, 182, 104)); MAT_ROOF = mat('Tak_svart', (46, 46, 48), 0.7)
MAT_ROOF_TILE = mat('Tak_tegel', (128, 60, 44), 0.8); MAT_ROOF_TIN = mat('Tak_plat', (90, 92, 94), 0.5)

def btype(t, area):
    b = t.get('building', 'yes')
    if b == 'church':
        return 'kyrka'
    if b in ('barn', 'farm_auxiliary', 'shed', 'garage', 'industrial', 'warehouse', 'stable', 'cowshed'):
        return 'lada' if area > 60 else 'bod'
    if area < 30:
        return 'bod'
    if area > 260:
        return 'lada'
    return 'hus'

SPEC = dict(  # takfotshöjd, takvinkel, väggmaterial, takmaterial
    hus=(4.2, 38, [MAT_WALL_RED, MAT_WALL_RED, MAT_WALL_YELLOW, MAT_WALL_WHITE], [MAT_ROOF, MAT_ROOF_TILE]),
    lada=(5.0, 28, [MAT_WALL_RED], [MAT_ROOF_TIN, MAT_ROOF]),
    bod=(2.4, 30, [MAT_WALL_RED], [MAT_ROOF]),
    kyrka=(8.5, 45, [MAT_WALL_WHITE], [MAT_ROOF]),
)

def gable_house(rect, ground_min, ground_max, eave, pitch, overhang=0.35):
    c = np.array(rect.exterior.coords)[:4]
    e0 = np.linalg.norm(c[1] - c[0]); e1 = np.linalg.norm(c[2] - c[1])
    if e0 < e1:
        c = np.roll(c, -1, axis=0); e0, e1 = e1, e0
    # c0-c1 långsida, c1-c2 kortsida
    base = ground_min - 0.6; top = ground_max + eave
    ridge = top + math.tan(math.radians(pitch)) * e1 / 2
    W_ = [to_world(*p) for p in c]
    verts, faces_w, faces_r = [], [], []
    def v(p, y):
        verts.append([p[0], y, p[1]]); return len(verts) - 1
    # väggar
    for a_, b_ in [(0, 1), (1, 2), (2, 3), (3, 0)]:
        i0 = v(W_[a_], base); i1 = v(W_[b_], base); i2 = v(W_[b_], top); i3 = v(W_[a_], top)
        faces_w += [[i0, i2, i1], [i0, i3, i2]]
    # gavlar (kortsidorna 1-2 och 3-0)
    for a_, b_ in [(1, 2), (3, 0)]:
        mid = ((W_[a_][0] + W_[b_][0]) / 2, (W_[a_][1] + W_[b_][1]) / 2)
        i0 = v(W_[a_], top); i1 = v(W_[b_], top); i2 = v(mid, ridge)
        faces_w += [[i0, i2, i1]]
    # tak med utsprång
    Wa = np.array(W_)
    ax_long = (Wa[1] - Wa[0]) / e0; ax_short = (Wa[2] - Wa[1]) / e1
    ctr = Wa.mean(0)
    def P(sl, ss):
        return ctr + ax_long * sl + ax_short * ss
    hl = e0 / 2 + overhang; hs = e1 / 2 + overhang
    drop = math.tan(math.radians(pitch)) * overhang
    for side in (-1, 1):
        p0 = P(-hl, side * hs); p1 = P(hl, side * hs); p2 = P(hl, 0); p3 = P(-hl, 0)
        i0 = v(p0, top - drop); i1 = v(p1, top - drop); i2 = v(p2, ridge); i3 = v(p3, ridge)
        faces_r += [[i0, i1, i2], [i0, i2, i3]]
    return np.array(verts), faces_w, faces_r

def flat_building(poly, ground_min, ground_max, eave):
    base = ground_min - 0.6; top = ground_max + eave
    verts, fw, fr = [], [], []
    ring = np.array(poly.exterior.coords)[:-1]
    if not poly.exterior.is_ccw:
        ring = ring[::-1]
    for k in range(len(ring)):
        a_, b_ = to_world(*ring[k]), to_world(*ring[(k + 1) % len(ring)])
        n0 = len(verts)
        verts += [[a_[0], base, a_[1]], [b_[0], base, b_[1]], [b_[0], top, b_[1]], [a_[0], top, a_[1]]]
        fw += [[n0, n0 + 2, n0 + 1], [n0, n0 + 3, n0 + 2]]
    for tri in triangulate(poly):
        if not poly.buffer(0.01).contains(tri.centroid):
            continue
        n0 = len(verts)
        for p in list(tri.exterior.coords)[:3]:
            q = to_world(*p); verts.append([q[0], top, q[1]])
        fr.append([n0, n0 + 1, n0 + 2])
    return np.array(verts), fw, fr

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

TAKSTAT = {}
LUTANDE = ('sadel', 'valmat', 'talt')

def add_part(group, V, faces, roof, ctr, material):
    if not faces:
        return
    msh = trimesh.Trimesh(V.copy(), np.array(orient(V, faces, roof, ctr)), process=False)
    msh.remove_unreferenced_vertices()
    add_merged(group, msh, material, husgeometri.plan_uv(np.asarray(msh.vertices), np.asarray(msh.faces)))

def bygg_med_takform(poly, group, gz, wm, rm):
    """Hus med takformer ur laserdatan: fotavtrycket delas i rektanglar och varje del får
    den takmodell som passar laserhöjderna bäst (takform.py). False om laserdata saknas."""
    delar = takform.dela_i_rektanglar(poly)
    tolkade = [takform.tolka_delar(d, laser) for d in delar]
    giltiga = [t for ts in tolkade for t in ts]
    if not giltiga:
        return False
    ref = gz.mean(); bas = gz.min() - 0.6
    tak = []
    for d, ts in zip(delar, tolkade):
        if not ts:      # del utan laserträffar: platt tak på husets takfotshöjd
            mitt, u, v, a, b = takform.ram(d)
            ts = [takform.Tak('platt', mitt, u, v, a, b, giltiga[0].takfot, giltiga[0].takfot)]
        tak += ts
    for t in tak:
        V, fw, fr = husgeometri.bygg_del(t, to_world, ref, bas)
        ctr = to_world(*t.mitt)
        add_part(group, V, fw, False, ctr, wm)
        add_part(group, V, fr, True, ctr, rm if t.modell in LUTANDE else MAT_ROOF_TIN)
        TAKSTAT[t.modell] = TAKSTAT.get(t.modell, 0) + 1
    TAKSTAT['hus'] = TAKSTAT.get('hus', 0) + 1
    TAKSTAT['delade hus'] = TAKSTAT.get('delade hus', 0) + (len(tak) > 1)
    return True

def add_building(poly, kind, name, group, heights=None):
    """Med laserdata: takform ur laserhöjderna (bygg_med_takform). Annars, eller om laserträffar
    saknas: heights = (takfot, nock) i meter över mark från laser, eller schablon per hustyp."""
    poly = poly.buffer(0)
    if poly.geom_type == 'MultiPolygon':
        poly = max(poly.geoms, key=lambda q: q.area)
    ring = np.array(poly.exterior.coords)
    gz = sample(h, ring[:, 0], ring[:, 1]); gz = np.r_[gz, sample(h, [poly.centroid.x], [poly.centroid.y])]
    eave, pitch, walls, roofs = SPEC[kind]
    wm = rng.choice(walls); rm = rng.choice(roofs)
    if laser is not None and bygg_med_takform(poly, group, gz, wm, rm):
        return
    rect = poly.minimum_rotated_rectangle
    gable = poly.area / max(rect.area, 1e-6) > 0.82
    top_ref = gz.max()
    if heights is not None:
        # Laserhöjderna är mot marken i varje punkt; utgå från markens medel under huset
        top_ref = gz.mean()
        eave = float(np.clip(heights[0], 2.0, 20.0))
        rise = max(heights[1] - eave, 0.0)
        c = np.array(rect.exterior.coords)[:3]
        short = min(np.linalg.norm(c[1] - c[0]), np.linalg.norm(c[2] - c[1]))
        if rise < 0.8 or short > 30:
            gable = False
            eave = float(np.clip(heights[1], 2.0, 25.0)) - 1.0   # platt tak på nockhöjd (flat_building lägger på 1 m)
        else:
            pitch = float(np.clip(math.degrees(math.atan(rise / (short / 2))), 12, 50))
    if gable:
        V, fw, fr = gable_house(rect, gz.min(), top_ref, eave, pitch)
    else:
        V, fw, fr = flat_building(poly, gz.min(), top_ref, eave + 1.0)
    cw = to_world(poly.centroid.x, poly.centroid.y)
    add_part(group, V, fw, False, cw, wm)
    add_part(group, V, fr, True, cw, rm)

scene.graph.update(frame_to='Byggnader_OSM', frame_from=scene.graph.base_frame)
laser = None
if OBJ:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from laserhus import Objekthojd
    laser = Objekthojd(OBJ)
osm_b = [(gm, t) for gm, t in feat['buildings'] if BOX.intersects(gm)]
bpolys = []
n_h = 0
for k, (gm, t) in enumerate(osm_b):
    kind = btype(t, gm.area)
    hh = laser.heights_in(gm) if laser else None
    n_h += hh is not None
    add_building(gm, kind, f'osm_{k:03d}_{kind}', 'Byggnader_OSM', hh)
    bpolys.append(gm)
print('OSM-byggnader', len(osm_b), 'varav med laserhöjd', n_h)

if laser:
    # Hus ur laserdatan: bara på land, inte på vägar, i vatten eller där OSM redan har hus
    scene.graph.update(frame_to='Byggnader_laser', frame_from=scene.graph.base_frame)
    excl = unary_union([b.buffer(1.0) for b in bpolys]
                       + [r['line'].buffer(r['width'] / 2 + 1.0) for r in roads if r['tags']['highway'] not in ('path', 'footway')]
                       + water_polys)
    n_l = 0
    for rect, poly in laser.detect(exclude=excl):
        c_, r_ = to_px(rect.centroid.x, rect.centroid.y)
        if not land[int(np.clip(round(r_), 0, H - 1)), int(np.clip(round(c_), 0, W - 1))]:
            continue
        hh = laser.heights_in(poly)
        kind = 'bod' if rect.area < 30 else ('lada' if rect.area > 250 else 'hus')
        add_building(poly, kind, f'laser_{n_l:04d}_{kind}', 'Byggnader_laser', hh)
        n_l += 1
    print('laserbyggnader', n_l)
if TAKSTAT:
    print('takformer (delar):', {k: v for k, v in TAKSTAT.items() if k not in ('hus', 'delade hus')},
          f"hus {TAKSTAT.get('hus', 0)}, varav delade {TAKSTAT.get('delade hus', 0)}")

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
        add_building(rect, kind, f'ph_{len(placed):03d}_{kind}', 'Byggnader_platshallare')
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

flush_merged()
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
