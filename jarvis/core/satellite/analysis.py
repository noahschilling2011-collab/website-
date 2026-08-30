"""Change Detection, ehrlich implementiert (docs/satellite.md, A.5).

Der Auftrag ist da eindeutig:

> Nicht: "zwei Bilder ans Vision-Modell, frag was sich geaendert hat." Das
> produziert selbstbewussten Unsinn.

Also in dieser Reihenfolge:

1. geometrisch abgleichen (gleiche Bounding Box, gleiches Raster),
2. Vergleichbarkeit pruefen (Jahreszeit, Wolken) - sonst melden statt rechnen,
3. **numerisch** rechnen (NDVI, NDWI, NBR),
4. erst dann ein Modell, mit hartem Kontext,
5. Ausgabeformat erzwingen, inklusive der Pflichtzeile GRENZE.

Gerechnet wird in reinem Python auf Listen. Kein numpy - der Stack ist
festgelegt, und fuer eine Vorschaukachel von 256x256 reicht es. Fuer grosse
Raster waere das zu langsam; deshalb steht unten eine harte Obergrenze,
statt es stillschweigend trotzdem zu versuchen.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import datetime

# Aus A.4: "keine Objekte unterhalb von etwa 3x der Bodenaufloesung benennen".
GRENZE_FAKTOR = 3.0

# Reines Python. Darueber wird abgelehnt statt minutenlang gerechnet.
MAX_PIXEL = 512 * 512

# Ab hier gilt eine NDVI-Aenderung als Veraenderung und nicht als Rauschen.
# Der Wert stammt aus A.5 ("NDVI-Rueckgang > 0.3") und ist bewusst grob.
NDVI_SCHWELLE = 0.3

# strftime("%B") haengt an der Locale des Rechners - auf einem englischen
# System stuende "July" in einer deutschen Meldung.
MONATE = [
    "Januar", "Februar", "Maerz", "April", "Mai", "Juni",
    "Juli", "August", "September", "Oktober", "November", "Dezember",
]


def beurteilbar(groesse_m: float, aufloesung_m: float) -> bool:
    """Ist ein Objekt dieser Groesse bei dieser Aufloesung ueberhaupt beurteilbar?"""
    return groesse_m >= GRENZE_FAKTOR * aufloesung_m


def grenzsatz(aufloesung_m: float) -> str:
    """Die Pflichtzeile GRENZE. Ohne sie ist die Ausgabe unvollstaendig."""
    return (
        f"Objekte unter {GRENZE_FAKTOR * aufloesung_m:.0f} m sind bei "
        f"{aufloesung_m:g} m/px nicht beurteilbar."
    )


def _index(a: list[float], b: list[float]) -> list[float]:
    """(a - b) / (a + b), der Bauplan aller genannten Indizes."""
    if len(a) != len(b):
        raise ValueError("Baender haben unterschiedliche Laenge.")
    werte = []
    for x, y in zip(a, b):
        nenner = x + y
        werte.append(0.0 if nenner == 0 else (x - y) / nenner)
    return werte


def ndvi(nir: list[float], rot: list[float]) -> list[float]:
    """Vegetation."""
    return _index(nir, rot)


def ndwi(gruen: list[float], nir: list[float]) -> list[float]:
    """Wasser."""
    return _index(gruen, nir)


def nbr(nir: list[float], swir: list[float]) -> list[float]:
    """Brandflaechen."""
    return _index(nir, swir)


def vergleichbar(
    a_datum: datetime,
    b_datum: datetime,
    a_wolken: float,
    b_wolken: float,
    *,
    max_wolken: float = 20.0,
    max_monatsabstand: int = 2,
) -> tuple[bool, str]:
    """A.5 Schritt 2. Gibt (vergleichbar, Begruendung) zurueck.

    Sommer gegen Winter ist kein Change, das ist Vegetation. Ist die Bedingung
    verletzt, wird gemeldet - nicht gerechnet.
    """
    if a_wolken > max_wolken or b_wolken > max_wolken:
        return False, (
            f"Zu bewoelkt fuer einen Vergleich: {a_wolken:.0f} % und "
            f"{b_wolken:.0f} %, erlaubt sind bis {max_wolken:.0f} %."
        )

    # Abstand im Jahreslauf, ueber den Jahreswechsel hinweg gerechnet.
    abstand = abs(a_datum.month - b_datum.month)
    abstand = min(abstand, 12 - abstand)
    if abstand > max_monatsabstand:
        return False, (
            f"Die Aufnahmen liegen {abstand} Monate im Jahreslauf auseinander "
            f"({MONATE[a_datum.month - 1]} vs. {MONATE[b_datum.month - 1]}). Was man "
            "dann sieht, ist die Jahreszeit und nicht die Veraenderung. "
            "Such eine Aufnahme aus einem aehnlichen Zeitraum."
        )
    return True, "vergleichbar"


@dataclass
class Vergleich:
    """Das Ergebnis der numerischen Auswertung - vor jedem Modellaufruf."""

    pixel: int
    aufloesung_m: float
    veraendert_pixel: int
    mittlere_aenderung: float
    groesste_abnahme: float
    groesste_zunahme: float
    hektar: float = field(init=False)
    beurteilbar: bool = field(init=False)

    def __post_init__(self) -> None:
        flaeche_m2 = self.veraendert_pixel * self.aufloesung_m**2
        self.hektar = flaeche_m2 / 10_000
        # Hier wird `beurteilbar()` endlich BENUTZT. Bis zum 30.08.2026 rief
        # die Funktion niemand im Betrieb auf - STATUS.md beschrieb sie
        # trotzdem als "Code, keine Bitte". Gefunden bei der
        # Verknuepfungspruefung, von drei Skeptikern bestaetigt.
        #
        # Im Werkzeug selbst kann sie nicht greifen: dort kommt nie eine
        # Objektgroesse an, die kennt nur das Modell. Hier schon. Die
        # veraenderte FLAECHE hat eine Kantenlaenge, und wenn die unter dem
        # Dreifachen der Bodenaufloesung liegt, ist der Befund kleiner als
        # das, was der Sensor aufloesen kann - also Rauschen, nicht Fund.
        #
        # Beispiel bei 10 m/px: die Grenze liegt bei 30 m Kantenlaenge, also
        # 900 m2 oder 9 Pixel. Wer daraus "ein Gebaeude ist verschwunden"
        # macht, liest Zufall.
        kante_m = flaeche_m2 ** 0.5
        self.beurteilbar = beurteilbar(kante_m, self.aufloesung_m)

    def als_dict(self) -> dict:
        return {
            "pixel": self.pixel,
            "resolution_m": self.aufloesung_m,
            "changed_pixels": self.veraendert_pixel,
            "changed_ha": round(self.hektar, 2),
            "mean_delta": round(self.mittlere_aenderung, 4),
            "max_decrease": round(self.groesste_abnahme, 4),
            "max_increase": round(self.groesste_zunahme, 4),
            "beurteilbar": self.beurteilbar,
        }

    def grenzhinweis(self) -> str:
        """Der Satz, der neben der Zahl stehen muss, wenn sie zu klein ist.

        Kein Werfen: die Zahl bleibt richtig, sie traegt nur nichts. Ein
        Abbruch wuerde eine korrekte Messung wegwerfen.
        """
        if self.beurteilbar:
            return ""
        grenze_m = GRENZE_FAKTOR * self.aufloesung_m
        return (
            f"Die veraenderte Flaeche ist zu klein, um sie zu deuten: "
            f"{self.hektar:.2f} ha entsprechen rund "
            f"{(self.hektar * 10_000) ** 0.5:.0f} m Kantenlaenge, die Grenze "
            f"liegt bei {grenze_m:.0f} m ({GRENZE_FAKTOR}x "
            f"{self.aufloesung_m:g} m/px). Die Zahl stimmt, sie traegt nur "
            f"keine Aussage."
        )


def vergleiche_raster(
    vorher: list[float],
    nachher: list[float],
    *,
    aufloesung_m: float,
    schwelle: float = NDVI_SCHWELLE,
) -> Vergleich:
    """A.5 Schritt 3: reproduzierbare Zahlen statt Sprachmodell-Meinungen."""
    if len(vorher) != len(nachher):
        raise ValueError(
            "Die Raster haben unterschiedliche Groesse. Ohne Ko-Registrierung "
            "vergleichst du Versatz, nicht Veraenderung."
        )
    if not vorher:
        raise ValueError("Leeres Raster.")
    if len(vorher) > MAX_PIXEL:
        raise ValueError(
            f"{len(vorher)} Pixel ueberschreiten die Grenze von {MAX_PIXEL}. "
            "Gerechnet wird in reinem Python; groessere Raster gehoeren "
            "vorher verkleinert."
        )

    deltas = [n - v for v, n in zip(vorher, nachher)]
    ueber = [d for d in deltas if abs(d) >= schwelle]
    return Vergleich(
        pixel=len(deltas),
        aufloesung_m=aufloesung_m,
        veraendert_pixel=len(ueber),
        mittlere_aenderung=sum(deltas) / len(deltas),
        groesste_abnahme=min(deltas),
        groesste_zunahme=max(deltas),
    )


def bericht(
    beobachtet: str,
    interpretation: str,
    konfidenz: str,
    grundlage: str,
    aufloesung_m: float,
) -> str:
    """Das Ausgabeformat aus A.5. Die Zeile GRENZE ist Pflicht.

    Sie ist der Unterschied zwischen einem Werkzeug und einem
    Bullshit-Generator.
    """
    if konfidenz not in ("niedrig", "mittel", "hoch"):
        raise ValueError("Konfidenz ist niedrig, mittel oder hoch.")
    return (
        "BEOBACHTET\n"
        f"  {beobachtet.strip()}\n"
        "INTERPRETATION\n"
        f"  {interpretation.strip()}\n"
        f"KONFIDENZ  {konfidenz}\n"
        f"GRUNDLAGE  {grundlage.strip()}\n"
        f"GRENZE     {grenzsatz(aufloesung_m)}"
    )
