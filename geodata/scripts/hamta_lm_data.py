#!/usr/bin/env python3
"""
Hämtar Lantmäteriets höjdmodell (1 m) och laserdata (Laserdata skog) för spelområdet
söder om E851 på Vikbolandet, och gör om laserdatan till en liten rasterfil med
objekthöjder (träd/hus) som är lätt att skicka vidare.

Steg (kör i den här ordningen, eller "allt" för alla på en gång):
    python3 scripts/hamta_lm_data.py lista     # visar vad som finns i katalogen för området (ingen inloggning)
    python3 scripts/hamta_lm_data.py hojd      # -> data/markhojd_vikbolandet_e851.tif
    python3 scripts/hamta_lm_data.py laser     # -> data/laser/*.laz  (stora filer, ~1-2 GB per 10 km-ruta)
    python3 scripts/hamta_lm_data.py bearbeta  # -> data/objekthojd_vikbolandet_e851.tif
    python3 scripts/hamta_lm_data.py allt

Inloggning: systemkontot som har beställt "Markhöjdmodell Nedladdning" och
"Laserdata Nedladdning, skog" på Geotorget. Skriptet frågar, eller läser LM_USER / LM_PASS.
Paket:  pip install rasterio "laspy[lazrs]"
"""
import argparse, base64, getpass, json, os, sys, time, urllib.parse, urllib.request
from datetime import datetime

STAC = "https://api.lantmateriet.se/stac-hojd/v1"
BBOX_SWEREF = (586040, 6478956, 592614, 6485950)   # minx, miny, maxx, maxy (SWEREF 99 TM)
BBOX_WGS84 = (16.4739, 58.4414, 16.5894, 58.5057)    # samma område i lon/lat
from pathlib import Path as _P
DATA = _P(__file__).resolve().parent.parent / "data"
DATA.mkdir(exist_ok=True)
DTM_FILE = str(DATA / "markhojd_vikbolandet_e851.tif")
OBJ_FILE = str(DATA / "objekthojd_vikbolandet_e851.tif")
LASER_DIR = str(DATA / "laser")
_CRED = {}


# ---------------------------------------------------------------- katalog
def stac_search():
    url = f"{STAC}/search?" + urllib.parse.urlencode({"bbox": ",".join(map(str, BBOX_WGS84)), "limit": 100})
    items, seen = [], set()
    while url and url not in seen:
        seen.add(url)
        with urllib.request.urlopen(url, timeout=60) as r:
            page = json.load(r)
        items += page.get("features", [])
        nxt = [l for l in page.get("links", []) if l.get("rel") == "next" and l.get("method", "GET").upper() == "GET"]
        url = nxt[0]["href"] if nxt else None
    return items


def assets_with_ext(item, exts):
    out = []
    for key, a in item.get("assets", {}).items():
        href = a.get("href", "")
        if href.lower().split("?")[0].endswith(exts):
            out.append(href)
    return out


def item_time(item):
    p = item.get("properties", {})
    for k in ("datetime", "end_datetime", "start_datetime", "created"):
        if p.get(k):
            try:
                return datetime.fromisoformat(p[k].replace("Z", "+00:00")).timestamp()
            except ValueError:
                pass
    return 0


def dtm_hrefs(items):
    hrefs = [h for i in items for h in assets_with_ext(i, (".tif", ".tiff"))]
    mhm = [h for h in hrefs if "/mhm/" in h.lower() or "mhm" in h.lower().rsplit("/", 1)[-1]]
    return mhm or hrefs


def laser_items(items):
    """Ett objekt per ruta; finns samma ruta från flera år väljs den senaste."""
    best = {}
    for it in items:
        laz = assets_with_ext(it, (".laz", ".las"))
        if not laz:
            continue
        key = tuple(round(v, 3) for v in it.get("bbox", [])) or it.get("id")
        if key not in best or item_time(it) > item_time(best[key][0]):
            best[key] = (it, laz[0])
    return list(best.values())


def creds():
    if not _CRED:
        _CRED["u"] = os.environ.get("LM_USER") or input("Lantmäteriet systemkonto, användarnamn: ")
        _CRED["p"] = os.environ.get("LM_PASS") or getpass.getpass("Lösenord: ")
    return _CRED["u"], _CRED["p"]


def auth_header():
    u, p = creds()
    return "Basic " + base64.b64encode(f"{u}:{p}".encode()).decode()


def explain_auth_error(product):
    sys.exit(f"Inloggningen nekades (401/403). Kontrollera användarnamn/lösenord, att det är "
             f"systemkontot, och att det har beställt '{product}' på Geotorget.")


# ---------------------------------------------------------------- lista
def cmd_lista(args):
    items = stac_search()
    print(f"{len(items)} objekt i katalogen för området:\n")
    for it in items:
        print(f"- {it.get('id')}  [{it.get('collection')}]  {it.get('properties', {}).get('datetime')}")
        for k, a in it.get("assets", {}).items():
            print(f"    {k}: {a.get('type', '')}  {a.get('href')}")
    print(f"\nHöjdrutor: {len(dtm_hrefs(items))}   Laserrutor: {len(laser_items(items))}")


