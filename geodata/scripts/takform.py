"""Takformer ur laserdatan.

Ett husfotavtryck delas i rektanglar (ett L-hus blir två). För varje del anpassas enkla
takmodeller mot objekthöjdsrastret (band 1, höjd över mark i meter, se laserhus.Objekthojd)
med minsta kvadrat, och den som passar bäst väljs:

    platt   h = c
    pulpet  h = a + b·v   (eller längs u)
    sadel   h = nock − k·|v − v0|   (nock längs delen, u)  eller  nock − k·|u − u0|  (tvärs)
    valmat  h = nock − k·max(|v|, |u| − (L − B)/2)   (tält när delen är nästan kvadratisk)

u går längs delens långsida, v tvärs, med origo i mitten. Allt i SWEREF 99 TM.
"""
from dataclasses import dataclass
import math
import numpy as np
from rasterio.features import rasterize
from shapely.affinity import rotate
from shapely.geometry import Polygon, box

DEL_RES = 0.5            # m, rutnät för uppdelningen i rektanglar
DEL_TACKNING = 0.90      # sluta när så stor del av fotavtrycket är täckt
DEL_MAX = 4              # delar för vanliga hus
DEL_MAX_STORT = 24       # stora komplex (kammar, gårdar), t.ex. Galaxen på Campus Valla
DEL_STORT_YTA = 1500.0   # m², fotavtryck från vilket ett hus räknas som stort
DEL_MIN_YTA = 12.0       # m²
DEL_MIN_SIDA = 3.0       # m
KANT_INDRAG = 0.5        # m, laserceller närmare kanten än så används inte (blandar tak och mark)
MIN_CELLER = 8
# Minst så stor del av delens yta måste ha laserträffar på taket. Glesa träffar är ofta en kran,
# fåglar eller brus över ett hus som inte fanns (eller saknade data) när det skannades.
LASER_MIN_TACKNING = 0.2
MIN_HOJD = 1.5           # m, lägre celler är mark eller buskar, inte tak
TRIM = 0.8               # robust fel: RMS av de 80 % minsta residualerna
STRAFF_PER_PARAM = 0.03  # m, gör att enklare modeller vinner när felen är nästan lika
PLATT_MAX_GRADER = 8.0
LUTNING_MIN, LUTNING_MAX = 10.0, 55.0
TALT_KVOT = 1.15         # valmat tak på en nästan kvadratisk del kallas tält
# Rastret har luckor och träd över kanterna; lutande modeller vinner därför ofta på marginalen.
LUTANDE_MAX_FELKVOT = 0.7   # ett lutande tak måste ha högst så stor del av det platta takets fel
PULPET_MAX_FELKVOT = 0.8    # ett pulpettak måste ha högst så stor del av bästa sadel/valmat-felet
# Trappsteg: två nivåer bredvid varandra (t.ex. en hög och en låg huskropp). Delen delas där
# och varje halva tolkas för sig.
TRAPPA_MIN_SKILLNAD = 0.8   # m mellan nivåerna
TRAPPA_FELKVOT = 0.7        # trappsteget måste ha högst så stor del av den bästa hela modellens fel
MIN_TAKFOT = 2.0
# Ett lutande tak måste hålla sig inom laserhöjderna: nocken högst så här mycket över den högsta
# cellen (98:e percentilen) och takfoten högst så här mycket under den lägsta. Smala delar med
# celler nästan på en linje gav annars lutningar som extrapolerades till hundratals meter.
TAK_MARGINAL_UPP = 1.5
TAK_MARGINAL_NED = 3.0


