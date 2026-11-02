#!/usr/bin/env python3
"""
Skapar en ny karta från två GPS-punkter (diagonala hörn, WGS84 lat,lon): räknar ut rutan,
hämtar all öppen data vi har tillgång till och bygger kartan ända in i Godot.

    .venv/bin/python scripts/nytt_omrade.py <namn> <lat1,lon1> <lat2,lon2>

Exempel:
    .venv/bin/python scripts/nytt_omrade.py hackerstad 58.4745,16.5130 58.4660,16.5320

Steg (körs i ordning; ett steg som redan är gjort hoppas över, så det går att avbryta och köra igen):
  ruta   punkterna -> ruta i SWEREF 99 TM, sparas i <namn>/omrade.json
  osm    OpenStreetMap via Overpass API -> <namn>/data/export.osm
  lm     Lantmäteriets höjdmodell 1 m och laser (inloggning) -> <namn>/data/
         Utan inloggning: Copernicus DEM 30 m från AWS (öppen), men då inga laserträd/laserhus.
  nmd    NMD-trädslag klipps ur den rikstäckande filen (lokal) -> <namn>/data/nmd
  bygg   scripts/bygg.py -> <namn>/out
  godot  importerar till Godot: terrain/<namn>/, assets/maps/<namn>/, scenes/maps/<namn>.tscn
         (en befintlig scen skrivs aldrig över)

  --om STEG     gör om ett steg (och alla efter det)
  --till STEG   stanna efter steget
  --utan-laser  hämta bara höjdmodellen från Lantmäteriet (snabbt, men inga träd/laserhus)
  --copernicus  hoppa över Lantmäteriet helt

Lantmäteriets lösenord skrivs i din egen terminal (eller LM_USER / LM_PASS), aldrig i en chatt.
"""
import argparse, json, math, os, re, shutil, subprocess, sys, time, urllib.error, urllib.parse, urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # geodata/
PROJECT = ROOT.parent                                    # Godot-projektet
S = ROOT / 'scripts'
STEG = ['ruta', 'osm', 'lm', 'nmd', 'bygg', 'godot']
RESERVERADE = {'scripts', 'data', 'work', 'out', 'forhandsbilder', 'lm_env', 'venv'}
OSM_MARGINAL_M = 300
OVERPASS = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter']
COPERNICUS = 'https://copernicus-dem-30m.s3.amazonaws.com/{n}/{n}.tif'
NMD_KALLA = Path.home() / 'Hämtningar' / 'NMD2023_Tradslag_v1_1'
NMD_SKIKT = ['tall', 'gran', 'trivial', 'ekovradel']
VARNA_SIDA_M = 10000
VARNA_YTA_KM2 = 60


def rubrik(text):
    print(f'\n=== {text}', flush=True)


def kor(*cmd, cwd=None):
    print('>', ' '.join(map(str, cmd)), flush=True)
    return subprocess.run([str(c) for c in cmd], cwd=cwd).returncode


def punkt(text):
    try:
        lat, lon = (float(v) for v in text.replace(' ', '').split(','))
    except ValueError:
        sys.exit(f'Kan inte läsa "{text}" som lat,lon (t.ex. 58.4715,16.5238)')
    if not (55 <= lat <= 70 and 10 <= lon <= 25):
        sys.exit(f'{text} ligger inte i Sverige (lat 55–70, lon 10–25). Har du skrivit lat,lon?')
    return lat, lon


def wgs84_ruta(sweref, marginal=0.0):
    from pyproj import Transformer
    tr = Transformer.from_crs(3006, 4326, always_xy=True)
    minx, miny, maxx, maxy = sweref
    hörn = [tr.transform(x, y) for x in (minx - marginal, maxx + marginal)
            for y in (miny - marginal, maxy + marginal)]
    return (min(p[0] for p in hörn), min(p[1] for p in hörn),
            max(p[0] for p in hörn), max(p[1] for p in hörn))


# ---------------------------------------------------------------- steg
def steg_ruta(o):
    from pyproj import Transformer
    tr = Transformer.from_crs(4326, 3006, always_xy=True)
    (la1, lo1), (la2, lo2) = o['punkter']
    e1, n1 = tr.transform(lo1, la1)
    e2, n2 = tr.transform(lo2, la2)
    ruta = [math.floor(min(e1, e2) / 10) * 10, math.floor(min(n1, n2) / 10) * 10,
            math.ceil(max(e1, e2) / 10) * 10, math.ceil(max(n1, n2) / 10) * 10]
    b, h = ruta[2] - ruta[0], ruta[3] - ruta[1]
    if b < 500 or h < 500:
        sys.exit(f'Rutan blir bara {b} × {h} m. Välj punkter minst 500 m isär åt båda hållen.')
    o['ruta'] = ruta
    o['wgs84'] = [round(v, 6) for v in wgs84_ruta(ruta)]
    print(f'Ruta (SWEREF 99 TM): {ruta}   {b / 1000:.2f} × {h / 1000:.2f} km = {b * h / 1e6:.1f} km²')
    if max(b, h) > VARNA_SIDA_M or b * h / 1e6 > VARNA_YTA_KM2:
        print(f'VARNING: stort område. Laserdatan blir flera GB och bygget tar lång tid.')


