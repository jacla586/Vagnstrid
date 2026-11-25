"""Broar och undergångar.

Lantmäteriets markhöjdmodell har broar och vägbankar över GC-tunnlar borttagna: marken under
dem ligger redan på den lägre nivån. Utan den här modulen fyller vägschaktningen igen sänkan och
vägen dyker ner i den. Här:

1. Broar: vägar med bridge=yes/viaduct/movable får en brobana (hela vägen) med smala räcken och
   pelare under långa spann. Parallella broar tätt intill varandra (väg + cykelbana) slås ihop:
   glipan fylls och de inre räckena tas bort. Små gångbroar är minst GC_BRO_MIN_BREDD breda, i trä.
2. Undergångar: vägar som korsar en väg med tunnel=yes får en rak profil över korsningen. Den
   undre vägen schaktas ned (ramp 12 %) med släntade sidor (1:SLANT) tills den fria höjden räcker;
   schaktet är minst SCHAKT_MIN_BREDD brett i botten, körbart för stridsvagnar. Ett gemensamt
   tunneltak täcker alla vägar som går över (väg, mittremsa, cykelbana), med räcken längs mynningarna.
3. Undergångarnas utseende (efter Mapillary-bilder från Linköping): korta (vägen ovanför täcker högst
   LADA_FRAN_M av gångvägen) blir balkbroar: tjocka kantbalkar vid mynningarna, pelare vid slänternas fot
   och slänterna under och vid bron klädda med gatsten (släntkoner). Längre blir betonglådor: väggar i
   schaktets kanter, betonggolv och lampor i taket, gatsten bara utanför mynningarna.
4. Allt läggs i glb-gruppen Broar (Godot ger den kollision, mesh_collision.gd).

Koordinater: SWEREF 99 TM (x, y) för all geometri; to_world() ger Godot (x, z) vid meshbygget.
"""
import numpy as np
import shapely
from scipy.spatial import cKDTree
from shapely import STRtree
from shapely.geometry import LineString, Point
from shapely.ops import substring
from rasterio.features import rasterize
import trimesh

BRO_TYPER = {'yes', 'viaduct', 'movable'}
GC = {'path', 'footway', 'cycleway', 'steps', 'pedestrian', 'bridleway'}
TRA = {'path', 'footway', 'bridleway', 'steps'}   # små gångbroar i trä
DACK_TJOCKLEK = 0.8      # brobanans tjocklek (m)
TRA_TJOCKLEK = 0.35      # gångbro i trä
TAK_TJOCKLEK = 0.6       # tunneltaket över en undergång
TAK_UNDER_ASFALT_M = 0.06   # tunneltakets ovansida under vägbanan (vägen ritas på profilen över hela taket)
KANTBALK_BRO_B = 0.45    # brobanornas kantbalkar (betong längs kanterna, räcket står på dem)
KANTBALK_BRO_H = 0.22    # över vägbanan
GC_BRO_MIN_BREDD = 2.5   # gångbroar är minst så här breda
TRA_MAX_LANGD = 40.0     # längre gångbroar blir betong
FRI_HOJD_GC = 3.8        # fri höjd under däck för stigar och GC-vägar (körbart för vagnar)
FRI_HOJD_VAG = 4.5       # fri höjd under däck för bilvägar
SCHAKT_MIN_BREDD = 6.0   # schaktets bottenbredd (m), vagnen är 3,2 m
SLANT = 1.5              # schaktets slänter: 1,5 m ut per meter ned
MAX_DJUP = 4.5           # uppskattat största schaktdjup, för takets bredd längs vägen över
RAMP_LUTNING = 0.12      # ramp ner i schaktet (12 %)
RAMP_MAX = 45.0          # hur långt (m) den undre vägen följs åt varje håll från korsningen
MASK_MARGINAL = 6.0      # profilen interpoleras även så här långt utanför spännvidden
ANSLUT_MASK = 8.0        # vägar som ansluter till en bro maskas så här långt från noden
FORLANG = 8.0            # brons ändhöjd tas så här långt utanför bron, i vägens förlängning
FOTAVTRYCK_MARGINAL = 1.0
# Landfästen (landfasten): marken vid varje däckände höjs till däckets ovansida, plant LANDFASTE_PLANT_M ut
# från änden, sedan tonat ned till marken till LANDFASTE_M; under däckets sista LANDFASTE_UNDER_M strax under
# däcket. Förut sjönk marken ofta 0,5-2,5 m precis vid brofästet (åbottnen eller en undergångs schakt nådde
# in dit) och vagnarna fick ett gupp eller fastnade.
LANDFASTE_PLANT_M = 3.0
LANDFASTE_M = 10.0
LANDFASTE_UNDER_M = 3.0
LANDFASTE_SIDA_M = 3.0   # utanför däckets bredd på var sida (gångvägar som korsar däckänden snett, Vallastaden)
# Räckena är smala (stolpar och slanor). Som trianglar med kollision kunde en vagn tryckas igenom och fastna
# grensle, och den osynliga tjocka väggen som ersatte dem (`Kollision_broar`) fastnade vagnarna också i.
# Med en vältbar samling (step3 VALT) blir räckena bitar om ca STOLP_AVSTAND m (glb-gruppen `Valtbart`,
# typerna Brorack*, spelets PropBreak välter dem när en vagn kör in i dem) och har ingen kollision alls;
# kantbalken (0,22 m) är kvar. Utan samling: de gamla räckena och väggen.
KANT_VAGG_H = 1.4
KANT_VAGG_TJOCK = 0.6
RACKE_HOJD = 1.0
RACKE_HOJD_GC = 0.9
STOLPE = 0.08            # räckesstolpar (m i fyrkant), var STOLP_AVSTAND m
STOLP_AVSTAND = 2.0
PELARE_FRAN = 30.0       # pelare under spännvidder längre än så här
PELARE_AVSTAND = 25.0
PELARE_TJOCKLEK = 1.2
PARALLELL_AVSTAND = 8.0  # parallella broar närmare än så här (kant till kant) slås ihop
NOD_TOL = 0.5            # punkter närmare än så här räknas som samma nod
TAK_GLAPP_M = 6.0        # tunneltak för vägar ovanför med mer luft än så här emellan blir separata
LADA_FRAN_M = 18.0       # täckt längd av gångvägen: längre = betonglåda, kortare = balkbro
KANTBALK_H = 1.1         # kantbalken vid mynningen: höjd från däckets ovansida
KANTBALK_D = 0.5
PELARE_U = 0.6           # pelare under kantbalken vid slänternas fot (m i fyrkant)
KON_M = 4.0              # gatstenen fortsätter så här långt utanför mynningarna (släntkon)
GATSTEN_LYFT = 0.05      # gatstenen över terrängen
LADA_VAGG = 0.35
LAMPA_AVSTAND = 6.0


def ar_bro(t):
    return t.get('bridge') in BRO_TYPER


def ar_tunnel(t):
    return t.get('tunnel') == 'yes'


def fri_hojd(t):
    return FRI_HOJD_GC if t['highway'] in GC else FRI_HOJD_VAG


