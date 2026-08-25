# PHASE 6 — Hermes (Orchestrator-Agent)

> Auftrag für Phase 6. Wird von `/phase 6` geladen.
> Regeln und Stack: `CLAUDE.md`. Datentypen: `docs/contracts.md`.
> Diese Phase erst starten, wenn Phase 5 in `STATUS.md` auf FERTIG steht.

**Auftrag:**
Hermes ist kein Magie-Agent. Hermes ist ein Agent, der andere Agents als Tools benutzt.

- `can_call_agents = ["research", ...]`, `max_depth` aus dem Budget wird erzwungen.
- Hermes fasst Teilergebnisse zusammen und **kennzeichnet, welcher Teil von welchem Agent kam**.
- Referenz-Task, der in der Abnahme durchlaufen muss:
  *"Finde mir drei Gravity-Bike-Helme unter 250 €, vergleiche sie und sag mir, welchen ich nehmen soll."*

**Definition of Done:**
1. Der Referenz-Task läuft vollständig durch und liefert eine Empfehlung mit Begründung.
2. Jeder Preis hat eine Quelle mit Abrufdatum. Preise ohne Quelle → Schritt gilt als fehlgeschlagen.
3. Der Task-Baum ist im UI sichtbar (Hermes → Research → Tool-Calls).
4. Gesamtkosten und Gesamttokens des Tasks werden am Ende angezeigt.
5. Ein Versuch, aus Tiefe 2 einen weiteren Agent zu rufen, wird abgelehnt und geloggt.
6. Der Task bleibt unter dem Default-Budget. Wenn nicht: Budget ist zu klein oder der Planner zu geschwätzig — beides melden, nicht das Budget stillschweigend hochsetzen.
