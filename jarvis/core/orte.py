"""Ein Ortsname wird zu Koordinaten.

Damit „zeig mir Schwäbisch Gmünd" auf dem Globus landen kann, muss aus dem
Namen ein Punkt werden. Ohne einen neuen Dienst: JARVIS spricht schon mit
Wikidata (`core/tools/wissen_tools.py`), dort hat praktisch jeder Ort die
Eigenschaft `P625` (Koordinate). Kein zweiter Anbieter, kein zweiter Key,
dieselbe User-Agent-Pflicht wie bisher.

Weltweit, nicht nur Deutschland. Gemessen am 26.08.2026:

    Tokio          -> Point(139.691666666 35.689444444)   EW 14.264.798
    New York City  -> Point(-74.006111111 40.712777777)   EW  8.804.190
    Kilimanjaro    -> Point(37.3268 -3.3376)
    Gibtesnichtstadt123 -> nichts gefunden

**Zwei Eigenheiten, ebenfalls gemessen und hier behandelt:**

1. Wikidata liefert denselben Ort mehrfach, wenn er mehrere
   Einwohner-Angaben hat (verschiedene Stichjahre). Entdoppelt wird über
   die Entitäts-URI, nicht über den Namen.
2. „São Paulo" liefert nach Einwohnern sortiert den **Staat**, nicht die
   Stadt - der Staat hat mehr. Das ist keine Panne, sondern eine echte
   Mehrdeutigkeit. Sie wird gemeldet, nicht versteckt.

**SPARQL-Injektion.** Der Name kommt vom Nutzer und wandert in ein
String-Literal der Abfrage. `"` und `\\` werden maskiert, Zeilenumbrüche
abgewiesen. Ein Name, der die Abfrage verlassen könnte, wird nicht
gestellt - `CLAUDE.md` Regel 5 im Geist: keine fremde Eingabe, die
unmaskiert in etwas Ausführbares wandert.
"""

from __future__ import annotations

import json
import logging
import math
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import httpx

log = logging.getLogger("jarvis")

SPARQL_ENDPUNKT = "https://query.wikidata.org/sparql"

# Aus core/tools/wissen_tools.py - dieselbe Pflicht, derselbe Text.
USER_AGENT_VORLAGE = "JARVIS/0.1 (persoenlicher Assistent; {kontakt})"

# "Point(9.8 48.8)" - Laenge ZUERST. Wer das dreht, landet im Indischen Ozean.
PUNKT = re.compile(r"Point\(\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\)", re.I)

# Ein Grad Breite in Metern; fuer die Laenge kommt der Kosinus dazu.
GRAD_M = 111_320.0


class OrtFehler(RuntimeError):
    pass


@dataclass(frozen=True)
class Ort:
    qid: str
    name: str
    lat: float
    lon: float
    einwohner: int | None = None
    weitere_treffer: int = 0
    # Nur aus der eingebauten Tabelle gefuellt: "land" oder "hauptstadt".
    art: str = ""
    iso3: str = ""

    @property
    def aus_der_tabelle(self) -> bool:
        return bool(self.art)

    def als_dict(self) -> dict:
        return {
            "qid": self.qid,
            "name": self.name,
            "lat": self.lat,
            "lon": self.lon,
            "einwohner": self.einwohner,
            "weitere_treffer": self.weitere_treffer,
            "art": self.art,
            "iso3": self.iso3,
            "quelle": "Tabelle" if self.aus_der_tabelle else "Wikidata",
        }


def maskiere(name: str) -> str:
    """Ein Ortsname, sicher als SPARQL-String-Literal.

    Zeilenumbrueche werden abgewiesen statt maskiert: ein Ortsname hat
    keine, und was hier ankommt, kommt vom Nutzer.
    """
    sauber = (name or "").strip()
    if not sauber:
        raise OrtFehler("Kein Ortsname angegeben.")
    if len(sauber) > 120:
        raise OrtFehler("Der Ortsname ist unsinnig lang.")
    if any(z in sauber for z in "\n\r\t"):
        raise OrtFehler("Ein Ortsname enthaelt keine Zeilenumbrueche.")
    return sauber.replace("\\", "\\\\").replace('"', '\\"')


