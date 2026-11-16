"""Vägbredd och läge ur ortofotot (analys; bygger inget och rör inte spelet).

  geodata/.venv/bin/python geodata/analys/vagbredd_orto.py <karta> [--bilder N] [--ruta E,N[,halv]]
      [--orto fil.tif]

Vägnätet läses precis som step3 (gemensamt.las_vagar). Var TVAR_AVST_M:e meter längs varje asfalterad
bilväg tas ett tvärsnitt i ortofotot (pixelklasser i gemensamt.ytklasser): asfaltens referensfärg ur
mitten, sedan utåt åt båda hållen:
  asfaltkant   sista pixeln med referensfärgen innan STOPP_M annat (grönt, annan färg) i följd
  hårdkant     samma men för all hårdgjord yta (grått, inte grönt), oavsett färg: plattor, trottoar i
               samma nivå, parkering; långt utanför asfaltkanten = vägen ligger i en större hård yta
Skugga och skymt (laserns objekthöjd: träd, bilar) är okänt, inte slut; ett tvärsnitt som blir ogiltigt
i sommarfotot mäts om i vårfotot (gemensamt.orto_var, inga löv: bara hinder under 3 m skymmer); mer än OKAND_MAX_M okänt i följd
eller asfalt ända ut till fönstrets kant gör sidan ogiltig. Per väg: medianbredd, spridning (p25..p75),
mittlinjens förskjutning (+ = åt vänster i linjens riktning), andel giltiga tvärsnitt och en säkerhetsklass:
  säker      minst 50 % giltiga och spridning < 1,5 m
  osäker     annars (för få giltiga, eller bredden hoppar)
  skuggig    mest skugga/skymt i mitten (smala gångar mellan hus): mätningen underskattar
Ut (geodata/analys/ut/<karta>_bredd/): vagar.csv, sammanfattning.txt, oversikt.png, NN_<namn>.png.
"""
import argparse
import csv

import numpy as np
from shapely.geometry import box

import gemensamt as G

TVAR_AVST_M = 10.0
STEG_M = 0.25
FONSTER_EXTRA_M = 7.0
REF_HALV_M = 1.0
FARG_MAX = 32.0          # RGB-avstånd till referensen: samma beläggning
MALAT_LJUSARE = 45.0     # vit färg: så mycket ljusare än asfalten (räknas som väg)
STOPP_M = 1.0
OKAND_MAX_M = 4.0
SAKER_GILTIGA = 0.5
SAKER_SPRID_M = 1.5


def mat_sida(bra, okand, start, steg):
    """Index för sista 'bra' provet åt ena hållet, eller None (för mycket okänt / bra ända ut)."""
    n = len(bra)
    sist, fel, ok_i_folj = start, 0, 0
    stopp, okmax = int(round(STOPP_M / STEG_M)), int(round(OKAND_MAX_M / STEG_M))
    i = start
    while 0 <= i < n:
        if okand[i]:
            ok_i_folj += 1
            if ok_i_folj > okmax:
                return None
        elif bra[i]:
            sist, fel, ok_i_folj = i, 0, 0
        else:
            fel += 1
            ok_i_folj = 0
            if fel >= stopp:
                return sist
        i += steg
    return None


def mat_vag(r, orto, hojd, var=None):
    """Tvärsnitten längs vägen r. var: vårfotot (inga löv); ett tvärsnitt som i sommarfotot är skymt av träd
    (för mycket okänt) mäts om i vårfotot (där räknas bara laserns lägre hinder, bilar, som skymt)."""
    ut = []
    for rad in _mat_vag(r, orto, hojd, False):
        if var is not None and not np.isfinite(rad['tv']):
            ny = _mat_ett(r, rad['s'], var, hojd, True)
            if np.isfinite(ny['tv']):
                ny['var'] = True
                rad = ny
        ut.append(rad)
    return ut


def _mat_vag(r, orto, hojd, var):
    L = r['line']
    return [_mat_ett(r, s, orto, hojd, var) for s in np.arange(TVAR_AVST_M / 2, L.length - 2.0, TVAR_AVST_M)]


