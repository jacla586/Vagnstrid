"""Vägytan som en sammanhängande yta (step3, i stället för ett band per OSM-väg).

Förut ritades varje väg som ett eget band: i korsningar gick banden omlott (flimmer, trappsteg),
hörnen blev fyrkantiga, delade körbanor fick en kil gräs emellan och skarpa kurvor fick hack.
Nu: varje vägs yta (buffrad mittlinje, bredden per punkt, rundade ändar) slås ihop per material
till polygoner; i varje korsning rundas hörnen (lokal morfologisk stängning med radie efter vägklass,
KORS_RADIE_M) och smala kilar mellan körbanor fylls. Polygonerna delas i 250 m-rutor och 2 m-celler
(lagda på terrängens hörn), trianguleras (constrained Delaunay) och draperas över terrängen med
vägens lyft (broar.lyft). Brodäck (och vägar över tunnlar) ritas som förut som band på profilen.

  V = Vagyta(roads, BRO, hinder, overtackt)    polygonerna (före heightmap-exporten: mask() för gräset)
  V.bygg(h, sample, to_world, add_merged, matfn, asfalt_mat, roadmat)   meshar
"""
import math

import numpy as np
from scipy import ndimage as ndi
import shapely
import trimesh
from shapely.geometry import Point, Polygon
from shapely.ops import substring, unary_union
from shapely.strtree import STRtree

import broar

GC = ('path', 'footway')
RANG = dict(motorway=9, trunk=8, primary=7, secondary=6, tertiary=5, unclassified=4, residential=4,
            living_street=3, pedestrian=2, service=2, track=1, cycleway=1, road=3)
# Hörnradie i korsningen efter den näst viktigaste vägen där (den mindre vägens svängar bestämmer)
KORS_RADIE_M = dict(motorway=14, trunk=12, primary=12, secondary=10, tertiary=8, unclassified=6, residential=6,
                    road=6, living_street=5, pedestrian=3, service=3, track=3, cycleway=2)
GC_RADIE_M = 1.0          # GC-vägarnas hörn (stängning över hela GC-nätet)
NOD_TOL_M = 1.0
BRO_AVST_M = 15.0
MITT_FYLL_M = 3.0
RONDELL_AVST_M = 30.0     # trafiköarna vid rondellernas infarter fylls inte
GC_REFUG_M = 2.0
SPARR_MIN_BREDD_M = 0.7   # smalare mittremsor målas inte
SPARR_KANT_IN_M = 0.15
SPARR_LINJE_M = 0.10
SPARR_STRECK_AVST_M = 2.5
SPARR_STRECK_B_M = 0.30
SPARR_KORSNING_M = 4.0
REFUG_MIN_BREDD_M = 6.5   # refuger vid övergångsställen (crossing:island=yes)
REFUG_HALV_L_M = 5.0
REFUG_B_M = 1.6
REFUG_GANG_M = 3.0        # gångbanan genom ön
REFUG_H_M = 0.12
TROTTOAR_B_M = 2.0        # trottoarer ur OSM sidewalk=*
TROTTOAR_H_M = 0.12       # kantstenens höjd över vägbanan
TROTTOAR_YTTER_M = 0.12   # trottoarens ytterkant över marken (fall utåt)
BUSSFICKA_B_M = 3.0       # busshållplatsficka (OSM bus_bay=right/left/both på vägen): bredd utanför kanten
BUSSFICKA_KIL_M = 15.0    # avsmalning i varje ände (kortare vägar: en tredjedel var)    # spärrområdet slutar så långt från en anslutande gata          # där en GC-väg korsar mittremsan blir den en refug (fylls inte)         # smalare mittremsa mellan två körbanor med samma namn: asfalt (målad refug)         # ingen rundning i korsningar så nära ett däck (olika nivåer)
CELL_M = 2.0              # trianguleringens rutor (terrängens hörnavstånd)
BIL_CELL_M = 4.0          # bilvägarna: terrängen under är planad efter profilen, glesare räcker...
# ...utom där ytan går utanför det planade bandet (korsningsrundningar och trottoarer vid en ravinkant,
# Vallastaden i road_to_science): en ruta vars mitt eller kantmitter ligger mer än OJAMN_M från hörnens plan
# delas i CELL_M-rutor (och grannarna med, så att skarven hamnar där marken är jämn); annars spände en 4 m-triangel
# fritt över slänten och asfalten svävade.
OJAMN_M = 0.08
RUTA_M = 250.0            # som step3:s MERGE_TILE
HW_STEG = 0.1             # bredden kvantiseras för buffringen
ENKEL_UV = 50.0           # lage_uv: enkelriktade körbanor får halvbredden + detta (shadern vet då körfälten)


def _ar_gc(r):
    return r['tags']['highway'] in GC


