#!/usr/bin/env python3
"""
Hittar häckar som raka linjer i kvarterets rutnät: <projekt>/work/hackar.pkl (segment).

    .venv/bin/python -I scripts/hackar.py <projekt>

Häckar står i rutmönster längs tomtkanterna, så de söks som raka linjer i kvarterets riktning, inte som former:
1. Rutnätet: per RUTA_M-ruta (överlapp) den dominerande riktningen (mod 90°) ur OSM-husens kanter och gatorna.
   Rutor nästan utan hus får inga häckar (åkerkanter: OSM-häckar och skogsbryn).
2. Häckpixlar ur lasern (objekthöjd, 1 m): HOJD_M höga, inte nära något högre än HOG_M (träd, hus), inte på hus,
   väg, vatten, skog, våtmark eller buskmark. Lasern är gles (1–2 punkter/m²) och randig, därför:
3. Per ruta och axel projiceras pixlarna på band (BAND_M brett, STEG_M isär) längs axeln; sträckor där minst
   TATHET av en FONSTER_M lång bit har träffar blir häckbitar. Bitar på samma linje slås ihop över luckor upp till
   LUCKA_M om luckan inte korsar hus, väg eller en större yta utan grönska i fotot (tak, uppfart).
4. Kontroll per segment: grönt i flygfotot (NDVI), jämn höjd; där lasern visar något mycket högre (träd, stor buske)
   bryts häcken. Sist slås dubbletter ihop och ändar förlängs till vinkelräta grannar (hörn).
Utdata: segment [E0, N0, E1, N1, höjd m] som step4_trees.py lägger ut som rader av små buskar.
Förhandsbilder: forhandsbilder/hackar_<projekt>.png (hela kartan) och hackar_<projekt>_<plats>.png (referenser).
Kör efter step3 (marktäcket) och före step4. Kräver data/ortofoto_<projekt>.tif (hamta_ortofoto.py).
"""
import argparse, json, math, pickle
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.features import rasterize
from rasterio.windows import from_bounds
from scipy import ndimage as ndi
from PIL import Image, ImageDraw

GEO = Path(__file__).resolve().parent.parent
R = 1.0                 # m per pixel (laserns upplösning)
HOJD_M = (0.5, 2.8)     # häckpixlar
HOG_M = 4.0             # träd och hus ...
HOG_MARGINAL_PX = 1     # ... och en pixel runt dem
RUTA_M, RUTA_STEG_M = 80.0, 60.0
MIN_HUSKANT_M = 40.0    # mindre huskant än så i rutan (+ 40 m runt): inget kvarter
BAND_M, STEG_M = 1.0, 0.5
FONSTER_M, TATHET = 4.0, 0.5
LUCKA_M = 6.0
MIN_LANGD_M = 5.0
NDVI_MIN = 0.2
HOGRE_M = 1.2           # mer än så över häckens median = träd eller stor buske: häcken bryts
SPRIDNING_M = 1.4       # p90 - p10 av häckens höjd större än så: ingen häck
MIN_TRAFF_BIT = 3       # en bit före ihopslagning: minst så många träffar ...
MIN_BIT_M = 3.0         # ... och så lång
MIN_TACKNING = 0.35     # andel av segmentet med träffar på linjen
SIDA_M, SIDA_ANDEL = 2.0, 0.4   # smalt band: på minst en sida (SIDA_M ut) högst SIDA_ANDEL av linjens träffar
DUBBLETT_M = 3.0        # parallella häcklinjer närmare än så är samma häck
BAND_GRANNE_M = 1.5     # band närmare än så tävlar om samma linje
ICKE_GRONT_NDVI = 0.08  # större ytor utan grönska (tak, uppfarter, uteplatser) bryter en häck
HORN_M = 2.5
EJ_KLASSER = ['skog', 'våtmark', 'buskmark', 'hav', 'sjö', 'väg_asfalt', 'väg_grus']
VAG_KLASSER = ['väg_asfalt', 'väg_grus']
# Referensplatser för förhandsbilderna (SWEREF 99 TM, per projekt)
PLATSER = {"vidingsjo": {"attinggatan20": (537455, 6471168), "ortgatan29": (537397, 6471141),
                         "spanngatan": (537586, 6471320)}}