@dataclass
class Tak:
    modell: str          # 'platt', 'pulpet', 'sadel', 'valmat', 'talt'
    mitt: np.ndarray     # delens mitt (E, N)
    u: np.ndarray        # enhetsvektor längs långsidan
    v: np.ndarray        # enhetsvektor tvärs
    halv_l: float        # halva längden längs u
    halv_b: float        # halva bredden längs v
    takfot: float        # m över mark (lägsta takkant)
    topp: float          # m över mark (nock, toppen eller platt takhöjd)
    nock_langs_u: bool = True    # sadel: nocken går längs u (annars längs v)
    fall: tuple = (0.0, 0.0)     # pulpet: riktning (du, dv) som taket sluttar NERÅT mot
    fel: float = 0.0


def dela_i_rektanglar(poly):
    """Delar ett fotavtryck i upp till DEL_MAX rektanglar längs husets huvudriktning.
    Stora hus (DEL_STORT_YTA) får upp till DEL_MAX_STORT delar, och det som blir över (flyglar
    i en annan riktning) delas sedan bit för bit i sin egen riktning.
    Returnerar en lista med shapely-polygoner (rektanglar i SWEREF)."""
    if poly.area < DEL_STORT_YTA:
        return _dela(poly, DEL_MAX, DEL_TACKNING) or [poly.minimum_rotated_rectangle]
    delar = _dela(poly, DEL_MAX_STORT, DEL_TACKNING)
    from shapely.ops import unary_union
    for _ in range(3):
        if len(delar) >= DEL_MAX_STORT:
            break
        rest = poly.difference(unary_union(delar)) if delar else poly
        # öppna upp tunna remsor (avrundning längs delarnas kanter)
        rest = rest.buffer(-DEL_MIN_SIDA / 2, join_style=2).buffer(DEL_MIN_SIDA / 2, join_style=2)
        bitar = sorted((b for b in getattr(rest, 'geoms', [rest]) if b.area >= DEL_MIN_YTA * 2),
                       key=lambda b: -b.area)
        if not bitar:
            break
        fler = []
        for b in bitar:
            plats = DEL_MAX_STORT - len(delar) - len(fler)
            if plats <= 0:
                break
            # rektanglarna klipps till fotavtrycket, så de aldrig går ut i en gård
            fler += [r for r in _dela(b, plats, DEL_TACKNING) if r.within(poly.buffer(0.3))]
        if not fler:
            break
        delar += fler
    return delar or [poly.minimum_rotated_rectangle]


def _dela(poly, max_delar, tackning):
    """Största rektanglarna i poly, längs den av två riktningar som täcker mest: minsta
    omslutande rektangelns eller den dominerande väggriktningen (_vaggriktning)."""
    rect = poly.minimum_rotated_rectangle
    c = np.array(rect.exterior.coords)[:4]
    e = c[1] - c[0]
    vinklar = [math.degrees(math.atan2(e[1], e[0]))]
    vagg = _vaggriktning(poly)
    if abs((vagg - vinklar[0] + 45.0) % 90.0 - 45.0) > 0.5:
        vinklar.append(vagg)
    return max((_dela_langs(poly, v, max_delar, tackning) for v in vinklar), key=lambda r: r[1])[0]


def _dela_langs(poly, vinkel, max_delar, tackning):
    """(rektanglar, täckta celler) längs vinkel (grader)."""
    origo = poly.centroid
    lokal = rotate(poly, -vinkel, origin=origo)
    minx, miny, maxx, maxy = lokal.bounds
    W = max(int(math.ceil((maxx - minx) / DEL_RES)), 1)
    H = max(int(math.ceil((maxy - miny) / DEL_RES)), 1)
    from rasterio.transform import from_origin
    T = from_origin(minx, maxy, DEL_RES, DEL_RES)
    m = rasterize([(lokal, 1)], out_shape=(H, W), transform=T, all_touched=False).astype(bool)
    total = m.sum()
    delar, tackt = [], 0
    min_celler = DEL_MIN_YTA / DEL_RES ** 2
    min_sida = int(DEL_MIN_SIDA / DEL_RES)
    while total and len(delar) < max_delar and tackt < tackning * total:
        r0, c0, h, w = _storsta_rektangel(m)
        if h * w < min_celler or min(h, w) < min_sida:
            break
        m[r0:r0 + h, c0:c0 + w] = False
        tackt += h * w
        x0 = minx + c0 * DEL_RES; y1 = maxy - r0 * DEL_RES
        delar.append(rotate(box(x0, y1 - h * DEL_RES, x0 + w * DEL_RES, y1), vinkel, origin=origo))
    return delar, tackt


