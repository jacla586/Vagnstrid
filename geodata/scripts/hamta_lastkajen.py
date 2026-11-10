#!/usr/bin/env python3
"""
Hämtar filer från Trafikverkets Lastkajen (NVDB-vägdata, järnvägsnätet) via dess REST-API.

    .venv/bin/python -I scripts/hamta_lastkajen.py lista                    # alla datapaket (id, namn)
    .venv/bin/python -I scripts/hamta_lastkajen.py filer <paket-id>         # filerna i ett paket
    .venv/bin/python -I scripts/hamta_lastkajen.py hamta <paket-id> <mönster>  # t.ex. "*Östergötland*gpkg*"

Filerna hamnar i östergötland/data/lastkajen/<paket-id>/ (ignoreras av git); zip packas upp och tas bort,
kvittofilerna (_kvitto.xml) hämtas inte.
Inloggning: ditt Lastkajen-konto. Skriptet frågar, eller läser LASTKAJEN_USER / LASTKAJEN_PASS.
Skriv lösenordet i din egen terminal, aldrig i en chatt.
"""
import fnmatch, getpass, json, os, sys, urllib.parse, urllib.request, zipfile
from pathlib import Path

API = "https://lastkajen.trafikverket.se/api"
UT = Path(__file__).resolve().parent.parent / "östergötland" / "data" / "lastkajen"
_TOKEN = {}


def logga_in():
    if "t" not in _TOKEN:
        anv = os.environ.get("LASTKAJEN_USER") or input("Användarnamn (Lastkajen): ")
        lo = os.environ.get("LASTKAJEN_PASS") or getpass.getpass("Lösenord: ")
        # Dokumentationen visar inte kroppens format: prova JSON, sedan formulär
        forsok = [(json.dumps({"UserName": anv, "Password": lo}).encode(), "application/json"),
                  (urllib.parse.urlencode({"UserName": anv, "Password": lo}).encode(),
                   "application/x-www-form-urlencoded")]
        fel = None
        for data, typ in forsok:
            req = urllib.request.Request(f"{API}/Identity/Login", data=data, method="POST",
                                         headers={"Content-Type": typ})
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    _TOKEN["t"] = json.load(r)["access_token"]
                    break
            except urllib.error.HTTPError as e:
                fel = e.code
        else:
            sys.exit(f"Inloggningen misslyckades ({fel}).")
    return _TOKEN["t"]


def get(url, auth=True):
    h = {"Authorization": f"Bearer {logga_in()}"} if auth else {}
    with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=120) as r:
        return json.load(r)


def paket():
    return get(f"{API}/DataPackage/GetPublishedDataPackages")


def filer(pid):
    return get(f"{API}/DataPackage/GetDataPackageFiles?id={pid}")


def ladda_ned(pid, namn):
    # en mapp per paket: olika paket har filer med samma namn (t.ex. "Östergötlands län.gpkg")
    mapp = UT / str(pid)
    mapp.mkdir(parents=True, exist_ok=True)
    fil = mapp / namn.rsplit("/", 1)[-1]
    if fil.exists():
        print("finns redan:", fil.name)
        return fil
    q = urllib.parse.urlencode({"id": pid, "fileName": namn})
    tok = get(f"{API}/File/GetDataPackageDownloadToken?{q}")
    tok = tok if isinstance(tok, str) else tok.get("token") or tok.get("downloadToken") or next(iter(tok.values()))
    tmp = fil.with_suffix(fil.suffix + ".del")
    with urllib.request.urlopen(f"{API}/File/GetDataPackageFile?token={urllib.parse.quote(tok)}", timeout=600) as r, \
            open(tmp, "wb") as f:
        n = 0
        while chunk := r.read(1 << 20):
            f.write(chunk)
            n += len(chunk)
            print(f"\r  {fil.name}: {n / 1e6:.0f} MB", end="", flush=True)
    print()
    tmp.rename(fil)
    return fil


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    steg = sys.argv[1]
    if steg == "lista":
        for p in paket():
            print(f"{p['id']:>6}  {p.get('name', '').strip()}  {p.get('description', '') or ''}")
    elif steg == "filer" and len(sys.argv) == 3:
        for f in filer(sys.argv[2]):
            print(("[mapp] " if f.get("isFolder") else "") + f"{f['name']}  {f.get('size', '')}")
    elif steg == "hamta" and len(sys.argv) == 4:
        valda = [f for f in filer(sys.argv[2]) if not f.get("isFolder") and fnmatch.fnmatch(f["name"], sys.argv[3])
                 and not f["name"].endswith("_kvitto.xml")]
        if not valda:
            sys.exit("Inga filer matchar mönstret (se 'filer <paket-id>').")
        for f in valda:
            fil = ladda_ned(sys.argv[2], f["name"])
            if fil.suffix == ".zip":
                with zipfile.ZipFile(fil) as z:
                    z.extractall(fil.parent)
                    print("  uppackat:", ", ".join(z.namelist()))
                fil.unlink()   # zipen behövs inte när den är uppackad
        print("klart ->", UT / sys.argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
