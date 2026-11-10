"""Vägkantens miljö (step3, efter vägmesharna och markeringarna). Glb-gruppen `Vagkant` (ingen kollision):

  kantstolpar   landsväg (inte tätort) från 70 km/h: vit stolpe med svart band var 50:e m på båda sidor
  gatlyktor     tätortsgator: en stolpe med arm var 32:a m på högersidan
  räcken        där vägbanken står mer än RACKE_BANK_M över marken intill (lasermarken, h_raw)
  hastighet     skylt där NVDB:s hastighet byter, åt båda hållen (högersidan)
  väjningsplikt OSM highway=give_way / stop: skylten på högersidan för trafiken mot korsningen
  hållplatser   OSM highway=bus_stop: hållplatsskylt; väderskydd vid OSM amenity=shelter (public_transport)
                och plattformar med shelter=yes (features.py: 'vaderskydd'), öppningen mot vägen
Skyltarna har en atlas (PIL) som glb-textur med alfa; baksidan är grå. Diken grävs i step3:s schaktning
(DIKE_*), på landsvägar utanför tätort.
"""
import os
import numpy as np
from shapely.geometry import Point
from PIL import Image, ImageDraw, ImageFont
import trimesh
from jarnvag import ladar, kuboider

DIKE_TYPER = ('trunk', 'primary', 'secondary', 'tertiary', 'unclassified')
DIKE_AVST_M = 3.2      # dikesbottnen från vägkanten
DIKE_HALV_M = 1.6
DIKE_DJUP_M = 0.6
STOR = ('trunk', 'primary', 'secondary', 'tertiary', 'unclassified')
GATA = ('primary', 'secondary', 'tertiary', 'unclassified', 'residential', 'living_street')
KANTSTOLPE_M = 50.0
LYKTA_M = 32.0
RACKE_BANK_M = 2.0
KORSNING_FRI_M = 14.0
HASTIGHETER = [30, 40, 50, 60, 70, 80, 90, 100, 110, 120]
ATLAS_RUTA = 128
ATLAS = HASTIGHETER + ['vajning', 'stopp', 'buss']   # celler i ordning, 8 per rad


def dike_flagga(r):
    """1.0 om vägen får diken (landsväg utanför tätort), annars 0."""
    return 1.0 if r['tags']['highway'] in DIKE_TYPER and not (r['tatt'].mean() > 0.5) else 0.0


