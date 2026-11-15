#!/usr/bin/env python3
"""
Fasadfärger ur Mapillarys gatubilder: <projekt>/data/husfarger.json (OSM-husets id -> färg), som step3
lägger som building:colour (husfarger.fasadfarger) när OSM saknar färg.

    export MLY_TOKEN='MLY|...'
    .venv/bin/python -I scripts/husfarger_mapillary.py <projekt> [--max-bilder-per-hus 6]

Så här:
1. Alla bilder i kartans ruta (perspektivkameror med beräknad rotation), listan sparas i
   <projekt>/data/mapillary/bilder.json.
2. Varje OSM-hus (minst MIN_YTA_M2) delas i väggar. En vägg kan synas i en bild om kameran står framför
   den (högst MAX_VINKEL grader snett), AVSTAND_M bort, utan annat hus emellan och med väggens mitt i
   bilden. Träd och bilar i vägen sorteras inte bort här (laserns kronor skymde för mycket): det gör
   omröstningen i steg 4.
3. Ett rutnät av punkter på väggen (PROV_U längs, PROV_V av höjden mellan 1,2 m och takfoten)
   projiceras i bilden med Mapillarys kamera (rotation: värld ENU -> kamera x höger, y ned, z framåt;
   brännvidd och radiell distorsion k1, k2, normerat mot bildens längsta sida) och samplas (fönster,
   skugga och grönska bort).
4. Bildernas lägen har några meters fel, så en del punkter hamnar på himmel, mark eller bilar. De
   hamnar olika i olika bilder; fasaden är det alla är överens om: den färg som har flest prov inom
   KLUSTER_AVSTAND, från minst MIN_BILDER bilder och minst KLUSTER_ANDEL av proven.
Bilderna (1024 px) cachas i <projekt>/data/mapillary/cache/. De följer aldrig med i spelet. `--rensa` tar
efteråt bort de bilder som inte bar någon husfärg (husfarger.json `bild_ids`), så att cachen bara håller det
en ombyggnad behöver.
Kontrollbild: forhandsbilder/husfarger_<projekt>.jpg (urklipp per hus och vald färg).
"""
import argparse, colorsys, json, math, pickle, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image, ImageDraw
from scipy.spatial import cKDTree
from scipy.spatial.transform import Rotation
from shapely import STRtree
from shapely.geometry import LineString, Polygon
from shapely.geometry.polygon import orient

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hamta_mapillary as mly   # noqa: E402
import husfarger   # noqa: E402

GEO = Path(__file__).resolve().parent.parent
MIN_YTA_M2 = 40.0
MIN_VAGG_M = 3.0
AVSTAND_M = (4.0, 30.0)
MAX_VINKEL = 70.0           # grader från väggens normal
PROV_U = (0.25, 0.4, 0.55, 0.7)
PROV_V = (0.3, 0.6)   # nedre delen av väggen: mindre himmel
PROV_FALT_M = 0.8           # samplat fält runt varje punkt (m på väggen)
KLUSTER_AVSTAND = 30.0      # RGB-avstånd inom vilket prov räknas som samma färg
KLUSTER_ANDEL = 0.35
MAX_BILDER_PER_HUS = 8
KAMERA_HOJD = (1.0, 3.0)    # computed_altitude begränsas hit (m över mark)
MIN_BILDER = 2              # ett hus behöver träffar i så här många bilder
FALT = ('id,computed_geometry,computed_rotation,camera_type,camera_parameters,width,height,'
        'captured_at,computed_altitude,thumb_1024_url,sequence')


def hamta_bilder(projekt, ruta):
    fil = GEO / projekt / 'data' / 'mapillary' / 'bilder.json'
    if fil.exists() and time.time() - fil.stat().st_mtime < 3 * 3600:   # bildlänkarna åldras
        return json.loads(fil.read_text())
    ut, sedda = [], set()

    def cell(c, djup=0):
        d = mly.hamta('images', fields=FALT, bbox=mly.bbox_wgs(*c), limit=mly.LIMIT).get('data', [])
        if len(d) >= mly.LIMIT and djup < 4:   # taket: dela rutan i fyra
            e0, n0, e1, n1 = c
            em, nm = (e0 + e1) / 2, (n0 + n1) / 2
            for q in ((e0, n0, em, nm), (em, n0, e1, nm), (e0, nm, em, n1), (em, nm, e1, n1)):
                cell(q, djup + 1)
            return
        for b in d:
            if b['id'] in sedda or b.get('camera_type') != 'perspective' or 'computed_rotation' not in b \
                    or 'computed_geometry' not in b or not b.get('camera_parameters'):
                continue
            sedda.add(b['id'])
            ut.append(b)
    alla = list(mly.celler(ruta))
    for i, c in enumerate(alla):
        cell(c)
        print(f'\r  bildlista: ruta {i + 1}/{len(alla)}, {len(ut)} bilder', end='', file=sys.stderr)
    print(file=sys.stderr)
    fil.parent.mkdir(parents=True, exist_ok=True)
    fil.write_text(json.dumps(ut))
    return ut


