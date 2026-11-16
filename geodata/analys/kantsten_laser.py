"""Kantsten ur laserns markhöjd mot OSM:s trottoarer (analys; bygger inget, rör inte spelet).

  geodata/.venv/bin/python geodata/analys/kantsten_laser.py <karta> [--ruta E,N[,halv]]

Var TVAR_AVST_M:e meter längs varje asfalterad bilväg: markhöjden (1 m-raster, bilinjärt) i ett
tvärsnitt. Vägbanan (tvärfall och bombering) anpassas som en andragradskurva över |t| < hw − 1 m; steget på varje sida är
medelavvikelsen från linjen strax utanför kanten (hw + 0,5 .. hw + 2 m) minus strax innanför
(hw − 1,5 .. hw − 0,5 m). Steg över STEG_KANTSTEN_M = kantsten (eller trottoar/slänt uppåt), under
−STEG_KANTSTEN_M = dike/slänt nedåt. Laserns markpunkter är ~1 m isär, så ett 12 cm-steg syns som en
mjuk ramp: det här är ett test av om det räcker.
Per väg och sida: andel tvärsnitt med kantsten, jämfört med OSM sidewalk(:left/right) och NVDB/OSM.
Ut (geodata/analys/ut/<karta>_kantsten/): vagar.csv, sammanfattning.txt (OSM-trottoar mot uppmätt
kantsten), oversikt.png (sidor färgade efter andelen), profil_<plats>.png (några tvärsnitt).
"""
import argparse
import csv

import numpy as np
from shapely.geometry import box

import gemensamt as G

TVAR_AVST_M = 10.0
STEG_M = 0.5
STEG_KANTSTEN_M = 0.07
KANTSTEN_ANDEL = 0.5     # en sida "har kantsten" om minst så stor andel av tvärsnitten visar steget


def osm_sidor(t):
    """{'left': True/False/None, 'right': ...}: OSM:s trottoar per sida (None = okänt)."""
    ut = {'left': None, 'right': None}
    sw = t.get('sidewalk')
    if sw in ('both', 'yes'):
        ut = {'left': True, 'right': True}
    elif sw in ('left', 'right'):
        ut = {'left': sw == 'left', 'right': sw == 'right'}
    elif sw in ('no', 'none', 'separate'):
        ut = {'left': False, 'right': False}
    for sd in ('left', 'right'):
        v = t.get(f'sidewalk:{sd}') or t.get('sidewalk:both')
        if v == 'yes':
            ut[sd] = True
        elif v in ('no', 'separate'):
            ut[sd] = False
    return ut


