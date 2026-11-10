"""Vägkantens miljö (step3, efter vägmesharna och markeringarna). Glb-gruppen `Vagkant` (ingen kollision):

  kantstolpar   landsväg (inte tätort) från 70 km/h: vit stolpe med svart band var 50:e m på båda sidor
  gatlyktor     tätortsgator: en stolpe med arm var 32:a m på högersidan; vältbara (valtbart.py, typen
                Lyktstolpe), inte i de sammanslagna mesharna
  räcken        där vägbanken står mer än RACKE_BANK_M över marken intill (lasermarken, h_raw)
  hastighet     skylt där NVDB:s hastighet byter, åt båda hållen (högersidan)
  väjningsplikt OSM highway=give_way / stop: skylten på högersidan för trafiken mot korsningen
  hållplatser   OSM highway=bus_stop: hållplatsskylt; väderskydd vid OSM amenity=shelter (public_transport)
                och plattformar med shelter=yes (features.py: 'vaderskydd'), öppningen mot vägen;
                hållplatsens namn (OSM name) på en skylt under H-skylten
  ortnamn       där en väg går in i en annan stadsdel/by (work/platser.json, platser.py): vit skylt med
                svart ram och text på högersidan för trafiken in, åt båda hållen (olika namn)
Vältbara (valtbart.py) med en Samling: lyktor, kantstolpar, räcken (en bit per 2 m), skyltar,
ortnamnsskyltar och väderskydd.
Skyltarna har en atlas (PIL) som glb-textur med alfa; baksidan är grå. Skylten sitter SKYLT_AVST_M
framför och baksidan lika långt bakom stolpens mitt, och stolpen slutar vid skyltens mitt, så den
syns aldrig genom skylten. Hållplatsnamnen har en egen atlas (en rad per namn). Diken grävs i step3:s schaktning
(DIKE_*), på landsvägar utanför tätort.
"""
import os
import numpy as np
from shapely.geometry import Point
from PIL import Image, ImageDraw, ImageFont
import trimesh
from jarnvag import ladar, kuboider
from valtbart import lador_mesh

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
SKYLT_AVST_M = 0.06    # skyltytan framför (och baksidan bakom) stolpens mitt; stolpen är 0,06 m
NAMN_H_M = 0.16        # hållplatsnamnets skylt: höjd, bredd efter texten (minst H-skyltens)
NAMN_HOJD_M = 2.2 - 0.25 - NAMN_H_M / 2 - 0.03   # namnskyltens mitt över marken, under H-skylten
ORTNAMN_H_M = 0.34      # ortnamnsskylten: höjd, bredd efter texten
ORTNAMN_MITT_M = 1.9    # skyltens mitt över marken
ORTNAMN_MIN_RACKVIDD = 300   # bara platser med minst så stor räckvidd (platser.py) får skyltar
ORTNAMN_STABIL = 15     # vägpunkter (var 2 m) i samma plats på båda sidor om bytet
NAMN_RAD_PX = 64
NAMN_BREDD_PX = 1024


def dike_flagga(r):
    """1.0 om vägen får diken (landsväg utanför tätort), annars 0."""
    return 1.0 if r['tags']['highway'] in DIKE_TYPER and not (r['tatt'].mean() > 0.5) else 0.0