def _mat_ett(r, s, orto, hojd, var):
    L = r['line']
    hw_arr = np.asarray(r['hw'], float)
    s_hw = np.linspace(0, L.length, len(hw_arr))
    if True:
        c = np.array(L.interpolate(s).coords[0])
        d = np.array(L.interpolate(min(s + 1, L.length)).coords[0]) - np.array(L.interpolate(max(s - 1, 0)).coords[0])
        d /= max(np.linalg.norm(d), 1e-9)
        nl = np.array([-d[1], d[0]])
        hw = float(np.interp(s, s_hw, hw_arr))
        R = hw + FONSTER_EXTRA_M
        t = np.arange(-R, R + 1e-6, STEG_M)
        P = c[None, :] + nl[None, :] * t[:, None]
        px = orto.nara(P[:, 0], P[:, 1]).astype(float)
        rgb, nir = px[:3].T, px[3]
        h = hojd.nara(P[:, 0], P[:, 1], 0).astype(float) / 10.0
        k = G.ytklasser(rgb, nir, h)
        if var:   # vårfotot: kronorna är kala, bara låga hinder (bilar, under 3 m) skymmer
            k['skymt'] = (h > G.HINDER_H_M) & (h < 3.0)
            k['hard'] = ~k['gron'] & ~k['skymt'] & ~k['skugga'] & (k['mattnad'] < G.MATTNAD_HARD)
        okand = k['skymt'] | k['skugga']
        mitt = np.abs(t) <= min(REF_HALV_M, hw * 0.5)
        rad = dict(s=s, hw=hw, c=c, nl=nl, tv=np.nan, th=np.nan, hv=np.nan, hh=np.nan,
                   skugga=float(okand[mitt].mean()))
        ref_ok = mitt & k['hard']
        if ref_ok.sum() >= 3:
            ref = np.median(rgb[ref_ok], axis=0)
            # vägmarkeringar (vitt, grått) är också väg: annars stannar mätningen vid första linjen
            malat = ~k['gron'] & ~k['skymt'] & (k['ljus'] > ref.mean() + MALAT_LJUSARE) & (k['mattnad'] < G.MATTNAD_HARD)
            asf = (k['hard'] & (np.linalg.norm(rgb - ref, axis=1) < FARG_MAX)) | malat
            i0 = int(np.argmin(np.abs(t)))
            iv, ih = mat_sida(asf, okand, i0, +1), mat_sida(asf, okand, i0, -1)
            if iv is not None and ih is not None:
                rad['tv'], rad['th'] = t[iv] + STEG_M / 2, t[ih] - STEG_M / 2
            jv, jh = mat_sida(k['hard'], okand, i0, +1), mat_sida(k['hard'], okand, i0, -1)
            rad['hv'] = t[jv] + STEG_M / 2 if jv is not None else np.inf
            rad['hh'] = t[jh] - STEG_M / 2 if jh is not None else -np.inf
        return rad


def sammanfatta(prov):
    if not prov:
        return dict(giltiga=0.0, klass='osäker')
    tv = np.array([p['tv'] for p in prov]); th = np.array([p['th'] for p in prov])
    hw = np.array([p['hw'] for p in prov])
    skugga = float(np.mean([p['skugga'] for p in prov]))
    ok = np.isfinite(tv) & np.isfinite(th)
    res = dict(giltiga=float(ok.mean()), modell=float(np.median(2 * hw)), skugga=skugga, n=int(ok.sum()))
    if not ok.any():
        res['klass'] = 'skuggig' if skugga > 0.5 else 'osäker'
        return res
    bredd = (tv - th)[ok]
    q1, q3 = np.percentile(bredd, [25, 75])
    hv = np.array([p['hv'] for p in prov])[ok]; hh = np.array([p['hh'] for p in prov])[ok]
    hard = hv - hh
    res.update(matt=float(np.median(bredd)), sprid=float(q3 - q1), forsk=float(np.median(((tv + th) / 2)[ok])),
               hard=float(np.median(hard[np.isfinite(hard)])) if np.isfinite(hard).any() else np.inf)
    if skugga > 0.5:
        res['klass'] = 'skuggig'
    elif res['giltiga'] >= SAKER_GILTIGA and res['sprid'] < SAKER_SPRID_M:
        res['klass'] = 'säker'
    else:
        res['klass'] = 'osäker'
    return res


