"""Stenblock ur orienteringskartan (okarta.py klassa -> work/okarta_stenar.npy) som low-poly-stenar.

Varje sten är en ikosaeder (42 hörn) med slumpad radie per hörn, tillplattad och vriden;
slumpen är fast per sten så att ombyggen ger samma stenar. 30 % av höjden ligger under marken.
Stenarna läggs i glb-gruppen Stenar (Godot ger den kollision: skydd mot skott och sikt).
"""
import numpy as np
import trimesh

LITEN = dict(hojd=(1.0, 1.4), bredd=(1.2, 1.8))
STOR = dict(hojd=(1.8, 2.5), bredd=(2.2, 3.2))
GRUPP_RADIE = 3.0        # stenblocksgrupp: stenarna sprids så här långt från symbolen
UNDER_MARK = 0.3         # andel av stenens höjd under marken
KANT_RUFF = 0.18         # slumpad radie per hörn (andel)

_BAS = trimesh.creation.icosphere(subdivisions=1)


def stenmesh(seed, hojd, bredd, mitt_xz, mark):
    """En sten i Godot-koordinater (x, y upp, z syd) med mitten av foten i mitt_xz på höjden mark."""
    rng = np.random.default_rng(seed)
    V = _BAS.vertices * (1.0 + rng.uniform(-KANT_RUFF, KANT_RUFF, (len(_BAS.vertices), 1)))
    a = bredd / 2 * rng.uniform(0.8, 1.0)
    c = bredd / 2 * rng.uniform(0.6, 0.9)
    b = hojd / (2 * (1 - UNDER_MARK))      # halva totala höjden; (1 - UNDER_MARK) syns
    V = V * np.array([a, b, c])
    yaw = rng.uniform(0, 2 * np.pi)
    rot = np.array([[np.cos(yaw), 0, np.sin(yaw)], [0, 1, 0], [-np.sin(yaw), 0, np.cos(yaw)]])
    V = V @ rot.T
    V += np.array([mitt_xz[0], mark + hojd - b, mitt_xz[1]])
    return trimesh.Trimesh(V, _BAS.faces.copy(), process=False)


def stenmesh_exakt(seed, hojd, bredd, langd, riktning_grader, mitt_xz, mark):
    """En inmätt sten: höjd, bredd och längd i meter, längden riktning_grader från norr."""
    rng = np.random.default_rng(seed)
    V = _BAS.vertices * (1.0 + rng.uniform(-0.08, 0.08, (len(_BAS.vertices), 1)))
    b = hojd / (2 * (1 - UNDER_MARK))
    V = V * np.array([bredd / 2, b, langd / 2])        # längden längs z (nord-syd i Godot)
    yaw = -np.radians(riktning_grader)
    rot = np.array([[np.cos(yaw), 0, np.sin(yaw)], [0, 1, 0], [-np.sin(yaw), 0, np.cos(yaw)]])
    V = V @ rot.T + np.array([mitt_xz[0], mark + hojd - b, mitt_xz[1]])
    return trimesh.Trimesh(V, _BAS.faces.copy(), process=False)


def manuella(path, stenar):
    """Läser stenar_manuellt.json och tar bort automatiska stenar nära de inmätta."""
    import json
    d = json.load(open(path))
    lista = d.get('stenar', [])
    r = float(d.get('ersatt_radie', 6.0))
    for s in lista:
        if len(stenar):
            stenar = stenar[np.hypot(stenar[:, 0] - s['E'], stenar[:, 1] - s['N']) > r]
    return lista, stenar


def bygg_stenar(stenar, sample, h, to_world, add_merged, material, hinder, inmatta=()):
    """stenar: N x 3 (E, N, storlek 0 = block, 1 = stort block, 2 = stenblocksgrupp: 3–4 stora
    block inom GRUPP_RADIE m). hinder(E, N) -> True där stenar inte får ligga.
    Returnerar de stenar som lades ut (E, N, radie) för masken till step4."""
    lagda = []
    for i, s in enumerate(inmatta):
        x, z = to_world(s['E'], s['N'])
        mark = float(sample(h, [s['E']], [s['N']])[0])
        add_merged('Stenar', stenmesh_exakt(500 + i, s['hojd'], s['bredd'], s['langd'], s.get('riktning', 0.0),
                                            (x, z), mark), material)
        lagda.append((s['E'], s['N'], max(s['bredd'], s['langd']) / 2))
        print('inmätt sten:', s.get('namn', ''))
    for i, (E0, N0, storlek) in enumerate(stenar):
        rng = np.random.default_rng(1000 + i)
        if storlek == 2:
            n_ = int(rng.integers(3, 5))
            vinkel = rng.uniform(0, 2 * np.pi) + np.arange(n_) * 2 * np.pi / n_
            avst = rng.uniform(0.8, GRUPP_RADIE, n_)
            platser = [(E0 + np.cos(v) * a, N0 + np.sin(v) * a, STOR) for v, a in zip(vinkel, avst)]
        else:
            platser = [(E0, N0, STOR if storlek == 1 else LITEN)]
        for q, (E, N, s) in enumerate(platser):
            if hinder(E, N):
                continue
            hojd = rng.uniform(*s['hojd'])
            bredd = rng.uniform(*s['bredd'])
            x, z = to_world(E, N)
            mark = float(sample(h, [E], [N])[0])
            add_merged('Stenar', stenmesh(1000 + i * 8 + q, hojd, bredd, (x, z), mark), material)
            lagda.append((E, N, bredd / 2))
    print(f'stenar: {len(lagda)} stenar ur {len(stenar)} symboler')
    return np.array(lagda).reshape(-1, 3)
