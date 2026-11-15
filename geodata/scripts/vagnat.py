"""Vägnätet före meshar och schaktning (step3 och vagtest.py kör samma kod):

  vaglista(feat_roads, BOX)       OSM-vägar inom rutan -> dict per väg (line, tags, width, surface, name)
  korsningsstumpar(roads)         körbanor med mittremsa fortsätter genom korsningar (se nedan)
  forbered(roads, ruta, work)     korsningsstumpar + NVDB (nvdb.berika) + harmonisering -> Matchning

Korsningsstumpar: OSM ritar ofta en väg med mittremsa (två enkelriktade körbanor) som en kort
dubbelriktad bit genom en korsning. Då hoppar vägen i sidled. En dubbelriktad bit kortare än
STUMP_MAX_M med samma namn, där båda ändarna möter ett par enkelriktade körbanor med samma namn,
tas bort; körbanorna slås ihop över den, förskjutna åt var sitt håll lika mycket som de ligger isär
STUMP_MATT_M från korsningen (de närmaste STUMP_MATT_M, där de svänger in mot stumpen, ersätts).
"""
import numpy as np
from shapely.geometry import LineString, Point

WIDTH = dict(trunk=8, primary=7.5, secondary=7, tertiary=6.5, unclassified=5, residential=5, living_street=4.5,
             pedestrian=3.0, service=3.5, track=3.0, path=1.2, footway=1.5, cycleway=2.5)
STUMP_MAX_M = 150.0
RONDELL_BREDD_M = 7.0      # cirkulationsplatsens körbana (en körbana runt; två körfält: +3 m)
STUMP_MATT_M = 30.0
NOD_TOL_M = 1.0
import os
_DEBUG = bool(os.environ.get('VAGNAT_DEBUG'))


def surface_of(t):
    s = t.get('surface')
    if s in ('asphalt', 'paved', 'concrete'):
        return 'asfalt'
    if s in ('unpaved', 'gravel', 'compacted', 'fine_gravel', 'dirt', 'ground'):
        return 'grus' if t['highway'] not in ('path', 'footway') else 'stig'
    if t['highway'] in ('trunk', 'primary', 'secondary', 'tertiary'):
        return 'asfalt'
    if t['highway'] in ('path', 'footway'):
        return 'stig'
    return 'grus'


def osm_bredd(r):
    """OSM:s width-tagg om den är satt (även GC-vägar), annars tabellen per vägtyp."""
    try:
        b = float(str(r['tags'].get('width', '')).replace(',', '.').split()[0])
        if 0.5 < b < 40:
            return b
    except (ValueError, IndexError):
        pass
    return WIDTH.get(r['tags']['highway'], 3.0)


def ny_vag(line, t):
    return dict(line=line, tags=t, width=osm_bredd(dict(tags=t)), surface=surface_of(t),
                name=t.get('name') or t.get('ref') or t['highway'])


def vaglista(feat_roads, BOX):
    roads = []
    for geom, t in feat_roads:
        is_e851 = t.get('ref') == 'E 851'
        gg = geom if is_e851 else geom.intersection(BOX)
        if gg.is_empty:
            continue
        for part in getattr(gg, 'geoms', [gg]):
            rondell = t.get('junction') in ('roundabout', 'circular')
            if part.geom_type != 'LineString' or part.length < (0.3 if rondell else 4):
                continue   # rondellernas korta kopplingsbitar behövs för att ringen ska bli hel
            roads.append(ny_vag(part, t))
    return roads


def _enkel(t):
    return t.get('oneway') in ('yes', '1', '-1')


def _namn(t):
    return t.get('name') or t.get('ref')


def _flode(r):
    """Linjen i körriktningen (oneway=-1 vänds)."""
    c = list(r['line'].coords)
    return c[::-1] if r['tags'].get('oneway') == '-1' else c


def _speciell(t):
    return any(t.get(k) not in (None, 'no') for k in ('bridge', 'tunnel', 'junction'))