class Mark:
    """Markhöjd (m) och laserns objekthöjd (m över mark) per SWEREF-punkt."""

    def __init__(self, projekt):
        d = GEO / projekt / 'data'
        with rasterio.open(str(next(d.glob('markhojd_*.tif')))) as s:
            self.mh, self.mT = s.read(1).astype(np.float32), ~s.transform
        with rasterio.open(str(next(d.glob('objekthojd_*.tif')))) as s:
            self.oh, self.oT = s.read(1).astype(np.float32) / 10.0, ~s.transform

    @staticmethod
    def _las(a, Tinv, E, N):
        c, r = Tinv * (np.asarray(E, float), np.asarray(N, float))
        r = np.clip(np.asarray(r).astype(int), 0, a.shape[0] - 1)
        c = np.clip(np.asarray(c).astype(int), 0, a.shape[1] - 1)
        return a[r, c]

    def mark(self, E, N):
        return self._las(self.mh, self.mT, E, N)

    def objekt(self, E, N):
        return self._las(self.oh, self.oT, E, N)


def hus_lista(projekt, ruta):
    from laserhus import Objekthojd
    feat = pickle.load(open(GEO / projekt / 'work' / 'features.pkl', 'rb'))
    laser = Objekthojd(str(next((GEO / projekt / 'data').glob('objekthojd_*.tif'))))
    e0, n0, e1, n1 = ruta
    ut = []
    for gm, t in feat['buildings']:
        if gm.geom_type != 'Polygon' or gm.area < MIN_YTA_M2:
            continue
        c = gm.centroid
        oid = husfarger.nyckel(gm, t)
        if not (e0 <= c.x <= e1 and n0 <= c.y <= n1):
            continue
        hh = laser.heights_in(gm)
        takfot = hh[0] if hh else 3.0
        ut.append(dict(id=str(oid), poly=orient(gm.simplify(0.5), 1.0), takfot=takfot, taggar=t))
    return ut


def vaggar(hus):
    """[(mitt (E, N), utåtnormal, längd)] för husets väggar (moturs polygon: normalen åt höger)."""
    c = np.array(hus['poly'].exterior.coords)
    ut = []
    for a, b in zip(c[:-1], c[1:]):
        v = b - a
        L = float(np.hypot(*v))
        if L < MIN_VAGG_M:
            continue
        ut.append(((a + b) / 2, np.array([v[1], -v[0]]) / L, L))
    return ut


class Kamera:
    def __init__(self, b):
        lon, lat = b['computed_geometry']['coordinates']
        self.E, self.N = mly.TILL_SWEREF.transform(lon, lat)
        self.lon, self.lat = lon, lat
        self.R = Rotation.from_rotvec(b['computed_rotation']).as_matrix()
        self.f, self.k1, self.k2 = (list(b['camera_parameters']) + [0.0, 0.0])[:3]
        self.w, self.h = b['width'], b['height']
        self.hojd = float(np.clip(b.get('computed_altitude') or 2.0, *KAMERA_HOJD))
        self.id = b['id']

    def enu(self, E, N, z_rel):
        """SWEREF-punkt -> lokala ENU-meter från kameran (z relativt kamerans höjd)."""
        lon, lat = mly.TILL_WGS.transform(E, N)
        x = math.radians(lon - self.lon) * 6371000.0 * math.cos(math.radians(self.lat))
        y = math.radians(lat - self.lat) * 6371000.0
        return np.array([x, y, z_rel])

    def pixel(self, X, bredd):
        """ENU-punkt -> (x, y) i en bild `bredd` px bred, eller None (bakom kameran / utanför)."""
        c = self.R @ X
        if c[2] <= 0.5:
            return None
        xn, yn = c[0] / c[2], c[1] / c[2]
        r2 = xn * xn + yn * yn
        d = 1.0 + self.k1 * r2 + self.k2 * r2 * r2
        skala = bredd / self.w * max(self.w, self.h)
        px = self.f * d * xn * skala + bredd / 2
        hojd = bredd * self.h / self.w
        py = self.f * d * yn * skala + hojd / 2
        if not (0.04 * bredd < px < 0.96 * bredd and 0.04 * hojd < py < 0.96 * hojd):
            return None
        return px, py, self.f * skala / c[2]   # sista: px per meter på väggen