def _vaggriktning(poly):
    """Husets huvudriktning (grader): den vinkel modulo 90° som flest meter vägg går längs
    (alla ringar, gårdar också). Bättre än minsta omslutande rektangel för hus med en sned flygel."""
    vinklar, langder = [], []
    for ring in [poly.exterior, *poly.interiors]:
        c = np.array(ring.coords)
        d = np.diff(c, axis=0)
        vinklar.append(np.degrees(np.arctan2(d[:, 1], d[:, 0])) % 90.0)
        langder.append(np.hypot(d[:, 0], d[:, 1]))
    v, w = np.concatenate(vinklar), np.concatenate(langder)
    # viktat histogram på en cirkel (modulo 90°), utjämnat ±2°
    hist = np.bincount(np.round(v).astype(int) % 90, weights=w, minlength=90)
    jamn = sum(np.roll(hist, k) for k in range(-2, 3))
    topp = int(np.argmax(jamn))
    # medelvinkel för väggarna nära toppen
    diff = (v - topp + 45.0) % 90.0 - 45.0
    nara = np.abs(diff) <= 3.0
    return float(topp + np.average(diff[nara], weights=w[nara])) if nara.any() else float(topp)


def _storsta_rektangel(m):
    """Största helt fyllda rektangel i en boolsk matris: (rad, kolumn, höjd, bredd)."""
    H, W = m.shape
    hojd = np.zeros(W, int)
    bast = (0, 0, 0, 0); bast_yta = 0
    for r in range(H):
        hojd = np.where(m[r], hojd + 1, 0)
        stack = []
        for c in range(W + 1):
            hc = hojd[c] if c < W else 0
            start = c
            while stack and stack[-1][1] >= hc:
                s, sh = stack.pop()
                yta = sh * (c - s)
                if yta > bast_yta:
                    bast_yta = yta; bast = (r - sh + 1, s, sh, c - s)
                start = s
            stack.append((start, hc))
    return bast


def ram(del_poly):
    """Mitt, u (längs långsidan), v och halva längder för en rektangel."""
    c = np.array(del_poly.exterior.coords)[:4]
    e0 = c[1] - c[0]; e1 = c[2] - c[1]
    l0, l1 = np.linalg.norm(e0), np.linalg.norm(e1)
    if l0 >= l1:
        u, v, L, B = e0 / l0, e1 / l1, l0, l1
    else:
        u, v, L, B = e1 / l1, e0 / l0, l1, l0
    return c.mean(0), u, v, L / 2, B / 2


def laserceller(del_poly, ok):
    """(u, v, h) för laserceller inne i delen, KANT_INDRAG innanför kanten."""
    mitt, u, v, a, b = ram(del_poly)
    minx, miny, maxx, maxy = del_poly.bounds
    import rasterio
    r0, c0 = rasterio.transform.rowcol(ok.T, minx, maxy)
    r1, c1 = rasterio.transform.rowcol(ok.T, maxx, miny)
    r0, c0 = max(r0, 0), max(c0, 0)
    r1, c1 = min(r1 + 1, ok.h.shape[0]), min(c1 + 1, ok.h.shape[1])
    if r1 <= r0 or c1 <= c0:
        return None
    rr, cc = np.mgrid[r0:r1, c0:c1]
    X = ok.T.c + (cc + 0.5) * ok.T.a
    Y = ok.T.f + (rr + 0.5) * ok.T.e
    d = np.c_[X.ravel() - mitt[0], Y.ravel() - mitt[1]]
    uu = d @ u; vv = d @ v
    hh = ok.h[r0:r1, c0:c1].ravel()
    har = ok.frac[r0:r1, c0:c1].ravel() != 255
    inne = (np.abs(uu) <= a - KANT_INDRAG) & (np.abs(vv) <= b - KANT_INDRAG) & har & (hh > MIN_HOJD)
    yta_inne = (np.abs(uu) <= a - KANT_INDRAG) & (np.abs(vv) <= b - KANT_INDRAG)
    if inne.sum() < max(MIN_CELLER, LASER_MIN_TACKNING * yta_inne.sum()):
        return None
    return uu[inne], vv[inne], hh[inne], (mitt, u, v, a, b)


