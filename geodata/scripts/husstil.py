"""Husstilar: klassning, val av variant och fasadatlasar.

Stilkatalogen ligger i geodata/stilar.json. Varje hus får en hustyp (klassa) och en variant
(valj_stil) som anger väggmaterial, färg, fönstertyp, knutar, skorsten och tak. Fasaderna ritas
i en atlas med tre rutor per variant: fönsterfack (ett fack × en våning), slät vägg och dörr.
Atlas() gör den stiliserade (platta färger, målade fönster) och Atlas(semi=True) den
semirealistiska (CC0-fototexturer från ambientCG med fönster ovanpå, plus normal- och
roughness-karta).
"""
import json, math, zlib
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import trimesh

ROOT = Path(__file__).resolve().parent.parent
KATALOG = json.loads((ROOT / 'stilar.json').read_text())
TEXTURER = ROOT / 'texturer'
FACK_M = float(KATALOG['fack_bredd_m'])
PAD = 6                         # px kant runt varje ruta (mot läckage i mipmaps)
KNUT_FARG = (240, 238, 232)

# ---------------------------------------------------------------- färger
FARGNAMN = {
    'white': (238, 236, 228), 'red': (150, 52, 40), 'darkred': (110, 36, 30), 'brown': (110, 78, 56),
    'yellow': (226, 200, 120), 'lightyellow': (236, 222, 168), 'beige': (220, 204, 170),
    'grey': (150, 152, 152), 'gray': (150, 152, 152), 'lightgrey': (196, 198, 196), 'lightgray': (196, 198, 196),
    'darkgrey': (90, 92, 94), 'darkgray': (90, 92, 94), 'black': (44, 44, 46), 'blue': (70, 98, 140),
    'lightblue': (160, 186, 206), 'green': (80, 110, 70), 'orange': (204, 120, 60), 'pink': (220, 170, 170),
    'cream': (238, 228, 196), 'silver': (180, 182, 184), 'maroon': (110, 36, 30),
}
MATERIAL_OSM = {'wood': ('panel_staende', 'panel_liggande'), 'brick': ('tegel', 'tegel_gult'),
                'plaster': ('puts',), 'concrete': ('betong',), 'glass': ('glas',), 'metal': ('plat',)}


def farg(text):
    """OSM-färg (namn eller #rrggbb) -> (r, g, b) eller None."""
    if not text:
        return None
    t = str(text).strip().lower().replace(' ', '').replace('_', '')
    if t.startswith('#') and len(t) in (4, 7):
        if len(t) == 4:
            t = '#' + ''.join(c * 2 for c in t[1:])
        try:
            return tuple(int(t[i:i + 2], 16) for i in (1, 3, 5))
        except ValueError:
            return None
    return FARGNAMN.get(t)


def _avstand(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b))


# ---------------------------------------------------------------- klassning
def klassa(taggar, yta, hojd, landsbygd):
    """Hustyp ur OSM-taggen, eller ur storlek, höjd och omgivning när taggen saknas."""
    b = (taggar or {}).get('building', 'yes')
    if b in ('house', 'detached', 'semidetached_house', 'villa', 'bungalow'):
        return 'villa'
    if b == 'terrace':
        return 'radhus'
    if b in ('apartments', 'dormitory', 'residential'):
        return 'villa' if (yta < 200 and hojd < 9) else 'flerbostadshus'
    if b in ('office', 'commercial', 'university', 'school', 'college', 'kindergarten', 'hospital',
             'public', 'civic', 'government', 'hotel', 'sports_hall'):
        return 'kontor'
    if b in ('retail', 'supermarket'):
        return 'butik'
    if b in ('industrial', 'warehouse', 'manufacture', 'service', 'hangar'):
        return 'industri'
    if b == 'farm':
        return 'gard'
    if b in ('farm_auxiliary', 'barn', 'stable', 'cowshed', 'sty'):
        return 'uthus' if yta < 40 else 'lada'
    if b in ('garage', 'garages', 'carport', 'shed', 'hut', 'allotment_house', 'roof', 'cabin', 'kiosk'):
        return 'uthus'
    if b in ('church', 'chapel', 'cathedral'):
        return 'kyrka'
    # building=yes eller okänd typ, och laserhus
    if yta < 30:
        return 'uthus'
    if landsbygd:
        return 'lada' if (yta > 180 or hojd > 7.5) else 'gard'
    if hojd >= 9 or yta >= 400:
        return 'kontor' if yta >= 1500 else 'flerbostadshus'
    if yta < 60:
        return 'uthus'
    return 'villa'