def lyft(t):
    """Vägytans lyft över profilen, samma som vägmesharna i step3."""
    return 0.15 if t['highway'] not in ('path', 'footway') else 0.04


def _punkter(geom):
    if geom.is_empty:
        return []
    if geom.geom_type == 'Point':
        return [geom]
    if hasattr(geom, 'geoms'):
        return [g for g in geom.geoms if g.geom_type == 'Point']
    return []


def _riktning(line, d):
    a = np.array(line.interpolate(max(d - 1.0, 0.0)).coords[0])
    b = np.array(line.interpolate(min(d + 1.0, line.length)).coords[0])
    v = b - a
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else np.array([1.0, 0.0])


def _sin(u, v):
    return abs(float(u[0] * v[1] - u[1] * v[0]))


def _nara_ande(line, p):
    c = line.coords
    return Point(c[0]).distance(p) < NOD_TOL or Point(c[-1]).distance(p) < NOD_TOL


def _bitar(mask):
    """(start, slut) för sammanhängande sanna bitar i en bool-array."""
    ut, i, n = [], 0, len(mask)
    while i < n:
        if not mask[i]:
            i += 1
            continue
        e = i
        while e + 1 < n and mask[e + 1]:
            e += 1
        ut.append((i, e))
        i = e + 1
    return ut


def _sla_ihop(spann):
    ut = []
    for s0, s1 in sorted(spann):
        if ut and s0 <= ut[-1][1]:
            ut[-1] = (ut[-1][0], max(ut[-1][1], s1))
        else:
            ut.append((s0, s1))
    return ut