def fri_sikt(hus_trad, eget, C, P):
    """Ingen annan byggnad mellan kameran och väggpunkten."""
    v = P - C
    L = float(np.hypot(*v))
    linje = LineString([C, C + v * (L - 0.4) / L])
    return not any(i != eget and hus_trad.geometries[i].intersects(linje) for i in hus_trad.query(linje))


def hamta_bild(b, cache):
    fil = cache / f"{b['id']}.jpg"
    if fil.exists() and fil.stat().st_size > 0:
        return fil
    try:
        with urllib.request.urlopen(b['thumb_1024_url'], timeout=60) as r:
            fil.write_bytes(r.read())
        return fil
    except Exception as ex:   # noqa: BLE001  (enstaka bilder får falla bort)
        print(f'  bild {b["id"]}: {ex}', file=sys.stderr)
        return None


def sampla(a, px, py, ppm):
    """Färgen i fältet runt (px, py) i bilden `a` (array): medianen av pixlar som inte är fönster,
    skugga eller grönska; None om för få är kvar."""
    r = int(np.clip(ppm * PROV_FALT_M / 2, 2, 12))
    y0, x0 = int(py), int(px)
    b = a[max(0, y0 - r):y0 + r + 1, max(0, x0 - r):x0 + r + 1].reshape(-1, 3).astype(float)
    if len(b) < 9:
        return None
    mx, mn = b.max(1), b.min(1)
    s = (mx - mn) / np.maximum(mx, 1)
    gron = (b[:, 1] > b[:, 0] * 1.03) & (b[:, 1] > b[:, 2] * 1.03) & (s > 0.10)
    if gron.mean() > 0.2 or (mx < 60).mean() > 0.4:
        return None   # träd, häck eller djup skugga framför väggen
    ok = (mx > 45) & ~gron
    if py < a.shape[0] * 0.5:   # övre halvan: himmel (ljus och blåaktig eller grå) bort
        ok &= ~((mx > 150) & (b[:, 2] >= b[:, 0] - 4) & (s < 0.35))
    if ok.mean() < 0.5:
        return None
    return np.median(b[ok], 0)


# Fasadfamiljer: kalibrerad färg (sRGB, nära stilar.json:s varianter). Bilderna är ofta underexponerade
# och fasaden i skugga, så familjen tas ur nyans och mättnad, och ljusheten räknas mot bildens 95:e
# percentil (himmel, vita ytor).
FAMILJER = {'falu': (132, 40, 30), 'tegel': (150, 70, 52), 'gul': (226, 196, 120), 'gul_tegel': (206, 178, 120),
            'beige': (232, 222, 196), 'brun': (102, 74, 54), 'vit': (236, 233, 222), 'gra': (176, 182, 184),
            'mork': (90, 92, 94)}


def kanonisk(farg, rel):
    """(familj, kalibrerad färg) ur uppmätt färg och ljushet relativt bilden."""
    h, s_, v = colorsys.rgb_to_hsv(*(np.clip(farg, 0, 255) / 255.0))
    hg = h * 360
    if s_ >= 0.18 and (hg < 18 or hg > 335):
        fam = 'falu' if s_ > 0.5 else 'tegel'
    elif s_ >= 0.18 and hg < 34:
        fam = 'brun' if rel < 0.45 else ('tegel' if s_ > 0.45 else 'gul_tegel')
    elif s_ >= 0.15 and hg < 65:
        fam = 'gul' if s_ > 0.3 else ('gul_tegel' if rel < 0.55 else 'beige')
    elif rel > 0.55:
        fam = 'vit'
    elif rel > 0.32:
        fam = 'gra'
    else:
        fam = 'mork'
    return fam, FAMILJER[fam]


