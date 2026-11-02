#!/usr/bin/env python3
"""Hämtar CC0-fototexturerna från ambientCG som de semirealistiska husen använder (texturer/<id>/).

    .venv/bin/python scripts/hamta_texturer.py
"""
import io, json, urllib.request, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UT = ROOT / 'texturer'
URL = 'https://ambientcg.com/get?file={id}_1K-JPG.zip'


def behov():
    """Alla textur-id som stilar.json använder."""
    s = json.loads((ROOT / 'stilar.json').read_text())
    ids = {m['textur'] for m in s['material_semi'].values() if m.get('textur')}
    ids |= {t['semi'] for t in s['tak'].values() if t.get('semi')}
    return sorted(ids)


def main():
    for tid in behov():
        mapp = UT / tid
        if mapp.exists() and any(mapp.glob('*_Color.jpg')):
            print(f'{tid}: finns'); continue
        print(f'{tid}: hämtar …', flush=True)
        req = urllib.request.Request(URL.format(id=tid), headers={'User-Agent': 'stridsvagn-geodata/1.0'})
        data = urllib.request.urlopen(req, timeout=120).read()
        mapp.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            for n in z.namelist():
                if n.lower().endswith(('.jpg', '.png')) and '/' not in n and '..' not in n:
                    (mapp / n).write_bytes(z.read(n))
    print('Klart:', UT)


if __name__ == '__main__':
    main()