class Broar:
    def __init__(self, roads):
        self.roads = roads
        n = len(roads)
        # rondellernas brobitar (vagnat.rondeller): bara de spannen är bro, inte hela ringen
        self.bro = [ar_bro(r['tags']) or bool(r.get('bro_spann')) for r in roads]
        tun = [ar_tunnel(r['tags']) for r in roads]
        self.spann = {k: [] for k in range(n)}      # (s0, s1) längs vägens mittlinje
        self.anslut = {k: [] for k in range(n)}     # s där vägen ansluter till en bro
        self.korsningar = {}                        # (undre j, övre k, n) -> korsningspunkt
        self.murar = []                             # (punkter Nx2, topp N, botten N, tjocklek)
        self.tak = []                               # (punkter Nx2, topp N, halvbredd N, undre vägens taggar, vägriktning)
        self.schakt = 0
        self.fria_hojder = []
        lines = [r['line'] for r in roads]
        self.tree = STRtree(lines)
        # ändpunkter, för att följa den undre vägen genom anslutande vägar
        self.noder = {}
        for k, L in enumerate(lines):
            for ande, c in ((0, L.coords[0]), (1, L.coords[-1])):
                self.noder.setdefault(self._nyckel(c), []).append((k, ande))

        for k in range(n):
            if not self.bro[k]:
                continue
            Lk = lines[k]
            egna = roads[k].get('bro_spann') or [(0.0, Lk.length)]
            self.spann[k] += egna
            andar = [Lk.interpolate(v).coords[0] for s0, s1 in egna for v in (s0, s1)]
            for c in andar:
                for j in self.tree.query(Point(c).buffer(NOD_TOL)):
                    if j == k or self.bro[j]:
                        continue
                    Lj = lines[j]
                    if Point(Lj.coords[0]).distance(Point(c)) < NOD_TOL:
                        self.anslut[j].append(0.0)
                    elif Point(Lj.coords[-1]).distance(Point(c)) < NOD_TOL:
                        self.anslut[j].append(Lj.length)
            for j in self.tree.query(Lk):
                if j == k or self.bro[j]:
                    continue
                for n_, p in enumerate(_punkter(Lk.intersection(lines[j]))):
                    if _nara_ande(Lk, p) or _nara_ande(lines[j], p):
                        continue
                    if not any(s0 <= Lk.project(p) <= s1 for s0, s1 in egna):
                        continue   # en rondell korsar vägen utanför sina brobitar
                    # en ring kan gå över samma väg två gånger: varje korsning för sig
                    self.korsningar.setdefault((int(j), k, n_), (p.x, p.y))

        for j in range(n):
            if not tun[j]:
                continue
            Lj = lines[j]
            bredd = max(roads[j]['width'], SCHAKT_MIN_BREDD)
            for k in self.tree.query(Lj):
                if k == j or tun[k]:
                    continue
                Lk = lines[k]
                for p in _punkter(Lj.intersection(Lk)):
                    if _nara_ande(Lj, p) or _nara_ande(Lk, p):
                        continue
                    dk = Lk.project(p)
                    sin = _sin(_riktning(Lk, dk), _riktning(Lj, Lj.project(p)))
                    halva = (bredd / 2 + SLANT * MAX_DJUP + 1.0) / max(sin, 0.5)
                    if not self.bro[k]:
                        self.spann[k].append((dk - halva, dk + halva))
                    self.korsningar.setdefault((j, int(k), 0), (p.x, p.y))

        for k in range(n):
            self.spann[k] = _sla_ihop(self.spann[k])
        print('broar: däck på', sum(1 for v in self.spann.values() if v), 'vägar,',
              len(self.korsningar), 'korsningar över/under')

    @staticmethod
    def _nyckel(c):
        return (round(c[0] / NOD_TOL), round(c[1] / NOD_TOL))

    # ---------- profiler ----------
    def pa_dack(self, k, s):
        """True för profilpunkter (s längs vägen) som ligger på ett däck."""
        s = np.asarray(s)
        m = np.zeros(len(s), bool)
        for s0, s1 in self.spann[k]:
            m |= (s >= s0) & (s <= s1)
        return m

    def tak_ytor(self):
        """Tunneltakens fotavtryck (SWEREF) och de undre vägarnas index: vägarna ovanför ritas på
        sin profil (inte på schaktets botten) där de går över ett tak, aldrig under takets ovansida.
        -> [(polygon, {undre}, gångvägens linje, s längs den, takets ovansida per s)]"""
        from shapely.geometry import Polygon as _P
        ut = []
        for (pts, tp, hw, _t, u), info in zip(self.tak, getattr(self, 'tak_info', [])):
            hw = np.broadcast_to(np.asarray(hw, float), (len(pts),))[:, None]
            Lp, Rp = pts + u * hw, pts - u * hw
            p = _P(np.vstack([Lp, Rp[::-1]])).buffer(0)
            if not p.is_empty:
                s_ = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
                ut.append((p, set(info.get('undre', [])), LineString(pts), s_, np.asarray(tp, float)))
        return ut

    def pa_bro(self, k, s):
        """Som pa_dack, men bara för riktiga broar (där vägschaktningen inte får fylla under)."""
        return self.pa_dack(k, s) if self.bro[k] else np.zeros(len(s), bool)

    def justera_profil(self, k, s, z, h_sample):
        """Rak profil över däcken: punkterna på och nära däcken interpoleras från dem utanför."""
        mask = np.zeros(len(s), bool)
        for s0, s1 in self.spann[k]:
            mask |= (s >= s0 - MASK_MARGINAL) & (s <= s1 + MASK_MARGINAL)
        for sa in self.anslut[k]:
            mask |= np.abs(s - sa) <= ANSLUT_MASK
        if not mask.any():
            return z
        sa, za = list(s[~mask]), list(z[~mask])
        if self.bro[k] and not self.roads[k].get('bro_spann'):   # hela vägen är bro: ankare utanför ändarna
            L = self.roads[k]['line']
            c = np.array(L.coords)
            for p, q, s_ankare in ((c[0], c[1], -FORLANG), (c[-1], c[-2], L.length + FORLANG)):
                v = p - q
                v /= max(np.linalg.norm(v), 1e-9)
                x = p + v * FORLANG
                sa.append(s_ankare)
                za.append(float(h_sample([x[0]], [x[1]])[0]))
        if not sa:
            return z
        order = np.argsort(sa)
        z = z.copy()
        z[mask] = np.interp(s[mask], np.asarray(sa)[order], np.asarray(za)[order])
        return z

    def dack_raster(self, shape, transform):
        """Celler under däcken (+ marginal): där schaktar vägen inte terrängen."""
        polys = []
        for k, spann in self.spann.items():
            if not self.bro[k]:
                continue   # vägar över tunnlar schaktas som vanligt; schaktet skärs ut efteråt
            r = self.roads[k]
            for s0, s1 in spann:
                seg = substring(r['line'], max(s0, 0.0), min(s1, r['line'].length))
                if seg.length > 0.1:
                    polys.append(seg.buffer(r['width'] / 2 + FOTAVTRYCK_MARGINAL, cap_style=2))
        if not polys:
            return np.zeros(shape, bool)
        return rasterize([(p, 1) for p in polys], out_shape=shape, transform=transform).astype(bool)

    def landfasten(self, h, shape, transform, OX, OY, RES):
        """Marken vid varje däckände (riktiga broar) höjs till däckets ovansida: plant LANDFASTE_PLANT_M ut,
        tonat ned till den vanliga marken vid LANDFASTE_M; under däckets sista LANDFASTE_UNDER_M strax under
        däcket. Bara höjning, aldrig sänkning (en undergång under däcket rörs inte, men dess schakt och
        slänter fylls igen utanför däckänden, där vägen ligger på marken)."""
        antal = 0
        for k, spann in self.spann.items():
            if not self.bro[k]:
                continue
            r = self.roads[k]
            L = r['line']
            halv = r['width'] / 2 + KANTBALK_BRO_B + LANDFASTE_SIDA_M
            undre = [self.roads[j] for (j, k_, _n) in self.korsningar if k_ == k]   # vägar under: rörs inte
            for s0, s1 in spann:
                s0, s1 = max(s0, 0.0), min(s1, L.length)
                if s1 - s0 < 1.0:
                    continue
                for s_e, inat in ((s0, 1.0), (s1, -1.0)):
                    p = np.array(L.interpolate(s_e).coords[0])
                    v = _riktning(L, s_e) * -inat              # utåt från däcket
                    nv = np.array([-v[1], v[0]])
                    topp = float(np.interp(s_e, r['s'], r['z'])) + lyft(r['tags'])
                    rad = LANDFASTE_M + halv + 2 * RES
                    i0, i1 = int((OY - (p[1] + rad)) / RES), int((OY - (p[1] - rad)) / RES) + 1
                    j0, j1 = int((p[0] - rad - OX) / RES), int((p[0] + rad - OX) / RES) + 1
                    i0, j0 = max(i0, 0), max(j0, 0)
                    i1, j1 = min(i1, shape[0]), min(j1, shape[1])
                    if i0 >= i1 or j0 >= j1:
                        continue
                    ii, jj = np.mgrid[i0:i1, j0:j1]
                    cx, cy = OX + jj * RES, OY - ii * RES
                    t = (cx - p[0]) * v[0] + (cy - p[1]) * v[1]      # utåt längs vägen
                    q = (cx - p[0]) * nv[0] + (cy - p[1]) * nv[1]    # tvärs
                    inne = (np.abs(q) <= halv) & (t >= -LANDFASTE_UNDER_M) & (t <= LANDFASTE_M)
                    if undre and inne.any():
                        punkter = shapely.points(cx[inne], cy[inne])
                        fri = np.zeros(int(inne.sum()), bool)
                        golv = np.zeros(int(inne.sum()), bool)
                        for ru in undre:
                            avst = shapely.distance(punkter, ru['line'])
                            fri |= avst < max(ru['width'], SCHAKT_MIN_BREDD) / 2 + 3.0
                            golv |= avst < ru['width'] / 2 + 0.5
                        # den undre vägen själv rörs aldrig; schaktets botten och slänter lämnas bara längre in under
                        # däcket än LANDFASTE_UNDER_M. Vid däckänden och utanför bär marken vägarna som ansluter där
                        # (gångvägar under Vallastadens broar, road_to_science, grävde annars bort marken vid
                        # brofästet och asfalten och gångvägarna där svävade)
                        inne[inne] = ~(golv | (fri & (t[inne] < -LANDFASTE_UNDER_M)))
                    if not inne.any():
                        continue
                    w = np.clip((t - LANDFASTE_PLANT_M) / (LANDFASTE_M - LANDFASTE_PLANT_M), 0.0, 1.0)
                    w = np.maximum(w, np.clip((np.abs(q) - (halv - LANDFASTE_SIDA_M)) / LANDFASTE_SIDA_M, 0, 1) * 0.5)
                    mal = np.where(t < 0, topp - 0.15, topp)
                    blk = h[i0:i1, j0:j1]
                    ny = np.maximum(blk, mal * (1 - w) + blk * w)
                    blk[inne] = ny[inne]
                    antal += 1
        print(f'broar: {antal} landfästen')

    # ---------- schakt ----------
    def _dack_hojd(self, k, p):
        r = self.roads[k]
        d = r['line'].project(Point(p))
        return float(np.interp(d, r['s'], r['z'])) + lyft(r['tags'])

    def _rutt(self, j, uppe):
        """Den undre vägen förlängd åt båda håll genom anslutande vägar (minst sväng)."""
        coords = [np.array(c) for c in self.roads[j]['line'].coords]
        anvanda = {j} | set(uppe)
        for vid_slutet in (True, False):
            langd = 0.0
            for _ in range(6):
                ande = coords[-1] if vid_slutet else coords[0]
                fore = coords[-2] if vid_slutet else coords[1]
                v = ande - fore
                v /= max(np.linalg.norm(v), 1e-9)
                bast, bast_dot = None, 0.3
                for i, a in self.noder.get(self._nyckel(ande), []):
                    if i in anvanda or self.bro[i]:
                        continue
                    c = [np.array(q) for q in self.roads[i]['line'].coords]
                    if a == 1:
                        c = c[::-1]
                    w = c[1] - c[0]
                    dot = float(np.dot(v, w / max(np.linalg.norm(w), 1e-9)))
                    if dot > bast_dot:
                        bast, bast_dot = (i, c), dot
                if bast is None:
                    break
                i, c = bast
                anvanda.add(i)
                if vid_slutet:
                    coords += c[1:]
                else:
                    coords = c[::-1][:-1] + coords
                langd += self.roads[i]['line'].length
                if langd >= RAMP_MAX:
                    break
        return LineString(coords)

    def schakta(self, h, sample, shape, transform, OX, OY, RES):
        """Sänker terrängen längs de undre vägarna tills den fria höjden under däcken räcker.

        Per undre väg: ett schakt för alla vägar över den. Botten är SCHAKT_MIN_BREDD bred och
        sidorna släntar 1:SLANT, så terrängens 2 m-rutnät ritar dem jämnt. Vägar utan egen bro
        får ett gemensamt tunneltak (self.tak).
        """
        self.schakt_mask = np.zeros(shape, bool)
        self.tak = []
        self.tak_info = []    # per tunneltak: undre vägens rutt, täckt sträcka, schaktbredd, riktningar
        self.pa_tak = set()   # korta broar över en undergång: de ingår i tunneltaket
        per_undre = {}
        for (j, k, _n), p in self.korsningar.items():
            per_undre.setdefault(j, []).append((k, p))
        # undre vägar som är delar av samma undergång (gångvägen uppdelad i flera OSM-vägar) blir
        # en grupp: ett schakt och ett tak för alla vägar över
        rutter = {j: self._rutt(j, {k for k, _ in lista}) for j, lista in per_undre.items()}
        grupp = {j: j for j in per_undre}

        def rot(j):
            while grupp[j] != j:
                j = grupp[j]
            return j
        for j1 in per_undre:
            for j2 in per_undre:
                if j1 < j2 and all(rutter[j1].distance(Point(p)) < 3.0 for _, p in per_undre[j2]) \
                        and rutter[j1].distance(Point(per_undre[j1][0][1])) < 3.0:
                    grupp[rot(j2)] = rot(j1)
        grupper = {}
        for j in per_undre:
            grupper.setdefault(rot(j), []).append(j)
        for j, medlemmar in grupper.items():
            lista = [kp for m_ in medlemmar for kp in per_undre[m_]]
            rutt = max((rutter[m_] for m_ in medlemmar), key=lambda r_: sum(r_.distance(Point(p)) < 3.0 for _, p in lista))
            n = max(2, int(rutt.length) + 1)
            ss = np.linspace(0.0, rutt.length, n)
            pts = np.array([rutt.interpolate(d).coords[0] for d in ss])
            z_r = np.full(n, np.inf)
            bottnar, tak_kanter = [], []
            for k, p in lista:
                rk = self.roads[k]
                topp = self._dack_hojd(k, p)
                kort_bro = self.bro[k] and rk['line'].length <= TRA_MAX_LANGD
                botten = topp - (DACK_TJOCKLEK if self.bro[k] and not kort_bro else TAK_TJOCKLEK)
                s_p = rutt.project(Point(p))
                sin = _sin(_riktning(rk['line'], rk['line'].project(Point(p))), _riktning(rutt, s_p))
                halv = (rk['width'] / 2 + 0.6) / max(sin, 0.5)
                # broar_justera.json (features.py): mer fri höjd under just den här bron
                krav = botten - fri_hojd(self.roads[j]['tags']) - float(rk['tags'].get('_extra_fri_hojd', 0.0))
                z_r = np.minimum(z_r, krav + RAMP_LUTNING * np.maximum(0.0, np.abs(ss - s_p) - halv))
                bottnar.append((botten, s_p))
                if '_extra_fri_hojd' in rk['tags']:
                    print(f"broar: {rk['tags'].get('name', rk['tags']['highway'])} över "
                          f"{self.roads[j]['tags'].get('name', self.roads[j]['tags']['highway'])}: "
                          f"golv {krav:.1f} m, mark nu {float(sample(h, [p[0]], [p[1]])[0]):.1f} m")
                if not self.bro[k] or kort_bro:
                    tak_kanter.append((s_p - halv, s_p + halv, s_p, topp,
                                       _riktning(rk['line'], rk['line'].project(Point(p)))))
                    if kort_bro:
                        self.pa_tak.add(k)
            h_nu = sample(h, pts[:, 0], pts[:, 1])
            schakt = (z_r < h_nu - 0.05).any()
            bredd = max(self.roads[j]['width'], SCHAKT_MIN_BREDD)
            if schakt:
                self.schakt += 1
                djup = float(np.max(h_nu - z_r))
                rad = bredd / 2 + SLANT * max(djup, 0.0) + 2 * RES
                m = rasterize([(rutt.buffer(rad, cap_style=2), 1)], out_shape=shape,
                              transform=transform).astype(bool)
                ii, jj = np.nonzero(m)
                cx, cy = OX + jj * RES, OY - ii * RES
                d, idx = cKDTree(pts).query(np.c_[cx, cy])
                z_schakt = z_r[idx] + np.maximum(0.0, d - bredd / 2) / SLANT
                lagre = z_schakt < h[ii, jj]
                h[ii[lagre], jj[lagre]] = z_schakt[lagre]
                self.schakt_mask[ii[lagre], jj[lagre]] = True
            # ett tak per grupp vägar ovanför som ligger intill varandra: med luft emellan (en rondell
            # över Riksvägen: gångbron norr om ringen och den söder om) blir det två tunnlar, inte ett
            # tak över hela rondellens mitt
            kluster = []
            for kant in sorted(tak_kanter):
                if kluster and kant[0] <= max(b for _, b, *_ in kluster[-1]) + TAK_GLAPP_M:
                    kluster[-1].append(kant)
                else:
                    kluster.append([kant])
            for tak_kanter in kluster:
                vag_riktn = [v for *_, v in tak_kanter]
                tak_kanter = [kant[:4] for kant in tak_kanter]
                s_lo = max(min(a for a, _, _, _ in tak_kanter), 0.0)
                s_hi = min(max(b for _, b, _, _ in tak_kanter), rutt.length)
                ordn = sorted((c, t) for _, _, c, t in tak_kanter)
                sp = np.r_[s_lo, ss[(ss > s_lo) & (ss < s_hi)], s_hi]
                tp = np.interp(sp, [c for c, _ in ordn], [t for _, t in ordn]) - TAK_UNDER_ASFALT_M
                zr = np.interp(sp, ss, z_r)
                hw = bredd / 2 + SLANT * np.maximum(0.0, tp - TAK_TJOCKLEK - zr) + 0.6
                # mynningarna parallella med vägen ovanför (medelriktning, samma håll som normalen)
                n_r = _riktning(rutt, float(np.mean([c for _, _, c, _ in tak_kanter])))
                n_r = np.array([-n_r[1], n_r[0]])
                u = np.zeros(2)
                for v in vag_riktn:
                    u += v if np.dot(v, n_r) >= 0 else -v
                u = u / np.linalg.norm(u) if np.linalg.norm(u) > 1e-9 else n_r
                sin = max(abs(float(np.dot(u, n_r))), 0.5)   # mot normalen: 1 = rät korsning
                self.tak.append((np.array([rutt.interpolate(d).coords[0] for d in sp]), tp, hw / sin,
                                 self.roads[j]['tags'], u))
                self.tak_info.append(dict(rutt=rutt, s_lo=float(s_lo), s_hi=float(s_hi), bredd=float(bredd),
                                          u=u, n_r=n_r, sp=sp, tp=tp, undre=list(medlemmar)))
            for botten, s_p in bottnar:
                if schakt:
                    golvet = float(np.interp(s_p, ss, z_r))
                else:
                    q = rutt.interpolate(s_p)
                    golvet = float(sample(h, [q.x], [q.y])[0])
                self.fria_hojder.append(botten - golvet)
        if self.fria_hojder:
            print(f'broar: {self.schakt} schakt, fri höjd under däck min {min(self.fria_hojder):.1f} m, '
                  f'median {float(np.median(self.fria_hojder)):.1f} m')

    def spara_mask(self, path, shape, transform):
        """Schakt, krön och däck (med en cells marginal), så att step4 inte sätter träd där."""
        from scipy import ndimage as ndi
        m = getattr(self, 'schakt_mask', np.zeros(shape, bool)) | self.dack_raster(shape, transform)
        np.save(path, ndi.binary_dilation(m, iterations=2))

    # ---------- meshar ----------
    def bygg_meshar(self, h, sample, to_world, add_merged, betong, tra, metall, mat=None, valt=None):
        # brobanor (bara vägar med bridge-tagg; vägar över tunnlar ligger på tunneltaken)
        dack = []
        for k, spann in self.spann.items():
            if not self.bro[k] or k in self.pa_tak:
                continue
            r = self.roads[k]
            L = r['line']
            gc = r['tags']['highway'] in GC
            bredd = max(r['width'], GC_BRO_MIN_BREDD) if gc else r['width']
            bredd = max(bredd, float(r['tags'].get('_min_bredd', 0.0)))   # broar_justera.json
            bredd += 2 * KANTBALK_BRO_B - 0.1
            for s0, s1 in spann:
                a, b = max(s0, 0.0), min(s1, L.length)
                if b - a < 0.5:
                    continue
                inne = r['s'][(r['s'] > a) & (r['s'] < b)]
                ss = np.r_[a, inne, b]
                pts = np.array([L.interpolate(d).coords[0] for d in ss])
                topp = np.interp(ss, r['s'], r['z']) + lyft(r['tags'])
                trabro = r['tags']['highway'] in TRA and b - a <= TRA_MAX_LANGD
                dack.append(dict(k=k, a=a, b=b, ss=ss, pts=pts, topp=topp, bredd=bredd, gc=gc, tra=trabro,
                                 seg=substring(L, a, b)))
        polys = [d['seg'].buffer(d['bredd'] / 2 + 0.3, cap_style=2) for d in dack]
        # parallella broar: sidor som har en annan bro intill blir inre (inget räcke, glipan fylls)
        for i, d in enumerate(dack):
            d['inre'] = {}
            dv = np.gradient(d['pts'], axis=0)
            dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
            nrm = np.c_[-dv[:, 1], dv[:, 0]]
            d['nrm'] = nrm
            for sida in (1.0, -1.0):
                traffar = {}
                for f in (0.25, 0.5, 0.75):
                    q = min(int(f * (len(d['pts']) - 1)), len(d['pts']) - 1)
                    for off in np.arange(0.5, PARALLELL_AVSTAND + 0.01, 1.0):
                        pt = Point(d['pts'][q] + nrm[q] * sida * (d['bredd'] / 2 + off))
                        hit = next((o for o, pg in enumerate(polys) if o != i and pg.contains(pt)), None)
                        if hit is not None:
                            traffar[hit] = traffar.get(hit, 0) + 1
                            break
                bast = max(traffar.items(), key=lambda kv: kv[1], default=(None, 0))
                if bast[1] >= 2:
                    d['inre'][sida] = bast[0]
        antal = 0
        for i, d in enumerate(dack):
            m = _Mesh(to_world)
            tjock = TRA_TJOCKLEK if d['tra'] else DACK_TJOCKLEK
            m.platta(d['pts'], d['topp'], d['bredd'] / 2, tjock, ovan_under=0.06)
            r = self.roads[d['k']]
            L = r['line']
            if d['b'] - d['a'] > PELARE_FRAN and not r['tags'].get('_utan_pelare'):
                for sp in np.arange(d['a'] + PELARE_AVSTAND, d['b'] - 5.0, PELARE_AVSTAND):
                    c = np.array(L.interpolate(sp).coords[0])
                    v = _riktning(L, sp)
                    nv = np.array([-v[1], v[0]])
                    z_u = float(np.interp(sp, r['s'], r['z'])) + lyft(r['tags']) - DACK_TJOCKLEK
                    mark = float(sample(h, [c[0]], [c[1]])[0]) - 0.5
                    if z_u - mark > 0.5:
                        halv = max(d['bredd'] / 2 - 0.8, 0.5)
                        m.mur(np.array([c + nv * halv, c - nv * halv]), np.full(2, z_u), np.full(2, mark),
                              PELARE_TJOCKLEK)
            mr = _Mesh(to_world)
            mk = _Mesh(to_world)   # osynlig kollisionsvägg längs räckena
            for sida in (1.0, -1.0):
                if sida in d['inre']:
                    o = d['inre'][sida]
                    if i < o:   # fyll glipan till grannbron (en gång per par)
                        m.fyllnad(d['pts'], d['nrm'], sida, d['bredd'] / 2, d['topp'], dack[o], tjock)
                    continue
                if d['tra']:
                    linje = d['pts'] + d['nrm'] * sida * (d['bredd'] / 2 - STOLPE)
                    if valt is not None:
                        _valtbart_racke(valt, to_world, linje, d['topp'] - 0.02, d['gc'], tra, metall, True)
                        continue
                    mr.racke(linje, d['topp'] - 0.02, RACKE_HOJD_GC if d['gc'] else RACKE_HOJD)
                    mk.mur(linje, d['topp'] + KANT_VAGG_H, d['topp'] - 0.1, KANT_VAGG_TJOCK)
                    continue
                # kantbalk: betongen syns bara här (och på sidorna/under), vägbanan är asfalt hela vägen
                balk = d['pts'] + d['nrm'] * sida * (d['bredd'] / 2 - KANTBALK_BRO_B / 2)
                m.mur(balk, d['topp'] + KANTBALK_BRO_H, d['topp'] - 0.1, KANTBALK_BRO_B)
                linje = d['pts'] + d['nrm'] * sida * (d['bredd'] / 2 - KANTBALK_BRO_B / 2)
                if valt is not None:
                    _valtbart_racke(valt, to_world, linje, d['topp'] + KANTBALK_BRO_H, d['gc'], tra, metall, False)
                    continue
                mr.racke(linje, d['topp'] + KANTBALK_BRO_H, RACKE_HOJD_GC if d['gc'] else RACKE_HOJD)
                mk.mur(linje, d['topp'] + KANT_VAGG_H, d['topp'] - 0.1, KANT_VAGG_TJOCK)
            add_merged('Broar', m.trimesh(), tra if d['tra'] else betong)
            if mr.V:
                add_merged('Brorack', mr.trimesh(), tra if d['tra'] else metall)
            if mk.V:
                add_merged('Kollision_broar', mk.trimesh(), metall)
            antal += 1
        # tunneltak över undergångarna, med räcken längs mynningarna
        for pts, topp, hw, tj, u in self.tak:
            m = _Mesh(to_world)
            m.platta(pts, topp, hw, TAK_TJOCKLEK, ovan_under=0.0, tvars=u)
            mr = _Mesh(to_world)
            mk = _Mesh(to_world)
            dv = np.gradient(pts, axis=0) if len(pts) > 2 else np.repeat([pts[-1] - pts[0]], len(pts), 0)
            dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
            for i_, inat in ((0, 1.0), (len(pts) - 1, -1.0)):
                n_ = max(2, int(2 * hw[i_]) + 1)
                tvars = np.linspace(-hw[i_] + 0.3, hw[i_] - 0.3, n_)
                linje = pts[i_] + dv[i_] * inat * STOLPE + np.outer(tvars, u)
                if valt is not None:
                    _valtbart_racke(valt, to_world, linje, np.full(n_, topp[i_]), False, tra, metall, False)
                    continue
                mr.racke(linje, np.full(n_, topp[i_]), RACKE_HOJD)
                mk.mur(linje, np.full(n_, topp[i_] + KANT_VAGG_H), np.full(n_, topp[i_] - 0.1), KANT_VAGG_TJOCK)
            add_merged('Broar', m.trimesh(), betong)
            if mr.V:
                add_merged('Brorack', mr.trimesh(), metall)
            if mk.V:
                add_merged('Kollision_broar', mk.trimesh(), metall)
        if mat is not None:
            self._undergangar(h, sample, to_world, add_merged, betong, mat)
        print(f'broar: {antal} brobanor, {len(self.tak)} tunneltak, '
              f'{sum(len(d["inre"]) for d in dack) // 2} sammanslagna par')


    # ---------- undergångarnas utseende ----------
    def _undergangar(self, h, sample, to_world, add_merged, betong, mat):
        gatsten = _gatsten_material()
        golv_mat = mat('Tunnelgolv', (96, 96, 98), 0.9)
        lampa = trimesh.visual.material.PBRMaterial(name='Tunnellampa', baseColorFactor=[1.0, 0.96, 0.85, 1.0],
                                                    emissiveFactor=[1.0, 0.92, 0.75], roughnessFactor=0.5)
        n_balk = n_lada = 0
        for info, (pts, topp, hw, _tj, u) in zip(self.tak_info, self.tak):
            rutt, s_lo, s_hi, bredd = info['rutt'], info['s_lo'], info['s_hi'], info['bredd']
            n_r = info['n_r']                      # gångvägens normal (SWEREF)
            lada = s_hi - s_lo > LADA_FRAN_M
            sinf = max(abs(float(np.dot(u, n_r))), 0.5)

            def golv(q):
                return float(sample(h, [q[0]], [q[1]])[0])
            m = _Mesh(to_world)
            # kantbalkar vid mynningarna (längs vägen ovanför, u)
            for i_, inat in ((0, 1.0), (len(pts) - 1, -1.0)):
                d_ = _riktning(rutt, info['sp'][i_])
                c = pts[i_] + d_ * inat * KANTBALK_D / 2
                m.mur(np.array([c - u * hw[i_], c + u * hw[i_]]), np.full(2, topp[i_] - 0.06),   # under vägbanan
                      np.full(2, topp[i_] - KANTBALK_H), KANTBALK_D)
                if not lada:
                    # pelare under balken vid slänternas fot, på var sida om gångvägen
                    for sida in (1.0, -1.0):
                        off = sida * (bredd / 2 + PELARE_U / 2 + 0.2)
                        q = c + u * (off / sinf)
                        zg = golv(q)
                        if topp[i_] - KANTBALK_H - zg > 0.8:
                            m.mur(np.array([q - d_ * PELARE_U / 2, q + d_ * PELARE_U / 2]),
                                  np.full(2, topp[i_] - KANTBALK_H + 0.05), np.full(2, zg - 0.3), PELARE_U)
            if lada:
                # väggar i schaktets kanter, golv och lampor i taket
                ss = np.r_[s_lo, np.arange(np.ceil(s_lo), s_hi, 1.0), s_hi]
                c_ = np.array([rutt.interpolate(d).coords[0] for d in ss])
                tp_ = np.interp(ss, info['sp'], topp) - TAK_TJOCKLEK
                zg_ = np.array([golv(q) for q in c_])
                dv = np.gradient(c_, axis=0)
                dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
                nrm = np.c_[-dv[:, 1], dv[:, 0]]
                for sida in (1.0, -1.0):
                    m.mur(c_ + nrm * sida * (bredd / 2 + LADA_VAGG / 2), tp_ + 0.05, zg_ - 0.3, LADA_VAGG)
                g = _Mesh(to_world)
                g.platta(c_, zg_ + 0.12, bredd / 2 + 0.2, 0.3, ovan_under=0.0)
                add_merged('Broar', g.trimesh(), golv_mat)
                lm = _Mesh(to_world)
                for sv in np.arange(s_lo + LAMPA_AVSTAND / 2, s_hi, LAMPA_AVSTAND):
                    q = np.array(rutt.interpolate(sv).coords[0])
                    zt = float(np.interp(sv, info['sp'], topp)) - TAK_TJOCKLEK
                    d_ = _riktning(rutt, sv)
                    lm.mur(np.array([q - d_ * 0.6, q + d_ * 0.6]), np.full(2, zt + 0.01), np.full(2, zt - 0.08), 0.25)
                add_merged('Broar', lm.trimesh(), lampa)
                n_lada += 1
            else:
                n_balk += 1
            add_merged('Broar', m.trimesh(), betong)
            # gatsten på slänterna: under bron (balkbro) och som koner utanför mynningarna
            V, F, UV = _gatsten_yta(rutt, s_lo, s_hi, bredd, lada, h, sample, to_world, info, topp)
            if F:
                add_merged('Broar', trimesh.Trimesh(np.array(V), np.array(F), process=False), gatsten,
                           uv=np.array(UV))
        print(f'undergångar: {n_balk} balkbroar, {n_lada} betonglådor')


