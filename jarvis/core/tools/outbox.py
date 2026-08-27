"""Ein Werkzeug mit Aussenwirkung - als Testfall fuer Phase 5.

`send_email` verschickt **nichts**. Es schreibt in eine Datei. Das ist
Absicht: der Bestaetigungs-Flow, das Audit-Log und die Permission-Sperre
lassen sich damit vollstaendig pruefen, ohne dass je eine echte Mail rausgeht.

Ein echter Versand waere ein eigenes Werkzeug in einer spaeteren Phase, mit
einem eigenen Anbieter und einem eigenen Key.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

from core.contracts import Permission, Tool, ToolResult
from core.tools.registry import register


@register
class SendEmail(Tool):
    name = "send_email"
    description = (
        "Verschickt eine E-Mail. Der Nutzer muss jeden Versand einzeln "
        "bestaetigen und sieht vorher Empfaenger, Betreff und Text."
    )
    parameters = {
        "type": "object",
        "properties": {
            "to": {"type": "string", "description": "Empfaengeradresse."},
            "subject": {"type": "string", "description": "Betreff."},
            "body": {"type": "string", "description": "Der Text der Mail."},
        },
        "required": ["to", "subject", "body"],
        "additionalProperties": False,
    }
    permission = Permission.EXTERNAL
    requires_confirmation = True

    # Wird beim Start gesetzt. Solange leer, schreibt das Werkzeug nichts.
    outbox: Path | str = ""

    def vorschau(self, to: str, subject: str, body: str) -> str:
        """Genau das, was der Nutzer vor dem Senden zu sehen bekommt (DoD 2).

        **Vollstaendig, nie gekuerzt.** Bis FIX-07 stand hier eine Grenze von
        800 Zeichen. Das war ein Fehler, und zwar ein sicherheitsrelevanter:
        seit `datei_lesen` existiert, kann fremder Dateiinhalt in den Text
        geraten - und wer eine Anweisung in eine Datei schmuggelt, setzt sie
        ans Ende, nicht an den Anfang. Gemessen an einem Text von 1163
        Zeichen fehlte genau die letzte Zeile in der Vorschau. Dieser Dialog
        ist die einzige Stelle, an der ein Mensch das noch sieht; er darf
        nichts verschweigen.

        Lang wird der Text dadurch schon - aber `.frage pre` in `index.html`
        ist ein Scrollbereich (`max-height: 320px; overflow-y: auto`). Der
        Text ist also vollstaendig da und trotzdem nicht im Weg.
        """
        return (
            "E-Mail senden\n"
            f"An:      {to}\n"
            f"Betreff: {subject}\n"
            "\n"
            f"{body}"
        )

    async def execute(self, to: str, subject: str, body: str) -> ToolResult:
        begonnen = time.monotonic()
        if not self.outbox:
            return ToolResult(
                ok=False,
                error="Kein Postausgang eingerichtet.",
                display="send_email hat keinen Ablageort - nichts geschrieben.",
            )

        pfad = Path(self.outbox)
        pfad.parent.mkdir(parents=True, exist_ok=True)
        eintrag = {
            "to": to,
            "subject": subject,
            "body": body,
            "written_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        with pfad.open("a", encoding="utf-8") as datei:
            datei.write(json.dumps(eintrag, ensure_ascii=False) + "\n")

        return ToolResult(
            ok=True,
            data=eintrag,
            display=f"In den Postausgang geschrieben: {subject} an {to}",
            duration_ms=int((time.monotonic() - begonnen) * 1000),
        )
