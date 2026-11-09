#!/usr/bin/env python3
"""Side by side pictures of two tools/render_views.gd runs, with their frame times.

    geodata/.venv/bin/python tools/compare_views.py <label a> <label b>
    e.g. before after_terrain

Reads renders/views/<a>/ and renders/views/<b>/ (pictures and results.txt) and writes
renders/views/compare_<a>_<b>/<view>.png: a over b, each half size, labelled.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent / 'renders' / 'views'


def results(label):
    out = {}
    path = ROOT / label / 'results.txt'
    if path.exists():
        for line in path.read_text().splitlines()[2:]:
            parts = line.split()
            if len(parts) >= 6:
                out[parts[0]] = 'frame %s ms  gpu %s ms  %s k tris' % (parts[1], parts[3], parts[5])
    return out


def main():
    a, b = sys.argv[1], sys.argv[2]
    ra, rb = results(a), results(b)
    out = ROOT / f'compare_{a}_{b}'
    out.mkdir(parents=True, exist_ok=True)
    for pa in sorted((ROOT / a).glob('*.png')):
        pb = ROOT / b / pa.name
        if not pb.exists():
            continue
        ia, ib = Image.open(pa).convert('RGB'), Image.open(pb).convert('RGB')
        w, h = ia.width // 2, ia.height // 2
        sheet = Image.new('RGB', (w, h * 2), 'black')
        sheet.paste(ia.resize((w, h)), (0, 0))
        sheet.paste(ib.resize((w, h)), (0, h))
        d = ImageDraw.Draw(sheet)
        for y, label, res in ((0, a, ra), (h, b, rb)):
            text = f'{label}   {res.get(pa.stem, "")}'
            d.rectangle((0, y, 9 * len(text) + 16, y + 26), fill='black')
            d.text((8, y + 7), text, fill='white')
        sheet.save(out / pa.name)
        print(out / pa.name)


if __name__ == '__main__':
    main()
