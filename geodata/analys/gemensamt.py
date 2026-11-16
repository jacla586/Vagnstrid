"""Gemensamt för analysskripten i geodata/analys/ (läser bara; bygger inget och rör inte spelet).

  las_vagar(karta)          vägnätet precis som step3 ser det (vaglista + forbered: NVDB-bredder,
                            harmonisering, isärflyttade körbanor), med r['s'], r['pts'] var 2 m
  vagyta_i(roads, fonster)  vagyta.Vagyta för vägarna i ett fönster (samma ytor som bygget)
  Raster                    ett GeoTIFF i minnet: nara() (närmaste pixel), bilinjar(), utsnitt()
  orto / objekthojd / markhojd(karta)
  ytklasser(rgb, nir, h)    per pixel: grönt, skugga, hårdgjort, skymt (laserns objekthöjd)
  PLATSER[karta]            testplatser (namn, E, N) som skripten använder utan --ruta (andra kartor:
                            auto_platser, mitt på den längsta vägen per vägklass)
"""
import json
import os
import pickle
import sys
from pathlib import Path

import numpy as np
import rasterio
from shapely.geometry import box

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'scripts'))
UT = ROOT / 'analys' / 'ut'

GATOR = ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'unclassified', 'residential',
         'living_street', 'service', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link',
         'tertiary_link')

# Testplatser: (namn, E, N) i SWEREF 99 TM. Väljs för att täcka typfallen (dubbla körbanor, korsningar,
# villagata, breda gator med cykelfält, smala gångar mellan radhus som OSM kallar gator).
PLATSER = {
    'vidingsjo': [
        ('coop_bron', 536380, 6472335),            # Haningeleden under bron vid Stora Coop
        ('haningeleden_kors', 537107, 6471205),    # korsning med spärrområde och svängpilar
        ('algvagen', 538293, 6472093),             # bred gata (11 m enligt fotot)
        ('villagata_gupp', 537519, 6471599),       # villagata med farthinder
        ('blastadsgatan', 538890, 6471071),        # smal gång mellan radhus (OSM living_street)
        ('skogsgatan', 538770, 6472211),           # tertiär gata
        ('ortgatan', 537372, 6471130),             # villakvarter
    ],
}


def grid(karta):
    g = json.load(open(ROOT / karta / 'work' / 'grid.json'))
    x0, y1 = g['x0'], g['y1']
    x1, y0 = x0 + g['W'] * g['RES'], y1 - g['H'] * g['RES']
    return dict(x0=x0, y0=y0, x1=x1, y1=y1, OX=x0 + g['RES'] / 2, OY=y1 - g['RES'] / 2, RES=g['RES'])


def las_vagar(karta, med_bro=True):
    """(roads, BRO, ruta): vägnätet som step3 ser det. BRO = broar.Broar (däckens spann) eller None."""
    import vagnat
    import broar
    work = ROOT / karta / 'work'
    os.environ.setdefault('GEO_WORK', str(work))
    os.environ.setdefault('GEO_NAMN', karta)
    g = grid(karta)
    ruta = (g['x0'], g['y0'], g['x1'], g['y1'])
    feat = pickle.load(open(work / 'features.pkl', 'rb'))
    roads = vagnat.vaglista(feat['roads'], box(*ruta))
    vagnat.forbered(roads, ruta, work, rattningar=False)   # analysen mäter alltid mot vägnätet utan rättningar
    BRO = broar.Broar(roads) if med_bro else None
    for r in roads:   # som step3: punkter var 2 m (höjden behövs inte här)
        L = r['line']
        n = max(2, int(L.length / 2) + 1)
        r['s'] = np.linspace(0, L.length, n)
        r['pts'] = np.array([L.interpolate(d).coords[0] for d in r['s']])
        r['z'] = np.zeros(n)
    return roads, BRO, ruta


def hus(karta, fonster=None):
    feat = pickle.load(open(ROOT / karta / 'work' / 'features.pkl', 'rb'))
    return [g for g, t in feat['buildings'] if fonster is None or g.intersects(fonster)]


