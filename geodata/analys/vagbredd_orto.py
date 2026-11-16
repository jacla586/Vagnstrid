"""Vägbredd och läge ur ortofotot (analys, inte en del av bygget; spelet rörs inte).

  GEO_WORK=geodata/<karta>/work geodata/.venv/bin/python geodata/analys/vagbredd_orto.py <karta> [--bilder N]
      [--ruta E,N,halv]

Läser vägnätet precis som step3 (vagnat.vaglista + forbered: NVDB-bredder, harmonisering, isärflyttade
körbanor) och mäter var TVAR_AVST_M:e meter längs varje asfalterad bilväg ett tvärsnitt i ortofotot:
asfaltens referensfärg tas mitt på vägen, sedan gås utåt åt båda hållen tills asfalten tar slut (grönt i
IR-bandet eller annan färg i STOPP_M i följd). Där laserns objekthöjd visar något högre än HINDER_H_M
(träd, bilar) är pixeln okänd; för mycket okänt eller asfalt ända ut till fönstrets kant (parkering,
torg) gör tvärsnittet ogiltigt. Per väg: medianbredd, spridning, mittlinjens förskjutning, andel giltiga.

Ut (geodata/analys/ut/<karta>_bredd/):
  vagar.csv          en rad per väg: modellens bredd (det bygget ger) mot uppmätt
  sammanfattning.txt fördelning av avvikelsen per vägklass, de största avvikelserna
  oversikt.png       hela kartan: vägarna färgade efter avvikelsen (röd = bredare i verkligheten)
  NN_<namn>.png      utsnitt för de största avvikelserna: fotot, modellens kanter (gult), uppmätta (rött)
"""
import argparse
import csv
import json
import os
import pickle
import sys
from pathlib import Path

import numpy as np
import rasterio
from shapely.geometry import box

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))

TVAR_AVST_M = 10.0      # tvärsnitt så här tätt längs vägen
STEG_M = 0.25           # sampelavstånd längs tvärsnittet
FONSTER_EXTRA_M = 7.0   # tvärsnittet når så här långt utanför modellens kant
REF_HALV_M = 1.0        # referensfärgen ur mittens ±1 m
NDVI_MAX = 0.12         # över detta är det grönt
FARG_MAX = 30.0         # största RGB-avstånd till referensen för asfalt
HINDER_H_M = 0.8        # laserns objekthöjd: över detta är pixeln skymd (träd, bil, skylt)
STOPP_M = 1.0           # så mycket icke-asfalt i följd avslutar sidan
OKAND_MAX_M = 4.0       # mer skymt än så i följd: sidan ogiltig
GATOR = ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'unclassified', 'residential',
         'living_street', 'service', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link',
         'tertiary_link')


def las_vagar(karta):
    import vagnat
    work = ROOT / karta / 'work'
    os.environ.setdefault('GEO_WORK', str(work))
    os.environ.setdefault('GEO_NAMN', karta)
    g = json.load(open(work / 'grid.json'))
    x0, y1 = g['x0'], g['y1']
    x1, y0 = x0 + g['W'] * g['RES'], y1 - g['H'] * g['RES']
    feat = pickle.load(open(work / 'features.pkl', 'rb'))
    roads = vagnat.vaglista(feat['roads'], box(x0, y0, x1, y1))
    vagnat.forbered(roads, (x0, y0, x1, y1), work)
    return roads, (x0, y0, x1, y1)


class Raster:
    def __init__(self, fil):
        with rasterio.open(fil) as r:
            self.A = r.read()
            self.T = r.transform
            self.inv = ~r.transform

    def nara(self, x, y, band=None):
        c, rr = self.inv * (np.asarray(x), np.asarray(y))
        c = np.clip(np.floor(c).astype(int), 0, self.A.shape[2] - 1)
        rr = np.clip(np.floor(rr).astype(int), 0, self.A.shape[1] - 1)
        return self.A[:, rr, c] if band is None else self.A[band, rr, c]


