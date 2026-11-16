"""Detaljer på vägytan (step3, efter vagyta.Vagyta.bygg): linjer vid korsningar, pilar, farthinder.

  väjningslinje  OSM highway=give_way: trianglar (bas 0,5 m, 0,7 m långa) tvärs över det egna körfältet,
                 spetsen mot föraren; stopp-plikt (highway=stop) en heldragen 0,4 m stopplinje.
  stopplinje     trafikljus: OSM highway=traffic_signals i en korsning (en linje per tillfart) eller längs
                 vägen (traffic_signals:direction, annars mot närmaste korsning); vid signalreglerade
                 övergångsställen en linje på var sida.
                 Riktning: OSM direction=forward/backward, annars mot närmaste korsning (vägände där andra
                 bilvägar möts). En nod i själva korsningen flyttas tillbaka korsande vägs halva bredd + 1 m.
  svängpilar     OSM turn:lanes (enkelriktade körbanor), turn:lanes:forward/backward (dubbelriktade):
                 en pil per körfält (left, right, through och kombinationer; slight_* som raka) med spetsen
                 PIL_FORE_M före korsningen och en till PIL_AVST_M längre bak om sträckan räcker.
  farthinder     OSM traffic_calming på bilvägen: hump (4 m, 8 cm, cos²-profil), bump/dynamic_bump (kort),
                 table (upphöjd korsning/övergångsställe: ramper 1,5 m, platå, 10 cm; noder eller vägar),
                 cushion (en kudde per körfält, 1,8 × 3 m), island (trafikö på mitten), choker (avsmalning:
                 kantstensuddar från båda kanterna), chicane (uddar växelvis). Profilen läggs på vägytans
                 plan (bilinjärt mellan de 4 m-celler vägytan trianguleras med), med en kjol nedåt runt om.
Allt ligger i glb-gruppen Vagar (ingen kollision: tankarna kör på terrängen). Inget på broar.
"""
import math

import numpy as np
import shapely
import trimesh
from shapely.geometry import Point, Polygon, LineString
from shapely.ops import unary_union
from shapely.strtree import STRtree

import broar
import vagyta

KORS_TOL_M = 1.5
LINJE_LYFT = 0.015          # över vägytans plan (bilinjärt mellan 4 m-cellernas hörn)
VAJ_BAS_M, VAJ_L_M, VAJ_STEG_M = 0.5, 0.7, 0.75
STOPP_B_M = 0.4
KANT_IN_M = 0.3
SIGNAL_OVERGANG_M = 3.0     # stopplinjen så långt före övergångsstället (signalreglerat)
PIL_FORE_M = 4.0            # pilspetsen så här långt före stopplinjens läge
PIL_AVST_M = 25.0
PIL_L_M = 5.0
PIL_SKAFT_B = 0.2
PIL_HUVUD_B = 0.75
PIL_HUVUD_L = 1.3
HINDER = {  # (längd längs vägen, höjd)
    'hump': (4.0, 0.08), 'bump': (1.2, 0.06), 'dynamic_bump': (0.9, 0.05), 'table': (7.0, 0.10),
}
RAMP_M = 1.5                # upphöjd korsning: rampernas längd
RAMP_TRI_B_M, RAMP_TRI_L_M, RAMP_TRI_STEG_M = 0.6, 1.0, 1.2   # trianglarna på uppfarten
KUDDE_B_M, KUDDE_L_M, KUDDE_H_M, KUDDE_RAMP_M = 1.8, 3.0, 0.07, 0.5
O_L_M, O_B_M, O_H_M = 7.0, 1.4, 0.12          # trafikö (traffic_calming=island)
UDD_L_M, UDD_DJUP_M, UDD_H_M = 5.0, 1.0, 0.12  # avsmalningens kantstensuddar
UDD_MIN_KVAR_M = 4.5        # så här mycket körbana måste finnas kvar
CHICANE_AVST_M = 4.0
FIN_CELL_M = 0.5


