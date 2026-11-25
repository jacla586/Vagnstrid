"""
Överfarter: diken som stridsvagnar ska kunna köra över (step3, efter bäckarnas fåror).

`<projekt>/overfarter.json`:
    {"diken": [{"namn": "...", "linje_sweref": [[E, N], ...],
                "botten_halv_m": 3.0,   # plan botten, halva bredden
                "lyft_m": 1.0,          # botten läggs så mycket över dikets lägsta punkt
                "slant_grader": 12.0,   # slänternas lutning
                "avsmalning_m": 25.0,   # ändarna går mjukt över i det gamla diket
                # valfritt: mjuka till dalen runt fåran (marken kan då också sänkas på krönen)
                "utjamna_m": 6.0,       # gaussutjämning (sigma, m) efter fyllningen
                "utjamna_bredd_m": 35.0,  # så långt ut från linjen (tonas ut de sista 10 m)
                "min_vattendjup_m": 0.3}]}  # botten aldrig högre än vattenytan minus detta

Diket fylls (marken sänks aldrig) till en flack U-profil: plan botten på dikets lägsta nivå
plus `lyft_m`, slänter med `slant_grader` upp till kanten (den lägre sidans krön). Med
`utjamna_m` jämnas sedan hela dalen ut (kurvorna mjukare, fårans kanter borta), men aldrig
närmare vägar än `skydd` (bilvägarnas schaktade band utanför däcken) och aldrig så högt i
vattnet att det blir grundare än `min_vattendjup_m` (sjö-/åpolygonernas nivåer). Bäckens
vattenyta läggs sedan i den nya botten (step3 läser höjden efter detta).
"""
import json
from pathlib import Path

import numpy as np
from scipy import ndimage as ndi
from scipy.spatial import cKDTree
from shapely.geometry import LineString


def las(projekt: Path) -> list:
    f = Path(projekt) / 'overfarter.json'
    return json.loads(f.read_text()).get('diken', []) if f.exists() else []


