"""Werkzeuge fuers Gedaechtnis (Phase 3).

Ein Fakt wird **nur** gespeichert, wenn das Modell ihn ausdruecklich als
merkenswert markiert - deshalb ein Werkzeug und kein automatisches Absaugen
des Chats. Was gemerkt wird, ist damit im Werkzeug-Log sichtbar und im UI
loeschbar.
"""

from __future__ import annotations

import time
from pathlib import Path

from core import memory
from core.contracts import Permission, Tool, ToolResult
from core.tools.registry import register


class _MitDatenbank(Tool):
    """Der Pfad wird beim Start gesetzt, nicht importiert.

    So bleibt das Werkzeug ohne Umgebung baubar und in Tests umlenkbar.

    Der Vorgabewert bleibt leer, weil die Registry die Werkzeuge ohne
    Argumente baut. Er ist aber keine benutzbare Voreinstellung: wer das
    Werkzeug laufen laesst, ohne den Pfad zu setzen, bekommt einen Fehler
    und keine stille Wegwerf-Datenbank.
    """

    db_path: Path | str = ""

    # Leer = kein Vault. Dann bleibt alles beim Alten und es wird nichts
    # angelegt. Gesetzt wird das beim App-Start, wie db_path.
    vault_pfad: str = ""

    # docs/MIGRATION-VAULT.md Schritt 5: nie den ganzen Vault in einen Prompt
    # kippen. Was zuerst greift, gewinnt.
    MAX_NOTIZEN = 5
    MAX_ZEICHEN = 8000          # ~2000 Token, grob und bewusst konservativ

    def vault_an(self) -> bool:
        return bool(str(self.vault_pfad).strip())

    def pfad(self) -> Path | str:
        """Der Datenbankpfad - oder ein Fehler, nie ein stiller Ersatz."""
        if not str(self.db_path).strip():
            raise ValueError(
                f"{self.name}: db_path ist leer. Das Werkzeug wurde nie mit der "
                f"Datenbank verdrahtet (das passiert beim App-Start in "
                f"api/app.py). Ohne diesen Fehler wuerde sqlite3 eine anonyme "
                f"Wegwerf-Datenbank anlegen und jeden gemerkten Satz verlieren."
            )
        return self.db_path


@register
class Remember(_MitDatenbank):
    name = "remember"
    description = (
        "Merkt sich eine dauerhafte Tatsache ueber den Nutzer - Vorlieben, "
        "Ausruestung, Namen, Gewohnheiten. Benutze das NUR, wenn der Nutzer "
        "etwas sagt, das auch in einem Monat noch gilt, oder wenn er dich "
        "ausdruecklich bittet, es dir zu merken. Merk dir nichts, was nur fuer "
        "dieses Gespraech gilt, und nichts, was du selbst geschlossen hast."
    )
    parameters = {
        "type": "object",
        "properties": {
            "text": {
                "type": "string",
                "description": (
                    "Die Tatsache als vollstaendiger Satz aus Sicht des "
                    "Nutzers, z. B. 'Mein Rad ist ein Santa Cruz V10'."
                ),
            },
            "category": {
                "type": "string",
                "description": (
                    "Kurzes Schlagwort zur Einordnung, z. B. 'ausruestung', "
                    "'hobby', 'arbeit', 'kontakt'."
                ),
            },
        },
        "required": ["text"],
        "additionalProperties": False,
    }
    permission = Permission.LOCAL

    def _merken(self, text: str, category: str, begonnen: float) -> ToolResult:
        """FIX-04 Schritt 2: EIN Schreibweg, fuer alle Aufrufer derselbe.

        Vorher stand hier ein zweiter, eigener Weg in den Vault - und die
        API-Endpunkte hatten einen dritten in die Tabelle `facts`. Jetzt geht
        alles durch `core.gedaechtnis`: mit Vault zuerst die Datei, dann der
        Index; ohne Vault wie bisher.
        """
        from core import gedaechtnis
        from core.vault import VaultKonflikt

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        try:
            neu, widerspruch = gedaechtnis.anlegen(
                self.pfad(), self.vault_pfad, text, category=category
            )
        except ValueError as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())
        except VaultKonflikt as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())
        except OSError as exc:
            return ToolResult(ok=False, error=str(exc),
                              display=f"Vault nicht beschreibbar: {exc}",
                              duration_ms=dauer())

        # Ohne Vault bleibt die Anzeige wortgleich zu vorher: "#7" ist eine
        # Zeilennummer, "f_395043" ist ein Dateischluessel. Beides als "#7"
        # zu schreiben waere gelogen.
        def zeige(kennung) -> str:
            return f"#{kennung}" if isinstance(kennung, int) else str(kennung)

        wo = f" in {neu.pfad}" if neu.pfad else ""
        zeilen = [f"Gemerkt ({zeige(neu.id)}, {neu.category}){wo}: {neu.text}"]
        if widerspruch is not None:
            zeilen.append(
                f"ACHTUNG: das widerspricht moeglicherweise "
                f"{zeige(widerspruch.id)}: {widerspruch.text}"
            )
            zeilen.append(
                "Beide Staende bleiben stehen. Sag dem Nutzer, dass es einen "
                "Widerspruch gibt, und frag welcher gilt."
            )
        return ToolResult(
            ok=True,
            data={"id": neu.id, "conflicts_with": widerspruch.id if widerspruch else None,
                  "datei": neu.pfad},
            display="\n".join(zeilen),
            sources=[neu.pfad] if neu.pfad else [],
            duration_ms=dauer(),
        )

    async def execute(self, text: str, category: str = "allgemein") -> ToolResult:
        return self._merken(text, category.strip() or "allgemein", time.monotonic())