def _atlas():
    cols, rows = 8, 2
    im = Image.new('RGBA', (cols * ATLAS_RUTA, rows * ATLAS_RUTA), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype('DejaVuSans-Bold.ttf', 54)
        font_l = ImageFont.truetype('DejaVuSans-Bold.ttf', 30)
    except OSError:
        font = font_l = ImageFont.load_default()
    for i, namn in enumerate(ATLAS):
        x0, y0 = (i % cols) * ATLAS_RUTA, (i // cols) * ATLAS_RUTA
        c = (x0 + ATLAS_RUTA / 2, y0 + ATLAS_RUTA / 2)
        R = ATLAS_RUTA / 2 - 4
        if isinstance(namn, int):
            d.ellipse([c[0] - R, c[1] - R, c[0] + R, c[1] + R], fill=(200, 30, 35, 255))
            d.ellipse([c[0] - R * 0.78, c[1] - R * 0.78, c[0] + R * 0.78, c[1] + R * 0.78], fill=(245, 200, 30, 255))
            d.text(c, str(namn), fill=(15, 15, 15, 255), font=font, anchor='mm')
        elif namn == 'vajning':
            tri = [(c[0], y0 + ATLAS_RUTA - 6), (x0 + 4, y0 + 14), (x0 + ATLAS_RUTA - 4, y0 + 14)]
            d.polygon(tri, fill=(200, 30, 35, 255))
            k = 0.62
            inner = [(c[0] + (p[0] - c[0]) * k, c[1] + 6 + (p[1] - c[1]) * k) for p in tri]
            d.polygon(inner, fill=(245, 200, 30, 255))
        elif namn == 'stopp':
            ang = np.radians(22.5 + np.arange(8) * 45)
            d.polygon([(c[0] + R * np.cos(a), c[1] + R * np.sin(a)) for a in ang], fill=(200, 30, 35, 255))
            d.text(c, 'STOP', fill=(250, 250, 250, 255), font=font_l, anchor='mm')
        elif namn == 'buss':
            d.rectangle([x0 + 10, y0 + 6, x0 + ATLAS_RUTA - 10, y0 + ATLAS_RUTA - 6], fill=(250, 210, 30, 255),
                        outline=(30, 90, 50, 255), width=8)
            d.text((c[0], c[1] - 14), 'H', fill=(30, 90, 50, 255), font=font, anchor='mm')
            d.text((c[0], c[1] + 36), 'BUSS', fill=(30, 90, 50, 255), font=font_l, anchor='mm')
    return im, cols, rows


class Vagkant:
    def __init__(self, roads, korsningar, vagpunkter, h, h_raw, sample, to_world, add_merged, mat):
        self.roads = roads
        self.kors = korsningar
        self.punkter = vagpunkter
        self.h, self.h_raw, self.sample, self.to_world = h, h_raw, sample, to_world
        self.add = add_merged
        self.mat = mat
        self.boxar = {}   # material -> lista med (n, 8, 3)
        self.skyltar = []   # (mitt SWEREF, riktning mot trafiken SWEREF, höjd, atlasnamn, storlek)
        self._skydd = []
        self.antal = dict(kantstolpar=0, lyktor=0, racken_m=0, hastighet=0, vajning=0, hallplatser=0, skydd=0)

    # ---------- hjälp ----------
    def _box(self, mat, C):
        self.boxar.setdefault(mat, []).append(C)

    def _mark(self, x, y):
        return float(self.sample(self.h, [x], [y])[0])

    def _nara_korsning(self, p, m=KORSNING_FRI_M):
        if not len(self.kors):
            return False
        return bool((np.hypot(self.kors[:, 0] - p[0], self.kors[:, 1] - p[1]) < m).any())

    def _stolpe(self, p, hojd, tjock, mat, z0=None):
        z = self._mark(*p) if z0 is None else z0
        w = np.array(self.to_world(p[0], p[1]))
        self._box(mat, ladar(w[None], np.array([[1.0, 0.0]]), tjock / 2, tjock / 2, z - 0.3, z + hojd))
        return z

    # ---------- delar ----------
    def bygg(self):
        for r in self.roads:
            if 'pts' not in r or 'zm' not in r:
                continue
            hw_typ = r['tags']['highway']
            if r['surface'] == 'asfalt' and hw_typ in STOR:
                self._kantstolpar(r)
                self._racken(r)
            if hw_typ in GATA and r['tatt'].mean() > 0.5:
                self._lyktor(r)
            if hw_typ in GATA:
                self._hastighet(r)
        self._punkter()
        self._skriv()
        print('vägkant:', ', '.join(f'{k} {v}' for k, v in self.antal.items()))

    def _langs(self, r, delning, fas=0.0):
        """(punkt, riktning, vänsternormal, halvbredd, s) var delning:e m längs vägen."""
        s, pts, nrm, hw = r['s'], r['pts'], r['nrm'], r['hw']
        for sv in np.arange(fas + delning / 2, s[-1] - 2.0, delning):
            p = np.array([np.interp(sv, s, pts[:, 0]), np.interp(sv, s, pts[:, 1])])
            nn = np.array([np.interp(sv, s, nrm[:, 0]), np.interp(sv, s, nrm[:, 1])])
            nn /= max(np.linalg.norm(nn), 1e-9)
            yield p, np.array([nn[1], -nn[0]]), nn, float(np.interp(sv, s, hw)), sv

    def _pa_bro(self, r):
        return r['tags'].get('bridge') not in (None, 'no') or r['tags'].get('tunnel') not in (None, 'no')

    def _kantstolpar(self, r):
        v = np.nanmedian(r['hastighet']) if np.isfinite(r['hastighet']).any() else 70.0
        if r['tatt'].mean() > 0.5 or v < 70 or self._pa_bro(r):
            return
        vit, svart = self.mat('Kantstolpe', (235, 235, 230), 0.6), self.mat('Kantstolpe_band', (25, 25, 25), 0.6)
        for p, d, nn, hw, _ in self._langs(r, KANTSTOLPE_M):
            if self._nara_korsning(p):
                continue
            for sida in (1, -1):
                q = p + nn * sida * (hw + 0.6)
                z = self._stolpe(q, 1.1, 0.11, vit)
                w = np.array(self.to_world(q[0], q[1]))
                self._box(svart, ladar(w[None], np.array([[1.0, 0.0]]), 0.058, 0.058, z + 0.75, z + 0.95))
                self.antal['kantstolpar'] += 1

    def _lyktor(self, r):
        if self._pa_bro(r):
            return
        stal = self.mat('Lyktstolpe', (120, 124, 126), 0.5)
        lampa = self.mat('Lykta', (235, 232, 215), 0.4)
        for p, d, nn, hw, _ in self._langs(r, LYKTA_M, fas=7.0):
            if self._nara_korsning(p, 8.0):
                continue
            q = p - nn * (hw + 1.0)   # högersidan
            z = self._stolpe(q, 6.0, 0.13, stal)
            # arm ut över vägen och lampkupa
            arm_mitt = q + nn * 0.75
            w = np.array(self.to_world(arm_mitt[0], arm_mitt[1]))
            wd = np.array(self.to_world(q[0] + nn[0], q[1] + nn[1])) - np.array(self.to_world(q[0], q[1]))
            self._box(stal, ladar(w[None], wd[None], 0.8, 0.04, z + 5.9, z + 6.0))
            hq = q + nn * 1.5
            w2 = np.array(self.to_world(hq[0], hq[1]))
            self._box(lampa, ladar(w2[None], wd[None], 0.28, 0.13, z + 5.75, z + 5.95))
            self.antal['lyktor'] += 1

    def _racken(self, r):
        if self._pa_bro(r):
            return
        stal = self.mat('Racke_vag', (150, 154, 152), 0.45)
        s, pts, nrm, hw, zm = r['s'], r['pts'], r['nrm'], r['hw'], r['zm']
        for sida in (1, -1):
            ute = pts + nrm * sida * (hw[:, None] + 6.0)
            bank = zm - self.sample(self.h_raw, ute[:, 0], ute[:, 1])
            hog = bank > RACKE_BANK_M
            if hog.sum() < 8:
                continue
            for i in np.nonzero(hog)[0]:
                if self._nara_korsning(pts[i], 10.0):
                    continue
                q = pts[i] + nrm[i] * sida * (hw[i] + 0.5)
                z = float(zm[i])
                w = np.array(self.to_world(q[0], q[1]))
                d = np.array(self.to_world(q[0] - nrm[i][1], q[1] + nrm[i][0])) - w
                self._box(stal, ladar(w[None], np.array([[1.0, 0.0]]), 0.05, 0.05, z - 0.4, z + 0.7))
                if i + 1 < len(pts) and hog[i + 1]:
                    q2 = pts[i + 1] + nrm[i + 1] * sida * (hw[i + 1] + 0.5)
                    m = (q + q2) / 2
                    wm = np.array(self.to_world(m[0], m[1]))
                    wd = np.array(self.to_world(q2[0], q2[1])) - w
                    L = float(np.linalg.norm(wd))
                    self._box(stal, ladar(wm[None], wd[None], L / 2 + 0.02, 0.03, z + 0.45, z + 0.75))
                    self.antal['racken_m'] += int(round(L))

    def _hastighet(self, r):
        v = r['hastighet']
        if not np.isfinite(v).any() or len(v) < 10:
            return
        v = np.where(np.isfinite(v), v, np.nan)
        s, pts, nrm, hw = r['s'], r['pts'], r['nrm'], r['hw']
        for i in range(1, len(v)):
            if not (np.isfinite(v[i]) and np.isfinite(v[i - 1])) or v[i] == v[i - 1]:
                continue
            # bara bestående byten (minst 25 m åt båda håll)
            fore = v[max(0, i - 12):i]
            efter = v[i:i + 12]
            if (fore != v[i - 1]).any() or (efter != v[i]).any():
                continue
            p = pts[i]
            if self._nara_korsning(p, 6.0):
                continue
            d = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
            d /= max(np.linalg.norm(d), 1e-9)
            # framåt (ökande s): ny hastighet v[i] på högersidan; bakåt: v[i-1] på andra sidan
            for riktning, varde in ((d, v[i]), (-d, v[i - 1])):
                if int(varde) not in HASTIGHETER:
                    continue
                hoger = np.array([riktning[1], -riktning[0]])
                q = p + hoger * (hw[i] + 1.0)
                self._skylt(q, -riktning, f'{int(varde)}', 2.0, 0.64)
                self.antal['hastighet'] += 1

    def _punkter(self):
        from shapely import STRtree
        bil = [r for r in self.roads if 'pts' in r and r['tags']['highway'] not in
               ('path', 'footway', 'cycleway', 'steps', 'bridleway', 'pedestrian')]
        if not bil:
            return
        tree = STRtree([r['line'] for r in bil])
        for pt, t in self.punkter:
            typ = t.get('highway')
            if typ == 'street_lamp':
                continue   # gatlyktorna läggs ut efter regeln
            j = tree.nearest(pt)
            r = bil[j]
            L = r['line']
            if L.distance(pt) > 25:
                continue
            sp = L.project(pt)
            p_vag = np.array(L.interpolate(sp).coords[0])
            d = np.array(L.interpolate(min(sp + 1, L.length)).coords[0]) - np.array(L.interpolate(max(sp - 1, 0)).coords[0])
            d /= max(np.linalg.norm(d), 1e-9)
            hw = float(np.interp(sp, r['s'], r['hw']))
            if typ in ('give_way', 'stop'):
                # trafiken kör mot den närmaste vägänden (korsningen)
                mot_slut = sp > L.length / 2
                if t.get('direction') == 'backward':
                    mot_slut = False
                elif t.get('direction') == 'forward':
                    mot_slut = True
                riktning = d if mot_slut else -d
                hoger = np.array([riktning[1], -riktning[0]])
                q = p_vag + hoger * (hw + 1.0)
                self._skylt(q, -riktning, 'vajning' if typ == 'give_way' else 'stopp', 2.0, 0.7)
                self.antal['vajning'] += 1
            elif typ == 'bus_stop':
                pos = np.array(pt.coords[0])
                ut = pos - p_vag
                if np.linalg.norm(ut) < hw + 0.8:   # noden på vägen: ställ skylten vid kanten
                    nn = np.array([-d[1], d[0]])
                    sida = 1.0 if np.dot(ut, nn) >= 0 else -1.0
                    pos = p_vag + nn * sida * (hw + 1.2)
                    ut = nn * sida
                ut /= max(np.linalg.norm(ut), 1e-9)
                # skylten vänd längs vägen, så att bussen ser den
                self._skylt(pos, d, 'buss', 2.2, 0.5, dubbel=True)
                self.antal['hallplatser'] += 1
            elif typ == 'vaderskydd':
                # öppningen mot vägen: bakväggen på bortre sidan
                pos = np.array(pt.coords[0])
                ut = pos - p_vag
                if np.linalg.norm(ut) < hw + 1.5:
                    nn = np.array([-d[1], d[0]])
                    ut = nn * (1.0 if np.dot(ut, nn) >= 0 else -1.0)
                    pos = p_vag + ut * (hw + 2.5)
                ut /= max(np.linalg.norm(ut), 1e-9)
                if any(np.hypot(*(pos - q)) < 4.0 for q in self._skydd):
                    continue   # samma skydd som nod och plattform
                self._skydd.append(pos)
                self._vaderskydd(pos, d, ut)
                self.antal['skydd'] += 1

    def _vaderskydd(self, p, langs, ut):
        ram = self.mat('Vaderskydd_ram', (70, 74, 76), 0.5)
        glas = self.mat('Vaderskydd_glas', (150, 175, 185), 0.15)
        tak = self.mat('Vaderskydd_tak', (60, 62, 64), 0.6)
        z = self._mark(*p)
        def w(q):
            return np.array(self.to_world(q[0], q[1]))
        wl = w(p + langs) - w(p)
        # bakvägg (glas) längs vägen, två gavlar, tak, fyra stolpar
        self._box(glas, ladar(w(p + ut * 0.7)[None], wl[None], 1.5, 0.03, z, z + 2.2))
        for s in (-1.5, 1.5):
            self._box(glas, ladar(w(p + langs * s)[None], (w(p + ut) - w(p))[None], 0.7, 0.03, z, z + 2.2))
            for u in (-0.7, 0.7):
                self._box(ram, ladar(w(p + langs * s + ut * u)[None], wl[None], 0.04, 0.04, z, z + 2.3))
        self._box(tak, ladar(w(p)[None], wl[None], 1.65, 0.85, z + 2.3, z + 2.4))

    def _skylt(self, p, mot, namn, hojd, storlek, dubbel=False):
        """Skylt på stolpe vid p, framsidan vänd åt `mot` (SWEREF-riktning mot trafiken)."""
        z = self._stolpe(p, hojd + storlek * 0.5, 0.06, self.mat('Skyltstolpe', (150, 154, 156), 0.5))
        self.skyltar.append((p, mot, z + hojd, namn, storlek))
        if os.environ.get('VAGKANT_DEBUG') and len(self.skyltar) <= 6:
            w = self.to_world(p[0], p[1])
            m = self.to_world(p[0] + mot[0] * 10, p[1] + mot[1] * 10)
            print(f'  skylt {namn} vid ({w[0]:.0f}, {w[1]:.0f}) sedd från ({m[0]:.0f}, {m[1]:.0f})')
        if dubbel:
            self.skyltar.append((p, -mot, z + hojd, namn, storlek))

    # ---------- skriv ut ----------
    def _skriv(self):
        for mat, lista in self.boxar.items():
            C = np.vstack(lista)
            V, Fs, Ft = kuboider(C)
            F = np.vstack([Fs, Ft])
            nyckel = np.floor(C.mean(1)[:, [0, 2]] / 250.0).astype(int)
            _, grp = np.unique(nyckel, axis=0, return_inverse=True)
            grp = grp.ravel()
            per = len(Fs) // len(C)
            pt = len(Ft) // len(C)
            fgrp = np.r_[np.repeat(grp, per), np.repeat(grp, pt)]
            for g in np.unique(grp):
                f = F[fgrp == g]
                used = np.unique(f)
                remap = np.full(len(V), -1)
                remap[used] = np.arange(len(used))
                self.add('Vagkant', trimesh.Trimesh(V[used], remap[f], process=False), mat)
        if not self.skyltar:
            return
        im, cols, rows = _atlas()
        fram = trimesh.visual.material.PBRMaterial(name='Vagskylt', baseColorTexture=im, alphaMode='MASK',
                                                   alphaCutoff=0.5, roughnessFactor=0.5, doubleSided=False)
        bak = trimesh.visual.material.PBRMaterial(name='Vagskylt_bak', baseColorTexture=im, alphaMode='MASK',
                                                  alphaCutoff=0.5, baseColorFactor=[0.25, 0.25, 0.26, 1.0],
                                                  roughnessFactor=0.7, doubleSided=False)
        for ytor, material, framsida in ((self.skyltar, fram, True), (self.skyltar, bak, False)):
            V, F, UV = [], [], []
            for p, mot, z, namn, st in ytor:
                i = ATLAS.index(namn if namn in ATLAS else int(namn))
                c, rr = i % cols, i // cols
                u0, u1 = c / cols, (c + 1) / cols
                v_top, v_bot = 1 - rr / rows, 1 - (rr + 1) / rows   # trimesh: v från botten
                mot = mot / max(np.linalg.norm(mot), 1e-9)
                hoger = np.array([mot[1], -mot[0]])   # sett från trafiken: höger
                off = 0.0 if framsida else -0.012
                m = p + mot * (0.04 + off)
                a, b = m - hoger * st / 2, m + hoger * st / 2
                wa, wb = np.array(self.to_world(*a)), np.array(self.to_world(*b))
                n0 = len(V)
                V += [[wa[0], z - st / 2, wa[1]], [wb[0], z - st / 2, wb[1]],
                      [wb[0], z + st / 2, wb[1]], [wa[0], z + st / 2, wa[1]]]
                if framsida:
                    UV += [[u1, v_bot], [u0, v_bot], [u0, v_top], [u1, v_top]]
                else:
                    UV += [[u0, v_bot], [u1, v_bot], [u1, v_top], [u0, v_top]]
                # framsidan mot trafiken (mot), baksidan bort
                nvec = np.array([mot[0], 0.0, -mot[1]]) * (1 if framsida else -1)
                tri = np.array([[n0, n0 + 1, n0 + 2], [n0, n0 + 2, n0 + 3]])
                v = np.array(V[n0:n0 + 4])
                if np.dot(np.cross(v[1] - v[0], v[2] - v[0]), nvec) < 0:
                    tri = tri[:, ::-1]
                F += tri.tolist()
            msh = trimesh.Trimesh(np.array(V), np.array(F), process=False)
            msh.visual = trimesh.visual.TextureVisuals(uv=np.array(UV), material=material)
            self.add('Vagkant', msh, material, np.array(UV))