# ---------------------------------------------------------------- höjd
def cmd_hojd(args):
    import rasterio
    from rasterio.merge import merge
    print("Söker höjdrutor …")
    hrefs = dtm_hrefs(stac_search())
    if not hrefs:
        sys.exit("Hittade inga höjdrutor. Kör 'lista' och skicka utskriften till Claude.")
    for h in hrefs:
        print("  ", h)
    u, p = creds()
    env = dict(GDAL_HTTP_AUTH="BASIC", GDAL_HTTP_USERPWD=f"{u}:{p}", GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
               CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif,.tiff", GDAL_HTTP_MULTIRANGE="YES",
               GDAL_HTTP_MERGE_CONSECUTIVE_RANGES="YES", VSI_CACHE="TRUE",
               GDAL_HTTP_MAX_RETRY="4", GDAL_HTTP_RETRY_DELAY="2")
    print("Läser bara de delar av rutorna som täcker området …")
    with rasterio.Env(**env):
        srcs = []
        try:
            for h in hrefs:
                try:
                    srcs.append(rasterio.open("/vsicurl/" + h))
                except rasterio.errors.RasterioIOError as e:
                    if "401" in str(e) or "403" in str(e):
                        explain_auth_error("Markhöjdmodell Nedladdning")
                    raise
            nodata = srcs[0].nodata if srcs[0].nodata is not None else -9999.0
            mosaic, transform = merge(srcs, bounds=BBOX_SWEREF, res=args.res, nodata=nodata)
            crs = srcs[0].crs
        finally:
            for s in srcs:
                s.close()
    prof = dict(driver="GTiff", height=mosaic.shape[1], width=mosaic.shape[2], count=1, dtype=mosaic.dtype,
                crs=crs, transform=transform, nodata=nodata, compress="deflate",
                predictor=3 if mosaic.dtype.kind == "f" else 2, tiled=True, blockxsize=512, blockysize=512)
    with rasterio.open(DTM_FILE, "w", **prof) as dst:
        dst.write(mosaic)
    v = mosaic[0][mosaic[0] != nodata]
    print(f"Klart: {DTM_FILE}  ({mosaic.shape[2]} x {mosaic.shape[1]} px, {args.res} m/px"
          + (f", höjd {v.min():.1f}–{v.max():.1f} m)" if v.size else ")"))


# ---------------------------------------------------------------- laser
def download(url, dest):
    tmp = dest + ".part"
    have = os.path.getsize(tmp) if os.path.exists(tmp) else 0
    req = urllib.request.Request(url, headers={"Authorization": auth_header(), **({"Range": f"bytes={have}-"} if have else {})})
    try:
        r = urllib.request.urlopen(req, timeout=120)
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            explain_auth_error("Laserdata Nedladdning, skog")
        if e.code == 416:  # redan helt nedladdad
            os.replace(tmp, dest); return
        raise
    total = r.headers.get("Content-Length")
    total = int(total) + have if total else None
    if have and r.status != 206:      # servern stödde inte återupptagning
        have = 0
    mode = "ab" if have else "wb"
    done, t0 = have, time.time()
    with open(tmp, mode) as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk); done += len(chunk)
            if total:
                sp = (done - have) / max(time.time() - t0, 1e-6) / 1e6
                print(f"\r    {done / 1e6:8.0f} / {total / 1e6:.0f} MB  ({sp:.1f} MB/s)", end="", flush=True)
    print()
    os.replace(tmp, dest)


def cmd_laser(args):
    print("Söker laserrutor …")
    sel = laser_items(stac_search())
    if not sel:
        sys.exit("Hittade inga laserrutor. Kör 'lista' och skicka utskriften till Claude.")
    os.makedirs(LASER_DIR, exist_ok=True)
    print(f"  {len(sel)} ruta(or). Filerna är stora; avbryter du kan du köra igen så fortsätter nedladdningen.")
    for it, href in sel:
        name = os.path.basename(urllib.parse.urlparse(href).path)
        dest = os.path.join(LASER_DIR, name)
        if os.path.exists(dest):
            print(f"  {name}: finns redan"); continue
        print(f"  {name}  ({it.get('properties', {}).get('datetime', '')[:10]})")
        download(href, dest)
    print(f"Klart: laserfiler i mappen {LASER_DIR}/")