def bild(r, prov, orto, fil, titel):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    L = r['line']
    m = L.interpolate(0.5, normalized=True)
    halv = max(30.0, min(80.0, L.length / 2 + 10))
    sub, ext, _ = orto.utsnitt(m.x - halv, m.y - halv, m.x + halv, m.y + halv)
    fig, ax = plt.subplots(figsize=(8, 8), dpi=110)
    ax.imshow(sub[:3].transpose(1, 2, 0), extent=ext)
    for p in prov:
        c, nl, hw = p['c'], p['nl'], p['hw']
        ax.plot(*np.c_[c + nl * hw, c - nl * hw], color='yellow', lw=0.6, alpha=0.6)
        for v in (hw, -hw):
            ax.plot(*(c + nl * v), 'o', color='yellow', ms=2.5)
        for v in (p['hv'], p['hh']):
            if np.isfinite(v):
                ax.plot(*(c + nl * v), 's', color='#40c0ff', ms=2.5)
        if np.isfinite(p['tv']):
            ax.plot(*(c + nl * p['tv']), 'o', color='red', ms=3)
            ax.plot(*(c + nl * p['th']), 'o', color='red', ms=3)
    ax.plot(*L.xy, color='cyan', lw=0.8)
    ax.set_xlim(m.x - halv, m.x + halv); ax.set_ylim(m.y - halv, m.y + halv)
    ax.set_title(titel, fontsize=8)
    ax.set_xticks([]); ax.set_yticks([])
    fig.tight_layout(); fig.savefig(fil); plt.close(fig)


