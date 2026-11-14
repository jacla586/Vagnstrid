"""Gatumöbler ur Mapillarys kartobjekt (vagkant.py `_mly_mobler`): papperskorgar, bänkar, elskåp,
cykelställ, brandposter, brevlådor och elstolpar i trä, vältbara (valtbart.py, en mall per variant).

Mallarna: foten i origo, x framåt (mot närmaste väg: bänkens sittsida, skåpets dörr), y upp. Varianten
väljs stabilt per läge (crc32). Lågpoly av lådor och prismor, färger i sRGB (mat()).
"""
import zlib

import numpy as np
import trimesh

from jarnvag import ladar
from valtbart import lador_mesh

# Mapillary object_value -> (sort, avstånd från vägkanten m, dubblettavstånd m)
SORTER = {
    'object--trash-can': ('Papperskorg', 0.8, 3.0),
    'object--bench': ('Bank', 1.2, 3.0),
    'object--junction-box': ('Elskap', 1.0, 3.0),
    'object--bike-rack': ('Cykelstall', 1.5, 4.0),
    'object--fire-hydrant': ('Brandpost', 0.8, 5.0),
    'object--mailbox': ('Brevlada', 0.8, 3.0),
    'object--support--utility-pole': ('Elstolpe', 2.0, 12.0),
}
VARIANTER = {'Papperskorg': 'abc', 'Bank': 'ab', 'Elskap': 'ab', 'Cykelstall': 'a', 'Brandpost': 'a',
             'Brevlada': 'a', 'Elstolpe': 'ab'}


def variant(sort, E, N):
    v = VARIANTER[sort]
    return f'{sort}_{v[zlib.crc32(f"{round(E)},{round(N)}".encode()) % len(v)]}'


def _lada(cx, cz, hx, hz, y0, y1):
    return lador_mesh(ladar([[cx, cz]], [[1.0, 0.0]], hx, hz, y0, y1), botten=True)


def _prisma(cx, cz, r, y0, y1, n=10):
    """Stående prisma (cylinder) med lock och botten."""
    a = np.linspace(0, 2 * np.pi, n, endpoint=False)
    ring = np.c_[cx + r * np.cos(a), cz + r * np.sin(a)]
    V = np.vstack([np.c_[ring[:, 0], np.full(n, y0), ring[:, 1]], np.c_[ring[:, 0], np.full(n, y1), ring[:, 1]],
                   [[cx, y0, cz], [cx, y1, cz]]])
    F = []
    for i in range(n):
        j = (i + 1) % n
        F += [[i, n + j, j], [i, n + i, n + j]]          # sidor (utåt)
        F += [[2 * n, i, j], [2 * n + 1, n + j, n + i]]  # botten, lock
    m = trimesh.Trimesh(V, np.array(F), process=False)
    m.fix_normals()
    return m


def _slå_ihop(lista):
    return trimesh.util.concatenate(lista)


def skapa_mallar(valt, mat):
    """Alla varianters mallar i valt (valtbart.Samling)."""
    gron = mat('Mobel_gron', (46, 84, 56), 0.5)
    svart = mat('Mobel_svart', (36, 37, 38), 0.5)
    gra = mat('Mobel_gra', (120, 124, 126), 0.45)
    tra = mat('Mobel_tra', (128, 92, 60), 0.85)
    betong = mat('Mobel_betong', (158, 156, 150), 0.95)
    elgron = mat('Elskap_gron', (112, 124, 108), 0.6)
    beige = mat('Elskap_beige', (196, 186, 164), 0.6)
    rod = mat('Brandpost_rod', (178, 34, 30), 0.5)
    gul = mat('Brevlada_gul', (236, 186, 20), 0.5)
    stolpe = mat('Elstolpe_tra', (92, 72, 52), 0.9)
    vit = mat('Isolator', (230, 230, 226), 0.3)

    def m(typ, delar):
        if not valt.har_mall(typ):
            valt.mall(typ, delar)

    # papperskorgar
    m('Papperskorg_a', [(_lada(0, 0, 0.03, 0.03, -0.3, 1.0), gra),                          # grön korg på stolpe
                        (_prisma(0.22, 0, 0.2, 0.45, 0.95), gron), (_prisma(0.22, 0, 0.21, 0.93, 0.97), svart)])
    m('Papperskorg_b', [(_prisma(0, 0, 0.27, 0.0, 0.92), svart), (_prisma(0, 0, 0.29, 0.88, 0.98), gra)])
    m('Papperskorg_c', [(_lada(0, 0, 0.25, 0.25, 0.0, 0.85), tra), (_lada(0, 0, 0.27, 0.27, 0.85, 0.92), svart)])
    # bänkar: sitter mot +x
    ben = _slå_ihop([_lada(0, z, 0.24, 0.03, 0.0, 0.42) for z in (-0.75, 0.75)] +
                    [_lada(-0.26, z, 0.03, 0.03, 0.0, 0.82) for z in (-0.75, 0.75)])
    sits = _slå_ihop([_lada(x, 0, 0.06, 0.95, 0.42, 0.46) for x in (-0.15, 0.0, 0.15)] +
                     [_lada(-0.27, 0, 0.02, 0.95, y, y + 0.08) for y in (0.55, 0.7)])
    m('Bank_a', [(ben, svart), (sits, tra)])
    m('Bank_b', [(_slå_ihop([_lada(0, z, 0.22, 0.12, 0.0, 0.4) for z in (-0.7, 0.7)]), betong),
                 (_lada(0, 0, 0.24, 1.0, 0.4, 0.47), tra)])
    # elskåp: dörren mot +x
    m('Elskap_a', [(_lada(0, 0, 0.18, 0.45, -0.1, 1.25), elgron), (_lada(0, 0, 0.21, 0.48, 1.25, 1.3), gra)])
    m('Elskap_b', [(_lada(0, 0, 0.15, 0.3, -0.1, 0.95), beige), (_lada(0, 0, 0.17, 0.32, 0.95, 1.0), gra)])
    # cykelställ: fem bågar på rad längs z, cyklarna står längs x
    bagar = []
    for z in np.arange(-1.6, 1.61, 0.8):
        bagar += [_lada(x, z, 0.025, 0.025, -0.2, 0.8) for x in (-0.3, 0.3)] + [_lada(0, z, 0.33, 0.025, 0.75, 0.8)]
    m('Cykelstall_a', [(_slå_ihop(bagar), gra)])
    m('Brandpost_a', [(_prisma(0, 0, 0.1, -0.1, 0.75), rod), (_prisma(0, 0, 0.12, 0.75, 0.82), rod),
                      (_lada(0, 0, 0.13, 0.03, 0.45, 0.52), rod)])
    m('Brevlada_a', [(_lada(0, 0, 0.03, 0.03, -0.3, 0.95), gra), (_lada(0.04, 0, 0.17, 0.22, 0.95, 1.3), gul)])
    # elstolpar i trä: tre isolatorer på en tvärslå (a) eller bara toppen (b, lågspänning)
    m('Elstolpe_a', [(_prisma(0, 0, 0.12, -0.5, 9.0, 8), stolpe), (_lada(0, 0, 0.06, 0.9, 8.3, 8.42), stolpe),
                     (_slå_ihop([_prisma(0, z, 0.05, 8.42, 8.6, 6) for z in (-0.8, 0.0, 0.8)]), vit)])
    m('Elstolpe_b', [(_prisma(0, 0, 0.11, -0.5, 8.0, 8), stolpe),
                     (_slå_ihop([_lada(0.12, z, 0.05, 0.03, y, y + 0.08) for z, y in ((0.0, 7.6), (0.0, 7.2))]), vit)])
