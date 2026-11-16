"""Vägmarkeringar ur ortofotot (analys; bygger inget, rör inte spelet).

  geodata/.venv/bin/python geodata/analys/vagmarkering_orto.py <karta> [--ruta E,N[,halv]] [--orto fil.tif]

Linjerna är 10-30 cm breda: i 0,5 m-fotot syns bara de grövsta (övergångsställenas block, spärrområden,
heldragna linjer i sol); med 16 cm-fotot (--orto, t.ex. hämtat med hamta_ortofoto.py --upplosning 0.16)
syns det mesta. Skriptet är byggt för båda.

För varje testplats: bilvägarnas yta som bygget ritar den (vagyta.Vagyta) + 1 m; vit färg = pixlar
MALAT_LJUSARE ljusare än vägens median, grå och inte gröna. Sammanhängande bitar klassas efter storlek,
form (minsta omskrivna rektangel) och riktning mot närmaste mittlinje:
  längs     långsmal, längs vägen (mitt-, kant-, körfältslinjer; streckade blir flera korta)
  tvärs     långsmal, tvärs vägen (stopplinjer, övergångsställenas block i 16 cm)
  block     kort och bred (övergångsställen i 0,5 m, pilar, väjningstrianglar)
  yta       stor och inte långsmal (spärrområden, målade refuger)
Ut (geodata/analys/ut/<karta>_markering/): <plats>.png (fotot; bitarna färgade efter klass) och
sammanfattning.txt (antal och meter per klass och plats).
"""
import argparse

import numpy as np
import rasterio.features
import shapely
from scipy import ndimage as ndi
from shapely.ops import unary_union

import gemensamt as G

MALAT_LJUSARE = 40.0
VIT_MIN = 165.0      # och minst så ljus (ny mörk asfalt får annars ljusgrå kantsten som 'vit')
MIN_PX = 2
FARG = {'längs': (0.95, 0.85, 0.1), 'tvärs': (0.95, 0.2, 0.2), 'block': (0.2, 0.8, 1.0), 'yta': (0.9, 0.3, 0.9)}


def klassa(del_, mittlinjer, res):
    """Klass för en bit (shapely-polygon i SWEREF)."""
    rekt = del_.minimum_rotated_rectangle
    if rekt.geom_type != 'Polygon':
        return 'block', 0.0
    c = np.array(rekt.exterior.coords)
    e1, e2 = c[1] - c[0], c[2] - c[1]
    l1, l2 = np.linalg.norm(e1), np.linalg.norm(e2)
    lang, kort = (e1, l1), (e2, l2)
    if l2 > l1:
        lang, kort = kort, lang
    langd, bredd = lang[1], max(kort[1], res)
    if del_.area > 12.0 and langd / bredd < 4:
        return 'yta', langd
    if langd / bredd < 2.5:
        return 'block', langd
    # riktning mot närmaste mittlinje
    p = del_.centroid
    L = min(mittlinjer, key=lambda l_: l_.distance(p))
    s = L.project(p)
    a_, b_ = np.array(L.interpolate(max(s - 1, 0)).coords[0]), np.array(L.interpolate(min(s + 1, L.length)).coords[0])
    d = (b_ - a_) / max(np.linalg.norm(b_ - a_), 1e-9)
    u = lang[0] / max(lang[1], 1e-9)
    return ('längs' if abs(float(np.dot(u, d))) > 0.7 else 'tvärs'), langd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('karta')
    ap.add_argument('--ruta', default=None)
    ap.add_argument('--orto', default=None)
    ap.add_argument('--halv', type=float, default=60.0)
    a = ap.parse_args()
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    roads, BRO, _ = G.las_vagar(a.karta)
    orto, H = G.orto(a.karta, a.orto), G.objekthojd(a.karta)
    ut = G.ut_mapp(a.karta, 'markering')
    rader = [f'Vägmarkeringar ur ortofotot ({orto.res:.2f} m/px), {a.karta}', '',
             f'{"plats":18} ' + ' '.join(f'{k:>12}' for k in FARG)]
    for namn, fon in G.platser(a.karta, a.ruta, a.halv):
        V, idx = G.vagyta_i(roads, BRO, a.karta, fon)
        bil = [k for k in V.bil_ytor if roads[idx[k]]['surface'] == 'asfalt']
        yta = unary_union([V.poly[k] for k in bil] + [p for p, _ in V.fyll]).buffer(1.0).intersection(fon)
        mitt = [roads[idx[k]]['line'] for k in bil]
        if yta.is_empty or not mitt:
            continue
        x0, y0, x1, y1 = fon.bounds
        sub, ext, T = orto.utsnitt(x0, y0, x1, y1)
        rgb = sub[:3].transpose(1, 2, 0).astype(float)
        nir = sub[3].astype(float)
        k = G.ytklasser(rgb, nir, G.h_pa_orto(H, T, nir.shape))
        vag = rasterio.features.rasterize([(yta, 1)], out_shape=nir.shape, transform=T).astype(bool)
        if (vag & k['hard']).sum() < 20:
            continue
        median = np.median(k['ljus'][vag & k['hard']])
        vit = vag & ~k['gron'] & ~k['skymt'] & (k['ljus'] > max(median + MALAT_LJUSARE, VIT_MIN)) \
            & (k['mattnad'] < 0.25)
        lab, n = ndi.label(vit, structure=np.ones((3, 3)))
        delar = {kl: [] for kl in FARG}
        for g, v in rasterio.features.shapes(lab.astype(np.int32), mask=vit, transform=T):
            p = shapely.geometry.shape(g)
            if p.area < MIN_PX * orto.res ** 2:
                continue
            kl, langd = klassa(p, mitt, orto.res)
            delar[kl].append((p, langd))
        rader.append(f'{namn:18} ' + ' '.join(f'{len(delar[kl]):4} {sum(l for _, l in delar[kl]):5.0f} m'
                                              for kl in FARG))
        fig, ax = plt.subplots(1, 2, figsize=(16, 8), dpi=100)
        ax[0].imshow(sub[:3].transpose(1, 2, 0), extent=ext)
        ax[0].set_title(f'{namn}: fotot ({orto.res:.2f} m/px)', fontsize=9)
        ax[1].imshow((sub[:3].transpose(1, 2, 0) * 0.35).astype(np.uint8), extent=ext)
        G.rita_poly(ax[1], yta, color='#808080', lw=0.6)
        for kl, lista in delar.items():
            for p, _ in lista:
                for q in getattr(p, 'geoms', [p]):
                    ax[1].fill(*q.exterior.xy, color=FARG[kl], lw=0)
        ax[1].set_title('längs (gul), tvärs (röd), block (cyan), yta (lila); grå = vägytan', fontsize=9)
        for x in ax:
            x.set_xlim(x0, x1); x.set_ylim(y0, y1); x.set_xticks([]); x.set_yticks([])
        fig.tight_layout(); fig.savefig(ut / f'{namn}.png'); plt.close(fig)
    rader += ['', '(antal bitar och sammanlagd längd per klass)']
    text = '\n'.join(rader)
    print(text)
    (ut / 'sammanfattning.txt').write_text(text + '\n')


if __name__ == '__main__':
    main()
