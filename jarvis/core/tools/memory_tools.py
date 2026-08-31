"""Werkzeuge fuers Gedaechtnis (Phase 3).

Ein Fakt wird **nur** gespeichert, wenn das Modell ihn ausdruecklich als
merkenswert markiert - deshalb ein Werkzeug und kein automatisches Absaugen
des Chats. Was gemerkt wird, ist damit im Werkzeug-Log sichtbar und im UI
loeschbar.
"""

from __future__ import annotations

import logging
import time
from pathlib import Path

from core import memory
from core.contracts import Permission, Tool, ToolResult
from core.tools.registry import register

log = logging.getLogger("jarvis")


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
        "Legt eine dauerhafte Tatsache ueber den Nutzer im Langzeitgedaechtnis ab.\n"
        "Nimm es fuer: was auch in einem Monat noch gilt - Vorlieben, Ausruestung, Namen, Gewohnheiten - oder wenn der Nutzer ausdruecklich darum bittet. Dabei entsteht der Eintrag, den recall spaeter wiederfindet.\n"
        "Nimm es NICHT fuer: Nachsehen, was schon gespeichert ist - das macht recall; auch nicht fuer Dinge, die nur fuer dieses Gespraech gelten, oder die du selbst geschlossen hast.\n"
        "Beispiel: remember(text=\"Mein Rad ist ein Santa Cruz V10\", category=\"ausruestung\")"
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
            # KEIN `exc` in error oder display. Ein OSError traegt den
            # vollstaendigen Pfad in seinem Text ("[Errno 2] No such file or
            # directory: '/home/noah/vault/2026/notiz.md'"), und `display`
            # ist die sichtbare Chat-Ausgabe - der Pfad stuende damit im
            # Fenster und im Prompt.
            #
            # FIX-07 verbietet Pfade ausserhalb der Wurzeln in JEDER
            # UI-Ausgabe, ausdruecklich auch in Fehlermeldungen. Fuer die
            # Datei-Werkzeuge war das umgesetzt, fuer den Vault nicht - hier
            # war die Regel nur an einer Stelle gedacht statt am Grundsatz.
            # Gefunden am 31.08.2026.
            log.warning("Vault nicht beschreibbar: %s", exc)
            hinweis = (f"Vault nicht beschreibbar ({type(exc).__name__}). "
                       "Pruefe VAULT_PFAD in der .env und die Schreibrechte. "
                       "Der Pfad steht im Serverlog, nicht hier.")
            return ToolResult(ok=False, error=hinweis, display=hinweis,
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
        "Durchsucht Noahs Langzeitgedaechtnis und den bisherigen Gespraechsverlauf nach Stichworten.\n"
        "Nimm es fuer: alles, was der Nutzer dir frueher selbst gesagt haben koennte - Vorlieben, Ausruestung, Namen, Gewohnheiten; hier findest du wieder, was remember abgelegt hat. Findest du nichts, sag das - rate nicht.\n"
        "Nimm es NICHT fuer: Wissen ueber die Welt oder Aktuelles - das steht nicht im Gedaechtnis, dafuer web_search; und nicht, um etwas Neues abzulegen - das macht remember.\n"
        "Beispiel: recall(query=\"Fahrrad\", include_messages=true)"
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
