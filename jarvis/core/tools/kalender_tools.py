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
    parse,
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
        "Termine in einem Zeitfenster, aus Noahs Kalender. Ohne Angabe: "
        "von heute bis in sieben Tagen. Wiederkehrende Termine werden "
        "gezaehlt, aber nicht aufgeloest - das sagt das Ergebnis dazu."
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

        alle, wiederkehrend = parse(roh)
        treffer = im_fenster(alle, a, b)

        zeilen = []
        for t in treffer:
            if t.ganztaegig:
                wann = f"{t.beginn.isoformat()} (ganztaegig)"
            else:
                wann = t.beginn.strftime("%Y-%m-%d %H:%M")
                wann += t.ende.strftime(" bis %H:%M")
            zeilen.append(f"{wann}  {t.titel}" + (f"  [{t.ort}]" if t.ort else ""))

        hinweis = ""
        if wiederkehrend:
            hinweis = (
                f"\n\n{wiederkehrend} wiederkehrende Termine im Kalender nicht "
                f"aufgeloest - siehe Kalender-App. {AUSBLICK}"
            )

        kopf = f"{len(treffer)} Termine vom {a.isoformat()} bis {b.isoformat()}"
        if aus_cache:
            kopf += " (aus dem Zwischenspeicher, hoechstens 15 Minuten alt)"

        return ToolResult(
            ok=True,
            data={
                "termine": [t.als_dict() for t in treffer],
                "von": a.isoformat(),
                "bis": b.isoformat(),
                "wiederkehrend_nicht_aufgeloest": wiederkehrend,
                "aus_cache": aus_cache,
            },
            display=kopf + (":\n" + "\n".join(zeilen) if zeilen else ".") + hinweis,
            duration_ms=dauer(),
        )
