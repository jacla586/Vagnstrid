"""Bygger väggar och tak för en husdel utifrån en takform (takform.Tak) och en fasad.

Koordinater: delens lokala (u, v) i SWEREF görs om till Godot-världen med to_world(E, N),
höjden (y) är mark_ref + höjd över mark. Väggarna går ner till `bas` (under marken, så att
huset inte svävar i sluttningar).

Fasad: varje vägg är en polygon i (s längs väggen, h höjd) som delas i fack (cirka
husstil.FACK_M breda, jämnt fördelade) och våningar räknade från marken. Fack på våningarna
får atlasrutan 'fack' (fönster), mittfacket i bottenvåningen på dörrväggen 'dorr', och resten
(sockel, gavelspetsar, sneda överkanter) 'slat'. UV pekar in i rutan; varje ruta motsvarar ett
fack × en våning, så texturen får rätt skala.
"""
import math
import numpy as np
from shapely.geometry import Polygon, box as sbox

UTSPRANG = 0.35        # m, takutsprång för lutande tak
KNUT_BREDD = 0.14      # m
KNUT_UTSTICK = 0.03    # m utanför väggen (undviker z-fighting)
SKORSTEN_SIDA = 0.55   # m
SKORSTEN_OVER = 0.9    # m över nocken
MIN_VANING = 1.8       # m; lägre väggar får inga fönster
SOCKEL_H = 0.35        # m över markreferensen: grå sockel runt huset
SOCKEL_UT = 0.04       # m utanför väggen
TAKFOT_H = 0.2         # m hög takfotsbräda/vindskiva längs lutande taks kanter
KRON_H = 0.3           # m hög kant (krön) runt platta tak
KRON_B = 0.25          # m bred krönkant


