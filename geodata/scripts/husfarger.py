"""Husens verkliga färger: tak ur ortofotot, fasader ur Mapillary (husfarger_mapillary.py).

Taken: medianfärgen i flygfotot innanför husets fotavtryck (krympt TAK_KRYMP_M, så att väggar,
takfot och hus som lutar i fotot inte kommer med), växtlighet bortsorterad med IR-bandet (NDVI).
Fotot har ett blått dis, så färgen klassas i familjer i stället för att användas rakt av:
röd (tegel/plåt), brun, svart, grå, ljus och grön. Familjen och takets form (husets stil för
tegel eller plåt) ger ett tak ur stilar.json (`tak_namn`). Utan foto eller med för få pixlar:
None, och step3 gör som förut.

Fasaderna: `fasadfarger(data)` läser <projekt>/data/husfarger.json (OSM-husets id -> färg, gjord av
husfarger_mapillary.py) och step3 lägger färgen som OSM:s building:colour om OSM saknar den.
"""
import colorsys, json
from pathlib import Path

import numpy as np

TAK_KRYMP_M = 0.75
MIN_PIXLAR = 20
NDVI_MAX = 0.2           # grönare än så = träd eller gräs över taket
ROD_GRANS = 0.18         # (R - B) / max: rödare än så är tegel/rödmålad plåt (fotot är blåstickigt)
MORK_GRANS = 140         # max-kanalen under det: svart tak
LJUS_GRANS = 185         # över det: ljust (vitt/ljusgrått, mest platta tak)
BRUN_GRANS = 120         # rött men mörkare än så: brunt
BRUN_ROD = 0.10          # svagt rödaktigt (fotots blåstick drar ned) och inte ljust: bruna pannor
BRUN_MAX = 165
GRON_NYANS = (0.20, 0.50)


def tak_fran_ortofoto(ortofoto, polys):
    """[(r, g, b) eller None] per polygon (SWEREF 99 TM) ur ortofotot (RGB + IR)."""
    ortofoto = Path(ortofoto)
    if not ortofoto.exists():
        return [None] * len(polys)
    import rasterio
    from rasterio.features import rasterize
    from rasterio.windows import from_bounds
    ut = []
    with rasterio.open(str(ortofoto)) as r:
        A = r.read()
        B = r.bounds
        for poly in polys:
            g = poly.buffer(-TAK_KRYMP_M)
            if g.is_empty or g.area < 6:
                g = poly.buffer(-0.25)
            b = g.bounds if not g.is_empty else None
            if b is None or b[0] < B.left or b[2] > B.right or b[1] < B.bottom or b[3] > B.top:
                ut.append(None)
                continue
            w = from_bounds(*b, r.transform).round_offsets().round_lengths()
            if w.width < 1 or w.height < 1:
                ut.append(None)
                continue
            sub = A[:, w.row_off:w.row_off + w.height, w.col_off:w.col_off + w.width].astype(np.float32)
            if sub.shape[1] < 1 or sub.shape[2] < 1:
                ut.append(None)
                continue
            m = rasterize([(g, 1)], out_shape=sub.shape[1:], transform=r.window_transform(w)).astype(bool)
            px = sub[:, m].T
            if len(px) >= MIN_PIXLAR and sub.shape[0] >= 4:
                R, N = px[:, 0], px[:, 3]
                px = px[(N - R) / (N + R + 1.0) < NDVI_MAX]
            ut.append(tuple(float(v) for v in np.median(px[:, :3], 0)) if len(px) >= MIN_PIXLAR else None)
    return ut


def familj(rgb):
    """Takfärgens familj ur fotots färg: 'rod', 'brun', 'svart', 'gra', 'ljus', 'gron' (eller None)."""
    if rgb is None:
        return None
    r, g, b = rgb
    mx = max(r, g, b)
    rod = (r - b) / max(mx, 1.0)
    h, s, _ = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if s > 0.12 and GRON_NYANS[0] < h < GRON_NYANS[1] and g > r:
        return 'gron'
    if rod > ROD_GRANS:
        return 'rod' if mx >= BRUN_GRANS else 'brun'
    if rod > BRUN_ROD and mx < BRUN_MAX:
        return 'brun'
    if mx < MORK_GRANS:
        return 'svart'
    if mx > LJUS_GRANS:
        return 'ljus'
    return 'gra'


LUTANDE = ('sadel', 'valmat', 'talt')


def tak_namn(fam, modell, stil_tak):
    """Taknamn i stilar.json för en takfamilj, takets form och stilens eget tak (tegel/betong/plåt)."""
    plat = str(stil_tak).startswith('plat')
    if modell in LUTANDE:
        return {'rod': 'plat_rod' if plat else 'tegel_rod', 'brun': 'tegel_brun',
                'svart': 'plat_svart' if plat else 'betong_svart', 'gra': 'plat_gra' if plat else 'betong_gra',
                'ljus': 'plat_gra', 'gron': 'plat_gron'}[fam]
    if modell == 'pulpet':
        return {'rod': 'plat_rod', 'brun': 'plat_rod', 'svart': 'plat_svart', 'gra': 'plat_gra',
                'ljus': 'papp_vit', 'gron': 'plat_gron'}[fam]
    return {'rod': 'plat_rod', 'brun': 'papp', 'svart': 'papp', 'gra': 'papp_gra',
            'ljus': 'papp_vit', 'gron': 'sedum'}[fam]


def nyckel(poly, taggar):
    """Husets nyckel i husfarger.json: OSM-id, eller mittpunkten 'E,N' (äldre features.pkl utan id)."""
    oid = (taggar or {}).get('_osm_id')
    if oid:
        return str(oid)
    c = poly.centroid
    return f'{round(c.x)},{round(c.y)}'


def fasadfarger(data_mapp):
    """{nyckel (OSM-id eller 'E,N'): '#rrggbb'} ur <data>/husfarger.json, eller {}."""
    fil = Path(data_mapp) / 'husfarger.json'
    if not fil.exists():
        return {}
    d = json.loads(fil.read_text())
    return {k: v['farg'] for k, v in d.get('hus', {}).items() if v.get('farg')}