def steg_osm(o, data):
    ut = data / 'export.osm'
    w, s, e, n = wgs84_ruta(o['ruta'], OSM_MARGINAL_M)
    fraga = f'[out:xml][timeout:600];(nwr({s:.6f},{w:.6f},{n:.6f},{e:.6f}););(._;>;);out meta;'
    for försök in range(4):
        url = OVERPASS[försök % len(OVERPASS)]
        print(f'Hämtar OSM från {url} …', flush=True)
        try:
            req = urllib.request.Request(url, data=urllib.parse.urlencode({'data': fraga}).encode(),
                                         headers={'User-Agent': 'stridsvagn-geodata/1.0'})
            tmp = ut.with_suffix('.part')
            with urllib.request.urlopen(req, timeout=900) as r, open(tmp, 'wb') as f:
                shutil.copyfileobj(r, f, 1 << 20)
            if tmp.stat().st_size < 1000 or b'<osm' not in tmp.read_bytes()[:2000]:
                raise RuntimeError('svaret ser inte ut som OSM-data')
            tmp.replace(ut)
            print(f'Klart: {ut} ({ut.stat().st_size / 1e6:.1f} MB)')
            return
        except (urllib.error.URLError, RuntimeError, TimeoutError) as fel:
            print(f'  misslyckades ({fel}); servern kan vara upptagen, försöker igen om 20 s')
            time.sleep(20)
    sys.exit('Kunde inte hämta OSM-data. Försök igen senare.')


def steg_lm(o, data, a):
    namn = o['namn']
    if a.copernicus:
        return steg_copernicus(o, data)
    steg = ['hojd'] if a.utan_laser else ['hojd', 'laser', 'bearbeta']
    rc = kor(sys.executable, S / 'hamta_lm_data.py', *steg, '--ruta', ','.join(map(str, o['ruta'])),
             '--namn', namn, '--data', data)
    if rc == 0 and (data / f'markhojd_{namn}.tif').exists():
        o['dem'] = f'data/markhojd_{namn}.tif'
        o['dem_typ'] = 'lm'
        objekt = data / f'objekthojd_{namn}.tif'
        o['objekt'] = f'data/{objekt.name}' if objekt.exists() else None
        return
    print('\nLantmäteriets data gick inte att hämta. Använder Copernicus DEM 30 m i stället '
          '(inga laserträd eller laserhus). Kör med --om lm när inloggningen fungerar.')
    steg_copernicus(o, data)


def steg_copernicus(o, data):
    import rasterio
    from rasterio.merge import merge
    w, s, e, n = wgs84_ruta(o['ruta'], 500)
    namn = [f'Copernicus_DSM_COG_10_N{lat:02d}_00_E{lon:03d}_00_DEM'
            for lat in range(math.floor(s), math.floor(n) + 1) for lon in range(math.floor(w), math.floor(e) + 1)]
    print('Läser Copernicus-rutor:', ', '.join(namn), flush=True)
    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR', CPL_VSIL_CURL_ALLOWED_EXTENSIONS='.tif'):
        srcs = [rasterio.open('/vsicurl/' + COPERNICUS.format(n=t)) for t in namn]
        try:
            mosaic, transform = merge(srcs, bounds=(w, s, e, n))
            prof = srcs[0].profile.copy()
        finally:
            for src in srcs:
                src.close()
    prof.update(driver='GTiff', height=mosaic.shape[1], width=mosaic.shape[2], transform=transform,
                compress='deflate', tiled=False)
    ut = data / 'dem.tif'
    with rasterio.open(ut, 'w', **prof) as dst:
        dst.write(mosaic)
    print(f'Klart: {ut} ({mosaic.shape[2]} × {mosaic.shape[1]} px)')
    o['dem'] = 'data/dem.tif'
    o['dem_typ'] = 'copernicus'
    o['objekt'] = None


def steg_nmd(o, data, a):
    kalla = Path(a.nmd_kalla)
    filer = [next(iter(sorted(kalla.glob(f'*tradslag_{k}_*.tif'))), None) for k in NMD_SKIKT]
    if not all(filer):
        print(f'Hittar inte NMD-trädslagen ({", ".join(NMD_SKIKT)}) i {kalla}. Hoppar över; '
              'trädslagen blir då genomsnittsandelar. Ladda ner NMD2023 Trädslag från Naturvårdsverket '
              'och ange mappen med --nmd-kalla.')
        return
    if kor(sys.executable, S / 'klipp_nmd.py', *filer, '--ruta', ','.join(map(str, o['ruta'])),
           '--ut', data / 'nmd') != 0:
        sys.exit('NMD-klippningen misslyckades.')


def steg_bygg(o, mapp, data):
    cmd = [sys.executable, S / 'bygg.py', '--projekt', mapp, '--ruta', ','.join(map(str, o['ruta'])),
           '--osm', data / 'export.osm', '--dem', mapp / o['dem'], '--dem-typ', o['dem_typ'],
           '--nmd', data / 'nmd']
    if o.get('objekt'):
        cmd += ['--objekt', mapp / o['objekt']]
    if kor(*cmd, cwd=ROOT) != 0:
        sys.exit('Bygget misslyckades (se utskriften ovan).')


