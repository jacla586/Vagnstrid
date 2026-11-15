"""Markvegetation per 2 m-cell (samma rutnät som heightmapen) för spelets markväxtlighet (GroundCover):
höjden på gräs, gröda, vass och ris avgör hur väl en liggande eller knästående soldat döljs, och
spelet ritar växtligheten efter klassen. Anropas från step3 när marktäcket är klart.

Klasser (index i out/markvegetation.bin, uint8 rad för rad; namnen står i markvegetation.json och
i spelets data/world/ground_cover.tres, som har höjder och utseende):
  0 ingen         vägar, hus, vatten, berg, sand
  1 gräsmatta     tomter
  2 kort gräs     betesmark, gårdsplan, öppen mark
  3 högt gräs     äng, vall, slåtteräng, skyddszoner, gräsfattig mark
  4 gröda         spannmål och andra åkergrödor (Jordbruksverkets skiften, annars OSM-åker)
  5 våtmark       starr och vass
  6 snår          buskmark, sly (lågt ris mellan buskarna)
  7 skogsbotten   ris, blåbär och ljung under träden
  8 vass          bälte längs sjöarnas stränder: VASS_LAND_M upp på land (naturmark) och VASS_VATTEN_M ut i sjön
Grödor ur `<data>/jordbruk_skiften.geojson` (hamta_jordbruk.py) går före OSM:s åker/äng.
"""
import json
from pathlib import Path
import numpy as np
from rasterio.features import rasterize
from shapely.geometry import shape as geo_shape

KLASSER = ['ingen', 'gräsmatta', 'kort gräs', 'högt gräs', 'gröda', 'våtmark', 'snår', 'skogsbotten', 'vass']
K = {n: i for i, n in enumerate(KLASSER)}
# marktäcke (step3 CLASSES) -> klass
FRAN_MARKTACKE = {'hav': 'ingen', 'mark': 'kort gräs', 'skog': 'skogsbotten', 'åker': 'gröda', 'äng': 'högt gräs',
                  'tomt': 'gräsmatta', 'gård': 'kort gräs', 'våtmark': 'våtmark', 'berg': 'ingen',
                  'buskmark': 'snår', 'strand': 'ingen', 'sjö': 'ingen', 'väg_asfalt': 'ingen', 'väg_grus': 'ingen', 'hårdgjord': 'ingen'}
# Jordbruksverkets grödkoder (huvudgröda): bete kort, vall/äng/skyddszon högt, annars gröda
BETE = {52, 55, 56, 61}
VASS_LAND_M = 4.0
VASS_VATTEN_M = 6.0
GRAS = {49, 50, 53, 54, 57, 58, 59, 62, 63, 64, 65, 66, 77, 80, 90, 95}


