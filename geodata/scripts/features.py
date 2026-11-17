"""OSM -> geometrier i SWEREF 99 TM (EPSG:3006)."""
import json
from pathlib import Path
import os
ROOT = Path(__file__).resolve().parent.parent
WORK = Path(os.environ.get('GEO_WORK', ROOT / 'work'))   # bygg.py --projekt sätter egen work-mapp
WORK.mkdir(exist_ok=True)
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from osmload import load
from pyproj import Transformer
from shapely.geometry import LineString, Polygon, Point
from shapely.ops import linemerge, polygonize, unary_union

LANDCOVER_KEYS = {
    ('landuse', 'forest'): 'forest', ('natural', 'wood'): 'forest',
    ('landuse', 'farmland'): 'farmland', ('landuse', 'meadow'): 'meadow',
    ('landuse', 'grass'): 'meadow', ('landuse', 'residential'): 'residential',
    ('landuse', 'farmyard'): 'farmyard', ('landuse', 'cemetery'): 'residential',
    ('natural', 'wetland'): 'wetland', ('natural', 'bare_rock'): 'rock',
    ('natural', 'scrub'): 'scrub', ('natural', 'beach'): 'beach',
    ('natural', 'water'): 'water',
}

# Järnväg i bruk (jarnvag.py); disused/abandoned/museum/tram tas inte med
RAIL_KINDS = ('rail', 'light_rail', 'narrow_gauge')

def landcover_class(t):
    for (k, v), c in LANDCOVER_KEYS.items():
        if t.get(k) == v:
            return c
    return None