def oversikt(roads, res, ruta, fil):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots(figsize=(14, 14 * (ruta[3] - ruta[1]) / (ruta[2] - ruta[0])), dpi=110)
    ax.set_facecolor('#202020')
    cm = plt.get_cmap('RdBu_r')
    for k, r in enumerate(roads):
        s = res.get(k)
        if not s or s.get('klass') != 'säker':
            ax.plot(*r['line'].xy, color='#606060' if not s else '#a0a040', lw=0.6)
            continue
        diff = s['matt'] - s['modell']
        ax.plot(*r['line'].xy, color=cm(0.5 + np.clip(diff / 6.0, -0.5, 0.5)), lw=2.0)
    ax.set_xlim(ruta[0], ruta[2]); ax.set_ylim(ruta[1], ruta[3]); ax.set_aspect('equal')
    ax.set_title('säkra mätningar, uppmätt − modell: röd = bredare i verkligheten, blå = smalare (±3 m); '
                 'gul = osäker/skuggig, grå = ej mätt', fontsize=9)
    ax.set_xticks([]); ax.set_yticks([])
    fig.tight_layout(); fig.savefig(fil); plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('karta')
    ap.add_argument('--bilder', type=int, default=16)
    ap.add_argument('--ruta', default=None, help='E,N[,halv]: bara vägar inom rutan')
    ap.add_argument('--orto', default=None, help='annat ortofoto (t.ex. 16 cm)')
    ap.add_argument('--utan-var', action='store_true', help='mät inte om skymda tvärsnitt i vårfotot')
    a = ap.parse_args()
    roads, _, ruta = G.las_vagar(a.karta, med_bro=False)
    orto, hojd = G.orto(a.karta, a.orto), G.objekthojd(a.karta)
    var = None if a.utan_var else G.orto_var(a.karta)
    urval = None
    if a.ruta:
        v = [float(x) for x in a.ruta.split(',')]
        h_ = v[2] if len(v) > 2 else 100.0
        urval = box(v[0] - h_, v[1] - h_, v[0] + h_, v[1] + h_)
    res, prov_alla = {}, {}
    for k, r in enumerate(roads):
        t = r['tags']
        if t['highway'] not in G.GATOR or r['surface'] != 'asfalt' or t.get('bridge') or t.get('tunnel') \
                or r['line'].length < 15 or (urval is not None and not r['line'].intersects(urval)):
            continue
        prov_alla[k] = mat_vag(r, orto, hojd, var)
        res[k] = sammanfatta(prov_alla[k])
    ut = G.ut_mapp(a.karta, 'bredd')
    for f in ut.glob('*.png'):
        f.unlink()
    with open(ut / 'vagar.csv', 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['index', 'namn', 'highway', 'oneway', 'langd_m', 'klass', 'giltiga', 'skugga', 'modell_m',
                    'matt_m', 'sprid_m', 'hardyta_m', 'forskjutning_m', 'E', 'N'])
        for k, s in res.items():
            r = roads[k]
            m = r['line'].interpolate(0.5, normalized=True)
            w.writerow([k, r['tags'].get('name', ''), r['tags']['highway'], r['tags'].get('oneway', ''),
                        round(r['line'].length), s['klass'], round(s['giltiga'], 2), round(s.get('skugga', 0), 2),
                        round(s.get('modell', np.nan), 2), round(s.get('matt', np.nan), 2),
                        round(s.get('sprid', np.nan), 2), round(s.get('hard', np.nan), 2),
                        round(s.get('forsk', np.nan), 2), round(m.x, 1), round(m.y, 1)])
    langd = lambda ks: sum(roads[k]['line'].length for k in ks) / 1000
    n_var = sum(1 for pr in prov_alla.values() for p_ in pr if p_.get('var'))
    n_tot = sum(len(pr) for pr in prov_alla.values())
    rader = [f'Vägbredd ur ortofotot, {a.karta}: {len(res)} vägar, {langd(res):.1f} km; '
             f'{n_var} av {n_tot} tvärsnitt mätta i vårfotot (skymda av löv i sommarfotot)', '']
    for kl in ('säker', 'osäker', 'skuggig'):
        ks = [k for k, s in res.items() if s['klass'] == kl]
        rader.append(f'  {kl:8} {len(ks):5} vägar {langd(ks):6.1f} km')
    rader += ['', 'Säkra mätningar per vägklass (längdviktat):',
              f'{"klass":14} {"km":>6}  {"avvikelse median":>17} {"p10..p90":>14}  {"|förskj.| median":>17}']
    klasser = {}
    for k, s in res.items():
        if s['klass'] == 'säker':
            klasser.setdefault(roads[k]['tags']['highway'], []).append((roads[k]['line'].length, s))
    for kl, lista in sorted(klasser.items(), key=lambda kv: -sum(l for l, _ in kv[1])):
        L_ = np.array([l for l, _ in lista])
        diff = np.array([s['matt'] - s['modell'] for _, s in lista])
        fs = np.array([abs(s['forsk']) for _, s in lista])
        o = np.argsort(diff); cw = np.cumsum(L_[o]) / L_.sum()
        p = lambda q: diff[o][min(np.searchsorted(cw, q), len(o) - 1)]
        rader.append(f'{kl:14} {L_.sum() / 1000:6.1f}  {p(0.5):+17.2f} {p(0.1):+6.1f}..{p(0.9):+5.1f}  {np.median(fs):17.2f}')
    kand = sorted(((abs(s['matt'] - s['modell']) * min(roads[k]['line'].length, 100), k) for k, s in res.items()
                   if s['klass'] == 'säker' and abs(s['matt'] - s['modell']) > 1.0), reverse=True)
    rader += ['', f'Största säkra avvikelserna (> 1 m): {len(kand)} vägar', '']
    for i, (_, k) in enumerate(kand[:40]):
        s, r = res[k], roads[k]
        m = r['line'].interpolate(0.5, normalized=True)
        hard = f'{s["hard"]:5.1f}' if np.isfinite(s.get('hard', np.inf)) else '  ∞  '
        rader.append(f'{i:2} {r["tags"].get("name", "-")[:24]:24} {r["tags"]["highway"]:13} modell {s["modell"]:5.1f} '
                     f'mätt {s["matt"]:5.1f} (±{s["sprid"] / 2:.1f}) hård {hard} förskj {s["forsk"]:+5.1f}  '
                     f'E {m.x:.0f} N {m.y:.0f}')
        if i < a.bilder:
            namn = r['tags'].get('name', 'vag').replace(' ', '_')[:20]
            bild(r, prov_alla[k], orto, ut / f'{i:02d}_{namn}.png',
                 f'{r["tags"].get("name", "-")} ({r["tags"]["highway"]}): modell {s["modell"]:.1f} m (gult), '
                 f'asfalt {s["matt"]:.1f} m (rött), hårdgjort (blått), förskj. {s["forsk"]:+.1f} m')
    text = '\n'.join(rader)
    print(text)
    (ut / 'sammanfattning.txt').write_text(text + '\n')
    if not a.ruta:
        oversikt(roads, res, ruta, ut / 'oversikt.png')


if __name__ == '__main__':
    main()
