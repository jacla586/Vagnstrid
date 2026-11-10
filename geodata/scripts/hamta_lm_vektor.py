#!/usr/bin/env python3
"""
Hämtar Lantmäteriets vektordata (STAC-vektor, CC BY 4.0) per kommun som GeoPackage.

    python3 scripts/hamta_lm_vektor.py lista                          # samlingarna (ingen inloggning)
    python3 scripts/hamta_lm_vektor.py hamta                          # fastighetsindelning, Linköping + Norrköping
    python3 scripts/hamta_lm_vektor.py hamta --samling byggnader --kommun 0580

Filerna hamnar i ostergotland/data/<samling>/ (ignoreras av git), uppackade.
Samlingar: fastighetsindelning, byggnader, marktacke, belagenhetsadresser, ortnamn, kommun-lan-rike.
Kommunkoder: 0580 Linköping (vidingsjo, linghem, campus, road_to_science), 0581 Norrköping (vikbolandet).
Inloggning: systemkontot på Geotorget (samma som för höjd/laser) som har beställt produkten,
t.ex. "Fastighetsindelning Nedladdning, vektor". Skriptet frågar, eller läser LM_USER / LM_PASS.
Skriv lösenordet i din egen terminal, aldrig i en chatt.
"""
import argparse, base64, getpass, json, os, sys, urllib.request, zipfile
from pathlib import Path

STAC = "https://api.lantmateriet.se/stac-vektor/v1"
GEO = Path(__file__).resolve().parent.parent
_CRED = {}


def hamta_json(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return json.load(r)


def auth_header():
    if not _CRED:
        anv = os.environ.get("LM_USER") or (input("Användarnamn (Lantmäteriet): ") if sys.stdin.isatty() else "")
        lo = os.environ.get("LM_PASS") or (getpass.getpass("Lösenord: ") if sys.stdin.isatty() else "")
        if not anv or not lo:
            sys.exit("Ingen inloggning till Lantmäteriet (sätt LM_USER/LM_PASS eller kör i en terminal).")
        _CRED["h"] = "Basic " + base64.b64encode(f"{anv}:{lo}".encode()).decode()
    return _CRED["h"]


def lista():
    for c in hamta_json(f"{STAC}/collections")["collections"]:
        print(f"{c['id']:22} {c.get('license', ''):10} {c.get('description', '')}")


def objekt(samling):
    """Alla objekt i samlingen (en per kommun, eller ett för hela landet)."""
    url, ut = f"{STAC}/collections/{samling}/items?limit=500", []
    while url:
        d = hamta_json(url)
        ut += d["features"]
        url = next((l["href"] for l in d.get("links", []) if l["rel"] == "next"), None)
    return ut


def ladda_ned(url, fil):
    if fil.exists():
        print("finns redan:", fil.name)
        return
    tmp = fil.with_suffix(fil.suffix + ".del")
    req = urllib.request.Request(url, headers={"Authorization": auth_header()})
    try:
        with urllib.request.urlopen(req, timeout=300) as r, open(tmp, "wb") as f:
            total, n = int(r.headers.get("Content-Length") or 0), 0
            while chunk := r.read(1 << 20):
                f.write(chunk)
                n += len(chunk)
                if total:
                    print(f"\r  {fil.name}: {n / 1e6:.0f} / {total / 1e6:.0f} MB", end="", flush=True)
        print()
    except urllib.error.HTTPError as e:
        tmp.unlink(missing_ok=True)
        if e.code in (401, 403):
            sys.exit(f"Nekad ({e.code}). Har kontot beställt produkten för samlingen på Geotorget?")
        raise
    tmp.rename(fil)


def hamta(samling, kommuner):
    mapp = GEO / "ostergotland" / "data" / samling
    mapp.mkdir(parents=True, exist_ok=True)
    alla = objekt(samling)
    valda = alla if len(alla) == 1 else [o for o in alla if o["id"] in kommuner]
    if not valda:
        sys.exit(f"Hittade inga objekt för {kommuner} i {samling}.")
    for o in valda:
        print(o["properties"].get("title", o["id"]))
        for a in o["assets"].values():
            fil = mapp / a["href"].rsplit("/", 1)[-1]
            ladda_ned(a["href"], fil)
            if fil.suffix == ".zip":
                with zipfile.ZipFile(fil) as z:
                    z.extractall(mapp)
                    print("  uppackat:", ", ".join(z.namelist()))
    print("klart ->", mapp)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("steg", choices=["lista", "hamta"])
    ap.add_argument("--samling", default="fastighetsindelning")
    ap.add_argument("--kommun", default="0580,0581", help="kommunkoder, kommaseparerade")
    a = ap.parse_args()
    if a.steg == "lista":
        lista()
    else:
        hamta(a.samling, a.kommun.split(","))


if __name__ == "__main__":
    main()