def bygg(lc, CIDX, T, shape, data_dir, byggnader, ut_dir, forhands=None, sjoar=None, RES=2.0, gräsmattor=None):
    namn_av = {i: n for n, i in CIDX.items()}
    mv = np.zeros(shape, np.uint8)
    for idx, namn in namn_av.items():
        mv[lc == idx] = K[FRAN_MARKTACKE.get(namn, 'kort gräs')]
    fil = Path(data_dir) / 'jordbruk_skiften.geojson'
    n_sk = 0
    if fil.exists():
        sk = json.loads(fil.read_text())['features']
        former = []
        for f in sk:
            try:
                kod = int(f['properties'].get('grdkod_mar') or 0)
            except (TypeError, ValueError):
                continue
            klass = 'kort gräs' if kod in BETE else 'högt gräs' if kod in GRAS else 'gröda'
            former.append((geo_shape(f['geometry']), K[klass]))
        if former:
            r = rasterize(former, out_shape=shape, transform=T, fill=255).astype(np.uint8)
            # bara där marken är öppen (inte vägar, vatten, skog, tomter)
            oppen = np.isin(mv, [K['kort gräs'], K['högt gräs'], K['gröda'], K['våtmark'], K['snår']])
            satt = (r != 255) & oppen
            mv[satt] = r[satt]
            n_sk = len(former)
    if sjoar:
        # vass: ett bälte längs stränderna, på naturmark och ut i grunt vatten
        from scipy import ndimage as ndi
        sjo = rasterize([(p, 1) for p in sjoar], out_shape=shape, transform=T).astype(bool)
        land_avst = ndi.distance_transform_edt(~sjo) * RES
        vatten_avst = ndi.distance_transform_edt(sjo) * RES
        natur = np.isin(mv, [K['kort gräs'], K['högt gräs'], K['våtmark'], K['snår']])
        vass = (~sjo & (land_avst <= VASS_LAND_M) & natur) | (sjo & (vatten_avst <= VASS_VATTEN_M))
        mv[vass] = K['vass']
    # lekplatser och liknande (OSM): klippt gräs
    if gräsmattor:
        g = rasterize([(p, 1) for p in gräsmattor if not p.is_empty], out_shape=shape, transform=T).astype(bool)
        mv[g & (mv != K['ingen'])] = K['gräsmatta']
    # vägrenen (en cell utanför asfalten och gruset) hålls kort
    vag_idx = [CIDX[n] for n in ('väg_asfalt', 'väg_grus') if n in CIDX]
    if vag_idx:
        from scipy import ndimage as ndi
        vag = np.isin(lc, vag_idx)
        ren = ndi.binary_dilation(vag, iterations=1) & ~vag & np.isin(mv, [K['högt gräs'], K['gröda'], K['snår'], K['våtmark']])
        mv[ren] = K['kort gräs']
    if byggnader:
        mv[rasterize([(b, 1) for b in byggnader], out_shape=shape, transform=T).astype(bool)] = K['ingen']
    ut = Path(ut_dir)
    mv.tofile(ut / 'markvegetation.bin')
    json.dump(dict(width=int(shape[1]), height=int(shape[0]), klasser=KLASSER,
                   kalla='marktäcke (OSM, NMD, orienteringskarta) + Jordbruksverkets skiften'),
              open(ut / 'markvegetation.json', 'w'), ensure_ascii=False)
    andel = {KLASSER[i]: round(float((mv == i).mean()) * 100, 1) for i in range(len(KLASSER))}
    print(f'markvegetation: {n_sk} jordbruksskiften, andelar % {andel}')
    if forhands:
        from PIL import Image
        pal = np.array([(90, 90, 90), (120, 170, 80), (150, 175, 90), (190, 200, 90), (225, 200, 90),
                         (90, 140, 130), (100, 120, 60), (60, 90, 50), (150, 120, 60)], np.uint8)
        Image.fromarray(pal[mv]).save(forhands)
    return mv


# ---------- växtlagret på avstånd (spelets GroundCoverCanopy) ----------
LAGER_KLASSER = (3, 4, 5, 6, 8)   # högt gräs, gröda, våtmark, snår, vass: höjer sig över en liggande soldat
LAGER_RUTA = 2                 # 2 × 2 celler = 4 m
LAGER_TILE_M = 250.0


