"""Erinnerungen aus dem Gespraech heraus (FIX-09).

"Erinnere mich morgen um acht an den Zahnarzt" - das legt einen Zeitplan
an (core/zeitplan.py), einmalig oder wiederkehrend. Zur Zeit startet JARVIS
daraus einen ganz normalen Auftrag, dessen Antwort die Erinnerung ist; sie
erscheint im Chat mit Herkunft "Zeitplan" und als Hinweis am Chat-Tab.

Was das Werkzeug NICHT kann: Rechte ausweiten. Der Lauf hat die Grenzen
jedes Zeitplans - hoechstens LOCAL, Tagesdeckel, unbeaufsichtigt. Und mehr
als MAX_PLAENE Plaene gibt es nicht, egal wer sie anlegt.
"""

from __future__ import annotations

import time
from pathlib import Path

from core import zeitplan
from core.contracts import Permission, Tool, ToolResult
from core.tools.registry import register


@register
class ErinnerungAnlegen(Tool):
    name = "erinnerung_anlegen"
    description = (
        "Legt eine Erinnerung oder einen wiederkehrenden Auftrag an, den JARVIS spaeter von selbst ausfuehrt.\n"
        "Nimm es fuer: \"erinnere mich morgen um 8 an den Zahnarzt\", \"jeden Morgen um 7 die Morgenlage\", \"alle 6 Stunden nachsehen\". Rechne die Uhrzeit vorher mit clock aus, wenn der Nutzer relativ spricht (\"in zwei Stunden\", \"morgen\").\n"
        "Nimm es NICHT fuer: Dinge, die JARVIS jetzt sofort tun soll - die machst du direkt; auch nicht fuer Termine in einem Kalender (das ist kalender, und der ist hier nur lesbar).\n"
        "Beispiel: erinnerung_anlegen(text=\"Zahnarzt anrufen\", wann=\"einmal 2026-09-06 08:00\")"
    )
    parameters = {
        "type": "object",
        "properties": {
            "text": {
                "type": "string",
                "description": "Woran erinnert werden soll, als kurzer Satz.",
            },
            "wann": {
                "type": "string",
                "description": (
                    "Genau eine von drei Formen: 'einmal JJJJ-MM-TT HH:MM' (Ortszeit), "
                    "'taeglich HH:MM' oder 'alle N stunden'."
                ),
            },
        },
        "required": ["text", "wann"],
        "additionalProperties": False,
    }
    permission = Permission.LOCAL

    # Wird beim App-Start gesetzt (api/app.py), nicht importiert.
    db_path: Path | str = ""

    async def execute(self, text: str, wann: str) -> ToolResult:
        begonnen = time.monotonic()
        if not self.db_path:
            hinweis = "Erinnerungen sind nicht eingerichtet (kein Datenbankpfad)."
            return ToolResult(ok=False, error=hinweis, display=hinweis)
        text = " ".join(str(text or "").split())
        if not text:
            return ToolResult(ok=False, error="Kein Text.", display="Woran soll ich erinnern?")
        try:
            regel = zeitplan.lies_regel(wann)
            plan = zeitplan.anlegen(
                self.db_path,
                name=text[:40],
                ziel=(f"Erinnere den Nutzer jetzt daran: {text}. Antworte mit genau "
                      f"einer kurzen Erinnerung in einem Satz, ohne Werkzeuge."),
                regel_text=regel.text,
            )
        except ValueError as exc:      # RegelUngueltig ist ein ValueError
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=int((time.monotonic() - begonnen) * 1000))
        lokal = zeitplan._aus_z(plan["naechster_lauf"]).astimezone().strftime("%d.%m.%Y %H:%M")
        art = "einmalig" if regel.einmalig else regel.text
        anzeige = f"Erinnerung angelegt: „{text}“ - {art}, naechster Lauf {lokal}."
        return ToolResult(
            ok=True,
            data={"id": plan["id"], "regel": plan["regel"],
                  "naechster_lauf": plan["naechster_lauf"]},
            display=anzeige,
            duration_ms=int((time.monotonic() - begonnen) * 1000),
        )