def vagyta_i(roads, BRO, karta, fonster):
    """vagyta.Vagyta för vägarna som når in i fönstret (polygonen) -> (Vagyta, [index i roads])."""
    import vagyta
    idx = [k for k, r in enumerate(roads) if r['line'].intersects(fonster.buffer(40))]
    sroads = [roads[k] for k in idx]

    class _Bro:
        pass
    b = _Bro()
    b.spann = {i: (BRO.spann.get(k, []) if BRO is not None else []) for i, k in enumerate(idx)}
    g = grid(karta)
    V = vagyta.Vagyta(sroads, b, hus(karta, fonster.buffer(40)), rutnat=(g['OX'], g['OY']))
    return V, idx


class Raster:
    def __init__(self, fil):
        with rasterio.open(fil) as r:
            self.A = r.read()
            self.T = r.transform
            self.inv = ~r.transform
            self.res = r.res[0]
            self.nodata = r.nodata

    def nara(self, x, y, band=None):
        c, rr = self.inv * (np.asarray(x, float), np.asarray(y, float))
        c = np.clip(np.floor(c).astype(int), 0, self.A.shape[2] - 1)
        rr = np.clip(np.floor(rr).astype(int), 0, self.A.shape[1] - 1)
        return self.A[:, rr, c] if band is None else self.A[band, rr, c]

    def bilinjar(self, x, y, band=0):
        c, rr = self.inv * (np.asarray(x, float), np.asarray(y, float))
        c, rr = c - 0.5, rr - 0.5
        c0 = np.clip(np.floor(c).astype(int), 0, self.A.shape[2] - 2)
        r0 = np.clip(np.floor(rr).astype(int), 0, self.A.shape[1] - 2)
        fc, fr = np.clip(c - c0, 0, 1), np.clip(rr - r0, 0, 1)
        A = self.A[band].astype(float)
        return (A[r0, c0] * (1 - fc) * (1 - fr) + A[r0, c0 + 1] * fc * (1 - fr) +
                A[r0 + 1, c0] * (1 - fc) * fr + A[r0 + 1, c0 + 1] * fc * fr)

    def utsnitt(self, x0, y0, x1, y1):
        """(array (band, rad, kol), extent (x0, x1, y0, y1), transform) för rutan."""
        r0, c0 = rasterio.transform.rowcol(self.T, x0, y1)
        r1, c1 = rasterio.transform.rowcol(self.T, x1, y0)
        r0, c0 = max(r0, 0), max(c0, 0)
        r1, c1 = min(r1, self.A.shape[1]), min(c1, self.A.shape[2])
        sub = self.A[:, r0:r1, c0:c1]
        X0, Y1 = self.T * (c0, r0)
        X1, Y0 = self.T * (c1, r1)
        T = rasterio.transform.from_origin(X0, Y1, self.res, self.res)
        return sub, (X0, X1, Y0, Y1), T


def orto_fil(karta, fil=None):
    """Ortofotot att använda: fil om given, annars 16 cm-fotot om det finns (hamta_ortofoto.py --suffix 16cm),
    annars byggets 0,5 m-foto. None om inget finns."""
    if fil:
        return Path(fil)
    for namn in (f'ortofoto_{karta}_16cm.tif', f'ortofoto_{karta}.tif'):
        f = ROOT / karta / 'data' / namn
        if f.exists():
            return f
    return None


def orto(karta, fil=None):
    """Ortofotot (RGB + IR), se orto_fil."""
    f = orto_fil(karta, fil)
    if f is None:
        sys.exit(f'inget ortofoto för {karta} (hämta: scripts/hamta_ortofoto.py hamta --omrade {karta} '
                 f'--upplosning 0.16 --suffix 16cm)')
    print('ortofoto:', f.name)
    return Raster(f)


def orto_var(karta):
    """Vårfotot (före lövsprickningen, hamta_ortofoto.py --samling orto-l2-2023 --suffix 16cm_2023) eller None.
    Vägar under träd syns där; skuggorna är längre (lägre sol)."""
    f = ROOT / karta / 'data' / f'ortofoto_{karta}_16cm_2023.tif'
    if not f.exists():
        return None
    print('vårfoto:', f.name)
    return Raster(f)


def objekthojd(karta):
    return Raster(ROOT / karta / 'data' / f'objekthojd_{karta}.tif')


