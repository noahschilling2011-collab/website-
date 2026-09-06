"""Erzeugt `core/daten/orte.json`: jedes Land und jede Hauptstadt der Welt.

    python -m scripts.orte_tabelle            # schreibt die Datei neu
    python -m scripts.orte_tabelle --zeigen   # nur ausgeben, nichts schreiben

**Warum eine Datei und nicht jedes Mal eine Abfrage.** `core/orte.py` fragt
Wikidata live - das ist richtig für „Kilimandscharo" oder
„Schwäbisch Gmünd". Für Länder und Hauptstädte ist es die falsche
Abhängigkeit: das sind rund 400 Einträge, die sich im Jahr vielleicht
einmal ändern, und sie müssen auch dann funktionieren, wenn der
Wikidata-Endpunkt gerade wartet oder das Netz weg ist. Deshalb liegen sie
als Datei bei - erzeugt, nicht abgetippt, mit der Abfrage daneben.

Gemessen am 26.08.2026: 206 Zeilen, davon 196 Länder mit ISO-3166-alpha-3,
und für **alle 196** eine Hauptstadt mit Koordinate.

Die Abfrage steht unten im Klartext. Wer das Ergebnis anzweifelt, kann sie
kopieren und selbst bei query.wikidata.org ausführen.

**Ein Befund vom 26.08.2026, der hier nicht verschwiegen wird.** In der
Umgebung, in der diese Datei entstand, antwortet Wikidata auf `httpx`
durchgehend mit **403** („Please respect our robot policy"), auf `curl`
mit **200** - bei gleichem User-Agent, gleichem Accept, gleicher Methode,
durch denselben Proxy. Weder Header noch GET/POST machten einen
Unterschied. Ob das an jener Umgebung liegt oder allgemein gilt, ließ sich
von dort nicht entscheiden.

Deshalb gibt es `--aus-datei`: die Antwort einmal per curl holen,

    curl -sG https://query.wikidata.org/sparql \
      --data-urlencode query@abfrage.rq \
      -H "Accept: application/sparql-results+json" \
      -H "User-Agent: JARVIS/0.1 (dein-name@example.org)" -o roh.json

    python -m scripts.orte_tabelle --aus-datei roh.json

und derselbe Code baut daraus die Tabelle. Der normale Weg ohne
`--aus-datei` bleibt drin und ist der gemeinte - er wurde hier nur nicht
grün gesehen.

Und es ist der zweite Grund für die Datei: **Länder und Hauptstädte
funktionieren damit ganz ohne Netz.**
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import httpx

WURZEL = Path(__file__).resolve().parent.parent
ZIEL = WURZEL / "core" / "daten" / "orte.json"
ENDPUNKT = "https://query.wikidata.org/sparql"

# Q3624078 = souveräner Staat. Q3024240 = historischer Staat - die fliegen
# raus, sonst steht die DDR neben Deutschland.
ABFRAGE = """
SELECT ?land ?iso3 ?landKoord ?landDe ?landEn ?hs ?hsKoord ?hsDe ?hsEn WHERE {
  ?land wdt:P31 wd:Q3624078 .
  FILTER NOT EXISTS { ?land wdt:P31 wd:Q3024240 }
  ?land wdt:P298 ?iso3 .
  ?land wdt:P625 ?landKoord .
  ?land wdt:P36 ?hs .
  ?hs wdt:P625 ?hsKoord .
  OPTIONAL { ?land rdfs:label ?landDe FILTER(LANG(?landDe) = "de") }
  OPTIONAL { ?land rdfs:label ?landEn FILTER(LANG(?landEn) = "en") }
  OPTIONAL { ?hs   rdfs:label ?hsDe   FILTER(LANG(?hsDe)   = "de") }
  OPTIONAL { ?hs   rdfs:label ?hsEn   FILTER(LANG(?hsEn)   = "en") }
}
"""


def _iso_nach_a3() -> dict[str, dict]:
    """Aus static/vendor/iso3166.json: {"DEU": {"a2": "DE", "name": "Germany"}}."""
    pfad = WURZEL / "static" / "vendor" / "iso3166.json"
    roh = json.loads(pfad.read_text(encoding="utf-8"))
    return {e["a3"]: e for e in roh.values() if e.get("a3")}


ISO_NACH_A3 = _iso_nach_a3()


def punkt(wkt: str) -> tuple[float, float]:
    """"Point(9.8 48.8)" -> (lat, lon). Laenge steht zuerst im WKT."""
    roh = wkt.strip().removeprefix("Point(").rstrip(")")
    lon, lat = (float(x) for x in roh.split())
    return lat, lon


def hole(kontakt: str) -> list[dict]:
    kopf = {
        "user-agent": f"JARVIS/0.1 (persoenlicher Assistent; {kontakt})",
        "accept": "application/sparql-results+json",
    }
    antwort = httpx.get(ENDPUNKT, params={"query": ABFRAGE}, headers=kopf,
                        timeout=120.0, follow_redirects=True)
    antwort.raise_for_status()
    return antwort.json()["results"]["bindings"]


def baue(zeilen: list[dict]) -> list[dict]:
    """Zwei Eintraege je Zeile: das Land und seine Hauptstadt.

    Entdoppelt ueber die Entitaets-URI. Wikidata liefert ein Land mehrfach,
    wenn es mehrere Hauptstadt-Angaben hat (etwa eine Regierungs- und eine
    Verfassungshauptstadt) - dann stehen beide drin, aber jede nur einmal.
    """
    orte: dict[str, dict] = {}
    for z in zeilen:
        iso3 = z["iso3"]["value"]
        for art, uri_key, koord_key, de_key, en_key in (
            ("land", "land", "landKoord", "landDe", "landEn"),
            ("hauptstadt", "hs", "hsKoord", "hsDe", "hsEn"),
        ):
            uri = z[uri_key]["value"]
            if uri in orte:
                continue
            lat, lon = punkt(z[koord_key]["value"])
            namen = [z[k]["value"] for k in (de_key, en_key) if k in z]
            if not namen:
                continue
            # Der ANZEIGENAME ist der erste echte Name, deutsch bevorzugt -
            # und wird hier festgehalten, BEVOR die ISO-Codes dazukommen.
            # Sonst gewinnt "DE" die alphabetische Sortierung und JARVIS
            # sagt "DE" statt "Deutschland". (Genau so passiert.)
            anzeige = namen[0]
            if art == "land":
                # Die amtlichen Labels reichen nicht: niemand tippt
                # "Vereinigte Staaten", alle tippen "USA". Die ISO-Codes und
                # der englische ISO-Name liegen schon im Projekt
                # (static/vendor/iso3166.json) - dafuer braucht es keine
                # zweite Abfrage.
                iso = ISO_NACH_A3.get(iso3)
                if iso:
                    namen += [iso3, iso["a2"], iso["name"]]
            orte[uri] = {
                "qid": uri.rsplit("/", 1)[-1],
                "art": art,
                "iso3": iso3,
                "name": anzeige,
                "namen": sorted(dict.fromkeys(namen)),
                "lat": round(lat, 5),
                "lon": round(lon, 5),
            }
    return sorted(orte.values(), key=lambda o: (o["iso3"], o["art"]))


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--kontakt", default="jarvis@example.org",
                   help="Kontakt fuer den User-Agent (Wikimedia verlangt ihn).")
    p.add_argument("--zeigen", action="store_true",
                   help="Nur ausgeben, nichts schreiben.")
    p.add_argument("--aus-datei", metavar="PFAD",
                   help="Eine bereits geholte SPARQL-Antwort verarbeiten, "
                        "statt neu zu fragen. Siehe den Hinweis im Kopf "
                        "dieser Datei.")
    args = p.parse_args()

    if args.aus_datei:
        print(f"Lese {args.aus_datei} …")
        zeilen = json.loads(Path(args.aus_datei).read_text(encoding="utf-8"))
        zeilen = zeilen["results"]["bindings"]
    else:
        print(f"Frage {ENDPUNKT} …")
        zeilen = hole(args.kontakt)
    orte = baue(zeilen)
    laender = sum(1 for o in orte if o["art"] == "land")
    haupt = sum(1 for o in orte if o["art"] == "hauptstadt")
    print(f"{len(orte)} Orte: {laender} Laender, {haupt} Hauptstaedte")

    if laender < 180:
        print(f"ABBRUCH: nur {laender} Laender - das kann nicht stimmen. "
              "Die alte Datei bleibt liegen.", file=sys.stderr)
        return 1

    inhalt = {
        "erzeugt": time.strftime("%Y-%m-%d", time.gmtime()),
        "quelle": "Wikidata (query.wikidata.org). Abfrage: scripts/orte_tabelle.py",
        "laender": laender,
        "hauptstaedte": haupt,
        "orte": orte,
    }
    if args.zeigen:
        print(json.dumps(inhalt, ensure_ascii=False, indent=2)[:2000])
        return 0

    ZIEL.parent.mkdir(parents=True, exist_ok=True)
    ZIEL.write_text(
        json.dumps(inhalt, ensure_ascii=False, indent=1) + "\n", encoding="utf-8"
    )
    print(f"geschrieben: {ZIEL.relative_to(WURZEL)} "
          f"({ZIEL.stat().st_size // 1024} kB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
