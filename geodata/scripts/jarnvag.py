"""Järnväg ur OSM (railway=rail): banvall, makadam, sliprar, räls, kontaktledning, broar och plattformar.

Anropas från step3_build.py:
    BANA = jarnvag.Jarnvag(feat['rails'], feat['platforms'], BOX, h_raw, sample)
    BANA.forma(h, (H, W), T, OX, OY, RES)          # banvallen i höjdmodellen (efter vägar och vatten)
    BANA.spara_mask(fil, (H, W), T)                 # step4: inga träd eller buskar nära spåret
    BANA.marktacke(lc, CIDX['väg_grus'], (H, W), T)
    BANA.bygg_meshar(h, sample, to_world, add_merged, mat)

Höjden: makadamens överkant zb följer markhöjdmodellen (lasern ser banvallens krön), utjämnad i
planet över alla spår (parallella spår och växlar hamnar på samma nivå). Över broar (bridge=yes)
används bara punkter utanför bron, så profilen går rakt över vägen under.
Glb-grupper: `Jarnvag` (utseende: makadam, sliprar, räls, ledningar, utliggare) och `Banhinder`
(kollision: stolpar, brodäck, landfästen, plattformar).
"""
import numpy as np
from scipy.spatial import cKDTree
from rasterio.features import rasterize
from shapely.geometry import Polygon
import shapely
import trimesh

STEG_M = 2.0                  # punkter längs spåret
UTJAMNING_M = 15.0            # gaussisk utjämning av profilen (sigma)
UTJAMNING_RADIE_M = 45.0
BRO_MARGINAL_M = 6.0          # punkter så nära en bro räknas inte till profilen (vallen sluttar ner mot vägen)
SPARVIDD_M = 1.435
RALS_B, RALS_H = 0.07, 0.17   # rälsens bredd och höjd ovanför sliperns överkant
SLIPER_L, SLIPER_B, SLIPER_H, SLIPER_DELNING = 2.6, 0.25, 0.20, 0.65
MAKADAM = [(-3.0, -0.7), (-1.75, 0.15), (1.75, 0.15), (3.0, -0.7)]   # (sidled, höjd över zb)
FORM_HW, FORM_SLANT_M, FORM_UNDER = 2.4, 6.0, 0.25   # marken: plan ±2,4 m strax under zb, mjuk övergång 6 m
TRADFRITT_M = 8.0             # inga träd/buskar närmare spårmitt än så
STOLPE_DELNING_M = 60.0
STOLPE_SIDLED_M = 3.2
KONTAKT_OVER_RALS, BAR_OVER_RALS, BAR_NEDHANG = 5.5, 6.7, 0.45
SICKSACK_M = 0.2
PERRONG_OVER_RALS = 0.58
SERVICE = ('crossover', 'siding', 'yard', 'spur')


def _norm(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-9)


def kuboider(C, ta_bort_botten=True):
    """C: (n, 8, 3) hörn, botten 0-3 i ring och topp 4-7 i samma ordning.
    Ger (V, F_sidor, F_topp) med normalerna utåt (kontroll mot kroppens mitt)."""
    n = len(C)
    F = []
    if not ta_bort_botten:
        F += [(0, 2, 1), (0, 3, 2)]
    topp = [(4, 5, 6), (4, 6, 7)]
    sidor = []
    for i in range(4):
        j = (i + 1) % 4
        sidor += [(i, j, 4 + j), (i, 4 + j, 4 + i)]
    sidor = F + sidor
    V = C.reshape(-1, 3)
    mitt = C.mean(1)

    def bygg(mall):
        mall = np.array(mall)
        Fa = (mall[None, :, :] + 8 * np.arange(n)[:, None, None])
        tri = V[Fa]                                     # (n, k, 3, 3)
        nr = np.cross(tri[..., 1, :] - tri[..., 0, :], tri[..., 2, :] - tri[..., 0, :])
        ut = tri.mean(2) - mitt[:, None, :]
        vand = (nr * ut).sum(-1) < 0
        Fa = np.where(vand[..., None], Fa[..., ::-1], Fa)
        return Fa.reshape(-1, 3)
    return V, bygg(sidor), bygg(topp)


