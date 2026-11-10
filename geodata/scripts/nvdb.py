"""NVDB (Trafikverket, Lastkajen, CC0) för vägarna: bredd, slitlager, hastighet, beläggningens ålder m.m.

Läser länsfilen `östergötland/data/lastkajen/Östergötlands_län.gpkg` (och beläggningsfilen) inom kartans
ruta, sparar ett utdrag i `work/nvdb.pkl` och kopplar egenskaperna till OSM-vägarnas punkter (var 2 m):
närmaste NVDB-sträcka inom MAX_AVSTAND_M med liknande riktning. Utan filerna blir allt tomt och
step3 använder OSM-reglerna som förut.
"""
import os, pickle, sqlite3
from pathlib import Path
import numpy as np
import shapely
from shapely.geometry import box

ROOT = Path(__file__).resolve().parent.parent
LASTKAJEN = ROOT / 'östergötland' / 'data' / 'lastkajen'
NVDB_FIL = LASTKAJEN / 'Östergötlands_län.gpkg'
BELAGGNING_FIL = LASTKAJEN / 'Östergötland-Beläggning-Senaste-2026.gpkg'
MARGINAL_M = 200.0
MAX_AVSTAND_M = 9.0
MAX_VINKEL_DEG = 35.0

# lager -> {kort namn: kolumn}
LAGER = {
    'NVDB_DK_O_31_Vagbredd': {'bredd': 'Bredd'},
    'NVDB_DK_O_30_Slitlager': {'slitlager': 'Slitlagertyp'},
    'NVDB_DK_O_48_Hastighetsgrans': {'hastighet': 'Hogsta_tillatna_hastighet'},
    'NVDB_DK_O_105_Antal_korfalt2': {'korfalt': 'Korfaltsantal'},
    'NVDB_DK_O_40_TattbebyggtOmrade': {'tattbebyggt': 'ELEMENT_ID'},
    'NVDB_DK_O_38_FunkVagklass': {'klass': 'Klass'},
    'NVDB_DK_O_2_Vaghallare': {'vaghallare': 'Vaghallartyp'},
    'NVDB_DK_O_100_Gatutyp': {'gatutyp': 'Typ', 'uppsamlande': 'Uppsamlande'},
    'NVDB_DK_O_113_Forbud_omkorn': {'omkorningsforbud': 'ELEMENT_ID'},
    'NVDB_DK_O_111_Vagnummer': {'vagnummer': 'Huvudnummer'},
    'NVDB_DK_O_99_GCM_vagtyp': {'gcm': 'Gcm_typ'},
}


def _wkb(b):
    flags = b[3]
    env = (flags >> 1) & 7
    return bytes(b[8 + {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}[env]:])


def _las_lager(con, tabell, kolumner, ruta):
    finns = {r[0] for r in con.execute("select name from sqlite_master where type='table'")}
    if tabell not in finns:
        return []
    kol = ', '.join(f't."{c}"' for c in kolumner.values())
    rt = f'rtree_{tabell}_geom'
    if rt in finns:
        q = (f'select t.geom, {kol} from "{tabell}" t join "{rt}" r on t.id = r.id '
             f'where r.maxx >= ? and r.minx <= ? and r.maxy >= ? and r.miny <= ?')
        rader = con.execute(q, (ruta[0], ruta[2], ruta[1], ruta[3]))
    else:   # utan rumsligt index (beläggningsfilen): läs allt och sålla
        rader = con.execute(f'select t.geom, {kol} from "{tabell}" t')
    ruta_g = box(*ruta)
    ut = []
    for rad in rader:
        if rad[0] is None:
            continue
        g = shapely.force_2d(shapely.from_wkb(_wkb(rad[0])))
        if g.intersects(ruta_g):
            ut.append((g, dict(zip(kolumner, rad[1:]))))
    return ut