def mat_sida(asf, okand, start, steg):
    """Index för sista asfaltsprovet åt ena hållet från start, eller None om sidan är ogiltig."""
    n = len(asf)
    sist = start
    fel, okand_i_folj = 0, 0
    i = start
    stopp = int(round(STOPP_M / STEG_M))
    okmax = int(round(OKAND_MAX_M / STEG_M))
    while 0 <= i < n:
        if okand[i]:
            okand_i_folj += 1
            if okand_i_folj > okmax:
                return None
        elif asf[i]:
            sist, fel, okand_i_folj = i, 0, 0
        else:
            fel += 1
            okand_i_folj = 0
            if fel >= stopp:
                return sist
        i += steg
    return None   # asfalt ända ut: parkering, torg, korsning


def mat_vag(r, orto, hojd):
    L = r['line']
    hw_arr = np.asarray(r['hw'], float)
    s_hw = np.linspace(0, L.length, len(hw_arr))
    ut = []
    for s in np.arange(TVAR_AVST_M / 2, L.length - 2.0, TVAR_AVST_M):
        c = np.array(L.interpolate(s).coords[0])
        d = np.array(L.interpolate(min(s + 1, L.length)).coords[0]) - np.array(L.interpolate(max(s - 1, 0)).coords[0])
        d /= max(np.linalg.norm(d), 1e-9)
        nl = np.array([-d[1], d[0]])
        hw = float(np.interp(s, s_hw, hw_arr))
        R = hw + FONSTER_EXTRA_M
        t = np.arange(-R, R + 1e-6, STEG_M)
        P = c[None, :] + nl[None, :] * t[:, None]
        px = orto.nara(P[:, 0], P[:, 1]).astype(float)   # (4, n)
        rgb, nir = px[:3].T, px[3]
        ndvi = (nir - rgb[:, 0]) / (nir + rgb[:, 0] + 1.0)
        h = hojd.nara(P[:, 0], P[:, 1], 0).astype(float) / 10.0
        okand = h > HINDER_H_M
        mitt = (np.abs(t) <= min(REF_HALV_M, hw * 0.5)) & ~okand & (ndvi < NDVI_MAX)
        if mitt.sum() < 3:
            ut.append((s, hw, np.nan, np.nan, c, nl))
            continue
        ref = np.median(rgb[mitt], axis=0)
        asf = (ndvi < NDVI_MAX) & (np.linalg.norm(rgb - ref, axis=1) < FARG_MAX) & ~okand
        i0 = int(np.argmin(np.abs(t)))
        iv = mat_sida(asf, okand, i0, +1)    # vänster (+nl)
        ih = mat_sida(asf, okand, i0, -1)    # höger
        if iv is None or ih is None:
            ut.append((s, hw, np.nan, np.nan, c, nl))
            continue
        tv, th = t[iv] + STEG_M / 2, t[ih] - STEG_M / 2
        ut.append((s, hw, tv, th, c, nl))
    return ut


def sammanfatta(r, prov):
    tv = np.array([p[2] for p in prov]); th = np.array([p[3] for p in prov])
    hw = np.array([p[1] for p in prov])
    ok = np.isfinite(tv) & np.isfinite(th)
    if not ok.any():
        return dict(giltiga=0.0)
    bredd = (tv - th)[ok]
    forsk = ((tv + th) / 2)[ok]
    q1, q3 = np.percentile(bredd, [25, 75])
    return dict(giltiga=ok.mean(), modell=float(np.median(2 * hw)), matt=float(np.median(bredd)),
                sprid=float(q3 - q1), forsk=float(np.median(forsk)), n=int(ok.sum()))


