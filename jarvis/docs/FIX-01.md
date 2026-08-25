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

## SCHRITT 1 — Echter Provider statt schlauerem Fake

> **Überarbeitet am 25.08.2026.** Ursprünglich stand hier: den `FakeLLMProvider` so
> umbauen, dass er Plan-JSON liefert. Das ist überholt. Mit einem Max-Abo gibt es einen
> echten Provider ohne Zusatzkosten — und ein Fake, der ein echtes Modell nachahmt,
> verdeckt auf Dauer Fehler, statt sie zu zeigen.

Ursache: der voreingestellte Provider echot die letzte Nachricht, der Planner will JSON,
nach 3 Versuchen `failed`.

**Fix:** `ClaudeCodeProvider` aus `docs/provider-claude-code.md` einbauen und als
Voreinstellung setzen. Nutzt die angemeldete Claude Code CLI, kein API-Schlüssel,
keine Zusatzkosten.

Entscheidend ist `--json-schema`: das Plan-JSON wird von der CLI erzwungen, nicht vom
Prompt erhofft. Damit ist die Ursache weg statt umschifft.

Die drei geprüften Fallen aus dem Provider-Dokument sind Pflicht, nicht optional:
`cwd` auf ein leeres Scratch-Verzeichnis (sonst liest Claude Code JARVIS' eigene
CLAUDE.md), `is_error` prüfen statt Exit-Code, `stdin=DEVNULL` gegen drei Sekunden
Wartezeit pro Aufruf.

**Der `FakeLLMProvider` bleibt — aber nur für Tests.** Er darf weiter dumm sein und soll
es auch. Kein Test verbraucht Kontingent.

**README korrigieren:**

> Voraussetzung ist eine installierte und **angemeldete** Claude Code CLI
> (`claude` im Pfad, `claude -p "test" < /dev/null` liefert eine Antwort).
> Ohne Anmeldung startet JARVIS, aber kein Auftrag läuft durch.

**Abnahme:** Schritt-0-Test grün, **ohne** untergeschobenen Provider.
`pytest -q` weiterhin 364+ grün und weiterhin **null** CLI-Aufrufe in der Testsuite,
im Log nachgewiesen. `scripts/smoke.py` grün und legt nachweislich einen Auftrag an.
Zusätzlich: zehn Planner-Läufe liefern zehnmal gültiges JSON. Wenn nicht, melden —
nicht die Retry-Grenze hochsetzen.

