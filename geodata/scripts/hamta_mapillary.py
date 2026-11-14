#!/usr/bin/env python3
"""
Mapillary (API v4, bilder CC BY-SA 4.0) för en karta: täckning, förebildsbilder vid undergångar och
kartobjekt (skyltar, lyktor, trafikljus ...) som Mapillary har känt igen i bilderna.

    .venv/bin/python -I scripts/hamta_mapillary.py tacka <projekt>
    .venv/bin/python -I scripts/hamta_mapillary.py bilder <projekt> [--radie 40] [--per-plats 6]
    .venv/bin/python -I scripts/hamta_mapillary.py bilder <projekt> --punkt E,N [--namn braskens_bro]
    .venv/bin/python -I scripts/hamta_mapillary.py objekt <projekt>   (+ bildlägen, för vagkant.py)

Platserna för `bilder` är NVDB:s underfarter (Bro_och_tunnel "underfart") och planskilda GCM-passager
inom kartans ruta, eller en egen punkt i SWEREF 99 TM. Bilderna hamnar i
<projekt>/data/mapillary/<plats>/ (gitignorerat) med index.json (id, läge, riktning, datum, avstånd,
länk till bilden på mapillary.com). De är förebilder att modellera efter: ingen bild får följa med i
spelet. Kartobjektens lägen är härledd data (credits: "Mapillary, CC BY-SA").

Nyckel: en Client Token från mapillary.com/dashboard/developers i miljövariabeln MLY_TOKEN
(skriv den i din egen terminal, aldrig i en chatt):  export MLY_TOKEN='MLY|...'
"""
import argparse, json, math, os, sqlite3, sys, time, urllib.error, urllib.parse, urllib.request
from collections import Counter
from pathlib import Path

import shapely
from pyproj import Transformer

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nvdb   # noqa: E402  (läser länsfilens geometri, _wkb)

GEO = Path(__file__).resolve().parent.parent
API = 'https://graph.mapillary.com'
CELL_M = 400.0            # rutans sida vid täckning/objekt (stora rutor svarar långsamt eller inte alls)
LIMIT = 2000              # API:ets största sida
TILL_WGS = Transformer.from_crs('EPSG:3006', 'EPSG:4326', always_xy=True)
TILL_SWEREF = Transformer.from_crs('EPSG:4326', 'EPSG:3006', always_xy=True)


def token():
    t = os.environ.get('MLY_TOKEN', '').strip()
    if not t:
        sys.exit("Ingen nyckel: export MLY_TOKEN='MLY|...' (Client Token från mapillary.com/dashboard/developers).")
    return t


def hamta(vag, **param):
    url = f'{API}/{vag}?' + urllib.parse.urlencode(param)
    req = urllib.request.Request(url, headers={'Authorization': f'OAuth {token()}'})
    for forsok in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (401, 403):
                sys.exit(f'Mapillary nekar nyckeln ({e.code}). Kontrollera MLY_TOKEN.')
            if e.code < 500 and e.code != 429:
                sys.exit(f'Mapillary svarade {e.code}: {e.read()[:300]!r}')
        except (urllib.error.URLError, TimeoutError):
            pass
        time.sleep(2 ** forsok)
    print('  (ger upp en förfrågan efter fyra försök)', file=sys.stderr)
    return {'data': []}


def ruta_for(projekt):
    g = json.load(open(GEO / projekt / 'work' / 'grid.json'))
    x0, y1 = g['x0'], g['y1']
    return x0, y1 - g['H'] * g['RES'], x0 + g['W'] * g['RES'], y1


def bbox_wgs(e0, n0, e1, n1):
    lon0, lat0 = TILL_WGS.transform(e0, n0)
    lon1, lat1 = TILL_WGS.transform(e1, n1)
    return f'{min(lon0, lon1):.6f},{min(lat0, lat1):.6f},{max(lon0, lon1):.6f},{max(lat0, lat1):.6f}'


def celler(ruta):
    e0, n0, e1, n1 = ruta
    e = e0
    while e < e1:
        n = n0
        while n < n1:
            yield e, n, min(e + CELL_M, e1), min(n + CELL_M, n1)
            n += CELL_M
        e += CELL_M


def sweref(geom):
    lon, lat = geom['coordinates']
    return TILL_SWEREF.transform(lon, lat)


# ---------- täckning ----------

def tacka(projekt):
    ruta = ruta_for(projekt)
    alla = list(celler(ruta))
    tackta, bilder, ar = 0, 0, Counter()
    for i, c in enumerate(alla):
        d = hamta('images', fields='id,captured_at', bbox=bbox_wgs(*c), limit=LIMIT).get('data', [])
        if d:
            tackta += 1
            bilder += len(d)
            ar.update(time.gmtime(b['captured_at'] / 1000).tm_year for b in d if b.get('captured_at'))
        print(f'\r  ruta {i + 1}/{len(alla)}', end='', file=sys.stderr)
    print(file=sys.stderr)
    print(f'{projekt}: {tackta}/{len(alla)} rutor à {CELL_M:.0f} m har bilder, {bilder} bilder'
          f'{" (minst; en ruta ger högst %d)" % LIMIT if bilder >= LIMIT else ""}')
    if ar:
        print('  år:', ', '.join(f'{a}: {n}' for a, n in sorted(ar.items())))