def dominant_riktning(byggnader, vagar):
    """Riktning (rad, 0..pi/2) som kanterna oftast följer, mod 90°, viktad efter längd; None om för lite hus."""
    vinklar, vikter = [], []
    for g in byggnader:
        for poly in getattr(g, 'geoms', [g]):
            c = np.asarray(poly.exterior.coords)
            d = np.diff(c, axis=0)
            vinklar.append(np.arctan2(d[:, 1], d[:, 0]))
            vikter.append(np.hypot(d[:, 0], d[:, 1]))
    if not vikter or np.concatenate(vikter).sum() < MIN_HUSKANT_M:
        return None
    for g in vagar:
        c = np.asarray(g.coords)
        d = np.diff(c, axis=0)
        vinklar.append(np.arctan2(d[:, 1], d[:, 0]))
        vikter.append(0.5 * np.hypot(d[:, 0], d[:, 1]))
    v = np.mod(np.concatenate(vinklar), np.pi / 2)
    w = np.concatenate(vikter)
    hist, _ = np.histogram(v, bins=90, range=(0, np.pi / 2), weights=w)
    hist = ndi.uniform_filter1d(hist, 5, mode='wrap')
    return (np.argmax(hist) + 0.5) * (np.pi / 2) / 90


def korningar(occ):
    """Sträckor (start, slut) där ett glidande FONSTER_M-fönster har minst TATHET träffar."""
    f = max(int(round(FONSTER_M / R)), 1)
    tat = ndi.uniform_filter1d(occ.astype(np.float32), f, mode='constant')
    bra = tat >= TATHET
    # varje bra fönster täcker sina f celler, men sträckan börjar och slutar på en träff
    tack = ndi.binary_dilation(bra, np.ones(f, bool)) & ndi.binary_dilation(occ, np.ones(3, bool))
    lab, n = ndi.label(tack)
    return [(s[0].start, s[0].stop) for s in ndi.find_objects(lab)] if n else []