def tvarsnitt(r, M):
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
        t = np.arange(-(hw + 4), hw + 4 + 1e-6, STEG_M)
        P = c[None, :] + nl[None, :] * t[:, None]
        z = M.bilinjar(P[:, 0], P[:, 1])
        inne = np.abs(t) < max(hw - 1.0, 0.75)
        if inne.sum() < 3 or not np.isfinite(z).all():
            continue
        # vägbanan: bombering (mitten högst, rännstenar vid kanterna) som andragradskurva, annars rät linje
        grad = 2 if inne.sum() >= 6 else 1
        res = z - np.polyval(np.polyfit(t[inne], z[inne], grad), t)
        steg = {}
        for sd, tecken in (('left', 1), ('right', -1)):
            ute = (tecken * t >= hw + 0.5) & (tecken * t <= hw + 2.0)
            inn = (tecken * t >= hw - 1.5) & (tecken * t <= hw - 0.5)
            steg[sd] = float(res[ute].mean() - res[inn].mean()) if ute.any() and inn.any() else np.nan
        ut.append(dict(s=s, t=t, res=res, hw=hw, steg=steg))
    return ut


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('karta')
    ap.add_argument('--ruta', default=None)
    a = ap.parse_args()
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    roads, _, ruta = G.las_vagar(a.karta, med_bro=False)
    M = G.markhojd(a.karta)
    urval = None
    if a.ruta:
        v = [float(x) for x in a.ruta.split(',')]
        h_ = v[2] if len(v) > 2 else 100.0
        urval = box(v[0] - h_, v[1] - h_, v[0] + h_, v[1] + h_)
    ut = G.ut_mapp(a.karta, 'kantsten')
    res = {}
    for k, r in enumerate(roads):
        t = r['tags']
        if t['highway'] not in G.GATOR or r['surface'] != 'asfalt' or t.get('bridge') or t.get('tunnel') \
                or r['line'].length < 15 or (urval is not None and not r['line'].intersects(urval)):
            continue
        ts = tvarsnitt(r, M)
        if not ts:
            continue
        andel = {sd: float(np.nanmean([x['steg'][sd] > STEG_KANTSTEN_M for x in ts])) for sd in ('left', 'right')}
        median = {sd: float(np.nanmedian([x['steg'][sd] for x in ts])) for sd in ('left', 'right')}
        res[k] = dict(andel=andel, median=median, osm=osm_sidor(t), ts=ts)
    with open(ut / 'vagar.csv', 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['index', 'namn', 'highway', 'langd_m', 'osm_vanster', 'osm_hoger', 'kantsten_andel_v',
                    'kantsten_andel_h', 'steg_median_v_m', 'steg_median_h_m', 'E', 'N'])
        for k, x in res.items():
            r = roads[k]
            m = r['line'].interpolate(0.5, normalized=True)
            w.writerow([k, r['tags'].get('name', ''), r['tags']['highway'], round(r['line'].length),
                        x['osm']['left'], x['osm']['right'], round(x['andel']['left'], 2), round(x['andel']['right'], 2),
                        round(x['median']['left'], 3), round(x['median']['right'], 3), round(m.x), round(m.y)])
    # OSM mot laser, per sida, längdviktat
    tab = {}
    for k, x in res.items():
        Lk = roads[k]['line'].length
        for sd in ('left', 'right'):
            o = {True: 'OSM trottoar', False: 'OSM ingen', None: 'OSM okänt'}[x['osm'][sd]]
            l_ = 'kantsten' if x['andel'][sd] >= KANTSTEN_ANDEL else 'ingen'
            tab[(o, l_)] = tab.get((o, l_), 0.0) + Lk / 1000
    rader = [f'Kantsten ur lasern, {a.karta}: {len(res)} vägar (km vägsida, steg > {STEG_KANTSTEN_M * 100:.0f} cm '
             f'i minst {KANTSTEN_ANDEL:.0%} av tvärsnitten = kantsten)', '',
             f'{"":14} {"kantsten":>9} {"ingen":>9}']
    for o in ('OSM trottoar', 'OSM ingen', 'OSM okänt'):
        rader.append(f'{o:14} {tab.get((o, "kantsten"), 0):9.1f} {tab.get((o, "ingen"), 0):9.1f}')
    rader += ['', 'Rimligt utfall: OSM trottoar -> mest kantsten; OSM ingen -> mest ingen. OSM okänt med kantsten',
              '= trottoarer OSM saknar (kandidater).']
    text = '\n'.join(rader)
    print(text)
    (ut / 'sammanfattning.txt').write_text(text + '\n')
    # översikt: varje sida som en förskjuten linje, färg efter andelen
    if not a.ruta:
        fig, ax = plt.subplots(figsize=(14, 14 * (ruta[3] - ruta[1]) / (ruta[2] - ruta[0])), dpi=110)
        ax.set_facecolor('#202020')
        cm = plt.get_cmap('viridis')
        for k, x in res.items():
            L = roads[k]['line']
            hw = float(np.median(roads[k]['hw']))
            for sd, tecken in (('left', 1), ('right', -1)):
                try:
                    o = L.offset_curve(tecken * (hw + 1.0))
                except Exception:
                    continue
                for g in getattr(o, 'geoms', [o]):
                    if g.is_empty:
                        continue
                    ax.plot(*g.xy, color=cm(x['andel'][sd]), lw=1.2)
        ax.set_xlim(ruta[0], ruta[2]); ax.set_ylim(ruta[1], ruta[3]); ax.set_aspect('equal')
        ax.set_title('andel tvärsnitt med kantsten per vägsida (gul = alla, lila = inga)', fontsize=10)
        ax.set_xticks([]); ax.set_yticks([])
        fig.tight_layout(); fig.savefig(ut / 'oversikt.png'); plt.close(fig)
    # profiler vid testplatserna
    for namn, fon in G.platser(a.karta, a.ruta, 60.0):
        nara = [k for k in res if roads[k]['line'].intersects(fon)]
        if not nara:
            continue
        fig, axs = plt.subplots(2, 3, figsize=(15, 7), dpi=100)
        for ax, k in zip(axs.ravel(), sorted(nara, key=lambda k: -roads[k]['line'].length)[:6]):
            x = res[k]
            for tv in x['ts'][:12]:
                ax.plot(tv['t'], tv['res'] * 100, color='#4060c0', alpha=0.35, lw=0.8)
            hw = x['ts'][0]['hw']
            for v in (hw, -hw):
                ax.axvline(v, color='orange', lw=0.8)
            ax.set_ylim(-40, 40)
            ax.set_title(f'{roads[k]["tags"].get("name", "-")} | OSM v {x["osm"]["left"]} h {x["osm"]["right"]} | '
                         f'kantsten v {x["andel"]["left"]:.0%} h {x["andel"]["right"]:.0%}', fontsize=7)
            ax.set_xlabel('m från mittlinjen (+ vänster)', fontsize=7)
            ax.set_ylabel('cm över tvärfallet', fontsize=7)
        fig.suptitle(f'{namn}: markhöjd tvärs vägen minus vägbanans tvärfall (orange = modellens kant)', fontsize=9)
        fig.tight_layout(); fig.savefig(ut / f'profil_{namn}.png'); plt.close(fig)


if __name__ == '__main__':
    main()
