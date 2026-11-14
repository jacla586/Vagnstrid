"""Mapillarys kartobjekt för vägkanten (vagkant.py): gatlyktor, vägmärken och gatumöbler (gatumobler.py)
där de faktiskt står.

Läser <projekt>/data/mapillary_objekt.geojson och mapillary_bildlagen.json (hamta_mapillary.py objekt).
Där Mapillary har bilder (`tacker`: en bild inom TACKNING_M) ersätter objekten vägkantens regler
(lyktor var 32:a m, hastighetsskyltar ur NVDB, väjningsplikt ur OSM); utan bilder gäller reglerna som
förut. Utan filerna är allt tomt. Lägena är härledda ur CC BY-SA-bilder: "Mapillary" i credits.
"""
import json
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree

TACKNING_M = 20.0
LYKTA = 'object--street-light'
# Mapillarys vägmärke (början av object_value) -> (atlasnamn i vagkant.ATLAS, storlek m, bara bilvägar)
SKYLTAR = [
    ('regulatory--yield', 'vajning', 0.7, True),
    ('regulatory--stop--', 'stopp', 0.7, True),
    ('regulatory--priority-road', 'huvudled', 0.64, True),
    ('information--pedestrians-crossing', 'overgang', 0.64, True),
    ('regulatory--keep-right', 'hall_hoger', 0.5, True),
    ('regulatory--shared-path-pedestrians-and-bicycles', 'gcm', 0.5, False),
    ('regulatory--pedestrians-and-bicycles', 'gcm', 0.5, False),
    ('information--parking', 'parkering', 0.5, True),
    ('regulatory--no-parking', 'p_forbud', 0.5, True),
]
HASTIGHET = 'regulatory--maximum-speed-limit-'
MOBLER = ('object--trash-can', 'object--bench', 'object--junction-box', 'object--bike-rack',
          'object--fire-hydrant', 'object--mailbox', 'object--support--utility-pole')


class MlyObjekt:
    def __init__(self, data_mapp):
        d = Path(data_mapp)
        self.lyktor, self.skyltar = [], []   # [(E, N)], [(E, N, atlasnamn, storlek, bara_bil)]
        self.mobler = []   # [(E, N, object_value)] för gatumobler.SORTER
        pos = []
        fil = d / 'mapillary_objekt.geojson'
        if fil.exists():
            for f in json.loads(fil.read_text())['features']:
                v = f['properties'].get('object_value') or ''
                E, N = f['geometry']['coordinates']
                if v == LYKTA:
                    self.lyktor.append((E, N))
                elif v in MOBLER:
                    self.mobler.append((E, N, v))
                elif v.startswith(HASTIGHET):
                    try:
                        kmh = int(v[len(HASTIGHET):].split('--')[0])
                    except ValueError:
                        continue
                    self.skyltar.append((E, N, str(kmh), 0.64, True))
                else:
                    for prefix, namn, st, bil in SKYLTAR:
                        if v.startswith(prefix):
                            self.skyltar.append((E, N, namn, st, bil))
                            break
        bf = d / 'mapillary_bildlagen.json'
        if bf.exists():
            pos = json.loads(bf.read_text())
        self._kd = cKDTree(np.array(pos, float)) if pos else None

    def __bool__(self):
        return self._kd is not None and bool(self.lyktor or self.skyltar or self.mobler)

    def tacker(self, P, r=TACKNING_M):
        """Bool per punkt (n, 2): finns en Mapillary-bild inom r m?"""
        P = np.atleast_2d(np.asarray(P, float))
        if self._kd is None:
            return np.zeros(len(P), bool)
        d, _ = self._kd.query(P, distance_upper_bound=r)
        return np.isfinite(d)
