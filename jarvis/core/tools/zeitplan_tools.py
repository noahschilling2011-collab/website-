"""Erinnerungen aus dem Gespraech heraus (FIX-09).

"Erinnere mich morgen um acht an den Zahnarzt" - das legt einen Zeitplan
an (core/zeitplan.py), einmalig oder wiederkehrend. Der Text selbst ist
die Nachricht: zur faelligen Zeit schreibt die Schleife ihn mit Herkunft
"Erinnerung" in den Verlauf und meldet ihn der Oberflaeche - ohne Planer,
ohne Werkzeuge, ohne Modellaufruf (Pruefrunde FIX-09: ein Lauf mit
Werkzeugen waere eine Flaeche fuer Anweisungen im Text gewesen).

Was das Werkzeug NICHT kann: mehr als MAX_PLAENE lebende Plaene anlegen,
egal wer es ruft - und Texte laenger als MAX_TEXT ablegen.
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
        "Legt eine Erinnerung an, die spaeter von selbst im Chat erscheint - einmalig oder wiederkehrend.\n"
        "Nimm es fuer: \"erinnere mich morgen um 8 an den Zahnarzt\", \"jeden Morgen um 7 ans Wasser trinken\". Rechne die Uhrzeit vorher mit clock in Ortszeit aus, wenn der Nutzer relativ spricht (\"in zwei Stunden\", \"morgen\"); das Datum im Prompt ist UTC.\n"
        "Nimm es NICHT fuer: Dinge, die jetzt sofort zu tun sind - die machst du direkt; nicht fuer Auftraege, die Werkzeuge brauchen (dafuer gibt es die Zeitplaene in der Oberflaeche); nicht fuer Termine in einem Kalender (das ist kalender, und der ist hier nur lesbar).\n"
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
    # Ein Erinnerungstext ist ein Satz. Ein Dokument ist keiner - und ein
    # Modell, das eines hier ablegt, tut es aus Versehen oder auf Anweisung.
    MAX_TEXT = 500

    async def execute(self, text: str, wann: str) -> ToolResult:
        begonnen = time.monotonic()
        if not self.db_path:
            hinweis = "Erinnerungen sind nicht eingerichtet (kein Datenbankpfad)."
            return ToolResult(ok=False, error=hinweis, display=hinweis)
        text = " ".join(str(text or "").split())
        if not text:
            return ToolResult(ok=False, error="Kein Text.", display="Woran soll ich erinnern?")
        if len(text) > self.MAX_TEXT:
            hinweis = (f"Der Erinnerungstext ist zu lang ({len(text)} Zeichen, hoechstens "
                       f"{self.MAX_TEXT}). Fasse ihn in einem Satz zusammen.")
            return ToolResult(ok=False, error=hinweis, display=hinweis)
        try:
            regel = zeitplan.lies_regel(wann)
            # art='erinnerung': der Text IST die Nachricht. Kein Planer, keine
            # Werkzeuge, null Token - und keine Flaeche fuer Anweisungen im Text.
            plan = zeitplan.anlegen(
                self.db_path, name=text[:40], ziel=text, regel_text=regel.text,
                art="erinnerung",
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