def valj_stil(hustyp, taggar, nyckel):
    """Variant (dict ur katalogen, plus 'hustyp', 'vaning_m', 'fonster', 'skorsten', 'tak_namn').
    `nyckel` ger ett stabilt slumpfrö (t.ex. husets mittpunkt)."""
    ht = KATALOG['hustyper'][hustyp]
    rng = np.random.default_rng(zlib.crc32(repr(nyckel).encode()))
    varianter = ht['varianter']
    taggar = taggar or {}
    osm_farg = farg(taggar.get('building:colour'))
    osm_mat = MATERIAL_OSM.get(str(taggar.get('building:material', '')).lower())
    kandidater = [v for v in varianter if not osm_mat or v['vagg'] in osm_mat] or varianter
    if osm_farg:
        v = min(kandidater, key=lambda v: _avstand(v['farg'], osm_farg))
    else:
        vikt = np.array([v['vikt'] for v in kandidater], float)
        v = kandidater[int(rng.choice(len(kandidater), p=vikt / vikt.sum()))]
    tak_farg = farg(taggar.get('roof:colour'))
    if tak_farg:
        tak = min(KATALOG['tak'], key=lambda n: _avstand(KATALOG['tak'][n]['farg'], tak_farg))
    else:
        tak = v['tak'][int(rng.integers(len(v['tak'])))]
    return dict(v, hustyp=hustyp, vaning_m=ht['vaning_m'], fonster=v.get('fonster', ht['fonster']),
                skorsten=ht['skorsten'], tak_namn=tak)


def alla_varianter():
    for ht, d in KATALOG['hustyper'].items():
        for v in d['varianter']:
            yield ht, dict(v, hustyp=ht, vaning_m=d['vaning_m'], fonster=v.get('fonster', d['fonster']))


# ---------------------------------------------------------------- atlas
def _morkare(c, f):
    return tuple(int(max(0, min(255, x * f))) for x in c)


