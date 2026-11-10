"""Saker som stridsvagnar kan välta (spelets PropBreak): glb-gruppen `Valtbart`, ingen kollision.

  Mall_<typ>          en mall per typ i lokala koordinater (foten i origo, y upp), en barnmesh per
                      material (Mall_<typ>_<n>)
  <typ>__<n>          en tom nod per exemplar: transformen (foten, vridning runt y) placerar mallen
  Ledning__<spår>_<i> enskilda meshar i världskoordinater (kontaktledningen mellan stolpstation i och
                      i + 1); en stolpe med namnet Kontaktstolpe_*__<spår>_<i> drar med sig spannen
                      <i − 1> och <i> när den faller

Spelet ritar exemplaren som MultiMesh per 250 m-ruta (lika många draw calls som de sammanslagna
mesharna förut) och döljer det som välts.
"""
import numpy as np
import trimesh
from jarnvag import kuboider


def lador_mesh(C, botten=False):
    """Lådor (n, 8, 3) -> en trimesh (botten tas bort utom med `botten`)."""
    V, Fs, Ft = kuboider(np.asarray(C, float), ta_bort_botten=not botten)
    return trimesh.Trimesh(V, np.vstack([Fs, Ft]), process=False)


def yaw_matris(fot, x_dir, skala_x=1.0):
    """4x4: lokala x längs x_dir (världens xz), y upp, foten i `fot` (världen x, y, z); x skalas
    med skala_x (räckesbitar med olika längd)."""
    x = np.array([x_dir[0], 0.0, x_dir[1]], float)
    x /= max(np.linalg.norm(x), 1e-9)
    z = np.cross(x, [0.0, 1.0, 0.0])   # högerhänt: x × y = z
    M = np.eye(4)
    M[:3, 0], M[:3, 1], M[:3, 2] = x * skala_x, [0.0, 1.0, 0.0], z
    M[:3, 3] = fot
    return M


class Samling:
    def __init__(self):
        self.mallar = {}     # typ -> [(trimesh, material)]
        self.platser = []    # (nodnamn, 4x4)
        self.meshar = []     # (nodnamn, trimesh, material)
        self.antal = {}

    def har_mall(self, typ):
        return typ in self.mallar

    def mall(self, typ, delar):
        """delar: [(trimesh i lokala koordinater, material[, uv])]."""
        self.mallar.setdefault(typ, delar)

    def placera(self, typ, fot, x_dir, nyckel=None, skala_x=1.0):
        n = self.antal.get(typ, 0)
        self.antal[typ] = n + 1
        self.platser.append((f'{typ}__{n if nyckel is None else nyckel}', yaw_matris(fot, x_dir, skala_x)))

    def mesh(self, namn, msh, material):
        self.meshar.append((namn, msh, material))

    def __bool__(self):
        return bool(self.platser or self.meshar)

    def skriv(self, scene):
        if not self:
            return
        scene.graph.update(frame_to='Valtbart', frame_from=scene.graph.base_frame)
        for typ, delar in self.mallar.items():
            scene.graph.update(frame_to=f'Mall_{typ}', frame_from='Valtbart')
            for j, del_ in enumerate(delar):
                m, mat = del_[0].copy(), del_[1]
                uv = del_[2] if len(del_) > 2 else None   # texturerade delar (skyltytor)
                m.visual = trimesh.visual.TextureVisuals(uv=uv, material=mat)
                namn = f'Mall_{typ}_{j}'
                scene.add_geometry(m, node_name=namn, geom_name=namn, parent_node_name=f'Mall_{typ}')
        for namn, M in self.platser:
            scene.graph.update(frame_to=namn, frame_from='Valtbart', matrix=M)
        for namn, m, mat in self.meshar:
            m.visual = trimesh.visual.TextureVisuals(material=mat)
            scene.add_geometry(m, node_name=namn, geom_name=namn, parent_node_name='Valtbart')
        print('vältbart:', ', '.join(f'{k} {v}' for k, v in self.antal.items()),
              f'+ {len(self.meshar)} meshar' if self.meshar else '')
