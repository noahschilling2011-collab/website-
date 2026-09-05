"""Links, die kein Werkzeug geliefert hat, kommen aus dem Gedaechtnis.

Beobachtet am 26.08.2026, erster Lauf mit einem echten Modell: der
Satelliten-Agent scheiterte an fehlenden CDSE-Zugangsdaten - richtig - und
haengte an seine Meldung drei Quellen-URLs. Er hat weder `web_search` noch
`fetch_url` (`core/agents.py`: `tools=["satellite_search",
"satellite_compare", "calculator", "clock"]`), kann also keine Seite
abgerufen haben. Eine der drei antwortete beim Nachpruefen gar nicht:

    https://copernicus.eu/en/access-data                       HTTP 200
    https://dataspace.copernicus.eu/                           HTTP 200
    https://sentinel.esa.int/web/sentinel/missions/sentinel-2  HTTP 000

`core/config.py` sagt dem Modell woertlich "Erfinde keine Fakten, keine
Quellen und keine Zahlen", und `core/runner.py` haelt daneben fest: "Ob das
Modell sie im Text zitiert, ist eine Bitte; dass sie unter der Antwort
stehen, ist eine Tatsache."

Eine Bitte reicht nicht. Deshalb steht hier eine Regel: was ein Werkzeug
geliefert hat, bleibt; alles andere fliegt raus und der Leser erfaehrt,
dass es raus ist. Bewusst ohne Modellaufruf und ohne Netz - eine Pruefung,
die vom Tagesform eines Modells oder von der Erreichbarkeit einer Seite
abhaengt, ist keine Regel. Ob ein Link *funktioniert*, ist hier nicht die
Frage; ob ihn jemand *nachgeschlagen* hat, schon.
"""

from __future__ import annotations

import re
from typing import Iterable

# Bewusst schlicht. Endende Satzzeichen gehoeren nicht mehr zur Adresse -
# sonst haengt bei "siehe https://example.org." der Punkt mit drin und der
# Vergleich mit dem Beleg schlaegt fehl.
URL = re.compile(r"https?://[^\s<>\"'`\)\]\},]+", re.IGNORECASE)
_SATZENDE = ".,;:!?"

MARKIERUNG = (
    "[{n} Link(e) entfernt: in diesem Lauf wurde nichts nachgeschlagen. "
    "Angehaengt werden nur Quellen, die ein Werkzeug wirklich geholt hat.]"
)


def _normalisiert(url: str) -> str:
    return url.rstrip(_SATZENDE).rstrip("/").lower()


def finde_urls(text: str) -> list[str]:
    """Alle Adressen im Text, ohne anhaengendes Satzzeichen."""
    return [treffer.rstrip(_SATZENDE) for treffer in URL.findall(text or "")]


def belegte_urls(*quellen: Iterable[str]) -> set[str]:
    """Was Werkzeuge geliefert haben - als Vergleichsmenge.

    Nimmt sowohl fertige URL-Listen (`ToolResult.sources`) als auch freien
    Text (`ToolResult.display`): eine Adresse, die im Ergebnis eines
    Werkzeugs steht, ist nachgeschlagen, auch wenn sie nicht in `sources`
    gelandet ist.
    """
    belegt: set[str] = set()
    for gruppe in quellen:
        for eintrag in gruppe:
            if not eintrag:
                continue
            gefunden = finde_urls(eintrag)
            # Ein reiner URL-Eintrag findet sich selbst; ein Fliesstext
            # liefert die Adressen, die darin vorkommen.
            for url in gefunden or [eintrag]:
                belegt.add(_normalisiert(url))
    return belegt


def _aufraeumen(text: str) -> str:
    """Was nach dem Entfernen an Satzzeichen uebrigbleibt.

    Aus "(https://a; https://b)" wird sonst "( ; )".
    """
    text = re.sub(r"\(\s*[;,\s]*\)", "", text)
    text = re.sub(r"\[\s*[;,\s]*\]", "", text)
    text = re.sub(r"[ \t]{2,}", " ", text)
    text = re.sub(r" +([.,;:!?])", r"\1", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def ohne_unbelegte_links(text: str, belegt: set[str]) -> tuple[str, int]:
    """Entfernt Adressen, die kein Werkzeug geliefert hat.

    Gibt (bereinigter Text, Anzahl entfernter Adressen) zurueck. Die Anzahl
    zaehlt Vorkommen, nicht verschiedene Adressen: dreimal dieselbe erfundene
    Adresse ist dreimal eine Behauptung.
    """
    if not text:
        return text, 0

    entfernt = 0

    def ersetze(treffer: re.Match[str]) -> str:
        nonlocal entfernt
        roh = treffer.group(0)
        schwanz = ""
        while roh and roh[-1] in _SATZENDE:
            schwanz = roh[-1] + schwanz
            roh = roh[:-1]
        if _normalisiert(roh) in belegt:
            return treffer.group(0)
        entfernt += 1
        return schwanz

    bereinigt = URL.sub(ersetze, text)
    if not entfernt:
        return text, 0
    bereinigt = _aufraeumen(bereinigt)
    hinweis = MARKIERUNG.format(n=entfernt)
    return (f"{bereinigt}\n\n{hinweis}" if bereinigt else hinweis), entfernt