class Atlas:
    """Fasadatlas: rutor 'fack', 'slat', 'dorr' per variant, plus 'knut' och 'skorsten_*'."""

    def __init__(self, semi=False, storlek=2048, bara=None):
        self.semi = semi
        varianter = [v for _, v in alla_varianter() if bara is None or v['id'] in bara]
        self.varianter = {v['id']: v for v in varianter}
        nycklar = [(v['id'], r) for v in varianter for r in ('fack', 'slat', 'dorr')]
        nycklar += [('knut', 'slat'), ('skorsten_tegel', 'slat'), ('skorsten_puts', 'slat')]
        self.n = math.ceil(math.sqrt(len(nycklar)))
        self.cell = storlek // self.n
        self.S = storlek
        self.index = {k: i for i, k in enumerate(nycklar)}
        self.albedo = Image.new('RGB', (storlek, storlek), (128, 128, 128))
        self.normal = Image.new('RGB', (storlek, storlek), (128, 128, 255)) if semi else None
        self.rough = Image.new('L', (storlek, storlek), 200) if semi else None
        self._tex = {}
        for k in nycklar:
            self._rita(k)
        self._material = None

    # -- uv
    def uv(self, variant_id, ruta):
        """(u0, v0, u1, v1) för en ruta, OpenGL-konvention (v uppåt), innanför kanten."""
        i = self.index[(variant_id, ruta)]
        x0 = (i % self.n) * self.cell + PAD
        y0 = (i // self.n) * self.cell + PAD
        x1 = x0 + self.cell - 2 * PAD
        y1 = y0 + self.cell - 2 * PAD
        return (x0 / self.S, 1 - y1 / self.S, x1 / self.S, 1 - y0 / self.S)

    def material(self):
        if self._material is None:
            if self.semi:
                mr = Image.merge('RGB', (Image.new('L', self.rough.size, 0), self.rough,
                                         Image.new('L', self.rough.size, 0)))
                self._material = trimesh.visual.material.PBRMaterial(
                    name='Fasad_semi', baseColorTexture=self.albedo, normalTexture=self.normal,
                    metallicRoughnessTexture=mr, metallicFactor=1.0, roughnessFactor=1.0)
            else:
                self._material = trimesh.visual.material.PBRMaterial(
                    name='Fasad_atlas', baseColorTexture=self.albedo, metallicFactor=0.0, roughnessFactor=0.9)
        return self._material

    # -- ritning
    def _ruta_ram(self, k):
        i = self.index[k]
        x0 = (i % self.n) * self.cell
        y0 = (i // self.n) * self.cell
        return x0, y0, self.cell

    def _rita(self, k):
        x0, y0, c = self._ruta_ram(k)
        namn, ruta = k
        if namn == 'knut':
            v = dict(vagg='puts', farg=KNUT_FARG, fonster='inga', vaning_m=3.0)
        elif namn == 'skorsten_tegel':
            v = dict(vagg='tegel', farg=(150, 70, 52), fonster='inga', vaning_m=3.0)
        elif namn == 'skorsten_puts':
            v = dict(vagg='puts', farg=(232, 228, 218), fonster='inga', vaning_m=3.0)
        else:
            v = self.varianter[namn]
        bas = self._bas(v, c)
        img = Image.fromarray(bas[0]); self.albedo.paste(img, (x0, y0))
        if self.semi:
            self.normal.paste(Image.fromarray(bas[1]), (x0, y0))
            self.rough.paste(Image.fromarray(bas[2]), (x0, y0))
        if ruta != 'slat':
            self._oppningar(v, ruta, x0, y0, c)

    def _bas(self, v, c):
        """Väggytan för en ruta: (albedo, normal, roughness) som uint8-arrayer."""
        farg_ = tuple(v['farg'])
        if self.semi and v['vagg'] != 'glas':
            return self._foto(v, c)
        a = np.zeros((c, c, 3), np.uint8); a[:] = farg_
        im = Image.fromarray(a); d = ImageDraw.Draw(im)
        m = v['vagg']
        if m == 'panel_staende':
            for x in range(0, c, max(c // 14, 4)):
                d.line([(x, 0), (x, c)], fill=_morkare(farg_, 0.82), width=max(c // 120, 1))
        elif m == 'panel_liggande':
            for y in range(0, c, max(c // 14, 4)):
                d.line([(0, y), (c, y)], fill=_morkare(farg_, 0.82), width=max(c // 120, 1))
        elif m in ('tegel', 'tegel_gult'):
            rh = max(c // 22, 4); bw = max(c // 8, 8); fog = _morkare(farg_, 1.35)
            rng = np.random.default_rng(1)
            for r, y in enumerate(range(0, c, rh)):
                off = (bw // 2) * (r % 2)
                for x in range(-off, c, bw):
                    d.rectangle([x + 1, y + 1, x + bw - 1, y + rh - 1], fill=_morkare(farg_, rng.uniform(0.9, 1.08)))
                d.line([(0, y), (c, y)], fill=fog, width=1)
        elif m == 'plat':
            for x in range(0, c, max(c // 16, 4)):
                d.line([(x, 0), (x, c)], fill=_morkare(farg_, 0.8), width=max(c // 60, 2))
        elif m == 'glas':
            for y in range(c):
                t = y / c
                d.line([(0, y), (c, y)], fill=tuple(int(a_ * (1 - t) + b_ * t) for a_, b_ in zip((120, 150, 175), farg_)))
            d.rectangle([0, int(c * 0.88), c, c], fill=_morkare(farg_, 0.7))
            for x in (0, c // 2, c - 1):
                d.line([(x, 0), (x, c)], fill=(60, 64, 68), width=max(c // 60, 2))
        elif m in ('puts', 'betong'):
            n = np.random.default_rng(2).normal(0, 4, (c, c, 1))
            a = np.clip(np.asarray(im, float) + n, 0, 255).astype(np.uint8)
            return a, None, None
        return np.asarray(im), None, None

    def _laddat(self, tid):
        if tid not in self._tex:
            mapp = TEXTURER / tid
            ladda = lambda suffix, mode: Image.open(next(mapp.glob(f'*_{suffix}.jpg'))).convert(mode)
            self._tex[tid] = (ladda('Color', 'RGB'), ladda('NormalGL', 'RGB'), ladda('Roughness', 'L'))
        return self._tex[tid]

    def _foto(self, v, c):
        spec = KATALOG['material_semi'][v['vagg']]
        alb, nrm, rgh = self._laddat(spec['textur'])
        if spec.get('rotera'):
            alb = alb.rotate(90, expand=True); rgh = rgh.rotate(90, expand=True)
            n = np.asarray(nrm.rotate(90, expand=True)).astype(np.int16)
            # vinkelrät rotation: (x, y) -> (-y, x) i tangentrummet
            nx, ny = n[..., 0] - 128, n[..., 1] - 128
            nrm = Image.fromarray(np.stack([128 - ny, 128 + nx, n[..., 2]], -1).clip(0, 255).astype(np.uint8))
        px_x = c / FACK_M; px_y = c / float(v['vaning_m'])
        tw = max(int(spec['meter'] * px_x), 8); th = max(int(spec['meter'] * px_y), 8)
        def kakla(im):
            im = im.resize((tw, th), Image.LANCZOS)
            ut = Image.new(im.mode, (c, c))
            for y in range(0, c, th):
                for x in range(0, c, tw):
                    ut.paste(im, (x, y))
            return np.asarray(ut)
        a = kakla(alb).astype(float)
        if spec.get('ton'):
            lum = a.mean(-1, keepdims=True)
            a = lum / max(lum.mean(), 1) * np.array(v['farg'], float)
        return np.clip(a, 0, 255).astype(np.uint8), kakla(nrm), kakla(rgh)

    def _oppningar(self, v, ruta, x0, y0, c):
        """Ritar fönster eller dörr i rutan (y nedåt i bilden)."""
        d = ImageDraw.Draw(self.albedo)
        dn = ImageDraw.Draw(self.normal) if self.semi else None
        dr = ImageDraw.Draw(self.rough) if self.semi else None
        typ = v['fonster']
        ram = (244, 244, 240)
        glas_topp, glas_botten = ((150, 176, 196), (52, 62, 74)) if self.semi else ((112, 136, 156), (58, 70, 84))

        def R(fx0, fy0, fx1, fy1):     # rektangel i andelar av rutan, fy från BOTTEN
            return [x0 + fx0 * c, y0 + (1 - fy1) * c, x0 + fx1 * c, y0 + (1 - fy0) * c]

        def platt(box, rough):
            if dn is not None:
                dn.rectangle(box, fill=(128, 128, 255)); dr.rectangle(box, fill=rough)

        def glas(box):
            bx0, by0, bx1, by1 = box
            for y in range(int(by0), int(by1) + 1):
                t = (y - by0) / max(by1 - by0, 1)
                d.line([(bx0, y), (bx1, y)], fill=tuple(int(a * (1 - t) + b * t) for a, b in zip(glas_topp, glas_botten)))
            if dr is not None:
                dr.rectangle(box, fill=30)

        def fonster(fx0, fy0, fx1, fy1, sprojs=True, bage=False):
            box = R(fx0, fy0, fx1, fy1); t = max(c * 0.03, 2)
            platt([box[0] - t, box[1] - t, box[2] + t, box[3] + t], 150)
            d.rectangle([box[0] - t, box[1] - t, box[2] + t, box[3] + t], fill=ram)
            if bage:
                d.pieslice([box[0] - t, box[1] - t - (box[2] - box[0]) / 2, box[2] + t, box[1] + t + (box[2] - box[0]) / 2],
                           180, 360, fill=ram)
            glas(box)
            if bage:
                d.pieslice([box[0], box[1] - (box[2] - box[0]) / 2, box[2], box[1] + (box[2] - box[0]) / 2], 180, 360,
                           fill=glas_topp)
            if sprojs:
                mx = (box[0] + box[2]) / 2
                d.line([(mx, box[1]), (mx, box[3])], fill=ram, width=int(t * 0.6) + 1)
                my = box[1] + (box[3] - box[1]) * 0.33
                d.line([(box[0], my), (box[2], my)], fill=ram, width=int(t * 0.6) + 1)
            d.rectangle([box[0] - t * 1.6, box[3] + t, box[2] + t * 1.6, box[3] + t * 2.2], fill=(120, 124, 128))

        def dorr(bredd, hojd, farg_, glasruta=True, port=False):
            box = R(0.5 - bredd / 2, 0.0, 0.5 + bredd / 2, hojd); t = max(c * 0.025, 2)
            platt([box[0] - t, box[1] - t, box[2] + t, box[3]], 120)
            d.rectangle([box[0] - t, box[1] - t, box[2] + t, box[3]], fill=ram)
            d.rectangle(box, fill=farg_)
            if port:
                for y in np.linspace(box[1], box[3], 7)[1:-1]:
                    d.line([(box[0], y), (box[2], y)], fill=_morkare(farg_, 0.8), width=max(int(t * 0.5), 1))
            if glasruta:
                g = [box[0] + (box[2] - box[0]) * 0.3, box[1] + (box[3] - box[1]) * 0.12,
                     box[0] + (box[2] - box[0]) * 0.7, box[1] + (box[3] - box[1]) * 0.42]
                glas(g)

        mork = _morkare(v['farg'], 0.55) if sum(v['farg']) > 300 else (58, 42, 32)
        if ruta == 'fack':
            if typ == 'villa':
                fonster(0.32, 0.30, 0.68, 0.74)
            elif typ == 'rader':
                fonster(0.27, 0.28, 0.73, 0.78)
            elif typ == 'band':
                box = R(0.0, 0.32, 1.0, 0.80); glas(box); platt(box, 30)
                for fx in (0.0, 1 / 3, 2 / 3, 1.0):
                    xx = x0 + fx * c
                    d.line([(xx, box[1]), (xx, box[3])], fill=(70, 74, 78), width=max(c // 60, 2))
            elif typ == 'industri':
                box = R(0.1, 0.80, 0.9, 0.90); glas(box); platt(box, 30)
            elif typ == 'kyrka':
                fonster(0.40, 0.25, 0.60, 0.75, sprojs=False, bage=True)
            # glas: hela väggen är redan glas; lada/uthus: slät
        elif ruta == 'dorr':
            if typ in ('villa', 'rader'):
                dorr(0.30, 0.74, mork)
            elif typ in ('band', 'glas'):
                dorr(0.50, 0.72, (70, 80, 90))
            elif typ == 'lada':
                dorr(0.70, 0.80, _morkare(v['farg'], 0.85), glasruta=False)
                box = R(0.15, 0.0, 0.85, 0.80)
                d.line([(box[0], box[1]), (box[2], box[3])], fill=ram, width=max(c // 50, 2))
                d.line([(box[0], box[3]), (box[2], box[1])], fill=ram, width=max(c // 50, 2))
            elif typ == 'uthus':
                dorr(0.76, 0.78, (226, 226, 222), glasruta=False, port=True)
            elif typ == 'industri':
                dorr(0.60, 0.70, (200, 204, 208), glasruta=False, port=True)
            elif typ == 'kyrka':
                dorr(0.26, 0.60, (90, 60, 40), glasruta=False)


_MAT_FN = None
_TAK_CACHE = {}


def satt_mat(fn):
    """step3 ger sin mat()-funktion (sRGB -> linjärt glTF-material)."""
    global _MAT_FN
    _MAT_FN = fn


def tak(namn, semi):
    nyckel = (namn, semi)
    if nyckel in _TAK_CACHE:
        return _TAK_CACHE[nyckel]
    t = KATALOG['tak'][namn]
    if not semi or not t.get('semi'):
        m = _MAT_FN(f'Tak_{namn}', tuple(t['farg']), 0.8)
        m.uv_skala = None
    else:
        mapp = TEXTURER / t['semi']
        alb = Image.open(next(mapp.glob('*_Color.jpg'))).convert('RGB')
        if t.get('semi_ton'):
            a = np.asarray(alb, float); lum = a.mean(-1, keepdims=True)
            alb = Image.fromarray(np.clip(lum / max(lum.mean(), 1) * np.array(t['semi_ton'], float), 0, 255).astype(np.uint8))
        nrm = Image.open(next(mapp.glob('*_NormalGL.jpg'))).convert('RGB')
        rgh = Image.open(next(mapp.glob('*_Roughness.jpg'))).convert('L')
        storlek = (512, 512)
        alb, nrm, rgh = alb.resize(storlek), nrm.resize(storlek), rgh.resize(storlek)
        mr = Image.merge('RGB', (Image.new('L', storlek, 0), rgh, Image.new('L', storlek, 0)))
        m = trimesh.visual.material.PBRMaterial(name=f'Tak_semi_{namn}', baseColorTexture=alb, normalTexture=nrm,
                                                metallicRoughnessTexture=mr, metallicFactor=1.0, roughnessFactor=1.0)
        m.uv_skala = 1.0 / float(t.get('semi_m', 2.0))
    _TAK_CACHE[nyckel] = m
    return m