def _atlas():
    cols, rows = 8, 2
    im = Image.new('RGBA', (cols * ATLAS_RUTA, rows * ATLAS_RUTA), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype('DejaVuSans-Bold.ttf', 54)
        font_m = ImageFont.truetype('DejaVuSans-Bold.ttf', 40)   # tre siffror
        font_l = ImageFont.truetype('DejaVuSans-Bold.ttf', 30)
    except OSError:
        font = font_m = font_l = ImageFont.load_default()
    for i, namn in enumerate(ATLAS):
        x0, y0 = (i % cols) * ATLAS_RUTA, (i // cols) * ATLAS_RUTA
        c = (x0 + ATLAS_RUTA / 2, y0 + ATLAS_RUTA / 2)
        R = ATLAS_RUTA / 2 - 4
        if isinstance(namn, int):
            d.ellipse([c[0] - R, c[1] - R, c[0] + R, c[1] + R], fill=(200, 30, 35, 255))
            d.ellipse([c[0] - R * 0.78, c[1] - R * 0.78, c[0] + R * 0.78, c[1] + R * 0.78], fill=(245, 200, 30, 255))
            d.text(c, str(namn), fill=(15, 15, 15, 255), font=font if namn < 100 else font_m, anchor='mm')
        elif namn == 'vajning':
            # liksidig triangel med spetsen nedåt; den gula insidan krympt mot den inskrivna
            # cirkelns mitt, så att den röda kanten blir lika bred på alla sidor
            sida = ATLAS_RUTA - 8
            hojd = sida * np.sqrt(3) / 2
            topp = y0 + (ATLAS_RUTA - hojd) / 2
            tri = [(c[0], topp + hojd), (c[0] - sida / 2, topp), (c[0] + sida / 2, topp)]
            mitt = (c[0], topp + hojd / 3)   # inskrivna cirkelns mitt (liksidig: tyngdpunkten)
            k = 0.66
            inner = [(mitt[0] + (p[0] - mitt[0]) * k, mitt[1] + (p[1] - mitt[1]) * k) for p in tri]
            d.polygon(tri, fill=(200, 30, 35, 255))
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


def _namnatlas(namnlista, text=(30, 90, 50, 255), ram=(30, 90, 50, 255), min_bredd_m=0.5, skylt_h_m=NAMN_H_M):
    """En rad per namn: vit skylt med ram och text i färgen (hållplatser mörkgrönt, ortnamn svart)
    -> (bild, höjd px, {namn: (rad, andel av bredden)})."""
    rader = max(len(namnlista), 1)
    hojd_px = 1
    while hojd_px < rader * NAMN_RAD_PX:
        hojd_px *= 2
    im = Image.new('RGBA', (NAMN_BREDD_PX, hojd_px), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype('DejaVuSans-Bold.ttf', 40)
    except OSError:
        font = ImageFont.load_default()
    info = {}
    for i, namn in enumerate(namnlista):
        y0 = i * NAMN_RAD_PX
        w = min(d.textlength(namn, font=font) + 36, NAMN_BREDD_PX)
        w = max(w, NAMN_RAD_PX * min_bredd_m / skylt_h_m)   # minst min_bredd_m bred
        w = min(w, NAMN_BREDD_PX)
        d.rectangle([0, y0 + 2, w - 1, y0 + NAMN_RAD_PX - 3], fill=(245, 245, 240, 255), outline=ram, width=4)
        d.text((w / 2, y0 + NAMN_RAD_PX / 2), namn, fill=text, font=font, anchor='mm')
        info[namn] = (i, w / NAMN_BREDD_PX)
    return im, hojd_px, info


def _plana_ytor(lista, bak=False):
    """Skyltytor i mallens lokala koordinater: [(x, y, bredd, höjd, uv, framåt)] -> (trimesh, uv). Ytan i
    planet x = konst.; framåt = normalen mot +x, annars mot -x (en andra framsida, läsbar bakifrån). Sett
    från normalens håll ligger u0 till vänster (vid +x är +z vänster). bak: baksidan till en framsida
    vid +x (normalen mot -x, samma uv på samma ställe så att konturen stämmer)."""
    V, F, UV = [], [], []
    for x, y, bredd, hojd, (u0, u1, vb, vt), framat in lista:
        n0 = len(V)
        utat = 1.0 if (framat and not bak) else -1.0
        zv, zh = (bredd / 2, -bredd / 2) if (framat or bak) else (-bredd / 2, bredd / 2)
        V += [[x, y - hojd / 2, zv], [x, y - hojd / 2, zh], [x, y + hojd / 2, zh], [x, y + hojd / 2, zv]]
        UV += [[u0, vb], [u1, vb], [u1, vt], [u0, vt]]
        tri = np.array([[n0, n0 + 1, n0 + 2], [n0, n0 + 2, n0 + 3]])
        v = np.array(V[n0:n0 + 4])
        if np.cross(v[1] - v[0], v[2] - v[0])[0] * utat < 0:
            tri = tri[:, ::-1]
        F += tri.tolist()
    return trimesh.Trimesh(np.array(V), np.array(F), process=False), np.array(UV)


class Vagkant:
    def __init__(self, roads, korsningar, vagpunkter, h, h_raw, sample, to_world, add_merged, mat, valt=None,
                 platser=None):
        self.roads = roads
        self.kors = korsningar
        self.punkter = vagpunkter
        self.h, self.h_raw, self.sample, self.to_world = h, h_raw, sample, to_world
        self.add = add_merged
        self.mat = mat
        self.boxar = {}   # material -> lista med (n, 8, 3)
        self.skyltar = []   # (mitt SWEREF, riktning mot trafiken SWEREF, höjd, atlasnamn, storlek, baksida)
        self.namnskyltar = []   # (mitt SWEREF, riktning SWEREF, höjd, namn)
        self.valt = valt    # valtbart.Samling: lyktor, kantstolpar och skyltar (annars sammanslagna meshar)
        # platser.py (work/platser.json): [{namn, typ, E, N, rackvidd}]; ortnamnsskyltar kräver valt
        self.platser = [p for p in (platser or []) if p['rackvidd'] >= ORTNAMN_MIN_RACKVIDD]
        self.ortnamn = []   # (stolpens mitt SWEREF, riktning mot trafiken SWEREF, namn)
        self.valt_skyltar = []   # vältbara skyltar: (p, mot, atlasnamn, höjd, storlek, dubbel, hållplatsnamn)
        self._skydd = []
        self.antal = dict(kantstolpar=0, lyktor=0, racken_m=0, hastighet=0, vajning=0, hallplatser=0, skydd=0,
                          ortnamn=0)

    # ---------- hjälp ----------
    def _box(self, mat, C):
        self.boxar.setdefault(mat, []).append(C)

    def _mark(self, x, y):
        return float(self.sample(self.h, [x], [y])[0])

    def _nara_korsning(self, p, m=KORSNING_FRI_M):
        if not len(self.kors):
            return False
        return bool((np.hypot(self.kors[:, 0] - p[0], self.kors[:, 1] - p[1]) < m).any())

    def _stolpe(self, p, hojd, tjock, mat, z0=None, mot=None):
        """Fyrkantig stolpe; med `mot` (SWEREF) vänd som skylten, annars längs världens axlar."""
        z = self._mark(*p) if z0 is None else z0
        w = np.array(self.to_world(p[0], p[1]))
        u = np.array([[1.0, 0.0]])
        if mot is not None:
            u = (np.array(self.to_world(p[0] + mot[0], p[1] + mot[1])) - w)[None]
        self._box(mat, ladar(w[None], u, tjock / 2, tjock / 2, z - 0.3, z + hojd))
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
            if hw_typ in GATA + STOR and self.platser and self.valt is not None:
                self._ortnamn(r)
        self._punkter()
        self._skriv()
        print('vägkant:', ', '.join(f'{k} {v}' for k, v in self.antal.items()),
              '(allt utom räckenas bankar vältbart)' if self.valt is not None else '')

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
        if self.valt is not None and not self.valt.har_mall('Kantstolpe'):
            self.valt.mall('Kantstolpe', [
                (lador_mesh(ladar([[0, 0]], [[1, 0]], 0.055, 0.055, -0.3, 1.1)), vit),
                (lador_mesh(ladar([[0, 0]], [[1, 0]], 0.058, 0.058, 0.75, 0.95)), svart)])
        for p, d, nn, hw, _ in self._langs(r, KANTSTOLPE_M):
            if self._nara_korsning(p):
                continue
            for sida in (1, -1):
                q = p + nn * sida * (hw + 0.6)
                if self.valt is not None:
                    w = np.array(self.to_world(q[0], q[1]))
                    self.valt.placera('Kantstolpe', [w[0], self._mark(*q), w[1]],
                                      np.array(self.to_world(q[0] + d[0], q[1] + d[1])) - w)
                    self.antal['kantstolpar'] += 1
                    continue
                z = self._stolpe(q, 1.1, 0.11, vit)
                w = np.array(self.to_world(q[0], q[1]))
                self._box(svart, ladar(w[None], np.array([[1.0, 0.0]]), 0.058, 0.058, z + 0.75, z + 0.95))
                self.antal['kantstolpar'] += 1

    def _lyktor(self, r):
        if self._pa_bro(r):
            return
        stal = self.mat('Lyktstolpe', (120, 124, 126), 0.5)
        lampa = self.mat('Lykta', (235, 232, 215), 0.4)
        if self.valt is not None and not self.valt.har_mall('Lyktstolpe'):
            # mallen: foten i origo, armen längs +x
            self.valt.mall('Lyktstolpe', [
                (lador_mesh(np.vstack([ladar([[0, 0]], [[1, 0]], 0.065, 0.065, -0.3, 6.0),
                                       ladar([[0.75, 0]], [[1, 0]], 0.8, 0.04, 5.9, 6.0)])), stal),
                (lador_mesh(ladar([[1.5, 0]], [[1, 0]], 0.28, 0.13, 5.75, 5.95)), lampa)])
        for p, d, nn, hw, _ in self._langs(r, LYKTA_M, fas=7.0):
            if self._nara_korsning(p, 8.0):
                continue
            q = p - nn * (hw + 1.0)   # högersidan
            if self.valt is not None:
                z = self._mark(*q)
                w = np.array(self.to_world(q[0], q[1]))
                wd = np.array(self.to_world(q[0] + nn[0], q[1] + nn[1])) - w
                self.valt.placera('Lyktstolpe', [w[0], z, w[1]], wd)
                self.antal['lyktor'] += 1
                continue
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
        if self.valt is not None and not self.valt.har_mall('Racke'):
            # en bit: stolpen vid foten och balken 2 m längs +x (skalas till bitens längd)
            stolpe = ladar([[0, 0]], [[1, 0]], 0.05, 0.05, -0.4, 0.7)
            self.valt.mall('Racke', [(lador_mesh(np.vstack([
                stolpe, ladar([[1.0, 0]], [[1, 0]], 1.02, 0.03, 0.45, 0.75)])), stal)])
            self.valt.mall('Rackestolpe', [(lador_mesh(stolpe), stal)])
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
                if self.valt is not None:
                    if i + 1 < len(pts) and hog[i + 1]:
                        q2 = pts[i + 1] + nrm[i + 1] * sida * (hw[i + 1] + 0.5)
                        wd = np.array(self.to_world(q2[0], q2[1])) - w
                        L = float(np.linalg.norm(wd))
                        self.valt.placera('Racke', [w[0], z, w[1]], wd, skala_x=L / 2.0)
                        self.antal['racken_m'] += int(round(L))
                    else:
                        self.valt.placera('Rackestolpe', [w[0], z, w[1]], d)
                    continue
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

    def _plats_index(self, P):
        """Platsen vid varje punkt (n, 2) SWEREF: närmast i förhållande till räckvidden (som platser.py
        säger), -1 där ingen når."""
        E = np.array([p['E'] for p in self.platser])
        N = np.array([p['N'] for p in self.platser])
        R = np.array([p['rackvidd'] for p in self.platser], float)
        andel = np.hypot(P[:, 0:1] - E[None], P[:, 1:2] - N[None]) / R[None]
        i = andel.argmin(1)
        return np.where(andel[np.arange(len(P)), i] < 1.0, i, -1)

    def _ortnamn(self, r):
        """Ortnamnsskylt där vägen byter plats (bestående, ORTNAMN_STABIL punkter åt båda håll): för
        trafiken in i den nya platsen på högersidan, åt båda hållen (enkelriktat: bara framåt)."""
        pts, hw = r['pts'], r['hw']
        k = ORTNAMN_STABIL
        if len(pts) < 2 * k + 1 or self._pa_bro(r):
            return
        idx = self._plats_index(pts)
        enkel = r['tags'].get('oneway') in ('yes', '1', 'true') or r.get('rondell')
        for i in range(k, len(pts) - k + 1):
            if idx[i] == idx[i - 1] or (idx[i - k:i] != idx[i - 1]).any() or (idx[i:i + k] != idx[i]).any():
                continue
            if self._nara_korsning(pts[i], 8.0):
                continue
            d = pts[min(i + 1, len(pts) - 1)] - pts[i - 1]
            d /= max(np.linalg.norm(d), 1e-9)
            for riktning, ny in ((d, idx[i]), (-d, idx[i - 1])):
                if ny < 0 or (enkel and riktning is not d):
                    continue
                hoger = np.array([riktning[1], -riktning[0]])
                self.ortnamn.append((pts[i] + hoger * (hw[i] + 1.2), -riktning, self.platser[ny]['namn']))
                self.antal['ortnamn'] += 1

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
                # skylten vänd längs vägen, så att bussen ser den; namnet på en skylt under
                namn = (t.get('name') or '').strip()
                self._skylt(pos, d, 'buss', 2.2, 0.5, dubbel=True, text=namn)
                if namn and self.valt is None:
                    self.namnskyltar.append((pos, d, NAMN_HOJD_M, namn))
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
        if self.valt is not None:
            if not self.valt.har_mall('Vaderskydd'):
                # lokalt: x längs vägen, z ut från vägen (bakväggen på +z)
                st = [ladar([[s_, u]], [[1, 0]], 0.04, 0.04, 0.0, 2.3) for s_ in (-1.5, 1.5) for u in (-0.7, 0.7)]
                self.valt.mall('Vaderskydd', [
                    (lador_mesh(np.vstack([ladar([[0, 0.7]], [[1, 0]], 1.5, 0.03, 0.0, 2.2)]
                                          + [ladar([[s_, 0]], [[0, 1]], 0.7, 0.03, 0.0, 2.2) for s_ in (-1.5, 1.5)])),
                     glas),
                    (lador_mesh(np.vstack(st)), ram),
                    (lador_mesh(ladar([[0, 0]], [[1, 0]], 1.65, 0.85, 2.3, 2.4)), tak)])
            wu = w(p + ut) - w(p)
            self.valt.placera('Vaderskydd', [w(p)[0], z, w(p)[1]], np.array([wu[1], -wu[0]]))
            return
        wl = w(p + langs) - w(p)
        # bakvägg (glas) längs vägen, två gavlar, tak, fyra stolpar
        self._box(glas, ladar(w(p + ut * 0.7)[None], wl[None], 1.5, 0.03, z, z + 2.2))
        for s in (-1.5, 1.5):
            self._box(glas, ladar(w(p + langs * s)[None], (w(p + ut) - w(p))[None], 0.7, 0.03, z, z + 2.2))
            for u in (-0.7, 0.7):
                self._box(ram, ladar(w(p + langs * s + ut * u)[None], wl[None], 0.04, 0.04, z, z + 2.3))
        self._box(tak, ladar(w(p)[None], wl[None], 1.65, 0.85, z + 2.3, z + 2.4))

    def _skylt(self, p, mot, namn, hojd, storlek, dubbel=False, text=''):
        """Skylt på stolpe vid p, framsidan vänd åt `mot` (SWEREF-riktning mot trafiken). Stolpen
        slutar vid skyltens mitt och står mellan fram- och baksidan; dubbel = framsida åt båda hållen.
        text: hållplatsens namn (en skylt under). Med valt: vältbar (mallar i _skriv_valtbara)."""
        if self.valt is not None:
            self.valt_skyltar.append((p, mot, namn, hojd, storlek, dubbel, text))
            return
        z = self._stolpe(p, hojd, 0.06, self.mat('Skyltstolpe', (150, 154, 156), 0.5), mot=mot)
        self.skyltar.append((p, mot, z + hojd, namn, storlek, not dubbel))
        if os.environ.get('VAGKANT_DEBUG') and len(self.skyltar) <= 6:
            w = self.to_world(p[0], p[1])
            m = self.to_world(p[0] + mot[0] * 10, p[1] + mot[1] * 10)
            print(f'  skylt {namn} vid ({w[0]:.0f}, {w[1]:.0f}) sedd från ({m[0]:.0f}, {m[1]:.0f})')
        if dubbel:
            self.skyltar.append((p, -mot, z + hojd, namn, storlek, False))

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
        if self.valt_skyltar:
            self._skriv_valtbara()
        if self.ortnamn:
            self._skriv_ortnamn()
        if self.skyltar:
            self._skriv_skyltar()
        if self.namnskyltar:
            self._skriv_namn()

    def _ruta(self, V, F, UV, p, mot, z, bredd, hojd, uv, framsida):
        """En skyltyta (fyrhörning) SKYLT_AVST_M framför (eller baksidan bakom) stolpens mitt p.
        uv = (u0, u1, v_bot, v_top), sett framifrån: u0 till vänster."""
        u0, u1, v_bot, v_top = uv
        mot = mot / max(np.linalg.norm(mot), 1e-9)
        hoger = np.array([mot[1], -mot[0]])   # sett från trafiken är detta vänster
        m = p + mot * (SKYLT_AVST_M if framsida else -SKYLT_AVST_M)
        a, b = m - hoger * bredd / 2, m + hoger * bredd / 2
        wa, wb = np.array(self.to_world(*a)), np.array(self.to_world(*b))
        n0 = len(V)
        V += [[wa[0], z - hojd / 2, wa[1]], [wb[0], z - hojd / 2, wb[1]],
              [wb[0], z + hojd / 2, wb[1]], [wa[0], z + hojd / 2, wa[1]]]
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

    def _mesh(self, V, F, UV, material):
        msh = trimesh.Trimesh(np.array(V), np.array(F), process=False)
        msh.visual = trimesh.visual.TextureVisuals(uv=np.array(UV), material=material)
        self.add('Vagkant', msh, material, np.array(UV))

    def _skriv_skyltar(self):
        im, cols, rows = _atlas()
        fram = trimesh.visual.material.PBRMaterial(name='Vagskylt', baseColorTexture=im, alphaMode='MASK',
                                                   alphaCutoff=0.5, roughnessFactor=0.5, doubleSided=False)
        bak = trimesh.visual.material.PBRMaterial(name='Vagskylt_bak', baseColorTexture=im, alphaMode='MASK',
                                                  alphaCutoff=0.5, baseColorFactor=[0.25, 0.25, 0.26, 1.0],
                                                  roughnessFactor=0.7, doubleSided=False)
        for material, framsida in ((fram, True), (bak, False)):
            V, F, UV = [], [], []
            for p, mot, z, namn, st, baksida in self.skyltar:
                if not framsida and not baksida:
                    continue   # dubbelsidig: den andra framsidan täcker
                i = ATLAS.index(namn if namn in ATLAS else int(namn))
                c, rr = i % cols, i // cols
                uv = (c / cols, (c + 1) / cols, 1 - (rr + 1) / rows, 1 - rr / rows)   # trimesh: v från botten
                self._ruta(V, F, UV, p, mot, z, st, st, uv, framsida)
            if V:
                self._mesh(V, F, UV, material)

    def _skriv_valtbara(self):
        """Vältbara skyltar: en mall per skylttyp (stolpe, framsida, baksida eller andra framsidan)
        och per hållplatsnamn (H-skylten med namnskylten under). Mallens x pekar mot trafiken."""
        im, cols, rows = _atlas()
        fram = trimesh.visual.material.PBRMaterial(name='Vagskylt', baseColorTexture=im, alphaMode='MASK',
                                                   alphaCutoff=0.5, roughnessFactor=0.5, doubleSided=False)
        bak = trimesh.visual.material.PBRMaterial(name='Vagskylt_bak', baseColorTexture=im, alphaMode='MASK',
                                                  alphaCutoff=0.5, baseColorFactor=[0.25, 0.25, 0.26, 1.0],
                                                  roughnessFactor=0.7, doubleSided=False)
        stolpe = self.mat('Skyltstolpe', (150, 154, 156), 0.5)
        namnlista = sorted({t for *_, t in self.valt_skyltar if t})
        if namnlista:
            nim, hojd_px, info = _namnatlas(namnlista)
            namnmat = trimesh.visual.material.PBRMaterial(name='Hallplatsnamn', baseColorTexture=nim,
                                                          alphaMode='MASK', alphaCutoff=0.5, roughnessFactor=0.5,
                                                          doubleSided=False)

        def ytor(lista):
            return _plana_ytor(lista)

        def bak_ytor(lista):
            return _plana_ytor(lista, bak=True)

        a = SKYLT_AVST_M
        for p, mot, namn, hojd, st, dubbel, text in self.valt_skyltar:
            typ = f'Hallplats_{namnlista.index(text)}' if text else f'Skylt_{namn}'
            if not self.valt.har_mall(typ):
                i = ATLAS.index(namn if namn in ATLAS else int(namn))
                c, rr = i % cols, i // cols
                uv = (c / cols, (c + 1) / cols, 1 - (rr + 1) / rows, 1 - rr / rows)
                delar = [(lador_mesh(ladar([[0, 0]], [[1, 0]], 0.03, 0.03, -0.3, hojd)), stolpe)]
                m, u = ytor([(a, hojd, st, st, uv, True)] + ([(-a, hojd, st, st, uv, False)] if dubbel else []))
                delar.append((m, fram, u))
                if not dubbel:
                    m, u = bak_ytor([(-a, hojd, st, st, uv, False)])
                    delar.append((m, bak, u))
                if text:
                    rad, andel = info[text]
                    bredd = NAMN_H_M * andel * NAMN_BREDD_PX / NAMN_RAD_PX
                    nuv = (0.0, andel, 1 - (rad + 1) * NAMN_RAD_PX / hojd_px, 1 - rad * NAMN_RAD_PX / hojd_px)
                    m, u = ytor([(a, NAMN_HOJD_M, bredd, NAMN_H_M, nuv, True),
                                 (-a, NAMN_HOJD_M, bredd, NAMN_H_M, nuv, False)])
                    delar.append((m, namnmat, u))
                self.valt.mall(typ, delar)
            w = np.array(self.to_world(p[0], p[1]))
            wm = np.array(self.to_world(p[0] + mot[0], p[1] + mot[1])) - w
            self.valt.placera(typ, [w[0], self._mark(*p), w[1]], wm)
        if namnlista:
            print(f'hållplatsnamn: {len(namnlista)} namn (vältbara skyltar)')

    def _skriv_ortnamn(self):
        """Ortnamnsskyltarna: vit med svart ram och text, grå baksida, en mall per namn (Ortnamn_<n>);
        breda skyltar på två stolpar."""
        namnlista = sorted({n for _, _, n in self.ortnamn})
        im, hojd_px, info = _namnatlas(namnlista, text=(20, 20, 20, 255), ram=(20, 20, 20, 255),
                                       min_bredd_m=0.9, skylt_h_m=ORTNAMN_H_M)
        fram = trimesh.visual.material.PBRMaterial(name='Ortnamn', baseColorTexture=im, alphaMode='MASK',
                                                   alphaCutoff=0.5, roughnessFactor=0.5, doubleSided=False)
        bak = trimesh.visual.material.PBRMaterial(name='Ortnamn_bak', baseColorTexture=im, alphaMode='MASK',
                                                  alphaCutoff=0.5, baseColorFactor=[0.25, 0.25, 0.26, 1.0],
                                                  roughnessFactor=0.7, doubleSided=False)
        stolpe = self.mat('Skyltstolpe', (150, 154, 156), 0.5)
        a = SKYLT_AVST_M
        for p, mot, namn in self.ortnamn:
            typ = f'Ortnamn_{namnlista.index(namn)}'
            if not self.valt.har_mall(typ):
                rad, andel = info[namn]
                bredd = ORTNAMN_H_M * andel * NAMN_BREDD_PX / NAMN_RAD_PX
                uv = (0.0, andel, 1 - (rad + 1) * NAMN_RAD_PX / hojd_px, 1 - rad * NAMN_RAD_PX / hojd_px)
                lagen = [0.0] if bredd < 1.2 else [-bredd * 0.32, bredd * 0.32]
                stolpar = np.vstack([ladar([[0, z_]], [[1, 0]], 0.03, 0.03, -0.3, ORTNAMN_MITT_M) for z_ in lagen])
                m, u = _plana_ytor([(a, ORTNAMN_MITT_M, bredd, ORTNAMN_H_M, uv, True)])
                mb, ub = _plana_ytor([(-a, ORTNAMN_MITT_M, bredd, ORTNAMN_H_M, uv, True)], bak=True)
                self.valt.mall(typ, [(lador_mesh(stolpar), stolpe), (m, fram, u), (mb, bak, ub)])
            w = np.array(self.to_world(p[0], p[1]))
            wm = np.array(self.to_world(p[0] + mot[0], p[1] + mot[1])) - w
            self.valt.placera(typ, [w[0], self._mark(*p), w[1]], wm)
        print(f'ortnamn: {len(self.ortnamn)} skyltar, {len(namnlista)} namn')

    def _skriv_namn(self):
        """Hållplatsnamnen: dubbelsidiga skyltar under H-skylten, en egen atlas."""
        namnlista = sorted({n for _, _, _, n in self.namnskyltar})
        im, hojd_px, info = _namnatlas(namnlista)
        material = trimesh.visual.material.PBRMaterial(name='Hallplatsnamn', baseColorTexture=im, alphaMode='MASK',
                                                       alphaCutoff=0.5, roughnessFactor=0.5, doubleSided=False)
        V, F, UV = [], [], []
        for p, d, hojd, namn in self.namnskyltar:
            rad, andel = info[namn]
            bredd = NAMN_H_M * andel * NAMN_BREDD_PX / NAMN_RAD_PX
            v_top = 1 - rad * NAMN_RAD_PX / hojd_px
            v_bot = 1 - (rad + 1) * NAMN_RAD_PX / hojd_px
            z = self._mark(*p) + hojd
            for mot in (d, -d):
                self._ruta(V, F, UV, p, mot, z, bredd, NAMN_H_M, (0.0, andel, v_bot, v_top), True)
        self._mesh(V, F, UV, material)
        print(f'hållplatsnamn: {len(self.namnskyltar)} skyltar, {len(namnlista)} namn')