def ladar(P, U, hu, hv, z0, z1):
    """Lådor: mitt P (n, 2) i världens xz, axel U (n, 2) med halva längden hu, tvärs hv, y från z0 till z1."""
    P, U = np.asarray(P, float), _norm(np.asarray(U, float))
    Vv = np.c_[-U[:, 1], U[:, 0]]
    hu, hv = np.broadcast_to(hu, len(P))[:, None], np.broadcast_to(hv, len(P))[:, None]
    ring = [P - U * hu - Vv * hv, P + U * hu - Vv * hv, P + U * hu + Vv * hv, P - U * hu + Vv * hv]
    z0, z1 = np.broadcast_to(z0, len(P)), np.broadcast_to(z1, len(P))
    C = np.empty((len(P), 8, 3))
    for k, r in enumerate(ring):
        C[:, k] = np.c_[r[:, 0], z0, r[:, 1]]
        C[:, 4 + k] = np.c_[r[:, 0], z1, r[:, 1]]
    return C


def ror(A, B, t):
    """Fyrkantiga rör (tråd) från A till B (n, 3) i världen, tjocklek t."""
    A, B = np.asarray(A, float), np.asarray(B, float)
    d = _norm(B - A)
    upp = np.where(np.abs(d[:, 1:2]) > 0.9, [[1.0, 0, 0]], [[0, 1.0, 0]])
    a = _norm(np.cross(d, upp)) * t / 2
    b = _norm(np.cross(d, a)) * t / 2
    C = np.empty((len(A), 8, 3))
    for k, (sa, sb) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
        C[:, k] = A + sa * a + sb * b
        C[:, 4 + k] = B + sa * a + sb * b
    return C


