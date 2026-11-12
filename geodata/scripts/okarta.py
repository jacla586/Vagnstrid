#!/usr/bin/env python3
"""Orienteringskartor (ISOM, png utan georeferens) som extra källa för ett område.

    .venv/bin/python scripts/okarta.py passa <karta.png> --projekt <mapp> [--skala 0.55,0.75]
    .venv/bin/python scripts/okarta.py klassa --projekt <mapp>

passa:  kopierar kartan till <mapp>/data/okarta.png och passar in den mot områdets OSM-hus:
        grov sökning av skala och vridning (FFT-korrelation av kartans svarta husytor mot
        rastrerade OSM-hus), fin sökning, och sist lokala förskjutningar per 250 m-ruta som ger
        en affin avbildning SWEREF -> kartpixel (minsta kvadrat). Sparar <mapp>/data/okarta.json.
klassa: vrider in kartan i områdets rutnät och skriver
        <mapp>/work/okarta_klass.npy  (heightmapens 2 m-rutnät, koder i KODER, 255 = utanför)
        <mapp>/work/okarta_stenar.npy (E, N, storlek 0 = litet block, 1 = stort)
        forhandsbilder/okarta_<mapp>.png (kontrollbild: kartan, OSM-hus, stenar)

<mapp> är en områdesmapp (vidingsjo, linghem, ...) eller '.' för Vikbolandet.
Orienteringskartorna ägs av respektive klubb: bara för privat bruk, ligger i data/ (utanför git).
"""
import argparse, json, math, pickle, shutil, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from scipy.signal import fftconvolve
from rasterio.transform import from_origin
from rasterio.features import rasterize

Image.MAX_IMAGE_PIXELS = None
ROOT = Path(__file__).resolve().parent.parent

# ISOM-palett (färgerna i de renderade kartorna). Flera färger kan höra till samma klass.
PALETT = [('skog', (255, 255, 255)), ('svart', (0, 0, 0)), ('oppen', (255, 193, 79)),
          ('halvoppen', (255, 223, 163)), ('tomt', (152, 177, 21)), ('tomt', (152, 177, 43)),
          ('hardgjord', (230, 172, 127)), ('linje', (206, 104, 28)), ('vatten', (0, 212, 212)),
          ('vatten', (70, 225, 225)), ('vatten', (120, 233, 233)), ('snar1', (192, 245, 183)),
          ('snar2', (131, 236, 112)), ('snar3', (54, 223, 24)), ('linje', (120, 120, 120)),
          ('linje', (187, 187, 187)), ('linje', (160, 51, 240))]
KODER = dict(skog=0, oppen=1, halvoppen=2, odlad=3, tomt=4, hardgjord=5, vatten=6, myr=7,
             snar1=8, snar2=9, snar3=10)
YTKLASSER = ['skog', 'oppen', 'halvoppen', 'tomt', 'hardgjord', 'vatten', 'snar1', 'snar2', 'snar3']
UTANFOR = 255
SVART_MAX = 60           # max(R, G, B) under detta räknas som svart


def mappar(projekt):
    p = ROOT if projekt in ('.', '') else ROOT / projekt
    return p, p / 'data', p / 'work'


def las_karta(path, ds=1):
    bild = Image.open(path)
    if bild.mode in ('RGBA', 'LA', 'P'):
        # genomskinligt utanför kartan (svart i RGB) läggs på vitt, annars blir det hus
        bild = bild.convert('RGBA')
        vit = Image.new('RGBA', bild.size, (255, 255, 255, 255))
        bild = Image.alpha_composite(vit, bild)
    im = np.asarray(bild.convert('RGB'))
    return im[::ds, ::ds] if ds > 1 else im


def osm_hus(work):
    feat = pickle.load(open(work / 'features.pkl', 'rb'))
    return [q for gm, _ in feat['buildings'] for q in getattr(gm, 'geoms', [gm]) if q.geom_type == 'Polygon']


def hogpass(a, sig):
    a = ndi.gaussian_filter(a, 1.0)
    return a - ndi.gaussian_filter(a, sig)


