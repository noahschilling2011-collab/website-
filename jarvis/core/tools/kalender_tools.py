"""Kalender lesen (FIX-07 Abschnitt 4).

Die Mechanik steht in `core/kalender.py`. `READ` - es wird gelesen, nichts
angelegt. `termin_anlegen` waere `EXTERNAL` und bestaetigungspflichtig; das
kommt erst, wenn Noah es will und die Abnahme dieser drei Werkzeuge durch
ist (FIX-07 Abschnitt 6).

**Ein leerer Kalender und ein nicht eingerichteter Kalender sehen gleich
aus** - und der Unterschied ist genau der zwischen "du hast heute frei" und
"ich weiss es nicht". Deshalb ist die Antwort ohne `KALENDER_QUELLE` kein
leeres Ergebnis, sondern ein Satz.
"""

from __future__ import annotations

import time
from datetime import date, timedelta

from core.contracts import Permission, Tool, ToolResult
from core.kalender import (
    AUSBLICK,
    KalenderFehler,
    hole,
    im_fenster,
    in_anzeigezone,
    parse,
    zonenname,
)
from core.tools.registry import register


def _datum(wert: str | None, ersatz: date) -> date:
    if not wert:
        return ersatz
    return date.fromisoformat(str(wert).strip()[:10])


@register
class Kalender(Tool):
    name = "kalender"
    description = (
        "Liest Termine aus Noahs Kalender in einem Zeitfenster; ohne Angabe von heute bis in sieben Tagen.\n"
        "Nimm es fuer: \"was habe ich morgen vor?\", \"wann ist der Zahnarzt?\" - alles, wo ein Eintrag im Kalender die Antwort ist. Das heutige Datum fuer von/bis liefert dir clock; wiederkehrende Termine werden gezaehlt, nicht aufgeloest.\n"
        "Nimm es NICHT fuer: Uhrzeit, heutiges Datum oder Wochentag - das gibt clock.\n"
        "Beispiel: kalender(von=\"2026-08-28\", bis=\"2026-08-30\")"
    )
    parameters = {
        "type": "object",
        "properties": {
            "von": {
                "type": "string",
                "description": "Startdatum als ISO, z. B. 2026-08-27. Vorgabe: heute.",
            },
            "bis": {
                "type": "string",
                "description": "Enddatum als ISO. Vorgabe: heute plus sieben Tage.",
            },
        },
        "required": [],
        "additionalProperties": False,
    }
    permission = Permission.READ
    timeout_s = 25

    # Werden beim App-Start gesetzt, wie db_path bei den anderen.
    kalender_quelle: str = ""
    db_path: str = ""

    async def execute(self, von: str = "", bis: str = "") -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        try:
            # `date.today()` ist das Datum der Systemzeitzone - also ein
            # Ortsdatum, genau wie das, was das Modell vom `clock`-Werkzeug
            # bekommt. Bis zur Verknuepfungspruefung 31.08.2026 (Fund 3) hat
            # `im_fenster` daraus ein UTC-Fenster gebaut; jetzt baut es
            # Mitternacht in derselben Ortszone, aus der dieses Datum kommt.
            # Deshalb bleibt hier `date.today()` stehen - Datum und
            # Fenstergrenze stammen ab sofort aus derselben Quelle.
            a = _datum(von, date.today())
            b = _datum(bis, a + timedelta(days=7))
        except ValueError:
            return ToolResult(
                ok=False, error="Datum nicht lesbar.",
                display="Datum bitte als ISO angeben, z. B. 2026-08-27.",
                duration_ms=dauer(),
            )
        if b < a:
            a, b = b, a

        try:
            roh, aus_cache = await hole(
                self.kalender_quelle, db_path=self.db_path
            )
        except KalenderFehler as exc:
            # Der wichtigste Fall: keine Quelle eingetragen. Das ist KEIN
            # leerer Kalender.
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())
        except OSError as exc:
            return ToolResult(ok=False, error=str(exc),
                              display=f"Kalender nicht lesbar: {exc}",
                              duration_ms=dauer())

        alle, wiederkehrend, nicht_lesbar = parse(roh)
        treffer = im_fenster(alle, a, b)
        zone_heisst = zonenname(a)

        zeilen = []
        for t in treffer:
            if t.ganztaegig:
                # Ein Ganztagstermin ist ein DATUM, kein Zeitpunkt (RFC 5545,
                # 3.3.4) - da gibt es nichts umzurechnen.
                wann = f"{t.beginn.isoformat()} (ganztaegig)"
            else:
                # WAS WAR FALSCH (Verknuepfungspruefung 31.08.2026, Fund 2):
                # hier stand `t.beginn.strftime(...)` ohne `astimezone`.
                # `strftime` druckt die Wanduhrzeit DER ZONE, die am Objekt
                # haengt - und die ist je nach Feed UTC (DTSTART mit `Z`,
                # also Outlook, iCloud, die meisten Exporte) oder die
                # Kalenderzone (DTSTART mit TZID, also Google).
                # WARUM DAS FALSCH IST: zwei Termine, die real zwei Stunden
                # auseinanderliegen, bekamen dieselbe Uhrzeit gedruckt.
                # JARVIS sagte "Zahnarzt um 12:00", der Termin war um 14:00 -
                # und die Ausgabe nannte keine Zone, an der jemand haette
                # stutzig werden koennen. `core/satellite/ueberflug.py:107-110`
                # macht es richtig vor und schreibt "UTC" daneben; deshalb
                # steht die Zone jetzt auch hier im Kopf der Antwort.
                wann = in_anzeigezone(t.beginn).strftime("%Y-%m-%d %H:%M")
                wann += in_anzeigezone(t.ende).strftime(" bis %H:%M")
            zeilen.append(f"{wann}  {t.titel}" + (f"  [{t.ort}]" if t.ort else ""))

        hinweis = ""
        if wiederkehrend:
            hinweis = (
                f"\n\n{wiederkehrend} wiederkehrende Termine im Kalender nicht "
                f"aufgeloest - siehe Kalender-App. {AUSBLICK}"
            )
        if nicht_lesbar:
            # Fund 1: dasselbe Versprechen wie fuer wiederkehrende Termine.
            # Weglassen ja, verschweigen nein - sonst nennt die Antwort eine
            # Zahl, die zu niedrig ist, und niemand kann es merken.
            hinweis += (
                f"\n\n{nicht_lesbar} Termine im Kalender waren nicht lesbar "
                f"und fehlen in dieser Liste - im Log steht, welche."
            )

        kopf = (
            f"{len(treffer)} Termine vom {a.isoformat()} bis {b.isoformat()}"
            f" (alle Zeiten in {zone_heisst})"
        )
        if aus_cache:
            kopf += " (aus dem Zwischenspeicher, hoechstens 15 Minuten alt)"

        return ToolResult(
            ok=True,
            data={
                "termine": [t.als_dict() for t in treffer],
                "von": a.isoformat(),
                "bis": b.isoformat(),
                "zeitzone": zone_heisst,
                "wiederkehrend_nicht_aufgeloest": wiederkehrend,
                "nicht_lesbar": nicht_lesbar,
                "aus_cache": aus_cache,
            },
            display=kopf + (":\n" + "\n".join(zeilen) if zeilen else ".") + hinweis,
            duration_ms=dauer(),
        )