class Jarnvag:
    def __init__(self, rails, platforms, BOX, h0, sample):
        self.spar = []
        for geom, t in rails:
            if t.get('tunnel') in ('yes', 'building_passage'):
                continue
            gg = geom.intersection(BOX)
            for part in getattr(gg, 'geoms', [gg]):
                if part.is_empty or part.geom_type != 'LineString' or part.length < 4:
                    continue
                n = max(2, int(np.ceil(part.length / STEG_M)) + 1)
                s = np.linspace(0, part.length, n)
                pts = np.array([part.interpolate(d).coords[0] for d in s])
                dv = _norm(np.gradient(pts, axis=0))
                self.spar.append(dict(line=part, tags=t, s=s, pts=pts, dir=dv, nrm=np.c_[-dv[:, 1], dv[:, 0]],
                                      bro=t.get('bridge') not in (None, 'no'),
                                      service=t.get('service') in SERVICE,
                                      el=t.get('electrified') in ('contact_line', 'yes')))
        self.perronger = []
        for geom, t in platforms:
            g = geom if geom.geom_type in ('Polygon', 'MultiPolygon') else geom.buffer(2.0, cap_style=2)
            g = g.buffer(0).intersection(BOX)
            self.perronger += [p for p in getattr(g, 'geoms', [g]) if p.geom_type == 'Polygon' and p.area > 4]
        if not self.spar:
            return
        P = np.vstack([sp['pts'] for sp in self.spar])
        self.P = P
        self.id = np.concatenate([np.full(len(sp['pts']), k) for k, sp in enumerate(self.spar)])
        self.pa_bro = np.concatenate([np.full(len(sp['pts']), sp['bro']) for sp in self.spar])
        self.alla = cKDTree(P)
        nara_bro = np.zeros(len(P), bool)
        if self.pa_bro.any():
            d, _ = cKDTree(P[self.pa_bro]).query(P)
            nara_bro = d < BRO_MARGINAL_M
        z_dem = sample(h0, P[:, 0], P[:, 1])
        ok = ~(self.pa_bro | nara_bro)
        if not ok.any():
            ok[:] = True
        zb = z_dem.copy()
        tr_ok, z_ok = cKDTree(P[ok]), z_dem[ok]
        for i, grannar in enumerate(tr_ok.query_ball_point(P, UTJAMNING_RADIE_M)):
            if grannar:
                d2 = ((P[ok][grannar] - P[i]) ** 2).sum(1)
                w = np.exp(-d2 / (2 * UTJAMNING_M ** 2))
                zb[i] = (w * z_ok[grannar]).sum() / w.sum()
        self.zb = zb
        o = 0
        for sp in self.spar:
            sp['zb'] = zb[o:o + len(sp['pts'])]
            o += len(sp['pts'])
        km = sum(sp['line'].length for sp in self.spar) / 1000
        print(f'järnväg: {len(self.spar)} spårbitar, {km:.2f} km, {sum(sp["bro"] for sp in self.spar)} broar, '
              f'{len(self.perronger)} plattformar')

    def __bool__(self):
        return bool(self.spar)

    def _celler(self, buffert, shape, T):
        u = [sp['line'].buffer(buffert) for sp in self.spar]
        return rasterize([(g, 1) for g in u], out_shape=shape, transform=T).astype(bool)

    def forma(self, h, shape, T, OX, OY, RES):
        """Banvallen: plan yta strax under makadamens överkant och mjuk övergång till marken.
        Under broar ligger marken (vägen) kvar."""
        if not self:
            return
        m = self._celler(FORM_HW + FORM_SLANT_M, shape, T)
        ii, jj = np.nonzero(m)
        d, idx = self.alla.query(np.c_[OX + jj * RES, OY - ii * RES])
        ok = ~self.pa_bro[idx]
        ii, jj, d, idx = ii[ok], jj[ok], d[ok], idx[ok]
        t = np.clip((d - FORM_HW) / FORM_SLANT_M, 0, 1)
        w = 1 - t * t * (3 - 2 * t)
        h[ii, jj] = h[ii, jj] * (1 - w) + (self.zb[idx] - FORM_UNDER) * w
        print('järnväg: formade celler', len(ii))

    def spara_mask(self, fil, shape, T):
        m = self._celler(TRADFRITT_M, shape, T) if self else np.zeros(shape, bool)
        if self.perronger:
            m |= rasterize([(p.buffer(1.5), 1) for p in self.perronger], out_shape=shape, transform=T).astype(bool)
        np.save(fil, m)

    def marktacke(self, lc, klass, shape, T):
        if self:
            lc[self._celler(MAKADAM[-1][0] - 0.3, shape, T)] = klass

    # ---------- meshar ----------
    def bygg_meshar(self, h, sample, to_world, add_merged, mat, valt=None):
        """valt (valtbart.Samling): kontaktledningsstolparna (med utliggare) och trådarna per spann
        blir vältbara, utan kollision; annars stolparna i Banhinder och trådarna sammanslagna."""
        if not self:
            return
        M = dict(makadam=mat('Makadam', (96, 88, 80), 1.0), sliper=mat('Sliper', (138, 136, 130), 0.95),
                 rals=mat('Rals', (92, 70, 56), 0.8), ralshuvud=mat('Ralshuvud', (176, 176, 180), 0.35),
                 stolpe=mat('Kontaktstolpe', (140, 144, 140), 0.6), trad=mat('Kontakttrad', (58, 54, 46), 0.5),
                 betong=mat('Banbetong', (150, 148, 142), 0.95), perrong=mat('Perrong', (164, 160, 152), 0.9),
                 kant=mat('Perrongkant', (220, 210, 150), 0.8))

        def W(xy):   # SWEREF (n, 2) -> världens xz (n, 2)
            xy = np.asarray(xy, float)
            x, z = to_world(xy[:, 0], xy[:, 1])
            return np.c_[x, z]

        def dirW(d):   # riktning i SWEREF -> världen (z = −N)
            return np.c_[d[:, 0], -d[:, 1]]

        def lagg(grupp, C, mat_sida, mat_topp=None, botten=False):
            if len(C) == 0:
                return
            V, Fs, Ft = kuboider(C, ta_bort_botten=not botten)
            # en mesh per 250 m-ruta (add_merged väljer ruta efter meshens mitt)
            nyckel = np.floor(C.mean(1)[:, [0, 2]] / 250.0).astype(int)
            _, grp = np.unique(nyckel, axis=0, return_inverse=True)
            grp = grp.ravel()
            for F, mm in ((Fs, mat_sida), (Ft, mat_topp or mat_sida)):
                per = len(F) // len(C)
                fgrp = np.repeat(grp, per)
                for g in np.unique(grp):
                    f = F[fgrp == g]
                    used = np.unique(f)
                    remap = np.full(len(V), -1)
                    remap[used] = np.arange(len(used))
                    add_merged(grupp, trimesh.Trimesh(V[used], remap[f], process=False), mm)

        n_sliper = n_stolpe = 0
        lagg_sliper, lagg_rals, lagg_huvud, stolpar, armar, tradar = [], [], [], [], [], []
        dack, racken, landfasten = [], [], []
        for k, sp in enumerate(self.spar):
            pts, zb, s, nrm, dv = sp['pts'], sp['zb'], sp['s'], sp['nrm'], sp['dir']
            # makadam: tvärsnitt längs spåret
            n = len(pts)
            V = np.empty((n, len(MAKADAM), 3))
            for c, (off, dz) in enumerate(MAKADAM):
                w = W(pts + nrm * off)
                V[:, c] = np.c_[w[:, 0], zb + dz, w[:, 1]]
            F = []
            K = len(MAKADAM)
            for c in range(K - 1):
                a = np.arange(n - 1) * K + c
                F.append(np.c_[a, a + K, a + 1])
                F.append(np.c_[a + 1, a + K, a + K + 1])
            msh = trimesh.Trimesh(V.reshape(-1, 3), np.vstack(F), process=False)
            if msh.face_normals[:, 1].mean() < 0:
                msh.faces = msh.faces[:, ::-1]
            add_merged('Jarnvag', msh, M['makadam'])

            # sliprar
            ss = np.arange(SLIPER_DELNING / 2, sp['line'].length, SLIPER_DELNING)
            sx, sy = np.interp(ss, s, pts[:, 0]), np.interp(ss, s, pts[:, 1])
            sz = np.interp(ss, s, zb)
            sd = _norm(np.c_[np.interp(ss, s, dv[:, 0]), np.interp(ss, s, dv[:, 1])])
            behall = np.ones(len(ss), bool)
            if sp['service']:   # växlar och sidospår: inga sliprar ovanpå huvudspårets
                for i, gr in enumerate(self.alla.query_ball_point(np.c_[sx, sy], SLIPER_L * 0.6)):
                    behall[i] = not any(self.id[g] != k and not self.spar[self.id[g]]['service'] for g in gr)
            sn = np.c_[-sd[:, 1], sd[:, 0]]
            Cw = W(np.c_[sx, sy])[behall]
            lagg_sliper.append(ladar(Cw, dirW(sn)[behall], SLIPER_L / 2, SLIPER_B / 2, sz[behall], sz[behall] + SLIPER_H))
            n_sliper += int(behall.sum())

            # räls: en låda per 2 m-bit och skena, blank överyta
            mid = (pts[1:] + pts[:-1]) / 2
            seg = pts[1:] - pts[:-1]
            L = np.linalg.norm(seg, axis=1)
            sdir = _norm(seg)
            snrm = np.c_[-sdir[:, 1], sdir[:, 0]]
            zm = (zb[1:] + zb[:-1]) / 2
            for sida in (-1, 1):
                off = sida * (SPARVIDD_M + RALS_B) / 2
                lagg_rals.append(ladar(W(mid + snrm * off), dirW(sdir), L / 2 + 0.01, RALS_B / 2,
                                       zm + SLIPER_H, zm + SLIPER_H + RALS_H))

            # broar: däck, räcke på yttersidan och landfästen
            if sp['bro']:
                ytter = self._yttersida(k, mid, snrm)
                dack.append(ladar(W(mid), dirW(sdir), L / 2 + 0.02, 2.6, zm - 1.4, zm - 0.3))
                for sida in (-1, 1):
                    v = ytter[:, 1 if sida > 0 else 0]
                    if v.any():
                        racken.append(ladar(W(mid[v] + snrm[v] * sida * 2.75), dirW(sdir[v]), L[v] / 2 + 0.02, 0.15,
                                            zm[v] - 0.3, zm[v] + 0.7))
                for e, ut in ((0, -1), (-1, 1)):
                    p = pts[e] + dv[e] * ut * 0.5
                    botten = float(np.min(sample(h, pts[:, 0], pts[:, 1]))) - 1.0
                    landfasten.append(ladar(W(p[None]), dirW(dv[e][None]), 0.5, 3.0, botten, zb[e] - 0.3))

            # kontaktledning
            if sp['el'] and not sp['service']:
                C_st, C_arm, A, B, fotter, spann = self._kontaktledning(k, sp, W)
                if valt is not None:
                    self._valtbar_ledning(valt, k, fotter, spann, M)
                    n_stolpe += len(fotter)
                else:
                    stolpar.append(C_st)
                    armar.append(C_arm)
                    tradar.append((A, B))
                    n_stolpe += len(C_st)

        lagg('Jarnvag', np.vstack(lagg_sliper), M['sliper'])
        lagg('Jarnvag', np.vstack(lagg_rals), M['rals'], M['ralshuvud'])
        if stolpar:
            lagg('Banhinder', np.vstack(stolpar), M['stolpe'])
            lagg('Jarnvag', np.vstack(armar), M['stolpe'])
            A = np.vstack([a for a, _ in tradar])
            B = np.vstack([b for _, b in tradar])
            if len(A):
                lagg('Jarnvag', ror(A, B, 0.035), M['trad'], botten=True)
        for C in (dack, racken, landfasten):
            if C:
                lagg('Banhinder', np.vstack(C), M['betong'], botten=True)
        self._perronger(h, sample, W, add_merged, M)
        print(f'järnväg: {n_sliper} sliprar, {n_stolpe} kontaktledningsstolpar')

    def _valtbar_ledning(self, valt, k, fotter, spann, M):
        """Stolpar som mallar (två utliggarlängder: a när stolpens sida och sicksacken är lika,
        annars b) och ett mesh per spann; stolpe i drar med sig spann i − 1 och i."""
        from valtbart import lador_mesh   # valtbart importerar kuboider härifrån
        topp = SLIPER_H + RALS_H + BAR_OVER_RALS
        for v, tecken in (('a', 1), ('b', -1)):
            typ = f'Kontaktstolpe_{v}'
            if valt.har_mall(typ):
                continue
            ut = (STOLPE_SIDLED_M - tecken * SICKSACK_M) / 2   # utliggarens mitt mot spåret (+x)
            valt.mall(typ, [(lador_mesh(np.vstack([
                ladar([[0, 0]], [[0, 1]], 0.12, 0.15, -0.5, topp + 1.0),
                ladar([[ut, 0]], [[1, 0]], ut + 0.1, 0.04, topp - 0.05, topp + 0.05)])), M['stolpe'])])
        for i, fot, x_dir, v in fotter:
            valt.placera(f'Kontaktstolpe_{v}', fot, x_dir, nyckel=f'{k}_{i}')
        for i, A, B in spann:
            valt.mesh(f'Ledning__{k}_{i}', lador_mesh(ror(A, B, 0.035), botten=True), M['trad'])

    def _yttersida(self, k, P, nrm):
        """(n, 2) bool: [vänster fri, höger fri] = inget annat spår 2–7 m åt det hållet."""
        fri = np.ones((len(P), 2), bool)
        for i, gr in enumerate(self.alla.query_ball_point(P, 7.5)):
            for g in gr:
                if self.id[g] == k:
                    continue
                off = float(np.dot(self.P[g] - P[i], nrm[i]))
                if off > 2.0:
                    fri[i, 1] = False   # nrm pekar åt vänster i SWEREF; "sida +1" = nrm-hållet
                elif off < -2.0:
                    fri[i, 0] = False
        return fri

    def _kontaktledning(self, k, sp, W):
        pts, zb, s = sp['pts'], sp['zb'], sp['s']
        Ltot = sp['line'].length
        stn = np.r_[0.0, np.arange(STOLPE_DELNING_M / 2, Ltot, STOLPE_DELNING_M), Ltot]
        if Ltot - stn[-2] < 10:
            stn = np.delete(stn, -2)
        px, py = np.interp(stn, s, pts[:, 0]), np.interp(stn, s, pts[:, 1])
        pz = np.interp(stn, s, zb)
        d = _norm(np.c_[np.interp(stn, s, sp['dir'][:, 0]), np.interp(stn, s, sp['dir'][:, 1])])
        nr = np.c_[-d[:, 1], d[:, 0]]
        P = np.c_[px, py]
        fri = self._yttersida(k, P, nr)
        rals = pz + SLIPER_H + RALS_H
        nara_bro = np.zeros(len(P), bool)
        if self.pa_bro.any():
            dd, _ = cKDTree(self.P[self.pa_bro]).query(P)
            nara_bro = dd < 4.0
        C_st, C_arm = [], []
        fotter = []   # (station, fot i världen, x mot spåret i världens xz, utliggarvariant)
        zig = np.where(np.arange(len(stn)) % 2 == 0, SICKSACK_M, -SICKSACK_M)
        for i in range(1, len(stn) - 1):   # ändpunkterna bär bara tråd (nästa spårbit fortsätter)
            if nara_bro[i] or not (fri[i, 0] or fri[i, 1]):
                continue
            sida = 1 if fri[i, 1] else -1
            m = P[i] + nr[i] * sida * STOLPE_SIDLED_M
            wm = W(m[None])[0]
            fotter.append((i, [wm[0], pz[i], wm[1]], W(m[None] - nr[i:i + 1] * sida)[0] - wm,
                           'a' if sida * zig[i] > 0 else 'b'))
            C_st.append(ladar(W(m[None]), W(m[None] + d[i:i + 1]) - W(m[None]), 0.12, 0.15, pz[i] - 0.5,
                              rals[i] + BAR_OVER_RALS + 1.0))
            a_mitt = (m + P[i] + nr[i] * zig[i]) / 2
            ah = abs(STOLPE_SIDLED_M - sida * zig[i]) / 2 + 0.1
            C_arm.append(ladar(W(a_mitt[None]), W(nr[i:i + 1] + P[i:i + 1]) - W(P[i:i + 1]), ah, 0.04,
                               rals[i] + BAR_OVER_RALS - 0.05, rals[i] + BAR_OVER_RALS + 0.05))
        # trådar: kontakttråd (sicksack) och bärlina (nedhäng) mellan stationerna, hängare emellan
        A, B = [], []
        spann = []   # (i, A, B) för trådarna mellan station i och i + 1
        for i in range(len(stn) - 1):
            n_fore = len(A)
            for j in range(6):
                t0, t1 = j / 6, (j + 1) / 6
                def punkt(t, hojd, sag):
                    ss = stn[i] + (stn[i + 1] - stn[i]) * t
                    x, y = np.interp(ss, s, pts[:, 0]), np.interp(ss, s, pts[:, 1])
                    nn = nr[i] * (1 - t) + nr[i + 1] * t
                    z_ = zig[i] * (1 - t) + zig[i + 1] * t
                    w = W(np.array([[x + nn[0] * z_, y + nn[1] * z_]]))[0]
                    z = np.interp(ss, s, zb) + SLIPER_H + RALS_H + hojd - sag * 4 * t * (1 - t)
                    return np.array([w[0], z, w[1]])
                A.append(punkt(t0, KONTAKT_OVER_RALS, 0)); B.append(punkt(t1, KONTAKT_OVER_RALS, 0))
                A.append(punkt(t0, BAR_OVER_RALS, BAR_NEDHANG)); B.append(punkt(t1, BAR_OVER_RALS, BAR_NEDHANG))
                if j > 0:
                    A.append(punkt(t0, KONTAKT_OVER_RALS, 0)); B.append(punkt(t0, BAR_OVER_RALS, BAR_NEDHANG))
            spann.append((i, np.array(A[n_fore:]), np.array(B[n_fore:])))
        tom = np.zeros((0, 8, 3))
        return ((np.vstack(C_st) if C_st else tom), (np.vstack(C_arm) if C_arm else tom), np.array(A), np.array(B),
                fotter, spann)

    def _platta(self, poly, c, h, sample, to_W):
        def topp(xy):
            _, idx = self.alla.query(xy)
            return self.zb[idx] + SLIPER_H + RALS_H + PERRONG_OVER_RALS
        def botten(xy):
            return np.minimum(sample(h, xy[:, 0], xy[:, 1]) - 0.8, topp(xy) - 0.3)
        return _platta_mesh(poly, topp, botten, to_W)

    def _perronger(self, h, sample, to_W, add_merged, M):
        for poly in self.perronger:
            c = np.array(poly.centroid.coords[0])
            m = self._platta(poly, c, h, sample, to_W)
            add_merged('Banhinder', m, M['perrong'])
            # vit-gul kant längs spårsidan: smal remsa på överytan där spåret är närmast
            ring = np.array(poly.exterior.coords)
            d, _ = self.alla.query(ring)
            near = d < d.min() + 1.0
            for a in range(len(ring) - 1):
                if near[a] and near[a + 1]:
                    p0, p1 = ring[a], ring[a + 1]
                    mid = (p0 + p1) / 2
                    L = np.linalg.norm(p1 - p0)
                    if L < 0.2:
                        continue
                    _, ix = self.alla.query(mid)
                    z = self.zb[ix] + SLIPER_H + RALS_H + PERRONG_OVER_RALS
                    C = ladar(to_W(mid[None]), to_W(p1[None]) - to_W(p0[None]), L / 2, 0.25, z, z + 0.01)
                    V2, Fs, Ft = kuboider(C)
                    add_merged('Banhinder', trimesh.Trimesh(V2, np.vstack([Fs, Ft]), process=False), M['kant'])