def bild(r, prov, orto, fil, titel):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    L = r['line']
    mitt = L.interpolate(0.5, normalized=True)
    halv = max(30.0, min(80.0, L.length / 2 + 10))
    x0, x1, y0, y1 = mitt.x - halv, mitt.x + halv, mitt.y - halv, mitt.y + halv
    r0, c0 = rasterio.transform.rowcol(orto.T, x0, y1)
    r1, c1 = rasterio.transform.rowcol(orto.T, x1, y0)
    r0, c0 = max(r0, 0), max(c0, 0)
    sub = orto.A[:3, r0:r1, c0:c1].transpose(1, 2, 0)
    fig, ax = plt.subplots(figsize=(8, 8), dpi=110)
    ax.imshow(sub, extent=(x0, x0 + sub.shape[1] * 0.5, y1 - sub.shape[0] * 0.5, y1))
    for s, hw, tv, th, c, nl in prov:
        a, b = c + nl * hw, c - nl * hw
        ax.plot([a[0], b[0]], [a[1], b[1]], color='yellow', lw=0.6, alpha=0.6)
        ax.plot(*(c + nl * hw), 'o', color='yellow', ms=2.5)
        ax.plot(*(c - nl * hw), 'o', color='yellow', ms=2.5)
        if np.isfinite(tv):
            ax.plot(*(c + nl * tv), 'o', color='red', ms=3)
            ax.plot(*(c + nl * th), 'o', color='red', ms=3)
    xs, ys = L.xy
    ax.plot(xs, ys, color='cyan', lw=0.8)
    ax.set_xlim(x0, x1); ax.set_ylim(y0, y1)
    ax.set_title(titel, fontsize=9)
    ax.set_xticks([]); ax.set_yticks([])
    fig.tight_layout()
    fig.savefig(fil)
    plt.close(fig)


