"""Lekplatser (step3): OSM leisure=playground-ytor får redskap, olika i varje park.

Varje park slumpas med sitt OSM-id som frö: antal efter ytan, ett urval av redskapstyper (gungställning
med 2–4 gungor eller fågelbo, rutschkana, klätterställning med torn, tak, nät och rutschkana, snurra,
linbana i stora parker, sandlåda, basketkorg, gungbräda, bänkar), parkens egna färger, storlekar och
placering (största redskapen först, med luft emellan, vridna efter ytans längdriktning). Redskap som OSM
har ritat in (playground=swing/slide/sandpit/...) placeras där de står. Under gungor, rutschkanor och
tornet ligger sand eller gummi.

Varje redskap blir en egen nod i glb-gruppen `Lekplatser` (namn `Lek_<park>_<nr>_<typ>`, en mesh med
vertexfärger), så att spelet (PlaygroundBreak) kan trycka ner det när en vagn kör över det; underlaget
ligger i `Lekplatsunderlag` (sammanslaget). Ingen kollision.
"""
import zlib
import numpy as np
from shapely.geometry import Point, Polygon
import trimesh

FARGER = {   # sRGB
    'röd': (190, 45, 40), 'blå': (40, 90, 170), 'gul': (235, 190, 40), 'grön': (60, 140, 70),
    'orange': (225, 120, 35), 'lila': (120, 70, 150), 'turkos': (40, 150, 150), 'trä': (150, 105, 65),
    'mörkträ': (100, 70, 45), 'metall': (160, 165, 168), 'svart': (35, 35, 38), 'rostfri': (190, 192, 195),
    'sand': (210, 190, 140), 'gummi': (150, 60, 50), 'gummigrön': (70, 110, 70), 'asfalt': (70, 70, 72),
    'vit': (235, 235, 230),
}
TEMAN = [('röd', 'gul', 'blå'), ('grön', 'gul', 'trä'), ('blå', 'orange', 'metall'), ('lila', 'grön', 'trä'),
         ('turkos', 'röd', 'metall'), ('orange', 'blå', 'trä'), ('gul', 'grön', 'mörkträ'), ('röd', 'blå', 'trä')]
# typ: (fotavtrycksradie m, vikt, minsta parkyta m²)
TYPER = {
    'gunga': (2.6, 5, 0), 'rutschkana': (2.4, 3, 0), 'klatter': (3.2, 4, 120), 'snurra': (1.5, 2, 0),
    'linbana': (0, 3, 700), 'sandlada': (2.0, 4, 0), 'basket': (3.0, 2, 300), 'gungbrada': (1.8, 2, 0),
    'bank': (1.2, 2, 0), 'fagelbo': (2.4, 2, 0), 'lekstuga': (1.6, 1, 150),
    'lektag': (4.2, 2, 900), 'fjader': (0.9, 4, 0), 'rotator': (3.2, 2, 600),
}
OSM_TYP = {'swing': 'gunga', 'basketswing': 'fagelbo', 'slide': 'rutschkana', 'sandpit': 'sandlada',
           'climbingframe': 'klatter', 'structure': 'klatter', 'roundabout': 'snurra', 'zipwire': 'linbana',
           'seesaw': 'gungbrada', 'playhouse': 'lekstuga', 'basketball': 'basket',
           'aerialrotator': 'rotator', 'spinning_disc': 'snurra', 'springy': 'fjader', 'train': 'lektag'}
MAX_PER_TYP = {'lektag': 1, 'rotator': 2, 'basket': 1, 'lekstuga': 1, 'linbana': 1}
STOR_PARK_M2 = 1500     # större lekplatser: fler redskap (en per STOR_YTA_PER_REDSKAP m², högst STOR_MAX) och trästaket
STOR_YTA_PER_REDSKAP = 110.0
STOR_MAX = 40
STAKET_BIT_M = 10.0     # staketet runt stora lekplatser i bitar (egna noder, vältbara var för sig)
STAKET_OPPNING_M = 3.0  # en öppning var STAKET_OPPNING_VAR_M
STAKET_OPPNING_VAR_M = 28.0