class Vagyta:
    def __init__(self, roads, BRO, hinder=(), overtackt=lambda r: False, rutnat=(0.0, 0.0)):
        """roads: step3:s vägar (pts, s, hw satta); BRO: broar.Broar; hinder: polygoner (hus, vatten) som
        rundningarna inte får gå in i; overtackt(r): vägar som inte ritas (inne i stenläggningen);
        rutnat: (OX, OY) terrängens hörn, så att trianguleringens celler ligger på dem."""
        self.roads, self.BRO, self.rutnat = roads, BRO, rutnat
        self.ritas = [k for k, r in enumerate(roads) if len(r['pts']) >= 2 and not overtackt(r)]
        self._linjer = [r['line'] for r in roads]
        self._tak = BRO.tak_ytor() if hasattr(BRO, 'tak_ytor') else []
        self._ltrad = STRtree(self._linjer)
        self.poly = {}            # vägindex -> vägens yta (utan däck)
        self.spann_k = {}         # vägindex -> sträckor på profilen (däck, tunneltak)
        self.dack_bitar = []      # (k, s0, s1): band på profilen
        for k in self.ritas:
            p = self._vagpoly(k)
            if p is not None and not p.is_empty:
                self.poly[k] = p
        bil = [k for k in self.poly if not _ar_gc(roads[k])]
        gc = [k for k in self.poly if _ar_gc(roads[k])]
        self.mitt = self._mittremsor(bil)
        self.fickor = self._busfickor(bil)
        self.fyll = self._rundningar(bil, hinder) + self.mitt + self.fickor
        print(f'vägyta: {len(bil)} bilvägar, {len(gc)} GC-vägar, {len(self.fyll)} korsningsrundningar',
              f'({int(sum(p.area for p, _ in self.fyll))} m²), {len(self.dack_bitar)} däckband, {len(self.fickor)} bussfickor')
        self.bil_ytor, self.gc_ytor = bil, gc
        self.hinder = hinder
        self.trottoar = self._trottoarer(bil, gc, hinder)
        self.o_nosar = []         # (nosens punkt, riktning mot trafiken): hålla höger-skyltar (vagkant.py)

    # ------------------------------------------------------------------ polygoner
    def _vagpoly(self, k):
        r = self.roads[k]
        L = r['line']
        spann = [(max(0.0, s0), min(L.length, s1)) for s0, s1 in self.BRO.spann.get(k, [])]
        # över tunneltak (även intill korta broar som ingår i taket): på profilen, inte på schaktets botten
        for tak, undre, *_ in self._tak:
            if k in undre or not L.intersects(tak):
                continue
            del_ = L.intersection(tak.buffer(0.3))
            for d in getattr(del_, 'geoms', [del_]):
                if d.geom_type == 'LineString' and d.length > 0.2:
                    a_, b_ = sorted((L.project(Point(d.coords[0])), L.project(Point(d.coords[-1]))))
                    spann.append((a_, b_))
        spann.sort()
        ihop = []
        for s0, s1 in spann:
            if ihop and s0 <= ihop[-1][1] + 0.5:
                ihop[-1] = (ihop[-1][0], max(ihop[-1][1], s1))
            else:
                ihop.append((s0, s1))
        spann = ihop
        self.spann_k[k] = spann
        for s0, s1 in spann:
            if s1 - s0 > 0.1:
                self.dack_bitar.append((k, s0, s1))
        # intervall utan däck
        fria, a = [], 0.0
        for s0, s1 in spann:
            if s0 > a + 0.05:
                fria.append((a, s0))
            a = max(a, s1)
        if a < L.length - 0.05:
            fria.append((a, L.length))
        s, hw = r['s'], np.asarray(r['hw'], float)
        delar = []
        for a, b in fria:
            # körningar med samma (kvantiserade) halvbredd, raka ändar; runda skarvar mellan körningarna
            i0, i1 = np.searchsorted(s, a), np.searchsorted(s, b)
            idx = np.arange(max(0, i0 - 1), min(len(s), i1 + 1))
            if not len(idx):
                continue
            q = np.round(hw[idx] / HW_STEG) * HW_STEG
            start = a
            j = 0
            while j < len(idx):
                j2 = j
                while j2 + 1 < len(idx) and q[j2 + 1] == q[j]:
                    j2 += 1
                slut = b if j2 + 1 >= len(idx) else min(b, max(start, (s[idx[j2]] + s[idx[j2 + 1]]) / 2))
                if slut - start > 0.01:
                    delar.append(substring(L, start, slut).buffer(float(q[j]), quad_segs=6, cap_style='flat'))
                    if slut < b - 0.01:
                        delar.append(L.interpolate(slut).buffer(float(min(q[j], q[min(j2 + 1, len(q) - 1)])), quad_segs=6))
                start = slut
                j = j2 + 1
            # böjar inom en körning: flat-buffern är redan rund i böjarna (join round)
        # återvändsändar (ingen annan väg där) blir runda
        for ande, s_ in ((L.coords[0], 0.0), (L.coords[-1], L.length)):
            if not any(s0 - 0.5 <= s_ <= s1 + 0.5 for s0, s1 in spann) and not self._annan_vid(k, Point(ande)):
                delar.append(Point(ande).buffer(float(np.interp(s_, s, hw)), quad_segs=6))
        if not delar:
            return None
        p = unary_union(delar)
        # rundade ändar får inte gå in under det egna däcket
        for s0, s1 in spann:
            if s1 - s0 > 0.1:
                p = p.difference(substring(L, s0, s1).buffer(float(hw.max()) + 1.0, cap_style='flat'))
        return p.buffer(0)

    def tak_hojd(self, pts, k):
        """Lägsta vägyta över tunneltaken (takets ovansida + TAK_UNDER_ASFALT_M) per punkt, annars -inf."""
        z = np.full(len(pts), -np.inf)
        for tak, undre, rutt, s_, tp in self._tak:
            if k in undre:
                continue
            nara = tak.buffer(0.5)
            for i, q in enumerate(pts):
                pq = Point(q)
                if nara.contains(pq):
                    z[i] = max(z[i], float(np.interp(rutt.project(pq), s_, tp)) + broar.TAK_UNDER_ASFALT_M + 0.01)
        return z

    def pa_dack(self, k, s):
        """True för punkter (s längs vägen) som ritas på profilen: däck och tunneltak."""
        s = np.asarray(s)
        m = np.zeros(len(s), bool)
        for s0, s1 in self.spann_k.get(k, self.BRO.spann.get(k, [])):
            m |= (s >= s0) & (s <= s1)
        return m

    def _annan_vid(self, k, p):
        return any(i != k and self._linjer[i].distance(p) < NOD_TOL_M for i in self._ltrad.query(p.buffer(NOD_TOL_M)))

    def _noder(self, bil):
        """Korsningspunkter: ändpunkter där minst två bilvägar möts. -> [(Point, [vägindex])]"""
        linjer = [self.roads[k]['line'] for k in bil]
        trad = STRtree(linjer)
        noder = []
        sett = []
        for k in bil:
            L = self.roads[k]['line']
            for p in (Point(L.coords[0]), Point(L.coords[-1])):
                if any(p.distance(q) < 3.0 for q in sett):
                    continue
                nara = [bil[i] for i in trad.query(p.buffer(NOD_TOL_M)) if linjer[i].distance(p) < NOD_TOL_M]
                if len(set(nara)) >= 2:
                    sett.append(p)
                    noder.append((p, sorted(set(nara))))
        return noder

    def _nara_dack(self, k, p):
        r = self.roads[k]
        s = r['line'].project(p)
        return any(s0 - BRO_AVST_M <= s <= s1 + BRO_AVST_M for s0, s1 in self.BRO.spann.get(k, [])) \
            or any(tak.distance(p) < BRO_AVST_M for tak, *_ in self._tak)

    def _rundningar(self, bil, hinder):
        """Rundade hörn och fyllda kilar i varje korsning: lokal stängning (buffer +R, -R) av vägytorna
        runt noden, bara det som tillkommer, inom en cirkel runt noden. -> [(polygon, vägindex för materialet)]"""
        if not bil:
            return []
        noder = self._noder(bil)
        ytor = [self.poly[k] for k in bil]
        trad = STRtree(ytor)
        hind = unary_union(list(hinder)) if hinder else None
        holmar = []   # rondellernas mittöar
        for k in bil:
            r = self.roads[k]
            if r.get('rondell') and r['line'].is_ring:
                o = Polygon(r['line'].coords).buffer(-float(np.max(r['hw'])) - 0.3)
                if not o.is_empty:
                    holmar.append(o)
        holm = unary_union(holmar) if holmar else None
        ut = []
        for p, ks in noder:
            if any(self._nara_dack(k, p) for k in ks):
                continue
            ks = sorted(ks, key=lambda k: -RANG.get(self.roads[k]['tags']['highway'], 2))
            hw_max = max(float(np.max(self.roads[k]['hw'])) for k in ks)
            klass = self.roads[ks[1] if len(ks) > 1 else ks[0]]['tags']['highway']
            R = KORS_RADIE_M.get(klass, 4)
            rack = p.buffer(hw_max + 2.5 * R + 5)
            grannar = [bil[i] for i in trad.query(rack)]
            lokal = unary_union([self.poly[k] for k in grannar]).intersection(rack.buffer(2 * R))
            stangd = lokal.buffer(R, quad_segs=8).buffer(-R, quad_segs=8)
            ring = p.buffer(hw_max + 2 * R + 4)
            ny = stangd.difference(lokal)
            if hind is not None:
                ny = ny.difference(hind)
            if holm is not None:
                ny = ny.difference(holm)
            kant = ring.exterior
            for d in getattr(ny, 'geoms', [ny]):
                # bara hörn nära noden; kilar mellan vägar som löper ihop långt (de når ringen) får vara
                if d.geom_type == 'Polygon' and d.area > 0.3 and d.distance(p) < hw_max + R \
                        and not d.intersects(kant) and d.within(ring) and not self._mellan_korbanor(d, grannar):
                    ut.append((d, ks[0]))
        return ut

    def _mittremsor(self, bil):
        """Smala mittremsor mellan enkelriktade körbanor med samma namn fylls (målad refug i verkligheten;
        OSM ritar körbanorna isär). -> [(polygon, vägindex)]"""
        en = [k for k in bil if self.roads[k]['tags'].get('oneway') in ('yes', '-1', '1')
              and not self.roads[k].get('rondell') and self.roads[k]['tags'].get('name')]
        if len(en) < 2:
            return []
        trad = STRtree([self.roads[k]['line'] for k in en])
        ringar = [self.roads[k]['line'] for k in bil if self.roads[k].get('rondell')]
        undvik = [L_.buffer(RONDELL_AVST_M) for L_ in ringar]
        gc = [r_['line'].buffer(GC_REFUG_M) for r_ in self.roads if r_['tags']['highway'] in GC + ('cycleway',)]
        undvik = unary_union(undvik + gc) if (undvik or gc) else None
        ut = []
        for k in en:
            r = self.roads[k]
            for i in trad.query(r['line'].buffer(25.0)):
                j = en[i]
                if j == k or self.roads[j]['tags'].get('name') != r['tags'].get('name'):
                    continue
                Lj = self.roads[j]['line']
                hwj = float(np.median(self.roads[j]['hw']))
                pts, hw = r['pts'], np.asarray(r['hw'])
                ok = np.zeros(len(pts), bool)
                nar = []
                for t, (P, h_) in enumerate(zip(pts, hw)):
                    pp = Point(P)
                    d = Lj.distance(pp)
                    q = Lj.interpolate(Lj.project(pp))
                    nar.append(q.coords[0])
                    ok[t] = d - h_ - hwj < MITT_FYLL_M and d > 0.5
                    # bara på tvären (inte där körbanan går mot grannens ände)
                    if ok[t]:
                        v = np.array(q.coords[0]) - P
                        tg = pts[min(t + 1, len(pts) - 1)] - pts[max(t - 1, 0)]
                        ok[t] = abs(np.dot(v, tg)) < 0.5 * np.linalg.norm(v) * np.linalg.norm(tg) + 1e-9
                nar = np.array(nar)
                fyrs = [Polygon([pts[t], pts[t + 1], nar[t + 1], nar[t]]) for t in range(len(pts) - 1) if ok[t] and ok[t + 1]]
                fyrs = [f.buffer(0) for f in fyrs if f.is_valid or f.buffer(0).area > 0]
                if fyrs:
                    u = unary_union(fyrs)
                    if undvik is not None:
                        u = u.difference(undvik)
                    for d_ in getattr(u, 'geoms', [u]):
                        if d_.geom_type == 'Polygon' and d_.area > 1.0:
                            ut.append((d_, k))
        return ut

    def _trottoarer(self, bil, gc, hinder):
        """Trottoarer där OSM säger sidewalk=both/left/right (sidewalk:<sida>=yes) på gatan och ingen egen
        gångväg är ritad bredvid: en remsa TROTTOAR_B_M bred längs kanten, avskuren mot alla bilvägsytor
        (korsningar), GC-vägar, hus och däck. -> polygon eller None"""
        delar = []
        for k in bil:
            r = self.roads[k]
            t = r['tags']
            sw = t.get('sidewalk')
            sidor = set()
            if sw in ('both', 'yes'):
                sidor = {'left', 'right'}
            elif sw in ('left', 'right'):
                sidor = {sw}
            for sd in ('left', 'right'):
                if t.get(f'sidewalk:{sd}') == 'yes' or t.get('sidewalk:both') == 'yes':
                    sidor.add(sd)
                if t.get(f'sidewalk:{sd}') in ('no', 'separate') or t.get('sidewalk:both') in ('no', 'separate'):
                    sidor.discard(sd)
            if not sidor or r.get('rondell'):
                continue
            hw = float(np.median(r['hw']))
            for sd in sidor:
                d = (hw + TROTTOAR_B_M / 2) * (1 if sd == 'left' else -1)
                try:
                    lin = r['line'].offset_curve(d, quad_segs=4, join_style='round')
                except Exception:
                    continue
                if lin.is_empty:
                    continue
                delar.append(lin.buffer(TROTTOAR_B_M / 2 + 0.05, cap_style='flat'))
        if not delar:
            return None
        y = unary_union(delar)
        # runt hörnen: bandet utanför gatornas yta (med rundningarna) där en trottoar finns i närheten
        nara = [self.poly[k] for k in bil if self.poly[k].intersects(y.buffer(TROTTOAR_B_M * 2))] + \
               [p for p, _ in self.fyll if p.intersects(y.buffer(TROTTOAR_B_M * 2))]
        U = unary_union(nara)
        band = U.buffer(TROTTOAR_B_M, quad_segs=6).difference(U)
        y = band.intersection(y.buffer(TROTTOAR_B_M * 1.6))
        bort = [self.poly[k] for k in bil] + [p for p, _ in self.fyll] + [self.poly[k].buffer(0.5) for k in gc]
        for k, s0, s1 in self.dack_bitar:
            r = self.roads[k]
            bort.append(substring(r['line'], s0, s1).buffer(float(np.max(r['hw'])) + TROTTOAR_B_M + 1.0))
        bort += list(hinder)
        y = y.difference(unary_union(bort))
        ut = [p for p in getattr(y, 'geoms', [y]) if p.geom_type == 'Polygon' and p.area > 4.0]
        if not ut:
            return None
        y = unary_union(ut)
        print('vägyta: trottoarer', int(y.area), 'm²')
        return y

    def _busfickor(self, bil):
        """Busshållplatsfickor: OSM bus_bay=right/left/both på en väg (sträckan är fickan) -> en remsa
        BUSSFICKA_B_M bred utanför kanten på den sidan, avsmalnande i ändarna. [(polygon, k)]"""
        ut = []
        for k in bil:
            r = self.roads[k]
            sida = r['tags'].get('bus_bay')
            if sida not in ('right', 'left', 'both') or self.spann_k.get(k):
                continue
            L = r['line']
            if L.length < 12.0:
                continue
            kil = min(BUSSFICKA_KIL_M, L.length / 3)
            ss = np.linspace(0, L.length, max(4, int(L.length / 2.0) + 1))
            pts = np.array([L.interpolate(d).coords[0] for d in ss])
            dv = np.gradient(pts, axis=0)
            dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
            nrm = np.c_[-dv[:, 1], dv[:, 0]]   # vänster om vägens riktning
            hw = np.interp(ss, r['s'], r['hw'])
            w = BUSSFICKA_B_M * np.clip(np.minimum(ss, L.length - ss) / kil, 0, 1)
            for tecken in ([-1] if sida == 'right' else [1] if sida == 'left' else [-1, 1]):
                inne = pts + nrm * (tecken * (hw - 0.2))[:, None]
                ute = pts + nrm * (tecken * (hw + w))[:, None]
                p = Polygon(np.r_[inne, ute[::-1]]).buffer(0)
                if not p.is_empty and p.area > 5.0:
                    ut.append((p, k))
        return ut

    def _mellan_korbanor(self, d, grannar):
        """Ligger biten mellan två enkelriktade körbanor med samma namn (trafikön vid en rondells infart)?"""
        namn, andra = {}, 0
        for k in grannar:
            r = self.roads[k]
            if self.poly[k].distance(d) >= 0.3 or r.get('rondell'):
                continue
            n_ = r['tags'].get('name') or r['tags'].get('ref')
            if r['tags'].get('oneway') in ('yes', '1', '-1') and n_:
                namn[n_] = namn.get(n_, 0) + 1
            else:
                andra += 1
        return andra == 0 and any(v >= 2 for v in namn.values())

    def mask(self, rasterize_fn, alla=False):
        """Rundningarna och mittremsorna (för markvegetationen: inget gräs på asfalten); alla: även
        bilvägarnas ytor (step4: inga laserträd på vägen, de är oftast skyltar och lyktstolpar)."""
        ytor = [p for p, _ in self.fyll] + ([self.trottoar] if self.trottoar is not None else [])
        if alla:
            ytor += [self.poly[k] for k in self.bil_ytor]
        return rasterize_fn(ytor)

    # ------------------------------------------------------------------ meshar
    def bygg(self, h, sample, to_world, add_merged, asfalt_mat, roadmat, vit=None, matfn=None):
        self._tw = to_world
        def material(k):
            r = self.roads[k]
            return asfalt_mat(r) if r['surface'] == 'asfalt' else roadmat[r['surface']]
        # bilvägar per material; överlapp: högre vägklass först
        grupper = {}
        ordning = sorted(self.bil_ytor, key=lambda k: -RANG.get(self.roads[k]['tags']['highway'], 2))
        for k in ordning:
            m = material(k)
            grupper.setdefault(m.name, [m, [], RANG.get(self.roads[k]['tags']['highway'], 2)])[1].append(self.poly[k])
        for p, k in self.fyll:
            m = material(k)
            grupper.setdefault(m.name, [m, [], RANG.get(self.roads[k]['tags']['highway'], 2)])[1].append(p)
        tagen = None
        n_tri = 0
        for namn, (m, ps, _) in sorted(grupper.items(), key=lambda kv: -kv[1][2]):
            y = unary_union(ps)
            if tagen is not None:
                y = y.difference(tagen)
            tagen = y if tagen is None else tagen.union(y)
            n_tri += self._mesh(y, h, sample, to_world, add_merged, m, broar.lyft({'highway': 'residential'}), BIL_CELL_M,
                                uv_fn=self.lage_uv)
        bil = tagen
        if vit is not None:
            n_tri += self._sparromraden(h, sample, to_world, add_merged, vit)
        if self.trottoar is not None:
            n_tri += self._trottoar_mesh(bil, h, sample, to_world, add_merged, matfn)
        # GC-vägar: rundade hörn över hela nätet, under bilvägarnas kant
        gg = {}
        for k in self.gc_ytor:
            m = material(k)
            gg.setdefault(m.name, [m, []])[1].append(self.poly[k])
        tagen = bil
        for namn, (m, ps) in gg.items():
            u = unary_union(ps)
            y = u.buffer(GC_RADIE_M, quad_segs=4).buffer(-GC_RADIE_M, quad_segs=4)
            if self.hinder:
                y = y.difference(unary_union(list(self.hinder)))
            y = y.union(u)
            if tagen is not None:
                y = y.difference(tagen)
            tagen = y if tagen is None else tagen.union(y)
            n_tri += self._mesh(y, h, sample, to_world, add_merged, m, broar.lyft({'highway': 'footway'}))
        # däcken: band på den raka profilen
        for k, s0, s1 in self.dack_bitar:
            msh = self._dack_band(k, s0, s1)
            if msh is not None:
                add_merged('Vagar', msh, material(k), uv=msh.metadata.get('uv'))
                n_tri += len(msh.faces)
        print('vägyta:', n_tri, 'trianglar')

    def sparr_polygoner(self):
        """De fyllda mittremsorna målas som spärrområden: kantlinje runt om och snedstreck."""
        delar = []
        if not self.mitt:
            return None
        # ihop (båda körbanornas fyllning), och öppet där en annan gata ansluter (svängfältet)
        namn = {self.roads[k]['tags'].get('name') for _, k in self.mitt}
        u_ = unary_union([p for p, _ in self.mitt])
        andra = [self.poly[k].buffer(SPARR_KORSNING_M) for k in self.bil_ytor
                 if self.roads[k]['tags'].get('name') not in namn and self.poly[k].intersects(u_.buffer(SPARR_KORSNING_M))]
        if andra:
            u_ = u_.difference(unary_union(andra))
        # bara mellanrummet: fyllningen går mittlinje till mittlinje, körbanorna själva målas inte
        korbanor = [self.poly[k] for k in self.bil_ytor if self.poly[k].intersects(u_)]
        if korbanor:
            u_ = u_.difference(unary_union(korbanor))
        for p in getattr(u_, 'geoms', [u_]):
            if p.geom_type != 'Polygon' or p.area < 2.0:
                continue
            if 2 * p.area / max(p.length, 1e-6) < SPARR_MIN_BREDD_M:
                continue
            inne = p.buffer(-SPARR_KANT_IN_M)
            if inne.is_empty:
                continue
            delar.append(inne.difference(inne.buffer(-SPARR_LINJE_M)))   # kantlinjen
            # snedstreck 45° mot remsans längdriktning
            rekt = np.array(p.minimum_rotated_rectangle.exterior.coords)
            e1, e2 = rekt[1] - rekt[0], rekt[2] - rekt[1]
            u = e1 if np.linalg.norm(e1) >= np.linalg.norm(e2) else e2
            u = u / max(np.linalg.norm(u), 1e-9)
            v = np.array([-u[1], u[0]])
            d = (u + v) / math.sqrt(2)
            n_ = np.array([-d[1], d[0]])
            c = np.array(p.centroid.coords[0])
            R_ = math.hypot(*(np.array(p.bounds[2:]) - np.array(p.bounds[:2]))) / 2 + 2
            streck = []
            for t in np.arange(-R_, R_, SPARR_STRECK_AVST_M):
                a0 = c + n_ * t - d * R_
                a1 = c + n_ * t + d * R_
                streck.append(shapely.LineString([a0, a1]).buffer(SPARR_STRECK_B_M / 2, cap_style='flat'))
            delar.append(unary_union(streck).intersection(inne))
        return unary_union(delar) if delar else None

    def _sparromraden(self, h, sample, to_world, add_merged, vit):
        y = self.sparr_polygoner()
        if y is None:
            return 0
        return self._mesh(y, h, sample, to_world, add_merged, vit, broar.lyft({'highway': 'residential'}) + 0.04, BIL_CELL_M)

    def refuger(self, punkter, h, sample, to_world, add_merged, matfn):
        """Upphöjda refuger vid övergångsställen med crossing:island=yes (OSM-noder på bilvägen):
        två öar med kantsten, gångbanan rakt igenom i vägens nivå. Bara dubbelriktade vägar minst
        REFUG_MIN_BREDD_M breda (mellan delade körbanor är mittremsan redan ön)."""
        topp_mat = matfn('Refug', (150, 146, 138), 0.9)
        kant_mat = matfn('Kantsten', (172, 170, 164), 0.8)
        dubbel = [k for k in self.bil_ytor if self.roads[k]['tags'].get('oneway') not in ('yes', '1', '-1')
                  and not self.roads[k].get('rondell')]
        if not dubbel:
            return 0
        trad = STRtree([self.roads[k]['line'] for k in dubbel])
        lyft = broar.lyft({'highway': 'residential'})
        n = 0
        lagda = []
        for pt, t in punkter:
            if t.get('crossing:island') != 'yes':
                continue
            p = pt if hasattr(pt, 'x') else Point(pt)
            if any(p.distance(q) < 10.0 for q in lagda):
                continue
            i = trad.nearest(p)
            k = dubbel[i]
            r = self.roads[k]
            L = r['line']
            if L.distance(p) > 2.0:
                continue
            sp = L.project(p)
            hw = float(np.interp(sp, r['s'], r['hw']))
            if 2 * hw < REFUG_MIN_BREDD_M or any(s0 - 5 <= sp <= s1 + 5 for s0, s1 in self.spann_k.get(k, [])):
                continue
            c = np.array(L.interpolate(sp).coords[0])
            d = np.array(L.interpolate(min(sp + 1, L.length)).coords[0]) - np.array(L.interpolate(max(sp - 1, 0)).coords[0])
            d /= max(np.linalg.norm(d), 1e-9)
            nn = np.array([-d[1], d[0]])
            o = shapely.LineString([c - d * REFUG_HALV_L_M, c + d * REFUG_HALV_L_M]).buffer(REFUG_B_M / 2, quad_segs=4)
            gang = shapely.Polygon([c - d * REFUG_GANG_M / 2 + nn * 3, c + d * REFUG_GANG_M / 2 + nn * 3,
                                    c + d * REFUG_GANG_M / 2 - nn * 3, c - d * REFUG_GANG_M / 2 - nn * 3])
            o = o.difference(gang)
            for del_ in getattr(o, 'geoms', [o]):
                if del_.geom_type != 'Polygon':
                    continue
                self._prisma(del_, h, sample, to_world, add_merged, topp_mat, kant_mat, lyft, REFUG_H_M)
                n += 1
            lagda.append(p)
            self.o_nosar += [(c - d * (REFUG_HALV_L_M - 0.5), -d), (c + d * (REFUG_HALV_L_M - 0.5), d)]
        print('vägyta: refuger', len(lagda))
        return n

    def _prisma(self, poly, h, sample, to_world, add_merged, topp_mat, kant_mat, lyft, hojd):
        """En låg ö: ovansida (triangulerad) och lodräta kanter ned till vägytan (och 5 cm under)."""
        ring = np.array(poly.exterior.coords)[:-1]
        zb = sample(h, ring[:, 0], ring[:, 1]) + lyft
        ztop = float(np.max(zb)) + hojd
        tri = shapely.get_parts(shapely.constrained_delaunay_triangles(poly))
        P = shapely.get_coordinates(tri).reshape(-1, 4, 2)[:, :3].reshape(-1, 2)
        x, z = to_world(P[:, 0], P[:, 1])
        V = np.column_stack([x, np.full(len(P), ztop), z])
        top = trimesh.Trimesh(V, np.arange(len(P)).reshape(-1, 3), process=False)
        ned = top.face_normals[:, 1] < 0
        top.faces[ned] = top.faces[ned][:, ::-1]
        add_merged('Vagar', top, topp_mat)
        # kanterna: utåt (ringen moturs = ytterkant till höger om kanten)
        if not shapely.LinearRing(ring).is_ccw:
            ring, zb = ring[::-1], zb[::-1]
        m = len(ring)
        xs, zs = to_world(ring[:, 0], ring[:, 1])
        V, F = [], []
        for a in range(m):
            b = (a + 1) % m
            base = len(V)
            V += [[xs[a], ztop, zs[a]], [xs[b], ztop, zs[b]], [xs[b], zb[b] - 0.05, zs[b]], [xs[a], zb[a] - 0.05, zs[a]]]
            F += [[base, base + 2, base + 1], [base, base + 3, base + 2]]
        sida = trimesh.Trimesh(np.array(V), np.array(F), process=False)
        # normalerna utåt från öns mitt
        c = np.array(poly.centroid.coords[0])
        cw = np.array(to_world(c[0], c[1]))
        mitt = sida.triangles_center[:, [0, 2]] - cw
        vand = (sida.face_normals[:, [0, 2]] * mitt).sum(1) < 0
        sida.faces[vand] = sida.faces[vand][:, ::-1]
        add_merged('Vagar', sida, kant_mat)

    def _trottoar_mesh(self, bil, h, sample, to_world, add_merged, matfn):
        """Trottoaren: kantsten TROTTOAR_H_M över gatan mot vägbanan, fall utåt till TROTTOAR_YTTER_M
        över marken; lodräta kanter runt om (kantsten)."""
        if matfn is None:
            return 0
        yta = matfn('Trottoar', (96, 96, 98), 0.85)
        kant = matfn('Kantsten', (172, 170, 164), 0.8)
        gata = bil.boundary if bil is not None else None
        bas = broar.lyft({'highway': 'residential'})

        def lyft(P):
            if gata is None:
                return np.full(len(P), bas + TROTTOAR_H_M)
            d = shapely.distance(shapely.points(P), gata)
            f = np.clip(d / TROTTOAR_B_M, 0, 1)
            return (bas + TROTTOAR_H_M) * (1 - f) + TROTTOAR_YTTER_M * f
        n = self._mesh(self.trottoar, h, sample, to_world, add_merged, yta, lyft)
        # kanterna
        V, F = [], []
        for p in getattr(self.trottoar, 'geoms', [self.trottoar]):
            for ring in [p.exterior] + list(p.interiors):
                R_ = np.array(ring.coords)
                # dela långa kanter var 2 m så att de följer marken
                pts = [R_[0]]
                for a, b in zip(R_[:-1], R_[1:]):
                    m_ = max(1, int(np.linalg.norm(b - a) / 2.0))
                    for t in np.linspace(0, 1, m_ + 1)[1:]:
                        pts.append(a + (b - a) * t)
                pts = np.array(pts)
                zt = sample(h, pts[:, 0], pts[:, 1]) + lyft(pts)
                zb = sample(h, pts[:, 0], pts[:, 1]) + min(bas, TROTTOAR_YTTER_M) - 0.08
                x, z = to_world(pts[:, 0], pts[:, 1])
                ccw = shapely.LinearRing(R_).is_ccw
                for i in range(len(pts) - 1):
                    b0 = len(V)
                    V += [[x[i], zt[i], z[i]], [x[i + 1], zt[i + 1], z[i + 1]],
                          [x[i + 1], zb[i + 1], z[i + 1]], [x[i], zb[i], z[i]]]
                    # ytterring moturs: utsidan till höger om kanten; hål tvärtom
                    if ccw == (ring is p.exterior):
                        F += [[b0, b0 + 1, b0 + 2], [b0, b0 + 2, b0 + 3]]
                    else:
                        F += [[b0, b0 + 2, b0 + 1], [b0, b0 + 3, b0 + 2]]
        if F:
            V, F = np.array(V), np.array(F)
            for t0 in range(0, len(F), 60000):
                ff = F[t0:t0 + 60000]
                idx = np.unique(ff)
                ny = np.searchsorted(idx, ff)
                msh = trimesh.Trimesh(V[idx], ny, process=False)
                for tx_key, sel in self._per_ruta(msh):
                    add_merged('Vagar', sel, kant)
            n += len(F)
        return n

    def _per_ruta(self, msh):
        """Delar en mesh per 250 m-ruta (add_merged lägger hela meshen i rutan där medelpunkten är)."""
        c = msh.triangles_center[:, [0, 2]]
        nyck = np.floor(c / RUTA_M).astype(int)
        for key in np.unique(nyck, axis=0):
            sel = np.all(nyck == key, axis=1)
            yield tuple(key), msh.submesh([np.nonzero(sel)[0]], append=True)

    def _mesh(self, y, h, sample, to_world, add_merged, m, lyft, cell=None, uv_fn=None):
        if y is None or y.is_empty:
            return 0
        E0, N0, E1, N1 = y.bounds
        n = 0
        for tx in np.arange(math.floor(E0 / RUTA_M) * RUTA_M, E1, RUTA_M):
            for ty in np.arange(math.floor(N0 / RUTA_M) * RUTA_M, N1, RUTA_M):
                d = y.intersection(shapely.box(tx, ty, tx + RUTA_M, ty + RUTA_M))
                if d.is_empty or d.area < 0.05:
                    continue
                msh = self._triangulera(d, h, sample, to_world, lyft, cell or CELL_M, uv_fn)
                if msh is not None:
                    add_merged('Vagar', msh, m, uv=msh.metadata.get('uv'))
                    n += len(msh.faces)
        return n

    def _triangulera(self, poly, h, sample, to_world, lyft, CELL_M=CELL_M, uv_fn=None):
        ox, oy = self.rutnat
        E0, N0, E1, N1 = poly.bounds
        xs = ox + np.arange(math.floor((E0 - ox) / CELL_M), math.ceil((E1 - ox) / CELL_M)) * CELL_M
        ys = oy + np.arange(math.floor((N0 - oy) / CELL_M), math.ceil((N1 - oy) / CELL_M)) * CELL_M
        X, Y = np.meshgrid(xs, ys)
        rutor = shapely.box(X.ravel(), Y.ravel(), X.ravel() + CELL_M, Y.ravel() + CELL_M)
        shapely.prepare(poly)
        traff = shapely.intersects(poly, rutor)
        if CELL_M > globals()['CELL_M'] + 1e-6 and traff.any():
            rutor = self._dela_ojamna(X, Y, traff, h, sample, CELL_M)
        else:
            rutor = rutor[traff]
        bitar = shapely.intersection(rutor, poly)
        bitar = shapely.get_parts(bitar[~shapely.is_empty(bitar)])
        bitar = bitar[shapely.get_type_id(bitar) == 3]
        if not len(bitar):
            return None
        tri = shapely.get_parts(shapely.constrained_delaunay_triangles(bitar))
        tri = tri[shapely.get_type_id(tri) == 3]
        if not len(tri):
            return None
        P = shapely.get_coordinates(tri).reshape(-1, 4, 2)[:, :3]
        nyck, inv = np.unique(np.round(P.reshape(-1, 2), 3), axis=0, return_inverse=True)
        yy = sample(h, nyck[:, 0], nyck[:, 1]) + (lyft(nyck) if callable(lyft) else lyft)
        x, z = to_world(nyck[:, 0], nyck[:, 1])
        F = inv.reshape(-1, 3)
        msh = trimesh.Trimesh(np.column_stack([x, yy, z]), F, process=False)
        ned = msh.face_normals[:, 1] < 0
        msh.faces[ned] = msh.faces[ned][:, ::-1]
        if uv_fn is not None:
            msh.metadata['uv'] = uv_fn(nyck)
        return msh

    def _dela_ojamna(self, X, Y, traff, h, sample, cell):
        """Rutorna (nedre vänstra hörn X, Y; de som träffar ytan i `traff`) som boxar, ojämna delade i fyra."""
        fin = globals()['CELL_M']
        x0, y0 = X.ravel(), Y.ravel()
        m = cell / 2
        # höjder i hörn, kantmitter och mitt; avvikelse från det bilinjära planet genom hörnen
        hx = [x0, x0 + m, x0 + cell]
        hy = [y0, y0 + m, y0 + cell]
        z = {(a, b): sample(h, hx[a], hy[b]) for a in range(3) for b in range(3)}
        avv = np.zeros(len(x0))
        for a, b in ((1, 0), (1, 2), (0, 1), (2, 1), (1, 1)):
            plan = (z[(0, 0)] * (2 - a) * (2 - b) + z[(2, 0)] * a * (2 - b) +
                    z[(0, 2)] * (2 - a) * b + z[(2, 2)] * a * b) / 4.0
            avv = np.maximum(avv, np.abs(z[(a, b)] - plan))
        ojamn = (avv > OJAMN_M).reshape(X.shape)
        ojamn = ndi.binary_dilation(ojamn, iterations=1) if ojamn.any() else ojamn
        oj = ojamn.ravel() & traff
        hela = traff & ~oj
        delar = [shapely.box(x0[hela], y0[hela], x0[hela] + cell, y0[hela] + cell)]
        n_ = int(round(cell / fin))
        for i in range(n_):
            for j in range(n_):
                xa, ya = x0[oj] + i * fin, y0[oj] + j * fin
                delar.append(shapely.box(xa, ya, xa + fin, ya + fin))
        return np.concatenate(delar)

    def lage_uv(self, P):
        """Vägytans läge per punkt (för asfaltens shader, hjulspåren): (v, hw) med v = avstånd åt vänster
        från närmaste bilvägs mittlinje och hw dess halva bredd (+ ENKEL_UV på enkelriktade körbanor);
        (0, -1) utanför vägens egen yta (korsningsrundningar, fickor)."""
        ut = np.tile([0.0, -1.0], (len(P), 1))
        if not len(P) or not self.bil_ytor:
            return ut
        if not hasattr(self, '_bil_trad'):
            self._bil_trad = STRtree([self.roads[k]['line'] for k in self.bil_ytor])
        pts = shapely.points(P)
        ix, jx = self._bil_trad.query_nearest(pts, all_matches=False)
        for j in np.unique(jx):
            sel = ix[jx == j]
            k = self.bil_ytor[j]
            r = self.roads[k]
            L = r['line']
            sp = shapely.line_locate_point(L, pts[sel])
            c = shapely.get_coordinates(shapely.line_interpolate_point(L, sp))
            fr = shapely.get_coordinates(shapely.line_interpolate_point(L, np.minimum(sp + 0.5, L.length)))
            ba = shapely.get_coordinates(shapely.line_interpolate_point(L, np.maximum(sp - 0.5, 0.0)))
            t = fr - ba
            t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-9)
            d = P[sel] - c
            v = t[:, 0] * d[:, 1] - t[:, 1] * d[:, 0]
            hw = np.interp(sp, r['s'], r['hw'])
            inne = np.abs(v) <= hw + 0.3
            enkel = r['tags'].get('oneway') in ('yes', '1', '-1') or bool(r.get('rondell'))
            ut[sel[inne], 0] = v[inne]
            ut[sel[inne], 1] = hw[inne] + (ENKEL_UV if enkel else 0.0)
        return ut

    def _dack_band(self, k, s0, s1):
        r = self.roads[k]
        L = r['line']
        n = max(2, int(math.ceil((s1 - s0) / 2.0)) + 1)
        ss = np.linspace(s0, s1, n)
        pts = np.array([L.interpolate(d).coords[0] for d in ss])
        dv = np.gradient(pts, axis=0)
        dv /= np.maximum(np.linalg.norm(dv, axis=1, keepdims=True), 1e-9)
        nrm = np.c_[-dv[:, 1], dv[:, 0]]
        hw = np.interp(ss, r['s'], r['hw'])[:, None]
        z = np.interp(ss, r['s'], r['z']) + broar.lyft(r['tags'])
        z = np.maximum(z, self.tak_hojd(pts, k))
        Lp, Rp = pts + nrm * hw, pts - nrm * hw
        wl = np.column_stack(to_world_pair(self._tw, Lp))
        wr = np.column_stack(to_world_pair(self._tw, Rp))
        V = np.empty((2 * n, 3))
        V[0::2] = np.c_[wl[:, 0], z, wl[:, 1]]
        V[1::2] = np.c_[wr[:, 0], z, wr[:, 1]]
        a = np.arange(n - 1) * 2
        F = np.r_[np.c_[a, a + 1, a + 2], np.c_[a + 1, a + 3, a + 2]]
        msh = trimesh.Trimesh(V, F, process=False)
        if msh.face_normals[:, 1].mean() < 0:
            msh.faces = msh.faces[:, ::-1]
        if not _ar_gc(r):
            hwv = hw[:, 0] + (ENKEL_UV if r['tags'].get('oneway') in ('yes', '1', '-1') else 0.0)
            uv = np.empty((2 * n, 2))
            uv[0::2] = np.c_[hw[:, 0], hwv]
            uv[1::2] = np.c_[-hw[:, 0], hwv]
            msh.metadata['uv'] = uv
        return msh


def to_world_pair(to_world, P):
    x, z = to_world(P[:, 0], P[:, 1])
    return np.asarray(x), np.asarray(z)
