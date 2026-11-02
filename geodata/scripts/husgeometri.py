"""Bygger väggar och tak för en husdel utifrån en takform (takform.Tak).

Koordinater: delens lokala (u, v) i SWEREF görs om till Godot-världen med to_world(E, N),
höjden (y) är mark_ref + höjd över mark. Väggarna går ner till `bas` (under marken, så att
huset inte svävar i sluttningar). Varje yta får egna hörn så att UV kan sättas per yta.
"""
import numpy as np

UTSPRANG = 0.35   # m, takutsprång för lutande tak


class Bygge:
    def __init__(self, tak, to_world, mark_ref, bas):
        self.t = tak; self.to_world = to_world; self.ref = mark_ref; self.bas = bas
        self.V = []; self.vagg = []; self.tak = []

    def p(self, u, v, h):
        """Punkt i delens lokala koordinater (u, v) och höjd över mark -> världen."""
        e, n = self.t.mitt + u * self.t.u + v * self.t.v
        x, z = self.to_world(e, n)
        self.V.append([x, self.ref + h if h is not None else self.bas, z])
        return len(self.V) - 1

    def yta(self, lista, punkter):
        """Polygon (konvex, i ordning) som trianglar; punkter = [(u, v, h)], h None = bas."""
        def samma(p, q):             # None (bas) är bara lika med None
            return all((x is None and y is None) or (x is not None and y is not None and abs(x - y) < 1e-6)
                       for x, y in zip(p, q))
        unika = []
        for q in punkter:            # ett tält ger sammanfallande hörn; hoppa över dem
            if not unika or not samma(q, unika[-1]):
                unika.append(q)
        if len(unika) > 2 and samma(unika[0], unika[-1]):
            unika.pop()
        if len(unika) < 3:
            return
        idx = [self.p(*q) for q in unika]
        for i in range(1, len(idx) - 1):
            lista.append([idx[0], idx[i], idx[i + 1]])

    def vaggar(self, topphojd):
        """Fyra väggar från basen upp till topphojd(u, v) i hörnen."""
        a, b = self.t.halv_l, self.t.halv_b
        hörn = [(-a, -b), (a, -b), (a, b), (-a, b)]
        for (u0, v0), (u1, v1) in zip(hörn, hörn[1:] + hörn[:1]):
            self.yta(self.vagg, [(u0, v0, None), (u1, v1, None), (u1, v1, topphojd(u1, v1)), (u0, v0, topphojd(u0, v0))])


def bygg_del(tak, to_world, mark_ref, bas):
    """Returnerar (V, väggtrianglar, taktrianglar) för en husdel."""
    g = Bygge(tak, to_world, mark_ref, bas)
    a, b = tak.halv_l, tak.halv_b
    e, t = tak.takfot, tak.topp
    o = UTSPRANG
    if tak.modell == 'platt':
        g.vaggar(lambda u, v: t)
        g.yta(g.tak, [(-a, -b, t), (a, -b, t), (a, b, t), (-a, b, t)])
    elif tak.modell == 'pulpet':
        du, dv = tak.fall           # taket sluttar NERÅT åt (du, dv)
        langd = 2 * (a if du else b)
        def h(u, v):                # högst på uppsidan, takfot på nedsidan
            s = (u * du + v * dv)   # -langd/2 (uppe) .. +langd/2 (nere)
            return t - (s + langd / 2) / langd * (t - e)
        g.vaggar(h)
        g.yta(g.tak, [(-a, -b, h(-a, -b)), (a, -b, h(a, -b)), (a, b, h(a, b)), (-a, b, h(-a, b))])
    elif tak.modell == 'sadel':
        # r = längs nocken, c = tvärs; byt roller om nocken går tvärs delen
        if tak.nock_langs_u:
            P = lambda r, c, hh: (r, c, hh); R, C = a, b
        else:
            P = lambda r, c, hh: (c, r, hh); R, C = b, a
        k = (t - e) / C
        g.vaggar(lambda u, v: e)
        for s in (-1, 1):           # gavlar
            g.yta(g.vagg, [P(s * R, -C, e), P(s * R, C, e), P(s * R, 0, t)])
        el = e - o * k              # takkanten med utsprång ligger lägre
        for s in (-1, 1):           # takfall
            g.yta(g.tak, [P(-R - o, 0, t), P(R + o, 0, t), P(R + o, s * (C + o), el), P(-R - o, s * (C + o), el)])
    else:                           # valmat / tält
        k = (t - e) / b
        g.vaggar(lambda u, v: e)
        r = max(a - b, 0.0)         # halva nocklängden
        el = e - o * k
        A, B = a + o, b + o
        g.yta(g.tak, [(-A, -B, el), (A, -B, el), (r, 0, t), (-r, 0, t)])
        g.yta(g.tak, [(A, B, el), (-A, B, el), (-r, 0, t), (r, 0, t)])
        g.yta(g.tak, [(A, -B, el), (A, B, el), (r, 0, t)])
        g.yta(g.tak, [(-A, B, el), (-A, -B, el), (-r, 0, t)])
    return np.array(g.V, float), g.vagg, g.tak


def plan_uv(V, faces):
    """UV i meter per hörn: väggar längs väggen och uppåt, tak och golv i planet (x, z)."""
    uv = np.zeros((len(V), 2))
    for f in faces:
        a, b, c = V[f[0]], V[f[1]], V[f[2]]
        n = np.cross(b - a, c - a)
        n /= max(np.linalg.norm(n), 1e-9)
        if abs(n[1]) < 0.5:                       # vägg: horisontell tangent längs väggen
            t = np.array([-n[2], 0.0, n[0]]); t /= max(np.linalg.norm(t), 1e-9)
            for i in f:
                uv[i] = [V[i] @ t, V[i][1]]
        else:                                     # tak: planprojektion
            for i in f:
                uv[i] = [V[i][0], V[i][2]]
    return uv
