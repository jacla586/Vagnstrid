"""Före/efter: spelets vägyta med dagens bredder mot med bredder och lägen uppmätta i ortofotot
(analys; bygger inget, rör inte spelet).

  geodata/.venv/bin/python geodata/analys/vagkorr_orto.py <karta> [--ruta E,N[,halv]] [--halv m]

1. Mätning som vagbredd_orto.py (tvärsnitt var 10 m, vårfotot där löv skymmer) på alla asfalterade bilvägar.
2. Rättning, bara av säkra mätningar (vagbredd_orto: klass 'säker'):
   - en bredd per gata: vägar med samma namn och enkelriktning som hänger ihop (som nvdb.harmonisera)
     får den längdviktade medianen av sina säkra mätningar; onamngivna vägar var för sig
   - smala (asfaltbredd under SMAL_M): den hårdgjorda bredden om den är rimlig (plattbelagda gångar
     mellan hus mäts annars för smalt)
   - ändringen begränsas till faktor BREDD_FAKTOR och minst MIN_BREDD_M; mindre än MIN_ANDRING_M ändras inte
   - mittlinjen flyttas med den uppmätta förskjutningen (median per väg, om över MIN_FORSKJ_M, högst
     MAX_FORSKJ_M), avtrappad över AVTRAPP_M mot vägändarna så att korsningarna hänger ihop
3. Spelets vägyta (vagyta.Vagyta, samma kod som bygget) byggs två gånger per testplats: före och efter.
   Båda jämförs med fotots asfalt (vagform_orto.foto_yta) inom ±KANT_M från vägkanterna: IoU före/efter.
Ut (geodata/analys/ut/<karta>_korr/): <plats>.png (fotot; gul = dagens väg, grön = rättad), rattningar.csv
(alla föreslagna ändringar) och sammanfattning.txt.
--skriv: rättningarna till geodata/<karta>/vagrattningar.csv, som bygget läser (vagnat.forbered ->
tillampa_rattningar); ta bort filen för att bygga utan dem.
"""
import argparse
import copy
import csv

import numpy as np
import rasterio.features
import shapely
from shapely.geometry import Point, LineString
from shapely.ops import unary_union

import gemensamt as G
import vagbredd_orto as VB
import vagform_orto as VF

SMAL_M = 3.0
BREDD_FAKTOR = (0.5, 2.2)
MIN_BREDD_M = 2.5
MIN_ANDRING_M = 0.5
MIN_FORSKJ_M = 0.3
MAX_FORSKJ_M = 2.5
AVTRAPP_M = 15.0
KANT_M = 3.0


def kedjor(roads, ks):
    """Grupper av vägindex: samma namn och enkelriktning, ändar som möts (union-find)."""
    far = {k: k for k in ks}

    def rot(k):
        while far[k] != k:
            far[k] = far[far[k]]
            k = far[k]
        return k
    nyck = {}
    for k in ks:
        t = roads[k]['tags']
        namn = t.get('name') or t.get('ref')
        if not namn:
            continue
        enk = t.get('oneway') in ('yes', '1', '-1')
        L = roads[k]['line']
        for p in (L.coords[0], L.coords[-1]):
            nyck.setdefault((namn, enk, round(p[0]), round(p[1])), []).append(k)
    for lista in nyck.values():
        for k in lista[1:]:
            far[rot(k)] = rot(lista[0])
    grp = {}
    for k in ks:
        grp.setdefault(rot(k), []).append(k)
    return list(grp.values())


