#!/usr/bin/env python3
"""Fetches the terrain textures in tools/terrain_textures.json from ambientCG (CC0, 1K JPG)
and packs them the way Terrain3D wants them:

    <file>_alb_ht.png   RGB albedo, A height (displacement)
    <file>_nrm_rgh.png  RGB normal (OpenGL, Y+), A roughness

    geodata/.venv/bin/python tools/pack_terrain_texture.py [--force]

Downloads go to geodata/texturer/<source>/ (git-ignored); packed files to assets/terrain/.
Existing packed files are kept unless --force. Adds a line per texture to
assets/terrain/LICENSE.txt.
"""
import io
import json
import sys
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / 'tools' / 'terrain_textures.json'
CACHE = ROOT / 'geodata' / 'texturer'
OUT = ROOT / 'assets' / 'terrain'
LICENSE = OUT / 'LICENSE.txt'
URL = 'https://ambientcg.com/get?file={id}_1K-JPG.zip'
SIZE = 1024


def fetch(source):
    folder = CACHE / source
    if folder.exists() and any(folder.glob('*_Color.jpg')):
        return folder
    print(f'{source}: downloading', flush=True)
    req = urllib.request.Request(URL.format(id=source), headers={'User-Agent': 'vagnstrid-tools/1.0'})
    data = urllib.request.urlopen(req, timeout=120).read()
    folder.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for name in z.namelist():
            if name.lower().endswith(('.jpg', '.png')) and '/' not in name and '..' not in name:
                (folder / name).write_bytes(z.read(name))
    return folder


def channel(folder, suffix, mode, default):
    files = sorted(folder.glob(f'*_{suffix}.jpg')) + sorted(folder.glob(f'*_{suffix}.png'))
    if not files:
        print(f'  no {suffix}, using a flat {default}')
        return Image.new(mode, (SIZE, SIZE), default)
    return Image.open(files[0]).convert(mode).resize((SIZE, SIZE), Image.LANCZOS)


def pack(entry, force):
    file, source = entry['file'], entry['source']
    alb_path, nrm_path = OUT / f'{file}_alb_ht.png', OUT / f'{file}_nrm_rgh.png'
    if alb_path.exists() and nrm_path.exists() and not force:
        print(f'{file}: packed already')
        return
    folder = fetch(source)
    color = channel(folder, 'Color', 'RGB', (128, 128, 128))
    height = channel(folder, 'Displacement', 'L', 128)
    normal = channel(folder, 'NormalGL', 'RGB', (128, 128, 255))
    rough = channel(folder, 'Roughness', 'L', 200)
    Image.merge('RGBA', (*color.split(), height)).save(alb_path, optimize=True)
    Image.merge('RGBA', (*normal.split(), rough)).save(nrm_path, optimize=True)
    print(f'{file}: packed from {source}')
    line = f'{file}_* : {entry["name"]}  https://ambientcg.com/view?id={source}'
    text = LICENSE.read_text() if LICENSE.exists() else ''
    if line not in text:
        LICENSE.write_text(text.rstrip('\n') + '\n' + line + '\n')


def main():
    force = '--force' in sys.argv
    config = json.loads(CONFIG.read_text())
    OUT.mkdir(parents=True, exist_ok=True)
    for entry in config['textures']:
        pack(entry, force)


if __name__ == '__main__':
    main()