def _gatsten_yta(rutt, s_lo, s_hi, bredd, lada, h, sample, to_world, info, topp):
    """Rutnät (1 m) på slänterna från schaktets botten och utåt, GATSTEN_LYFT över terrängen.
    Balkbro: under hela bron och KON_M utanför; låda: bara utanför mynningarna. Utanför mynningarna
    smalnar den av (kon). Bara där marken ligger under däcket, och inte på schaktets botten."""
    V, F, UV = [], [], []
    s0, s1 = max(s_lo - KON_M, 0.0), min(s_hi + KON_M, rutt.length)
    ss = np.arange(s0, s1 + 0.01, 1.0)
    if len(ss) < 2:
        return V, F, UV
    c = np.array([rutt.interpolate(d).coords[0] for d in ss])
    dv = np.gradient(c, axis=0)
    dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
    nrm = np.c_[-dv[:, 1], dv[:, 0]]
    tmax = float(np.max(topp))
    for sida in (1.0, -1.0):
        offs = bredd / 2 + np.arange(0.0, 12.01, 1.0)
        P = c[:, None, :] + nrm[:, None, :] * sida * offs[None, :, None]
        Z = sample(h, P[..., 0].ravel(), P[..., 1].ravel()).reshape(P.shape[:2]) + GATSTEN_LYFT
        golv = Z[:, :1]
        utanfor = np.minimum(np.abs(ss - np.clip(ss, s_lo, s_hi)), KON_M)   # 0 under bron
        # konens bredd: hela slänten vid mynningen, smalare ut mot KON_M
        max_off = bredd / 2 + 12.0 * (1.0 - utanfor / KON_M)
        ok = (offs[None, :] <= max_off[:, None] + 1e-6) & (Z < tmax - 0.4) & (Z - golv < 6.0)
        if lada:
            ok &= (utanfor > 0)[:, None]
        base = len(V)
        idx = -np.ones(P.shape[:2], int)
        for i in range(len(ss)):
            for j in range(len(offs)):
                x, zz = to_world(P[i, j, 0], P[i, j, 1])
                idx[i, j] = len(V)
                V.append([x, Z[i, j], zz])
                UV.append([ss[i] / 2.0, offs[j] / 2.0])
        for i in range(len(ss) - 1):
            for j in range(len(offs) - 1):
                if not (ok[i, j] and ok[i + 1, j] and ok[i, j + 1] and ok[i + 1, j + 1]):
                    continue
                a, b, c_, d = idx[i, j], idx[i + 1, j], idx[i + 1, j + 1], idx[i, j + 1]
                # uppåt: normalens y > 0
                pa, pb, pc = np.array(V[a]), np.array(V[b]), np.array(V[c_])
                if np.cross(pb - pa, pc - pa)[1] >= 0:
                    F += [[a, b, c_], [a, c_, d]]
                else:
                    F += [[a, c_, b], [a, d, c_]]
        if base == len(V):
            continue
    if not F:
        return [], [], []
    # ta bort hörn som ingen triangel använder
    Fa = np.array(F)
    anv = np.unique(Fa)
    ny = -np.ones(len(V), int)
    ny[anv] = np.arange(len(anv))
    return [V[i] for i in anv], ny[Fa].tolist(), [UV[i] for i in anv]