def rattningar(roads, res):
    """{k: dict(bredd_fore, bredd_efter, forsk)} för vägar som ändras."""
    ut = {}
    for grp in kedjor(roads, list(res)):
        saker = [(roads[k]['line'].length, res[k]) for k in grp if res[k].get('klass') == 'säker']
        if not saker:
            continue
        vikt = np.array([l for l, _ in saker])
        matt = []
        for _, s in saker:
            b = s['matt']
            if b < SMAL_M and np.isfinite(s.get('hard', np.inf)) and s['hard'] < SMAL_M * 2.5:
                b = max(b, s['hard'])
            matt.append(b)
        matt = np.array(matt)
        o = np.argsort(matt)
        med = float(matt[o][np.searchsorted(np.cumsum(vikt[o]) / vikt.sum(), 0.5)])
        for k in grp:
            fore = float(np.median(roads[k]['hw'])) * 2
            efter = float(np.clip(med, max(MIN_BREDD_M, fore * BREDD_FAKTOR[0]), fore * BREDD_FAKTOR[1]))
            forsk = res[k].get('forsk', 0.0) if res[k].get('klass') == 'säker' else 0.0
            forsk = float(np.clip(forsk, -MAX_FORSKJ_M, MAX_FORSKJ_M)) if abs(forsk) > MIN_FORSKJ_M else 0.0
            if abs(efter - fore) < MIN_ANDRING_M:
                efter = fore
            if efter != fore or forsk:
                ut[k] = dict(bredd_fore=fore, bredd_efter=efter, forsk=forsk)
    return ut