@register
class Recall(_MitDatenbank):
    name = "recall"
    description = (
        "Durchsucht das Langzeitgedaechtnis und den bisherigen Verlauf nach "
        "Stichworten. Benutze das, wenn der Nutzer nach etwas fragt, das er "
        "dir frueher gesagt haben koennte. Wenn nichts gefunden wird, sag das "
        "- rate nicht."
    )
    parameters = {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "Stichworte zur Suche."},
            "include_messages": {
                "type": "boolean",
                "description": "Auch alte Nachrichten durchsuchen, nicht nur Fakten.",
            },
        },
        "required": ["query"],
        "additionalProperties": False,
    }
    permission = Permission.READ

    def _aus_dem_vault(self, query: str, begonnen: float) -> ToolResult:
        """Sucht ueber den Index, gibt hoechstens `MAX_NOTIZEN` Notizen zurueck.

        Jede Zeile nennt die Quelldatei. Auch bei lokaler Quelle - eine
        Antwort ohne Herkunft ist eine Behauptung.
        """
        from core.gedaechtnis import frisch_halten
        from core.vault_index import suche

        # FIX-04 Schritt 3: derselbe Leseweg wie das Panel - erst die
        # Zeitstempel gegen den Index, dann suchen. Ohne das faende `recall`
        # nicht, was zwischendurch in Obsidian getippt wurde.
        frisch_halten(self.pfad(), self.vault_pfad)
        treffer = suche(self.pfad(), query, limit=self.MAX_NOTIZEN)

        zeilen: list[str] = []
        zeichen = 0
        genutzt = []
        for t in treffer:
            zeile = f"[{t.herkunft}] {t.text}"
            if zeichen + len(zeile) > self.MAX_ZEICHEN:
                break
            zeilen.append(zeile)
            genutzt.append(t)
            zeichen += len(zeile)

        dauer = int((time.monotonic() - begonnen) * 1000)
        if not zeilen:
            return ToolResult(
                ok=True,
                data={"query": query, "hits": 0},
                display=f"Nichts zu {query!r} im Vault.",
                duration_ms=dauer,
            )
        return ToolResult(
            ok=True,
            data={"query": query, "hits": len(zeilen),
                  "notizen": [t.id for t in genutzt]},
            display="\n".join(zeilen),
            sources=[t.pfad for t in genutzt],
            duration_ms=dauer,
        )

    async def execute(
        self, query: str, include_messages: bool = False
    ) -> ToolResult:
        begonnen = time.monotonic()
        if self.vault_an():
            return self._aus_dem_vault(query, begonnen)
        fakten = memory.search_facts(self.pfad(), query)
        zeilen = [
            f"Fakt #{f.id} ({f.category})"
            + (f" [Widerspruch zu #{f.conflicts_with}]" if f.conflicts_with else "")
            + f": {f.text}"
            for f in fakten
        ]

        if include_messages:
            for mid, rolle, inhalt, wann in memory.search_messages(self.pfad(), query):
                gekuerzt = inhalt if len(inhalt) <= 200 else inhalt[:199] + "…"
                zeilen.append(f"Nachricht #{mid} ({rolle}, {wann}): {gekuerzt}")

        dauer = int((time.monotonic() - begonnen) * 1000)
        if not zeilen:
            return ToolResult(
                ok=True,
                data={"query": query, "hits": 0},
                display=f"Nichts zu {query!r} im Gedaechtnis.",
                duration_ms=dauer,
            )
        return ToolResult(
            ok=True,
            data={"query": query, "hits": len(zeilen),
                  "facts": [f.id for f in fakten]},
            display="\n".join(zeilen),
            duration_ms=dauer,
        )