def build(osm_path):
    nodes, ntags, ways, rels = load(osm_path)
    tr = Transformer.from_crs(4326, 3006, always_xy=True)
    P = {k: tr.transform(*v) for k, v in nodes.items()}

    def coords(w):
        return [P[k] for k in w['nds'] if k in P]

    out = dict(buildings=[], roads=[], landcover=[], water=[], waterways=[], points=[], hedges=[],
               rails=[], platforms=[], vagpunkter=[], lekplatser=[], lekredskap=[], idrottsbanor=[], byggdelar=[],
               idrottsplaner=[], bassanger=[], kyrkogardar=[])
    used_in_rel = set()
    bana_medlem = set()   # vägar i en löparbanas multipolygon (idrott.py) läggs inte till en gång till
    for rid, r in rels.items():
        t = r['tags']
        if t.get('type') != 'multipolygon':
            continue
        outer = [LineString(coords(ways[m[1]])) for m in r['members']
                 if m[0] == 'way' and m[1] in ways and m[2] in ('outer', '') and len(coords(ways[m[1]])) > 1]
        inner = [LineString(coords(ways[m[1]])) for m in r['members']
                 if m[0] == 'way' and m[1] in ways and m[2] == 'inner' and len(coords(ways[m[1]])) > 1]
        try:
            op = unary_union(list(polygonize(linemerge(outer)))) if outer else None
            ip = unary_union(list(polygonize(linemerge(inner)))) if inner else None
        except Exception:
            continue
        if op is None or op.is_empty:
            continue
        g = op.difference(ip) if ip is not None and not ip.is_empty else op
        cls = landcover_class(t)
        if t.get('landuse') == 'cemetery' or t.get('amenity') == 'grave_yard':
            out['kyrkogardar'].append((g, t, f'r{rid}'))   # gravar.py (ytan blir även marktäcke nedan)
        if t.get('leisure') == 'track':
            out['idrottsbanor'].append((g, t, rid))   # idrott.py: löparbana med hål
            bana_medlem.update(m[1] for m in r['members'] if m[0] == 'way')
        elif 'building' in t:   # multipolygon-hus (A-, B-huset ...): id 'r<relation>' för husfarger/landmärken
            out['buildings'].append((g, dict(t, _osm_id=f'r{rid}')))
        elif cls == 'water':
            out['water'].append((g, t))
        elif cls:
            out['landcover'].append((g, cls))
        for m in r['members']:
            if m[0] == 'way' and not ways.get(m[1], {}).get('tags'):
                used_in_rel.add(m[1])

    # <projekt>/broar_bort.json: OSM-vägar (id) som inte ska bli broar, t.ex. långa spänger
    # mitt i skogen som stänger vägen för vagnarna. Vägen blir kvar som vanlig väg på marken.
    # <projekt>/vagar_bort.json: ["<OSM-väg-id>", ...] (eller {"vagar": [...]}): vägarna tas bort helt,
    # t.ex. broar över en å som inte ska gå att korsa (peking: Motala ström väster om Drottningbron)
    vbort = WORK.parent / 'vagar_bort.json'
    if vbort.exists():
        lista = json.loads(vbort.read_text())
        for wid in (lista['vagar'] if isinstance(lista, dict) else lista):
            if ways.pop(wid, None) is None and ways.pop(str(wid), None) is None and \
                    (not str(wid).isdigit() or ways.pop(int(wid), None) is None):
                print(f'vagar_bort.json: ingen väg {wid}')

    # <projekt>/broar_sammanfoga.json: {"<namn>": {"vagar": [id, ...], "bredd": 40, "highway": "secondary",
    # "lanes": 4, "axel": [[E, N], [E, N]] (valfri mittlinje)}}: en bro som OSM ritar som många parallella vägar (körbanor, spårvägs- och busskörfält,
    # GC-banor) blir ett enda däck: vägarna tas bort och ersätts av en väg längs mittlinjen av deras
    # minsta omslutande rektangel, `bredd` m bred (fast, `_fast_bredd`: NVDB-stegets tak 14 m gäller inte).
    # Annars blev det ett smalt däck per väg med vatten emellan (Hamnbron och Drottningbron i peking).
    sam = WORK.parent / 'broar_sammanfoga.json'
    if sam.exists():
        nytt_id = -1
        for namn, val in json.loads(sam.read_text()).items():
            if namn.startswith('_'):
                continue
            ids = [int(w) for w in val['vagar'] if int(w) in ways]
            if not ids:
                print(f'broar_sammanfoga.json: inga vägar kvar för {namn}')
                continue
            forsta = ways[ids[0]]['tags']
            if val.get('axel'):           # handräknad mittlinje [[E, N], [E, N]]
                mitt = [tuple(map(float, q)) for q in val['axel']]
            else:
                linjer = [LineString(coords(ways[w])) for w in ids if len(coords(ways[w])) > 1]
                hörn = list(unary_union(linjer).minimum_rotated_rectangle.exterior.coords)[:4]
                kant = lambda i: (hörn[i], hörn[(i + 1) % 4])
                längd = lambda i: ((kant(i)[1][0] - kant(i)[0][0]) ** 2 + (kant(i)[1][1] - kant(i)[0][1]) ** 2) ** 0.5
                kort = 0 if längd(0) < längd(1) else 1      # rektangelns korta kanter: 0 och 2 (eller 1 och 3)
                mitt = [tuple((a + b) / 2 for a, b in zip(*kant(i))) for i in (kort, kort + 2)]
            nds = []
            for e, n in mitt:
                P[nytt_id] = (e, n)
                nds.append(nytt_id)
                nytt_id -= 1
            tags = {'highway': val.get('highway', forsta.get('highway', 'secondary')), 'name': namn,
                    'bridge': 'yes', 'layer': '1', 'oneway': 'no', 'surface': 'asphalt',
                    'width': str(val['bredd']), '_fast_bredd': str(float(val['bredd'])),
                    '_min_bredd': str(float(val['bredd']))}
            if val.get('lanes'):
                tags['lanes'] = str(val['lanes'])
            for w in ids:
                del ways[w]
            ways[nytt_id] = {'nds': nds, 'tags': tags}
            nytt_id -= 1
            print(f'broar_sammanfoga.json: {namn} = {len(ids)} vägar -> ett däck {val["bredd"]} m')

    bort = WORK.parent / 'broar_bort.json'
    if bort.exists():
        for wid in json.loads(bort.read_text()):
            ways.get(wid, ways.get(str(wid), {})).get('tags', {}).pop('bridge', None)
    # <projekt>/broar_justera.json: {"<OSM-väg-id>": {"utan_pelare": true, "extra_fri_hojd": 1.0,
    # "min_bredd": 5.0}}: bron får inga pelare, marken under den sänks så mycket mer än vanligt, och
    # körbanan mellan kantbalkarna blir minst så bred (broar.py; t.ex. gångbroar som vagnar ska över).
    justera = WORK.parent / 'broar_justera.json'
    if justera.exists():
        for wid, val in json.loads(justera.read_text()).items():
            if wid.startswith('_'):
                continue
            t = ways.get(wid, ways.get(int(wid) if wid.isdigit() else wid, {})).get('tags')
            if t is None:
                print(f'broar_justera.json: ingen väg {wid}')
                continue
            if val.get('utan_pelare'):
                t['_utan_pelare'] = 'yes'
            if val.get('extra_fri_hojd'):
                t['_extra_fri_hojd'] = str(float(val['extra_fri_hojd']))
            if val.get('min_bredd'):
                t['_min_bredd'] = str(float(val['min_bredd']))

    # <projekt>/vagar_justera.json: {"<OSM-väg-id>": {"width": "9", ...}}: taggar som läggs på vägen
    # (t.ex. en GC-väg som är mycket bredare än OSM-tabellens stig, Märkesbacken på Campus Valla)
    vjust = WORK.parent / 'vagar_justera.json'
    if vjust.exists():
        for wid, val in json.loads(vjust.read_text()).items():
            if wid.startswith('_'):
                continue
            t = ways.get(wid, ways.get(int(wid) if wid.isdigit() else wid, {})).get('tags')
            if t is None:
                print(f'vagar_justera.json: ingen väg {wid}')
                continue
            t.update({k: str(v) for k, v in val.items()})

    for wid, w in ways.items():
        t = w['tags']
        c = coords(w)
        if len(c) < 2:
            continue
        closed = w['nds'][0] == w['nds'][-1] and len(c) >= 4
        if 'building' in t and closed:
            out['buildings'].append((Polygon(c).buffer(0), dict(t, _osm_id=str(wid))))
        elif 'building:part' in t and closed:
            out['byggdelar'].append((Polygon(c).buffer(0), t, str(wid)))   # landmarken.py
        elif 'highway' in t and t['highway'] not in ('proposed', 'construction', 'platform'):
            out['roads'].append((LineString(c), t))
        elif t.get('railway') in RAIL_KINDS:
            out['rails'].append((LineString(c), t))
        elif t.get('railway') == 'platform' or t.get('public_transport') == 'platform' and t.get('train') == 'yes':
            out['platforms'].append((Polygon(c).buffer(0) if closed else LineString(c), t))
        elif t.get('leisure') == 'track' and closed and wid not in bana_medlem:
            out['idrottsbanor'].append((Polygon(c).buffer(0), t, wid))   # idrott.py
        elif t.get('leisure') == 'pitch' and closed:
            out['idrottsplaner'].append((Polygon(c).buffer(0), t, wid))   # idrott.py: fotboll, tennis
        elif t.get('leisure') == 'swimming_pool' and closed:
            out['bassanger'].append((Polygon(c).buffer(0), t, wid))   # idrott.py: utomhusbad
        elif t.get('leisure') == 'playground' and closed:
            out['lekplatser'].append((Polygon(c).buffer(0), t, wid))   # lekplatser.py
        elif t.get('public_transport') == 'platform' and t.get('shelter') == 'yes':
            out['vagpunkter'].append((LineString(c).centroid, {'highway': 'vaderskydd'}))   # vagkant.py
        elif 'waterway' in t:
            out['waterways'].append((LineString(c), t))
        elif t.get('barrier') == 'hedge':
            out['hedges'].append(LineString(c))
        elif closed and landcover_class(t):
            cls = landcover_class(t)
            g = Polygon(c).buffer(0)
            (out['water'] if cls == 'water' else out['landcover']).append((g, t if cls == 'water' else cls))
    for nid, t in ntags.items():
        if 'name' in t and ('place' in t or 'historic' in t):
            out['points'].append((Point(P[nid]), t))
        # vägkanten (vagkant.py): hållplatser, väjnings- och stopplikt, gatlyktor, trafikljus
        if (t.get('highway') in ('bus_stop', 'give_way', 'stop', 'street_lamp', 'traffic_signals') or 'traffic_calming' in t) and nid in P:
            out['vagpunkter'].append((Point(P[nid]), t))
        elif t.get('highway') == 'crossing' and nid in P:
            out['vagpunkter'].append((Point(P[nid]), t))   # övergångsställen (vagmarkering.py, vagkant.py)
        elif 'playground' in t and nid in P:
            out['lekredskap'].append((Point(P[nid]), t))   # lekplatser.py: redskap ur OSM
        elif t.get('amenity') == 'shelter' and t.get('shelter_type') == 'public_transport' and nid in P:
            out['vagpunkter'].append((Point(P[nid]), {'highway': 'vaderskydd'}))
    # kyrkogårdar (gravar.py); ytan är också marktäcke (residential) som förut
    for wid, w in ways.items():
        t = w['tags']
        if (t.get('landuse') == 'cemetery' or t.get('amenity') == 'grave_yard') and w['nds'][0] == w['nds'][-1]:
            c = coords(w)
            if len(c) >= 4:
                out['kyrkogardar'].append((Polygon(c).buffer(0), t, wid))
    return out