def _ringar(poly):
    return [np.array(poly.exterior.coords)[:-1]] + [np.array(r.coords)[:-1] for r in poly.interiors]


def _platta_mesh(poly, z_topp, z_botten, to_W):
    """Prisma ur en polygon: överyta (begränsad Delaunay), sidor ner till z_botten.
    z_topp, z_botten: funktioner av (n, 2) SWEREF -> höjd."""
    tri = shapely.constrained_delaunay_triangles(poly)
    T = [np.array(t.exterior.coords)[:3] for t in tri.geoms]
    V, F = [], []
    for t in T:
        a = len(V) * 1
        V.extend(t)
    V = np.array(V)
    top = np.c_[to_W(V)[:, 0], z_topp(V), to_W(V)[:, 1]]
    F = np.arange(len(V)).reshape(-1, 3)
    Vs, Fs = [top], [F]
    n = len(top)
    for ring in _ringar(poly):
        a, b = ring, np.roll(ring, -1, axis=0)
        wa, wb = to_W(a), to_W(b)
        q = np.concatenate([np.c_[wa[:, 0], z_topp(a), wa[:, 1]], np.c_[wb[:, 0], z_topp(b), wb[:, 1]],
                            np.c_[wb[:, 0], z_botten(b), wb[:, 1]], np.c_[wa[:, 0], z_botten(a), wa[:, 1]]])
        k = len(a)
        i = np.arange(k)
        Vs.append(q)
        Fs.append(n + np.r_[np.c_[i, i + k, i + 2 * k], np.c_[i, i + 2 * k, i + 3 * k]])
        n += 4 * k
    m = trimesh.Trimesh(np.vstack(Vs), np.vstack(Fs), process=False)
    # överytan uppåt, sidorna utåt (från polygonens mitt)
    c = np.array(poly.centroid.coords[0])
    cw = to_W(c[None])[0]
    nr, ce = m.face_normals, m.triangles_center
    upp = np.abs(nr[:, 1]) > 0.5
    ut = np.where(upp, nr[:, 1], nr[:, 0] * (ce[:, 0] - cw[0]) + nr[:, 2] * (ce[:, 2] - cw[1]))
    f = m.faces.copy()
    f[ut < 0] = f[ut < 0][:, ::-1]
    m.faces = f
    return m