def utdrag(ruta, work):
    """{lager: [(LineString, {egenskap: värde})]} inom rutan (+ marginal), cachat i work/nvdb.pkl."""
    fil = Path(work) / 'nvdb.pkl'
    ruta = tuple(float(v) for v in ruta)
    if fil.exists():
        d = pickle.load(open(fil, 'rb'))
        if d.get('ruta') == ruta and d.get('kalla_mtime') == _mtime():
            return d['lager']
    if not NVDB_FIL.exists():
        print('nvdb: hittar inte', NVDB_FIL, '- vägarna byggs ur OSM')
        return {}
    r = (ruta[0] - MARGINAL_M, ruta[1] - MARGINAL_M, ruta[2] + MARGINAL_M, ruta[3] + MARGINAL_M)
    lager = {}
    con = sqlite3.connect(f'file:{NVDB_FIL}?mode=ro', uri=True)
    for tabell, kol in LAGER.items():
        lager[tabell] = _las_lager(con, tabell, kol, r)
    con.close()
    if BELAGGNING_FIL.exists():
        con = sqlite3.connect(f'file:{BELAGGNING_FIL}?mode=ro', uri=True)
        lager['belaggning'] = _las_lager(con, 'BelaggningSenaste', {'datum': 'BelaggningsDatum', 'typ': 'BelaggningsTyp'}, r)
        con.close()
    pickle.dump(dict(ruta=ruta, kalla_mtime=_mtime(), lager=lager), open(fil, 'wb'))
    print('nvdb:', ', '.join(f'{k.split("_O_")[-1]} {len(v)}' for k, v in lager.items()))
    return lager


def _mtime():
    return (NVDB_FIL.stat().st_mtime if NVDB_FIL.exists() else 0,
            BELAGGNING_FIL.stat().st_mtime if BELAGGNING_FIL.exists() else 0)


class Matchning:
    """Egenskaper per vägpunkt: närmaste NVDB-bit med liknande riktning."""

    def __init__(self, lager):
        self.lager = {}
        for namn, rader in lager.items():
            A, B, attr = [], [], []
            for g, a in rader:
                for part in getattr(g, 'geoms', [g]):
                    c = np.asarray(part.coords)
                    if len(c) < 2:
                        continue
                    A.append(c[:-1]); B.append(c[1:]); attr += [a] * (len(c) - 1)
            if not A:
                continue
            A, B = np.vstack(A), np.vstack(B)
            segs = shapely.linestrings(np.stack([A, B], axis=1))
            self.lager[namn] = [shapely.STRtree(segs), A, B, attr, np.zeros(len(A), bool)]
        # bitar som ligger på en gång- och cykelväg (NVDB:s GCM-typ) används inte för bilvägar
        if 'NVDB_DK_O_99_GCM_vagtyp' in self.lager:
            gtree, gA, gB, gattr, _ = self.lager['NVDB_DK_O_99_GCM_vagtyp']
            for namn, (tree, A, B, attr, gc) in self.lager.items():
                if namn == 'NVDB_DK_O_99_GCM_vagtyp':
                    continue
                mitt = shapely.points((A + B) / 2)
                ip, _ = gtree.query(mitt, predicate='dwithin', distance=1.0)
                gc[np.unique(ip)] = True

    def __bool__(self):
        return bool(self.lager)

    def egenskaper(self, pts, riktning, namn, gcm=False, bil=False):
        """Lista med dict (eller None) per punkt. riktning: enhetsvektorer (n, 2).
        gcm=True: tvärgående bitar räknas också (övergångsställen korsar vägen).
        bil=True: bitar på gång- och cykelvägar räknas inte."""
        ut = [None] * len(pts)
        if namn not in self.lager:
            return ut
        tree, A, B, attr, gc = self.lager[namn]
        p = shapely.points(pts)
        ip, js = tree.query(p, predicate='dwithin', distance=MAX_AVSTAND_M)
        if len(ip) == 0:
            return ut
        AB = B[js] - A[js]
        L2 = np.maximum((AB ** 2).sum(1), 1e-9)
        t = np.clip(((pts[ip] - A[js]) * AB).sum(1) / L2, 0, 1)
        d = np.linalg.norm(A[js] + AB * t[:, None] - pts[ip], axis=1)
        cos = np.abs((AB / np.sqrt(L2)[:, None] * riktning[ip]).sum(1))
        ok = np.ones(len(ip), bool) if gcm else cos >= np.cos(np.radians(MAX_VINKEL_DEG))
        if bil:
            ok &= ~gc[js]
        kost = d + (1 - cos) * 6.0
        kost[~ok] = np.inf
        ordning = np.lexsort((kost, ip))
        sett = set()
        for k in ordning:
            i = ip[k]
            if i in sett or not np.isfinite(kost[k]):
                continue
            sett.add(i)
            ut[i] = attr[js[k]]
        return ut


