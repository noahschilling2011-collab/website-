"""Jede Abhaengigkeit, die die Suite braucht, steht in `requirements.txt`.

Gefunden bei der Verknuepfungspruefung am 29.08.2026: `playwright`, `Pillow`
und `PyYAML` fehlten dort, obwohl 103 von 1125 Tests sie brauchen.

Das ist heimtueckischer als ein normaler fehlender Import. Die Tests holen
diese Pakete ueber `pytest.importorskip` - ohne sie werden sie **still
uebersprungen** statt rot. Auf einer frischen Installation nach
`pip install -r requirements.txt` haette die Suite also "alles gruen"
gemeldet und dabei sechs Testdateien, den ganzen Globus und beide
Oberflaechen gar nicht ausgefuehrt.

Der Test prueft beide Richtungen nicht: eine Zeile in requirements.txt, die
niemand importiert, ist ein anderes Problem und kostet nur Platz.
"""

from __future__ import annotations

import re
from pathlib import Path

WURZEL = Path(__file__).resolve().parent.parent
ANFORDERUNGEN = WURZEL / "requirements.txt"

# Wie das Paket auf PyPI heisst, wenn der Importname ein anderer ist.
# Nur diese Richtung: aus dem Importname allein laesst sich der Paketname
# nicht ableiten.
PAKETNAME = {
    "PIL": "pillow",
    "yaml": "pyyaml",
    "playwright.sync_api": "playwright",
    "playwright.async_api": "playwright",
    "dotenv": "python-dotenv",
}

# Was zur Standardbibliothek gehoert, steht in keiner Anforderungsdatei.
STDLIB = {"zoneinfo", "sqlite3", "tomllib", "dataclasses"}


def _geforderte_pakete() -> set[str]:
    """Die Paketnamen aus requirements.txt, klein und ohne Versionsangabe."""
    namen = set()
    for zeile in ANFORDERUNGEN.read_text(encoding="utf-8").splitlines():
        zeile = zeile.split("#", 1)[0].strip()
        if not zeile:
            continue
        # fastapi>=0.115 / skyfield==1.55 / uvicorn[standard]>=0.30
        name = re.split(r"[<>=!\[; ]", zeile, 1)[0].strip().lower()
        if name:
            namen.add(name)
    return namen


def _uebersprungene_importe() -> dict[str, list[str]]:
    """Jedes `importorskip("x")` und jedes `from PIL import ...` der Suite."""
    gefunden: dict[str, list[str]] = {}
    # Diese Datei NICHT: sie nennt `importorskip` in ihrem eigenen Text als
    # Beispiel, und der Waechter hat sich prompt daran verschluckt.
    hier = Path(__file__).name
    quellen = [p for p in sorted((WURZEL / "tests").glob("*.py"))
               if p.name != hier]
    quellen += sorted((WURZEL / "scripts").glob("*.py"))
    for pfad in quellen:
        text = pfad.read_text(encoding="utf-8")
        modul_namen = re.findall(r'importorskip\(\s*["\']([\w.]+)["\']', text)
        modul_namen += re.findall(r'^\s*(?:from|import)\s+(PIL|yaml)\b',
                                  text, re.MULTILINE)
        for m in modul_namen:
            gefunden.setdefault(m, []).append(pfad.name)
    return gefunden


def test_jedes_optional_geladene_paket_steht_in_requirements():
    """`importorskip` ist der gefaehrlichste Import im Projekt: fehlt das
    Paket, wird der Test nicht rot, sondern verschwindet."""
    gefordert = _geforderte_pakete()
    fehlt = []
    for modul, dateien in sorted(_uebersprungene_importe().items()):
        wurzel_modul = modul.split(".")[0]
        if wurzel_modul in STDLIB:
            continue
        paket = PAKETNAME.get(modul, PAKETNAME.get(wurzel_modul, wurzel_modul)).lower()
        if paket not in gefordert:
            fehlt.append(
                f"{modul} (Paket {paket!r}) wird von "
                f"{', '.join(sorted(set(dateien)))} gebraucht, steht aber "
                f"nicht in requirements.txt"
            )
    assert fehlt == [], (
        "Diese Tests wuerden auf einer frischen Installation STILL "
        "uebersprungen:\n  " + "\n  ".join(fehlt)
    )


def test_der_wichtigste_fall_ist_wirklich_abgedeckt():
    """Gegenprobe zum Test darueber: er wuerde nichts merken, wenn das
    Einsammeln der Importe leer liefe. Playwright traegt 103 Tests - wenn
    der Test es nicht mehr sieht, ist er kaputt, nicht das Projekt."""
    gefunden = _uebersprungene_importe()
    assert "playwright.sync_api" in gefunden, sorted(gefunden)
    assert len(gefunden["playwright.sync_api"]) >= 6, gefunden["playwright.sync_api"]