def _anpassa(A, h):
    """Minsta kvadrat i två varv: andra varvet utan de sämsta 20 % (träd, skorstenar)."""
    p, *_ = np.linalg.lstsq(A, h, rcond=None)
    r = np.abs(A @ p - h)
    keep = r <= np.quantile(r, TRIM)
    if keep.sum() >= A.shape[1] + 2:
        p, *_ = np.linalg.lstsq(A[keep], h[keep], rcond=None)
    r = np.sort(np.abs(A @ p - h))
    return p, float(np.sqrt(np.mean(r[:max(int(len(r) * TRIM), 1)] ** 2)))


def tolka_delar(del_poly, ok, djup=0):
    """Som tolka(), men delar delen i två om laserhöjderna visar ett tydligt trappsteg
    (två nivåer). Returnerar en lista med Tak (tom om laserdata saknas)."""
    data = laserceller(del_poly, ok)
    if data is None:
        return []
    hel, hel_fel = _tolka_data(data)
    if djup > 0:
        return [hel]
    uu, vv, hh, (mitt, u, v, a, b) = data
    ett = np.ones_like(hh)
    bast = None
    for axel, koord, halv in (('u', uu, a), ('v', vv, b)):
        for x0 in np.arange(-halv + DEL_MIN_SIDA, halv - DEL_MIN_SIDA + 1e-6, 0.5):
            steg = (koord > x0).astype(float)
            if steg.sum() < MIN_CELLER or (1 - steg).sum() < MIN_CELLER:
                continue
            p, f = _anpassa(np.c_[ett, steg], hh)
            if abs(p[1]) >= TRAPPA_MIN_SKILLNAD and (bast is None or f < bast[0]):
                bast = (f, axel, x0)
    if bast is None or bast[0] > TRAPPA_FELKVOT * hel_fel:
        return [hel]
    _, axel, x0 = bast
    halvor = []
    for lo, hi in ((-a if axel == 'u' else -b, x0), (x0, a if axel == 'u' else b)):
        if axel == 'u':
            hörn = [(lo, -b), (hi, -b), (hi, b), (lo, b)]
        else:
            hörn = [(-a, lo), (a, lo), (a, hi), (-a, hi)]
        halvor.append(Polygon([tuple(mitt + du * u + dv * v) for du, dv in hörn]))
    ut = []
    for h_poly in halvor:
        ut += tolka_delar(h_poly, ok, djup + 1)
    return ut or [hel]


def tolka(del_poly, ok):
    """Anpassar takmodellerna mot laserhöjderna i en del. Returnerar Tak eller None."""
    data = laserceller(del_poly, ok)
    return _tolka_data(data)[0] if data is not None else None


