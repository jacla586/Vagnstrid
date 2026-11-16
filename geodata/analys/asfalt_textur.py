"""Asfaltens verkliga variation ur ortofotot som detaljkarta (analys; bygger inget, rör inte spelet).

  geodata/.venv/bin/python geodata/analys/asfalt_textur.py <karta> [--ruta E,N[,halv]] [--orto fil.tif]

Idén: spelets asfaltsshader (RoadLook) har bara brus. Med en gråskalekarta över vägytorna ur fotot får
den de verkliga lagningarna, spåren, fläckarna och brunnarna, med shaderns brus för det fina ovanpå.
För varje testplats:
  1. vägytan som bygget ritar den (vagyta.Vagyta: bilvägar, fyllningar, GC-vägar, trottoarer)
  2. fotots ljushet; vägmarkeringar (vitt), skymt (laser), skugga och grönt fylls med omgivningens median
  3. detalj = ljushet / lokal medel (gauss, UTJAMNA_M) inom vägen: 1 = vägens egen ton, < 1 mörkare
     (nyare lagning, fukt, olja), > 1 ljusare (sliten, dammig)
  4. förhandsvisning: asfaltens grundfärg × detalj (klippt till DETALJ_MIN..MAX), så som shadern skulle
     läsa den
Ut (geodata/analys/ut/<karta>_textur/): <plats>.png (fotot | detaljkartan | förhandsvisning) och
sammanfattning.txt med kartans storlek för hela kartan (vägarnas yta, bara rutor med väg).
"""
import argparse

import numpy as np
import rasterio.features
from scipy import ndimage as ndi
from shapely.ops import unary_union

import gemensamt as G