def baue_frage(name: str) -> str:
    sicher = maskiere(name)
    return (
        "SELECT ?ort ?ortLabel ?koord ?einwohner WHERE {\n"
        f'  VALUES ?name {{ "{sicher}"@de "{sicher}"@en }}\n'
        "  { ?ort rdfs:label ?name } UNION { ?ort skos:altLabel ?name }\n"
        "  ?ort wdt:P625 ?koord .\n"
        "  OPTIONAL { ?ort wdt:P1082 ?einwohner }\n"
        '  SERVICE wikibase:label { bd:serviceParam wikibase:language "de,en". }\n'
        "} ORDER BY DESC(?einwohner) LIMIT 20"
    )


def lies_punkt(wkt: str) -> tuple[float, float]:
    """Aus "Point(9.8 48.8)" wird (lat, lon) - in dieser Reihenfolge.

    WKT nennt die LAENGE zuerst. Hier wird bewusst umgedreht zurueckgegeben,
    weil der Rest des Programms (lat, lon) spricht - und der Tausch soll an
    genau einer Stelle passieren, nicht an fuenf.
    """
    treffer = PUNKT.search(wkt or "")
    if not treffer:
        raise OrtFehler(f"Keine lesbare Koordinate: {wkt!r}")
    lon, lat = float(treffer.group(1)), float(treffer.group(2))
    if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
        raise OrtFehler(f"Koordinate ausserhalb der Erde: {lat}, {lon}")
    return lat, lon


def _auswerten(payload: dict) -> Ort | None:
    zeilen = (payload.get("results") or {}).get("bindings") or []
    gesehen: dict[str, dict] = {}
    for zeile in zeilen:
        uri = (zeile.get("ort") or {}).get("value", "")
        if not uri or uri in gesehen:
            # Derselbe Ort kommt mehrfach, wenn er mehrere
            # Einwohner-Angaben hat. Die erste gewinnt: sortiert ist
            # absteigend, das ist die juengste/groesste.
            continue
        gesehen[uri] = zeile
    if not gesehen:
        return None

    uri, erste = next(iter(gesehen.items()))
    roh_ew = (erste.get("einwohner") or {}).get("value")
    try:
        einwohner = int(float(roh_ew)) if roh_ew else None
    except (TypeError, ValueError):
        einwohner = None
    lat, lon = lies_punkt((erste.get("koord") or {}).get("value", ""))
    return Ort(
        qid=uri.rsplit("/", 1)[-1],
        name=(erste.get("ortLabel") or {}).get("value") or "?",
        lat=lat,
        lon=lon,
        einwohner=einwohner,
        weitere_treffer=len(gesehen) - 1,
    )


# --- Die eingebaute Tabelle -----------------------------------------------
#
# Jedes Land und jede Hauptstadt der Welt, erzeugt von
# `scripts/orte_tabelle.py`. Drei Gruende, warum das eine Datei ist und
# keine Abfrage:
#
# 1. Es sind rund 400 Eintraege, die sich im Jahr vielleicht einmal aendern.
# 2. Sie muessen auch ohne Netz gehen - und ohne WIKI_KONTAKT.
# 3. Wikidata hat beim Bau dieser Datei auf httpx durchgehend mit 403
#    geantwortet und auf curl mit 200 (siehe scripts/orte_tabelle.py). Ob
#    das an der Umgebung lag, war von dort nicht zu entscheiden - aber ein
#    Land soll nicht davon abhaengen.
#
# Alles andere (Berge, Kleinstaedte, Stadtteile) geht weiter live.

TABELLE_PFAD = Path(__file__).resolve().parent / "daten" / "orte.json"