def korsningsstumpar(roads):
    n_fix = 0
    borta = set()
    nya = []
    for k, r in enumerate(roads):
        t = r['tags']
        if _enkel(t) or not _namn(t) or r['line'].length > STUMP_MAX_M or _speciell(t) or k in borta:
            continue
        a, b = np.array(r['line'].coords[0]), np.array(r['line'].coords[-1])
        par = []
        for nod in (a, b):
            in_, ut = None, None
            for j, q in enumerate(roads):
                if j == k or j in borta or not _enkel(q['tags']) or _namn(q['tags']) != _namn(t) \
                        or _speciell(q['tags']):
                    continue
                f = _flode(q)
                if np.linalg.norm(np.array(f[-1]) - nod) < NOD_TOL_M:
                    in_ = j
                elif np.linalg.norm(np.array(f[0]) - nod) < NOD_TOL_M:
                    ut = j
            par.append((in_, ut))
        (in_a, ut_a), (in_b, ut_b) = par
        if None in (in_a, ut_a, in_b, ut_b) or len({in_a, ut_a, in_b, ut_b}) < 4:
            if _DEBUG:
                print('  stump', round(r['line'].length), 'par', par)
            continue
        stump = np.array(r['line'].coords)
        riktn = stump[-1] - stump[0]
        riktn /= max(np.linalg.norm(riktn), 1e-9)
        nrm = np.array([-riktn[1], riktn[0]])

        def isar(j_in, j_ut, fran_slut):
            """Halva avståndet mellan paret STUMP_MATT_M från noden."""
            fi, fu = LineString(_flode(roads[j_in])), LineString(_flode(roads[j_ut]))
            p = fi.interpolate(max(fi.length - STUMP_MATT_M, 0))
            return max(fu.distance(p) / 2, 2.0)
        off = (isar(in_a, ut_a, True) + isar(in_b, ut_b, True)) / 2

        def sida(j):
            """Vilken sida om stumpen körbanan ligger: en punkt 15 m från noden den möter."""
            f = LineString(_flode(roads[j]))
            vid_a = min(np.linalg.norm(np.array(f.coords[0]) - a), np.linalg.norm(np.array(f.coords[-1]) - a)) < NOD_TOL_M
            nod = a if vid_a else b
            ande_ar_start = np.linalg.norm(np.array(f.coords[0]) - nod) < NOD_TOL_M
            p = f.interpolate(min(15.0, f.length / 2) if ande_ar_start else max(f.length - 15.0, f.length / 2))
            return 1.0 if np.dot(np.array(p.coords[0]) - nod, nrm) > 0 else -1.0

        # in vid a -> ut vid b (samma körriktning a->b), in vid b -> ut vid a (b->a)
        ok = True
        for j_in, j_ut, fram in ((in_a, ut_b, True), (in_b, ut_a, False)):
            if sida(j_in) != sida(j_ut):
                ok = False
        if not ok:
            continue
        lokala = []
        for j_in, j_ut, fram in ((in_a, ut_b, True), (in_b, ut_a, False)):
            fi, fu = LineString(_flode(roads[j_in])), LineString(_flode(roads[j_ut]))
            s = sida(j_in)
            mitt = stump if fram else stump[::-1]
            mitt = mitt + nrm * s * off
            if fi.length <= STUMP_MATT_M + 5 or fu.length <= STUMP_MATT_M + 5:
                ok = False
                break
            fore = [fi.interpolate(d).coords[0] for d in np.arange(0, fi.length - STUMP_MATT_M, 2.0)]
            efter = [fu.interpolate(d).coords[0] for d in np.arange(STUMP_MATT_M, fu.length, 2.0)] + [fu.coords[-1]]
            koord = fore + [tuple(p) for p in mitt] + efter
            linje = LineString(_jamna(np.array(koord), 3))
            tags = dict(roads[j_in]['tags'])
            tags['oneway'] = 'yes'
            lokala.append(ny_vag(linje, tags))
        if not ok:
            if _DEBUG:
                print('  stump', round(r['line'].length), 'för korta körbanor')
            continue
        nya += lokala
        borta |= {k, in_a, ut_a, in_b, ut_b}
        n_fix += 1
    ut = [r for k, r in enumerate(roads) if k not in borta] + nya
    print(f'vägnät: {n_fix} korsningsstumpar borttagna, körbanorna fortsätter genom korsningen')
    return ut


def _jamna(c, varv):
    """Chaikin-utjämning, ändpunkterna behålls."""
    for _ in range(varv):
        if len(c) < 3:
            return c
        q = 0.75 * c[:-1] + 0.25 * c[1:]
        r = 0.25 * c[:-1] + 0.75 * c[1:]
        m = np.empty((2 * len(q), 2))
        m[0::2], m[1::2] = q, r
        c = np.vstack([c[:1], m, c[-1:]])
    return c


def rondeller(roads):
    """Cirkulationsplatsens bitar (junction=roundabout) slås ihop till en sluten väg per rondell,
    så att ringen inte får glipor i skarvarna; r['rondell'] = True (fast bredd, harmoniseras inte)."""
    from shapely.ops import linemerge
    idx = [k for k, r in enumerate(roads) if r['tags'].get('junction') in ('roundabout', 'circular')]
    if not idx:
        return roads
    forald = {k: k for k in idx}
    def rot(k):
        while forald[k] != k:
            forald[k] = forald[forald[k]]
            k = forald[k]
        return k
    andar = [(k, np.array(roads[k]['line'].coords[e])) for k in idx for e in (0, -1)]
    for i in range(len(andar)):
        for j in range(i + 1, len(andar)):
            if np.linalg.norm(andar[i][1] - andar[j][1]) < NOD_TOL_M:
                forald[rot(andar[i][0])] = rot(andar[j][0])
    grupper = {}
    for k in idx:
        grupper.setdefault(rot(k), []).append(k)
    nya = []
    for lista in grupper.values():
        m = linemerge([roads[k]['line'] for k in lista])
        for part in getattr(m, 'geoms', [m]):
            t = dict(roads[lista[0]]['tags'])
            r = ny_vag(part, t)
            r['rondell'] = True
            nya.append(r)
    borta = set(idx)
    print(f'vägnät: {len(idx)} rondellbitar -> {len(nya)} ringar')
    return [r for k, r in enumerate(roads) if k not in borta] + nya


def forbered(roads, ruta, work):
    import nvdb
    roads[:] = rondeller(roads)
    roads[:] = korsningsstumpar(roads)
    NV = nvdb.Matchning(nvdb.utdrag(ruta, work))
    nvdb.berika(roads, NV, osm_bredd)
    nvdb.harmonisera(roads)
    for r in roads:   # rondellerna: fast bredd efter körfälten
        if r.get('rondell'):
            try:
                kf = int(r['tags'].get('lanes', '1'))
            except ValueError:
                kf = 1
            b = RONDELL_BREDD_M + 3.0 * max(kf - 1, 0)
            r['hw'] = np.full(len(r['hw']), b / 2)
            r['width'] = b
    return NV
