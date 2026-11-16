"""Uppfarter på villatomterna (anropas av stenlaggning.berakna): en rak bit asfalt eller marksten från gatan
in till garaget (eller villans gavel mot gatan där OSM inte har något garage).

OSM har nästan inga uppfarter, men garagen och villorna. För varje garage/villa: närmaste bilgata inom
MAX_AVST_M, axeln från huset till gatans kant. I en korridor KORRIDOR_HALV_M åt sidorna längs axeln läses
ortofotot (0,5 m) och laserns objekthöjd: hårt = ingen grönska (NDVI) och lågt (inte häck, buske eller tak).
Bara en sammanhängande hård yta som når både huset och gatan blir en uppfart, och då som en rak rektangel
(bredden mellan 5:e och 95:e percentilen tvärs axeln), som måste vara fylld längs hela vägen: hellre ingen
uppfart än en påhittad över gräsmattan. Tonen i fotot avgör asfalt (mörk) eller marksten (ljus).
-> [(polygon, 'asfalt' | 'sten')]
"""
import math

import numpy as np
import rasterio
import shapely
from rasterio.enums import Resampling
from rasterio.features import rasterize
from scipy import ndimage as ndi
from shapely.geometry import LineString, Polygon
from shapely.ops import nearest_points, unary_union
from shapely.strtree import STRtree

CELL = 0.5
GARAGE = ('garage', 'garages', 'carport')
VILLOR = ('house', 'detached', 'semidetached_house', 'terrace', 'villa', 'bungalow', 'farm')
GATOR = ('residential', 'living_street', 'unclassified', 'tertiary', 'service', 'secondary', 'road')
MAX_AVST_M = 25.0
MIN_AVST_M = 1.5
KORRIDOR_HALV_M = 5.0
NDVI_HART = 0.10
HOJD_HART_M = 1.0
BREDD_M = (2.4, 8.0)
FYLLD = 0.6          # medel längs axeln
FYLLD_MINST = 0.3    # varje meter längs axeln
LJUS_STEN = 115      # ljusare än så i fotot: marksten/betong


def bygg(byggnader, roads, vatten, upptaget, ortofoto, objhojd, karta):
    """byggnader: [(polygon, taggar)]; roads: step3:s vägar; upptaget: ytor som redan är något (parkeringar);
    karta: shapely-ruta. -> [(polygon, sort)]"""
    if not ortofoto.exists():
        return []
    gator = [r for r in roads if r['tags'].get('highway') in GATOR
             and r['tags'].get('service') not in ('parking_aisle', 'drive-through', 'driveway')]
    osm_uppf = [r['line'] for r in roads if r['tags'].get('service') == 'driveway']   # ritas redan som väg
    utrad = STRtree(osm_uppf) if osm_uppf else None
    if not gator:
        return []
    gpoly = [r['line'].buffer(r['width'] / 2) for r in gator]
    gtrad = STRtree(gpoly)
    alla_hus = [g for g, _ in byggnader]
    htrad = STRtree(alla_hus)
    garage = [g for g, t in byggnader if t.get('building') in GARAGE and g.intersects(karta)]
    gtrad_garage = STRtree(garage) if garage else None
    villor = []
    for g, t in byggnader:
        b = t.get('building')
        if not g.intersects(karta):
            continue
        if b in VILLOR or (b == 'yes' and 50 <= g.area <= 250):
            if gtrad_garage is not None and len(gtrad_garage.query(g.buffer(15.0))):
                continue   # garaget har uppfarten
            villor.append(g)
    hojd = None
    if objhojd is not None and objhojd.exists():
        with rasterio.open(objhojd) as src:
            hojd, hT = src.read(1).astype(np.float32) / 10.0, src.transform
    upptagen = unary_union(list(upptaget) + list(vatten)) if (upptaget or vatten) else None
    ut = []
    with rasterio.open(ortofoto) as foto:
        for hus in garage + villor:
            if utrad is not None and len(utrad.query(hus.buffer(4.0))):
                continue
            p = _en(hus, gtrad, gpoly, htrad, alla_hus, foto, hojd, hT if hojd is not None else None)
            if p is not None:
                ut.append(p)
    if not ut:
        return []
    # ihop (garage och villa på samma tomt), minus parkeringar, vatten och hus
    sorter = {}
    for p, s in ut:
        sorter.setdefault(s, []).append(p)
    res = []
    tagna = upptagen
    for s in ('asfalt', 'sten'):
        if s not in sorter:
            continue
        y = unary_union(sorter[s])
        if tagna is not None:
            y = y.difference(tagna)
        for p in getattr(y, 'geoms', [y]):
            if p.geom_type == 'Polygon' and p.area >= 6.0:
                res.append((p, s))
        tagna = y if tagna is None else tagna.union(y)
    print('uppfarter:', len(res), 'av', len(garage), 'garage +', len(villor), 'villor;',
          int(sum(p.area for p, _ in res)), 'm²')
    return res