# ---------------------------------------------------------------- bearbeta
def cmd_bearbeta(args):
    import numpy as np, rasterio, laspy, glob
    if not os.path.exists(DTM_FILE):
        sys.exit(f"Saknar {DTM_FILE}. Kör steget 'hojd' först.")
    files = sorted(glob.glob(os.path.join(LASER_DIR, "*.la[sz]")))
    if not files:
        sys.exit(f"Inga laserfiler i {LASER_DIR}/. Kör steget 'laser' först.")
    with rasterio.open(DTM_FILE) as d:
        dtm = d.read(1).astype(np.float32); T = d.transform; crs = d.crs; nod = d.nodata
    H, W = dtm.shape; res = T.a; x0, y0 = T.c, T.f
    ncell = H * W
    zmax = np.full(ncell, -np.inf, np.float32)
    n_all = np.zeros(ncell, np.uint16)
    n_multi = np.zeros(ncell, np.uint16)
    n_ground = np.zeros(ncell, np.uint16)

    def accumulate(idx, z=None, counter=None):
        if idx.size == 0:
            return
        o = np.argsort(idx, kind="stable"); s = idx[o]
        u, start = np.unique(s, return_index=True)
        if z is not None:
            zm = np.maximum.reduceat(z[o], start)
            zmax[u] = np.maximum(zmax[u], zm)
        if counter is not None:
            c = np.diff(np.r_[start, s.size])
            counter[u] = np.minimum(counter[u].astype(np.int64) + c, 65535).astype(np.uint16)

    for f in files:
        print(f"  {os.path.basename(f)}")
        with laspy.open(f) as r:
            hb = r.header
            if hb.maxs[0] < x0 or hb.mins[0] > x0 + W * res or hb.maxs[1] < y0 - H * res or hb.mins[1] > y0:
                print("    (utanför området, hoppar över)"); continue
            total = hb.point_count; done = 0
            for pts in r.chunk_iterator(5_000_000):
                done += len(pts)
                x = np.asarray(pts.x); y = np.asarray(pts.y); z = np.asarray(pts.z, dtype=np.float32)
                col = np.floor((x - x0) / res).astype(np.int64); row = np.floor((y0 - y) / res).astype(np.int64)
                ok = (col >= 0) & (col < W) & (row >= 0) & (row < H)
                if not ok.any():
                    continue
                cls = np.asarray(pts.classification)[ok]
                idx = (row * W + col)[ok]; z = z[ok]
                rn = np.asarray(pts.return_number)[ok]; nr = np.asarray(pts.number_of_returns)[ok]
                obj = cls == 1                     # 1 = oklassad: vegetation, byggnader m.m.
                accumulate(idx[obj], z[obj], n_all)
                accumulate(idx[obj & (rn < nr)], None, n_multi)   # ej sista ekot: typiskt träd
                accumulate(idx[cls == 2], None, n_ground)
                print(f"\r    {done / total * 100:5.1f} %", end="", flush=True)
            print()

    zmax = zmax.reshape(H, W); n_all = n_all.reshape(H, W); n_multi = n_multi.reshape(H, W)
    valid_dtm = dtm != nod if nod is not None else np.isfinite(dtm)
    hag = np.where(np.isfinite(zmax) & valid_dtm, zmax - dtm, 0.0)
    hag = np.clip(hag, 0, 60)
    band1 = np.round(hag * 10).astype(np.uint16)                     # höjd över mark, decimeter
    frac = np.where(n_all > 0, n_multi / np.maximum(n_all, 1), 0)
    band2 = np.where(n_all > 0, np.round(frac * 100), 255).astype(np.uint16)  # andel flerekon, %, 255 = inga punkter
    band3 = n_ground.reshape(H, W)                                    # markpunkter per cell
    with rasterio.open(OBJ_FILE, "w", driver="GTiff", height=H, width=W, count=3, dtype="uint16", crs=crs,
                       transform=T, compress="deflate", predictor=2, tiled=True, blockxsize=512, blockysize=512) as dst:
        dst.write(band1, 1); dst.write(band2, 2); dst.write(band3, 3)
        dst.set_band_description(1, "hojd over mark (dm), hogsta oklassade punkt")
        dst.set_band_description(2, "andel punkter som inte ar sista ekot (%), 255 = inga punkter")
        dst.set_band_description(3, "antal markpunkter")
    cover = (n_all > 0).mean() * 100
    print(f"Klart: {OBJ_FILE}  ({os.path.getsize(OBJ_FILE) / 1e6:.0f} MB, punkter i {cover:.0f} % av cellerna)")
    print(f"Nästa steg: python3 scripts/bygg.py --dem {DTM_FILE} --dem-typ lm")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("steg", choices=["lista", "hojd", "laser", "bearbeta", "allt"])
    ap.add_argument("--res", type=float, default=1.0, help="upplösning för höjdmodellen i meter (standard 1)")
    a = ap.parse_args()
    steps = dict(lista=[cmd_lista], hojd=[cmd_hojd], laser=[cmd_laser], bearbeta=[cmd_bearbeta],
                 allt=[cmd_hojd, cmd_laser, cmd_bearbeta])[a.steg]
    for s in steps:
        s(a)


if __name__ == "__main__":
    main()