def tillampa(roads, ratt):
    """Kopia av roads med rättningarna, med samma funktion som bygget (vagnat.tillampa_rattningar)."""
    import vagnat
    ny = [dict(r) for r in roads]
    vagnat.tillampa_rattningar(ny, ratt, kontroll=False)
    for k in ratt:   # vagyta behöver s och pts var 2 m (som step3)
        L = ny[k]['line']
        n = max(2, int(L.length / 2) + 1)
        ny[k]['s'] = np.linspace(0, L.length, n)
        ny[k]['pts'] = np.array([L.interpolate(d).coords[0] for d in ny[k]['s']])
        ny[k]['z'] = np.zeros(n)
    return ny


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('karta')
    ap.add_argument('--ruta', default=None)
    ap.add_argument('--halv', type=float, default=60.0)
    ap.add_argument('--skriv', action='store_true',
                    help='skriv rättningarna till geodata/<karta>/vagrattningar.csv (bygget läser den)')
    a = ap.parse_args()
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    roads, BRO, _ = G.las_vagar(a.karta)
    orto, H, var = G.orto(a.karta), G.objekthojd(a.karta), G.orto_var(a.karta)
    res = {}
    for k, r in enumerate(roads):
        t = r['tags']
        if t['highway'] not in G.GATOR or r['surface'] != 'asfalt' or t.get('bridge') or t.get('tunnel') \
                or r['line'].length < 15:
            continue
        res[k] = VB.sammanfatta(VB.mat_vag(r, orto, hojd=H, var=var))
    ratt = rattningar(roads, res)
    efter_roads = tillampa(roads, ratt)
    ut = G.ut_mapp(a.karta, 'korr')
    for f in ut.glob('*.png'):
        f.unlink()
    with open(ut / 'rattningar.csv', 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['index', 'osm_namn', 'highway', 'oneway', 'langd_m', 'bredd_fore_m', 'bredd_efter_m',
                    'forskjutning_m', 'E', 'N'])
        for k, rt in ratt.items():
            r = roads[k]
            m = r['line'].interpolate(0.5, normalized=True)
            w.writerow([k, r['tags'].get('name', ''), r['tags']['highway'], r['tags'].get('oneway', ''),
                        round(r['line'].length), round(rt['bredd_fore'], 2), round(rt['bredd_efter'], 2),
                        round(rt['forsk'], 2), round(m.x), round(m.y)])
    if a.skriv:
        fil = G.ROOT / a.karta / 'vagrattningar.csv'
        with open(fil, 'w', newline='') as fh:
            w = csv.writer(fh)
            w.writerow(['index', 'E', 'N', 'bredd_fore_m', 'bredd_efter_m', 'forskjutning_m', 'osm_namn', 'highway'])
            for k, rt in sorted(ratt.items()):
                m = roads[k]['line'].interpolate(0.5, normalized=True)
                w.writerow([k, round(m.x, 2), round(m.y, 2), round(rt['bredd_fore'], 3), round(rt['bredd_efter'], 3),
                            round(rt['forsk'], 3), roads[k]['tags'].get('name', ''), roads[k]['tags']['highway']])
        print(f'skrev {fil} ({len(ratt)} vägar)')
    km = lambda ks: sum(roads[k]['line'].length for k in ks) / 1000
    bredare = [k for k, rt in ratt.items() if rt['bredd_efter'] > rt['bredd_fore']]
    smalare = [k for k, rt in ratt.items() if rt['bredd_efter'] < rt['bredd_fore']]
    flyttade = [k for k, rt in ratt.items() if rt['forsk']]
    rader = [f'Före/efter med uppmätta bredder och lägen, {a.karta}', '',
             f'mätta vägar {len(res)} ({km(res):.1f} km), säkra {sum(1 for s in res.values() if s["klass"] == "säker")}',
             f'rättade: {len(ratt)} vägar ({km(ratt):.1f} km): bredare {len(bredare)} ({km(bredare):.1f} km), '
             f'smalare {len(smalare)} ({km(smalare):.1f} km), mittlinjen flyttad {len(flyttade)} ({km(flyttade):.1f} km)',
             '', f'{"plats":30} {"IoU före":>9} {"IoU efter":>10}  (mot fotots asfalt inom ±{KANT_M:.0f} m från kanterna)']
    for namn, fon in G.platser(a.karta, a.ruta, a.halv):
        Vf, idx = G.vagyta_i(roads, BRO, a.karta, fon)
        Ve, idx_e = G.vagyta_i(efter_roads, BRO, a.karta, fon)
        fore = VF.model_yta(Vf, roads, idx).intersection(fon)
        efter = VF.model_yta(Ve, efter_roads, idx_e).intersection(fon)
        x0, y0, x1, y1 = fon.bounds
        sub, ext, T = orto.utsnitt(x0, y0, x1, y1)
        korridor = fore.union(efter).buffer(VF.KORRIDOR_M).intersection(fon)
        mitt = unary_union([roads[idx[k]]['line'].buffer(0.75) for k in Vf.bil_ytor
                            if roads[idx[k]]['surface'] == 'asfalt']).intersection(fon)
        foto, okand, _ = VF.foto_yta(sub, T, H, korridor, mitt, G.hus(a.karta, fon), orto.res)
        rad = f'{namn:30}'
        if foto is not None:
            okp = unary_union([shapely.geometry.shape(g) for g, v in
                               rasterio.features.shapes(okand.astype(np.uint8), mask=okand, transform=T) if v == 1]) \
                if okand.any() else shapely.Polygon()
            # bara kantzonen räknas: infarter och parkeringar längre ut påverkar inte jämförelsen
            zon = (fore.boundary.buffer(KANT_M).union(efter.boundary.buffer(KANT_M))).intersection(fon).difference(okp)
            iou = lambda m_: (m_.intersection(zon).intersection(foto.intersection(zon)).area /
                              max(m_.intersection(zon).union(foto.intersection(zon)).area, 1e-6))
            rad += f' {iou(fore):9.2f} {iou(efter):10.2f}'
        rader.append(rad)
        fig, ax = plt.subplots(figsize=(10, 10), dpi=100)
        ax.imshow(sub[:3].transpose(1, 2, 0), extent=ext)
        G.rita_poly(ax, fore, color='yellow', lw=1.6)
        G.rita_poly(ax, efter, color='#30ff60', lw=1.6, ls='--')
        andrade = [k for k in idx if k in ratt]
        for k in andrade:
            rt = ratt[k]
            m = efter_roads[k]['line'].interpolate(0.5, normalized=True)
            if fon.contains(m):
                txt = f'{rt["bredd_fore"]:.1f}→{rt["bredd_efter"]:.1f} m'
                if rt['forsk']:
                    txt += f', {rt["forsk"]:+.1f} m i sidled'
                ax.text(m.x, m.y, txt, color='white', fontsize=7, ha='center',
                        bbox=dict(facecolor='black', alpha=0.5, lw=0, pad=1))
        ax.set_xlim(x0, x1); ax.set_ylim(y0, y1); ax.set_xticks([]); ax.set_yticks([])
        ax.set_title(f'{namn}: gul = spelets väg i dag, grön streckad = med uppmätta bredder/lägen', fontsize=9)
        fig.tight_layout(); fig.savefig(ut / f'{namn}.png'); plt.close(fig)
    text = '\n'.join(rader)
    print(text)
    (ut / 'sammanfattning.txt').write_text(text + '\n')


if __name__ == '__main__':
    main()
