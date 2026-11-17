"""Platsdetaljer (step3): handplacerade föremål efter användarens foton (geodata/platsdetaljer.json).

Underlag: användarens foton (geodata/bilder uni/), ortofotot, OSM och användarens GPS-punkter. Parken mitt
emot Campushallen (rostiga balkar, vit sten, hukande flicka, hund, kolonistuga med staket och flaggstång,
livboj, skylt "bad förbjudet", D-skulpturen, trädbänken), Corson (lampgrupper med banderoller, vältbara),
Studenthuset (röd rutfasad på glasad bottenvåning) och dess cykeltak, cisternen (fjärrvärmeackumulatorn),
Kårallens vindbrygga, scenen på Blå havet, Campushallens entré och ramp, skyltar (KEY, I-HUSET, Pressbyrån).
Lågpoly: varje del är ett konvext skal (trimesh.convex_hull, utåtriktade normaler), hårda delar med en egen
hörnpunkt per triangel (platt skuggning), mjuka (kroppar) delade; fasader och skyltar som texturerade ytor.

Glb-grupper: `Byggnader_konst` (kollision, blockerar i bottarnas rutnät) och `Konst` (ingen kollision).
Hus i `osm_hus` byggs här i stället för som vanliga OSM-hus (step3 hoppar över dem); `hus_justera` ger hus
som innehåller en punkt andra OSM-taggar (fasadstil). Stenläggningen: stenlaggning.py.
"""
import json
import math
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
FAST = 'Byggnader_konst'
LOS = 'Konst'

# Färger (sRGB)
ROST = (112, 52, 30)
STEN_VIT = (226, 224, 200)
STATY_VIT = (228, 228, 222)
BRONS = (98, 90, 76)
FALUROD = (128, 34, 28)
VITT = (236, 236, 230)
TAKSVART = (38, 38, 40)
GLAS = (60, 80, 100)
TEGEL = (120, 60, 45)
STAKET = (112, 52, 38)
FLAGGBLA = (0, 82, 147)
FLAGGGUL = (254, 204, 2)
LIVROD = (210, 40, 35)
STOLPE_TRA = (150, 135, 110)
LIVSTOLPE = (190, 190, 185)
KONST_GRA = (168, 170, 168)      # Märkesbackens pelare (betong/stål)
KONST_ROD = (196, 38, 32)        # och deras cylindrar
HUND_LILA = (112, 48, 150)       # rondellhunden
HUND_GUL = (240, 200, 40)


# ---------------------------------------------------------------- primitiver (lokalt: r höger, u upp, f fram)
def lada(c, s):
    """Låda: mitt c = (r, u, f), storlek s = (r, u, f)."""
    c, s = np.asarray(c, float), np.asarray(s, float) / 2
    return np.array([[c[0] + i * s[0], c[1] + j * s[1], c[2] + k * s[2]]
                     for i in (-1, 1) for j in (-1, 1) for k in (-1, 1)])


def lada_mellan(r0, r1, u0, u1, f0, f1):
    return lada(((r0 + r1) / 2, (u0 + u1) / 2, (f0 + f1) / 2), (r1 - r0, u1 - u0, f1 - f0))


def ellipsoid(c, radier, n=10, m=6):
    c = np.asarray(c, float)
    P = [c + [0, -radier[1], 0], c + [0, radier[1], 0]]
    for i in range(1, m):
        v = math.pi * i / m
        for j in range(n):
            a = 2 * math.pi * j / n
            P.append(c + [radier[0] * math.sin(v) * math.cos(a), -radier[1] * math.cos(v),
                          radier[2] * math.sin(v) * math.sin(a)])
    return np.array(P)


def kapsel(p0, p1, r0, r1, n=8):
    """Avsmalnande kapsel mellan två punkter (skalet runt två klot)."""
    return np.vstack([ellipsoid(p0, (r0, r0, r0), n, 4), ellipsoid(p1, (r1, r1, r1), n, 4)])


