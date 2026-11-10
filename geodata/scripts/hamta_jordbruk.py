#!/usr/bin/env python3
"""
Hämtar Jordbruksverkets öppna data (INSPIRE-WFS, ingen inloggning) för en karta:

  jordbruk_skiften.geojson   jordbruksskiften senaste året, med grödkod (grdkod_mar, grdkod_und)
  jordbruk_block.geojson     jordbruksblock senaste året (åker, betesmark ...)
  jordbruk_angsbete.geojson  ängs- och betesmarksinventeringen, naturtyper

    .venv/bin/python -I scripts/hamta_jordbruk.py vidingsjo linghem
    .venv/bin/python -I scripts/hamta_jordbruk.py alla

Rutan tas ur <namn>/omrade.json (vidingsjo och vikbolandet har förval), med 500 m marginal.
Filerna hamnar i <namn>/data/ (vikbolandet: data/), som ignoreras av git.
Grödkoderna: https://jordbruksverket.se/stod/lantbruk-skogsbruk-och-tradgard/sam-ansokan-och-allmant-om-jordbrukarstoden/grodkoder
"""
import json, sys, urllib.parse, urllib.request
from collections import Counter
from pathlib import Path

WFS = "https://epub.sjv.se/inspire/inspire/ows"
GEO = Path(__file__).resolve().parent.parent
LAGER = {
    "skiften": "inspire:senaste_arslager_skifte",
    "block": "inspire:senaste_arslager_block",
    "angsbete": "inspire:HB.Angs-och_betesmarksinventeringen_naturtyper",
}
FORVAL = {  # kartor utan omrade.json: (ruta, datamapp)
    "vidingsjo": ((536120, 6469620, 539500, 6472670), GEO / "vidingsjo" / "data"),
    "vikbolandet": ((586040, 6478956, 592614, 6485950), GEO / "data"),
}
MARGINAL_M = 500
SIDA = 2000


def omraden():
    namn = set(FORVAL) | {p.parent.name for p in GEO.glob("*/omrade.json")}
    return sorted(namn)


def ruta_och_mapp(namn):
    if namn in FORVAL:
        return FORVAL[namn]
    fil = GEO / namn / "omrade.json"
    if not fil.exists():
        sys.exit(f"Okänt område: {namn} (finns: {', '.join(omraden())})")
    return tuple(json.loads(fil.read_text())["ruta"]), GEO / namn / "data"


def hamta_lager(typ, ruta):
    minx, miny, maxx, maxy = ruta
    # EPSG:3006 som urn har axelordningen N, E
    bbox = f"{miny},{minx},{maxy},{maxx},urn:ogc:def:crs:EPSG::3006"
    alla, start = [], 0
    while True:
        q = dict(service="WFS", version="2.0.0", request="GetFeature", typeNames=typ, bbox=bbox,
                 outputFormat="application/json", srsName="EPSG:3006", count=SIDA, startIndex=start)
        with urllib.request.urlopen(f"{WFS}?{urllib.parse.urlencode(q)}", timeout=120) as r:
            d = json.load(r)
        alla += d["features"]
        if len(d["features"]) < SIDA:
            return alla
        start += SIDA


def main():
    namnlista = sys.argv[1:]
    if not namnlista:
        sys.exit(__doc__)
    if namnlista == ["alla"]:
        namnlista = omraden()
    for namn in namnlista:
        ruta, mapp = ruta_och_mapp(namn)
        ruta = (ruta[0] - MARGINAL_M, ruta[1] - MARGINAL_M, ruta[2] + MARGINAL_M, ruta[3] + MARGINAL_M)
        mapp.mkdir(parents=True, exist_ok=True)
        print(f"{namn}: ruta {ruta}")
        for kort, typ in LAGER.items():
            f = hamta_lager(typ, ruta)
            ut = mapp / f"jordbruk_{kort}.geojson"
            ut.write_text(json.dumps({"type": "FeatureCollection", "crs": "EPSG:3006",
                                      "kalla": "Jordbruksverket (öppna data)", "features": f}))
            print(f"  {kort}: {len(f)} ytor -> {ut.relative_to(GEO)}")
            if kort == "skiften" and f:
                ar = Counter(x["properties"].get("arslager") for x in f)
                koder = Counter(x["properties"].get("grdkod_mar") for x in f)
                print(f"    år {dict(ar)}, vanligaste grödkoder {koder.most_common(8)}")


if __name__ == "__main__":
    main()
