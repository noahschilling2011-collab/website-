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

---

# BEFUND SCHRITT 2 — der Pfad, einzeln geprüft

Alles gegen einen laufenden `uvicorn` auf `127.0.0.1:8012`, Anbieter `fake`,
plus einen echten Chromium über Playwright.

## 2a Schrittliste — ✓

```
status   : done
schritte : 1
   - done | Was ist 2+2 | agent= None
```

Im Browser:

```
Plan-Text    : Plan · done · 1/1 | ✓ | Was ist 2+2 | 392 Token
Schritt-Knoten im Plan: 1
JS-Fehler    : keine
```

## 2b `/api/events` — ✓

```
task-Ereignisse: 3
step-Ereignisse: 3
      1 event: hello
      3 event: step
      3 event: task
```

## 2c Werkzeug-Ansicht — funktionsfähig, im Auslieferungszustand dauerhaft leer

Nach zwei Aufträgen: `/api/tool-calls` → `[]`, `tool_calls` in der DB → `0`.
Der Fake schlägt nie einen Werkzeugaufruf vor, also läuft keiner.

Die Ansicht selbst ist nicht kaputt. Mit einem geskripteten Fake, der einen
Werkzeugaufruf vorschlägt:

```
status          : done
spent_tool_calls: 1
tool_calls DB   : 1  -> ('calculator', 1, 0)
/api/tool-calls : [{"name": "calculator", "ok": true, "display": "2+2 = 4", ...}]
```

Im Browser zeigt die Ansicht ohne Daten korrekt „Noch kein Werkzeug gelaufen."

## 2d Abbrechen — ✓ am Endpunkt, im Auslieferungszustand nicht erreichbar

Mit einem künstlich verlangsamten Fake:

```
vor dem Abbruch : running
cancel HTTP     : 200 {"status":"cancelling"}
Endzustand      : cancelled
abort_reason    : Vom Nutzer abgebrochen.
```

Mit dem normalen Fake dauert ein Auftrag `Fertig in 0.7 s` — kein Mensch
trifft den Knopf. Der Knopf ist da und funktioniert; prüfbar ist er nur mit
einem Anbieter, der lange genug braucht.

## Zusätzlich aufgefallen — nicht repariert

1. Das Ergebnis zitiert den Planner-Umschlag mit: `Zuletzt sagtest du: "Ziel: Was ist 2+2`.
   Der Fake echot, was er bekommt, und bekommt `Ziel: `-präfixierten Text.
   Kosmetisch, nur im Fake-Betrieb sichtbar.
2. Der Bestätigungsdialog ist mit dem Fake gar nicht erreichbar: er hängt an
   einem Werkzeug ab `EXTERNAL`, und der Fake ruft kein Werkzeug auf.

## BLOCKER

**Werkzeuge und Bestätigungsdialog lassen sich mit dem Fake nicht sinnvoll
prüfen.** Dafür braucht es einen echten Provider mit Key — `LLM_API_KEY`,
`LLM_MODEL`, und für die Websuche `SEARCH_API_KEY`. Jeder Auftrag geht dann
durch Planner, Schritt und Zusammenfassung: drei bis vier Modellaufrufe,
die Geld kosten. Ich umgehe das nicht mit einem schlaueren Fake — ein Fake,
der Werkzeuge auswählt, prüft nur sich selbst.