def cylinder(p0, p1, r0, r1=None, n=8):
    """Rak cylinder/kon från p0 till p1 (platta ändar)."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    r1 = r0 if r1 is None else r1
    d = p1 - p0
    d /= np.linalg.norm(d)
    a = np.cross(d, [0, 1, 0] if abs(d[1]) < 0.9 else [1, 0, 0])
    a /= np.linalg.norm(a)
    b = np.cross(d, a)
    P = []
    for p, r in ((p0, r0), (p1, r1)):
        for j in range(n):
            t = 2 * math.pi * j / n
            P.append(p + r * (math.cos(t) * a + math.sin(t) * b))
    return np.array(P)


class Plats:
    """Lokalt -> värld: foten i (E, N) på höjden y0, framåt mot kompassriktningen `grad`."""

    def __init__(self, E, N, y0, grad, to_world):
        t = math.radians(grad)
        self.E, self.N, self.y0, self.to_world = E, N, y0, to_world
        self.fram = (math.sin(t), math.cos(t))
        self.hoger = (math.cos(t), -math.sin(t))

    def en(self, r, f):
        return (self.E + r * self.hoger[0] + f * self.fram[0], self.N + r * self.hoger[1] + f * self.fram[1])

    def varld(self, P):
        P = np.asarray(P, float)
        E = self.E + P[:, 0] * self.hoger[0] + P[:, 2] * self.fram[0]
        N = self.N + P[:, 0] * self.hoger[1] + P[:, 2] * self.fram[1]
        x, z = self.to_world(E, N)
        return np.column_stack([x, self.y0 + P[:, 1], z])


def _skal(V, platt):
    m = trimesh.convex.convex_hull(V)
    if platt:   # en hörnpunkt per triangel: platt skuggning
        v = m.vertices[m.faces].reshape(-1, 3)
        m = trimesh.Trimesh(v, np.arange(len(v)).reshape(-1, 3), process=False)
    return m


def _skylt_material():
    """Bad förbjudet: blå skylt, vitt fält, svart badare i vågor, röd snedstreck."""
    B, H = 256, 320
    im = Image.new('RGB', (B, H), (25, 90, 190))
    d = ImageDraw.Draw(im)
    d.rectangle([22, 22, B - 23, H - 23], fill=(245, 245, 245))
    d.ellipse([108, 70, 148, 110], fill=(20, 20, 20))                          # huvud
    d.polygon([(100, 120), (156, 120), (166, 200), (90, 200)], fill=(20, 20, 20))   # kropp i vattnet
    for k, y in enumerate((200, 228, 256)):                                      # vågor
        pts = [(40 + i * 12, y + (8 if i % 2 else 0)) for i in range(16)]
        d.line(pts, fill=(20, 20, 20), width=9)
    d.line([(B - 40, 40), (40, H - 40)], fill=(220, 30, 30), width=18)
    return trimesh.visual.material.PBRMaterial(name='Skylt_badforbud', baseColorTexture=im,
                                               metallicFactor=0.0, roughnessFactor=0.6)


class Platsdetaljer:
    def __init__(self, box):
        fil = ROOT / 'platsdetaljer.json'
        conf = json.loads(fil.read_text()) if fil.exists() else {'objekt': []}
        self.conf = conf
        x0, y0, x1, y1 = box.bounds

        def inne(o):
            pts = [o[k] for k in ('lage', 'fran', 'till', 'flaggstang') if k in o] + o.get('hus', [])
            pts += o.get('lagen', []) + o.get('fotavtryck', []) + o.get('omkrets', [])[:1]
            if 'ram' in o:
                pts.append(o['ram'][:2])
            if 'ramp' in o:
                pts.append(o['ramp']['fran'])
            return any(x0 < p[0] < x1 and y0 < p[1] < y1 for p in pts)
        self.lista = [o for o in conf['objekt'] if inne(o)]
        self.hus_id = set()
        for o in self.lista:
            ids = o.get('osm_hus', [])
            self.hus_id |= {str(i) for i in (ids if isinstance(ids, list) else [ids])}
        self.hus_justera = [j for j in conf.get('hus_justera', [])
                            if 'osm_id' in j or x0 < j['punkt'][0] < x1 and y0 < j['punkt'][1] < y1]
        self.punkter = []   # (E, N, radie m): träd och buskar hålls borta (step4)

    def fotavtryck(self):
        """Ytor som byggs här: inga laserhus där (step3)."""
        from shapely.geometry import Point, box as sbox, Polygon
        ut = []
        for o in self.lista:
            if o['typ'] == 'ringhus':
                ut.append(Point(*o['lage']).buffer(o['r_ute_m'] + 1.5))
            elif o['typ'] == 'cistern':
                ut.append(Point(*o['lage']).buffer(o['radie_m'] + 1.5))
            elif o['typ'] in ('studenthuset', 'scen'):
                ut.append(sbox(*o['ram']).buffer(1.0))
            elif o['typ'] == 'cykeltak':
                ut.append(Polygon(o['fotavtryck']).buffer(1.0))
            elif o['typ'] == 'friform':
                ut.append(Polygon(o['omkrets']).buffer(o.get('buffert_m', 2.0) + 1.0))
        return ut

    def justera_hus(self, poly, taggar):
        """hus_justera: huset med OSM-id `osm_id` (relationer 'r<id>') eller som innehåller `punkt` får taggarna
        (fasadstil; punkt fungerar även för laserhus)."""
        from shapely.geometry import Point
        for j in self.hus_justera:
            if 'osm_id' in j:
                if str(taggar.get('_osm_id', '')) == str(j['osm_id']):
                    return dict(taggar, **j['taggar'])
            elif poly.contains(Point(*j['punkt'])):
                return dict(taggar, **j['taggar'])
        return taggar

    def ar(self, t):
        """Huset byggs här (stugan) i stället för som vanligt OSM-hus."""
        return str(t.get('_osm_id', '')) in self.hus_id

    def bygg(self, sample, h, to_world, add_merged, mat, valt=None, laser=None):
        self.h, self.sample, self.to_world, self.add, self.mat = h, sample, to_world, add_merged, mat
        self.valt, self.laser = valt, laser
        self.laserhojd = laser.heights_in if laser is not None else None
        self._mats = {}
        for o in self.lista:
            getattr(self, '_' + o['typ'])(o)
            print('platsdetaljer:', o['namn'])

    # ---------------------------------------------------------------- hjälp
    def _m(self, namn, rgb, rough=0.85):
        if namn not in self._mats:
            self._mats[namn] = self.mat(namn, rgb, rough)
        return self._mats[namn]

    def _mark(self, E, N, radie=0.0):
        """Lägsta markhöjden runt punkten (inget svävar)."""
        if radie <= 0:
            return float(self.sample(self.h, [E], [N])[0])
        a = np.linspace(0, 2 * np.pi, 8, endpoint=False)
        return float(np.min(self.sample(self.h, E + radie * np.cos(a), N + radie * np.sin(a))))

    def _del(self, plats, V, material, grupp=FAST, platt=True):
        self.add(grupp, _skal(plats.varld(V), platt), material)

    # ---------------------------------------------------------------- balkar
    def _balkrad(self, o):
        a, b = np.array(o['fran'], float), np.array(o['till'], float)
        steg = (b - a) / (o['antal'] - 1)
        grad = math.degrees(math.atan2(steg[0], steg[1]))
        H, B = o['hojd_m'], o['bredd_m']
        fl, liv = 0.035, 0.025
        m = self._m('Rost', ROST, 0.8)
        for k in range(o['antal']):
            if k in o.get('utan', []):
                continue
            E, N = a + steg * k
            p = Plats(E, N, self._mark(E, N, 0.4) - 0.3, grad, self.to_world)
            u1 = H + 0.3
            # H-balk: två flänsar tvärs raden, livet längs den
            for s in (-1, 1):
                self._del(p, lada((0, u1 / 2, s * (B / 2 - fl / 2)), (B, u1, fl)), m)
            self._del(p, lada((0, u1 / 2, 0), (liv, u1, B - 2 * fl)), m)
            self.punkter.append((E, N, 1.5))

    # ---------------------------------------------------------------- vit sten
    def _vit_sten(self, o):
        E, N = o['lage']
        H = o['hojd_m']
        p = Plats(E, N, self._mark(E, N, 0.6) - 0.15, o['riktning_grad'], self.to_world)
        V = []
        for i in range(9):
            s = i / 8
            u = 0.15 + s * H
            w = 0.25 + 0.6 * math.sin(math.pi * min(s * 1.15, 1.0)) ** 0.8   # bladform, spetsig topp
            d = 0.12 + 0.22 * math.sin(math.pi * min(s * 1.15, 1.0))
            lut = 0.35 * s * s                                                # lutar åt höger
            for j in range(10):
                t = 2 * math.pi * j / 10
                V.append((lut + w * math.cos(t), u, d * math.sin(t)))
        V.append((0.45, H + 0.3, 0.0))   # spetsen
        V.append((0.0, 0.0, 0.0))
        self._del(p, V, self._m('Konst_vit_sten', STEN_VIT, 0.7), platt=False)
        self.punkter.append((E, N, 2.0))

    # ---------------------------------------------------------------- hukande flicka
    def _flicka(self, o):
        E, N = o['lage']
        p = Plats(E, N, self._mark(E, N, 0.8) - 0.05, o['riktning_grad'], self.to_world)
        m = self._m('Konst_staty_vit', STATY_VIT, 0.75)
        hard = [
            lada_mellan(0.0, 0.44, 0.0, 0.92, -0.32, 0.30),     # stående platåsko (höger fot)
            lada_mellan(-0.46, -0.04, 0.0, 0.62, -0.92, -0.26),  # liggande platåsko (vänster), sulan bakåt
        ]
        for V in hard:
            self._del(p, V, m)
        mjuka = [
            kapsel((0.22, 0.88, 0.0), (0.22, 1.70, 0.62), 0.15, 0.13),     # höger underben upp till knät
            kapsel((0.22, 1.72, 0.64), (0.14, 1.20, -0.22), 0.14, 0.19),   # höger lår bak till höften
            kapsel((-0.24, 0.42, -0.34), (-0.20, 0.78, 0.50), 0.14, 0.13),  # vänster underben fram till knät
            kapsel((-0.20, 0.80, 0.50), (-0.14, 1.18, -0.20), 0.14, 0.19),  # vänster lår
            ellipsoid((0.0, 1.24, -0.20), (0.30, 0.20, 0.24)),             # bäcken
            kapsel((0.0, 1.32, -0.16), (0.0, 1.86, -0.06), 0.17, 0.18),     # bål
            kapsel((0.0, 1.95, -0.02), (0.02, 2.05, 0.06), 0.07, 0.07),     # hals
            ellipsoid((0.0, 2.17, 0.12), (0.16, 0.18, 0.17)),              # huvud
            ellipsoid((0.0, 2.27, 0.10), (0.175, 0.10, 0.18)),             # keps
            kapsel((0.0, 2.24, -0.05), (0.0, 2.02, -0.42), 0.07, 0.035),    # hästsvans
            kapsel((0.17, 1.90, -0.06), (0.20, 1.62, 0.18), 0.065, 0.06),   # höger överarm
            kapsel((0.20, 1.62, 0.18), (0.22, 1.98, 0.88), 0.055, 0.05),    # höger underarm över knät
            ellipsoid((0.22, 2.00, 0.95), (0.05, 0.05, 0.08)),             # handen
            kapsel((0.22, 2.01, 0.98), (0.22, 2.03, 1.10), 0.018, 0.015),   # pekfingret
            kapsel((-0.17, 1.90, -0.08), (-0.30, 1.50, -0.18), 0.065, 0.06),  # vänster överarm
            kapsel((-0.30, 1.50, -0.18), (-0.32, 1.10, -0.10), 0.055, 0.05),  # vänster underarm ned
        ]
        for V in mjuka:
            self._del(p, V, m, platt=False)
        self._del(p, lada_mellan(-0.15, 0.15, 2.20, 2.235, 0.18, 0.48), m)   # kepsens skärm
        self.punkter.append((E, N, 2.0))

    # ---------------------------------------------------------------- hund
    def _hund(self, o):
        E, N = o['lage']
        p = Plats(E, N, self._mark(E, N, 0.5) - 0.03, o['riktning_grad'], self.to_world)
        m = self._m('Konst_brons', BRONS, 0.6)
        delar = [
            kapsel((0, 0.62, -0.30), (0, 0.80, 0.08), 0.15, 0.17),       # rygg och bål, krökt uppåt
            kapsel((0, 0.80, 0.08), (0, 0.72, 0.24), 0.16, 0.12),        # bröst
            kapsel((0, 0.74, 0.26), (0, 0.66, 0.42), 0.08, 0.10),        # hals ned framåt
            ellipsoid((0, 0.66, 0.46), (0.10, 0.11, 0.13)),             # huvud
            kapsel((0, 0.64, 0.50), (0, 0.58, 0.66), 0.06, 0.04),        # nos
            kapsel((-0.07, 0.62, 0.20), (-0.08, 0.02, 0.24), 0.04, 0.03),  # framben
            kapsel((0.07, 0.62, 0.20), (0.08, 0.02, 0.26), 0.04, 0.03),
            kapsel((-0.08, 0.58, -0.30), (-0.09, 0.30, -0.42), 0.06, 0.04),  # bakben: lår
            kapsel((-0.09, 0.30, -0.42), (-0.09, 0.02, -0.32), 0.04, 0.03),  # och underben
            kapsel((0.08, 0.58, -0.30), (0.09, 0.30, -0.42), 0.06, 0.04),
            kapsel((0.09, 0.30, -0.42), (0.09, 0.02, -0.30), 0.04, 0.03),
            kapsel((0, 0.62, -0.42), (0, 0.10, -0.62), 0.035, 0.02),     # svansen ned mot marken
        ]
        for V in delar:
            self._del(p, V, m, platt=False)
        for s in (-1, 1):   # långa hängande öron som halsdukar
            self._del(p, lada_mellan(s * 0.10 - 0.02, s * 0.10 + 0.02, 0.30, 0.74, 0.38, 0.52), m)
        self.punkter.append((E, N, 1.5))

    # ---------------------------------------------------------------- Märkesbackens konstverk
    def _markeskonst(self, o):
        """Fyra pelare på rad (lokalt r) med en röd cylinder överst var, axlarna längs `riktning_grad`
        (lokalt f): en lång tunn stång, två mellanstora och en kort bred skiva (samma sak i olika
        proportioner). Efter användarens foton (Google Street View) och ortofotot 2023 (stångens riktning).
        `pelare`: [r, bredd, rund (0/1), topp_m, cylinder_radie, cylinder_langd]."""
        E, N = o['lage']
        y0 = self._mark(E, N, 2.5) - 0.3
        p = Plats(E, N, y0, o['riktning_grad'], self.to_world)
        gra, rod = self._m('Konst_pelare', KONST_GRA, 0.7), self._m('Konst_rod_cylinder', KONST_ROD, 0.45)
        for r, b, rund, topp, cr, cl in o['pelare']:
            topp += 0.3   # foten ligger 0,3 m i marken
            if rund:
                self._del(p, cylinder((r, 0.0, 0.0), (r, topp, 0.0), b / 2, n=14), gra, platt=False)
            else:
                self._del(p, lada_mellan(r - b / 2, r + b / 2, 0.0, topp, -b / 2, b / 2), gra)
            self._del(p, cylinder((r, topp + cr, -cl / 2), (r, topp + cr, cl / 2), cr, n=20), rod, LOS, platt=False)
        self.punkter.append((E, N, 4.0))

    # ---------------------------------------------------------------- rondellhund
    def _rondellhund(self, o):
        """Rondellhund av svetsade rör: lila, gula detaljer, lyfter höger bakben och kissar (tunn gul
        stråle). Ungefär `hojd_m` hög; framåt = `riktning_grad`."""
        E, N = o['lage']
        k = o.get('hojd_m', 1.2) / 1.2
        p = Plats(E, N, self._mark(E, N, 0.6) - 0.02, o['riktning_grad'], self.to_world)
        lila, gul = self._m('Konst_lila', HUND_LILA, 0.5), self._m('Konst_gul', HUND_GUL, 0.5)
        S = lambda *v: tuple(x * k for x in v)
        rör = [   # (från, till, radie, material)
            (S(0, 0.72, -0.42), S(0, 0.78, 0.36), 0.17, lila),          # kroppen
            (S(-0.12, 0.66, 0.30), S(-0.12, 0.06, 0.32), 0.065, lila),  # framben
            (S(0.12, 0.66, 0.30), S(0.12, 0.06, 0.34), 0.065, lila),
            (S(-0.12, 0.66, -0.36), S(-0.14, 0.06, -0.40), 0.07, lila),  # vänster bakben (står)
            (S(0.12, 0.70, -0.36), S(0.42, 0.86, -0.30), 0.07, lila),    # höger bakben: lyft åt sidan
            (S(0.42, 0.86, -0.30), S(0.58, 0.70, -0.30), 0.06, lila),
            (S(0, 0.86, 0.34), S(0, 1.04, 0.48), 0.10, lila),            # hals
            (S(0, 1.06, 0.40), S(0, 1.08, 0.74), 0.13, lila),            # huvud
            (S(0, 1.02, 0.74), S(0, 1.00, 0.86), 0.07, lila),            # nos
            (S(0, 0.84, -0.42), S(0, 1.06, -0.62), 0.04, lila),          # svans upp
        ]
        for a, b, r, m in rör:
            self._del(p, cylinder(a, b, r * k, n=12), m, LOS, platt=False)
        gula = [
            (S(0, 0.95, 0.40), S(0, 1.00, 0.46), 0.12),                  # halsband
            (S(-0.12, 0.0, 0.30), S(-0.12, 0.06, 0.32), 0.09),           # tassar
            (S(0.12, 0.0, 0.32), S(0.12, 0.06, 0.34), 0.09),
            (S(-0.14, 0.0, -0.40), S(-0.14, 0.06, -0.40), 0.09),
            (S(0.58, 0.64, -0.30), S(0.62, 0.70, -0.30), 0.08),          # den lyfta tassen
            (S(-0.10, 1.16, 0.50), S(-0.14, 1.30, 0.46), 0.05),          # öron
            (S(0.10, 1.16, 0.50), S(0.14, 1.30, 0.46), 0.05),
            (S(0, 1.06, -0.62), S(0, 1.12, -0.68), 0.05),                # svanstipp
            (S(-0.09, 1.14, 0.68), S(-0.09, 1.16, 0.74), 0.03),          # ögon
            (S(0.09, 1.14, 0.68), S(0.09, 1.16, 0.74), 0.03),
            (S(0, 0.99, 0.86), S(0, 0.99, 0.89), 0.05),                  # nostipp
        ]
        for a, b, r in gula:
            self._del(p, cylinder(a, b, r * k, n=12), gul, LOS, platt=False)
        # strålen: tre korta raka bitar i en båge från magen ut mot pelaren
        båge = [S(0.16, 0.62, -0.20), S(0.42, 0.52, -0.18), S(0.62, 0.28, -0.16), S(0.74, 0.02, -0.14)]
        for a, b in zip(båge[:-1], båge[1:]):
            self._del(p, cylinder(a, b, 0.012 * k, n=6), gul, LOS, platt=False)
        self.punkter.append((E, N, 1.2))

    # ---------------------------------------------------------------- kolonistuga, staket, flaggstång
    def _kolonistuga(self, o):
        hus = np.array(o['hus'], float)
        c = hus.mean(0)
        g = o['nock_grad']
        nock = np.array([math.sin(math.radians(g)), math.cos(math.radians(g))])
        tvars = np.array([nock[1], -nock[0]])
        L = float(np.ptp((hus - c) @ nock))    # längs nocken
        B = float(np.ptp((hus - c) @ tvars))   # tvärs (takfall)
        y0 = self._mark(c[0], c[1], max(L, B) / 2)
        p = Plats(c[0], c[1], y0, g, self.to_world)   # f = längs nocken (gavlarna fram/bak), r = tvärs
        vagg = 2.15                    # vägghöjd
        hr, hf = B / 2, L / 2
        nockh = vagg + hr * 0.7
        rod, vit = self._m('Konst_falurod', FALUROD, 0.9), self._m('Konst_vit_snickeri', VITT, 0.8)
        # stomme med gavlar (ett konvext prisma), ned under marken
        stomme = [(sr * hr, u, sf * hf) for sr in (-1, 1) for sf in (-1, 1) for u in (-0.4, vagg)]
        stomme += [(0, nockh, sf * hf) for sf in (-1, 1)]
        self._del(p, stomme, rod)
        self._del(p, lada_mellan(-hr - 0.05, hr + 0.05, -0.4, 0.25, -hf - 0.05, hf + 0.05),
                  self._m('Konst_sockel', (120, 120, 118)))
        # knutar
        for sr in (-1, 1):
            for sf in (-1, 1):
                self._del(p, lada((sr * (hr - 0.02), vagg / 2, sf * (hf - 0.02)), (0.14, vagg, 0.14)), vit)
        # tak: två plattor med utsprång, svart papp
        ut, tjock = 0.3, 0.08
        tak = self._m('Konst_tak_papp', TAKSVART, 0.95)
        for sr in (-1, 1):
            r_ut = sr * (hr + ut)
            u_ut = vagg - ut * (nockh - vagg) / hr
            V = []
            for sf in (-1, 1):
                for du in (0.0, tjock):
                    V += [(0.0, nockh + 0.02 + du, sf * (hf + ut)), (r_ut, u_ut + du, sf * (hf + ut))]
            self._del(p, V, tak)
            # vindskivor (vita) längs gavlarnas takkant
            for sf in (-1, 1):
                V = []
                for du in (-0.16, 0.02):
                    for df in (0.0, 0.04):
                        V += [(0.0, nockh + du, sf * (hf + ut + df)), (r_ut, u_ut + du, sf * (hf + ut + df))]
                self._del(p, V, vit)
        # skorsten på nocken, nära ena gaveln
        self._del(p, lada((0, nockh + 0.3, -hf * 0.45), (0.38, 0.9, 0.38)), self._m('Konst_tegel', TEGEL, 0.9))
        self._del(p, lada((0, nockh + 0.78, -hf * 0.45), (0.48, 0.07, 0.48)), tak)
        # fönster på långsidorna, dörr på ena gaveln
        glas = self._m('Konst_glas', GLAS, 0.2)
        for sr in (-1, 1):
            for fm in (-0.25, 0.3):
                rr = sr * (hr + 0.03)
                self._del(p, lada((rr, 1.35, fm * L), (0.06, 0.95, 0.95)), vit)
                self._del(p, lada((sr * (hr + 0.05), 1.35, fm * L), (0.04, 0.78, 0.78)), glas)
        self._del(p, lada((0.0, 1.0, hf + 0.03), (0.85, 2.0, 0.06)), vit)
        self._del(p, lada((-0.15, 1.0, hf + 0.06), (0.04, 0.04, 0.04)), self._m('Konst_metall', (60, 60, 60), 0.4))
        # gavelfönster
        self._del(p, lada((0.0, vagg + 0.25, -hf - 0.03), (0.6, 0.45, 0.06)), vit)
        self._del(p, lada((0.0, vagg + 0.25, -hf - 0.05), (0.48, 0.33, 0.04)), glas)
        self.punkter.append((c[0], c[1], max(L, B)))
        self._staket(o)
        self._flaggstang(o)

    def _staket(self, o):
        """Gärdesgård: rödbruna stolpar var 2 m med två slanor; en vit grind mitt på sidan grind_sida."""
        P = np.array(o['staket'], float)
        m = self._m('Konst_staket', STAKET, 0.9)
        vit = self._m('Konst_vit_snickeri', VITT, 0.8)
        n = len(P)
        for i in range(n):
            a, b = P[i], P[(i + 1) % n]
            d = b - a
            L = float(np.hypot(*d))
            grad = math.degrees(math.atan2(d[0], d[1]))
            k = max(1, round(L / 2.0))
            grind = i == o.get('grind_sida', -1)
            for j in range(k + 1):
                E, N = a + d * (j / k)
                p = Plats(E, N, self._mark(E, N) - 0.2, grad, self.to_world)
                self._del(p, lada((0, 0.6, 0), (0.1, 1.2, 0.1)), m, LOS)
            for j in range(k):
                s0, s1 = j / k, (j + 1) / k
                mid = (s0 + s1) / 2
                ar_grind = grind and j == k // 2
                E0, N0 = a + d * s0
                E1, N1 = a + d * s1
                y0, y1 = self._mark(E0, N0), self._mark(E1, N1)
                p = Plats(*(a + d * mid), (y0 + y1) / 2, grad, self.to_world)
                seg = L / k - 0.1
                if ar_grind:   # vit spjälgrind
                    for q in np.linspace(-seg / 2 + 0.08, seg / 2 - 0.08, 9):
                        self._del(p, lada((0, 0.5, q), (0.03, 0.95, 0.07)), vit, LOS)
                    for u in (0.25, 0.8):
                        self._del(p, lada((0, u, 0), (0.035, 0.08, seg)), vit, LOS)
                    continue
                for u in (0.5, 0.9):
                    V = []
                    for f, yy in ((-seg / 2 - 0.05, y0), (seg / 2 + 0.05, y1)):
                        dy = yy - (y0 + y1) / 2
                        for dr in (-0.025, 0.025):
                            for du in (-0.05, 0.05):
                                V.append((dr + 0.06, u + dy + du, f))
                    self._del(p, V, m, LOS)

    def _flaggstang(self, o):
        E, N = o['flaggstang']
        p = Plats(E, N, self._mark(E, N) - 0.3, 0, self.to_world)
        H = 9.0
        vit = self._m('Konst_vit_snickeri', VITT, 0.8)
        self._del(p, cylinder((0, 0, 0), (0, H, 0), 0.065, 0.04), vit)
        self._del(p, ellipsoid((0, H + 0.07, 0), (0.08, 0.08, 0.08), 8, 4),
                  self._m('Konst_guld', (200, 160, 60), 0.4), platt=False)
        # vimpel som hänger längs stången (blå med gul rand)
        self._del(p, lada_mellan(0.05, 0.27, H - 2.3, H - 0.15, -0.006, 0.006),
                  self._m('Konst_flagga_bla', FLAGGBLA, 0.9), LOS)
        self._del(p, lada_mellan(0.05, 0.27, H - 1.3, H - 1.15, -0.009, 0.009),
                  self._m('Konst_flagga_gul', FLAGGGUL, 0.9), LOS)
        self.punkter.append((E, N, 1.0))

    # ---------------------------------------------------------------- livboj och skylt
    def _livboj(self, o):
        E, N = o['lage']
        p = Plats(E, N, self._mark(E, N) - 0.3, o['riktning_grad'], self.to_world)
        st = self._m('Konst_livstolpe', LIVSTOLPE, 0.6)
        for r in (-0.22, 0.22):
            self._del(p, lada((r, 0.85, -0.03), (0.06, 1.7, 0.06)), st, LOS)
        self._del(p, lada((0, 1.62, 0.0), (0.18, 0.14, 0.12)), self._m('Konst_metall', (60, 60, 60), 0.4), LOS)
        # ringen: 8 bitar, rött och vitt växelvis
        R, rr, uc = 0.33, 0.065, 1.30
        rod, vit = self._m('Konst_livboj_rod', LIVROD, 0.6), self._m('Konst_vit_snickeri', VITT, 0.8)
        for k in range(8):
            V = []
            for t in np.linspace(2 * math.pi * k / 8, 2 * math.pi * (k + 1) / 8, 3):
                cx, cu = R * math.cos(t), uc + R * math.sin(t)
                for q in range(6):
                    w = 2 * math.pi * q / 6
                    rad = rr * math.cos(w)
                    V.append((cx + rad * math.cos(t), cu + rad * math.sin(t), 0.06 + rr * math.sin(w)))
            self._del(p, V, rod if k % 2 == 0 else vit, LOS, platt=False)

    def _skylt_badforbud(self, o):
        E, N = o['lage']
        p = Plats(E, N, self._mark(E, N) - 0.3, o['riktning_grad'], self.to_world)
        tra = self._m('Konst_skyltstolpe', STOLPE_TRA, 0.9)
        self._del(p, lada((0, 0.85, 0), (0.07, 1.7, 0.07)), tra, LOS)
        u0, u1, b = 1.45, 1.85, 0.32
        self._del(p, lada((0, (u0 + u1) / 2, 0.05), (b, u1 - u0, 0.02)), self._m('Konst_skylt_bak', (150, 150, 150), 0.5), LOS)
        # framsidan med texturen (fyrhörning vänd framåt)
        V = p.varld([(-b / 2, u0, 0.062), (b / 2, u0, 0.062), (b / 2, u1, 0.062), (-b / 2, u1, 0.062)])
        F = np.array([[0, 1, 2], [0, 2, 3]])
        fram = p.varld([(0, 0, 1)])[0] - p.varld([(0, 0, 0)])[0]
        nrm = np.cross(V[1] - V[0], V[2] - V[0])
        if np.dot(nrm, fram) < 0:
            F = F[:, ::-1]
        uv = np.array([[1, 0], [0, 0], [0, 1], [1, 1]], float)   # r = -b/2 är betraktarens högra kant
        if not hasattr(self, '_skyltmat'):
            self._skyltmat = _skylt_material()
        self.add(LOS, trimesh.Trimesh(V, F, process=False), self._skyltmat, uv)

    # ================================================================ gemensamt för de nya typerna
    def _tex(self, namn, bild, rough=0.8, metal=0.0):
        if namn not in self._mats:
            self._mats[namn] = trimesh.visual.material.PBRMaterial(name=namn, baseColorTexture=bild,
                                                                   metallicFactor=metal, roughnessFactor=rough)
        return self._mats[namn]

    def _quad(self, grupp, V, uv, material, ut):
        """Fyrhörning (4 världspunkter) med UV, framsidan mot vektorn `ut` (världen)."""
        V = np.asarray(V, float)
        F = np.array([[0, 1, 2], [0, 2, 3]])
        if np.dot(np.cross(V[1] - V[0], V[2] - V[0]), ut) < 0:
            F = F[:, ::-1]
        self.add(grupp, trimesh.Trimesh(V, F, process=False), material, np.asarray(uv, float))

    def _ut(self, grad):
        """Kompassriktning -> världsvektor (x = E, z = -N)."""
        t = math.radians(grad)
        return np.array([math.sin(t), 0.0, -math.cos(t)])

    def _skylt_yta(self, p, b, h, u0, f, material, grupp=LOS):
        """Texturerad skylt i Plats p: bredd b, höjd h från u0, på avståndet f framåt, vänd framåt."""
        V = p.varld([(-b / 2, u0, f), (b / 2, u0, f), (b / 2, u0 + h, f), (-b / 2, u0 + h, f)])
        fram = p.varld([(0, 0, 1)])[0] - p.varld([(0, 0, 0)])[0]
        self._quad(grupp, V, [[1, 0], [0, 0], [0, 1], [1, 1]], material, fram)

    # ================================================================ Corson: lampgrupper (vältbara)
    def _corsonlampa(self, o):
        if self.valt is None:
            return
        typ = 'Corsonlampa'
        if not self.valt.har_mall(typ):
            self.valt.mall(typ, _lampgrupp(self._m))
        grad = o.get('riktning_grad', 0.0)
        for E, N in o['lagen']:
            x, z = self.to_world(E, N)
            t = math.radians(grad)
            self.valt.placera(typ, [float(x), self._mark(E, N, 1.0), float(z)], (math.sin(t), -math.cos(t)))

    # ================================================================ D-skulpturen (sju bågar runt en stolpe)
    def _d_skulptur(self, o):
        E, N = o['lage']
        H = o.get('hojd_m', 2.5)
        p = Plats(E, N, self._mark(E, N, 1.2) - 0.05, o.get('riktning_grad', 0), self.to_world)
        m = self._m('Konst_stal', o.get('farg', (205, 207, 210)), 0.4)
        self._del(p, cylinder((0, 0, 0), (0, H, 0), 0.06, 0.05, 10), m, platt=False)
        R = (H - 0.2) / 2
        mitt_u = 0.1 + R
        for k in range(o.get('bagar', 7)):
            a = 2 * math.pi * k / o.get('bagar', 7)
            dr, df = math.cos(a), math.sin(a)
            pts = []
            for i in range(13):
                phi = math.pi * i / 12
                ut = 0.05 + R * math.sin(phi)
                pts.append((dr * ut, mitt_u - R * math.cos(phi), df * ut))
            for q0, q1 in zip(pts[:-1], pts[1:]):
                self._del(p, cylinder(q0, q1, 0.035, 0.035, 6), m, platt=False)
        self.punkter.append((E, N, H / 2 + 0.5))

    # ================================================================ trädbänk (fyrkantig bänk runt ett träd)
    def _tradbank(self, o):
        E, N = o['lage']
        p = Plats(E, N, self._mark(E, N, 1.2) - 0.03, o.get('riktning_grad', 0), self.to_world)
        m = self._m('Mobel_morkgra', (50, 56, 58), 0.6)
        yt, inn = o.get('yttre_m', 2.3) / 2, o.get('inre_m', 1.1) / 2
        for k in range(4):   # fyra sidor, roterade 90 grader
            def rot(P, k=k):
                P = np.asarray(P, float)
                c, s_ = [(1, 0), (0, 1), (-1, 0), (0, -1)][k]
                return np.column_stack([P[:, 0] * c - P[:, 2] * s_, P[:, 1], P[:, 0] * s_ + P[:, 2] * c])
            for j in range(4):   # ribbor
                f0 = inn + (yt - inn) * j / 4 + 0.02
                f1 = inn + (yt - inn) * (j + 1) / 4 - 0.02
                self._del(p, rot(lada_mellan(-yt, yt, 0.42, 0.47, f0, f1)), m, LOS)
            for r in (-yt + 0.15, yt - 0.15):
                self._del(p, rot(lada((r, 0.21, (yt + inn) / 2), (0.06, 0.42, yt - inn - 0.1))), m, LOS)

    # ================================================================ cisternen (fjärrvärmeackumulatorn)
    def _cistern(self, o):
        E, N = o['lage']
        R, H = o['radie_m'], o['hojd_m']
        p = Plats(E, N, self._mark(E, N, R) - 0.5, 0, self.to_world)
        karna = self._m('Cistern_karna', (48, 52, 56), 0.7)
        self._del(p, cylinder((0, 0, 0), (0, H + 0.5, 0), R, R, 48), karna, platt=False)
        self._del(p, cylinder((0, H + 0.5, 0), (0, H + 1.6, 0), R, R * 0.92, 48), self._m('Cistern_tak', (90, 94, 98), 0.6))
        farger = [('Cistern_stav_ljus', (206, 204, 196)), ('Cistern_stav_guld', (184, 156, 98)),
                  ('Cistern_stav_brun', (128, 112, 92)), ('Cistern_stav_mork', (74, 76, 78))]
        rng = np.random.default_rng(11)
        n = o.get('staver', 220)
        for k in range(n):   # stavar runt fasaden, olika höjd och färg (taggig topp)
            a = 2 * math.pi * (k + rng.uniform(-0.25, 0.25)) / n
            rr = R + 0.35 + rng.uniform(0, 0.25)
            topp = H + 0.5 + rng.uniform(-2.5, 1.8)
            botten = rng.uniform(0.0, 2.5)
            namn, rgb = farger[rng.choice(4, p=[0.45, 0.2, 0.15, 0.2])]
            c, s_ = math.cos(a), math.sin(a)
            P = []
            bredd = math.pi * R / n * rng.uniform(0.75, 1.05)   # nästan tätt: fasaden är stavarna
            for dt in (-bredd, bredd):
                for dr in (-0.07, 0.07):
                    for u in (botten, topp):
                        P.append(((rr + dr) * c - dt * s_, u, (rr + dr) * s_ + dt * c))
            self._del(p, P, self._m(namn, rgb, 0.6), LOS)
        self.punkter.append((E, N, R + 2))

    # ================================================================ cykeltaket norr om Studenthuset
    def _cykeltak(self, o):
        P = np.array(o['fotavtryck'], float)
        c = P.mean(0)
        kanter = [P[(i + 1) % 4] - P[i] for i in range(4)]
        lang = max(kanter, key=lambda v: np.hypot(*v))
        L = float(np.hypot(*lang))
        grad = math.degrees(math.atan2(lang[0], lang[1]))
        B = float(min(np.hypot(*v) for v in kanter))
        y0 = self._mark(c[0], c[1], L / 2)
        p = Plats(c[0], c[1], y0, grad, self.to_world)   # f längs taket, r tvärs
        hl, hb = L / 2, B / 2
        H = o.get('hojd_m', 2.6)
        rf, tf = tuple(o.get('ram_farg', (104, 36, 40))), tuple(o.get('tak_farg', (62, 64, 66)))
        rod = self._m('Cykeltak_ram_%02x%02x%02x' % rf, rf, 0.6)
        tak = self._m('Cykeltak_tak_%02x%02x%02x' % tf, tf, 0.8)
        n = max(2, int(round(L / 3.3)))
        for k in range(n + 1):
            f = -hl + 0.15 + (L - 0.3) * k / n
            for r in (-hb + 0.3, hb - 0.3):
                self._del(p, lada((r, (H - 0.1) / 2 - 0.2, f), (0.14, H + 0.1, 0.14)), rod)
        self._del(p, lada_mellan(-hb, hb, H, H + 0.15, -hl, hl), tak)
        ff = tuple(o.get('fascia_farg', rf))
        fascia = self._m('Cykeltak_kant_%02x%02x%02x' % ff, ff, 0.6)
        for r in (-hb, hb):   # fascia
            self._del(p, lada_mellan(r - 0.04, r + 0.04, H - 0.3, H + 0.2, -hl, hl), fascia)
        for f in (-hl, hl):
            self._del(p, lada_mellan(-hb, hb, H - 0.3, H + 0.2, f - 0.04, f + 0.04), fascia)
        # betongvägg i ena änden (östra: den med störst E)
        if o.get('betongvagg', True):
            f_vagg = hl if p.en(0, hl)[0] > p.en(0, -hl)[0] else -hl
            s_ = 1 if f_vagg > 0 else -1
            self._del(p, lada_mellan(-hb, hb, -0.2, H, f_vagg - s_ * 0.25, f_vagg), self._m('Betong', (156, 154, 148), 0.95))
        # tvåvåningsställ: galvade ramar längs taket
        galv = self._m('Cykelstall_galv', (176, 180, 182), 0.4)
        for r in (-hb * 0.45, hb * 0.45):
            for u in (0.0, 1.45):
                self._del(p, lada_mellan(r - 0.25, r + 0.25, u, u + 0.06, -hl + 0.8, hl - 0.8), galv, LOS)
            for k in range(int(L / 2.5)):
                f = -hl + 1.0 + k * 2.5
                self._del(p, lada((r, 0.8, f), (0.06, 1.6, 0.06)), galv, LOS)
        self.punkter.append((c[0], c[1], hl))

    # ================================================================ Studenthuset: röd rutfasad på glasbotten
    def _studenthuset(self, o):
        E0, N0, E1, N1 = o['ram']
        bas_h = o.get('bas_h_m', 5.5)
        fot = [(E0, N0), (E1, N0), (E1, N1), (E0, N1)]
        y0 = min(self._mark(E, N) for E, N in fot + [((E0 + E1) / 2, (N0 + N1) / 2)])
        H = o.get('hojd_m', 24.0)
        if self.laserhojd is not None:
            from shapely.geometry import box as sbox
            lh = self.laserhojd(sbox(E0, N0, E1, N1))
            if lh is not None and lh[1] > bas_h + 6:
                H = float(lh[1])
        top = y0 + H
        fasad = self._tex('Studenthus_fasad', _rutfasad(), 0.85)
        TEX = 16.0
        # röda väggar från bas_h till toppen (med UV i meter / 16)
        hornen = [(E0, N0), (E1, N0), (E1, N1), (E0, N1)]
        for i in range(4):
            a, b = hornen[i], hornen[(i + 1) % 4]
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            ut_en = ((b[1] - a[1]) / L, -(b[0] - a[0]) / L)   # moturs ring: utåt till höger
            ut = np.array([ut_en[0], 0.0, -ut_en[1]])
            V = []
            for (E, N), y in ((a, y0 + bas_h), (b, y0 + bas_h), (b, top), (a, top)):
                x, z = self.to_world(E, N)
                V.append((x, y, z))
            u0 = (a[0] + a[1]) / TEX
            self._quad(FAST, V, [[u0, bas_h / TEX], [u0 + L / TEX, bas_h / TEX], [u0 + L / TEX, H / TEX],
                                 [u0, H / TEX]], fasad, ut)
        # undersida (soffitt) och tak
        def platt(Es, Ns, y, upp, material):
            V = []
            for E, N in zip(Es, Ns):
                x, z = self.to_world(E, N)
                V.append((x, y, z))
            self._quad(FAST, V, [[0, 0], [1, 0], [1, 1], [0, 1]], material, np.array([0, 1.0 if upp else -1.0, 0]))
        rod_mork = self._m('Studenthus_soffitt', (120, 50, 38), 0.9)
        platt([E0, E1, E1, E0], [N0, N0, N1, N1], y0 + bas_h, False, rod_mork)
        platt([E0 + 1.2, E1 - 1.2, E1 - 1.2, E0 + 1.2], [N0 + 1.2, N0 + 1.2, N1 - 1.2, N1 - 1.2], top - 0.4, True,
              self._m('Studenthus_tak', (58, 62, 70), 0.6))
        rod = self._m('Studenthus_rod', (172, 70, 50), 0.85)
        p = Plats((E0 + E1) / 2, (N0 + N1) / 2, y0, 0, self.to_world)
        hx, hy = (E1 - E0) / 2, (N1 - N0) / 2
        for r0, r1, f0, f1 in ((-hx, hx, -hy, -hy + 1.2), (-hx, hx, hy - 1.2, hy), (-hx, -hx + 1.2, -hy, hy),
                               (hx - 1.2, hx, -hy, hy)):   # takkantens röda ram
            self._del(p, lada_mellan(r0, r1, H - 0.6, H + 0.3, f0, f1), rod)
        # glasad bottenvåning, indragen (mest mot Corson i väster)
        iv, io, i_s, i_n = o.get('glas_in_m', [2.0, 0.6, 0.6, 0.6])   # väster, öster, söder, norr
        glas = self._m('Studenthus_glas', (52, 72, 88), 0.15)
        self._del(p, lada_mellan(-hx + iv, hx - io, -0.4, bas_h, -hy + i_s, hy - i_n), glas)
        post = self._m('Studenthus_post', (70, 50, 46), 0.5)
        for r_kant, f_lista in ((-hx + iv - 0.02, None), (hx - io + 0.02, None)):
            for k in range(int((2 * hy - i_s - i_n) / 1.6) + 1):
                f = -hy + i_s + k * 1.6
                self._del(p, lada((r_kant, bas_h / 2, f), (0.08, bas_h, 0.08)), post)
        for f_kant in (-hy + i_s - 0.02, hy - i_n + 0.02):
            for k in range(int((2 * hx - iv - io) / 1.6) + 1):
                r = -hx + iv + k * 1.6
                self._del(p, lada((r, bas_h / 2, f_kant), (0.08, bas_h, 0.08)), post)

    # ================================================================ Kårallens vindbrygga
    def _vindbrygga(self, o):
        (Ea, Na), (Eb, Nb) = o['fran'], o['till']
        L = math.hypot(Eb - Ea, Nb - Na)
        grad = math.degrees(math.atan2(Eb - Ea, Nb - Na))
        y = self._mark(Ea, Na) + 0.05
        p = Plats(Ea, Na, y, grad, self.to_world)
        B = o.get('bredd_m', 3.2)
        dack = self._m('Vindbrygga_dack', (98, 92, 86), 0.8)
        stal = self._m('Vindbrygga_stal', (58, 62, 66), 0.45)
        self._del(p, lada_mellan(-B / 2, B / 2, -0.3, 0.0, -0.3, L), dack)
        for r in (-B / 2, B / 2):   # balkar under och räcken med glas
            self._del(p, lada_mellan(r - 0.08, r + 0.08, -0.7, 0.0, -0.3, L), stal)
            for k in range(int(L / 1.5) + 1):
                f = min(k * 1.5, L - 0.05)
                self._del(p, lada((r, 0.55, f), (0.05, 1.1, 0.05)), stal)
            self._del(p, lada_mellan(r - 0.04, r + 0.04, 1.05, 1.12, -0.3, L), stal)
            self._del(p, lada_mellan(r - 0.01, r + 0.01, 0.15, 1.0, 0.0, L - 0.1), self._m('Glasracke', (150, 175, 185), 0.1), LOS)
        self.punkter.append((Ea, Na, 1.0))

    # ================================================================ scenen på Blå havet ("flotten")
    def _scen(self, o):
        E0, N0, E1, N1 = o['ram']
        H = o.get('hojd_m', 0.5)
        c = ((E0 + E1) / 2, (N0 + N1) / 2)
        y0 = min(self._mark(E, N) for E, N in ((E0, N0), (E1, N0), (E1, N1), (E0, N1)))
        p = Plats(c[0], c[1], y0, 0, self.to_world)
        hx, hy = (E1 - E0) / 2, (N1 - N0) / 2
        self._del(p, lada_mellan(-hx, hx, -0.3, H - 0.06, -hy, hy), self._m('Scen_sida', (70, 58, 46), 0.9))
        planka = self._tex('Scen_plankor', _plankor(), 0.85)
        V = p.varld([(-hx, H, -hy), (hx, H, -hy), (hx, H, hy), (-hx, H, hy)])
        self._quad(FAST, V, [[0, 0], [hx * 2 / 4, 0], [hx * 2 / 4, hy * 2 / 4], [0, hy * 2 / 4]], planka,
                   np.array([0, 1.0, 0]))

    # ================================================================ Campushallens entré och ramp
    def _campushallen(self, o):
        r = o['ramp']
        (Ea, Na), (Eb, Nb) = r['fran'], r['till']   # från marken upp till krönet
        L = math.hypot(Eb - Ea, Nb - Na)
        grad = math.degrees(math.atan2(Eb - Ea, Nb - Na))
        y0 = self._mark(Ea, Na)
        p = Plats(Ea, Na, y0, grad, self.to_world)
        B, Hr = r.get('bredd_m', 2.2), r.get('hojd_m', 2.8)
        betong = self._m('Betong', (156, 154, 148), 0.95)
        V = [(s * B / 2, u, f) for s in (-1, 1) for u, f in ((-0.5, 0.0), (0.0, 0.0), (Hr, L), (-0.5, L))]
        self._del(p, V, betong)
        sida = 1 if r.get('vagg_till_vanster', True) else -1   # räcket på den fria sidan (r > 0 = höger)
        for k in range(int(L / 1.4) + 1):
            f = min(k * 1.4, L)
            u = Hr * f / L
            self._del(p, lada((sida * (B / 2 - 0.05), u + 0.55, f), (0.05, 1.1, 0.05)), self._m('Racke_stal', (120, 124, 128), 0.4), LOS)
        Vr = [(sida * (B / 2 - 0.05) + d, u + 1.08 + du, f) for d in (-0.03, 0.03) for du in (0.0, 0.05)
              for u, f in ((0.0, 0.0), (Hr, L))]
        self._del(p, Vr, self._m('Racke_stal', (120, 124, 128), 0.4), LOS)
        Vn = [(sida * (B / 2 - 0.05) + d, u + du, f) for d in (-0.01, 0.01) for du in (0.15, 1.0)
              for u, f in ((0.0, 0.0), (Hr, L))]
        self._del(p, Vn, self._m('Racke_nat', (96, 100, 104), 0.5), LOS)
        # entré: glasparti, lameller och skylten CAMPUSHALLEN på väggen
        e = o['entre']
        (Ea, Na), (Eb, Nb) = e['fran'], e['till']
        L = math.hypot(Eb - Ea, Nb - Na)
        c = ((Ea + Eb) / 2, (Na + Nb) / 2)
        pe = Plats(c[0], c[1], self._mark(*c), e['riktning_grad'], self.to_world)   # framåt = ut från väggen
        Hg = e.get('hojd_m', 4.2)
        self._del(pe, lada_mellan(-L / 2, L / 2, -0.3, Hg, -0.05, 0.12), self._m('Entre_glas', (56, 74, 88), 0.15))
        for k in range(int(L / 1.2) + 1):
            self._del(pe, lada((-L / 2 + k * 1.2, Hg / 2, 0.15), (0.07, Hg, 0.07)), self._m('Entre_post', (72, 76, 80), 0.5))
        lam = self._m('Lameller_tra', (88, 70, 54), 0.85)
        for k in range(int(Hg / 0.3)):   # liggande lameller framför högra halvan
            u = 0.2 + k * 0.3
            self._del(pe, lada_mellan(0.0, L / 2, u, u + 0.08, 0.6, 0.72), lam, LOS)
        for r_ in (0.0, L / 2):
            self._del(pe, lada((r_, Hg / 2, 0.66), (0.08, Hg, 0.08)), lam, LOS)
        skylt = self._tex('Skylt_campushallen', _textskylt('CAMPUSHALLEN', (210, 212, 210), (58, 60, 64), 1400, 140), 0.6)
        self._skylt_yta(pe, min(L * 0.9, 6.0), 0.6, Hg + 0.15, 0.14, skylt)

    # ================================================================ skyltar och markiser
    def _skyltpelare(self, o):
        E, N = o['lage']
        p = Plats(E, N, self._mark(E, N) - 0.05, o['riktning_grad'], self.to_world)
        H, B = o.get('hojd_m', 3.4), o.get('bredd_m', 0.9)
        self._del(p, lada((0, 0.35, 0), (B + 0.1, 0.7, 0.45)), self._m('Betong', (156, 154, 148), 0.95))
        self._del(p, lada((0, 0.7 + H / 2, 0), (B, H, 0.22)), self._m('Pelare_gra', (140, 146, 150), 0.5))
        bild = _perforerad(o['text'], o.get('stående', True))
        mat_ = self._tex('Skylt_' + o['text'].replace('-', '_'), bild, 0.5, 0.3)
        for s in (1, -1):   # båda sidor
            ps = Plats(E, N, p.y0, o['riktning_grad'] + (0 if s > 0 else 180), self.to_world)
            self._skylt_yta(ps, B * 0.96, H * 0.98, 0.72, 0.115, mat_)
        self.punkter.append((E, N, 1.0))

    def _fasadskylt(self, o):
        E, N = o['lage']
        p = Plats(E, N, self._mark(E, N), o['riktning_grad'], self.to_world)
        B, Hs, u0 = o['bredd_m'], o['hojd_m'], o['over_mark_m']
        stil = o.get('stil', 'pressbyran')
        if stil == 'pressbyran':
            bild = _pressbyran()
        else:
            bild = _textskylt(o['text'], (235, 235, 230), (40, 40, 44), 1200, 200)
        self._del(p, lada((0, u0 + Hs / 2, 0.06), (B, Hs, 0.12)), self._m('Skylt_lada', (230, 196, 20) if stil == 'pressbyran' else (220, 220, 216), 0.5), LOS)
        self._skylt_yta(p, B, Hs, u0, 0.125, self._tex('Skylt_' + stil, bild, 0.5))

    def _markiser(self, o):
        (Ea, Na), (Eb, Nb) = o['fran'], o['till']
        n = o['antal']
        m = self._m('Markis_gra', o.get('farg', (92, 96, 100)), 0.8)
        for k in range(n):
            t = (k + 0.5) / n
            E, N = Ea + (Eb - Ea) * t, Na + (Nb - Na) * t
            p = Plats(E, N, self._mark(E, N), o['riktning_grad'], self.to_world)
            u, d, b = o['hojd_m'], o.get('djup_m', 0.9), o.get('bredd_m', 2.2)
            V = [(s * b / 2, u, 0.0) for s in (-1, 1)] + [(s * b / 2, u + 0.04, 0.0) for s in (-1, 1)]
            V += [(s * b / 2, u - 0.55, d) for s in (-1, 1)] + [(s * b / 2, u - 0.5, d) for s in (-1, 1)]
            self._del(p, V, m, LOS)


    # ================================================================ ringhus (Ångströmhuset): ring med snett avskuret tak
    def _ringhus(self, o):
        Ec, Nc = o['lage']
        Ru, Ri = o['r_ute_m'], o['r_inne_m']
        h0 = o['tak_mitt_m']
        lut = math.tan(math.radians(o['lutning_grad']))
        rikt = math.radians(o['stiger_mot_grad'])
        dE, dN = math.sin(rikt), math.cos(rikt)
        y0 = self._mark(Ec, Nc, Ru) - 0.3
        mark_mitt = self._mark(Ec, Nc)

        def tak(E, N):   # takets höjd (världen) i punkten: ett lutande plan
            return mark_mitt + h0 + lut * ((E - Ec) * dE + (N - Nc) * dN)
        n = 64
        fasad = self._tex('Ringhus_fasad', _ringfasad(), 0.7)
        takmat = self._m('Ringhus_tak', (226, 228, 226), 0.8)
        TB, TH = 16.0, 8.0
        for k in range(n):
            a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
            for R, inat in ((Ru, False), (Ri, True)):
                P = [(Ec + R * math.sin(a), Nc + R * math.cos(a)) for a in (a0, a1)]
                V = []
                for (E, N), y in ((P[0], y0), (P[1], y0), (P[1], tak(*P[1])), (P[0], tak(*P[0]))):
                    x, z = self.to_world(E, N)
                    V.append((x, y, z))
                am = (a0 + a1) / 2
                ut = np.array([math.sin(am), 0.0, -math.cos(am)]) * (-1 if inat else 1)
                u0, u1 = R * a0 / TB, R * a1 / TB
                hv = [(V[i][1] - (mark_mitt - 0.3)) / TH for i in range(4)]
                self._quad(FAST, V, [[u0, hv[0]], [u1, hv[1]], [u1, hv[2]], [u0, hv[3]]], fasad, ut)
            # taket: en ringbit
            Pt = [(Ec + Ru * math.sin(a0), Nc + Ru * math.cos(a0)), (Ec + Ru * math.sin(a1), Nc + Ru * math.cos(a1)),
                  (Ec + Ri * math.sin(a1), Nc + Ri * math.cos(a1)), (Ec + Ri * math.sin(a0), Nc + Ri * math.cos(a0))]
            V = []
            for E, N in Pt:
                x, z = self.to_world(E, N)
                V.append((x, tak(E, N) + 0.02, z))
            self._quad(FAST, V, [[0, 0], [1, 0], [1, 1], [0, 1]], takmat, np.array([0, 1.0, 0]))
        self.punkter.append((Ec, Nc, Ru + 1))

    # ================================================================ friform: hus direkt ur lasern (Kårallen)
    def _friform(self, o):
        """Konturen (med gårdar) och taket ur laserns objekthöjd inom OSM-ytan: raka väggar längs den
        förenklade konturen, taket som en triangulerad yta som följer laserhöjderna (lutningar, nivåer)."""
        from rasterio.features import rasterize, shapes
        from scipy import ndimage as ndi
        from scipy.spatial import Delaunay
        from shapely.geometry import Polygon, shape, Point
        from shapely.geometry.polygon import orient
        from shapely.ops import unary_union
        if self.laser is None:
            print('friform: ingen laser, hoppar över', o['namn'])
            return
        omkr = Polygon(o['omkrets']).buffer(o.get('buffert_m', 2.0))
        L = self.laser
        E0, N0, E1, N1 = omkr.bounds
        c0, r0 = ~L.T * (E0, N1)
        c1, r1 = ~L.T * (E1, N0)
        r0, c0, r1, c1 = int(r0), int(c0), int(r1) + 1, int(c1) + 1
        hh = L.h[r0:r1, c0:c1].astype(float)
        frac = L.frac_s[r0:r1, c0:c1]
        T1 = L.T * rasterio_affine_translation(c0, r0)
        inne = rasterize([(omkr, 1)], out_shape=hh.shape, transform=T1).astype(bool)
        tak = inne & (hh > o.get('min_hojd_m', 2.5)) & (frac < 35)
        tak = ndi.binary_closing(tak, iterations=2) & inne      # laserns hål (svarta prickar)
        tak = ndi.binary_opening(tak, iterations=1)
        lab, n = ndi.label(tak)
        if n:
            st = ndi.sum(tak, lab, range(1, n + 1))
            tak &= np.isin(lab, 1 + np.nonzero(st >= 30)[0])
        # höjder: fyll hålen med grannarnas, jämna ut lätt
        giltig = tak & (hh > 2.0)
        fyllt = ndi.grey_closing(np.where(giltig, hh, 0.0), size=3)
        hojd = np.where(giltig, hh, fyllt)
        hojd = ndi.median_filter(hojd, size=3)
        hojd = np.where(tak, hojd, 0.0)
        # takkanten i lasern blandar in marken: bara inre celler, utjämnade, sedan utfyllt till närmaste värde
        karna = ndi.binary_erosion(tak, iterations=1) & (hojd > 2.0)
        if not karna.any():
            karna = tak & (hojd > 2.0)
        vikt = karna.astype(float)
        sig = o.get('utjamna_m', 1.4)
        utj = ndi.gaussian_filter(hojd * vikt, sig) / np.maximum(ndi.gaussian_filter(vikt, sig), 1e-6)
        _, (ni, nj) = ndi.distance_transform_edt(~karna, return_indices=True)
        utj = np.where(karna, utj, utj[ni, nj])
        # konturen: OSM-ytan (raka väggar) eller polygoner ur rastret, förenklade
        if o.get('kontur', 'osm') == 'osm':
            form = Polygon(o['omkrets']).buffer(0)
        else:
            delar = [shape(g) for g, v in shapes(tak.astype(np.uint8), mask=tak, transform=T1) if v == 1]
            form = unary_union(delar).simplify(o.get('forenkla_m', 0.8))
        if form.is_empty:
            return
        polys = list(getattr(form, 'geoms', [form]))
        # material: nedre våningar (t.o.m. referensnivån + en våning) och övre, plåttak, kommandobrygga
        vaning = o.get('vaning_m', 3.3)
        nedre = self._tex('Friform_nedre_' + o.get('nedre', 'puts'), _FASADER[o.get('nedre', 'puts')](vaning), 0.85)
        ovre = self._tex('Friform_ovre_' + o.get('ovre', 'panel'), _FASADER[o.get('ovre', 'panel')](vaning), 0.7)
        brygga_mat = self._tex('Friform_brygga', _FASADER['brygga'](vaning), 0.5)
        takmat = self._tex('Friform_plattak', _plattak(), 0.45, 0.3)
        TB, TH = 8.1, 2 * vaning
        ref = o.get('referens')   # (E, N): nivån där nedre fasaden slutar en våning upp (vindbryggan)
        y_skarv = (self._mark(*ref) + vaning) if ref else None
        topp_min = o.get('topp_min_m')   # kommandobryggan: takdelar högre än detta blir en egen volym
        if topp_min:
            utj_huvud = np.minimum(utj, o.get('huvudtak_max_m', topp_min - 0.6))
        else:
            utj_huvud = utj

        kantmat = self._m('Friform_kant', (200, 206, 212), 0.5)   # plåtkant (takfot) överst på väggarna
        bas_ref = y_skarv
        utj_tak = ndi.gaussian_filter(utj_huvud, o.get('tak_utjamna_m', 1.5))

        def snappa(y, y_min=None):
            """Till närmaste våningsgräns (fönstren klipps aldrig)."""
            ref_ = bas_ref if bas_ref is not None else 0.0
            v = ref_ + round((y - ref_) / vaning) * vaning
            if y_min is not None:
                v = max(v, ref_ + math.ceil((y_min - ref_) / vaning - 1e-6) * vaning)
            return v

        def kanter(poly):
            ut = []
            for ring in [poly.exterior] + list(poly.interiors):
                P = np.array(ring.coords)
                for a, b in zip(P[:-1], P[1:]):
                    if np.hypot(*(b - a)) >= 0.05:
                        ut.append((a, b))
            return ut

        def vaggar(kantlista, y_bot, mat_fn, grupp=FAST):
            """Väggar längs kanterna [(a, b, takfot)] från y_bot till takfoten (rak), plus en plåtkant ovanpå."""
            u_lopande = 0.0
            for a, b, fot in kantlista:
                d = b - a
                Lk = float(np.hypot(*d))
                ut_en = np.array([d[1], -d[0]]) / Lk   # moturs ytterring / medurs hål: utåt till höger
                ut = np.array([ut_en[0], 0.0, -ut_en[1]])
                ua, ub = u_lopande / TB, (u_lopande + Lk) / TB
                xa, za = self.to_world(*a)
                xb, zb = self.to_world(*b)
                ref_y = y_skarv if y_skarv is not None else y_bot
                for yb, yt, mat_ in mat_fn(y_bot, fot) + [(fot, fot + 0.35, kantmat)]:
                    if yt <= yb + 0.01:
                        continue
                    V = [(xa, yb, za), (xb, yb, zb), (xb, yt, zb), (xa, yt, za)]
                    v0, v1 = (yb - ref_y) / TH, (yt - ref_y) / TH
                    self._quad(grupp, V, [[ua, v0], [ub, v0], [ub, v1], [ua, v1]], mat_, ut)
                u_lopande += Lk

        def tak_yta(poly, kantlista, inre_fn, material):
            """Delaunay över kantpunkterna (var 1 m, på sin kants takfot) och ett 1,5 m-rutnät inuti
            (inre_fn, aldrig under närmaste takfot), trianglar inne i formen."""
            from shapely.geometry import LineString
            pts, ys = [], []
            linjer = [(LineString([a, b]), fot) for a, b, fot in kantlista]
            for a, b, fot in kantlista:
                Lk = float(np.hypot(*(b - a)))
                for t in np.arange(0, Lk, 1.0):
                    pts.append(tuple(a + (b - a) * t / Lk))
                    ys.append(fot)
            x0_, y0_, x1_, y1_ = poly.bounds
            inre = poly.buffer(-0.7)
            for E in np.arange(x0_, x1_, 1.5):
                for N in np.arange(y0_, y1_, 1.5):
                    q = Point(E, N)
                    if inre.contains(q):
                        narmast = min(linjer, key=lambda lf: lf[0].distance(q))[1]
                        pts.append((E, N))
                        ys.append(max(inre_fn(E, N), narmast))
            pts = np.array(pts)
            tri = Delaunay(pts)
            F = [t for t in tri.simplices if poly.buffer(0.05).contains(Point(pts[t].mean(0)))]
            if not F:
                return
            x, z = self.to_world(pts[:, 0], pts[:, 1])
            msh = trimesh.Trimesh(np.column_stack([x, np.array(ys), z]), np.array(F), process=False)
            ned = msh.face_normals[:, 1] < 0
            msh.faces[ned] = msh.faces[ned][:, ::-1]
            v = msh.vertices[msh.faces].reshape(-1, 3)
            ox, oz = self.to_world(0.0, 0.0)
            uv = np.column_stack([(v[:, 0] - ox) / 4.8, (oz - v[:, 2]) / 4.8])   # plåtens falsar i världen
            self.add(FAST, trimesh.Trimesh(v, np.arange(len(v)).reshape(-1, 3), process=False), material, uv)

        def band(y0, y1):
            if y_skarv is None or y1 <= y_skarv:
                return [(y0, y1, nedre)]
            return [(y0, y_skarv, nedre), (y_skarv, y1, ovre)]
        n_topp = 0
        for poly in polys:
            poly = orient(poly, 1.0)   # ytterring moturs, hål medurs
            y_mark = min(self._mark(E, N) for E, N in poly.exterior.coords) - 0.3
            mark_mitt = self._mark(poly.centroid.x, poly.centroid.y)

            def h_tak(E, N, ras=utj_huvud):
                c, r = ~T1 * (E, N)
                return mark_mitt + float(ndi.map_coordinates(ras, [[r - 0.5], [c - 0.5]], order=1, mode='nearest')[0])
            # en rak takfot per vägg: laserns takkant längs väggen (median), till närmaste våningsgräns
            klista = []
            for a, b in kanter(poly):
                Lk = float(np.hypot(*(b - a)))
                ut_en = np.array([(b - a)[1], -(b - a)[0]]) / Lk
                prov = [h_tak(*(a + (b - a) * t - ut_en * 1.0)) for t in np.linspace(0.1, 0.9, max(2, int(Lk)))]
                klista.append((a, b, snappa(float(np.median(prov)), y_mark + vaning)))
            vaggar(klista, y_mark, band)
            tak_yta(poly, klista, lambda E, N: h_tak(E, N, utj_tak), takmat)
            # kommandobryggan: höga takpartier som egna volymer med glas runt om och plåttak
            if topp_min:
                hog = ndi.binary_opening((utj > topp_min) & karna, iterations=1)
                delar = [shape(g) for g, v in shapes(hog.astype(np.uint8), mask=hog, transform=T1) if v == 1]
                for del_ in getattr(unary_union(delar), 'geoms', [unary_union(delar)]) if delar else []:
                    del_ = del_.intersection(poly.buffer(-0.5)).simplify(o.get('topp_forenkla_m', 1.2))
                    for dp in getattr(del_, 'geoms', [del_]):
                        if dp.geom_type != 'Polygon' or dp.area < o.get('topp_min_yta_m2', 100):
                            continue
                        dp = orient(Polygon(dp.exterior), 1.0)   # utan hål
                        inne_d = rasterize([(dp, 1)], out_shape=utj.shape, transform=T1).astype(bool) & karna
                        hmax = o.get('huvudtak_max_m', topp_min - 0.6)
                        bas_y = snappa(mark_mitt + hmax)
                        topp_rel = float(np.percentile(hojd[inne_d], 90)) if inne_d.any() else hmax + vaning
                        topp_y = max(snappa(mark_mitt + topp_rel), bas_y + vaning)
                        bl = [(a, b, topp_y) for a, b in kanter(dp)]
                        vaggar(bl, bas_y - 1.0, lambda y0, y1: [(y0, y1, brygga_mat)])
                        tak_yta(dp, bl, lambda E, N, ty=topp_y: ty, takmat)
                        n_topp += 1
        print(f"friform: {o['namn']}: {len(polys)} del(ar), tak {utj[karna].min():.1f}-{utj[karna].max():.1f} m"
              + (f", kommandobrygga {n_topp} del(ar)" if topp_min else '')
              + (f", puts upp till {y_skarv:.1f} m ö.h." if y_skarv is not None else ''))

# ==================================================================== texturer och mallar
def _font(storlek):
    from PIL import ImageFont
    try:
        return ImageFont.truetype('DejaVuSans-Bold.ttf', storlek)
    except OSError:
        return ImageFont.load_default()


def _rutfasad():
    """Studenthusets fasad: röda kassetter 1,6 m med ett litet fyrkantigt fönster var, 16 x 16 m per bild."""
    px, n = 32, 512
    rng = np.random.default_rng(5)
    im = Image.new('RGB', (n, n), (150, 58, 42))
    d = ImageDraw.Draw(im)
    k = int(1.6 * px)
    for i in range(10):
        for j in range(10):
            x0, y0 = i * k, j * k
            g = rng.normal(0, 6)
            d.rectangle([x0 + 2, y0 + 2, x0 + k - 2, y0 + k - 2], fill=(int(184 + g), int(76 + g * 0.5), int(54 + g * 0.4)))
            d.line([x0 + 2, y0 + k - 3, x0 + k - 2, y0 + k - 3], fill=(130, 48, 34), width=3)   # skugga under
            d.line([x0 + 2, y0 + 2, x0 + k - 2, y0 + 2], fill=(206, 98, 72), width=2)
            w = int(0.42 * px)
            ox = int(rng.integers(6, k - w - 6))
            oy = int(rng.integers(6, k - w - 6))
            col = (236, 230, 206) if rng.random() < 0.12 else (int(rng.integers(30, 60)),) * 2 + (int(rng.integers(45, 70)),)
            d.rectangle([x0 + ox - 2, y0 + oy - 2, x0 + ox + w + 2, y0 + oy + w + 2], fill=(118, 42, 30))
            d.rectangle([x0 + ox, y0 + oy, x0 + ox + w, y0 + oy + w], fill=col)
    return im


def _plankor():
    """Trädäck: plankor 0,15 m, 4 x 4 m per bild."""
    px = 64
    n = 4 * px
    rng = np.random.default_rng(9)
    im = Image.new('RGB', (n, n), (90, 70, 52))
    d = ImageDraw.Draw(im)
    w = int(0.15 * px)
    for i in range(0, n, w):
        g = rng.normal(0, 10)
        d.rectangle([i + 1, 0, i + w - 2, n], fill=(int(150 + g), int(118 + g), int(84 + g * 0.8)))
        for _ in range(2):
            y = int(rng.integers(0, n))
            d.line([i + 1, y, i + w - 2, y], fill=(96, 74, 54), width=2)
    return im


def _textskylt(text, bak, fram, B, H):
    im = Image.new('RGB', (B, H), bak)
    d = ImageDraw.Draw(im)
    f = _font(int(H * 0.72))
    bb = d.textbbox((0, 0), text, font=f)
    d.text(((B - (bb[2] - bb[0])) / 2 - bb[0], (H - (bb[3] - bb[1])) / 2 - bb[1]), text, font=f, fill=fram)
    return im


def _perforerad(text, staende=True):
    """Grå perforerad skyltpelare med vit text (KEY, I-HUSET), stående text uppifrån och ned."""
    B, H = 256, 960
    im = Image.new('RGB', (B, H), (150, 156, 160))
    d = ImageDraw.Draw(im)
    rng = np.random.default_rng(len(text))
    for y in range(8, H - 8, 22):   # hålmönster
        for x in range(8, B - 8, 22):
            if rng.random() < 0.7:
                s = int(rng.integers(5, 12))
                d.rectangle([x, y, x + s, y + s], fill=(92, 96, 100))
    txt = Image.new('RGBA', (H, B), (0, 0, 0, 0))
    dt = ImageDraw.Draw(txt)
    f = _font(150)
    bb = dt.textbbox((0, 0), text, font=f)
    dt.text((60 - bb[0], (B - (bb[3] - bb[1])) / 2 - bb[1]), text, font=f, fill=(250, 250, 250, 255))
    txt = txt.rotate(-90, expand=True)
    im.paste(txt, (0, 0), txt)
    return im


def _pressbyran():
    B, H = 1000, 220
    im = Image.new('RGB', (B, H), (246, 206, 24))
    d = ImageDraw.Draw(im)
    f = _font(110)
    d.text((40, 45), 'Pressbyrån', font=f, fill=(24, 60, 140))
    cx, cy = B - 110, H // 2
    for r, col in ((80, (226, 92, 40)), (60, (246, 206, 24)), (42, (226, 92, 40)), (22, (246, 206, 24))):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    return im


def _lampgrupp(m):
    """Corsons lampgrupp: tre rödbruna U-stolpar, bågar med silverkupor, banderoll; x framåt, y upp, z höger."""
    rod = m('Corsonlampa_rod', (120, 44, 38), 0.6)
    silver = m('Corsonlampa_kupa', (196, 198, 200), 0.35)
    ljus = m('Corsonlampa_ljus', (244, 238, 214), 0.3)
    vit = m('Corsonlampa_banderoll', (232, 232, 226), 0.8)
    ring = m('Corsonlampa_ring', (150, 112, 104), 0.9)
    delar = []

    def till_lokalt(P):   # (r, u, f) -> (x = f, y = u, z = r)
        P = np.asarray(P, float)
        return P[:, [2, 1, 0]]

    def skal(P, material, platt=True):
        delar.append((_skal(till_lokalt(P), platt), material))

    def lampa(bas_r, bas_f, topp, ut_r, ut_f):
        """Stolpe med båge över toppen och kupa ute vid (ut_r, ut_f)."""
        skal(lada((bas_r, topp / 2, bas_f), (0.22, topp, 0.12)), rod)
        skal(cylinder((bas_r, -0.02, bas_f), (bas_r, 0.03, bas_f), 0.42, 0.42, 12), ring)
        dr, df = ut_r - bas_r, ut_f - bas_f
        lang = math.hypot(dr, df) or 1.0
        er, ef = dr / lang, df / lang
        R = lang / 2
        cr, cf, cu = bas_r + er * R, bas_f + ef * R, topp
        pts = [(cr - er * R * math.cos(math.pi * i / 8), cu + R * 1.3 * math.sin(math.pi * i / 8),
                cf - ef * R * math.cos(math.pi * i / 8)) for i in range(9)]
        for q0, q1 in zip(pts[:-1], pts[1:]):
            skal(cylinder(q0, q1, 0.025, 0.025, 6), rod, False)
        kr, kf, ku = pts[-1][0], pts[-1][2], topp - 0.05
        klocka = [(kr + rr * math.cos(a), ku - hh, kf + rr * math.sin(a))
                  for rr, hh in ((0.06, -0.02), (0.22, 0.12), (0.32, 0.32)) for a in np.linspace(0, 2 * math.pi, 14, endpoint=False)]
        skal(klocka, silver, False)
        skal(cylinder((kr, ku - 0.33, kf), (kr, ku - 0.31, kf), 0.29, 0.29, 14), ljus)

    lampa(-0.85, 0.0, 4.2, -1.45, 0.0)
    lampa(0.85, 0.0, 4.2, 1.45, 0.0)
    lampa(0.0, -0.35, 5.0, 0.0, 0.25)
    lampa(0.0, 0.45, 3.6, 0.0, 1.0)
    skal(lada_mellan(-0.75, -0.08, 2.0, 3.7, -0.03, 0.0), vit)   # banderoll mellan vänster och mitt
    return delar


def _ringfasad():
    """Ljus fasad med två fönsterband (vån. 1 och 2), 16 x 8 m per bild."""
    px = 32
    B, H = 16 * px, 8 * px
    im = Image.new('RGB', (B, H), (226, 226, 220))
    d = ImageDraw.Draw(im)
    for y0, y1 in ((1.0, 2.5), (4.3, 5.8)):
        top, bot = H - int(y1 * px), H - int(y0 * px)
        d.rectangle([0, top, B, bot], fill=(52, 66, 80))
        for x in range(0, B, int(1.6 * px)):
            d.rectangle([x, top, x + 3, bot], fill=(190, 192, 190))
    for x in range(0, B, int(3.2 * px)):   # skarvar mellan fasadskivorna
        d.line([x, 0, x, H], fill=(206, 206, 200), width=2)
    return im


def rasterio_affine_translation(c, r):
    import rasterio
    return rasterio.Affine.translation(c, r)


def _tegelband():
    """Rött tegel med ett mörkt fönsterband per våning (3,6 m), 8 x 7,2 m per bild."""
    px = 32
    B, H = int(8 * px), int(7.2 * px)
    rng = np.random.default_rng(13)
    im = Image.new('RGB', (B, H), (120, 112, 104))
    d = ImageDraw.Draw(im)
    sten_h, sten_b = int(0.075 * px) or 2, int(0.25 * px)
    for rad, y in enumerate(range(0, H, sten_h + 1)):
        x = -(rad % 2) * sten_b // 2
        while x < B:
            g = rng.normal(0, 7)
            d.rectangle([x, y, x + sten_b - 1, y + sten_h - 1], fill=(int(146 + g), int(66 + g * 0.6), int(50 + g * 0.5)))
            x += sten_b + 1
    for vaning in range(2):
        y0 = H - int((vaning * 3.6 + 1.0) * px)
        y1 = H - int((vaning * 3.6 + 2.7) * px)
        d.rectangle([0, y1, B, y0], fill=(46, 58, 70))
        for x in range(0, B, int(1.6 * px)):
            d.rectangle([x, y1, x + 3, y0], fill=(200, 200, 196))
        d.rectangle([0, y0, B, y0 + 4], fill=(196, 194, 188))   # fönsterbleck
    return im


def _fasad_puts(vaning):
    """Ljusgul/gräddvit puts med hålfönster, två våningar per bild (8,1 m bred)."""
    px = 32
    B, H = int(8.1 * px), int(2 * vaning * px)
    rng = np.random.default_rng(17)
    a = np.full((H, B, 3), (236, 226, 192), float) + rng.normal(0, 3, (H, B, 1))
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    for v in range(2):
        sill = H - int((v * vaning + 0.9) * px)
        top = H - int((v * vaning + 2.4) * px)
        for x0 in np.arange(0.45, 8.1, 2.7):
            xa, xb = int(x0 * px), int((x0 + 1.8) * px)
            d.rectangle([xa - 3, top - 3, xb + 3, sill + 3], fill=(246, 244, 236))
            d.rectangle([xa, top, xb, sill], fill=(52, 64, 76))
            d.line([(xa + xb) // 2, top, (xa + xb) // 2, sill], fill=(246, 244, 236), width=3)
    return im


def _fasad_panel(vaning):
    """Liggande panel i ljust blågrått med fönsterband per våning, två våningar per bild."""
    px = 32
    B, H = int(8.1 * px), int(2 * vaning * px)
    im = Image.new('RGB', (B, H), (176, 190, 202))
    d = ImageDraw.Draw(im)
    for y in range(0, H, int(0.25 * px)):
        d.line([0, y, B, y], fill=(156, 170, 184), width=1)
    for v in range(2):
        sill = H - int((v * vaning + 0.9) * px)
        top = H - int((v * vaning + 2.3) * px)
        d.rectangle([0, top, B, sill], fill=(46, 58, 70))
        for x in np.arange(0, 8.1, 1.35):
            d.rectangle([int(x * px), top, int(x * px) + 3, sill], fill=(206, 212, 216))
        d.rectangle([0, sill, B, sill + 3], fill=(214, 218, 222))
    return im


def _fasad_brygga(vaning):
    """Kommandobryggan: glas runt om med smala poster och en panelkant upptill."""
    px = 32
    B, H = int(8.1 * px), int(2 * vaning * px)
    im = Image.new('RGB', (B, H), (176, 190, 202))
    d = ImageDraw.Draw(im)
    for v in range(2):
        y_b = H - int((v * vaning + 0.5) * px)
        y_t = H - int((v * vaning + 2.8) * px)
        d.rectangle([0, y_t, B, y_b], fill=(58, 80, 98))
        for x in np.arange(0, 8.1, 0.9):
            d.rectangle([int(x * px), y_t, int(x * px) + 2, y_b], fill=(214, 218, 222))
    return im


def _plattak():
    """Falsat plåttak, ljust grått, falsar var 0,6 m (4,8 m per bild)."""
    px = 50
    n = int(4.8 * px)
    im = Image.new('RGB', (n, n), (184, 188, 190))
    d = ImageDraw.Draw(im)
    for k in range(8):
        x = int(k * 0.6 * px)
        d.line([x, 0, x, n], fill=(214, 218, 220), width=2)
        d.line([x + 3, 0, x + 3, n], fill=(150, 154, 158), width=1)
    return im


_FASADER = {'puts': _fasad_puts, 'panel': _fasad_panel, 'brygga': _fasad_brygga,
            'tegel': lambda vaning: _tegelband()}