def oversikt(roads, res, ruta, fil):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(14, 14 * (ruta[3] - ruta[1]) / (ruta[2] - ruta[0])), dpi=110)
    ax.set_facecolor('#202020')
    cm = plt.get_cmap('RdBu_r')
    for k, r in enumerate(roads):
        xs, ys = r['line'].xy
        s = res.get(k)
        if not s or s.get('giltiga', 0) < 0.3:
            ax.plot(xs, ys, color='#606060', lw=0.6)
            continue
        diff = s['matt'] - s['modell']
        ax.plot(xs, ys, color=cm(0.5 + np.clip(diff / 6.0, -0.5, 0.5)), lw=2.0)
    ax.set_xlim(ruta[0], ruta[2]); ax.set_ylim(ruta[1], ruta[3]); ax.set_aspect('equal')
    ax.set_title('uppmätt − modell: röd = bredare i verkligheten, blå = smalare (±3 m), grå = ej mätt', fontsize=10)
    ax.set_xticks([]); ax.set_yticks([])
    fig.tight_layout()
    fig.savefig(fil)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('karta')
    ap.add_argument('--bilder', type=int, default=16)
    ap.add_argument('--ruta', default=None, help='E,N,halv: bara vägar inom rutan')
    a = ap.parse_args()
    roads, ruta = las_vagar(a.karta)
    data = ROOT / a.karta / 'data'
    orto = Raster(data / f'ortofoto_{a.karta}.tif')
    hojd = Raster(data / f'objekthojd_{a.karta}.tif')
    urval = None
    if a.ruta:
        E, N, H = (float(v) for v in a.ruta.split(','))
        urval = box(E - H, N - H, E + H, N + H)
    res, prov_alla = {}, {}
    for k, r in enumerate(roads):
        t = r['tags']
        if t['highway'] not in GATOR or r['surface'] != 'asfalt' or t.get('bridge') or t.get('tunnel') \
                or r['line'].length < 15 or (urval is not None and not r['line'].intersects(urval)):
            continue
        prov = mat_vag(r, orto, hojd)
        prov_alla[k] = prov
        res[k] = sammanfatta(r, prov)
    ut = ROOT / 'analys' / 'ut' / f'{a.karta}_bredd'
    ut.mkdir(parents=True, exist_ok=True)
    for f in ut.glob('*.png'):
        f.unlink()
    with open(ut / 'vagar.csv', 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['index', 'namn', 'highway', 'oneway', 'langd_m', 'giltiga', 'modell_m', 'matt_m', 'sprid_m',
                    'forskjutning_m', 'E', 'N'])
        for k, s in res.items():
            r = roads[k]
            m = r['line'].interpolate(0.5, normalized=True)
            w.writerow([k, r['tags'].get('name', ''), r['tags']['highway'], r['tags'].get('oneway', ''),
                        round(r['line'].length), round(s.get('giltiga', 0), 2), round(s.get('modell', np.nan), 2),
                        round(s.get('matt', np.nan), 2), round(s.get('sprid', np.nan), 2),
                        round(s.get('forsk', np.nan), 2), round(m.x, 1), round(m.y, 1)])
    # sammanfattning per vägklass (längdviktad)
    rader = [f'Vägbredd ur ortofotot, {a.karta}: {len(res)} vägar mätta', '']
    rader.append(f'{"klass":14} {"km":>6} {"mätt":>6}  {"avvikelse median":>17} {"p10..p90":>14}  {"|förskj.| median":>17}')
    klasser = {}
    for k, s in res.items():
        if s.get('giltiga', 0) < 0.3:
            continue
        klasser.setdefault(roads[k]['tags']['highway'], []).append((roads[k]['line'].length, s))
    for kl, lista in sorted(klasser.items(), key=lambda kv: -sum(l for l, _ in kv[1])):
        L_ = np.array([l for l, _ in lista])
        diff = np.array([s['matt'] - s['modell'] for _, s in lista])
        fs = np.array([abs(s['forsk']) for _, s in lista])
        o = np.argsort(diff); cw = np.cumsum(L_[o]) / L_.sum()
        p = lambda q: diff[o][min(np.searchsorted(cw, q), len(o) - 1)]
        tot = sum(roads[k]['line'].length for k in res if roads[k]['tags']['highway'] == kl) / 1000
        rader.append(f'{kl:14} {tot:6.1f} {L_.sum() / 1000:6.1f}  {p(0.5):+17.2f} {p(0.1):+6.1f}..{p(0.9):+5.1f}  '
                     f'{np.median(fs):17.2f}')
    # största avvikelserna (säkra mätningar, viktade med längden)
    kand = [(abs(s['matt'] - s['modell']) * min(roads[k]['line'].length, 100), k) for k, s in res.items()
            if s.get('giltiga', 0) >= 0.5 and s.get('sprid', 9) < 2.0 and abs(s['matt'] - s['modell']) > 1.0]
    kand.sort(reverse=True)
    rader += ['', f'Största säkra avvikelserna (giltiga ≥ 50 %, spridning < 2 m, > 1 m fel): {len(kand)} vägar', '']
    for i, (_, k) in enumerate(kand[:40]):
        s, r = res[k], roads[k]
        m = r['line'].interpolate(0.5, normalized=True)
        rader.append(f'{i:2} {r["tags"].get("name", "-")[:24]:24} {r["tags"]["highway"]:12} modell {s["modell"]:5.1f} '
                     f'mätt {s["matt"]:5.1f} (±{s["sprid"] / 2:.1f}) förskj {s["forsk"]:+5.1f}  E {m.x:.0f} N {m.y:.0f}')
        if i < a.bilder:
            bild(r, prov_alla[k], orto, ut / f'{i:02d}_{r["tags"].get("name", "vag").replace(" ", "_")[:20]}.png',
                 f'{r["tags"].get("name", "-")} ({r["tags"]["highway"]}): modell {s["modell"]:.1f} m (gult), '
                 f'mätt {s["matt"]:.1f} m (rött), förskj. {s["forsk"]:+.1f} m')
    text = '\n'.join(rader)
    print(text)
    (ut / 'sammanfattning.txt').write_text(text + '\n')
    if not a.ruta:
        oversikt(roads, res, ruta, ut / 'oversikt.png')


if __name__ == '__main__':
    main()