class Bygge:
    def __init__(self, tak, to_world, mark_ref, bas):
        self.t = tak; self.to_world = to_world; self.ref = mark_ref; self.hb = bas - mark_ref
        self.V = []; self.UV = []; self.grupper = {}

    def _p(self, u, v, h, uv):
        e, n = self.t.mitt + u * self.t.u + v * self.t.v
        x, z = self.to_world(e, n)
        self.V.append([x, self.ref + h, z]); self.UV.append(uv)
        return len(self.V) - 1

    def yta(self, grupp, punkter, ctr=None, tak=False):
        """Konvex polygon som trianglar. punkter = [(u, v, h, (uu, vv))]."""
        unika = []
        for q in punkter:
            if not unika or any(abs(a - b) > 1e-6 for a, b in zip(q[:3], unika[-1][:3])):
                unika.append(q)
        if len(unika) > 2 and all(abs(a - b) < 1e-6 for a, b in zip(unika[0][:3], unika[-1][:3])):
            unika.pop()
        if len(unika) < 3:
            return
        idx = [self._p(*q) for q in unika]
        faces, _, _ = self.grupper.setdefault(grupp, ([], ctr, tak))
        for i in range(1, len(idx) - 1):
            faces.append([idx[0], idx[i], idx[i + 1]])

    # -- väggar
    def vagg(self, A, B, profil, fasad, dorr):
        """En vägg från A till B (lokala (u, v)). profil = [(s, h)] för överkanten från s=0 till s=L."""
        A = np.asarray(A, float); B = np.asarray(B, float)
        L = float(np.linalg.norm(B - A))
        if L < 0.05:
            return
        d = (B - A) / L
        poly = Polygon([(0.0, self.hb), (L, self.hb)] + [(s, h) for s, h in reversed(profil)])
        if not poly.is_valid or poly.area < 1e-4:
            return
        atlas, vid = fasad['atlas'], fasad['variant']
        n = max(1, int(round(L / fasad['fack_m'])))
        bw = L / n
        topp_min = min(h for _, h in profil)
        k = int(round(topp_min / fasad['vaning_m'])) if topp_min >= MIN_VANING else 0
        fh = topp_min / k if k else fasad['vaning_m']
        rader = []                                   # (h0 nominell, h1, typ, våning)
        h = 0.0
        while h > self.hb + 1e-6:
            rader.append((h - fh, h, 'slat', -1)); h -= fh
        for j in range(k):
            rader.append((j * fh, (j + 1) * fh, 'fack', j))
        h = k * fh; hmax = max(hh for _, hh in profil)
        while h < hmax - 1e-6:
            rader.append((h, h + fh, 'slat', -1)); h += fh
        for i in range(n):
            for h0, h1, typ, j in rader:
                bit = sbox(i * bw, max(h0, self.hb), (i + 1) * bw, h1).intersection(poly)
                if bit.is_empty or bit.area < 1e-4 or bit.geom_type != 'Polygon':
                    continue
                ruta = typ
                if typ == 'fack' and dorr and j == 0 and i == n // 2:
                    ruta = 'dorr'
                u0, v0, u1, v1 = atlas.uv(vid, ruta)
                pts = []
                for s, hh in list(bit.exterior.coords)[:-1]:
                    fx = min(max((s - i * bw) / bw, 0.0), 1.0); fy = min(max((hh - h0) / fh, 0.0), 1.0)
                    p = A + s * d
                    pts.append((p[0], p[1], hh, (u0 + fx * (u1 - u0), v0 + fy * (v1 - v0))))
                self.yta('vagg', pts)

    def knutar(self, horn, topp, fasad):
        """Vita hörnbrädor på båda väggarna vid varje hörn."""
        u0, v0, u1, v1 = fasad['atlas'].uv('knut', 'slat')
        mitt = np.mean(horn, axis=0)
        for i in range(4):
            A = np.asarray(horn[i], float); B = np.asarray(horn[(i + 1) % 4], float)
            d = (B - A) / max(np.linalg.norm(B - A), 1e-6)
            o = np.array([d[1], -d[0]])
            if np.dot(o, (A + B) / 2 - mitt) < 0:
                o = -o
            for P, riktning in ((A, d), (B, -d)):
                Q = P + riktning * KNUT_BREDD
                P2 = P + o * KNUT_UTSTICK; Q2 = Q + o * KNUT_UTSTICK
                hP, hQ = topp(*P), topp(*Q)
                self.yta('vagg', [(P2[0], P2[1], self.hb, (u0, v0)), (Q2[0], Q2[1], self.hb, (u1, v0)),
                                  (Q2[0], Q2[1], hQ, (u1, v1)), (P2[0], P2[1], hP, (u0, v1))])

    def sockel(self, horn, fasad):
        """Grått band från väggarnas fot upp till SOCKEL_H, strax utanför väggen."""
        u0, v0, u1, v1 = fasad['atlas'].uv('sockel', 'slat')
        mitt = np.mean(horn, axis=0)
        for i in range(4):
            A = np.asarray(horn[i], float); B = np.asarray(horn[(i + 1) % 4], float)
            d = (B - A) / max(np.linalg.norm(B - A), 1e-6)
            o = np.array([d[1], -d[0]])
            if np.dot(o, (A + B) / 2 - mitt) < 0:
                o = -o
            A2 = A + o * SOCKEL_UT - d * SOCKEL_UT; B2 = B + o * SOCKEL_UT + d * SOCKEL_UT
            self.yta('vagg', [(A2[0], A2[1], self.hb, (u0, v0)), (B2[0], B2[1], self.hb, (u1, v0)),
                              (B2[0], B2[1], SOCKEL_H, (u1, v1)), (A2[0], A2[1], SOCKEL_H, (u0, v1))])

    def list_(self, P, Q, fall, fasad, ruta='knut'):
        """En lodrät bräda från kanten P-Q (lokala (u, v, h)) ner `fall` m (takfotsbräda,
        vindskiva). Vänds utåt av step3 (bort från delens mitt)."""
        u0, v0, u1, v1 = fasad['atlas'].uv(ruta, 'slat')
        self.yta('vagg', [(P[0], P[1], P[2] - fall, (u0, v0)), (Q[0], Q[1], Q[2] - fall, (u1, v0)),
                          (Q[0], Q[1], Q[2], (u1, v1)), (P[0], P[1], P[2], (u0, v1))])

    def kron(self, horn, h, fasad):
        """Kant runt ett platt tak: utsida (fortsätter väggen) och ovansida."""
        u0, v0, u1, v1 = fasad['atlas'].uv('kron', 'slat')
        mitt = np.mean(horn, axis=0)
        for i in range(4):
            A = np.asarray(horn[i], float); B = np.asarray(horn[(i + 1) % 4], float)
            self.yta('vagg', [(A[0], A[1], h - 0.05, (u0, v0)), (B[0], B[1], h - 0.05, (u1, v0)),
                              (B[0], B[1], h + KRON_H, (u1, v1)), (A[0], A[1], h + KRON_H, (u0, v1))])
        # Ovansidan: en ram KRON_B bred innanför ytterkanten.
        for i in range(4):
            A = np.asarray(horn[i], float); B = np.asarray(horn[(i + 1) % 4], float)
            Ai = A + (mitt - A) / max(np.linalg.norm(mitt - A), 1e-6) * KRON_B * 1.41
            Bi = B + (mitt - B) / max(np.linalg.norm(mitt - B), 1e-6) * KRON_B * 1.41
            self.yta('kant_topp', [(A[0], A[1], h + KRON_H, (u0, v0)), (B[0], B[1], h + KRON_H, (u1, v0)),
                                   (Bi[0], Bi[1], h + KRON_H, (u1, v1)), (Ai[0], Ai[1], h + KRON_H, (u0, v1))],
                     tak=True)

    def skorsten(self, u, v, h0, h1, fasad):
        uv = fasad['atlas'].uv('skorsten_tegel', 'slat')
        s = SKORSTEN_SIDA / 2
        e, n = self.t.mitt + u * self.t.u + v * self.t.v
        ctr = self.to_world(e, n)
        hörn = [(u - s, v - s), (u + s, v - s), (u + s, v + s), (u - s, v + s)]
        for (a, b), (c, d) in zip(hörn, hörn[1:] + hörn[:1]):
            self.yta('skorsten', [(a, b, h0, (uv[0], uv[1])), (c, d, h0, (uv[2], uv[1])),
                                  (c, d, h1, (uv[2], uv[3])), (a, b, h1, (uv[0], uv[3]))], ctr=ctr)
        self.yta('skorsten_topp', [(a, b, h1, (uv[0], uv[1])) for a, b in hörn], tak=True)


