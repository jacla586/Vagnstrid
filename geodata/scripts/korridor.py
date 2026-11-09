"""Korridorkartor (väg-banor, ThunderRoad): bara hus, träd och buskar nära en rutt.

Finns <projekt>/korridor.json läggs objekt bara ut inom `bredd_m` från rutten, med en ojämn kant
som glesnar ut över `kant_m` (så att skogen inte slutar i en linjal). Terrängen och vägarna byggs
som vanligt över hela rutan (Terrain3D kostar inte per yta, objekten gör det).

    {"rutt_sweref": [[E, N], ...], "bredd_m": 500, "kant_m": 100}

Utan filen gör modulen ingenting (alla andra kartor).
"""
import json
from pathlib import Path

import numpy as np

_avst = None    # (avståndsraster i meter, x0, y1, res) eller False


def _las(work: Path):
    global _avst
    if _avst is not None:
        return _avst
    fil = work.parent / 'korridor.json'
    if not fil.exists():
        _avst = False
        return _avst
    from scipy import ndimage as ndi
    from rasterio.features import rasterize
    from rasterio.transform import from_origin
    from shapely.geometry import LineString
    k = json.loads(fil.read_text())
    g = json.load(open(str(work / 'grid.json')))
    W, H, RES, X0, Y1 = g['W'], g['H'], g['RES'], g['x0'], g['y1']
    linje = LineString(k['rutt_sweref']).buffer(RES)
    pa = rasterize([(linje, 1)], out_shape=(H, W), transform=from_origin(X0, Y1, RES, RES)).astype(bool)
    d = ndi.distance_transform_edt(~pa).astype(np.float32) * RES
    _avst = (d, X0, Y1, RES, float(k.get('bredd_m', 500.0)), float(k.get('kant_m', 100.0)))
    print(f"korridor: {k.get('bredd_m', 500)} m runt rutten ({fil.name})")
    return _avst


def aktiv(work: Path) -> bool:
    return bool(_las(work))


def avstand(work: Path, E, N):
    """Avstånd (m) till rutten för SWEREF-punkter; 0 överallt utan korridor."""
    a = _las(work)
    E = np.atleast_1d(np.asarray(E, float)); N = np.atleast_1d(np.asarray(N, float))
    if not a:
        return np.zeros(E.shape, np.float32)
    d, X0, Y1, RES = a[:4]
    j = np.clip(((E - X0) / RES).astype(int), 0, d.shape[1] - 1)
    i = np.clip(((Y1 - N) / RES).astype(int), 0, d.shape[0] - 1)
    return d[i, j]


def inne(work: Path, E, N, slump=None):
    """Bool per punkt: ska objektet med? Inom bredd_m alltid, sedan allt glesare till bredd + kant.
    `slump` (0..1 per punkt) ger den ojämna kanten; utan den gäller bredd + halva kanten."""
    a = _las(work)
    E = np.atleast_1d(np.asarray(E, float))
    if not a:
        return np.ones(E.shape, bool)
    bredd, kant = a[4], a[5]
    d = avstand(work, E, N)
    if slump is None:
        return d <= bredd + kant / 2
    return d <= bredd + kant * (1.0 - np.asarray(slump)) ** 2
