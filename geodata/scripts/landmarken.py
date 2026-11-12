"""Landmärken (step3): OSM-byggnader som byggs efter sina building:part-delar (geodata/landmarken.json).

Byggnaden (väg-id i filen) byggs inte som vanligt hus. Varje building:part inom den blir en egen kropp
med OSM-höjden (`height`, annars våningar × 3,2 m; lutande tak räknas till halva takhöjden), väggfärg
ur `building:colour` och tak ur `roof:colour` / `roof:material` (gräs, glas). Delen `torn` blir ett
glastorn: höjden × `hojd_faktor`, vidgas uppåt från `v_botten` × takets storlek vid marken (skalat mot
mitten, som ett V), glasband med mörka bröstningsband per våning (`vaning_m`), en takkant och ett mörkt
tak. Allt i glb-gruppen `Byggnader_landmarken` (spelet ger den kollision).
"""
import json
from pathlib import Path

import numpy as np
import shapely
import trimesh
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

ROOT = Path(__file__).resolve().parent.parent


def _srgb2lin(c):
    c = np.asarray(c, float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _farg(s, standard):
    if not s:
        return standard
    s = s.strip()
    if s.startswith('#') and len(s) == 7:
        return tuple(int(s[i:i + 2], 16) for i in (1, 3, 5))
    namn = {'white': (235, 235, 230), 'black': (40, 40, 42), 'grey': (140, 140, 140), 'gray': (140, 140, 140),
            'green': (80, 110, 70), 'red': (150, 60, 50), 'brown': (110, 80, 60)}
    return namn.get(s.lower(), standard)


def _pbr(namn, rgb, rough, metal=0.0):
    return trimesh.visual.material.PBRMaterial(name=namn, baseColorFactor=[*_srgb2lin(rgb), 1.0],
                                               roughnessFactor=rough, metallicFactor=metal)


def _hojd(t, standard=10.0):
    try:
        return float(str(t.get('height', '')).split()[0])
    except ValueError:
        pass
    try:
        return float(t.get('building:levels')) * 3.2
    except (TypeError, ValueError):
        return standard


class Landmarken:
    def __init__(self, feat, box):
        fil = ROOT / 'landmarken.json'
        conf = json.loads(fil.read_text()) if fil.exists() else {}
        self.conf = {k: v for k, v in conf.items() if not k.startswith('_')}
        self.lista = []   # (polygon, conf, [(delpolygon, taggar, id)])
        delar = feat.get('byggdelar', [])
        for gm, t in feat['buildings']:
            c = self.conf.get(str(t.get('_osm_id', '')))
            if c is None or not gm.intersects(box):
                continue
            inne = [(p, tt, i) for p, tt, i in delar if gm.buffer(1.0).contains(p.representative_point())]
            self.lista.append((gm, c, inne))
            print(f"landmärke: {c.get('namn', t.get('name'))}, {len(inne)} delar")

    def ar(self, t):
        return str(t.get('_osm_id', '')) in self.conf

    def bygg(self, sample, h, to_world, add_merged):
        for gm, c, delar in self.lista:
            ring = np.array(gm.exterior.coords)
            bas = float(np.min(sample(h, ring[:, 0], ring[:, 1])))
            if not delar:   # inga delar: hela huset som torn
                delar = [(gm, {}, c.get('torn'))]
            for p, t, i in delar:
                p = max(getattr(p, 'geoms', [p]), key=lambda q: q.area)
                if str(i) == str(c.get('torn')):
                    self._torn(p, t, c, bas, to_world, add_merged)
                else:
                    self._block(p, t, bas, to_world, add_merged)

    # ------------------------------------------------------------------ geometri
    @staticmethod
    def _ringar_till_mesh(ringar, ys, to_world, mittpunkt, tak=None):
        """Sidor mellan ringar (samma antal hörn, moturs i E/N) på höjderna ys, utåtriktade."""
        V, F = [], []
        n = len(ringar[0])
        for r, y in zip(ringar, ys):
            for e, nn in r:
                x, z = to_world(e, nn)
                V.append([x, y, z])
        for k in range(len(ringar) - 1):
            a0 = k * n
            for j in range(n):
                j1 = (j + 1) % n
                p, q, pu, qu = a0 + j, a0 + j1, a0 + n + j, a0 + n + j1
                F += [[p, q, qu], [p, qu, pu]]
        V = np.array(V, float)
        F = np.array(F)
        # vänd varje triangel så att normalen pekar ut från kanten (moturs ring i E/N = utåt till höger)
        for f in range(len(F)):
            a, b, c_ = V[F[f]]
            nrm = np.cross(b - a, c_ - a)
            j = (f // 2) % n
            r = ringar[0]
            de, dn = r[(j + 1) % n][0] - r[j][0], r[(j + 1) % n][1] - r[j][1]
            ut = np.array([dn, 0.0, de])   # utåt i E/N är (dn, -de); i Godot (x = E, z = -N): (dn, de)
            if np.dot(nrm, ut) < 0:
                F[f] = F[f][::-1]
        return V, F

    @staticmethod
    def _lock(poly2d, y, to_world, upp=True):
        tri = shapely.constrained_delaunay_triangles(poly2d)
        V, F = [], []
        for t in getattr(tri, 'geoms', []):
            pts = list(t.exterior.coords)[:3]
            k = len(V)
            for e, nn in pts:
                x, z = to_world(e, nn)
                V.append([x, y, z])
            a, b, c_ = (np.array(V[k + i]) for i in range(3))
            if (np.cross(b - a, c_ - a)[1] > 0) != upp:
                F.append([k, k + 2, k + 1])
            else:
                F.append([k, k + 1, k + 2])
        return np.array(V, float), np.array(F)

    @staticmethod
    def _lagg(add_merged, V, F, mat):
        if len(F):
            add_merged('Byggnader_landmarken', trimesh.Trimesh(V, F, process=False), mat)

    def _block(self, p, t, bas, to_world, add_merged):
        p = orient(p.simplify(0.2), 1.0)
        H = _hojd(t, 6.0)
        try:
            H -= float(t.get('roof:height', 0)) / 2 if t.get('roof:shape') not in (None, 'flat') else 0.0
        except ValueError:
            pass
        ring = list(p.exterior.coords)[:-1]
        vagg = _farg(t.get('building:colour'), (70, 76, 80))
        glas = t.get('building:material') == 'glass'
        mv = _pbr('Landmarke_vagg_%02x%02x%02x' % vagg, vagg, 0.15 if glas else 0.7, 0.6 if glas else 0.0)
        V, F = self._ringar_till_mesh([ring, ring], [bas - 0.5, bas + H], to_world, None)
        self._lagg(add_merged, V, F, mv)
        rm = t.get('roof:material')
        tak = (85, 110, 70) if rm == 'grass' else _farg(t.get('roof:colour'), vagg)
        mt = _pbr('Landmarke_tak_%02x%02x%02x' % tak, tak, 0.15 if rm == 'glass' else 0.85, 0.6 if rm == 'glass' else 0.0)
        V, F = self._lock(p, bas + H, to_world)
        self._lagg(add_merged, V, F, mt)

    def _torn(self, p, t, c, bas, to_world, add_merged):
        p = orient(p.simplify(0.3), 1.0)
        H = _hojd(t, 40.0) * float(c.get('hojd_faktor', 1.0))
        s0 = float(c.get('v_botten', 1.0))
        vh = float(c.get('vaning_m', 3.6))
        mid = np.array(p.centroid.coords[0])
        ring = np.array(list(p.exterior.coords)[:-1])

        def skala(y):   # linjärt från s0 vid marken till 1 vid taket
            return s0 + (1 - s0) * min(max(y / H, 0.0), 1.0)

        def ring_vid(y):
            return [tuple(mid + (q - mid) * skala(y)) for q in ring]

        glasfarg = tuple(c.get('glas', (52, 68, 84)))
        m_glas = _pbr('Landmarke_glas', glasfarg, 0.06, 0.85)
        m_band = _pbr('Landmarke_band', tuple(c.get('profil', (128, 134, 140))), 0.4, 0.5)
        m_tak = _pbr('Landmarke_taket', (55, 58, 62), 0.8)
        # våningar: bröstningsband 0,8 m + glas resten; bottenvåningen helt glas
        y = 0.0
        while y < H - 0.01:
            y1 = min(y + vh, H)
            if y > 0.0:
                yb = min(y + 0.8, y1)
                V, F = self._ringar_till_mesh([ring_vid(y), ring_vid(yb)], [bas + y, bas + yb], to_world, mid)
                self._lagg(add_merged, V, F, m_band)
                y = yb
            V, F = self._ringar_till_mesh([ring_vid(y), ring_vid(y1)], [bas + y, bas + y1], to_world, mid)
            self._lagg(add_merged, V, F, m_glas)
            y = y1
        # under marken (sluttning) och takkanten
        V, F = self._ringar_till_mesh([ring_vid(0), ring_vid(0)], [bas - 1.0, bas], to_world, mid)
        self._lagg(add_merged, V, F, m_band)
        V, F = self._ringar_till_mesh([ring_vid(H), ring_vid(H)], [bas + H, bas + H + 1.2], to_world, mid)
        self._lagg(add_merged, V, F, m_band)
        self._profiler(ring, mid, skala, H, bas, float(c.get('profil_m', 1.6)), to_world, add_merged, m_band)
        topp = Polygon(ring_vid(H))
        V, F = self._lock(topp, bas + H + 0.6, to_world)
        self._lagg(add_merged, V, F, m_tak)
        print(f"  torn {H:.1f} m, {s0:.0%} vid marken")

    @staticmethod
    def _profiler(ring, mid, skala, H, bas, avst, to_world, add_merged, mat):
        """Lodräta fönsterprofiler var `avst` m längs fasaden (vid taket), 12 cm breda, 4 cm utanför."""
        V, F = [], []
        n = len(ring)
        for j in range(n):
            a, b = ring[j], ring[(j + 1) % n]
            L = float(np.hypot(*(b - a)))
            if L < 0.5:
                continue
            u = (b - a) / L
            ut = np.array([u[1], -u[0]])   # moturs ring: utåt till höger
            for k in range(max(1, int(L / avst))):
                q = a + u * (k * L / max(1, int(L / avst)))
                for y, s in ((0.0, skala(0.0)), (H, skala(H))):
                    m = mid + (q - mid) * s + ut * 0.04
                    for w in (-0.06, 0.06):
                        x, z = to_world(*(m + u * w * s))
                        V.append([x, bas + y, z])
                i = len(V) - 4   # botten -w, botten +w, topp -w, topp +w
                F += [[i, i + 1, i + 3], [i, i + 3, i + 2]]
        if not F:
            return
        V = np.array(V, float); F = np.array(F)
        for f in range(len(F)):   # utåt: samma regel som fasaden
            a_, b_, c_ = V[F[f]]
            nrm = np.cross(b_ - a_, c_ - a_)
            i0 = F[f][0] - F[f][0] % 4
            mitt = V[i0:i0 + 4].mean(0)
            cx, cz = to_world(*mid)
            if np.dot(nrm[[0, 2]], mitt[[0, 2]] - np.array([cx, cz])) < 0:
                F[f] = F[f][::-1]
        add_merged('Byggnader_landmarken', trimesh.Trimesh(V, F, process=False), mat)