def forma(diken: list, h: np.ndarray, OX: float, OY: float, RES: float,
          skydd: np.ndarray | None = None, vattenniva: np.ndarray | None = None) -> None:
    """skydd: bool-raster där utjämningen inte får röra marken (vägar); vattenniva: nivån per
    cell i sjö-/åpolygonerna (nan utanför)."""
    H, W = h.shape
    for d in diken:
        linje = LineString(d['linje_sweref'])
        bh = float(d.get('botten_halv_m', 3.0))
        lyft = float(d.get('lyft_m', 1.0))
        k = np.tan(np.radians(float(d.get('slant_grader', 12.0))))
        avs = float(d.get('avsmalning_m', 25.0))
        n = max(2, int(linje.length / RES) + 1)
        ss = np.linspace(0, linje.length, n)
        pts = np.array([linje.interpolate(s).coords[0] for s in ss])
        dv = np.gradient(pts, axis=0)
        dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
        nrm = np.c_[-dv[:, 1], dv[:, 0]]

        def prov(xy):
            return ndi.map_coordinates(h, [(OY - xy[:, 1]) / RES, (xy[:, 0] - OX) / RES], order=1, mode='nearest')

        # dikets lägsta punkt tvärs över (±4 m) och krönet: den lägre sidans högsta punkt inom 25 m
        botten = np.min([prov(pts + nrm * o) for o in np.arange(-4.0, 4.1, 1.0)], axis=0)
        sidor = [np.max([prov(pts + nrm * sgn * o) for o in np.arange(4.0, 25.1, 1.0)], axis=0) for sgn in (1, -1)]
        kron = ndi.gaussian_filter1d(np.minimum(*sidor), 4.0, mode='nearest')
        botten = ndi.gaussian_filter1d(botten, 4.0, mode='nearest') + lyft
        botten = np.minimum(botten, kron - 0.3)
        nå = bh + float(np.max(kron - botten)) / k + 2.0
        utj = float(d.get('utjamna_m', 0.0))
        utj_b = float(d.get('utjamna_bredd_m', 35.0))
        if utj > 0.0:
            nå = max(nå, utj_b + 3.0 * utj)

        # celler nära linjen: närmaste linjepunkt, avstånd tvärs
        x0, y0, x1, y1 = linje.buffer(nå).bounds
        j0, j1 = max(0, int((x0 - OX) / RES)), min(W, int((x1 - OX) / RES) + 2)
        i0, i1 = max(0, int((OY - y1) / RES)), min(H, int((OY - y0) / RES) + 2)
        jj, ii = np.meshgrid(np.arange(j0, j1), np.arange(i0, i1))
        cx, cy = OX + jj.ravel() * RES, OY - ii.ravel() * RES
        dist, idx = cKDTree(pts).query(np.c_[cx, cy], distance_upper_bound=nå)
        ok = np.isfinite(dist)
        ii, jj, dist, idx = ii.ravel()[ok], jj.ravel()[ok], dist[ok], idx[ok]
        mal = np.minimum(botten[idx] + k * np.maximum(dist - bh, 0.0), kron[idx])
        # ändarna: från linjens ände och avsmalning_m in går fyllningen från noll till full
        s = ss[idx]
        vikt = np.clip(np.minimum(s, linje.length - s) / max(avs, 1e-3), 0.0, 1.0)
        vikt = vikt * vikt * (3 - 2 * vikt)
        gammal = h[ii, jj].copy()
        h[ii, jj] = np.maximum(gammal, gammal + (mal - gammal) * vikt)
        if utj > 0.0:
            # utjämna dalen i fönstret (fyllningen först, så fåran inte drar ned den)
            fon = h[i0:i1, j0:j1]
            mjuk = ndi.gaussian_filter(fon, utj / RES, mode='nearest')[ii - i0, jj - j0]
            tvars = np.clip((utj_b - dist) / 10.0, 0.0, 1.0)
            tvars = tvars * tvars * (3 - 2 * tvars)
            vu = vikt * tvars
            if skydd is not None:
                fri = 1.0 - np.clip(ndi.gaussian_filter(skydd[i0:i1, j0:j1].astype(float), 2.0) * 2.0, 0.0, 1.0)
                vu = vu * fri[ii - i0, jj - j0]
            ny = h[ii, jj] + (mjuk - h[ii, jj]) * vu
            # fåran behåller sin U-form: utjämningen höjer aldrig över botten + slänten
            # (botten högst vattenytan minus min_vattendjup_m), så ingen kant vid vattnet
            bot = botten.copy()
            if vattenniva is not None and 'min_vattendjup_m' in d:
                pi = np.clip(np.round((OY - pts[:, 1]) / RES).astype(int), 0, H - 1)
                pj = np.clip(np.round((pts[:, 0] - OX) / RES).astype(int), 0, W - 1)
                npt = ndi.grey_dilation(np.nan_to_num(vattenniva, nan=-1e9)[i0:i1, j0:j1], size=5)[pi - i0, pj - j0]
                har = npt > -1e8
                bot[har] = np.minimum(bot[har], npt[har] - float(d['min_vattendjup_m']))
            tak = bot[idx] + k * np.maximum(dist - bh, 0.0)
            ny = np.minimum(ny, np.maximum(tak, h[ii, jj]))
            if vattenniva is not None and 'min_vattendjup_m' in d:
                niva = vattenniva[ii, jj]
                vat = np.isfinite(niva)
                ny[vat] = np.minimum(ny[vat], np.maximum(niva[vat] - float(d['min_vattendjup_m']), h[ii, jj][vat]))
            h[ii, jj] = ny
        print(f"överfart '{d.get('namn', '?')}': {linje.length:.0f} m, botten +{lyft} m, "
              f"slänt {d.get('slant_grader', 12.0)}°, fyllda celler {int((h[ii, jj] > gammal + 0.05).sum())}"
              + (f", utjämnad {utj} m ut till {utj_b:.0f} m (sänkt {int((h[ii, jj] < gammal - 0.05).sum())})"
                 if utj > 0.0 else ''))