def kluster(prov):
    """Den färg flest prov är överens om: (färg, prov i klustret, bilder) eller None."""
    if not prov:
        return None
    F = np.array([c for c, _ in prov])
    B = np.array([b for _, b in prov])
    d = np.linalg.norm(F[:, None, :] - F[None, :, :], axis=2) < KLUSTER_AVSTAND
    # varje bild räknas högst en gång per prov (en bild med många träffar på en bil ska inte vinna)
    stod = [len(set(B[d[i]])) * 100 + d[i].sum() for i in range(len(F))]
    i = int(np.argmax(stod))
    m = d[i]
    bilder = set(B[m])
    if len(bilder) < MIN_BILDER or m.mean() < KLUSTER_ANDEL:
        return None
    return np.median(F[m], 0), int(m.sum()), sorted(bilder)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('projekt')
    ap.add_argument('--max-bilder-per-hus', type=int, default=MAX_BILDER_PER_HUS)
    ap.add_argument('--rensa', action='store_true',
                    help='ta bort cachade bilder som inte bar någon husfärg (bild_ids i husfarger.json)')
    args = ap.parse_args()
    mly.token()
    projekt = args.projekt
    ruta = mly.ruta_for(projekt)
    bilder = hamta_bilder(projekt, ruta)
    print(f'{len(bilder)} bilder med kamerageometri')
    kameror = [Kamera(b) for b in bilder]
    kd = cKDTree([[k.E, k.N] for k in kameror])
    hus = hus_lista(projekt, ruta)
    print(f'{len(hus)} hus')
    hus_trad = STRtree([h['poly'] for h in hus])
    mark = Mark(projekt)
    from shapely.geometry import Point
    inne = {i for i, k in enumerate(kameror)
            if any(hus_trad.geometries[j].contains(Point(k.E, k.N)) for j in hus_trad.query(Point(k.E, k.N)))}
    print(f'{len(inne)} bilder tagna inne i hus (används inte)')

    # 1. bästa (bild, vägg) per hus
    plan = {}
    for hi, h in enumerate(hus):
        kand = []
        for M, n, L in vaggar(h):
            z_mark = float(mark.mark([M[0]], [M[1]])[0])
            vagg = (M, n, L, z_mark, max(h['takfot'], 2.4))
            z_p = z_mark + float(np.clip(0.45 * h['takfot'], 1.6, 6.0))
            for ki in kd.query_ball_point(M, AVSTAND_M[1]):
                if ki in inne:
                    continue
                k = kameror[ki]
                C = np.array([k.E, k.N])
                d = C - M
                dist = float(np.hypot(*d))
                if dist < AVSTAND_M[0]:
                    continue
                cos = float(np.dot(d / dist, n))
                if cos < math.cos(math.radians(MAX_VINKEL)):
                    continue
                z_c = float(mark.mark([k.E], [k.N])[0]) + k.hojd
                p = k.pixel(k.enu(M[0], M[1], z_p - z_c), 1024)
                if p is None:
                    continue
                kand.append((cos * (1.0 - dist / 45.0), ki, vagg, z_c))
        kand.sort(key=lambda t: -t[0])
        valda, anv = [], set()
        for t in kand:
            if t[1] in anv:
                continue
            k = kameror[t[1]]
            if not fri_sikt(hus_trad, hi, np.array([k.E, k.N]), t[2][0]):
                continue
            anv.add(t[1])
            valda.append(t)
            if len(valda) >= args.max_bilder_per_hus:
                break
        if valda:
            plan[hi] = valda
        if hi % 50 == 0:
            print(f'\r  synlighet: hus {hi + 1}/{len(hus)}, {len(plan)} med bilder', end='', file=sys.stderr)
    print(file=sys.stderr)
    behov = sorted({t[1] for v in plan.values() for t in v})
    print(f'{len(plan)} hus syns i någon bild; {len(behov)} bilder behövs')

    # 2. hämta bilderna
    cache = GEO / projekt / 'data' / 'mapillary' / 'cache'
    cache.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(8) as ex:
        filer = dict(zip(behov, ex.map(lambda ki: hamta_bild(bilder[ki], cache), behov)))

    # 3. sampla ett rutnät på varje vägg i varje bild, 4. omröstning per hus
    resultat, urklipp = {}, []
    bildcache, ljus_ref = {}, {}
    for hi, valda in plan.items():
        prov, klipp = [], []
        for _, ki, (M, n, L, z_mark, takfot), z_c in valda:
            fil = filer.get(ki)
            if fil is None:
                continue
            if ki not in bildcache:
                try:
                    bildcache[ki] = np.asarray(Image.open(fil).convert('RGB'))
                except OSError:
                    continue
                if len(bildcache) > 400:
                    bildcache.pop(next(iter(bildcache)))
            a = bildcache[ki]
            if ki not in ljus_ref:
                ljus_ref[ki] = float(np.percentile(a[::4, ::4].mean(2), 95))
            if ljus_ref[ki] < 140:
                continue   # natt eller mörk bild
            k = kameror[ki]
            bredd = a.shape[1]
            t = np.array([-n[1], n[0]])   # längs väggen
            for u in PROV_U:
                P = M + t * (u - 0.5) * L
                for v in PROV_V:
                    z = z_mark + 1.2 + v * max(takfot - 1.5, 0.8)
                    p = k.pixel(k.enu(P[0], P[1], z - z_c), bredd)
                    if p is None or p[1] >= a.shape[0]:
                        continue
                    c = sampla(a, *p)
                    if c is not None and float(c.mean()) / ljus_ref[ki] > 0.18:
                        prov.append((c, k.id, float(c.mean()) / ljus_ref[ki]))
                        klipp.append((ki, p))
        res = kluster([(c, b) for c, b, _ in prov])
        if res is None:
            continue
        farg, n_k, bilder_k = res
        rel = float(np.median([r_ for c, _, r_ in prov if np.linalg.norm(c - farg) < KLUSTER_AVSTAND]))
        fam, kanon = kanonisk(farg, rel)
        bild_ids = sorted({str(b) for c, b, _ in prov if np.linalg.norm(c - farg) < KLUSTER_AVSTAND})
        resultat[hus[hi]['id']] = dict(farg='#%02x%02x%02x' % kanon, familj=fam, uppmatt='#%02x%02x%02x' % tuple(
            int(round(v)) for v in farg), ljus=round(rel, 2), n=n_k, prov=len(prov), bilder=bilder_k,
            bild_ids=bild_ids)
        if len(urklipp) < 80:   # kontrollbild: väggens mitt i upp till sex bilder
            sedda = []
            for ki, p in klipp:
                if ki in sedda:
                    continue
                sedda.append(ki)
                im = Image.fromarray(bildcache[ki]) if ki in bildcache else None
                if im is None:
                    continue
                r = int(np.clip(p[2] * 3.0, 24, 160))
                urklipp.append((hus[hi]['id'], im.crop((p[0] - r, p[1] - r, p[0] + r, p[1] + r)).resize((96, 96)), farg))
    ut = GEO / projekt / 'data' / 'husfarger.json'
    ut.write_text(json.dumps({'kalla': 'Mapillary (CC BY-SA 4.0), husfarger_mapillary.py', 'hus': resultat},
                             ensure_ascii=False, indent=1))
    print(f'{len(resultat)} hus med fasadfärg -> {ut}')
    kontrollbild(projekt, resultat, urklipp)
    if args.rensa:   # behåll bara bilderna som bar en färg: en ombyggnad läser dem ur cachen igen
        behall = {i for r in resultat.values() for i in r.get('bild_ids', [])}
        bort = [f for f in cache.glob('*.jpg') if f.stem not in behall]
        storlek = sum(f.stat().st_size for f in bort)
        for f in bort:
            f.unlink()
        kvar = list(cache.glob('*.jpg'))
        print(f'cache: {len(bort)} bilder bort ({storlek / 1e6:.0f} MB), {len(kvar)} kvar '
              f'({sum(f.stat().st_size for f in kvar) / 1e6:.0f} MB)')