# Fuer den Vergleich: Kleinschreibung, Umlaute aufgeloest, Bindestriche und
# Mehrfach-Leerzeichen weg. Damit findet "schwabisch gmund" auch
# "Schwäbisch Gmünd" - und "SAO PAULO" das São Paulo.
_FALTUNG = str.maketrans({
    "ä": "a", "ö": "o", "ü": "u", "ß": "ss",
    "á": "a", "à": "a", "â": "a", "ã": "a", "å": "a",
    "é": "e", "è": "e", "ê": "e", "ë": "e",
    "í": "i", "ì": "i", "î": "i", "ï": "i",
    "ó": "o", "ò": "o", "ô": "o", "õ": "o", "ø": "o",
    "ú": "u", "ù": "u", "û": "u",
    "ç": "c", "ñ": "n", "ý": "y",
    # Apostrophe in allen Varianten, die in Ortsnamen vorkommen. Wikidata
    # schreibt Nukuʻalofa mit dem ʻOkina (U+02BB) - wer das nicht kennt,
    # findet Tongas Hauptstadt nie.
    "-": " ", "'": "", "’": "", "ʻ": "", "ʼ": "", "`": "", "´": "",
    ".": "",
})


def falte(name: str) -> str:
    return " ".join((name or "").strip().lower().translate(_FALTUNG).split())


# Ein ISO-Code ist ein exaktes Kuerzel, kein unscharfer Name. Er steht
# deshalb in einem EIGENEN Index.
#
# Der Grund ist gemessen: mit beidem im selben Index fand "Poel" (eine
# Insel in der Ostsee) das Land POLEN - "poel" wird durch die
# oe-Ersatzschreibung zu "pol", und das ist Polens ISO-Code. Ein Kuerzel
# darf nur exakt treffen, nie ueber eine Faltung.
ISO_FORM = re.compile(r"^[A-Za-z]{2,3}$")


