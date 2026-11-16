"""Vägens verkliga form ur ortofotot mot vägytan bygget ger (analys; bygger inget, rör inte spelet).

  geodata/.venv/bin/python geodata/analys/vagform_orto.py <karta> [--ruta E,N[,halv]] [--orto fil.tif]

För varje testplats (gemensamt.PLATSER, eller --ruta): bilvägarnas yta som step3 bygger den
(vagyta.Vagyta: buffrade mittlinjer, korsningsrundningar, fyllda mittremsor, bussfickor) jämförs med
den hårdgjorda ytan i ortofotot inom en korridor (KORRIDOR_M utanför modellens kant):
  1. pixelklasser (gemensamt.ytklasser): hårdgjort = grått, inte grönt, inte skugga, inte skymt (laser)
  2. asfalt = hårdgjort med ungefär vägens färg (median längs mittlinjerna, FARG_MAX)
  3. stängning + öppning (MORF_M), bara bitar som når en mittlinje, utan hus
  4. polygon (rasterio.features.shapes), förenklad
Mått per plats: IoU (överlapp / union inom korridoren, skymt/skugga borträknat), m² som bara finns i
fotot (vägen är bredare / en ficka saknas) och bara i modellen (för bred / rundning som inte finns).
Ut (geodata/analys/ut/<karta>_form/): <plats>.png (vänster: fotot med modellens kant gul och fotots
röd; höger: grön = båda, röd = bara fotot, blå = bara modellen, grå = okänt) och sammanfattning.txt.
"""
import argparse

import numpy as np
import rasterio.features
import shapely
import shapely.ops
from scipy import ndimage as ndi
from shapely.ops import unary_union

import gemensamt as G

KORRIDOR_M = 6.0
FARG_MAX = 38.0
MORF_M = 1.0           # stängning/öppning (m; i pixlar efter fotots upplösning)
MALAT_LJUSARE = 45.0   # vit färg (linjer, spärrområden): så mycket ljusare än asfalten
KANT_M = 2.0           # 'bara fotot' inom så här långt från modellens kant: bredden; längre ut: utbyggnader


def model_yta(V, roads, idx):
    """Bilvägarnas yta (vägar + fyllningar) som bygget ritar den."""
    bil = [V.poly[k] for k in V.bil_ytor if roads[idx[k]]['surface'] == 'asfalt']
    fyll = [p for p, _ in V.fyll]
    return unary_union(bil + fyll)


