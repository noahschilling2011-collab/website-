"""Was der Agent nicht tut (docs/satellite.md, A.6).

> Der Agent baut kein Ueberwachungswerkzeug. Wiederholte, terminierte
> Beobachtung eines einzelnen privaten Grundstuecks oder einer bestimmten
> Person ist kein Anwendungsfall, auch wenn die Daten oeffentlich sind.

Das hier ist die **erste** Verteidigungslinie, nicht die einzige und keine
perfekte: eine Stichwortpruefung erkennt die offensichtlichen Faelle und
laesst sich umformulieren. Die zweite Linie ist der Systemprompt, die dritte
die Bodenaufloesung selbst - bei 10 m/px ist ein Grundstueck ein Pixel.

Bewusst kein Modellaufruf: eine Ablehnung, die vom Tagesform eines Modells
abhaengt, ist keine Regel.
"""

from __future__ import annotations

import re

UeberwachungMuster = [
    # Nachbarn, konkrete Personen, Privatgrundstuecke
    re.compile(r"\bnachbar\w*\b", re.IGNORECASE),
    re.compile(r"\b(grundstueck|grundstück|garten|hof|einfahrt|garage)\b.{0,40}"
               r"\b(von|des|der|meines|meiner)\b", re.IGNORECASE),
    re.compile(r"\b(ueberwach|überwach|beschatt|ausspion|spionier)\w*", re.IGNORECASE),
    re.compile(r"\bwohnt\b|\bwohnhaus von\b|\bprivatadresse\b", re.IGNORECASE),
    # Wiederholte, terminierte Beobachtung eines Punktes
    re.compile(r"\b(jeden tag|taeglich|täglich|jede woche|woechentlich|wöchentlich"
               r"|regelmaessig|regelmäßig)\b.{0,60}"
               r"\b(beobacht|ueberwach|überwach|kontrollier|im auge)\w*",
               re.IGNORECASE),
]


class UeberwachungAbgelehnt(PermissionError):
    pass


BEGRUENDUNG = (
    "Das lehne ich ab: wiederholte oder gezielte Beobachtung eines einzelnen "
    "Grundstuecks oder einer Person ist kein Anwendungsfall fuer diesen "
    "Agenten, auch wenn die Daten oeffentlich sind.\n\n"
    "Wofuer er da ist: Umweltmonitoring, Katastrophenlagen, Landnutzung, "
    "Bildung - Abholzung, Ueberschwemmungen, Baustellen, Brandflaechen, "
    "Gewaesserstaende.\n\n"
    "Nebenbei: bei 10 m Bodenaufloesung ist ein Einfamilienhaus ein einziges "
    "Pixel. Selbst wenn ich wollte, saehe man dort nichts."
)


def pruefe_anfrage(text: str) -> None:
    """Wirft `UeberwachungAbgelehnt`, wenn die Anfrage auf Beobachtung zielt."""
    for muster in UeberwachungMuster:
        if muster.search(text):
            raise UeberwachungAbgelehnt(BEGRUENDUNG)