_GATSTEN = None


def _gatsten_material():
    """Gatsten (smågatsten i rader, grå med variation och mörka fogar), 2 × 2 m per textur."""
    global _GATSTEN
    if _GATSTEN is not None:
        return _GATSTEN
    from PIL import Image
    import zlib
    c = 256
    rng = np.random.default_rng(zlib.crc32(b'gatsten'))
    a = np.zeros((c, c, 3), float)
    a[:] = (70, 68, 66)                         # fog
    rad = c // 16                              # 12,5 cm rader
    for y0 in range(0, c, rad):
        x = -rng.integers(0, rad)
        while x < c:
            w = int(rng.integers(int(rad * 0.8), int(rad * 1.3)))
            ton = rng.uniform(0.75, 1.15)
            bas = np.array((138, 134, 128)) * ton + rng.normal(0, 4, 3)
            xs, xe = max(x + 1, 0), min(x + w - 1, c)
            if xe > xs:
                for dy in range(1, rad - 1):
                    f = 1.06 - 0.18 * abs(dy - rad / 2) / (rad / 2)
                    a[y0 + dy, xs:xe] = bas * f
            x += w
    a += rng.normal(0, 5, a.shape)
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    _GATSTEN = trimesh.visual.material.PBRMaterial(name='Gatsten', baseColorTexture=im, metallicFactor=0.0,
                                                   roughnessFactor=0.9)
    return _GATSTEN