# ---------- förebildsbilder ----------

def platser_nvdb(ruta):
    """[(namn, E, N)] för NVDB:s underfarter och planskilda GCM-underfarter inom rutan."""
    con = sqlite3.connect(str(nvdb.NVDB_FIL))
    ut = []
    q = ('select t.geom, t.ELEMENT_ID, t.Namn, t.Konstruktion from "NVDB_DK_O_25_Bro_och_tunnel" t '
         'join "rtree_NVDB_DK_O_25_Bro_och_tunnel_geom" r on t.id = r.id '
         'where r.maxx >= ? and r.minx <= ? and r.maxy >= ? and r.miny <= ? and t.Konstruktion like "%underfart%"')
    sedda = set()
    for geom, eid, namn, _ in con.execute(q, (ruta[0], ruta[2], ruta[1], ruta[3])):
        g = shapely.force_2d(shapely.from_wkb(nvdb._wkb(geom)))
        p = g.interpolate(0.5, normalized=True) if g.geom_type != 'Point' else g
        nyckel = (round(p.x / 15), round(p.y / 15))   # samma passage i flera sträckor
        if eid in sedda or nyckel in sedda or not (ruta[0] <= p.x <= ruta[2] and ruta[1] <= p.y <= ruta[3]):
            continue
        sedda.update((eid, nyckel))
        ut.append((f'underfart_{_slug(namn) or eid}', p.x, p.y))
    q = ('select t.geom, t.ELEMENT_ID from "NVDB_DK_O_27_GCM_passage" t '
         'join "rtree_NVDB_DK_O_27_GCM_passage_geom" r on t.id = r.id '
         'where r.maxx >= ? and r.minx <= ? and r.maxy >= ? and r.miny <= ? '
         'and t.Passagetyp = "planskild passage underfart"')
    for geom, eid in con.execute(q, (ruta[0], ruta[2], ruta[1], ruta[3])):
        p = shapely.force_2d(shapely.from_wkb(nvdb._wkb(geom)))
        p = p if p.geom_type == 'Point' else p.centroid
        if any(math.hypot(p.x - e, p.y - n) < 25 for _, e, n in ut):
            continue
        ut.append((f'gcm_{eid}', p.x, p.y))
    return ut


def _slug(s):
    if not s:
        return ''
    t = ''.join(ch if ch.isalnum() else '_' for ch in s.lower())
    t = t.replace('å', 'a').replace('ä', 'a').replace('ö', 'o').replace('é', 'e')
    return '_'.join(x for x in t.split('_') if x)[:40]


