#!/usr/bin/env python3
"""
Bygger Godot-paketet för ett område.

Vikbolandet (standard, söder om E851 ner till Slätbaken):
    python3 scripts/bygg.py                                  # Copernicus DEM (data/dem.tif)
    python3 scripts/bygg.py --dem data/markhojd_vikbolandet_e851.tif --dem-typ lm

Annat område med egen projektmapp (data/, work/ och out/ under mappen) och en ruta som spelområde:
    python3 scripts/bygg.py --projekt vidingsjo --ruta 536120,6469620,539500,6472670 \\
        --osm vidingsjo/vidingsjo.osm --dem vidingsjo/data/markhojd_vidingsjo.tif --dem-typ lm \\
        --objekt vidingsjo/data/objekthojd_vidingsjo.tif

Indata:  OSM-utdrag och en höjdmodell (GeoTIFF), helst objekthöjd från laser och NMD-trädslag.
Utdata:  out/  (glb, heightmap, marktäcke, roads.json, places.json, heightmap_info.json, träd)
"""
import argparse, os, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
S = ROOT / 'scripts'


def run(*cmd, env=None):
    print('>', ' '.join(map(str, cmd)), flush=True)
    subprocess.run([sys.executable, *map(str, cmd)], check=True, env=env)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--projekt', default=None,
                    help="projektmapp med egna data/, work/ och out/ (standard: geodata/ själv, Vikbolandet)")
    ap.add_argument('--ruta', default=None,
                    help="minx,miny,maxx,maxy i SWEREF 99 TM; hela rutan blir spelområde (ingen E851/kust-logik)")
    ap.add_argument('--osm', default=None, help="standard: <projekt>/data/export.osm")
    ap.add_argument('--dem', default=None, help="standard: <projekt>/data/dem.tif")
    ap.add_argument('--dem-typ', choices=['copernicus', 'lm'], default='copernicus',
                    help="copernicus = 30 m ytmodell (kanopikorrigering + utjämning), lm = Lantmäteriets markmodell")
    ap.add_argument('--objekt', default=None,
                    help="objekthöjd från laser (hamta_lm_data.py bearbeta); ger hus och träd om filen finns. "
                         "Standard: <projekt>/data/objekthojd_vikbolandet_e851.tif")
    ap.add_argument('--nmd', default=None, help="mapp med utklippta NMD-trädslag (standard: <projekt>/data/nmd)")
    ap.add_argument('--out', default=None, help="standard: <projekt>/out")
    a = ap.parse_args()
    proj = Path(a.projekt).resolve() if a.projekt else ROOT
    osm = a.osm or proj / 'data' / 'export.osm'
    dem = a.dem or proj / 'data' / 'dem.tif'
    objekt = a.objekt or proj / 'data' / 'objekthojd_vikbolandet_e851.tif'
    nmd = a.nmd or proj / 'data' / 'nmd'
    out = Path(a.out or proj / 'out')
    work = proj / 'work'
    out.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, GEO_WORK=str(work), GEO_NAMN=proj.name if a.projekt else 'vikbolandet_e851')

    run(S / 'step1_region.py', osm, *([a.ruta] if a.ruta else []), env=env)
    run('-c', f"import sys,pickle; sys.path.insert(0,r'{S}'); from features import build; "
              f"pickle.dump(build(r'{osm}'), open(r'{work / 'features.pkl'}','wb'))", env=env)
    run(S / 'step2_terrain.py', dem, a.dem_typ, env=env)
    run(S / 'step3_build.py', out, objekt, env=env)
    if Path(objekt).exists():
        run(S / 'step4_trees.py', objekt, out, nmd, env=env)
    else:
        print(f'Hoppar över träd: {objekt} saknas')
    print(f'\nKlart. Resultatet ligger i {out}')


if __name__ == '__main__':
    main()