def foto_yta(sub, T, H, korridor, mitt, hus, res=0.5):
    """(asfaltsyta som polygon, okänd-mask, transform-form) ur ortofotots utsnitt."""
    rgb = sub[:3].transpose(1, 2, 0).astype(float)
    nir = sub[3].astype(float)
    h = G.h_pa_orto(H, T, nir.shape)
    k = G.ytklasser(rgb, nir, h)
    form = nir.shape
    kor = rasterio.features.rasterize([(korridor, 1)], out_shape=form, transform=T).astype(bool)
    mm = rasterio.features.rasterize([(mitt, 1)], out_shape=form, transform=T).astype(bool)
    husm = rasterio.features.rasterize([(g, 1) for g in hus], out_shape=form, transform=T).astype(bool) \
        if hus else np.zeros(form, bool)
    ref_px = mm & k['hard']
    if ref_px.sum() < 10:
        return None, None, None
    ref = np.median(rgb[ref_px], axis=0)
    farg = np.linalg.norm(rgb - ref, axis=-1) < FARG_MAX
    malat = ~k['gron'] & ~k['skymt'] & (k['ljus'] > ref.mean() + MALAT_LJUSARE) & (k['mattnad'] < G.MATTNAD_HARD)
    asf = ((k['hard'] & farg) | malat) & kor & ~husm   # vägmarkeringar är också väg
    okand = (k['skymt'] | k['skugga']) & kor & ~asf
    # stäng små hål (markeringar, brunnar) och ta bort brus; okänt får fylla hål inne i asfalten
    px = max(1, int(round(MORF_M / res)))
    a2 = ndi.binary_closing(asf | okand, iterations=px) & (asf | ndi.binary_dilation(asf, iterations=px))
    a2 = ndi.binary_opening(a2, iterations=px) & kor & ~husm
    lab, n = ndi.label(a2)
    behall = np.unique(lab[mm & a2])
    a2 = np.isin(lab, behall[behall > 0])
    polys = [shapely.geometry.shape(g) for g, v in rasterio.features.shapes(a2.astype(np.uint8), mask=a2, transform=T)
             if v == 1]
    y = unary_union(polys).simplify(0.3) if polys else shapely.Polygon()
    return y, okand, k


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
    ut = G.ut_mapp(a.karta, 'form')
    rader = [f'Vägens form ur ortofotot, {a.karta}', '',
             f'{"plats":18} {"IoU":>5} {"foto: kant":>10} {"utbyggn.":>10} {"bara modell m²":>15} {"okänt m²":>9}',
             f'  (foto: kant = bara i fotot inom {KANT_M:.0f} m från modellens kant, dvs. vägen är bredare;',
             '   utbyggn. = längre ut: infarter, parkeringar, torg)']
    for namn, fon in G.platser(a.karta, a.ruta, a.halv):
        V, idx = G.vagyta_i(roads, BRO, a.karta, fon)
        modell = model_yta(V, roads, idx).intersection(fon)
        korridor = modell.buffer(KORRIDOR_M).intersection(fon)
        mitt = unary_union([roads[idx[k]]['line'].buffer(0.75) for k in V.bil_ytor
                            if roads[idx[k]]['surface'] == 'asfalt']).intersection(fon)
        # under brodäck ser fotot däcket, inte vägen: okänt
        dack = unary_union([shapely.ops.substring(roads[k]['line'], s0, s1).buffer(float(np.max(roads[k]['hw'])) + 1.0,
                                                                                    cap_style='flat')
                            for k in range(len(roads)) for s0, s1 in BRO.spann.get(k, [])
                            if roads[k]['line'].intersects(fon)]) if BRO is not None else shapely.Polygon()
        x0, y0, x1, y1 = fon.bounds
        sub, ext, T = orto.utsnitt(x0, y0, x1, y1)
        foto, okand, k = foto_yta(sub, T, H, korridor, mitt, G.hus(a.karta, fon), orto.res)
        if foto is None:
            rader.append(f'{namn:18} (ingen referensfärg)')
            continue
        # okänt (skymt/skugga) räknas inte
        okand_poly = unary_union([shapely.geometry.shape(g) for g, v in
                                  rasterio.features.shapes(okand.astype(np.uint8), mask=okand, transform=T) if v == 1]) \
            if okand.any() else shapely.Polygon()
        okand_poly = okand_poly.union(dack.intersection(fon))
        okand = okand | (rasterio.features.rasterize([(dack, 1)], out_shape=okand.shape, transform=T).astype(bool)
                         if not dack.is_empty else False)
        jmf = korridor.difference(okand_poly)
        m_, f_ = modell.intersection(jmf), foto.intersection(jmf)
        iou = m_.intersection(f_).area / max(m_.union(f_).area, 1e-6)
        bara_f_geom = f_.difference(m_)
        kant_f = bara_f_geom.intersection(m_.buffer(KANT_M)).area
        utb_f = bara_f_geom.area - kant_f
        bara_m = m_.difference(f_).area
        rader.append(f'{namn:18} {iou:5.2f} {kant_f:10.0f} {utb_f:10.0f} {bara_m:15.0f} {okand_poly.area:9.0f}')
        bara_f = bara_f_geom.area
        fig, ax = plt.subplots(1, 2, figsize=(16, 8), dpi=100)
        bild = sub[:3].transpose(1, 2, 0)
        ax[0].imshow(bild, extent=ext)
        G.rita_poly(ax[0], modell, color='yellow', lw=1.0)
        G.rita_poly(ax[0], foto, color='red', lw=1.0)
        ax[0].set_title(f'{namn}: modell (gul), fotots asfalt (röd)', fontsize=9)
        diff = np.zeros(bild.shape[:2] + (3,), float) + 0.12
        fr = rasterio.features.rasterize
        mm = fr([(m_, 1)], out_shape=bild.shape[:2], transform=T).astype(bool) if not m_.is_empty else np.zeros(bild.shape[:2], bool)
        ff = fr([(f_, 1)], out_shape=bild.shape[:2], transform=T).astype(bool) if not f_.is_empty else np.zeros(bild.shape[:2], bool)
        diff[mm & ff] = (0.2, 0.7, 0.3)
        diff[ff & ~mm] = (0.9, 0.2, 0.2)
        diff[mm & ~ff] = (0.25, 0.45, 0.95)
        diff[okand] = (0.45, 0.45, 0.45)
        ax[1].imshow(diff, extent=ext)
        ax[1].set_title(f'IoU {iou:.2f}: grön båda, röd bara fotot ({bara_f:.0f} m²), blå bara modellen '
                        f'({bara_m:.0f} m²), grå okänt', fontsize=9)
        for x in ax:
            x.set_xlim(x0, x1); x.set_ylim(y0, y1); x.set_xticks([]); x.set_yticks([])
        fig.tight_layout(); fig.savefig(ut / f'{namn}.png'); plt.close(fig)
    text = '\n'.join(rader)
    print(text)
    (ut / 'sammanfattning.txt').write_text(text + '\n')


if __name__ == '__main__':
    main()
