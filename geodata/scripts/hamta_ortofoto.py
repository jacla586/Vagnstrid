#!/usr/bin/env python3
"""
Hämtar Lantmäteriets ortofoto (STAC-bild, CC BY 4.0) för ett spelområde som en GeoTIFF.

    .venv/bin/python scripts/hamta_ortofoto.py lista --omrade vidingsjo
    .venv/bin/python scripts/hamta_ortofoto.py hamta --omrade vidingsjo [--upplosning 0.5] [--samling orto-l2-2025]

  lista  -> vilka flygningar (samlingar) som täcker rutan, ingen inloggning
  hamta  -> <omrade>/data/ortofoto_<omrade>.tif (RGB + IR, SWEREF 99 TM, vald upplösning)

Rutan tas från <omrade>/omrade.json ('ruta', SWEREF 99 TM) eller förvalen i hamta_lm_data.py.
Filerna är molnoptimerade (COG): bara de byte som behövs läses, och med --upplosning grövre än
originalets 0.16 m läses färdiga översikter, så nedladdningen blir liten.
Förval: senaste flygningen i serien med 0.16 m (orto-<län>-<år>) som täcker hela rutan.
Inloggning: systemkontot med "Ortofoto Nedladdning" på Geotorget. Skriptet frågar, eller läser
LM_USER / LM_PASS. Skriv lösenordet i din egen terminal, aldrig i en chatt.
"""
import argparse, json, os, sys, urllib.parse, urllib.request
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import hamta_lm_data as lm  # noqa: E402

STAC = "https://api.lantmateriet.se/stac-bild/v1"
GEO = Path(__file__).resolve().parent.parent


def ruta_for(omrade):
    f = GEO / omrade / "omrade.json"
    if f.exists():
        return tuple(float(v) for v in json.loads(f.read_text())["ruta"])
    if omrade in lm.OMRADEN:
        return tuple(float(v) for v in lm.OMRADEN[omrade])
    sys.exit(f"Hittar ingen ruta för {omrade} (varken {f} eller förval).")


def sok(ruta):
    url = f"{STAC}/search?" + urllib.parse.urlencode({"bbox": ",".join(map(str, lm.wgs84_box(ruta))), "limit": 200})
    items, seen = [], set()
    while url and url not in seen:
        seen.add(url)
        with urllib.request.urlopen(url, timeout=60) as r:
            page = json.load(r)
        items += page.get("features", [])
        nxt = [l for l in page.get("links", []) if l.get("rel") == "next" and l.get("method", "GET").upper() == "GET"]
        url = nxt[0]["href"] if nxt else None
    per = defaultdict(list)
    for it in items:
        per[it["collection"]].append(it)
    return per


def _tacker(bbs, ruta, steg=20):
    minx, miny, maxx, maxy = ruta
    for i in range(steg + 1):
        for j in range(steg + 1):
            x = minx + (maxx - minx) * i / steg
            y = miny + (maxy - miny) * j / steg
            if not any(b and b[0] <= x <= b[2] and b[1] <= y <= b[3] for b in bbs):
                return False
    return True


def info(items):
    p = items[0]["properties"]
    return f"{p.get('upplosning')} m, {p.get('spektraltyp')}, flugen {str(p.get('datetime'))[:10]}"


def valj_samling(per, ruta, namn=None):
    if namn:
        if namn not in per:
            sys.exit(f"{namn} täcker inte rutan. Kör 'lista'.")
        return namn
    hela = [s for s, its in per.items() if _tacker([i["properties"].get("proj:bbox") for i in its], ruta)
            and abs(float(its[0]["properties"].get("upplosning", 1)) - 0.16) < 0.01]
    if not hela:
        sys.exit("Ingen 0.16 m-flygning täcker hela rutan. Ange --samling (se 'lista').")
    return max(hela, key=lambda s: (s.rsplit("-", 1)[-1], s))


def hamta(ruta, items, ut, upplosning):
    import rasterio
    from rasterio.merge import merge
    u, p = lm.creds()
    env = dict(GDAL_HTTP_AUTH="BASIC", GDAL_HTTP_USERPWD=f"{u}:{p}", GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
               CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif", GDAL_HTTP_MULTIRANGE="YES", GDAL_HTTP_MERGE_CONSECUTIVE_RANGES="YES",
               GDAL_HTTP_MAX_RETRY="4", GDAL_HTTP_RETRY_DELAY="2", VSI_CACHE="TRUE")
    hrefs = [it["assets"]["data"]["href"] for it in items
             if (b := it["properties"].get("proj:bbox")) and b[0] < ruta[2] and b[2] > ruta[0] and b[1] < ruta[3] and b[3] > ruta[1]]
    print(f"{len(hrefs)} rutor, läser i {upplosning} m ...")
    with rasterio.Env(**env):
        kallor = [rasterio.open("/vsicurl/" + h) for h in hrefs]
        try:
            bild, transform = merge(kallor, bounds=ruta, res=upplosning, resampling=rasterio.enums.Resampling.average)
            profil = kallor[0].profile.copy()
        finally:
            for k in kallor:
                k.close()
    profil.update(driver="GTiff", height=bild.shape[1], width=bild.shape[2], count=bild.shape[0], transform=transform,
                  compress="deflate", predictor=2, tiled=True, blockxsize=512, blockysize=512, photometric="RGB"
                  if bild.shape[0] == 3 else "MINISBLACK")
    for k in ("interleave",):
        profil.pop(k, None)
    Path(ut).parent.mkdir(parents=True, exist_ok=True)
    with rasterio.open(ut, "w", **profil) as dst:
        dst.write(bild)
    print(f"Klar: {ut}  {bild.shape[2]} × {bild.shape[1]} px, {bild.shape[0]} band")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("steg", choices=["lista", "hamta"])
    ap.add_argument("--omrade", required=True)
    ap.add_argument("--samling", help="t.ex. orto-l2-2025 (förval: senaste 0.16 m som täcker rutan)")
    ap.add_argument("--upplosning", type=float, default=0.5, help="meter per pixel (förval 0.5)")
    a = ap.parse_args()
    ruta = ruta_for(a.omrade)
    per = sok(ruta)
    if a.steg == "lista":
        for s in sorted(per, key=lambda s: s.rsplit("-", 1)[-1], reverse=True):
            hel = "hela" if _tacker([i["properties"].get("proj:bbox") for i in per[s]], ruta) else "delvis"
            print(f"{s:28s} {len(per[s]):3d} rutor  {hel:6s} {info(per[s])}")
        return
    s = valj_samling(per, ruta, a.samling)
    print(f"Samling {s}: {info(per[s])}")
    hamta(ruta, per[s], str(GEO / a.omrade / "data" / f"ortofoto_{a.omrade}.tif"), a.upplosning)


if __name__ == "__main__":
    main()