def lager_glb(mv, h, RES, ut_fil):
    """Plana rutor (4 m) där markvegetationen är hög, på markhöjden, en mesh per 250 m-ruta.
    UV.x = klassens index; spelets shader lägger på höjd och färg ur data/world/ground_cover.tres.
    Världskoordinater: cell (rad i, kolumn j) har mitten på x = j*RES, z = i*RES."""
    import trimesh
    H, W = mv.shape
    nb_i, nb_j = H // LAGER_RUTA, W // LAGER_RUTA
    blk = mv[:nb_i * LAGER_RUTA, :nb_j * LAGER_RUTA].reshape(nb_i, LAGER_RUTA, nb_j, LAGER_RUTA)
    blk = blk.transpose(0, 2, 1, 3).reshape(nb_i, nb_j, -1)
    # hela block av samma höga klass: en 4 m-ruta; blandade block (kanter mot vägar, stenläggning, öar):
    # en 2 m-ruta per cell med hög klass, så att lagret aldrig ligger över en yta (där är mv 0)
    hog = np.isin(blk, LAGER_KLASSER)
    hel = hog.all(-1) & (blk == blk[..., :1]).all(-1)
    bi, bj = np.nonzero(hel)
    s4 = LAGER_RUTA * RES
    i_hel = np.zeros((H, W), bool)
    i_hel[:nb_i * LAGER_RUTA, :nb_j * LAGER_RUTA] = np.kron(hel, np.ones((LAGER_RUTA, LAGER_RUTA), bool))
    ci, cj = np.nonzero(np.isin(mv, LAGER_KLASSER) & ~i_hel)
    x0 = np.r_[bj * s4, cj * RES] - RES / 2
    z0 = np.r_[bi * s4, ci * RES] - RES / 2
    sz = np.r_[np.full(len(bi), s4), np.full(len(ci), RES)]
    kl = np.r_[blk[bi, bj, 0], mv[ci, cj]].astype(int)
    if len(x0) == 0:
        return 0
    from scipy import ndimage as ndi
    def hojd(x, z):
        return ndi.map_coordinates(h, [z / RES, x / RES], order=1, mode='nearest')
    hx = [x0, x0 + sz, x0 + sz, x0]
    hz = [z0, z0, z0 + sz, z0 + sz]
    ys = [hojd(a, b) for a, b in zip(hx, hz)]
    scene = trimesh.Scene()
    tile = (np.floor(x0 / LAGER_TILE_M).astype(int), np.floor(z0 / LAGER_TILE_M).astype(int))
    nycklar = {}
    for k, key in enumerate(zip(*tile)):
        nycklar.setdefault(key, []).append(k)
    for (tx, tz), idx in sorted(nycklar.items()):
        idx = np.array(idx)
        n = len(idx)
        V = np.empty((n, 4, 3))
        for c in range(4):
            V[:, c] = np.c_[hx[c][idx], ys[c][idx], hz[c][idx]]
        V = V.reshape(-1, 3)
        a = np.arange(n) * 4
        # medurs sett uppifrån (Godots framsida); x österut, z söderut
        F = np.r_[np.c_[a, a + 2, a + 1], np.c_[a, a + 3, a + 2]]
        uv = np.repeat(np.c_[kl[idx].astype(float), np.zeros(n)], 4, axis=0)
        m = trimesh.Trimesh(V, F, process=False)
        if m.face_normals[:, 1].mean() < 0:
            m.faces = m.faces[:, ::-1]
        m.visual = trimesh.visual.TextureVisuals(uv=uv, material=trimesh.visual.material.PBRMaterial(
            name='Markvegetation', baseColorFactor=[0.2, 0.25, 0.1, 1.0]))
        namn = f'Markvegetation_{tx}_{tz}'
        scene.add_geometry(m, node_name=namn, geom_name=namn)
    scene.export(ut_fil)
    print(f'markvegetation: växtlager {len(bi)} hela 4 m-rutor + {len(ci)} 2 m-celler i {len(nycklar)} bitar -> {ut_fil}')
    return len(x0)



def vatten(sjoar, nivaer, T, shape, ut_dir):
    """Sjöarnas id per 2 m-cell (uint8, 0 = inget, n = sjö n) och vattennivåerna, för spelets vadning
    (GroundCoverData.water_ids/water_levels): out/vatten.bin + vatten.json."""
    ids = np.zeros(shape, np.uint8)
    former = [(p, min(k + 1, 255)) for k, p in enumerate(sjoar)]
    if former:
        ids = rasterize(former, out_shape=shape, transform=T, fill=0).astype(np.uint8)
    ut = Path(ut_dir)
    ids.tofile(ut / 'vatten.bin')
    json.dump(dict(width=int(shape[1]), height=int(shape[0]),
                   nivaer=[round(float(v), 3) for v in nivaer[:255]]), open(ut / 'vatten.json', 'w'))
    print(f'vatten: {len(sjoar)} sjöar, {int((ids > 0).sum())} celler')
