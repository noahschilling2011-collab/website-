# REPARATURAUFTRAG 01

Ausgangspunkt ist das Audit vom 2026-08-25 gegen `f85564c`.

## Regeln für diese Session

1. **Ein Schritt nach dem anderen.** Nach jedem Schritt: ausführen, echte Ausgabe zeigen, committen, dann erst weiter.
2. **Keine neuen Features.** Nichts aus den Phasen 8–10 anfassen.
3. **Kein Budget, Timeout oder Retry-Limit erhöhen**, damit etwas grün wird. Wenn ein Limit stört: melden und stoppen.
4. **Nichts auskommentieren.** Löschen oder lassen.
5. Wenn ein Schritt etwas Unerwartetes aufdeckt: melden und stoppen, nicht nebenbei mitreparieren.

---

## SCHRITT 0 — Erst rot sehen

Schreib den Test, der fehlt. **Nichts anderes.** Er muss rot sein, bevor irgendetwas repariert wird.

`tests/test_auslieferungszustand.py`: ein Auftrag über `POST /api/tasks`, ohne
untergeschobenen Provider, muss `done` erreichen und mindestens einen Schritt haben.

Zusätzlich: in `scripts/smoke.py` einen Schritt ergänzen, der **einen echten Auftrag anlegt und auf `done` wartet**. Der Rauchtest muss ab jetzt scheitern.

**Abnahme:** Beide scheitern, mit der echten Fehlermeldung im Protokoll. Committen als `test: Auslieferungszustand (rot)`.

---

## SCHRITT 1 — FakeLLMProvider

Ursache: der Provider echot die letzte Nachricht, der Planner will JSON, nach 3 Versuchen `failed`.

**Bau ihn absichtlich dumm.** Kein Musterabgleich auf Zielinhalte, keine Werkzeugauswahl.

- Fragt der Planner nach einem Plan → **ein** Schritt, Beschreibung = das Ziel, kein Werkzeug.
- Alles andere → Echo wie bisher.
- Der Antwortpfad muss gültiges JSON gegen das Pydantic-Schema liefern, nicht gegen ein Beispiel.

README ehrlich korrigieren:

> Ohne API-Key läuft die Oberfläche und Aufträge laufen durch, aber **es wird kein Werkzeug ausgeführt** — dafür braucht es einen echten Provider.

**Abnahme:** Schritt-0-Test grün. `pytest -q` weiterhin 364+ grün, kein einziger vorher grüner Test jetzt rot. `scripts/smoke.py` grün und legt nachweislich einen Auftrag an.

---

## SCHRITT 2 — Den Pfad zu Ende laufen

Einzeln prüfen, mit echter Ausgabe:

- Füllt sich die Schrittliste, oder bleibt `steps` leer?
- Feuert `/api/events` ein `task`-Ereignis?
- Zeigt die Werkzeug-Ansicht etwas, sobald ein Werkzeug lief?
- Greift der Abbrechen-Knopf bei einem laufenden Auftrag?

Was scheitert, wird **notiert, nicht sofort repariert**.

---

## SCHRITT 3 — STATUS.md entwerten

- Spalte **BELEG** in der Phasentabelle: der Befehl, mit dem das DoD nachgewiesen wurde.
- Jedes ✓ ohne Beleg → zurück auf `OFFEN`.
- Danach DoD-Prüfung ab Phase 1, bis das erste ✗ kommt. Dort anhalten.

---

## SCHRITT 4 — Phase 7 ehrlich machen

- **A:** `EventSource` verkabeln, 700-ms-Polling löschen. `grep -c EventSource index.html` > 0.
- **B:** Phase 7 auf `OFFEN` mit Begründung.

Kein dritter Ausgang.

---

## SCHRITT 5 — Widerspruch in der Spec auflösen

Neue Regel in `docs/contracts.md`:

> Bestätigung ist Pflicht ab `EXTERNAL` (3) aufwärts, plus bei jeder **löschenden oder überschreibenden** lokalen Operation. Rein anhängende lokale Schreibvorgänge (`remember`) brauchen keine.

- `remember` bleibt `LOCAL`, `confirm=False`.
- Werkzeug, das Memory löscht/überschreibt → `requires_confirmation=True`. Sonst nichts bauen.
- Test: jedes Werkzeug mit Permission ≥ EXTERNAL hat `requires_confirmation=True`.

---

## SCHRITT 6 — Die stille Falle schließen

`core/tools/memory_tools.py` — `db_path: Path | str = ""`. `sqlite3.connect("")` wirft nicht,
sondern legt eine private Wegwerf-Datenbank an. Leeren Pfad abfangen und `ValueError` werfen,
dazu ein Test.

---

## SCHRITT 7 — Aufräumen

Löschen, nicht auskommentieren:

```
core/runner.py    class TaskAbgebrochen(RuntimeError)
core/planner.py   def plan_als_text(schritte)
core/planner.py   def als_json(schritte)
core/db.py        def clear_messages(db_path)
core/db.py        def list_tool_calls(db_path, message_id)
```

`/api/chat` ebenfalls löschen. `/api/audit` und `/api/task-log` bleiben, kommen aber
in der README unter „nur API, kein UI".

**Abnahme:** `pytest -q` grün, App startet, `/api/chat` gibt 404.

---

## SCHRITT 8 — Rückfallschutz

Ein Test, der jede registrierte Route entweder in `index.html` findet oder in einer
ausdrücklichen Liste `NUR_API = {...}`.