UTJAMNA_M = 4.0
DETALJ_MIN, DETALJ_MAX = 0.6, 1.4
GRUND = np.array([62, 62, 64], float) / 255.0   # Vag_asfalt (step3 ROADMAT)
RUTA_PX = 256                                      # kartan sparas i rutor; bara rutor med väg


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
    roads, BRO, ruta = G.las_vagar(a.karta)
    orto, H = G.orto(a.karta, a.orto), G.objekthojd(a.karta)
    ut = G.ut_mapp(a.karta, 'textur')
    rader = [f'Asfaltens detaljkarta ur ortofotot ({orto.res:.2f} m/px), {a.karta}', '',
             f'{"plats":18} {"väg m²":>8} {"fyllt %":>8} {"detalj p5..p95":>16}']
    for namn, fon in G.platser(a.karta, a.ruta, a.halv):
        V, idx = G.vagyta_i(roads, BRO, a.karta, fon)
        delar = [V.poly[k] for k in V.poly] + [p for p, _ in V.fyll]
        if V.trottoar is not None:
            delar.append(V.trottoar)
        yta = unary_union(delar).intersection(fon)
        if yta.is_empty:
            continue
        x0, y0, x1, y1 = fon.bounds
        sub, ext, T = orto.utsnitt(x0, y0, x1, y1)
        rgb = sub[:3].transpose(1, 2, 0).astype(float)
        nir = sub[3].astype(float)
        k = G.ytklasser(rgb, nir, G.h_pa_orto(H, T, nir.shape))
        vag = rasterio.features.rasterize([(yta, 1)], out_shape=nir.shape, transform=T).astype(bool)
        lj = k['ljus']
        med = np.median(lj[vag & k['hard']]) if (vag & k['hard']).any() else np.median(lj[vag])
        dalig = vag & (k['skymt'] | k['gron'] | k['skugga'] | (lj > med + 40))   # bilar/träd, gräs, skugga, vit färg
        bra = vag & ~dalig
        # fyll dåliga pixlar med medianen av bra grannar (växande fönster)
        L = lj.copy()
        kvar = dalig.copy()
        for r_ in (2, 4, 8, 16):
            if not kvar.any():
                break
            num = ndi.uniform_filter(np.where(bra, L, 0.0), 2 * r_ + 1)
            den = ndi.uniform_filter(bra.astype(float), 2 * r_ + 1)
            ny = kvar & (den > 0.05)
            L[ny] = (num / np.maximum(den, 1e-6))[ny]
            bra = bra | ny
            kvar &= ~ny
        sig = UTJAMNA_M / orto.res
        num = ndi.gaussian_filter(np.where(vag, L, 0.0), sig)
        den = ndi.gaussian_filter(vag.astype(float), sig)
        lokal = num / np.maximum(den, 1e-6)
        detalj = np.where(vag, np.clip(L / np.maximum(lokal, 1.0), DETALJ_MIN, DETALJ_MAX), 1.0)
        p5, p95 = np.percentile(detalj[vag], [5, 95])
        rader.append(f'{namn:18} {vag.sum() * orto.res ** 2:8.0f} {100 * dalig.sum() / max(vag.sum(), 1):8.1f} '
                     f'{p5:7.2f}..{p95:5.2f}')
        prev = np.where(vag[..., None], np.clip(GRUND[None, None, :] * detalj[..., None] * 1.6, 0, 1),
                        rgb / 255.0 * 0.5)
        fig, ax = plt.subplots(1, 3, figsize=(21, 7.4), dpi=90)
        ax[0].imshow(sub[:3].transpose(1, 2, 0), extent=ext)
        ax[0].set_title(f'{namn}: fotot', fontsize=9)
        im = ax[1].imshow(np.where(vag, detalj, np.nan), extent=ext, cmap='gray', vmin=0.75, vmax=1.25)
        ax[1].set_title('detaljkartan (vägens ljushet / lokalt medel; vitt, bilar, träd ifyllda)', fontsize=9)
        fig.colorbar(im, ax=ax[1], fraction=0.04)
        ax[2].imshow(prev, extent=ext)
        ax[2].set_title('förhandsvisning: asfaltens grundfärg × detalj (utan shaderns brus)', fontsize=9)
        for x in ax:
            x.set_xlim(x0, x1); x.set_ylim(y0, y1); x.set_xticks([]); x.set_yticks([])
        fig.tight_layout(); fig.savefig(ut / f'{namn}.png'); plt.close(fig)
    # storlek för hela kartan: vägytan (buffrade linjer) i rutor om RUTA_PX
    yt = unary_union([r['line'].buffer(float(np.max(r['hw'])) + 2.0) for r in roads
                      if r['tags']['highway'] not in ('track',)])
    W = int((ruta[2] - ruta[0]) / orto.res); Hh = int((ruta[3] - ruta[1]) / orto.res)
    T_hel = rasterio.transform.from_origin(ruta[0], ruta[3], orto.res, orto.res)
    mask = rasterio.features.rasterize([(yt, 1)], out_shape=(Hh, W), transform=T_hel).astype(bool)
    rutor = mask[:Hh // RUTA_PX * RUTA_PX, :W // RUTA_PX * RUTA_PX].reshape(Hh // RUTA_PX, RUTA_PX, W // RUTA_PX, RUTA_PX)
    n_rutor = int(rutor.any(axis=(1, 3)).sum())
    mb = n_rutor * RUTA_PX * RUTA_PX / 1e6
    rader += ['', f'Hela kartan: vägytan {mask.sum() * orto.res ** 2 / 1e6:.2f} km², {n_rutor} rutor à {RUTA_PX}² px med väg '
              f'= {mb:.0f} MB okomprimerat (1 byte/px), hela kartan som en bild {W * Hh / 1e6:.0f} MB.',
              f'({orto.res:.2f} m/px; vid 0,5 m ~{(orto.res / 0.5) ** 2 * 100:.0f} % av detta, vid 0,25 m '
              f'~{(orto.res / 0.25) ** 2 * 100:.0f} %)']
    text = '\n'.join(rader)
    print(text)
    (ut / 'sammanfattning.txt').write_text(text + '\n')


if __name__ == '__main__':
    main()
