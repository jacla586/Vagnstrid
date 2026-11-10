"""Vägmarkeringar enligt förenklade svenska regler (step3, efter vägmesharna).

Per väg (punkter var ~2 m, egenskaper från nvdb.berika):
  mittlinje   3 m streck, 9 m lucka: belagd väg minst MITT_MIN_BREDD bred med 60 km/h eller mer,
              eller en uppsamlande/större väg (funktionell klass <= 5 eller vägnummer) från 40 km/h
  varningslinje 9 + 3: före korsningar och före spärrlinjer (VARNING_M, längre från 70 km/h)
  spärrlinje  heldragen: omkörningsförbud (NVDB) eller för kort sikt över krön och i kurvor
              (SIKT_KRAV_M per hastighet, ögon och mötande bil 1,1 m över vägen)
  kantlinje   1 + 2, 0,3 m in från kanten (högst 3,75 m från mitten, vägrenen utanför): minst KANT_MIN_BREDD bred och 70 km/h eller mer
  övergångsställe: NVDB-GCM "Övergångsställe" som korsar vägen, och OSM highway=crossing med
              crossing=uncontrolled/marked/zebra/traffic_signals eller crossing:markings (inte unmarked/no)
              på en asfalterad bilväg (inom OVERGANG_SAMMA_M av ett annat räknas som samma) -> block
              0,5 m breda, 3 m långa; listan `overgangar` får vagkant.py (skyltar)
Enkelriktade körbanor (oneway, t.ex. vägar med mittremsa): ingen spärr, körfältslinje 3 + 9 bara med
lanes >= 2, kantlinjer från 60 km/h. Tvåfältsvägar med lanes=1 får ingen mittlinje.
Inga linjer i korsningar (kortare än korsande vägens halva bredd + 3 m från korsningspunkten) eller i
cirkulationsplatser. Markeringarna läggs 1,5 cm över vägytan i gruppen Vagar (ingen kollision).
"""
import numpy as np
import shapely
from shapely.geometry import Point
import trimesh

MITT_MIN_BREDD = 5.8
KANT_MIN_BREDD = 6.5
LINJE_B_MITT, LINJE_B_KANT = 0.12, 0.10
KANT_IN_M = 0.3
KORFALT_MAX_M = 3.75   # kantlinjen skiljer körfältet från vägrenen: högst så här långt från mitten
LYFT = 0.015
VARNING_M = {True: 60.0, False: 35.0}           # >= 70 km/h : lägre
SIKT_KRAV_M = [(90, 350.0), (80, 300.0), (70, 250.0), (60, 200.0)]
OGA_M = 1.1
SIKT_FONSTER_M = 400.0
KORSNING_TOL_M = 1.5
UTAN_LINJER = ('path', 'footway', 'cycleway', 'steps', 'bridleway', 'pedestrian', 'track',
               'service', 'living_street')
import os
DEBUG = [x for x in os.environ.get('VAGMARK_DEBUG', '').split(',') if x]
SKALA = 0.5   # beräkningssteg (m) längs vägen för streckmönstret


def _sikt_krav(v):
    for grans, krav in SIKT_KRAV_M:
        if v >= grans:
            return krav
    return 0.0


def _sikt(s, z, pts, hw):
    """Siktsträcka framåt (m) per punkt: krön (vägytan skymmer) och kurvor (kurvans båge går mer än
    halva bredden + 4 m från siktlinjen, så kanten skymmer)."""
    n = len(s)
    ut = np.full(n, np.inf)
    steg = max(1, int(SIKT_FONSTER_M / max(s[1] - s[0], 0.5)))
    for i in range(n - 2):
        j = np.arange(i + 1, min(n, i + steg))
        d = s[j] - s[i]
        oga = z[i] + OGA_M
        mark = (z[j] - oga) / d
        mal = (z[j] + OGA_M - oga) / d
        hinder = np.maximum.accumulate(mark)
        skymd = np.zeros(len(j), bool)
        skymd[1:] = mal[1:] < hinder[:-1]
        # kurva: mittpunkten mellan i och j jämfört med kordan
        m = (i + j) // 2
        A, B, C = pts[i], pts[j], pts[m]
        ab = B - A
        L = np.maximum(np.linalg.norm(ab, axis=1), 1e-6)
        avv = np.abs(ab[:, 0] * (C[:, 1] - A[1]) - ab[:, 1] * (C[:, 0] - A[0])) / L
        skymd |= avv > hw[i] + 4.0
        if skymd.any():
            ut[i] = d[np.argmax(skymd)]
    return ut