def bilder_vid(namn, e, n, radie, per_plats, ut_mapp):
    falt = 'id,geometry,compass_angle,captured_at,is_pano,thumb_2048_url,sequence'
    d = hamta('images', fields=falt, bbox=bbox_wgs(e - radie, n - radie, e + radie, n + radie),
              limit=LIMIT).get('data', [])
    kandidater = []
    for b in d:
        if 'geometry' not in b:
            continue
        be, bn = sweref(b['geometry'])
        avst = math.hypot(be - e, bn - n)
        if avst > radie:
            continue
        # vänd mot platsen? (kompass 0 = norr, medurs) — panoramor ser åt alla håll
        mot = math.degrees(math.atan2(e - be, n - bn)) % 360
        fel = abs((b.get('compass_angle', mot) - mot + 180) % 360 - 180)
        if not b.get('is_pano') and fel > 70 and avst > 6:
            continue
        kandidater.append((avst + fel * 0.15, avst, fel, be, bn, b))
    kandidater.sort(key=lambda k: k[0])
    valda, sekvenser = [], Counter()
    for k in kandidater:   # sprid över olika bildserier (olika håll, olika år)
        if sekvenser[k[5].get('sequence')] >= max(2, per_plats // 2):
            continue
        sekvenser[k[5].get('sequence')] += 1
        valda.append(k)
        if len(valda) >= per_plats:
            break
    if not valda:
        return 0
    mapp = ut_mapp / namn
    mapp.mkdir(parents=True, exist_ok=True)
    index = {'plats': [e, n], 'radie_m': radie, 'bilder': []}
    for _, avst, fel, be, bn, b in valda:
        fil = mapp / f"{b['id']}.jpg"
        if not fil.exists() and b.get('thumb_2048_url'):
            try:
                with urllib.request.urlopen(b['thumb_2048_url'], timeout=60) as r:
                    fil.write_bytes(r.read())
            except (urllib.error.URLError, TimeoutError) as ex:
                print(f'  {namn}: kunde inte hämta {b["id"]}: {ex}', file=sys.stderr)
                continue
        index['bilder'].append({
            'id': b['id'], 'fil': fil.name, 'E': round(be, 1), 'N': round(bn, 1),
            'avstand_m': round(avst, 1), 'kompass': b.get('compass_angle'), 'fel_mot_platsen': round(fel),
            'panorama': bool(b.get('is_pano')),
            'datum': time.strftime('%Y-%m-%d', time.gmtime(b['captured_at'] / 1000)) if b.get('captured_at') else None,
            'lank': f"https://www.mapillary.com/app/?pKey={b['id']}",
        })
    json.dump(index, open(mapp / 'index.json', 'w'), ensure_ascii=False, indent=1)
    return len(index['bilder'])


def bilder(projekt, radie, per_plats, punkt, namn):
    ut_mapp = GEO / projekt / 'data' / 'mapillary'
    if punkt:
        e, n = (float(v) for v in punkt.split(','))
        platser = [(namn or f'punkt_{e:.0f}_{n:.0f}', e, n)]
    else:
        platser = platser_nvdb(ruta_for(projekt))
    print(f'{len(platser)} platser')
    tomma = []
    for namn_, e, n in platser:
        k = bilder_vid(namn_, e, n, radie, per_plats, ut_mapp)
        print(f'  {namn_:44s} {e:10.0f} {n:10.0f}  {k} bilder')
        if not k:
            tomma.append(namn_)
    print(f'klart: {ut_mapp}' + (f'  ({len(tomma)} platser utan bilder)' if tomma else ''))


# ---------- kartobjekt ----------

def objekt(projekt):
    ruta = ruta_for(projekt)
    sedda, ut, typer = set(), [], Counter()
    alla = list(celler(ruta))
    for i, c in enumerate(alla):
        d = hamta('map_features', fields='id,object_value,object_type,geometry,first_seen_at,last_seen_at',
                  bbox=bbox_wgs(*c), limit=LIMIT).get('data', [])
        if len(d) >= LIMIT:
            print(f'\n  ruta {c} gav {LIMIT} (taket): minska CELL_M', file=sys.stderr)
        for f in d:
            if f['id'] in sedda or 'geometry' not in f:
                continue
            sedda.add(f['id'])
            e, n = sweref(f['geometry'])
            typer[f.get('object_value')] += 1
            ut.append({'type': 'Feature', 'geometry': {'type': 'Point', 'coordinates': [round(e, 2), round(n, 2)]},
                       'properties': {k: f.get(k) for k in ('id', 'object_value', 'object_type',
                                                            'first_seen_at', 'last_seen_at')}})
        print(f'\r  ruta {i + 1}/{len(alla)}', end='', file=sys.stderr)
    print(file=sys.stderr)
    # bildernas lägen: var Mapillary har sett (vagkant.py ersätter bara reglerna där)
    pos = []
    for c in alla:
        for b in hamta('images', fields='id,computed_geometry,geometry', bbox=bbox_wgs(*c), limit=LIMIT).get('data', []):
            g = b.get('computed_geometry') or b.get('geometry')
            if g:
                pos.append([round(v, 1) for v in sweref(g)])
    fil = GEO / projekt / 'data' / 'mapillary_objekt.geojson'
    fil.parent.mkdir(parents=True, exist_ok=True)
    (fil.parent / 'mapillary_bildlagen.json').write_text(json.dumps(pos))
    print(f'{len(pos)} bildlägen -> {fil.parent / "mapillary_bildlagen.json"}')
    json.dump({'type': 'FeatureCollection', 'crs': {'type': 'name', 'properties': {'name': 'EPSG:3006'}},
               'features': ut}, open(fil, 'w'), ensure_ascii=False)
    print(f'{len(ut)} kartobjekt -> {fil}')
    for v, k in typer.most_common(30):
        print(f'  {k:6d}  {v}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('tacka'); s.add_argument('projekt')
    s = sub.add_parser('bilder'); s.add_argument('projekt')
    s.add_argument('--radie', type=float, default=40.0, help='sökradie runt platsen (m)')
    s.add_argument('--per-plats', type=int, default=6)
    s.add_argument('--punkt', help='egen plats i SWEREF 99 TM: E,N')
    s.add_argument('--namn', help='mappnamn för --punkt')
    s = sub.add_parser('objekt'); s.add_argument('projekt')
    a = ap.parse_args()
    token()
    if a.cmd == 'tacka':
        tacka(a.projekt)
    elif a.cmd == 'bilder':
        bilder(a.projekt, a.radie, a.per_plats, a.punkt, a.namn)
    else:
        objekt(a.projekt)


if __name__ == '__main__':
    main()