def _en(hus, gtrad, gpoly, htrad, alla_hus, foto, hojd, hT):
    near = gtrad.query(hus.buffer(MAX_AVST_M))
    if not len(near):
        return None
    gata = min((gpoly[i] for i in near), key=hus.distance)
    L = hus.distance(gata)
    if not MIN_AVST_M <= L <= MAX_AVST_M:
        return None
    pb, pr = nearest_points(hus, gata)
    b0, r0 = np.array(pb.coords[0]), np.array(pr.coords[0])
    u = (r0 - b0) / L
    n = np.array([-u[1], u[0]])
    # fönster runt korridoren
    hrn = [b0 - 2 * u + n * KORRIDOR_HALV_M, b0 - 2 * u - n * KORRIDOR_HALV_M,
           r0 + 2 * u + n * KORRIDOR_HALV_M, r0 + 2 * u - n * KORRIDOR_HALV_M]
    E0, N0 = np.floor(np.min(hrn, 0) / CELL) * CELL
    E1, N1 = np.ceil(np.max(hrn, 0) / CELL) * CELL
    nE, nN = int(round((E1 - E0) / CELL)), int(round((N1 - N0) / CELL))
    w = rasterio.windows.from_bounds(E0, N0, E1, N1, foto.transform)
    a = foto.read(window=w, out_shape=(foto.count, nN, nE), resampling=Resampling.average,
                  boundless=True, fill_value=0).astype(float)
    if a.shape[0] < 4 or (a[:3].sum(0) == 0).mean() > 0.2:
        return None
    ljus = a[:3].mean(0)
    ndvi = (a[3] - a[0]) / (a[3] + a[0] + 1e-6)
    hart = ndvi < NDVI_HART
    T1 = rasterio.transform.from_origin(E0, N1, CELL, CELL)
    EE, NN = np.meshgrid(E0 + (np.arange(nE) + 0.5) * CELL, N1 - (np.arange(nN) + 0.5) * CELL)
    if hojd is not None:
        rr, cc = rasterio.transform.rowcol(hT, EE.ravel(), NN.ravel())
        rr, cc = np.asarray(rr).reshape(EE.shape), np.asarray(cc).reshape(EE.shape)
        ok = (rr >= 0) & (rr < hojd.shape[0]) & (cc >= 0) & (cc < hojd.shape[1])
        hh = np.zeros(EE.shape, np.float32)
        hh[ok] = hojd[rr[ok], cc[ok]]
        hart &= hh < HOJD_HART_M
    ruta = shapely.box(E0, N0, E1, N1)
    hus_har = [alla_hus[i] for i in htrad.query(ruta)]
    husm = rasterize([(h, 1) for h in hus_har], out_shape=hart.shape, transform=T1).astype(bool)
    gatm = rasterize([(gata, 1)], out_shape=hart.shape, transform=T1).astype(bool)
    hart = ndi.binary_closing(hart, iterations=2) & ~husm   # bilar på uppfarten (laser/foto) fylls
    hart = ndi.binary_opening(hart, iterations=1)
    s = (EE - b0[0]) * u[0] + (NN - b0[1]) * u[1]
    t = (EE - b0[0]) * n[0] + (NN - b0[1]) * n[1]
    korr = (s >= -1.0) & (s <= L + 0.5) & (np.abs(t) <= KORRIDOR_HALV_M) & ~gatm
    hk = hart & korr
    lab, nl = ndi.label(hk)
    if not nl:
        return None
    # komponenten som når både huset (s < 1,5 m) och gatan (s > L - 1,5 m)
    vid_hus = set(np.unique(lab[hk & (s < 1.5)])) - {0}
    vid_gata = set(np.unique(lab[hk & (s > L - 1.5)])) - {0}
    bada = vid_hus & vid_gata
    if not bada:
        return None
    k = max(bada, key=lambda i: int((lab == i).sum()))
    km = lab == k
    tv = t[km]
    lo, hi = np.percentile(tv, [5, 95])
    lo, hi = lo - CELL / 2, hi + CELL / 2
    if not BREDD_M[0] <= hi - lo <= BREDD_M[1]:
        return None
    # fylld längs hela axeln (inom bredden)
    band = korr & (t >= lo) & (t <= hi) & (s >= 0) & (s <= L)
    sb = np.floor(s[band]).astype(int)
    if sb.size == 0:
        return None
    tot = np.bincount(sb)
    fyll = np.bincount(sb, weights=km[band].astype(float), minlength=tot.size)
    m = tot > 0
    andel = fyll[m] / tot[m]
    if andel.mean() < FYLLD or andel.min() < FYLLD_MINST:
        return None
    # rektangeln: från innanför husväggen till 0,3 m in under gatans kant
    def P(si, ti):
        return tuple(b0 + u * si + n * ti)
    rekt = Polygon([P(-2.0, lo), P(L + 0.3, lo), P(L + 0.3, hi), P(-2.0, hi)])
    hinder = [h.buffer(0.05) for h in hus_har if h.intersects(rekt)]
    smal = gata.buffer(-0.3)
    if not smal.is_empty:
        hinder.append(smal)
    if hinder:
        rekt = rekt.difference(unary_union(hinder))
    if rekt.is_empty:
        return None
    if rekt.geom_type != 'Polygon':   # bara biten som når gatan
        rekt = max(rekt.geoms, key=lambda g: g.area)
    sort = 'sten' if float(np.median(ljus[km])) > LJUS_STEN else 'asfalt'
    return rekt, sort