# ---------------------------------------------------------------- passa
class Grovpassning:
    """Kartans husmask i ett nordorienterat rutnät (R m/px) för en given skala och vridning,
    korrelerad mot rastrerade OSM-hus. Modell: kartpixel = M @ (rad, kol i rutnätet) + off."""

    def __init__(self, svart, blds, R):
        self.svart, self.R = svart.astype(np.float32), R
        xs = np.concatenate([np.array(b.exterior.coords)[:, 0] for b in blds])
        ys = np.concatenate([np.array(b.exterior.coords)[:, 1] for b in blds])
        self.x0, self.y1 = xs.min(), ys.max()
        self.H, self.W = int((ys.max() - ys.min()) / R) + 1, int((xs.max() - self.x0) / R) + 1
        ref = rasterize([(b, 1) for b in blds], out_shape=(self.H, self.W),
                        transform=from_origin(self.x0, self.y1, R, R)).astype(np.float32)
        self.ref_h = hogpass(ref, 6)
        self.ref_k = self.ref_h[::-1, ::-1].copy()
        self.ref_n = (self.ref_h ** 2).sum()

    def modell(self, s, th):
        h, w = self.svart.shape
        c, si = math.cos(th), math.sin(th)
        M = (self.R / s) * np.array([[c, -si], [si, c]])
        ext = int(max(h, w) * s / self.R * 1.05) + 2
        off = np.array([h / 2, w / 2]) - M @ np.array([ext / 2, ext / 2])
        return M, off, ext

    def poang(self, s, th):
        M, off, ext = self.modell(s, th)
        src, f = self.svart, 1.0
        if s / self.R < 0.5:   # förminska först, annars blir samplingen gles
            f = s / self.R * 2
            src = ndi.zoom(self.svart, f, order=1)
        o = ndi.affine_transform(src, M * f, offset=off * f, output_shape=(ext, ext), order=1)
        oh = hogpass(o, 6)
        cc = fftconvolve(oh, self.ref_k, mode='full')
        k = np.unravel_index(np.argmax(cc), cc.shape)
        return cc[k] / (np.sqrt((oh ** 2).sum() * self.ref_n) + 1e-9), k

    def sok(self, skalor, vinklar):
        bast = None
        for s in skalor:
            for th in vinklar:
                p, k = self.poang(s, math.radians(th))
                if bast is None or p > bast[0]:
                    bast = (p, s, th, k)
        return bast

    def till_pixel(self, s, th, k, ds):
        """Funktion (E, N) -> (rad, kol) i ursprungliga kartpixlar för grovmodellen."""
        M, off, _ = self.modell(s, math.radians(th))
        dr, dc = k[0] - (self.H - 1), k[1] - (self.W - 1)

        def f(E, N):
            r = (self.y1 - N) / self.R + dr
            c = (E - self.x0) / self.R + dc
            return (M[0, 0] * r + M[0, 1] * c + off[0]) * ds, (M[1, 0] * r + M[1, 1] * c + off[1]) * ds
        return f


def kontrollpunkter(svart, blds, till_px, ruta=250.0, sok=12):
    """Lokal förskjutning per ruta (1 m): OSM-husen korreleras mot kartans husmask."""
    H0, W0 = svart.shape
    cx = np.array([b.centroid.x for b in blds]); cy = np.array([b.centroid.y for b in blds])
    src, dst = [], []
    for ex in np.arange(cx.min(), cx.max(), ruta):
        for ny in np.arange(cy.min(), cy.max(), ruta):
            sel = (cx >= ex) & (cx < ex + ruta) & (cy >= ny) & (cy < ny + ruta)
            if sel.sum() < 6:
                continue
            n = int(ruta)
            ref = rasterize([(blds[i], 1) for i in np.nonzero(sel)[0]], out_shape=(n, n),
                            transform=from_origin(ex, ny + ruta, 1.0, 1.0)).astype(np.float32)
            m = n + 2 * sok
            jj, ii = np.meshgrid(np.arange(m), np.arange(m))
            rr, cc = till_px(ex - sok + jj + 0.5, ny + ruta + sok - ii - 0.5)
            ok = (rr >= 0) & (rr < H0 - 1) & (cc >= 0) & (cc < W0 - 1)
            if ok.mean() < 0.9:
                continue
            o = np.zeros((m, m), np.float32)
            o[ok] = svart[np.round(rr[ok]).astype(int), np.round(cc[ok]).astype(int)]
            if o.mean() < 0.01:
                continue
            a, b = o - o.mean(), ref - ref.mean()
            k_ = fftconvolve(a, b[::-1, ::-1], mode='valid')
            k = np.unravel_index(np.argmax(k_), k_.shape)
            topp = k_[k] / (np.sqrt((a ** 2).sum() * (b ** 2).sum()) + 1e-9)
            if topp < 0.35 or min(k) == 0 or max(k) == k_.shape[0] - 1:
                continue
            dy, dx = k[0] - sok, k[1] - sok
            Ec, Nc = ex + ruta / 2, ny + ruta / 2
            src.append((Ec, Nc)); dst.append(till_px(Ec + dx, Nc - dy))
    return np.array(src), np.array(dst)