def _valtbart_racke(valt, to_world, linje, topp, gc, tra, metall, av_tra):
    """Ett räcke som vältbara bitar (valtbart.Samling): en bit per ca STOLP_AVSTAND m, foten mitt på biten
    (stolpen i början, ledstång och mellanslå längs hela, skalad till bitens längd), och en ensam stolpe i
    slutet. Typerna Brorack[_tra][_gc] (material och höjd)."""
    from jarnvag import ladar
    from valtbart import lador_mesh
    hojd = RACKE_HOJD_GC if gc else RACKE_HOJD
    typ = 'Brorack' + ('_tra' if av_tra else '') + ('_gc' if gc else '')
    material = tra if av_tra else metall
    if not valt.har_mall(typ):
        stolpe = ladar([[-1.0, 0.0]], [[1.0, 0.0]], STOLPE / 2, STOLPE / 2, 0.0, hojd)
        valt.mall(typ, [(lador_mesh(np.vstack([
            stolpe,
            ladar([[0.0, 0.0]], [[1.0, 0.0]], 1.0, 0.035, hojd - 0.07, hojd),
            ladar([[0.0, 0.0]], [[1.0, 0.0]], 1.0, 0.02, hojd * 0.5 - 0.05, hojd * 0.5)])), material)])
        valt.mall(typ + '_stolpe', [(lador_mesh(ladar([[0.0, 0.0]], [[1.0, 0.0]], STOLPE / 2, STOLPE / 2,
                                                       0.0, hojd)), material)])
    linje = np.asarray(linje, float)
    topp = np.asarray(topp, float)
    s = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(linje, axis=0), axis=1))]
    if s[-1] < 0.3:
        return
    n = max(1, int(round(s[-1] / STOLP_AVSTAND)))
    kant = np.linspace(0.0, s[-1], n + 1)
    P = np.c_[np.interp(kant, s, linje[:, 0]), np.interp(kant, s, linje[:, 1])]
    Z = np.interp(kant, s, topp)
    W = np.array([to_world(x, y) for x, y in P])   # Godot (x, z)
    for i in range(n):
        wd = W[i + 1] - W[i]
        L = float(np.linalg.norm(wd))
        if L < 0.05:
            continue
        mitt = (W[i] + W[i + 1]) / 2
        valt.placera(typ, [mitt[0], float(Z[i] + Z[i + 1]) / 2, mitt[1]], wd, skala_x=L / 2.0)
    valt.placera(typ + '_stolpe', [W[-1][0], float(Z[-1]), W[-1][1]], W[-1] - W[-2] if n else [1.0, 0.0])


