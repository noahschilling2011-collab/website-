# Phase 4 — Werkzeuge

## Ziel
JARVIS kann etwas tun, nicht nur reden — unter Freigabe.

## Was gebaut wird
- `Tool`, `ToolResult`, `Permission` nach `docs/contracts.md`.
- Registry, Schema-Validierung vor jedem Aufruf, Tool-Schleife gegen die
  Messages-API (`stop_reason: "tool_use"` → `tool_result` zurück).
- Freigabe-Dialog in der Oberfläche: Tool, Argumente, Ja/Nein. Pro Aufruf.
- Erste Tools: Uhrzeit, Rechnen, Notiz anlegen/lesen, Dateien in **einem**
  Sandbox-Ordner, HTTP-GET gegen eine Allowlist.

## Definition of Done
1. Ein Werkzeug mit `ASK` läuft nachweislich nicht ohne Bestätigung.
2. Ein Werkzeug mit `DENY` wird dem Modell nicht angeboten.
3. Ungültige Argumente erzeugen `ToolResult(ok=False)` — keine Exception.
4. Das Dateiwerkzeug kommt aus dem Sandbox-Ordner nicht heraus; `../` und
   Symlinks sind getestet.
5. Nirgends `eval`, `exec` oder `shell=True` mit Modell-Ausgabe.