> **BLOCKIERT am 25.08.2026.** `docs/provider-claude-code.md` existiert im Repo nicht
> und wurde nicht mitgeliefert. Ohne dieses Dokument sind CLI-Flags, Ausgabeform und
> Fehlerbehandlung geraten — genau die erfundene API, die CLAUDE.md Regel 1 verbietet.
> Zweitens hebt dieser Schritt `CLAUDE.md:49` auf („Du selbst (Claude Code) bist
> **nicht** JARVIS' Modell-Backend … Bau keine Brücke von JARVIS zurück zu deiner
> eigenen Session"). Beides muss der Nutzer entscheiden, bevor gebaut wird.
>
> Als Zwischenstand liegt die alte Fassung von Schritt 1 im Baum: der
> `FakeLLMProvider` beantwortet die Planungsanfrage mit einem Ein-Schritt-Plan
> (Commit `2234a22`). Damit läuft ein Auftrag durch, ohne dass ein Werkzeug läuft.
> Wird der `ClaudeCodeProvider` gebaut, ersetzt er diesen Zweig als Voreinstellung;
> der Fake bleibt für Tests.

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

## SCHRITT 8 — Budget von Euro auf Aufrufe umstellen

`BUDGET_MAX_COST_EUR` ist mit diesem Provider bedeutungslos. Ersetzen durch:

```
BUDGET_MAX_CLI_AUFRUFE_PRO_TASK=12
BUDGET_MAX_CLI_AUFRUFE_PRO_TAG=150
```

Den Tageswert aus der in Schritt 2 gemessenen Zahl ableiten, nicht raten. Zähler
sichtbar im Dashboard. Beim Anschlagen: klare Meldung, dass das Kontingent begrenzt ist
und mit der Claude-App geteilt wird — nicht stillschweigend weiterlaufen.

Der Kill-Switch bleibt wichtiger als vorher, nicht unwichtiger: eine durchgedrehte
Retry-Schleife über Nacht kostet jetzt kein Geld, sondern deinen Wochenzugang.

> **Hängt an Schritt 1.** Ohne `ClaudeCodeProvider` gibt es keine CLI-Aufrufe zu zählen.

---

## SCHRITT 9 — Rückfallschutz (optional, aber billig)

Ein Test, der jede registrierte Route entweder in `index.html` findet oder in einer
ausdrücklichen Liste `NUR_API = {...}`. Neue Endpunkte, die niemand ruft, fallen dann
sofort auf statt erst beim nächsten Audit.

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

---

# BEFUND SCHRITT 7 — `/api/chat` ist kein Rest aus Phase 1

**Angehalten, wie Regel 5 es verlangt.** Die fünf toten Definitionen sind gelöscht.
Die Löschung von `/api/chat` habe ich gebaut, geprüft und **wieder zurückgenommen**,
weil die Prämisse des Auftrags nicht stimmt.

## Was beim Löschen herauskam

Der Auftrag sagt: *„Dass alles über `/api/tasks` läuft, ist laut Spec richtig … Der
Endpunkt ist ein Rest aus Phase 1."* Beim Löschen brachen 12 Tests. Zehn davon
liessen sich sinnerhaltend umschreiben. Zwei nicht — und die beiden sind der Grund
für diesen Befund:

```
$ # zweiter Auftrag, nachdem der erste "Mein Name ist Noah" hiess
Modellaufrufe im zweiten Zug: 3
  Aufruf 0: kennt 'Noah'?  False
  Aufruf 1: kennt 'Noah'?  False
  Aufruf 2: kennt 'Noah'?  False

system_prompt aus Settings taucht auf in: 0 von 6 Aufrufen
Verlauf in der DB: 4 Nachrichten
```

**1. Der Gesprächsverlauf erreicht das Modell auf dem Auftragspfad überhaupt nicht.**
Vier Nachrichten stehen in der Datenbank, und keiner der drei Modellaufrufe des
zweiten Zuges kennt die erste. `/api/chat` war der einzige Pfad, der
`db.list_messages(..., history_limit)` an das Modell weitergibt. Die Oberfläche hat
`/api/chat` nie benutzt — JARVIS hat im Browser also **noch nie** gewusst, was man
ihm einen Zug vorher gesagt hat. Was über Züge hinweg trägt, ist allein das
Gedächtnis aus Phase 3 (`recall`), und das greift nur, wenn das Modell das Werkzeug
von sich aus ruft.

**2. `settings.system_prompt` erreicht keinen einzigen Modellaufruf.** Die Agenten
tragen ihre eigenen Prompts (`STANDARD_PROMPT` und Geschwister über `mit_stil`). Der
konfigurierbare Systemprompt aus den Settings ist auf dem Auftragspfad wirkungslos —
`/api/chat` war sein einziger Leser.

## Warum ich nicht weitergemacht habe

`/api/chat` zu löschen heisst damit **nicht**, einen doppelten Weg aufzuräumen,
sondern die letzte Stelle zu entfernen, die Verlauf und Systemprompt überhaupt
benutzt. Das Ergebnis wäre ein System, in dem beides gebaut, gespeichert und tot ist.

Den Verlauf in den Auftragspfad einzubauen wäre ein neues Feature — Regel 2 verbietet
das, Regel 5 verlangt melden statt nebenbei reparieren.

## Was zu entscheiden ist

| Weg | Folge |
|---|---|
| **A** — erst Verlauf und Systemprompt in den Auftragspfad, dann `/api/chat` löschen | JARVIS bekommt Gesprächsgedächtnis. Neues Verhalten, gehört in einen eigenen Auftrag. |
| **B** — `/api/chat` behalten, in `NUR_API` eingetragen lassen | Nichts geht verloren, die Doppelung bleibt sichtbar dokumentiert. |
| **C** — `/api/chat` trotzdem löschen | Verlauf und `settings.system_prompt` sind danach unbenutzt. Ehrlich, aber ärmer. |

Bis zur Entscheidung steht `/api/chat` in `NUR_API` in
`tests/test_routen_haben_einen_nutzer.py`, mit genau dieser Begründung.

## Was in Schritt 7 erledigt ist

- Die fünf toten Definitionen sind **gelöscht**, nicht auskommentiert:
  `TaskAbgebrochen`, `plan_als_text`, `als_json`, `clear_messages`, `list_tool_calls`.
  30 Zeilen, `git diff --stat` bestätigt: nur diese.
- `/api/audit` und `/api/task-log` stehen in der README unter „nur API, kein UI".
- Nebenbefund, **nicht angefasst**: `core/runner.py` importiert `ToolResult` und
  `field`, beide schon vor dieser Session ungenutzt. Nicht Teil der genannten fünf.