def passa(a):
    proj, data, work = mappar(a.projekt)
    data.mkdir(parents=True, exist_ok=True)
    mal = data / f'{a.som}.png'
    if Path(a.karta).resolve() != mal.resolve():
        shutil.copyfile(a.karta, mal)
    im = las_karta(mal)
    ds = max(1, int(math.ceil(max(im.shape[:2]) / 4500)))
    blds = osm_hus(work)
    print(f'karta {im.shape[1]}x{im.shape[0]} px (nedskalning {ds}), {len(blds)} OSM-hus')
    svart_ds = ndi.binary_opening(im[::ds, ::ds].max(axis=2) < SVART_MAX, iterations=max(1, 3 // ds))
    # grov: 4 m, skala a.skala (m/px), vridning ±10° (orienteringskartor pekar mot magnetisk nord)
    lo, hi = map(float, a.skala.split(','))
    g = Grovpassning(svart_ds, blds, 4.0)
    p, s, th, k = g.sok(np.geomspace(lo * ds, hi * ds, max(4, int(np.log(hi / lo) / 0.04))),
                        np.arange(-10, 10.1, 1.0))
    print(f'grov: {s / ds:.3f} m/px, {th:+.2f}°, poäng {p:.3f}')
    # fin: 2 m
    g = Grovpassning(svart_ds, blds, 2.0)
    p, s, th, k = g.sok(np.linspace(s * 0.97, s * 1.03, 13), np.arange(th - 1, th + 1.01, 0.25))
    print(f'fin:  {s / ds:.3f} m/px, {th:+.2f}°, poäng {p:.3f}')
    till_px = g.till_pixel(s, th, k, ds)
    svart = ndi.binary_opening(im.max(axis=2) < SVART_MAX, iterations=2)
    del im
    src, dst = kontrollpunkter(svart, blds, till_px)
    if len(src) < 4:
        sys.exit(f'för få kontrollpunkter ({len(src)}): passar kartan området?')
    ctr = src.mean(0)
    A = np.c_[src - ctr, np.ones(len(src))]
    m_per_px = s / ds
    for _ in range(3):   # minsta kvadrat, släng avvikare
        coef, *_ = np.linalg.lstsq(A, dst, rcond=None)
        res = np.linalg.norm(A @ coef - dst, axis=1) * m_per_px
        keep = res < max(3 * np.median(res), 1.5)
        A, dst = A[keep], dst[keep]
    coef, *_ = np.linalg.lstsq(A, dst, rcond=None)
    res = np.linalg.norm(A @ coef - dst, axis=1) * m_per_px
    print(f'kontrollpunkter {len(A)}, residual median {np.median(res):.2f} m, max {res.max():.2f} m')
    if np.median(res) > 3:
        print('VARNING: stor residual, kontrollera kontrollbilden')
    json.dump(dict(kalla=Path(a.karta).name, m_per_px=m_per_px, vridning_grader=th,
                   affin=coef.T.tolist(), centrum=ctr.tolist(), kontrollpunkter=int(len(A)),
                   residual_median_m=float(np.median(res)), residual_max_m=float(res.max()),
                   kartstorlek=list(svart.shape),
                   anm='kartpixel (rad, kol) = affin @ (E - centrum_E, N - centrum_N, 1)'),
              open(data / f'{a.som}.json', 'w'), indent=1)
    print('sparat', data / f'{a.som}.json')


# ---------------------------------------------------------------- klassa
def avbildning(fit):
    a = np.array(fit['affin']); ce, cn = fit['centrum']
    return lambda E, N: (a[0, 0] * (E - ce) + a[0, 1] * (N - cn) + a[0, 2],
                         a[1, 0] * (E - ce) + a[1, 1] * (N - cn) + a[1, 2])


def stenblock(im, fit, till_px, grid, blds):
    """Stenblock: runda svarta prickar (storlek 0 = block, 1 = stort block) och fyllda trianglar
    (2 = stenblocksgrupp), inte mönster (odlad mark, prickade linjer), ringar eller hus."""
    W, H, RES, x0, y1 = grid['W'], grid['H'], grid['RES'], grid['x0'], grid['y1']
    hr, hc = [], []
    for E, N in ((x0, y1), (x0 + W * RES, y1), (x0, y1 - H * RES), (x0 + W * RES, y1 - H * RES)):
        r, c = till_px(E, N); hr.append(r); hc.append(c)
    r0, r1 = max(0, int(min(hr)) - 20), min(im.shape[0], int(max(hr)) + 20)
    c0, c1 = max(0, int(min(hc)) - 20), min(im.shape[1], int(max(hc)) + 20)
    if r1 <= r0 or c1 <= c0:
        return np.zeros((0, 3))
    bit = im[r0:r1, c0:c1]
    svart = bit.max(axis=2) < SVART_MAX
    lab, n = ndi.label(svart)
    if n == 0:
        return np.zeros((0, 3))
    idx = np.arange(1, n + 1)
    area = ndi.sum(svart, lab, idx)
    objs = ndi.find_objects(lab)
    bh = np.array([o[0].stop - o[0].start for o in objs]); bw = np.array([o[1].stop - o[1].start for o in objs])
    fyll = area / (bh * bw)
    # prickarnas area (px vid 0,635 m/px, omräknat efter kartans skala): prickade linjer, åkermönstret
    # och ringarnas mittprickar är 10–22 px, stenblock 30–85 px och stora block 85–220 px
    k_ = (0.635 / fit['m_per_px']) ** 2
    a_min, a_stor, a_max = 30 * k_, 85 * k_, 220 * k_
    rund = (area >= a_min) & (area <= a_max) & (np.abs(bh - bw) <= 2) & (fyll > 0.6)
    # trianglar: fyllnad ~0,5 av omskrivande rektangel och inget hål (ringar har hål)
    fylld = np.array([ndi.binary_fill_holes(lab[o] == i + 1).sum() for i, o in enumerate(objs)]) \
        if n < 2_000_000 else area
    tri = (area >= a_min) & (area <= a_max * 1.3) & (np.abs(bh - bw) <= 4) & (fyll > 0.35) & (fyll <= 0.6) \
        & (fylld < area * 1.1)
    kand = rund | tri
    cy = np.array([(o[0].start + o[0].stop) / 2 for o in objs]); cx = np.array([(o[1].start + o[1].stop) / 2 for o in objs])
    ki = np.nonzero(kand)[0]
    # prickade linjer och prickmönster: de två närmaste grannarna ligger åt motsatta håll på
    # ungefär samma avstånd. Klungor av block (slumpvis spridda) klarar sig.
    from scipy.spatial import cKDTree
    if len(ki) > 2:
        P = np.c_[cy[ki], cx[ki]]
        d, j = cKDTree(P).query(P, k=3, distance_upper_bound=16.0 / fit['m_per_px'])
        linje = np.zeros(len(ki), bool)
        har2 = np.isfinite(d[:, 2])
        v1 = P[np.minimum(j[har2, 1], len(P) - 1)] - P[har2]
        v2 = P[np.minimum(j[har2, 2], len(P) - 1)] - P[har2]
        cos = (v1 * v2).sum(1) / (np.linalg.norm(v1, axis=1) * np.linalg.norm(v2, axis=1) + 1e-9)
        lika = d[har2, 2] < 1.6 * d[har2, 1]
        linje[har2] = (cos < -0.7) & lika
        ki = ki[~linje]
    pal = np.array([c for _, c in PALETT], np.float32); namn = [n_ for n_, _ in PALETT]
    ok_bak = {'skog', 'halvoppen', 'oppen', 'hardgjord', 'snar1', 'snar2', 'snar3'}   # inte tomt (bodar)
    ut = []
    rad = int(6 / fit['m_per_px']) + 2
    for i in ki:
        y, x = int(cy[i]), int(cx[i])
        p = bit[max(0, y - rad):y + rad, max(0, x - rad):x + rad].reshape(-1, 3).astype(np.float32)
        p = p[p.max(axis=1) >= SVART_MAX]
        if len(p) < 10:
            continue
        m = np.median(p, axis=0)
        if namn[int(np.argmin(((pal - m) ** 2).sum(1)))] not in ok_bak:
            continue
        ut.append((y + r0, x + c0, 2 if tri[i] else (1 if area[i] >= a_stor else 0)))
    if not ut:
        return np.zeros((0, 3))
    ut = np.array(ut, float)
    # kartpixel -> SWEREF (invers av den affina avbildningen)
    a = np.array(fit['affin']); ce, cn = fit['centrum']
    inv = np.linalg.inv(a[:, :2])
    d = (ut[:, :2] - a[:, 2]) @ inv.T
    E, N = d[:, 0] + ce, d[:, 1] + cn
    inne = (E > x0) & (E < x0 + W * RES) & (N > y1 - H * RES) & (N < y1)
    # inte i OSM-hus
    hus = rasterize([(b.buffer(1.0), 1) for b in blds], out_shape=(H, W), transform=from_origin(x0, y1, RES, RES)).astype(bool)
    jj = np.clip(((E - x0) / RES).astype(int), 0, W - 1); ii = np.clip(((y1 - N) / RES).astype(int), 0, H - 1)
    inne &= ~hus[ii, jj]
    return np.c_[E[inne], N[inne], ut[inne, 2]]


def _myrstreck(cyan, lab, nr, o, avst=(2, 3, 4, 5)):
    """Myr ritas som parallella streck: en linje med ett annat cyan streck ett par meter rakt
    ovanför eller under sig (kartan är nästan nordorienterad) är myr, inte en bäck."""
    r0, r1 = max(o[0].start - 6, 0), min(o[0].stop + 6, cyan.shape[0])
    c0, c1 = o[1].start, o[1].stop
    egen = lab[r0:r1, c0:c1] == nr
    andra = cyan[r0:r1, c0:c1] & ~egen
    n = egen.sum()
    for d in avst:
        for tecken in (1, -1):
            if (np.roll(egen, tecken * d, axis=0) & andra).sum() > 0.3 * n:
                return True
    return False


def _kedja(P, steg=3.0):
    """Ordnar pixlarna i en linje till en följd: börjar i ena änden och går till närmaste
    obesökta pixel inom steg px. Grenar blir avskurna, det räcker för bäckar och diken."""
    from scipy.spatial import cKDTree
    t = cKDTree(P)
    c = P.mean(0)
    start = int(np.argmax(((P - c) ** 2).sum(1)))
    besokt = np.zeros(len(P), bool)
    ut, i = [], start
    while True:
        besokt[i] = True
        ut.append(P[i])
        nara = [j for j in t.query_ball_point(P[i], steg) if not besokt[j]]
        if not nara:
            break
        besokt[nara] = True   # pixlarna runt den här är avklarade
        i = max(nara, key=lambda j: ((P[j] - P[i]) ** 2).sum())
    ut = np.array(ut)
    return ut[::2] if len(ut) > 4 else ut


def kartor(data):
    """Områdets inpassade kartor i ordning: okarta först, sedan okarta2, okarta3 ... (den första som
    täcker en plats gäller där)."""
    def nr(p):
        t = p.stem[len('okarta'):]
        return int(t) if t.isdigit() else (1 if t == '' else 10 ** 6)
    return sorted((p for p in data.glob('okarta*.json') if (p.stem == 'okarta' or p.stem[6:].isdigit())
                   and p.with_suffix('.png').exists()), key=nr)


def klassa(a):
    proj, data, work = mappar(a.projekt)
    grid = json.load(open(work / 'grid.json'))
    W, H, RES, x0, y1 = grid['W'], grid['H'], grid['RES'], grid['x0'], grid['y1']
    blds = osm_hus(work)
    kod = None; stenar_alla = []; vattendrag = []; rgb_alla = None
    for js in kartor(data):
        fit = json.load(open(js))
        k, st, vd, rgb = _klassa_en(fit, las_karta(js.with_suffix('.png')), grid, blds)
        ny = k != UTANFOR if kod is None else (kod == UTANFOR) & (k != UTANFOR)
        print(f'{js.stem}: ny täckning {ny.mean():.0%}')
        if kod is None:
            kod = np.full_like(k, UTANFOR); rgb_alla = np.full_like(rgb, 255)
        kod[ny] = k[ny]
        f = rgb.shape[0] // H
        ny1 = np.repeat(np.repeat(ny, f, 0), f, 1)
        sl_ = (slice(0, ny1.shape[0]), slice(0, ny1.shape[1]))
        rgb_alla[sl_][ny1] = rgb[sl_][ny1]
        def nytt(E, N):
            j = np.clip(((np.asarray(E) - x0) / RES).astype(int), 0, W - 1)
            i = np.clip(((y1 - np.asarray(N)) / RES).astype(int), 0, H - 1)
            return ny[i, j]
        if len(st):
            stenar_alla.append(st[nytt(st[:, 0], st[:, 1])])
        vattendrag += [v for v in vd if nytt(v[:, 0], v[:, 1]).mean() > 0.5]
    if kod is None:
        sys.exit(f'ingen inpassad karta i {data} (kör passa först)')
    stenar = np.concatenate(stenar_alla) if stenar_alla else np.zeros((0, 3))
    pickle.dump(vattendrag, open(work / 'okarta_vattendrag.pkl', 'wb'))
    print('vattendrag som linjer:', len(vattendrag))
    np.save(work / 'okarta_klass.npy', kod)
    inv = {v: k for k, v in KODER.items()}
    tot = (kod != UTANFOR).sum()
    print(f'täckning {tot / kod.size:.0%};', ', '.join(f'{inv[v]} {(kod == v).sum() / max(tot, 1):.0%}'
                                                    for v in sorted(inv)))
    np.save(work / 'okarta_stenar.npy', stenar)
    print(f'stenblock {len(stenar)} (stora {int((stenar[:, 2] == 1).sum()) if len(stenar) else 0}, '
          f'grupper {int((stenar[:, 2] == 2).sum()) if len(stenar) else 0})')
    f = int(round(RES))
    # kontrollbild
    bild = Image.fromarray(rgb_alla); d = ImageDraw.Draw(bild)
    for b in blds:
        d.line([((x_ - x0) * f / RES, (y1 - y_) * f / RES) for x_, y_ in b.exterior.coords], fill=(255, 0, 0))
    for E, N, s in stenar:
        px, py = (E - x0) * f / RES, (y1 - N) * f / RES
        r = 4 if s else 3
        d.ellipse([px - r, py - r, px + r, py + r], outline=(0, 160, 255) if s == 2 else (255, 0, 255))
    (ROOT / 'forhandsbilder').mkdir(exist_ok=True)
    namn_ = proj.name if proj != ROOT else 'vikbolandet'
    bild.save(ROOT / 'forhandsbilder' / f'okarta_{namn_}.png')
    print('kontrollbild', ROOT / 'forhandsbilder' / f'okarta_{namn_}.png')


def _klassa_en(fit, im, grid, blds):
    """En karta: (klass per 2 m-cell, stenblock, vattendrag, 1 m-bild av kartan över området)."""
    W, H, RES, x0, y1 = grid['W'], grid['H'], grid['RES'], grid['x0'], grid['y1']
    till_px = avbildning(fit)
    h0, w0 = im.shape[:2]
    # 1 m-rutnät över området
    f = int(round(RES))
    nh, nw = H * f, W * f
    jj, ii = np.meshgrid(np.arange(nw), np.arange(nh))
    rr, cc = till_px(x0 + (jj + 0.5) * RES / f, y1 - (ii + 0.5) * RES / f)
    ok = (rr >= 0) & (rr < h0 - 1) & (cc >= 0) & (cc < w0 - 1)
    rgb = np.full((nh, nw, 3), 255, np.uint8)
    rgb[ok] = im[np.round(rr[ok]).astype(int), np.round(cc[ok]).astype(int)]
    del rr, cc, jj, ii
    # närmaste palettfärg
    pal = np.array([c for _, c in PALETT], np.float32)
    namn = [n_ for n_, _ in PALETT]
    best = np.zeros((nh, nw), np.uint8); bd = np.full((nh, nw), np.inf, np.float32)
    x = rgb.astype(np.float32)
    for k, c in enumerate(pal):
        d = ((x - c) ** 2).sum(axis=2)
        m = d < bd
        best[m] = k; bd[m] = d[m]
    del x, bd
    klass_1m = np.array([namn[k] for k in range(len(pal))])[best]
    # täckning: det ritade området (inte vitt), stängt och fyllt; vitt utanför kartan räknas inte
    ritat = ok & (rgb.min(axis=2) < 245)
    tack = ndi.binary_fill_holes(ndi.binary_closing(ritat, iterations=25)) & ok
    tack = ndi.binary_erosion(tack, iterations=4)
    # andel per ytklass i ett 3 m-fönster (linjer och svart räknas inte)
    andel = np.stack([ndi.uniform_filter((klass_1m == y).astype(np.float32), 3) for y in YTKLASSER])
    # bäckar och diken är långa smala cyan linjer: de räknas inte som myr (myr är korta streck)
    cyan_m = klass_1m == 'vatten'
    lab_c, n_c = ndi.label(cyan_m, structure=np.ones((3, 3)))
    linjer = np.zeros_like(cyan_m)
    if n_c:
        ob = ndi.find_objects(lab_c)
        ar = ndi.sum(cyan_m, lab_c, np.arange(1, n_c + 1))
        for i, o in enumerate(ob):
            diag = float(np.hypot(o[0].stop - o[0].start, o[1].stop - o[1].start))
            if diag >= 15 and ar[i] / diag < 6.0 and not _myrstreck(cyan_m, lab_c, i + 1, o):
                linjer[o] |= lab_c[o] == i + 1
    print(f'vattendrag i kartan: {linjer.sum() / max(cyan_m.sum(), 1):.0%} av cyan')
    vattendrag = []   # linjerna som SWEREF-koordinater (step3 lägger till dem som saknas i OSM)
    if n_c:
        for i, o in enumerate(ob):
            diag = float(np.hypot(o[0].stop - o[0].start, o[1].stop - o[1].start))
            if diag >= 25 and ar[i] / diag < 6.0 and linjer[o][lab_c[o] == i + 1].all():
                rr_, cc_ = np.nonzero(lab_c[o] == i + 1)
                kedja = _kedja(np.c_[rr_ + o[0].start, cc_ + o[1].start].astype(float))
                if len(kedja) >= 2:
                    vattendrag.append(np.c_[x0 + (kedja[:, 1] + 0.5) * RES / f, y1 - (kedja[:, 0] + 0.5) * RES / f])
    cyan = ndi.uniform_filter((cyan_m & ~linjer).astype(np.float32), 6)
    svart = ndi.uniform_filter((klass_1m == 'svart').astype(np.float32), 8)
    gult = ndi.uniform_filter((klass_1m == 'oppen').astype(np.float32), 8)
    # ned till 2 m: cellens mitt ligger mellan 1 m-pixlarna (2i, 2j) och (2i+1, 2j+1)
    sl = (slice(0, nh, f), slice(0, nw, f))
    yt = np.argmax(andel[(slice(None),) + sl], axis=0)
    kod = np.array([KODER[y] for y in YTKLASSER], np.uint8)[yt]
    c2, s2, g2 = cyan[sl], svart[sl], gult[sl]
    kod[(c2 >= 0.12) & (c2 < 0.7)] = KODER['myr']
    kod[c2 >= 0.7] = KODER['vatten']
    kod[(kod == KODER['oppen']) & (g2 > 0.5) & (s2 > 0.03) & (s2 < 0.25)] = KODER['odlad']
    kod[~tack[sl]] = UTANFOR
    kod = kod[:H, :W]
    stenar = stenblock(im, fit, till_px, grid, blds)
    return kod, stenar, vattendrag, rgb

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('passa'); p.add_argument('karta'); p.add_argument('--projekt', required=True)
    p.add_argument('--som', default='okarta',
                   help='filnamn i <mapp>/data: okarta (första kartan), okarta2, okarta3 ... fyller i där de före saknas')
    p.add_argument('--skala', default='0.3,2.0',
                   help='sökområde för kartans skala i m/px, t.ex. 0.55,0.75 (snabbare för stora kartor)')
    k = sub.add_parser('klassa'); k.add_argument('--projekt', required=True)
    a = ap.parse_args()
    passa(a) if a.cmd == 'passa' else klassa(a)


if __name__ == '__main__':
    main()