def markhojd(karta):
    return Raster(ROOT / karta / 'data' / f'markhojd_{karta}.tif')


NDVI_GRON = 0.12        # över detta: växtlighet
SKUGGA_LJUS = 55.0      # medelvärde av RGB under detta: skugga (okänt, inte "inte asfalt")
MATTNAD_HARD = 0.22     # hårdgjort: grått (låg mättnad)
HINDER_H_M = 0.8        # laserns objekthöjd över detta: skymt (träd, bil, skylt)


def ytklasser(rgb, nir, h_m):
    """rgb (..., 3) och nir (...) som float 0-255, h_m laserns objekthöjd i m (samma form som nir).
    -> dict med booleska masker: gron, skugga, skymt, hard (grått, inte grönt, inte skugga, inte skymt)."""
    rgb = np.asarray(rgb, float)
    R = rgb[..., 0]
    ndvi = (nir - R) / (nir + R + 1.0)
    ljus = rgb.mean(-1)
    mx, mn = rgb.max(-1), rgb.min(-1)
    mattnad = (mx - mn) / np.maximum(mx, 1.0)
    gron = ndvi > NDVI_GRON
    skymt = h_m > HINDER_H_M
    skugga = (ljus < SKUGGA_LJUS) & ~gron
    hard = ~gron & ~skymt & ~skugga & (mattnad < MATTNAD_HARD)
    return dict(gron=gron, skugga=skugga, skymt=skymt, hard=hard, ndvi=ndvi, ljus=ljus, mattnad=mattnad)


def h_pa_orto(H, T, form):
    """Laserns objekthöjd (m) samplad på ortofotots rutnät (transform T, form (rad, kol))."""
    rr, cc = np.mgrid[0:form[0], 0:form[1]]
    x, y = T * (cc + 0.5, rr + 0.5)
    return H.nara(x.ravel(), y.ravel(), 0).reshape(form).astype(float) / 10.0


AUTO_KLASSER = ('primary', 'secondary', 'tertiary', 'residential', 'living_street', 'service')


def auto_platser(karta):
    """Testplatser för en karta utan egna: mitt på den längsta asfalterade vägen (OSM-bit) per vägklass."""
    feat = pickle.load(open(ROOT / karta / 'work' / 'features.pkl', 'rb'))
    g = grid(karta)
    rb = box(g['x0'] + 80, g['y0'] + 80, g['x1'] - 80, g['y1'] - 80)
    ut = []
    for kl in AUTO_KLASSER:
        kand = [(L.intersection(rb).length, L, t) for L, t in feat['roads']
                if t.get('highway') == kl and t.get('surface', 'asphalt') in ('asphalt', 'paved') and L.intersects(rb)]
        if not kand:
            continue
        _, L, t = max(kand, key=lambda x: x[0])
        m = L.intersection(rb).interpolate(0.5, normalized=True)
        namn = (t.get('name') or kl).lower().replace(' ', '_')
        ut.append((f'{kl}_{namn}'[:30], round(m.x), round(m.y)))
    return ut


def platser(karta, ruta_arg=None, halv=60.0):
    """[(namn, fönsterpolygon)] ur --ruta 'E,N[,halv]', kartans testplatser (PLATSER) eller automatiska
    (auto_platser: en per vägklass)."""
    if ruta_arg:
        v = [float(x) for x in ruta_arg.split(',')]
        h_ = v[2] if len(v) > 2 else halv
        return [('ruta', box(v[0] - h_, v[1] - h_, v[0] + h_, v[1] + h_))]
    lista = PLATSER.get(karta) or auto_platser(karta)
    return [(n, box(E - halv, N - halv, E + halv, N + halv)) for n, E, N in lista]


def rita_poly(ax, geom, **kw):
    """Konturerna (även hål) av en (multi)polygon."""
    for p in getattr(geom, 'geoms', [geom]):
        if p.geom_type != 'Polygon':
            continue
        for ring in [p.exterior] + list(p.interiors):
            xs, ys = ring.xy
            ax.plot(xs, ys, **kw)


def ut_mapp(karta, namn):
    d = UT / f'{karta}_{namn}'
    d.mkdir(parents=True, exist_ok=True)
    return d