def _tolka_data(data):
    """(Tak, robust fel) för laserceller från laserceller()."""
    uu, vv, hh, (mitt, u, v, a, b) = data
    ett = np.ones_like(hh)
    kandidater = []

    p, f = _anpassa(np.c_[ett], hh)
    platt_fel = f
    kandidater.append((f + STRAFF_PER_PARAM * 1, 'platt', dict(topp=p[0], fel=f)))

    for axel, koord in (('u', uu), ('v', vv)):
        p, f = _anpassa(np.c_[ett, koord], hh)
        k = abs(p[1])
        if math.degrees(math.atan(k)) >= PLATT_MAX_GRADER:
            halv = a if axel == 'u' else b
            fall = (-math.copysign(1, p[1]), 0.0) if axel == 'u' else (0.0, -math.copysign(1, p[1]))
            kandidater.append((f + STRAFF_PER_PARAM * 3, 'pulpet',
                               dict(topp=p[0] + k * halv, takfot=p[0] - k * halv, k=k, fall=fall, fel=f)))

    for langs_u, tvars, halv in ((True, vv, b), (False, uu, a)):
        bast = None
        for x0 in np.linspace(-0.2 * halv, 0.2 * halv, 9):
            p, f = _anpassa(np.c_[ett, -np.abs(tvars - x0)], hh)
            if bast is None or f < bast[1]:
                bast = (p, f)
        p, f = bast
        if p[1] > 0 and math.degrees(math.atan(p[1])) >= PLATT_MAX_GRADER:
            kandidater.append((f + STRAFF_PER_PARAM * 3, 'sadel',
                               dict(topp=p[0], takfot=p[0] - p[1] * halv, k=p[1], nock_langs_u=langs_u, fel=f)))

    d = np.maximum(np.abs(vv), np.abs(uu) - (a - b))
    p, f = _anpassa(np.c_[ett, -d], hh)
    if p[1] > 0 and math.degrees(math.atan(p[1])) >= PLATT_MAX_GRADER:
        kandidater.append((f + STRAFF_PER_PARAM * 2, 'talt' if a / b < TALT_KVOT else 'valmat',
                           dict(topp=p[0], takfot=p[0] - p[1] * b, k=p[1], fel=f)))

    h_hog, h_lag = float(np.quantile(hh, 0.98)), float(np.quantile(hh, 0.02))
    kandidater = [c for c in kandidater if c[1] == 'platt' or
                  (c[2]['topp'] <= h_hog + TAK_MARGINAL_UPP and c[2]['takfot'] >= h_lag - TAK_MARGINAL_NED)]
    poang, modell, prm = min(kandidater, key=lambda x: x[0])
    if modell == 'pulpet':
        andra = [c for c in kandidater if c[1] in ('sadel', 'valmat', 'talt')]
        if andra:
            bast_andra = min(andra, key=lambda x: x[0])
            if prm['fel'] > PULPET_MAX_FELKVOT * bast_andra[2]['fel']:
                poang, modell, prm = bast_andra
    if modell != 'platt' and prm['fel'] > LUTANDE_MAX_FELKVOT * platt_fel:
        poang, modell, prm = kandidater[0]
    if modell == 'platt':
        topp = float(max(prm['topp'], MIN_TAKFOT))
        return Tak('platt', mitt, u, v, a, b, topp, topp, fel=poang), prm['fel']
    k = math.tan(math.radians(np.clip(math.degrees(math.atan(prm['k'])), LUTNING_MIN, LUTNING_MAX)))
    topp = float(prm['topp'])
    if modell == 'pulpet':
        fall_langd = 2 * (a if prm['fall'][0] else b)      # hela delen i fallriktningen
    elif modell == 'sadel':
        fall_langd = b if prm['nock_langs_u'] else a       # från nocken ut till takfoten
    else:
        fall_langd = b                                      # valmat/tält: kortsidan styr
    takfot = topp - k * fall_langd
    if takfot < MIN_TAKFOT:         # för lågt: behåll lutningen, lyft taket
        topp += MIN_TAKFOT - takfot
        takfot = MIN_TAKFOT
    return Tak(modell, mitt, u, v, a, b, float(takfot), topp,
               nock_langs_u=prm.get('nock_langs_u', True), fall=prm.get('fall', (0.0, 0.0)), fel=poang), prm['fel']