class Vagdetaljer:
    def __init__(self, VY, roads, punkter, h, sample, to_world, add_merged, vit, asfalt_mat, roadmat, matfn):
        self.VY, self.roads, self.h, self.sample, self.tw = VY, roads, h, sample, to_world
        self.add, self.vit, self.matfn = add_merged, vit, matfn
        self.asfalt_mat, self.roadmat = asfalt_mat, roadmat
        self.punkter = [(pt if hasattr(pt, 'x') else Point(pt), t) for pt, t in (punkter or [])]
        self.bil = [k for k in VY.bil_ytor if roads[k]['surface'] == 'asfalt']
        self.trad = STRtree([roads[k]['line'] for k in self.bil])
        self.alla_bil = list(VY.bil_ytor)
        self.atrad = STRtree([roads[k]['line'] for k in self.alla_bil])
        self.lyft = broar.lyft({'highway': 'residential'})
        self.linjer = []          # polygoner (SWEREF) i vitt
        self.n = dict(vaj=0, stopp=0, signal=0, pilar=0, hinder=0, oar=0, uddar=0)

    # ------------------------------------------------------------------ hjälp
    def _enkel(self, r):
        o = r['tags'].get('oneway')
        return 1 if o in ('yes', '1', 'true') or r.get('rondell') else -1 if o == '-1' else 0

    def _pa_dack(self, k, sp, marg=3.0):
        return any(s0 - marg <= sp <= s1 + marg for s0, s1 in self.VY.spann_k.get(k, []))

    def _ram(self, r, sp):
        """(punkt, enhetsriktning längs linjen, vänsternormal, halvbredd) vid sp."""
        L = r['line']
        sp = min(max(sp, 0.0), L.length)
        c = np.array(L.interpolate(sp).coords[0])
        d = np.array(L.interpolate(min(sp + 1, L.length)).coords[0]) - np.array(L.interpolate(max(sp - 1, 0)).coords[0])
        d /= max(np.linalg.norm(d), 1e-9)
        return c, d, np.array([-d[1], d[0]]), float(np.interp(sp, r['s'], r['hw']))

    def _andra_vid(self, k, p, tol=KORS_TOL_M):
        """Andra bilvägar vid punkten p (index i roads)."""
        idx = self.atrad.query(Point(p), predicate='dwithin', distance=tol)
        return [self.alla_bil[i] for i in idx if self.alla_bil[i] != k]

    def _korsningsande(self, k):
        """{0: halvbredd, L: halvbredd} för vägändar där andra bilvägar möts (korsande vägs halva bredd)."""
        r = self.roads[k]
        L = r['line']
        ut = {}
        for s_, p in ((0.0, L.coords[0]), (L.length, L.coords[-1])):
            andra = self._andra_vid(k, p)
            # en korsning: två andra vägändar möts här, eller en väg går igenom (inte bara nästa OSM-bit)
            pp = Point(p)
            ander = sum(1 for j in andra if min(pp.distance(Point(self.roads[j]['line'].coords[i])) for i in (0, -1))
                        < KORS_TOL_M)
            if andra and (ander >= 2 or ander < len(andra)):
                hw = max(float(np.interp(self.roads[j]['line'].project(Point(p)), self.roads[j]['s'], self.roads[j]['hw']))
                         for j in andra)
                ut[s_] = hw
        return ut

    def _vag_vid(self, p, tol=1.0):
        """Närmaste asfalterade bilväg genom p (k, sp) eller None."""
        if not self.bil:
            return None
        i = self.trad.nearest(p)
        k = self.bil[i]
        L = self.roads[k]['line']
        if L.distance(p) > tol:
            return None
        return k, L.project(p)

    # ------------------------------------------------------------------ linjer
    def _tvarlinje(self, k, s_linje, rikt, typ):
        """Väjnings-/stopplinje på vägen k vid s_linje för trafik i riktning rikt (+1 = längs linjen):
        över det egna körfältet (hela bredden på enkelriktade)."""
        r = self.roads[k]
        if self._pa_dack(k, s_linje):
            return False
        c, d, nl, hw = self._ram(r, s_linje)
        t = d * rikt                       # färdriktningen (mot korsningen)
        hoger = -nl * rikt
        if self._enkel(r):
            v0, v1 = -(hw - KANT_IN_M), hw - KANT_IN_M   # i högernormalens led
        else:
            v0, v1 = 0.15, hw - KANT_IN_M
        if v1 - v0 < 1.0:
            return False
        if typ == 'vaj':
            antal = int((v1 - v0) / VAJ_STEG_M)
            start = v0 + ((v1 - v0) - antal * VAJ_STEG_M) / 2 + (VAJ_STEG_M - VAJ_BAS_M) / 2
            for i in range(antal):
                a = start + i * VAJ_STEG_M
                b0 = c + hoger * a
                b1 = c + hoger * (a + VAJ_BAS_M)
                spets = c + hoger * (a + VAJ_BAS_M / 2) - t * VAJ_L_M
                self.linjer.append(Polygon([b0, b1, spets]))
        else:
            self.linjer.append(Polygon([c + hoger * v0, c + hoger * v1, c + hoger * v1 - t * STOPP_B_M,
                                        c + hoger * v0 - t * STOPP_B_M]))
        return True

    def _mot_korsning(self, k, sp, tagg_riktning=None):
        """(riktning, s för linjen) för en nod på vägen k vid sp."""
        r = self.roads[k]
        L = r['line']
        ander = self._korsningsande(k)
        if tagg_riktning in ('forward', 'backward'):
            rikt = 1 if tagg_riktning == 'forward' else -1
        elif ander:
            ande = min(ander, key=lambda s_: abs(s_ - sp))
            rikt = 1 if ande > sp or (ande == sp and ande > 0) else -1
            if abs(ande - sp) < 0.5:
                rikt = 1 if ande > 0 else -1
        else:
            return None
        ande = L.length if rikt > 0 else 0.0
        bak = ander.get(ande)
        s_ = sp
        if bak is not None:   # i korsningen: tillbaka till korsande vägs kant + 1 m
            minst = bak + 1.0
            if abs(ande - sp) < minst:
                s_ = ande - rikt * minst
        if not (0.5 < s_ < L.length - 0.5):
            return None
        return rikt, s_

    def vajningslinjer(self):
        for p, t in self.punkter:
            hwy = t.get('highway')
            if hwy not in ('give_way', 'stop'):
                continue
            # en nod i korsningen: den minsta vägen som slutar där
            idx = self.trad.query(p, predicate='dwithin', distance=1.0)
            slutar = [self.bil[i] for i in idx
                      if min(p.distance(Point(self.roads[self.bil[i]]['line'].coords[j])) for j in (0, -1)) < 1.0]
            if len(slutar) >= 2:
                k = min(slutar, key=lambda j: vagyta.RANG.get(self.roads[j]['tags']['highway'], 2))
                sp = self.roads[k]['line'].project(p)
            else:
                hit = self._vag_vid(p)
                if hit is None:
                    continue
                k, sp = hit
            res = self._mot_korsning(k, sp, t.get('direction'))
            if res is None:
                continue
            rikt, s_ = res
            if self._enkel(self.roads[k]) and rikt != self._enkel(self.roads[k]):
                continue
            typ = 'vaj' if hwy == 'give_way' else 'stopp'
            if self._tvarlinje(k, s_, rikt, typ):
                self.n[typ] += 1

    def signallinjer(self):
        gjorda = []
        for p, t in self.punkter:
            if t.get('highway') != 'traffic_signals' and t.get('crossing') != 'traffic_signals':
                continue
            if any(p.distance(q) < 6.0 for q in gjorda):
                continue
            gjorda.append(p)
            overgang = t.get('crossing') == 'traffic_signals' or t.get('highway') == 'crossing'
            # en nod i korsningen: en linje per tillfart
            idx = self.trad.query(p, predicate='dwithin', distance=KORS_TOL_M)
            ander = []
            for i in idx:
                k = self.bil[i]
                L = self.roads[k]['line']
                for s_, q in ((0.0, L.coords[0]), (L.length, L.coords[-1])):
                    if p.distance(Point(q)) < KORS_TOL_M:
                        ander.append((k, s_))
            if len(ander) >= 3 and not overgang:
                for k, ande in ander:
                    r = self.roads[k]
                    rikt = 1 if ande > 0 else -1
                    e = self._enkel(r)
                    if e and e != rikt:
                        continue
                    bak = max(float(np.interp(self.roads[j]['line'].project(p), self.roads[j]['s'], self.roads[j]['hw']))
                              for j, _ in ander if j != k) + 2.0
                    s_ = ande - rikt * bak
                    if 0.5 < s_ < r['line'].length - 0.5 and self._tvarlinje(k, s_, rikt, 'stopp'):
                        self.n['signal'] += 1
                continue
            hit = self._vag_vid(p)
            if hit is None:
                continue
            k, sp = hit
            r = self.roads[k]
            if overgang:   # en på var sida om övergångsstället
                for rikt in (1, -1):
                    e = self._enkel(r)
                    if e and e != rikt:
                        continue
                    s_ = sp - rikt * SIGNAL_OVERGANG_M
                    if 0.5 < s_ < r['line'].length - 0.5 and self._tvarlinje(k, s_, rikt, 'stopp'):
                        self.n['signal'] += 1
                continue
            res = self._mot_korsning(k, sp, t.get('traffic_signals:direction') or t.get('direction'))
            if res is None:
                continue
            rikt, s_ = res
            if self._tvarlinje(k, s_, rikt, 'stopp'):
                self.n['signal'] += 1

    # ------------------------------------------------------------------ pilar
    @staticmethod
    def _pilform(varden):
        """Pilen i körfältets ram (u framåt, v åt vänster), spetsen vid u = 0. None = ingen pil."""
        delar = []
        vanster = any(v in ('left', 'sharp_left') for v in varden)
        hoger = any(v in ('right', 'sharp_right') for v in varden)
        rakt = any(v in ('through', 'slight_left', 'slight_right') for v in varden)
        if not (vanster or hoger or rakt):
            return None
        bo = -PIL_L_M + 2.2 + PIL_HUVUD_L   # svängens läge (u)
        topp = 0.0 if rakt else bo + PIL_SKAFT_B / 2
        delar.append(Polygon([(-PIL_L_M, -PIL_SKAFT_B / 2), (topp - (PIL_HUVUD_L if rakt else 0), -PIL_SKAFT_B / 2),
                              (topp - (PIL_HUVUD_L if rakt else 0), PIL_SKAFT_B / 2), (-PIL_L_M, PIL_SKAFT_B / 2)]))
        if rakt:
            delar.append(Polygon([(-PIL_HUVUD_L, -PIL_HUVUD_B / 2), (0, 0), (-PIL_HUVUD_L, PIL_HUVUD_B / 2)]))
        for tecken, med in ((1, vanster), (-1, hoger)):
            if not med:
                continue
            arm = 0.45
            delar.append(Polygon([(bo - PIL_SKAFT_B / 2, 0), (bo + PIL_SKAFT_B / 2, 0),
                                  (bo + PIL_SKAFT_B / 2, tecken * arm), (bo - PIL_SKAFT_B / 2, tecken * arm)]))
            delar.append(Polygon([(bo - PIL_HUVUD_B / 2, tecken * arm), (bo, tecken * (arm + PIL_HUVUD_L * 0.75)),
                                  (bo + PIL_HUVUD_B / 2, tecken * arm)]))
        return unary_union([d.buffer(0) for d in delar])

    def _pilar_riktning(self, k, varde, rikt, sida_halv):
        """Pilar för körfälten i varde ('left|through;right') i riktning rikt. sida_halv: körfälten fyller
        bara den egna halvan (dubbelriktad väg)."""
        r = self.roads[k]
        L = r['line']
        falt = varde.split('|')
        n = len(falt)
        if n == 0 or n > 6:
            return
        ander = self._korsningsande(k)
        ande = L.length if rikt > 0 else 0.0
        if ande not in ander:
            return
        fore = ander[ande] + 1.0 + PIL_FORE_M
        for avst in (fore, fore + PIL_AVST_M):
            s_tip = ande - rikt * avst
            s_bak = s_tip - rikt * PIL_L_M
            if not (0.5 < min(s_tip, s_bak) and max(s_tip, s_bak) < L.length - 0.5):
                break
            if self._pa_dack(k, s_tip) or self._pa_dack(k, s_bak):
                break
            c, d, nl, hw = self._ram(r, s_tip)
            t = d * rikt
            vl = nl * rikt                  # vänster i färdriktningen
            bredd = hw if sida_halv else 2 * hw
            lw = bredd / n
            if lw < 2.2:
                break
            for i, f in enumerate(falt):
                form = self._pilform([x.strip() for x in f.split(';')])
                if form is None:
                    continue
                # körfälten från vänster: mitten (eller vänsterkanten) och åt höger
                v = (-(i + 0.5) * lw) if sida_halv else (hw - (i + 0.5) * lw)
                for g in getattr(form, 'geoms', [form]):
                    P = np.array(g.exterior.coords)
                    W = c[None, :] + t[None, :] * P[:, :1] + vl[None, :] * (P[:, 1:2] + v)
                    self.linjer.append(Polygon(W))
                self.n['pilar'] += 1

    def svangpilar(self):
        for k in self.bil:
            r = self.roads[k]
            tg = r['tags']
            e = self._enkel(r)
            if r.get('rondell'):
                continue
            if e and tg.get('turn:lanes'):
                self._pilar_riktning(k, tg['turn:lanes'], e, False)
            if not e:
                if tg.get('turn:lanes:forward'):
                    self._pilar_riktning(k, tg['turn:lanes:forward'], 1, True)
                if tg.get('turn:lanes:backward'):
                    self._pilar_riktning(k, tg['turn:lanes:backward'], -1, True)

    # ------------------------------------------------------------------ farthinder
    def _plan(self, P):
        """Vägytans höjd minus terrängens (sample) i P: bilinjärt mellan 4 m-cellernas hörn + lyftet."""
        ox, oy = self.VY.rutnat
        C = vagyta.BIL_CELL_M
        x0 = ox + np.floor((P[:, 0] - ox) / C) * C
        y0 = oy + np.floor((P[:, 1] - oy) / C) * C
        fx, fy = (P[:, 0] - x0) / C, (P[:, 1] - y0) / C
        s = self.sample
        z = (s(self.h, x0, y0) * (1 - fx) * (1 - fy) + s(self.h, x0 + C, y0) * fx * (1 - fy) +
             s(self.h, x0, y0 + C) * (1 - fx) * fy + s(self.h, x0 + C, y0 + C) * fx * fy)
        return z - s(self.h, P[:, 0], P[:, 1]) + self.lyft

    def _upphojd(self, poly, profil, mat):
        """Ytan poly med höjden profil(P) över vägytans plan och en kjol runt om ned under vägytan."""
        if poly.is_empty or poly.area < 0.2:
            return
        lyft = lambda P: self._plan(P) + 0.012 + profil(P)
        msh = self.VY._triangulera(poly, self.h, self.sample, self.tw, lyft, FIN_CELL_M)
        if msh is None:
            return
        self.add('Vagar', msh, mat)
        V, F = [], []
        for p in getattr(poly, 'geoms', [poly]):
            if p.geom_type != 'Polygon':
                continue
            R_ = np.array(p.exterior.coords)
            pts = [R_[0]]
            for a, b in zip(R_[:-1], R_[1:]):
                m_ = max(1, int(np.linalg.norm(b - a) / FIN_CELL_M))
                for tt in np.linspace(0, 1, m_ + 1)[1:]:
                    pts.append(a + (b - a) * tt)
            pts = np.array(pts)
            g = self.sample(self.h, pts[:, 0], pts[:, 1])
            zt = g + lyft(pts)
            zb = g + self._plan(pts) - 0.05
            x, z = self.tw(pts[:, 0], pts[:, 1])
            ccw = shapely.LinearRing(R_).is_ccw
            for i in range(len(pts) - 1):
                b0 = len(V)
                V += [[x[i], zt[i], z[i]], [x[i + 1], zt[i + 1], z[i + 1]], [x[i + 1], zb[i + 1], z[i + 1]], [x[i], zb[i], z[i]]]
                F += [[b0, b0 + 1, b0 + 2], [b0, b0 + 2, b0 + 3]] if ccw else [[b0, b0 + 2, b0 + 1], [b0, b0 + 3, b0 + 2]]
        if F:
            self.add('Vagar', trimesh.Trimesh(np.array(V), np.array(F), process=False), mat)

    def _material(self, k):
        r = self.roads[k]
        return self.asfalt_mat(r) if r['surface'] == 'asfalt' else self.roadmat[r['surface']]

    def _gupp(self, k, sp, typ, langd=None):
        r = self.roads[k]
        if self._pa_dack(k, sp, 6.0):
            return False
        c, d, nl, hw = self._ram(r, sp)
        L, H = HINDER[typ]
        if langd:
            L = langd
        yta = self.VY.poly.get(k)
        if yta is None:
            return False
        rekt = Polygon([c - d * L / 2 + nl * (hw + 0.5), c + d * L / 2 + nl * (hw + 0.5),
                        c + d * L / 2 - nl * (hw + 0.5), c - d * L / 2 - nl * (hw + 0.5)])
        fp = rekt.intersection(yta)

        def profil(P):
            u = (P - c) @ d
            if typ == 'table':
                return H * np.clip((L / 2 - np.abs(u)) / RAMP_M, 0, 1)
            return H * np.cos(np.clip(u / L, -0.5, 0.5) * math.pi) ** 2
        self._upphojd(fp, profil, self._material(k))
        if typ in ('hump', 'table'):
            self._rampmarkering(k, c, d, nl, hw, L, RAMP_M if typ == 'table' else L / 2, profil)
        return True

    def _rampmarkering(self, k, c, d, nl, hw, L, ramp, profil):
        """Vita trianglar på uppfarten (spetsen i färdriktningen) över det egna körfältet."""
        e = self._enkel(self.roads[k])
        tri = []
        for rikt in (1, -1):
            if e and e != rikt:
                continue
            t = d * rikt
            hoger = -nl * rikt
            v0, v1 = (-(hw - KANT_IN_M), hw - KANT_IN_M) if e else (0.3, hw - KANT_IN_M)
            if v1 - v0 < 1.0:
                continue
            bas = c - t * (L / 2 - 0.15)
            lang = min(RAMP_TRI_L_M, ramp - 0.2)
            antal = int((v1 - v0) / RAMP_TRI_STEG_M)
            start = v0 + ((v1 - v0) - antal * RAMP_TRI_STEG_M) / 2 + RAMP_TRI_STEG_M / 2
            for i in range(antal):
                m = bas + hoger * (start + i * RAMP_TRI_STEG_M)
                tri.append(Polygon([m - hoger * RAMP_TRI_B_M / 2, m + hoger * RAMP_TRI_B_M / 2, m + t * lang]))
        if not tri:
            return
        y = unary_union(tri)
        msh = self.VY._triangulera(y, self.h, self.sample, self.tw,
                                   lambda P: self._plan(P) + 0.012 + profil(P) + 0.008, FIN_CELL_M)
        if msh is not None:
            self.add('Vagar', msh, self.vit)

    def _kuddar(self, k, sp):
        r = self.roads[k]
        if self._pa_dack(k, sp, 6.0):
            return False
        c, d, nl, hw = self._ram(r, sp)
        e = self._enkel(r)
        mitter = [0.0] if (e and hw < 3.0) else ([hw / 2, -hw / 2] if not e else [hw / 2, -hw / 2])
        for v in mitter:
            m = c + nl * v

            def profil(P, m=m):
                u = np.abs((P - m) @ d)
                w = np.abs((P - m) @ nl)
                return KUDDE_H_M * np.clip(np.minimum((KUDDE_L_M / 2 - u), (KUDDE_B_M / 2 - w)) / KUDDE_RAMP_M, 0, 1)
            fp = Polygon([m - d * KUDDE_L_M / 2 + nl * KUDDE_B_M / 2, m + d * KUDDE_L_M / 2 + nl * KUDDE_B_M / 2,
                          m + d * KUDDE_L_M / 2 - nl * KUDDE_B_M / 2, m - d * KUDDE_L_M / 2 - nl * KUDDE_B_M / 2])
            self._upphojd(fp, profil, self._material(k))
        return True

    def _kantsten_mat(self):
        return self.matfn('Refug', (150, 146, 138), 0.9), self.matfn('Kantsten', (172, 170, 164), 0.8)

    def _o(self, k, sp):
        r = self.roads[k]
        if self._enkel(r) or self._pa_dack(k, sp, 6.0):
            return False
        c, d, nl, hw = self._ram(r, sp)
        if 2 * hw < vagyta.REFUG_MIN_BREDD_M:
            return False
        o = LineString([c - d * (O_L_M - O_B_M) / 2, c + d * (O_L_M - O_B_M) / 2]).buffer(O_B_M / 2, quad_segs=6)
        topp, kant = self._kantsten_mat()
        self.VY._prisma(o, self.h, self.sample, self.tw, self.add, topp, kant, self.lyft, O_H_M)
        self.VY.o_nosar += [(c - d * (O_L_M / 2 - 0.5), -d), (c + d * (O_L_M / 2 - 0.5), d)]
        return True

    def _udd(self, k, sp, sida, langd=UDD_L_M):
        """En kantstensudde från vägkanten på sidan sida (+1 vänster om linjen) vid sp."""
        r = self.roads[k]
        if self._pa_dack(k, sp, 6.0):
            return False
        c, d, nl, hw = self._ram(r, sp)
        djup = min(UDD_DJUP_M, (2 * hw - UDD_MIN_KVAR_M) / 2)
        if djup < 0.5:
            return False
        kant = c + nl * sida * hw
        inne = kant - nl * sida * djup
        p = Polygon([kant - d * langd / 2 + nl * sida * 0.3, kant + d * langd / 2 + nl * sida * 0.3,
                     inne + d * (langd / 2 - djup), inne - d * (langd / 2 - djup)]).buffer(0)
        yta = self.VY.poly.get(k)
        if yta is not None:
            p = p.intersection(yta)
        p = max(getattr(p, 'geoms', [p]), key=lambda g: g.area) if not p.is_empty else p
        if p.is_empty or p.geom_type != 'Polygon' or p.area < 1.0:
            return False
        topp, kantmat = self._kantsten_mat()
        self.VY._prisma(p, self.h, self.sample, self.tw, self.add, topp, kantmat, self.lyft, UDD_H_M)
        return True

    def farthinder(self):
        lagda = []

        def ny(p, avst=3.0):
            if any(p.distance(q) < avst for q in lagda):
                return False
            lagda.append(p)
            return True
        for p, t in self.punkter:
            tc = t.get('traffic_calming')
            if not tc:
                continue
            hit = self._vag_vid(p, 2.0)
            if hit is None or not ny(p):
                continue
            k, sp = hit
            ok = False
            if tc in HINDER:
                ok = self._gupp(k, sp, tc)
            elif tc == 'cushion':
                ok = self._kuddar(k, sp)
            elif tc == 'island':
                ok = self._o(k, sp)
                self.n['oar'] += ok
                continue
            elif tc == 'choker':
                ok = self._udd(k, sp, 1) | self._udd(k, sp, -1)
                self.n['uddar'] += ok
                continue
            elif tc == 'chicane':
                ok = self._udd(k, sp - CHICANE_AVST_M, 1) | self._udd(k, sp + CHICANE_AVST_M, -1)
                self.n['uddar'] += ok
                continue
            self.n['hinder'] += bool(ok)
        # vägar taggade traffic_calming: sträckan är hindret
        for k in self.alla_bil:
            r = self.roads[k]
            tc = r['tags'].get('traffic_calming')
            if not tc:
                continue
            L = r['line']
            mitt = L.interpolate(0.5, normalized=True)
            if not ny(mitt, 4.0):
                continue
            if tc == 'table' and L.length < 30:
                self.n['hinder'] += self._gupp(k, L.length / 2, 'table', langd=max(L.length, 4.0))
            elif tc == 'choker' and L.length < 30:
                self.n['uddar'] += self._udd(k, L.length / 2, 1, max(L.length, UDD_L_M)) | \
                    self._udd(k, L.length / 2, -1, max(L.length, UDD_L_M))

    # ------------------------------------------------------------------
    def bygg(self):
        self.vajningslinjer()
        self.signallinjer()
        self.svangpilar()
        self.farthinder()
        n_tri = 0
        if self.linjer:
            y = unary_union([p.buffer(0) for p in self.linjer if p.is_valid or p.buffer(0).is_valid])
            n_tri = self.VY._mesh(y, self.h, self.sample, self.tw, self.add, self.vit,
                                  lambda P: self._plan(P) + LINJE_LYFT, vagyta.BIL_CELL_M)
        print('vägdetaljer: väjningslinjer {vaj}, stopplinjer {stopp}, vid trafikljus {signal}, svängpilar {pilar}, '
              'farthinder {hinder}, trafiköar {oar}, avsmalningar {uddar}'.format(**self.n), f'({n_tri} trianglar linjer)')