@lru_cache(maxsize=1)
def _geladen() -> tuple[dict[str, Ort], dict[str, Ort]]:
    """(Namen, ISO-Codes). Einmal gelesen, dann im Speicher."""
    try:
        roh = json.loads(TABELLE_PFAD.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        log.warning("Ortstabelle nicht lesbar (%s) - es geht nur noch live.", exc)
        return {}, {}
    aus: dict[str, Ort] = {}
    codes: dict[str, Ort] = {}
    for eintrag in roh.get("orte", []):
        ort = Ort(
            qid=eintrag["qid"],
            # Der Anzeigename, nicht der erste Suchname: sonst heisst
            # Deutschland "DE", weil die ISO-Codes alphabetisch vorn
            # stehen. Aeltere Dateien ohne "name" fallen zurueck.
            name=eintrag.get("name") or eintrag["namen"][0],
            lat=float(eintrag["lat"]),
            lon=float(eintrag["lon"]),
            art=eintrag.get("art", ""),
            iso3=eintrag.get("iso3", ""),
        )
        for name in eintrag["namen"]:
            if ISO_FORM.match(name):
                codes.setdefault(name.upper(), ort)
                continue
            schluessel = falte(name)
            # Ein Land gewinnt gegen eine Hauptstadt gleichen Namens
            # (Luxemburg, Singapur, Dschibuti, Guatemala ...): wer "Monaco"
            # sagt, meint fast immer den Staat.
            if schluessel in aus and aus[schluessel].art == "land":
                continue
            aus[schluessel] = ort
    return aus, codes


def tabelle() -> dict[str, Ort]:
    return _geladen()[0]


def iso_codes() -> dict[str, Ort]:
    return _geladen()[1]


# Wer keine Umlaute tippt, schreibt "oe" statt "ö". Die Faltung oben macht
# aus "ö" ein "o" - "Koenigreich" und "Königreich" landen also auf
# verschiedenen Schluesseln. Ein zweiter Versuch fängt das, statt die
# Ersetzung in den Hauptindex zu ziehen: dort wuerde sie Falschtreffer
# erzeugen (aus "Poel" wuerde "Pol").
_UMSCHRIFT = (("oe", "o"), ("ae", "a"), ("ue", "u"), ("ss", "s"))


def aus_tabelle(name: str) -> Ort | None:
    roh = (name or "").strip()
    # 1. Ein Kuerzel trifft nur exakt: "DE", "DEU", "US".
    if ISO_FORM.match(roh):
        treffer = iso_codes().get(roh.upper())
        if treffer is not None:
            return treffer
    # 2. Der Name, gefaltet.
    schluessel = falte(roh)
    treffer = tabelle().get(schluessel)
    if treffer is not None:
        return treffer
    # 3. Zweiter Versuch fuer wer keine Umlaute tippt.
    zweiter = schluessel
    for lang, kurz in _UMSCHRIFT:
        zweiter = zweiter.replace(lang, kurz)
    return tabelle().get(zweiter) if zweiter != schluessel else None


async def finde_ort(
    name: str,
    *,
    kontakt: str,
    transport: httpx.AsyncBaseTransport | None = None,
    timeout: float = 20.0,
    nur_tabelle: bool = False,
) -> Ort | None:
    """Der beste Treffer, oder None. Wirft nur bei kaputter Eingabe/Antwort.

    Erst die eingebaute Tabelle (jedes Land, jede Hauptstadt - ohne Netz,
    ohne Key), dann Wikidata live fuer alles andere.
    """
    aus_der_tabelle = aus_tabelle(name)
    if aus_der_tabelle is not None:
        return aus_der_tabelle
    if nur_tabelle:
        return None
    if not kontakt.strip():
        raise OrtFehler(
            "WIKI_KONTAKT fehlt in der .env. Wikimedia verlangt einen "
            "User-Agent mit Kontaktangabe - ohne den wird nicht angefragt."
        )
    frage = baue_frage(name)
    kopf = {
        "user-agent": USER_AGENT_VORLAGE.format(kontakt=kontakt),
        "accept": "application/sparql-results+json",
    }
    async with httpx.AsyncClient(timeout=timeout, transport=transport) as client:
        antwort = await client.get(
            SPARQL_ENDPUNKT, params={"query": frage}, headers=kopf
        )
    if antwort.status_code >= 400:
        raise OrtFehler(
            f"Wikidata antwortete mit HTTP {antwort.status_code}."
        )
    try:
        payload = antwort.json()
    except ValueError as exc:
        raise OrtFehler(f"Wikidata antwortete kein JSON: {exc}") from exc
    return _auswerten(payload)


def bbox_um(lat: float, lon: float, kante_km: float = 12.0) -> tuple[float, float, float, float]:
    """Ein quadratischer Ausschnitt um den Punkt, in Grad.

    12 km Kante ist der Vorgabewert, weil das auf 512 Bildpixeln rund 23 m
    je Pixel ergibt - nahe an der Sensorgrenze von Sentinel-2 und damit das
    Schaerfste, was hier ueberhaupt zu holen ist. Ein ganzes Land auf
    dieselben 512 Pixel waeren Kilometer je Pixel.
    """
    if kante_km <= 0:
        raise OrtFehler("Die Kantenlaenge muss groesser als null sein.")
    halb_lat = (kante_km * 1000.0 / 2.0) / GRAD_M
    # Nahe den Polen wird der Kosinus winzig; ohne Untergrenze wuerde der
    # Ausschnitt in Laengenrichtung um die halbe Erde laufen.
    kosinus = max(math.cos(math.radians(lat)), 0.05)
    halb_lon = halb_lat / kosinus
    return (
        max(-180.0, lon - halb_lon),
        max(-90.0, lat - halb_lat),
        min(180.0, lon + halb_lon),
        min(90.0, lat + halb_lat),
    )