def bygg_del(tak, to_world, mark_ref, bas, fasad):
    """Returnerar (V, UV, grupper) för en husdel. grupper = {namn: (trianglar, ctr eller None, tak?)}:
    'vagg' och 'skorsten' (fasadatlasen), 'tak' (takmaterialet), 'skorsten_topp' (fasadatlasen).
    fasad = dict(atlas, variant, vaning_m, fack_m, dorr, knutar, skorsten)."""
    g = Bygge(tak, to_world, mark_ref, bas)
    g.grupper['vagg'] = ([], None, False)
    g.grupper['kant_topp'] = ([], None, True)
    a, b = tak.halv_l, tak.halv_b
    e, t = tak.takfot, tak.topp
    o = UTSPRANG
    hörn = [(-a, -b), (a, -b), (a, b), (-a, b)]
    nul = (0.0, 0.0)

    if tak.modell == 'pulpet':
        du, dv = tak.fall
        langd = 2 * (a if du else b)
        topp = lambda u, v: t - ((u * du + v * dv) + langd / 2) / langd * (t - e)
    elif tak.modell == 'platt':
        topp = lambda u, v: t
    else:
        topp = lambda u, v: e

    gavel = set()
    if tak.modell == 'sadel':
        gavel = {1, 3} if tak.nock_langs_u else {0, 2}
    for i in range(4):
        A, B = hörn[i], hörn[(i + 1) % 4]
        L = math.dist(A, B)
        if i in gavel:
            profil = [(0.0, e), (L / 2, t), (L, e)]
        else:
            profil = [(0.0, topp(*A)), (L, topp(*B))]
        g.vagg(A, B, profil, fasad, dorr=fasad.get('dorr') and i == 0)
    if fasad.get('knutar'):
        g.knutar(hörn, topp, fasad)
    g.sockel(hörn, fasad)

    if tak.modell in ('platt', 'pulpet'):
        g.yta('tak', [(u, v, topp(u, v), nul) for u, v in hörn], tak=True)
        if tak.modell == 'platt' and t >= 3.0:
            g.kron(hörn, t, fasad)
    elif tak.modell == 'sadel':
        if tak.nock_langs_u:
            P = lambda r, c, hh: (r, c, hh, nul); R, C = a, b
        else:
            P = lambda r, c, hh: (c, r, hh, nul); R, C = b, a
        k = (t - e) / C
        el = e - o * k
        for s in (-1, 1):
            g.yta('tak', [P(-R - o, 0, t), P(R + o, 0, t), P(R + o, s * (C + o), el), P(-R - o, s * (C + o), el)], tak=True)
            # Takfotsbräda längs takfoten och vindskivor längs gavlarnas takkanter.
            g.list_(P(-R - o, s * (C + o), el)[:3], P(R + o, s * (C + o), el)[:3], TAKFOT_H, fasad)
            for r in (-1, 1):
                g.list_(P(r * (R + o), 0, t)[:3], P(r * (R + o), s * (C + o), el)[:3], TAKFOT_H, fasad)
        if fasad.get('skorsten'):
            r0 = 0.35 * R
            g.skorsten(*((r0, 0.0) if tak.nock_langs_u else (0.0, r0)), t - 1.2, t + SKORSTEN_OVER, fasad)
    else:                               # valmat / tält
        k = (t - e) / b
        r = max(a - b, 0.0)
        el = e - o * k
        A_, B_ = a + o, b + o
        g.yta('tak', [(-A_, -B_, el, nul), (A_, -B_, el, nul), (r, 0, t, nul), (-r, 0, t, nul)], tak=True)
        g.yta('tak', [(A_, B_, el, nul), (-A_, B_, el, nul), (-r, 0, t, nul), (r, 0, t, nul)], tak=True)
        g.yta('tak', [(A_, -B_, el, nul), (A_, B_, el, nul), (r, 0, t, nul)], tak=True)
        g.yta('tak', [(-A_, B_, el, nul), (-A_, -B_, el, nul), (-r, 0, t, nul)], tak=True)
        # Takfotsbrädor runt hela takfoten.
        kant = [(-A_, -B_), (A_, -B_), (A_, B_), (-A_, B_)]
        for i in range(4):
            (pu, pv), (qu, qv) = kant[i], kant[(i + 1) % 4]
            g.list_((pu, pv, el), (qu, qv, el), TAKFOT_H, fasad)
        if fasad.get('skorsten'):
            g.skorsten(r * 0.5, 0.0, t - 1.2 - k * 0.3, t + SKORSTEN_OVER, fasad)
    return np.array(g.V, float), np.array(g.UV, float), g.grupper


def plan_uv(V, faces):
    """UV i meter per hörn. Väggar: längs väggen och uppåt. Tak: längs takfoten och längs
    fallet (så att takpannornas rader följer takfoten). Platta ytor: (x, z)."""
    uv = np.zeros((len(V), 2))
    for f in faces:
        a, b, c = V[f[0]], V[f[1]], V[f[2]]
        n = np.cross(b - a, c - a)
        n /= max(np.linalg.norm(n), 1e-9)
        if abs(n[1]) > 0.999:
            for i in f:
                uv[i] = [V[i][0], V[i][2]]
            continue
        t = np.array([-n[2], 0.0, n[0]]); t /= max(np.linalg.norm(t), 1e-9)
        if abs(n[1]) < 0.5:                       # vägg
            for i in f:
                uv[i] = [V[i] @ t, V[i][1]]
        else:                                     # lutande tak: längs takfoten och längs fallet
            fall = np.cross(n, t); fall /= max(np.linalg.norm(fall), 1e-9)
            for i in f:
                uv[i] = [V[i] @ t, V[i] @ fall]
    return uv