class Karta:
    """Rasterlager på 1 m och provtagning i världskoordinater."""

    def __init__(self, ruta, lager):
        self.ruta = ruta
        self.__dict__.update(lager)

    def ij(self, E, N):
        j = np.clip(((np.asarray(E) - self.ruta[0]) / R).astype(int), 0, self.W - 1)
        i = np.clip(((self.ruta[3] - np.asarray(N)) / R).astype(int), 0, self.H - 1)
        return i, j


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("projekt")
    a = ap.parse_args()
    p = GEO / a.projekt
    work, out = p / "work", p / "out"
    g = json.loads((work / "grid.json").read_text())
    RES, X0, Y1, GW, GH = g["RES"], g["x0"], g["y1"], g["W"], g["H"]
    ruta = (X0, Y1 - GH * RES, X0 + GW * RES, Y1)
    H, W = int(round(GH * RES / R)), int(round(GW * RES / R))

    with rasterio.open(p / "data" / f"objekthojd_{a.projekt}.tif") as d:
        h = d.read(1, window=from_bounds(*ruta, d.transform), out_shape=(H, W),
                   resampling=Resampling.nearest, boundless=True) / 10.0
    with rasterio.open(p / "data" / f"ortofoto_{a.projekt}.tif") as d:
        o = d.read([1, 2, 3, 4], window=from_bounds(*ruta, d.transform), out_shape=(4, H, W),
                   resampling=Resampling.average, boundless=True).astype(np.float32)
    ndvi = (o[3] - o[0]) / np.maximum(o[3] + o[0], 1.0)
    lc = np.array(Image.open(out / "landcover_index.png"))
    klasser = {v: int(k) for k, v in json.loads((out / "heightmap_info.json").read_text())["landcover_classes"].items()}
    f = int(round(RES / R))
    upp = lambda m: np.repeat(np.repeat(m, f, 0), f, 1)[:H, :W]
    ej = upp(np.isin(lc, [klasser[k] for k in EJ_KLASSER if k in klasser]))
    vag = upp(np.isin(lc, [klasser[k] for k in VAG_KLASSER if k in klasser]))
    feat = pickle.load(open(work / "features.pkl", "rb"))
    T = rasterio.transform.from_origin(ruta[0], ruta[3], R, R)
    hus_geo = [gm for gm, _ in feat["buildings"]]
    hus = rasterize(((gm, 1) for gm in hus_geo), out_shape=(H, W), transform=T).astype(bool) if hus_geo else \
        np.zeros((H, W), bool)
    tak = ndi.binary_opening((h > 2.5) & (ndvi < 0.15), np.ones((2, 2), bool))   # hus som inte finns i OSM
    icke_gront = ndi.binary_opening(ndvi < ICKE_GRONT_NDVI, np.ones((3, 3), bool))
    stopp = hus | tak | vag | icke_gront
    hack_px = (h >= HOJD_M[0]) & (h <= HOJD_M[1]) & ~ej & ~hus
    hack_px &= ~ndi.binary_dilation(h > HOG_M, iterations=HOG_MARGINAL_PX)
    K = Karta(ruta, dict(H=H, W=W, h=h, ndvi=ndvi, stopp=stopp))

    from shapely import STRtree
    from shapely.geometry import box
    hus_trad = STRtree(hus_geo) if hus_geo else None
    vag_geo = [gm for gm, t in feat["roads"] if gm.geom_type == "LineString"]
    vag_trad = STRtree(vag_geo) if vag_geo else None

    ii, jj = np.nonzero(hack_px)
    PE = ruta[0] + (jj + 0.5) * R
    PN = ruta[3] - (ii + 0.5) * R
    segment = []   # [E0, N0, E1, N1]
    kant = (RUTA_M - RUTA_STEG_M) / 2
    for e0 in np.arange(ruta[0], ruta[2], RUTA_STEG_M):
        for n0 in np.arange(ruta[1], ruta[3], RUTA_STEG_M):
            kb = (e0, n0, e0 + RUTA_STEG_M, n0 + RUTA_STEG_M)              # kärnan
            yb = (e0 - kant, n0 - kant, e0 + RUTA_STEG_M + kant, n0 + RUTA_STEG_M + kant)
            stor = box(yb[0] - 40, yb[1] - 40, yb[2] + 40, yb[3] + 40)
            hb = [hus_geo[k] for k in hus_trad.query(stor)] if hus_trad else []
            vb = []
            for k in (vag_trad.query(stor) if vag_trad else []):
                v_ = vag_geo[k].intersection(stor)
                if not v_.is_empty and v_.geom_type == "LineString":
                    vb.append(v_)
            theta = dominant_riktning(hb, vb)
            if theta is None:
                continue
            sel = (PE >= yb[0]) & (PE < yb[2]) & (PN >= yb[1]) & (PN < yb[3])
            if sel.sum() < 5:
                continue
            for phi in (theta, theta + np.pi / 2):
                c, s = math.cos(phi), math.sin(phi)
                u = PE[sel] * c + PN[sel] * s
                v = -PE[sel] * s + PN[sel] * c
                u0 = u.min()
                nu = int((u.max() - u0) / R) + 2
                kand = []
                for vk in np.arange(v.min(), v.max() + STEG_M, STEG_M):
                    i_band = np.abs(v - vk) <= BAND_M / 2
                    if i_band.sum() < 3:
                        continue
                    occ = np.zeros(nu, bool)
                    occ[((u[i_band] - u0) / R).astype(int)] = True
                    for a_, b_ in korningar(occ):
                        if occ[a_:b_].sum() < MIN_TRAFF_BIT or (b_ - a_) * R < MIN_BIT_M:
                            continue
                        kand.append([vk, u0 + a_ * R, u0 + b_ * R, int(occ[a_:b_].sum())])
                # bästa bandet per linje: flest träffar vinner mot överlappande grannar inom DUBBLETT_M
                kand.sort(key=lambda t: -t[3])
                valda = []
                for k_ in kand:
                    if any(abs(k_[0] - q[0]) < BAND_GRANNE_M and min(k_[2], q[2]) - max(k_[1], q[1]) > 0 for q in valda):
                        continue
                    valda.append(k_)
                # interpolation: bitar på (nästan) samma linje över luckor utan hus, väg eller uppfart
                valda.sort(key=lambda t: t[1])
                anvand = [False] * len(valda)
                for x in range(len(valda)):
                    if anvand[x]:
                        continue
                    vk, ua, ub, _ = valda[x]
                    anvand[x] = True
                    for y in range(x + 1, len(valda)):
                        if anvand[y] or abs(valda[y][0] - vk) > 1.0:
                            continue
                        lucka = valda[y][1] - ub
                        if lucka > LUCKA_M:
                            continue
                        vm = (vk + valda[y][0]) / 2
                        us = np.arange(ub, valda[y][1], 0.5)
                        i_, j_ = K.ij(us * c - vm * s, us * s + vm * c)
                        if lucka <= 0 or not K.stopp[i_, j_].any():
                            ub = max(ub, valda[y][2])
                            vk = vm
                            anvand[y] = True
                    um = (ua + ub) / 2
                    Em, Nm = um * c - vk * s, um * s + vk * c
                    if kb[0] <= Em < kb[2] and kb[1] <= Nm < kb[3]:
                        segment.append([ua * c - vk * s, ua * s + vk * c, ub * c - vk * s, ub * s + vk * c])
    print(f"råa häcklinjer: {len(segment)}")

    # Kontroll per segment: grönt, jämn höjd, bryts vid träd/stora buskar, hus och väg
    slutliga = []
    for E0, N0, E1, N1 in segment:
        L = math.hypot(E1 - E0, N1 - N0)
        if L < MIN_LANGD_M:
            continue
        t = np.arange(0, L + 0.25, 0.5) / L
        E, N = E0 + t * (E1 - E0), N0 + t * (N1 - N0)
        nx, ny = -(N1 - N0) / L, (E1 - E0) / L
        hs = np.stack([K.h[K.ij(E + o_ * nx, N + o_ * ny)] for o_ in (-1.0, -0.5, 0.0, 0.5, 1.0)])
        traff = hs[(hs >= HOJD_M[0]) & (hs <= HOJD_M[1])]
        if traff.size < 4:
            continue
        hm = float(np.median(traff))
        px = lambda o_: np.stack([hack_px[K.ij(E + (o_ + d_) * nx, N + (o_ + d_) * ny)] for d_ in (-0.5, 0.0, 0.5)]).any(0)
        mitt_t = px(0.0).mean()
        if mitt_t < MIN_TACKNING or min(px(-SIDA_M).mean(), px(SIDA_M).mean()) > SIDA_ANDEL * mitt_t:
            continue
        if np.percentile(traff, 90) - np.percentile(traff, 10) > SPRIDNING_M:
            continue
        ndv = np.stack([K.ndvi[K.ij(E + o_ * nx, N + o_ * ny)] for o_ in (-0.5, 0.0, 0.5)]).max(0)
        if ndv.mean() < NDVI_MIN:
            continue
        hogt = (hs[1:4].max(0) > max(hm + HOGRE_M, HOJD_M[1] + 0.2)) | K.stopp[K.ij(E, N)]
        lab, n = ndi.label(~hogt)
        for sl in ndi.find_objects(lab):
            a_, b_ = sl[0].start, sl[0].stop - 1
            if (b_ - a_) * 0.5 >= MIN_LANGD_M:
                slutliga.append([E[a_], N[a_], E[b_], N[b_], hm])
    seg = np.array(slutliga, np.float64).reshape(-1, 5)

    # Dubbletter (överlappande rutor): parallella inom DUBBLETT_M som överlappar, den längre vinner
    langd = np.hypot(seg[:, 2] - seg[:, 0], seg[:, 3] - seg[:, 1])
    from scipy.spatial import cKDTree
    mitt = np.c_[(seg[:, 0] + seg[:, 2]) / 2, (seg[:, 1] + seg[:, 3]) / 2]
    trad = cKDTree(mitt) if len(seg) else None
    behall, tagen = [], np.zeros(len(seg), bool)
    for k in np.argsort(-langd):
        if tagen[k]:
            continue
        behall.append(k)
        E0, N0, E1, N1, _ = seg[k]
        dk = np.array([E1 - E0, N1 - N0]) / langd[k]
        for q in trad.query_ball_point(mitt[k], langd[k] / 2 + 30):
            if q == k or tagen[q]:
                continue
            dq = np.array([seg[q, 2] - seg[q, 0], seg[q, 3] - seg[q, 1]]) / langd[q]
            if abs(dk @ dq) < math.cos(math.radians(10)):
                continue
            rel = mitt[q] - (E0, N0)
            sid = abs(rel[0] * -dk[1] + rel[1] * dk[0])
            lang = rel @ dk
            if sid < DUBBLETT_M and -langd[q] / 2 < lang < langd[k] + langd[q] / 2:
                tagen[q] = True
    seg = seg[sorted(behall)]

    # Hörn: en ände nära ett vinkelrätt segment förlängs fram till det (högst HORN_M)
    if len(seg):
        mitt = np.c_[(seg[:, 0] + seg[:, 2]) / 2, (seg[:, 1] + seg[:, 3]) / 2]
        langd = np.hypot(seg[:, 2] - seg[:, 0], seg[:, 3] - seg[:, 1])
        trad = cKDTree(mitt)
        for k in range(len(seg)):
            for ande in (0, 1):
                P = seg[k, 2 * ande:2 * ande + 2].copy()
                Q = seg[k, 2 - 2 * ande:4 - 2 * ande]
                d = (P - Q) / np.linalg.norm(P - Q)
                for q in trad.query_ball_point(P, langd.max() / 2 + HORN_M):
                    if q == k:
                        continue
                    A, B = seg[q, 0:2], seg[q, 2:4]
                    e = (B - A) / np.linalg.norm(B - A)
                    if abs(d @ e) > 0.3:
                        continue
                    n_ = np.array([-e[1], e[0]])
                    denom = d @ n_
                    s_ = ((A - P) @ n_) / denom
                    if 0 < s_ <= HORN_M:
                        X = P + s_ * d
                        tq = (X - A) @ e
                        if -HORN_M <= tq <= np.linalg.norm(B - A) + HORN_M:
                            seg[k, 2 * ande:2 * ande + 2] = X
                            break

    pickle.dump(dict(segment=seg, kolumner=["E0", "N0", "E1", "N1", "hojd"]), open(work / "hackar.pkl", "wb"))
    (work / "hackar_mask.npy").unlink(missing_ok=True)
    L = np.hypot(seg[:, 2] - seg[:, 0], seg[:, 3] - seg[:, 1])
    print(f"häckar: {len(seg)} segment, {L.sum():.0f} m, höjd median {np.median(seg[:, 4]) if len(seg) else 0:.1f} m")

    # Förhandsbilder: hela kartan (fotot, 1 m/px) och referensplatserna (foto | laser, gröna = häckpixlar)
    (GEO / "forhandsbilder").mkdir(exist_ok=True)
    hel = Image.fromarray(np.moveaxis(o[:3], 0, -1).clip(0, 255).astype(np.uint8))
    dr = ImageDraw.Draw(hel)
    for E0, N0, E1, N1, _ in seg:
        dr.line([((E0 - ruta[0]) / R, (ruta[3] - N0) / R), ((E1 - ruta[0]) / R, (ruta[3] - N1) / R)],
                fill=(255, 0, 255), width=1)
    hel.save(GEO / "forhandsbilder" / f"hackar_{a.projekt}.png")
    for namn, (Ec, Nc) in PLATSER.get(a.projekt, {}).items():
        B = (Ec - 50, Nc - 50, Ec + 50, Nc + 50)
        with rasterio.open(p / "data" / f"ortofoto_{a.projekt}.tif") as d:
            foto = np.moveaxis(d.read([1, 2, 3], window=from_bounds(*B, d.transform), out_shape=(3, 400, 400)), 0, -1)
        Eg, Ng = np.meshgrid(np.linspace(B[0], B[2], 400), np.linspace(B[3], B[1], 400))
        i_, j_ = K.ij(Eg, Ng)
        hh = K.h[i_, j_]
        hc = np.clip(hh / 8, 0, 1)
        las = (np.stack([hc, 0.3 + 0 * hc, 1 - hc], -1) * 255).astype(np.uint8)
        las[hh < 0.5] = 0
        las[hack_px[i_, j_]] = [60, 200, 60]
        bild = Image.fromarray(np.concatenate([foto, las], 1)).resize((1600, 800), Image.NEAREST)
        dr = ImageDraw.Draw(bild)
        k = 800 / 100
        nara = seg[(np.minimum(seg[:, 0], seg[:, 2]) < B[2]) & (np.maximum(seg[:, 0], seg[:, 2]) > B[0])
                   & (np.minimum(seg[:, 1], seg[:, 3]) < B[3]) & (np.maximum(seg[:, 1], seg[:, 3]) > B[1])]
        for E0, N0, E1, N1, _ in nara:   # (PIL ritar fel med linjer långt utanför bilden)
            for x_off in (0, 800):
                dr.line([((E0 - B[0]) * k + x_off, (B[3] - N0) * k), ((E1 - B[0]) * k + x_off, (B[3] - N1) * k)],
                        fill=(255, 0, 255), width=3)
        bild.save(GEO / "forhandsbilder" / f"hackar_{a.projekt}_{namn}.png")


if __name__ == "__main__":
    main()