def steg_godot(o, a):
    godot = a.godot or shutil.which('godot')
    if not godot:
        print('Hittar inte godot. Kör själv från projektroten:\n'
              f'  godot --headless --path . --script res://tools/import_geodata_map.gd -- {o["namn"]} '
              f'res://geodata/{o["namn"]}/out\n  godot --headless --path . --import')
        return
    namn = o['namn']
    if kor(godot, '--headless', '--path', PROJECT, '--script', 'res://tools/import_geodata_map.gd',
           '--', namn, f'res://geodata/{namn}/out') != 0:
        sys.exit('Godot-importen misslyckades.')
    kor(godot, '--headless', '--path', PROJECT, '--import')
    scen = PROJECT / 'scenes' / 'maps' / f'{namn}.tscn'
    if scen.exists():
        print(f'{scen.relative_to(PROJECT)} finns redan och skrivs inte över (terrängen och objekten är uppdaterade).')
    else:
        if kor(godot, '--headless', '--path', PROJECT, '--script', 'res://tools/build_geodata_scene.gd',
               '--', namn, f'res://geodata/{namn}/out') != 0:
            sys.exit('Kunde inte skapa scenen.')
        kor(godot, '--headless', '--path', PROJECT, '--import')
    print(f'\nKartan är klar: res://scenes/maps/{namn}.tscn (öppna och tryck F6)')


# ---------------------------------------------------------------- huvudprogram
def gjort(steg, o, mapp, data):
    namn = o['namn']
    if steg == 'ruta':
        return 'ruta' in o
    if steg == 'osm':
        return (data / 'export.osm').exists()
    if steg == 'lm':
        return bool(o.get('dem')) and (mapp / o['dem']).exists()
    if steg == 'nmd':
        return len(list((data / 'nmd').glob('*_utklipp.tif'))) >= len(NMD_SKIKT)
    if steg == 'bygg':
        return (mapp / 'out' / f'{namn}_objekt.glb').exists() and (mapp / 'out' / 'heightmap.r16').exists()
    if steg == 'godot':
        return (PROJECT / 'terrain' / namn).exists() and (PROJECT / 'scenes' / 'maps' / f'{namn}.tscn').exists()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('namn', help='kartans namn: små bokstäver, siffror och _ (blir mapp- och scennamn)')
    ap.add_argument('punkt1', help='lat,lon för ett hörn')
    ap.add_argument('punkt2', help='lat,lon för motsatt hörn')
    ap.add_argument('--om', choices=STEG, help='gör om det här steget och alla efter')
    ap.add_argument('--till', choices=STEG, help='stanna efter det här steget')
    ap.add_argument('--utan-laser', action='store_true', help='bara höjdmodellen från Lantmäteriet')
    ap.add_argument('--copernicus', action='store_true', help='hoppa över Lantmäteriet, använd Copernicus DEM')
    ap.add_argument('--nmd-kalla', default=str(NMD_KALLA), help=f'mapp med rikstäckande NMD-trädslag (standard {NMD_KALLA})')
    ap.add_argument('--godot', help='sökväg till godot (standard: godot i PATH)')
    a = ap.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]*', a.namn) or a.namn in RESERVERADE:
        sys.exit('Namnet får bara innehålla a–z, 0–9 och _, börja med en bokstav, '
                 f'och inte vara något av {sorted(RESERVERADE)}.')
    mapp = ROOT / a.namn
    data = mapp / 'data'
    data.mkdir(parents=True, exist_ok=True)
    fil = mapp / 'omrade.json'
    o = json.loads(fil.read_text()) if fil.exists() else {}
    punkter = [list(punkt(a.punkt1)), list(punkt(a.punkt2))]
    if o.get('punkter') and o['punkter'] != punkter:
        sys.exit(f'{fil} har andra punkter ({o["punkter"]}). Välj ett annat namn, eller ta bort mappen {mapp}.')
    o.update(namn=a.namn, punkter=punkter)
    om_fran = STEG.index(a.om) if a.om else len(STEG)
    for i, steg in enumerate(STEG):
        if i < om_fran and gjort(steg, o, mapp, data):
            print(f'--- {steg}: redan gjort')
        else:
            rubrik(steg)
            if steg == 'ruta':
                steg_ruta(o)
            elif steg == 'osm':
                steg_osm(o, data)
            elif steg == 'lm':
                steg_lm(o, data, a)
            elif steg == 'nmd':
                steg_nmd(o, data, a)
            elif steg == 'bygg':
                steg_bygg(o, mapp, data)
            elif steg == 'godot':
                steg_godot(o, a)
            o['uppdaterad'] = datetime.now().isoformat(timespec='seconds')
            fil.write_text(json.dumps(o, indent=1, ensure_ascii=False))
        if steg == a.till:
            break


if __name__ == '__main__':
    main()