# ---------- vägarnas egenskaper ur NVDB (step3) ----------
GC = ('path', 'footway', 'cycleway', 'steps', 'bridleway', 'pedestrian')
KLASS_BREDD = {0: 10.0, 1: 9.0, 2: 8.0, 3: 7.5, 4: 7.0, 5: 6.5, 6: 6.0, 7: 5.5, 8: 4.5, 9: 3.5}
UTJAMNA_BREDD_M = 40.0      # löpande median längs vägen (NVDB-bredden hoppar vid korsningar och fickor)


def _lopande_median(v, fonster):
    if len(v) <= 2 or fonster <= 1:
        return v
    h = fonster // 2
    p = np.pad(v, h, mode='edge')
    return np.median(np.lib.stride_tricks.sliding_window_view(p, 2 * h + 1), axis=1)[:len(v)]


def _tal(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return np.nan


def berika(roads, M, osm_bredd):
    """Sätter per väg (punkter var ~2 m som i step3): r['hw'] halva bredden, r['hastighet'] (km/h, nan =
    okänd), r['tatt'], r['klass'], r['omkf'] (omkörningsförbud), r['vagnr'], r['bel_ar'] (beläggningsår)
    och r['width'] (median), samt r['surface'] ur slitlagret. Utan NVDB: OSM-bredden överallt."""
    n_nv = 0
    for r in roads:
        L = r['line']
        n = max(2, int(L.length / 2) + 1)
        pts = np.array([L.interpolate(d).coords[0] for d in np.linspace(0, L.length, n)])
        dv = np.gradient(pts, axis=0)
        dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
        hw = r['tags']['highway']
        bas = osm_bredd(r)
        r['hw'] = np.full(n, bas / 2)
        r['hastighet'] = np.full(n, np.nan)
        r['tatt'] = np.zeros(n, bool)
        r['klass'] = np.full(n, np.nan)
        r['omkf'] = np.zeros(n, bool)
        r['vagnr'] = np.zeros(n, bool)
        r['bel_ar'] = np.full(n, np.nan)
        if not M or hw in GC:
            continue
        e = lambda lager: M.egenskaper(pts, dv, lager, bil=True)
        bredd = np.array([_tal((a or {}).get('bredd')) for a in e('NVDB_DK_O_31_Vagbredd')])
        klass = np.array([_tal((a or {}).get('klass')) for a in e('NVDB_DK_O_38_FunkVagklass')])
        r['klass'] = klass
        r['hastighet'] = np.array([_tal((a or {}).get('hastighet')) for a in e('NVDB_DK_O_48_Hastighetsgrans')])
        r['tatt'] = np.array([a is not None for a in e('NVDB_DK_O_40_TattbebyggtOmrade')])
        r['omkf'] = np.array([a is not None for a in e('NVDB_DK_O_113_Forbud_omkorn')])
        r['vagnr'] = np.array([a is not None for a in e('NVDB_DK_O_111_Vagnummer')])
        r['bel_ar'] = np.array([_tal(str((a or {}).get('datum') or '')[:4]) for a in e('belaggning')])
        slit = [(a or {}).get('slitlager') for a in e('NVDB_DK_O_30_Slitlager')]
        b = np.where(np.isfinite(bredd), bredd,
                     np.array([KLASS_BREDD.get(int(k), bas) if np.isfinite(k) else bas for k in klass]))
        # OSM:s bredd vinner om den är satt (sällan), och en bostadsgata blir aldrig smalare än OSM-tabellen
        if 'width' in r['tags'] and np.isfinite(_tal(r['tags']['width'])):
            b[:] = _tal(r['tags']['width'])
        # NVDB och OSM delar körbanor olika (Haningeleden: en NVDB-länk, två enkelriktade OSM-vägar och
        # tvärtom), så bredden hålls inom vad OSM:s körfält rymmer: 3,0-3,75 m per körfält plus vägren
        try:
            korfalt = int(r['tags'].get('lanes', '0'))
        except ValueError:
            korfalt = 0
        if korfalt > 0:
            enkel = r['tags'].get('oneway') in ('yes', '1', '-1')
            b = np.clip(b, korfalt * 3.0, korfalt * 3.75 + (1.5 if enkel else 3.0))
        b = _lopande_median(np.clip(b, 2.5, 14.0), int(UTJAMNA_BREDD_M / 2) | 1)
        r['hw'] = b / 2
        r['width'] = float(np.median(b))
        if any(slit):
            grus = sum(s == 'grus' for s in slit) > sum(s == 'belagd' for s in slit)
            r['surface'] = 'grus' if grus else 'asfalt'
        n_nv += np.isfinite(klass).any()
    print('nvdb: vägar med NVDB-data', n_nv, 'av', len(roads))


# ---------- harmonisering: en bredd per gata, körbanor som inte går in i varandra ----------
INTE_GRANNE = GC + ('service', 'track')
PARALLELL_DEG = 25.0
MIN_HW = 1.6


def harmonisera(roads):
    """Avslappnade regler ovanpå NVDB (step3, efter berika):
    1. sammanhängande vägar med samma namn/nummer och enkelriktning får samma bredd
       (medianen), så att bredden inte hoppar i trappsteg där NVDB-sträckorna byter;
    2. i skarvar där bara två vägar möts glider bredden över OVERGANG_M mot grannens (där två
       enkelriktade körbanor går ihop till en dubbelriktad väg: mot halva dess bredd);
    3. parallella körbanor (inom 25°) går inte in i varandra: halva bredden kapas till halva avståndet
       (minst MIN_HW), och r['granne'] (n, 2) säger på vilken sida [vänster, höger] en grannkörbana
       ligger kant i kant, så att vagmarkering inte drar kantlinje mot den."""
    bil = [k for k, r in enumerate(roads) if r['tags']['highway'] not in GC and not r.get('rondell')]
    # 1. kedjor
    def nyckel(r):
        t = r['tags']
        namn = t.get('name') or t.get('ref')
        return None if not namn else (namn, t.get('oneway') in ('yes', '1', '-1'))
    grupper = {}
    for k in bil:
        n = nyckel(roads[k])
        if n is not None:
            grupper.setdefault(n, []).append(k)
    n_kedjor = 0
    for lista in grupper.values():
        # sammanhängande delar (ändpunkter inom 1 m)
        forald = {k: k for k in lista}
        def rot(k):
            while forald[k] != k:
                forald[k] = forald[forald[k]]
                k = forald[k]
            return k
        andar = [(k, np.array(roads[k]['line'].coords[e])) for k in lista for e in (0, -1)]
        for i in range(len(andar)):
            for j in range(i + 1, len(andar)):
                if np.linalg.norm(andar[i][1] - andar[j][1]) < 1.0:
                    forald[rot(andar[i][0])] = rot(andar[j][0])
        kedjor = {}
        for k in lista:
            kedjor.setdefault(rot(k), []).append(k)
        for kedja in kedjor.values():
            b = float(np.median(np.concatenate([roads[k]['hw'] for k in kedja]))) * 2
            for k in kedja:
                roads[k]['hw'] = np.full(len(roads[k]['hw']), b / 2)
                roads[k]['width'] = b
            n_kedjor += 1
    # 2. mjuka övergångar i skarvarna: bredden glider över OVERGANG_M mot grannens bredd
    _skarvar(roads, bil)
    # 3. parallella körbanor
    grannar = [k for k in bil if roads[k]['tags']['highway'] not in INTE_GRANNE]
    tree = shapely.STRtree([roads[k]['line'] for k in grannar])
    max_hw = max((float(roads[k]['hw'].max()) for k in grannar), default=0.0)
    n_kap = 0
    for k in bil:
        r = roads[k]
        L = r['line']
        n = len(r['hw'])
        r['granne'] = np.zeros((n, 2), bool)
        if r['tags']['highway'] in INTE_GRANNE:
            continue
        pts = np.array([L.interpolate(d).coords[0] for d in np.linspace(0, L.length, n)])
        dv = np.gradient(pts, axis=0)
        dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
        nrm = np.c_[-dv[:, 1], dv[:, 0]]
        hw = r['hw'].copy()
        kandidater = [grannar[i] for i in tree.query(L, predicate='dwithin', distance=float(hw.max()) + max_hw + 1.5)
                      if grannar[i] != k]
        for j in kandidater:
            Lj = roads[j]['line']
            for i in range(n):
                p = shapely.Point(pts[i])
                d = Lj.distance(p)
                hj = float(np.interp(Lj.project(p), np.linspace(0, Lj.length, len(roads[j]['hw'])), roads[j]['hw']))
                if d > hw[i] + hj + 1.0 or d < 0.5:
                    continue
                pa = Lj.project(p)
                q = np.array(Lj.interpolate(pa).coords[0])
                vj = np.array(Lj.interpolate(min(pa + 1, Lj.length)).coords[0]) - np.array(Lj.interpolate(max(pa - 1, 0)).coords[0])
                vj /= max(np.linalg.norm(vj), 1e-9)
                if abs(float(np.dot(vj, dv[i]))) < np.cos(np.radians(PARALLELL_DEG)):
                    continue   # korsande väg: inte en grannkörbana
                sida = 0 if np.dot(q - pts[i], nrm[i]) > 0 else 1
                r['granne'][i, sida] = True
                ny = max(min(hw[i], d / 2), MIN_HW)
                if ny < hw[i] - 0.05:
                    hw[i] = ny
                    n_kap += 1
        if (hw < r['hw']).any():
            r['hw'] = np.minimum(r['hw'], _lopande_median(hw, 9))
    print(f'vägar: {n_kedjor} gator med en bredd, {n_kap} punkter kapade mot grannkörbanor')


OVERGANG_M = 30.0


def _enkel(r):
    return r['tags'].get('oneway') in ('yes', '1', '-1')


def _skarvar(roads, bil):
    andar = [(k, e, np.array(roads[k]['line'].coords[0 if e == 0 else -1])) for k in bil for e in (0, 1)]
    if not andar:
        return
    P = np.array([p for _, _, p in andar])
    from scipy.spatial import cKDTree
    tr = cKDTree(P)
    bredd = {k: float(np.median(roads[k]['hw'])) * 2 for k in bil}
    mal = []   # (väg, ände, målbredd)
    for (k, e, p) in andar:
        grannar = [andar[i][0] for i in tr.query_ball_point(p, 1.0) if andar[i][0] != k]
        if roads[k]['tags']['highway'] in INTE_GRANNE:
            continue
        grannar = [j for j in grannar if roads[j]['tags']['highway'] not in INTE_GRANNE]
        if len(grannar) > 1:   # korsning: fortsättningen är vägen med samma namn (om den är entydig)
            namn = roads[k]['tags'].get('name') or roads[k]['tags'].get('ref')
            samma = [j for j in grannar if namn and (roads[j]['tags'].get('name') or roads[j]['tags'].get('ref')) == namn]
            if len(samma) == 1 and _enkel(roads[samma[0]]) == _enkel(roads[k]):
                grannar = samma
        if len(grannar) == 1:
            j = grannar[0]
            if _enkel(roads[k]) == _enkel(roads[j]):
                mal.append((k, e, (bredd[k] + bredd[j]) / 2))
            elif _enkel(roads[k]):
                mal.append((k, e, bredd[j] / 2))
        elif len(grannar) == 2 and _enkel(roads[k]) and not all(_enkel(roads[j]) for j in grannar):
            # två körbanor möter en dubbelriktad väg: den här och den andra körbanan delar på den
            j = next(j for j in grannar if not _enkel(roads[j]))
            mal.append((k, e, bredd[j] / 2))
    for k, e, b in mal:
        r = roads[k]
        n = len(r['hw'])
        d = np.linspace(0, r['line'].length, n)
        if e == 1:
            d = r['line'].length - d
        L = min(OVERGANG_M, r['line'].length / 2)
        w = np.clip(1 - d / max(L, 1e-6), 0, 1)
        w = w * w * (3 - 2 * w)
        r['hw'] = r['hw'] + (b / 2 - r['hw'][0 if e == 0 else -1]) * w