class _Mesh:
    """Bygger fyrhörningar med uttryckligen orienterade normaler (Godot har backface culling)."""

    def __init__(self, to_world):
        self.to_world = to_world
        self.V, self.F = [], []

    def w(self, p, z):
        x, zz = self.to_world(p[0], p[1])
        return np.array([x, z, zz])

    def wdir(self, v):
        # riktning i SWEREF (x, y) -> Godot (x, 0, z), z = -y
        return np.array([v[0], 0.0, -v[1]])

    def quad(self, a, b, c, d, ut):
        n = len(self.V)
        self.V += [a, b, c, d]
        f1, f2 = [n, n + 1, n + 2], [n, n + 2, n + 3]
        if np.dot(np.cross(b - a, c - a), ut) < 0:
            f1, f2 = f1[::-1], f2[::-1]
        self.F += [f1, f2]

    def platta(self, pts, topp, hw, tjock, ovan_under=0.02, tvars=None):
        """Platta längs en linje med halvbredd hw (tal eller array): ovansida (ovan_under m under
        topp; på broar ligger vägmeshen utan kollision ovanpå), sidor, undersida och ändar.
        tvars: enhetsvektor (SWEREF) som kanterna tvärs över följer i stället för linjens normal,
        t.ex. vägen ovanför ett snett tunneltak (hw räknas då längs den)."""
        pts = np.asarray(pts, float)
        d = np.gradient(pts, axis=0) if len(pts) > 2 else np.repeat([pts[-1] - pts[0]], len(pts), 0)
        d = d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
        nrm = np.c_[-d[:, 1], d[:, 0]]
        hw = np.broadcast_to(np.asarray(hw, float), (len(pts),))[:, None]
        tv = nrm if tvars is None else np.broadcast_to(np.asarray(tvars, float), (len(pts), 2))
        Lp, Rp = pts + tv * hw, pts - tv * hw
        topp = np.asarray(topp, float)
        bot, ovan = topp - tjock, topp - ovan_under
        upp, ned = np.array([0.0, 1.0, 0.0]), np.array([0.0, -1.0, 0.0])
        for i in range(len(pts) - 1):
            ut_v = self.wdir(nrm[i])
            self.quad(self.w(Lp[i], ovan[i]), self.w(Rp[i], ovan[i]),
                      self.w(Rp[i + 1], ovan[i + 1]), self.w(Lp[i + 1], ovan[i + 1]), upp)
            self.quad(self.w(Lp[i], topp[i]), self.w(Lp[i + 1], topp[i + 1]),
                      self.w(Lp[i + 1], bot[i + 1]), self.w(Lp[i], bot[i]), ut_v)
            self.quad(self.w(Rp[i], topp[i]), self.w(Rp[i + 1], topp[i + 1]),
                      self.w(Rp[i + 1], bot[i + 1]), self.w(Rp[i], bot[i]), -ut_v)
            self.quad(self.w(Lp[i], bot[i]), self.w(Rp[i], bot[i]),
                      self.w(Rp[i + 1], bot[i + 1]), self.w(Lp[i + 1], bot[i + 1]), ned)
        for i, tecken in ((0, -1.0), (len(pts) - 1, 1.0)):
            self.quad(self.w(Lp[i], topp[i]), self.w(Rp[i], topp[i]),
                      self.w(Rp[i], bot[i]), self.w(Lp[i], bot[i]), self.wdir(d[i]) * tecken)

    def fyllnad(self, pts, nrm, sida, hw, topp, annan, tjock):
        """Fyller glipan mellan en bros kant och grannbrons kant (ovansida och undersida)."""
        kant = pts + nrm * sida * hw
        seg = annan['seg']
        motsatt = []
        for q in kant:
            dd = seg.project(Point(q))
            c = np.array(seg.interpolate(dd).coords[0])
            v = q - c
            v /= max(np.linalg.norm(v), 1e-9)
            z = float(np.interp(dd + annan['a'], annan['ss'], annan['topp']))
            motsatt.append((c + v * annan['bredd'] / 2, z))
        upp, ned = np.array([0.0, 1.0, 0.0]), np.array([0.0, -1.0, 0.0])
        for i in range(len(kant) - 1):
            (o0, z0), (o1, z1) = motsatt[i], motsatt[i + 1]
            self.quad(self.w(kant[i], topp[i] - 0.02), self.w(o0, z0 - 0.02),
                      self.w(o1, z1 - 0.02), self.w(kant[i + 1], topp[i + 1] - 0.02), upp)
            self.quad(self.w(kant[i], topp[i] - tjock), self.w(o0, z0 - tjock),
                      self.w(o1, z1 - tjock), self.w(kant[i + 1], topp[i + 1] - tjock), ned)

    def racke(self, linje, topp, hojd):
        """Smalt räcke: stolpar var STOLP_AVSTAND m, ledstång och en mellanslå."""
        linje = np.asarray(linje, float)
        topp = np.asarray(topp, float)
        s = np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(linje, axis=0), axis=1))]
        if s[-1] < 0.3:
            return
        for sp in np.arange(0.0, s[-1] + 1e-6, s[-1] / max(1, round(s[-1] / STOLP_AVSTAND))):
            i = min(np.searchsorted(s, sp), len(s) - 1)
            i0 = max(i - 1, 0)
            v = linje[i] - linje[i0] if i > 0 else linje[1] - linje[0]
            v = v / max(np.linalg.norm(v), 1e-9)
            c = linje[i0] + v * (sp - s[i0])
            z = float(np.interp(sp, s, topp))
            self.mur(np.array([c - v * STOLPE / 2, c + v * STOLPE / 2]), np.full(2, z + hojd), np.full(2, z), STOLPE)
        self.mur(linje, topp + hojd, topp + hojd - 0.07, 0.07)
        self.mur(linje, topp + hojd * 0.5, topp + hojd * 0.5 - 0.05, 0.04)

    def mur(self, pts, topp, botten, tjock):
        """Vägg längs en linje (SWEREF), med båda sidor, ovansida och ändar."""
        pts = np.asarray(pts, float)
        d = np.gradient(pts, axis=0) if len(pts) > 2 else np.repeat([pts[-1] - pts[0]], len(pts), 0)
        d = d / np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
        nrm = np.c_[-d[:, 1], d[:, 0]]
        A, B = pts + nrm * tjock / 2, pts - nrm * tjock / 2
        upp = np.array([0.0, 1.0, 0.0])
        for i in range(len(pts) - 1):
            ut_v = self.wdir(nrm[i])
            self.quad(self.w(A[i], topp[i]), self.w(A[i + 1], topp[i + 1]),
                      self.w(A[i + 1], botten[i + 1]), self.w(A[i], botten[i]), ut_v)
            self.quad(self.w(B[i], topp[i]), self.w(B[i + 1], topp[i + 1]),
                      self.w(B[i + 1], botten[i + 1]), self.w(B[i], botten[i]), -ut_v)
            self.quad(self.w(A[i], topp[i]), self.w(B[i], topp[i]),
                      self.w(B[i + 1], topp[i + 1]), self.w(A[i + 1], topp[i + 1]), upp)
        for i, tecken in ((0, -1.0), (len(pts) - 1, 1.0)):
            self.quad(self.w(A[i], topp[i]), self.w(B[i], topp[i]),
                      self.w(B[i], botten[i]), self.w(A[i], botten[i]), self.wdir(d[i]) * tecken)

    def trimesh(self):
        return trimesh.Trimesh(np.array(self.V), np.array(self.F), process=False)