def kontrollbild(projekt, resultat, urklipp):
    """Urklipp per hus (upp till sex) med den färg huset fick, för de första 60 husen."""
    import husstil
    per_hus = {}
    for hid, im, c in urklipp:
        if hid in resultat:
            per_hus.setdefault(hid, []).append(im)
    rader = list(per_hus.items())[:60]
    if not rader:
        return
    W = 96
    ark = Image.new('RGB', (W * 8, W * len(rader)), 'white')
    d = ImageDraw.Draw(ark)
    for r, (hid, ims) in enumerate(rader):
        for i, im in enumerate(ims[:6]):
            ark.paste(im, (i * W, r * W))
        farg = husstil.farg(resultat[hid]['farg'])
        d.rectangle([6 * W, r * W, 7 * W - 1, (r + 1) * W - 1], fill=farg)
        variant = min((v for v in husstil.KATALOG['hustyper']['villa']['varianter']),
                      key=lambda v: husstil._avstand(v['farg'], farg))
        d.rectangle([7 * W, r * W, 8 * W - 1, (r + 1) * W - 1], fill=tuple(variant['farg']))
        d.text((7 * W + 4, r * W + 4), variant['id'].replace('villa_', ''), fill=(0, 0, 0))
    ut = GEO / 'forhandsbilder' / f'husfarger_{projekt}.jpg'
    ut.parent.mkdir(exist_ok=True)
    ark.save(ut, quality=85)
    print(f'kontrollbild: {ut}')


if __name__ == '__main__':
    main()