OVERGANG_SAMMA_M = 10.0
OVERGANG_MALAT = ('uncontrolled', 'marked', 'zebra', 'traffic_signals')


def malat_overgangsstalle(t):
    """OSM highway=crossing som är ett målat övergångsställe (svensk praxis: uncontrolled = zebra)."""
    if t.get('highway') != 'crossing':
        return False
    m = t.get('crossing:markings')
    if m in ('no', 'surface'):
        return False
    return t.get('crossing') in OVERGANG_MALAT or t.get('crossing_ref') == 'zebra' or m not in (None, 'no')


class Markering:
    def __init__(self, roads, M, punkter=None):
        self.roads = roads
        self.M = M
        self.punkter = [(pt, t) for pt, t in (punkter or []) if malat_overgangsstalle(t)]
        # övergångsställen: dict(p (SWEREF på vägens mitt), d (vägens riktning), hw, ljus, enkel)
        self.overgangar = []
        bil = [k for k, r in enumerate(roads) if r['tags']['highway'] not in UTAN_LINJER[:6]]
        self.bil = bil
        self.tree = shapely.STRtree([roads[k]['line'] for k in bil])
        # korsningar räknas bara mellan gator: infarter, parkeringar och skogsvägar bryter inga linjer
        self.gator = [k for k in bil if roads[k]['tags']['highway'] not in ('service', 'track')]
        self.gtree = shapely.STRtree([roads[k]['line'] for k in self.gator])
        self.korsningar = self._korsningar()
        self.malad_m = 0.0

    def _korsningar(self):
        """Punkter där minst tre vägändar möts eller en väg slutar mot en annan vägs mitt: (x, y, radie)."""
        ut = []
        for k in self.gator:
            r = self.roads[k]
            for p in (r['line'].coords[0], r['line'].coords[-1]):
                idx = self.gtree.query(Point(p), predicate='dwithin', distance=KORSNING_TOL_M)
                ror = [self.gator[i] for i in idx]
                andar = 0
                genom = False
                for j in ror:
                    lj = self.roads[j]['line']
                    pp = Point(p)
                    if pp.distance(Point(lj.coords[0])) < KORSNING_TOL_M or pp.distance(Point(lj.coords[-1])) < KORSNING_TOL_M:
                        andar += 1
                    else:
                        genom = True
                if andar >= 3 or genom:
                    radie = max(self.roads[j]['width'] for j in ror) / 2 + 3.0
                    ut.append((p[0], p[1], radie))
        return np.array(ut) if ut else np.zeros((0, 3))

    def bygg(self, add_merged, mat, to_world):
        self.to_world = to_world
        vit = mat('Vagmarkering', (232, 232, 226), 0.6)
        n_m = n_s = n_k = 0
        for k in self.bil:
            r = self.roads[k]
            if r['surface'] != 'asfalt' or 'pts' not in r or r['tags'].get('junction') == 'roundabout' \
                    or r['tags']['highway'] in UTAN_LINJER:
                continue
            res = self._vag(r)
            if res is None:
                continue
            V, F = res
            if len(F):
                add_merged('Vagar', trimesh.Trimesh(V, F, process=False), vit)
                n_m += 1
        n_o = self._overgangsstallen(add_merged, vit, to_world)
        print(f'vägmarkeringar: {n_m} vägar, {self.malad_m / 1000:.1f} km målad linje, {len(self.korsningar)} korsningar, '
              f'{n_o} övergångsställen')

    def _vag(self, r):
        pts, s, hw, zm = r['pts'], r['s'], r['hw'], r['zm']
        n = len(pts)
        v = r['hastighet'].copy()
        v[~np.isfinite(v)] = np.where(r['tatt'][~np.isfinite(v)], 50.0, 70.0)
        b = hw * 2
        t = r['tags']
        enkel = t.get('oneway') in ('yes', '1', '-1') or t.get('junction') == 'roundabout'
        try:
            korfalt = int(t.get('lanes', '0'))
        except ValueError:
            korfalt = 0
        stor = (r['klass'] <= 5) | r['vagnr']
        if enkel:   # en körbana i ett hål (t.ex. Haningeleden): körfältslinje bara med två körfält
            mitt = np.full(n, korfalt >= 2) & (b >= 5.5)
            kant = (b >= 3.0) & (v >= 60)
        else:
            mitt = (b >= MITT_MIN_BREDD) & ((v >= 60) | (stor & (v >= 40))) & (korfalt != 1)
            kant = (b >= KANT_MIN_BREDD) & (v >= 70)
        if DEBUG and r['tags'].get('name') in DEBUG:
            print('  debug', r['tags'].get('name'), t.get('oneway'), t.get('lanes'), 'bredd', np.round(np.median(b), 1),
                  'v', np.nanmedian(r['hastighet']), 'klass', np.nanmedian(r['klass']), 'mitt', round(mitt.mean(), 2),
                  'kant', round(kant.mean(), 2), 'yta', r['surface'])
        if not mitt.any() and not kant.any():
            return None
        # spärr: omkörningsförbud eller kort sikt åt något håll (inte på enkelriktade körbanor)
        sparr = r['omkf'] & mitt & (not enkel)
        krav = np.array([_sikt_krav(x) for x in v]) * (not enkel)
        if (krav > 0).any() and n > 3:
            fram = _sikt(s, zm, pts, hw)
            bak = _sikt(s[-1] - s[::-1], zm[::-1], pts[::-1], hw[::-1])[::-1]
            sparr |= mitt & (np.minimum(fram, bak) < krav)
        sparr = _rensa_korta(sparr, s, 30.0)
        # korsningar: inga linjer nära, varningslinje före
        dk = np.full(n, np.inf)
        if len(self.korsningar):
            d = np.linalg.norm(pts[:, None, :] - self.korsningar[None, :, :2], axis=2)
            inom = d < self.korsningar[None, :, 2]
            fri = ~inom.any(1)
            # avstånd längs vägen till närmaste korsningszon
            zon = np.where(~fri)[0]
            if len(zon):
                dk = np.min(np.abs(s[:, None] - s[zon][None, :]), axis=1)
        else:
            fri = np.ones(n, bool)
        dsp = np.full(n, np.inf)
        kanter = np.where(np.diff(sparr.astype(int)) != 0)[0]
        if len(kanter):
            dsp = np.min(np.abs(s[:, None] - s[kanter][None, :]), axis=1)
        varn = mitt & ~sparr & ((dk < np.where(v >= 70, VARNING_M[True], VARNING_M[False])) |
                                (dsp < np.where(v >= 70, VARNING_M[True], VARNING_M[False])))
        typ = np.where(sparr, 3, np.where(varn, 2, np.where(mitt, 1, 0)))
        typ[~fri] = 0
        kant = kant & fri
        # fint rutnät längs vägen
        sf = np.arange(0, s[-1], SKALA)
        if len(sf) < 2:
            return None
        ix = np.clip(np.searchsorted(s, sf), 0, n - 1)
        tf = typ[ix]
        fas = sf % 12.0
        malad = (tf == 3) | ((tf == 1) & (fas < 3.0)) | ((tf == 2) & (fas < 9.0))
        kf = kant[ix] & ((sf % 3.0) < 1.0)
        # ingen kantlinje mot en grannkörbana som ligger kant i kant (nvdb.harmonisera)
        granne = r.get('granne', np.zeros((n, 2), bool))[ix]
        kv, kh = kf & ~granne[:, 0], kf & ~granne[:, 1]
        V, F = [], []
        for mask, off_fn, bredd in ((malad, lambda i: 0.0, LINJE_B_MITT),
                                    (kv, lambda i: 1.0, LINJE_B_KANT), (kh, lambda i: -1.0, LINJE_B_KANT)):
            for a, bb in _intervall(mask):
                self._remsa(r, sf[a], min(sf[bb] + SKALA, s[-1]), off_fn(0), bredd, V, F)
                self.malad_m += min(sf[bb] + SKALA, s[-1]) - sf[a]
        if not F:
            return np.zeros((0, 3)), np.zeros((0, 3), int)
        return np.vstack(V), np.vstack(F)

    def _remsa(self, r, s0, s1, sida, bredd, V, F):
        """En målad remsa från s0 till s1. sida 0 = mitten, ±1 = kantlinje (KANT_IN_M in från kanten)."""
        if s1 - s0 < 0.2:
            return
        s, pts, nrm, zm, hw = r['s'], r['pts'], r['nrm'], r['zm'], r['hw']
        ss = np.r_[s0, s[(s > s0) & (s < s1)], s1]
        x = np.interp(ss, s, pts[:, 0]); y = np.interp(ss, s, pts[:, 1])
        nx = np.interp(ss, s, nrm[:, 0]); ny = np.interp(ss, s, nrm[:, 1])
        ln = np.maximum(np.hypot(nx, ny), 1e-9); nx /= ln; ny /= ln
        z = np.interp(ss, s, zm) + LYFT
        kant_max = np.inf if r['tags'].get('oneway') in ('yes', '1', '-1') else KORFALT_MAX_M
        off = sida * np.minimum(np.interp(ss, s, hw) - KANT_IN_M, kant_max)
        cx, cy = x + nx * off, y + ny * off
        L = self.to_world(cx + nx * bredd / 2, cy + ny * bredd / 2)
        R = self.to_world(cx - nx * bredd / 2, cy - ny * bredd / 2)
        m = len(ss)
        Vv = np.empty((2 * m, 3))
        Vv[0::2] = np.c_[L[0], z, L[1]]
        Vv[1::2] = np.c_[R[0], z, R[1]]
        a = np.arange(m - 1) * 2
        Ff = np.r_[np.c_[a, a + 1, a + 2], np.c_[a + 1, a + 3, a + 2]]
        tri = Vv[Ff]
        ny_ = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])[:, 1]
        Ff[ny_ < 0] = Ff[ny_ < 0][:, ::-1]
        base = sum(len(v) for v in V)
        V.append(Vv); F.append(Ff + base)

    def _overgangsstallen(self, add_merged, vit, to_world):
        """NVDB:s övergångsställen först, sedan OSM:s som inte redan finns."""
        V, F = [], []
        if self.M and 'NVDB_DK_O_99_GCM_vagtyp' in self.M.lager:
            tree, A, B, attr, _ = self.M.lager['NVDB_DK_O_99_GCM_vagtyp']
            for a, b, at in zip(A, B, attr):
                if at.get('gcm') != 'Övergångsställe':
                    continue
                seg = shapely.linestrings([a, b])
                for i in self.tree.query(seg, predicate='intersects'):
                    r = self.roads[self.bil[i]]
                    if not self._malbar(r):
                        continue
                    p = r['line'].intersection(seg)
                    if p.is_empty or p.geom_type != 'Point':
                        continue
                    self._overgang(r, r['line'].project(p), False, V, F)
        for pt, t in self.punkter:
            for i in self.tree.query(pt, predicate='dwithin', distance=12.0):
                r = self.roads[self.bil[i]]
                if not self._malbar(r):
                    continue
                sp = r['line'].project(pt)
                if r['line'].distance(pt) > float(np.interp(sp, r['s'], r['hw'])) + 1.0:
                    continue
                ljus = t.get('crossing') == 'traffic_signals' or t.get('crossing:signals') == 'yes'
                self._overgang(r, sp, ljus, V, F)
                break
        if F:
            add_merged('Vagar', trimesh.Trimesh(np.vstack(V), np.vstack(F), process=False), vit)
        return len(self.overgangar)

    def _malbar(self, r):
        return r['surface'] == 'asfalt' and 'pts' in r and r['tags']['highway'] not in UTAN_LINJER

    def _overgang(self, r, sp, ljus, V, F):
        """Ett övergångsställe vid sp på r (om inget redan finns inom OVERGANG_SAMMA_M): block tvärs över
        vägen, 0,5 m breda med 0,5 m mellanrum, 3 m långa längs vägen."""
        L = r['line']
        p = np.array(L.interpolate(sp).coords[0])
        for o in self.overgangar:
            if np.hypot(*(o['p'] - p)) < OVERGANG_SAMMA_M:
                o['ljus'] = o['ljus'] or ljus
                return
        hw = float(np.interp(sp, r['s'], r['hw']))
        d = np.array(L.interpolate(min(sp + 1, L.length)).coords[0]) - np.array(L.interpolate(max(sp - 1, 0)).coords[0])
        d /= max(np.linalg.norm(d), 1e-9)
        k = 0
        for off in np.arange(-hw + 0.5, hw - 0.4, 1.0):
            self._block(r, sp, off + 0.25, V, F)
            k += 1
        if k:
            self.overgangar.append(dict(p=p, d=d, hw=hw, ljus=ljus,
                                        enkel=r['tags'].get('oneway') in ('yes', '1', '-1')))

    def _block(self, r, sp, off, V, F):
        s, pts, nrm, zm = r['s'], r['pts'], r['nrm'], r['zm']
        d = np.array([np.interp(sp, s, np.gradient(pts[:, 0])), np.interp(sp, s, np.gradient(pts[:, 1]))])
        d /= max(np.linalg.norm(d), 1e-9)
        nn = np.array([-d[1], d[0]])
        c = np.array([np.interp(sp, s, pts[:, 0]), np.interp(sp, s, pts[:, 1])]) + nn * off
        z = float(np.interp(sp, s, zm)) + LYFT
        hor = [c - d * 1.5 - nn * 0.25, c + d * 1.5 - nn * 0.25, c + d * 1.5 + nn * 0.25, c - d * 1.5 + nn * 0.25]
        w = [self.to_world(p[0], p[1]) for p in hor]
        Vv = np.array([[x, z, y] for x, y in w])
        Ff = np.array([[0, 1, 2], [0, 2, 3]])
        tri = Vv[Ff]
        if np.cross(tri[0, 1] - tri[0, 0], tri[0, 2] - tri[0, 0])[1] < 0:
            Ff = Ff[:, ::-1]
        base = sum(len(v) for v in V)
        V.append(Vv); F.append(Ff + base)


def _intervall(mask):
    """(start, slut)-index för sammanhängande sanna delar."""
    if not mask.any():
        return []
    d = np.diff(np.r_[0, mask.astype(int), 0])
    return list(zip(np.where(d == 1)[0], np.where(d == -1)[0] - 1))


def _rensa_korta(mask, s, min_m):
    """Ta bort spärrsträckor kortare än min_m (brus i siktberäkningen)."""
    ut = mask.copy()
    for a, b in _intervall(mask):
        if s[b] - s[a] < min_m:
            ut[a:b + 1] = False
    return ut