def _srgb2lin(c):
    c = np.asarray(c, float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


class _Bit:
    """Samlar primitiver med färg i redskapets egna koordinater (x höger, y upp, z framåt)."""

    def __init__(self):
        self.delar = []

    def _farg(self, m, farg):
        rgb = np.round(_srgb2lin(FARGER[farg]) * 255).astype(np.uint8)
        m.visual = trimesh.visual.ColorVisuals(m, vertex_colors=np.tile(np.r_[rgb, 255], (len(m.vertices), 1)))
        self.delar.append(m)

    def box(self, mitt, storlek, farg, rot=None):
        T = trimesh.transformations.translation_matrix(mitt)
        if rot is not None:
            T = T @ rot
        self._farg(trimesh.creation.box(extents=storlek, transform=T), farg)

    def ror(self, a, b, r, farg, sek=8):
        a, b = np.asarray(a, float), np.asarray(b, float)
        if np.linalg.norm(b - a) < 1e-4:
            return
        self._farg(trimesh.creation.cylinder(radius=r, segment=[a, b], sections=sek), farg)

    def skiva(self, mitt, r, tjock, farg, sek=16):
        T = trimesh.transformations.translation_matrix(mitt) @ trimesh.transformations.rotation_matrix(np.pi / 2, [1, 0, 0])
        self._farg(trimesh.creation.cylinder(radius=r, height=tjock, sections=sek, transform=T), farg)

    def kon(self, mitt, r, hojd, farg, sek=4):
        T = trimesh.transformations.translation_matrix(mitt) @ trimesh.transformations.rotation_matrix(-np.pi / 2, [1, 0, 0]) \
            @ trimesh.transformations.rotation_matrix(np.pi / 4, [0, 0, 1])
        self._farg(trimesh.creation.cone(radius=r, height=hojd, sections=sek, transform=T), farg)

    def mesh(self):
        return trimesh.util.concatenate(self.delar) if self.delar else None


# ---------- redskapen ----------

def gunga(rng, tema, fagelbo=False):
    b = _Bit()
    n = 1 if fagelbo else int(rng.integers(2, 5))
    bredd = (1.8 if fagelbo else n * 1.1) + 0.6
    h = rng.uniform(2.2, 2.6)
    ram = tema[2] if tema[2] in ('trä', 'mörkträ', 'metall') else 'metall'
    for x in (-bredd / 2, bredd / 2):
        for z in (-1.0, 1.0):
            b.ror([x, 0, z], [x, h, 0], 0.06, ram)
    b.ror([-bredd / 2 - 0.1, h, 0], [bredd / 2 + 0.1, h, 0], 0.07, ram)
    if fagelbo:
        b.skiva([0, 0.55, 0], 0.55, 0.12, tema[1], sek=20)
        for a in np.linspace(0, 2 * np.pi, 4, endpoint=False):
            b.ror([0.4 * np.cos(a), 0.58, 0.4 * np.sin(a)], [0.3 * np.cos(a), h, 0.0], 0.012, 'svart')
    else:
        for i in range(n):
            x = -bredd / 2 + 0.6 + (i + 0.5) * (bredd - 1.2) / n
            sits = tema[int(rng.integers(0, 2))] if rng.random() < 0.6 else 'svart'
            b.box([x, 0.45, 0], [0.48, 0.05, 0.22], sits)
            for dx in (-0.2, 0.2):
                b.ror([x + dx, 0.47, 0], [x + dx, h, 0], 0.012, 'metall')
    return b, max(bredd / 2, 1.2) + 0.8


def rutschkana(rng, tema, b=None, ofs=None, h=None, med_stege=True):
    egen = b is None
    b = b or _Bit()
    ofs = np.zeros(3) if ofs is None else np.asarray(ofs, float)
    h = h or rng.uniform(1.0, 1.6)
    farg = tema[int(rng.integers(0, 3))] if rng.random() < 0.8 else 'rostfri'
    farg = farg if farg not in ('trä', 'mörkträ', 'metall') else 'rostfri'
    L = h * rng.uniform(2.0, 2.5)
    vinkel = np.arctan2(h, L)
    if med_stege:
        b.box(ofs + [0, h - 0.04, -0.4], [0.8, 0.08, 0.8], 'trä' if rng.random() < 0.5 else 'metall')
        for x in (-0.3, 0.3):
            b.ror(ofs + [x, 0, -0.9], ofs + [x, h + 0.7, -0.7], 0.035, 'metall')
        for y in np.arange(0.3, h, 0.28):
            b.ror(ofs + [-0.3, y, -0.9 + 0.2 * y / h], ofs + [0.3, y, -0.9 + 0.2 * y / h], 0.02, 'metall')
    rot = trimesh.transformations.rotation_matrix(vinkel, [1, 0, 0])
    mitt = ofs + [0, h / 2, L / 2]
    b.box(mitt, [0.55, 0.05, np.hypot(L, h)], farg, rot)
    for x in (-0.3, 0.3):
        b.box(mitt + [x, 0.12, 0], [0.04, 0.22, np.hypot(L, h)], farg, rot)
    return (b, max(L, 2.0) / 2 + 1.0) if egen else b


def klatter(rng, tema):
    b = _Bit()
    s = rng.uniform(1.4, 2.0)
    h = rng.uniform(1.2, 1.7)
    stolpe = 'trä' if rng.random() < 0.6 else 'metall'
    for x in (-s / 2, s / 2):
        for z in (-s / 2, s / 2):
            b.box([x, (h + 1.4) / 2, z], [0.1, h + 1.4, 0.1], stolpe)
    b.box([0, h, 0], [s, 0.08, s], 'trä')
    # räcken/väggar på två sidor
    b.box([0, h + 0.45, -s / 2], [s, 0.7, 0.04], tema[1])
    b.box([-s / 2, h + 0.45, 0], [0.04, 0.7, s], tema[2] if tema[2] not in ('metall',) else tema[0])
    # tak
    b.kon([0, h + 1.4, 0], s * 0.8, rng.uniform(0.7, 1.1), tema[0])
    # klätternät eller klättervägg på högersidan
    if rng.random() < 0.5:
        for i in range(5):
            y = h * (i + 0.5) / 5
            b.ror([s / 2 + 0.05, y, -s / 2], [s / 2 + 0.05 + 0.35 * (1 - y / h), y, s / 2], 0.015, 'svart')
        for z in np.linspace(-s / 2, s / 2, 4):
            b.ror([s / 2 + 0.4, 0, z], [s / 2 + 0.05, h, z], 0.015, 'svart')
    else:
        rot = trimesh.transformations.rotation_matrix(-0.35, [0, 0, 1])
        b.box([s / 2 + 0.25, h / 2, 0], [0.06, h * 1.1, s * 0.9], tema[1], rot)
        for y in np.linspace(0.3, h - 0.2, 4):
            b.box([s / 2 + 0.25 + (h / 2 - y) * 0.35, y, rng.uniform(-0.3, 0.3)], [0.12, 0.1, 0.12], tema[2] if tema[2] != 'metall' else 'gul')
    # rutschkana fram
    rutschkana(rng, tema, b, [0, 0, s / 2], h, med_stege=False)
    # en andra, lägre plattform med bro i större varianter
    if rng.random() < 0.35:
        b.box([-s - 0.9, h * 0.65, 0], [1.2, 0.08, 1.2], 'trä')
        for x in (-s - 1.45, -s - 0.35):
            for z in (-0.55, 0.55):
                b.box([x, h * 0.65 / 2, z], [0.08, h * 0.65, 0.08], stolpe)
        b.box([-s / 2 - 0.35, (h + h * 0.65) / 2, 0], [0.8, 0.05, 0.7], 'trä')
    return b, s / 2 + h * 2.4 + 0.5


def snurra(rng, tema):
    b = _Bit()
    r = rng.uniform(0.8, 1.1)
    b.skiva([0, 0.25, 0], r, 0.08, tema[0], sek=20)
    b.ror([0, 0, 0], [0, 0.25, 0], 0.12, 'metall')
    b.ror([0, 0.29, 0], [0, 0.95, 0], 0.04, 'metall')
    for a in np.linspace(0, 2 * np.pi, 4, endpoint=False):
        b.ror([0, 0.9, 0], [r * 0.85 * np.cos(a), 0.9, r * 0.85 * np.sin(a)], 0.025, tema[1])
        b.ror([r * 0.85 * np.cos(a), 0.29, r * 0.85 * np.sin(a)], [r * 0.85 * np.cos(a), 0.9, r * 0.85 * np.sin(a)], 0.025, tema[1])
    return b, r + 0.8


def linbana(rng, tema, langd):
    b = _Bit()
    h0, h1 = 3.0, 2.4
    b.box([0, 0.5, 0], [1.2, 0.1, 1.2], 'trä')
    for x in (-0.5, 0.5):
        b.box([x, 0.25, -0.5], [0.08, 0.5, 0.08], 'trä')
        b.box([x, 0.25, 0.5], [0.08, 0.5, 0.08], 'trä')
    b.ror([0, 0, -0.7], [0, h0, 0], 0.08, 'metall')
    b.ror([0, 0, langd + 0.7], [0, h1, langd], 0.08, 'metall')
    b.ror([0, h0 - 0.1, 0], [0, h1 - 0.1, langd], 0.012, 'svart', sek=4)
    b.ror([0, h0 - 0.1, 0.6], [0, 0.7, 0.6], 0.012, 'svart', sek=4)
    b.skiva([0, 0.65, 0.6], 0.2, 0.06, tema[0])
    return b, 0


def sandlada(rng, tema):
    b = _Bit()
    s = rng.uniform(2.2, 3.6)
    t = 'trä' if rng.random() < 0.7 else 'mörkträ'
    for z in (-s / 2, s / 2):
        b.box([0, 0.15, z], [s + 0.2, 0.3, 0.12], t)
    for x in (-s / 2, s / 2):
        b.box([x, 0.15, 0], [0.12, 0.3, s], t)
    b.box([0, 0.08, 0], [s, 0.16, s], 'sand')
    if rng.random() < 0.4:   # ett sandbord eller en hink
        b.box([s * 0.2, 0.35, -s * 0.15], [0.6, 0.06, 0.4], tema[0])
    return b, s / 2 + 0.8


def basket(rng, tema):
    b = _Bit()
    b.box([0, 0.01, 1.6], [5.5, 0.03, 5.0], 'asfalt')
    b.ror([0, 0, -0.5], [0, 3.1, -0.5], 0.07, 'metall')
    b.ror([0, 3.1, -0.5], [0, 3.1, -0.1], 0.05, 'metall')
    b.box([0, 3.35, -0.05], [1.2, 0.8, 0.05], 'vit')
    for a in np.linspace(0, 2 * np.pi, 10, endpoint=False):
        a2 = a + 2 * np.pi / 10
        b.ror([0.23 * np.cos(a), 3.05, 0.25 + 0.23 * np.sin(a)], [0.23 * np.cos(a2), 3.05, 0.25 + 0.23 * np.sin(a2)],
              0.012, 'orange', sek=4)
    return b, 3.0


def gungbrada(rng, tema):
    b = _Bit()
    L = rng.uniform(2.6, 3.4)
    b.box([0, 0.25, 0], [0.3, 0.5, 0.3], 'metall')
    vinkel = rng.uniform(-0.25, 0.25)
    b.box([0, 0.5, 0], [L, 0.06, 0.3], tema[0], trimesh.transformations.rotation_matrix(vinkel, [0, 0, 1]))
    for sx in (-1, 1):
        x = sx * (L / 2 - 0.3)
        y = 0.5 + np.sin(vinkel) * x
        b.ror([x, y + 0.03, -0.12], [x, y + 0.35, -0.12], 0.02, tema[1])
        b.ror([x, y + 0.03, 0.12], [x, y + 0.35, 0.12], 0.02, tema[1])
    return b, L / 2 + 0.5


def bank(rng, tema):
    b = _Bit()
    t = 'trä' if rng.random() < 0.6 else 'mörkträ'
    b.box([0, 0.45, 0], [1.6, 0.05, 0.42], t)
    b.box([0, 0.75, -0.2], [1.6, 0.3, 0.04], t)
    for x in (-0.65, 0.65):
        b.box([x, 0.22, 0], [0.06, 0.45, 0.4], 'svart')
    return b, 1.1


def lekstuga(rng, tema):
    b = _Bit()
    b.box([0, 0.6, 0], [1.4, 1.2, 1.2], tema[0] if rng.random() < 0.5 else 'röd')
    b.box([0, 0.5, 0.61], [0.5, 0.8, 0.02], 'mörkträ')
    b.box([0.4, 0.75, 0.61], [0.35, 0.35, 0.02], 'vit')
    b.kon([0, 1.55, 0], 1.05, 0.7, 'svart')
    return b, 1.4


def lektag(rng, tema):
    """Lektåg (Folkparken i Norrköping, efter Mapillary): lok med hytt och skorsten, två öppna vagnar."""
    b = _Bit()
    farg = 'röd' if rng.random() < 0.6 else tema[0]
    farg = farg if farg not in ('trä', 'mörkträ', 'metall') else 'röd'
    z = -2.6
    # loket
    b.box([0, 0.55, z + 0.9], [1.2, 0.7, 1.8], farg)                     # panna
    b.ror([0, 0.95, z + 0.2], [0, 0.95, z + 1.9], 0.42, farg, sek=12)
    b.box([0, 1.15, z - 0.2], [1.25, 1.6, 1.0], farg)                    # hytt
    b.box([0, 2.0, z - 0.2], [1.45, 0.1, 1.2], 'svart')                  # tak
    b.ror([0, 1.3, z + 1.55], [0, 1.85, z + 1.55], 0.14, 'svart')        # skorsten
    b.box([0, 1.25, z + 0.31], [0.8, 0.5, 0.02], 'vit')                  # hyttfönster
    for zz in (z - 0.4, z + 0.5, z + 1.4):
        for x in (-0.62, 0.62):
            b.skiva([x, 0.32, zz], 0.3, 0.1, 'svart', sek=12)
    # vagnarna
    for k in range(2):
        zz = z + 3.0 + k * 1.9
        b.box([0, 0.55, zz], [1.2, 0.7, 1.6], farg if k == 0 else tema[1])
        b.box([0, 0.8, zz], [1.0, 0.25, 1.4], 'svart')                    # öppen ovanifrån
        b.box([0, 0.75, zz], [0.9, 0.06, 0.25], 'trä')                    # sittbräda
        b.box([0, 0.35, zz - 0.95], [0.2, 0.12, 0.4], 'svart')            # koppel
        for zz2 in (zz - 0.5, zz + 0.5):
            for x in (-0.62, 0.62):
                b.skiva([x, 0.28, zz2], 0.26, 0.1, 'svart', sek=12)
    return b, 4.2


def fjader(rng, tema):
    """Fjädergunga: ett djur eller en båt på en kraftig spiralfjäder."""
    b = _Bit()
    f = tema[int(rng.integers(0, 3))]
    f = f if f not in ('trä', 'mörkträ', 'metall') else 'blå'
    for i in range(6):   # fjädern
        y = 0.08 + i * 0.07
        b.ror([-0.1, y, 0], [0.1, y + 0.035, 0], 0.08, 'svart', sek=6)
    b.box([0, 0.0, 0], [0.4, 0.04, 0.4], 'metall')
    if rng.random() < 0.5:   # häst/djur: kropp, hals och huvud
        b.box([0, 0.62, 0], [0.28, 0.32, 0.8], f)
        b.box([0, 0.9, 0.35], [0.22, 0.4, 0.2], f)
        b.box([0, 1.05, 0.5], [0.2, 0.18, 0.3], f)
    else:                    # båt/våg: en skålad sits
        b.box([0, 0.6, 0], [0.5, 0.25, 0.9], f)
        b.box([0, 0.85, -0.38], [0.5, 0.3, 0.08], f)
    b.ror([-0.2, 0.95, 0.15], [0.2, 0.95, 0.15], 0.02, 'gul' if f != 'gul' else 'röd')
    return b, 0.9


def rotator(rng, tema):
    """Hög snurrställning (OSM playground=aerialrotator): en gul stolpe med en arm som man hänger i."""
    b = _Bit()
    h = rng.uniform(3.2, 3.8)
    stolpe = 'gul' if rng.random() < 0.7 else tema[0]
    b.ror([0, 0, 0], [0, h, 0], 0.09, stolpe)
    b.skiva([0, h + 0.05, 0], 0.18, 0.12, 'röd')
    L = rng.uniform(1.6, 2.2)
    for a in (0.0, np.pi):
        x = L * np.cos(a)
        b.ror([0, h - 0.15, 0], [x, h - 0.5, 0], 0.045, 'röd')
        b.ror([x, h - 0.5, 0], [x, 0.9, 0], 0.012, 'svart', sek=4)
        b.box([x, 0.9, 0], [0.45, 0.05, 0.22], 'svart')
    return b, L + 1.0


def staket(langd, rng):
    """Trästaket med två slanor (Folkparken): stolpar var 2,4 m längs lokala z, 0 .. langd."""
    b = _Bit()
    n = max(1, int(np.ceil(langd / 2.4)))
    for i in range(n + 1):
        z = langd * i / n
        b.box([0, 0.5, z], [0.12, 1.0, 0.12], 'trä')
    for y in (0.45, 0.85):
        b.box([0, y, langd / 2], [0.06, 0.12, langd], 'trä')
    return b


BYGG = {'gunga': gunga, 'fagelbo': lambda r, t: gunga(r, t, True), 'rutschkana': rutschkana, 'klatter': klatter,
        'snurra': snurra, 'sandlada': sandlada, 'basket': basket, 'gungbrada': gungbrada, 'bank': bank,
        'lekstuga': lekstuga, 'lektag': lektag, 'fjader': fjader, 'rotator': rotator}


# ---------- parkerna ----------

def _frö(osm_id, poly):
    return zlib.crc32(f'{osm_id}:{poly.centroid.x:.0f}:{poly.centroid.y:.0f}'.encode())


def _langdriktning(poly):
    mrr = poly.minimum_rotated_rectangle
    c = np.array(mrr.exterior.coords)[:4]
    e = [c[1] - c[0], c[2] - c[1]]
    lang = max(e, key=np.linalg.norm)
    return np.arctan2(lang[1], lang[0]), float(max(np.linalg.norm(e[0]), np.linalg.norm(e[1])))


def program(rng, yta, lang):
    n = int(np.clip(yta / 55.0, 2, 9))
    if yta >= STOR_PARK_M2:   # stora lekplatser fylls (Folkparken i Norrköping, 4 200 m²)
        n = int(np.clip(yta / STOR_YTA_PER_REDSKAP, 9, STOR_MAX))
    typer = [t for t, (_, _, minyta) in TYPER.items() if yta >= minyta and t != 'linbana']
    vikt = np.array([TYPER[t][1] for t in typer], float)
    val = []
    for _ in range(n):
        if vikt.sum() <= 0:
            break
        p = vikt / vikt.sum()
        t = typer[rng.choice(len(typer), p=p)]
        val.append(t)
        if val.count(t) >= MAX_PER_TYP.get(t, 99):
            vikt[typer.index(t)] = 0.0
            continue
        vikt[typer.index(t)] *= 0.35 if n <= 9 else 0.7   # mindre sannolikt igen: blandning
    if yta >= TYPER['linbana'][2] and lang > 26 and rng.random() < 0.6:
        val.insert(0, 'linbana')
    return val


def bygg(lekplatser, redskap, sample, h, to_world, scene, add_merged, mat, hinder=None):
    """lekplatser: [(Polygon SWEREF, taggar, osm-id)], redskap: [(Point, taggar)].
    hinder(E, N) -> True där inget får stå (hus, väg)."""
    if not lekplatser:
        return []
    underlag = {'sand': mat('Lek_sand', FARGER['sand'], 1.0), 'gummi': mat('Lek_gummi', FARGER['gummi'], 0.9),
                'gummigrön': mat('Lek_gummigron', FARGER['gummigrön'], 0.9)}
    platser = []
    n_redskap = 0
    for poly, t, osm_id in lekplatser:
        if poly.is_empty or poly.area < 30:
            continue
        rng = np.random.default_rng(_frö(osm_id, poly))
        tema = TEMAN[int(rng.integers(0, len(TEMAN)))]
        tema = tuple(rng.permutation(list(tema)))
        mark = ['sand', 'gummi', 'gummigrön'][int(rng.integers(0, 3))]
        vinkel, lang = _langdriktning(poly)
        inne = poly.buffer(-0.8) if poly.buffer(-0.8).area > 10 else poly
        lista = [(OSM_TYP[tt.get('playground')], np.array(p.coords[0]), True)
                 for p, tt in redskap if tt.get('playground') in OSM_TYP and poly.buffer(2.0).contains(p)]
        osm_typer = [l[0] for l in lista]
        for typ in program(rng, poly.area, lang):   # OSM:s redskap räknas av, ett för ett
            if typ in osm_typer:
                osm_typer.remove(typ)
            elif [l[0] for l in lista].count(typ) < MAX_PER_TYP.get(typ, 99):
                lista.append((typ, None, False))
        lista.sort(key=lambda x: -TYPER[x[0]][0])
        placerade = []   # (punkt, radie)
        nr = 0
        for typ, pos, fast in lista:
            r = TYPER[typ][0]
            yaw = vinkel + (np.pi / 2) * int(rng.integers(0, 4)) + rng.uniform(-0.15, 0.15)
            if typ == 'linbana':
                langd = min(lang - 6, 30.0)
                b, _ = linbana(rng, tema, langd)
                # längs ytans längdriktning, med start i ena änden
                c = np.array(poly.centroid.coords[0])
                d = np.array([np.cos(vinkel), np.sin(vinkel)])
                pos = c - d * langd / 2
                yaw = vinkel
                ok = all(np.linalg.norm(pos + d * s - q) > rq + 1.0 for q, rq in placerade for s in np.linspace(0, langd, 6))
                if not ok:
                    continue
                placerade += [(pos + d * s, 1.2) for s in np.linspace(0, langd, 6)]
            else:
                if pos is None:
                    pos = None
                    for _ in range(40):
                        minx, miny, maxx, maxy = inne.bounds
                        q = np.array([rng.uniform(minx, maxx), rng.uniform(miny, maxy)])
                        if not inne.contains(Point(q)):
                            continue
                        if any(np.linalg.norm(q - p) < r + rp + 1.0 for p, rp in placerade):
                            continue
                        if hinder is not None and hinder(*q):
                            continue
                        pos = q
                        break
                    if pos is None:
                        continue
                b, r = BYGG[typ](rng, tema)
                placerade.append((pos, r))
            m = b.mesh()
            if m is None:
                continue
            # lokala axlar: z framåt (SWEREF-riktning yaw), x höger; värld: x öst, z = −N
            fram = np.array([np.cos(yaw), np.sin(yaw)])
            hoger = np.array([fram[1], -fram[0]])
            wx, wz = to_world(pos[0], pos[1])
            y0 = float(sample(h, [pos[0]], [pos[1]])[0])
            R = np.eye(4)
            R[:3, 0] = [hoger[0], 0, -hoger[1]]
            R[:3, 1] = [0, 1, 0]
            R[:3, 2] = [fram[0], 0, -fram[1]]
            if np.linalg.det(R[:3, :3]) < 0:
                R[:3, 0] *= -1
            R[:3, 3] = [wx, y0, wz]
            m.apply_transform(R)
            namn = f'Lek_{osm_id}_{nr}_{typ}'
            scene.add_geometry(m, node_name=namn, geom_name=namn, parent_node_name='Lekplatser')
            nr += 1
            n_redskap += 1
            if typ in ('gunga', 'fagelbo', 'rutschkana', 'klatter', 'snurra', 'linbana') and r > 0:
                disk = trimesh.creation.cylinder(radius=r * 0.8, height=0.04, sections=20)
                disk.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [1, 0, 0]))
                disk.apply_translation([wx, y0 + 0.02, wz])
                add_merged('Lekplatsunderlag', disk, underlag[mark])
        if poly.area >= STOR_PARK_M2:   # trästaket runt om, i bitar med öppningar
            ring = poly.exterior
            s_ = 0.0
            k = 0
            while s_ < ring.length - 1.0:
                if (s_ % STAKET_OPPNING_VAR_M) < STAKET_OPPNING_M:
                    s_ += STAKET_OPPNING_M
                    continue
                L = min(STAKET_BIT_M, ring.length - s_, STAKET_OPPNING_VAR_M - (s_ % STAKET_OPPNING_VAR_M))
                a = np.array(ring.interpolate(s_).coords[0])
                e = np.array(ring.interpolate(s_ + L).coords[0])
                mitt = (a + e) / 2
                if L > 1.0 and not (hinder is not None and hinder(*mitt)):
                    m = staket(float(np.linalg.norm(e - a)), rng).mesh()
                    fram = (e - a) / max(np.linalg.norm(e - a), 1e-6)
                    hoger = np.array([fram[1], -fram[0]])
                    wx, wz = to_world(a[0], a[1])
                    y0 = float(min(sample(h, [a[0], e[0]], [a[1], e[1]])))
                    R = np.eye(4)
                    R[:3, 0] = [hoger[0], 0, -hoger[1]]
                    R[:3, 1] = [0, 1, 0]
                    R[:3, 2] = [fram[0], 0, -fram[1]]
                    if np.linalg.det(R[:3, :3]) < 0:
                        R[:3, 0] *= -1
                    R[:3, 3] = [wx, y0, wz]
                    m.apply_transform(R)
                    namn = f'Lek_{osm_id}_staket{k}_staket'
                    scene.add_geometry(m, node_name=namn, geom_name=namn, parent_node_name='Lekplatser')
                    k += 1
                s_ += L
        platser.append((poly, [p for p, _ in placerade]))
    print(f'lekplatser: {len(platser)} parker, {n_redskap} redskap')
    return platser
