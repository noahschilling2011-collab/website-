# STATUS

> Einzige Wahrheit über den Projektstand. Claude Code liest diese Datei zuerst
> und aktualisiert sie am Ende jeder Phase. Von Hand korrigieren ist erlaubt.

AKTUELL: Phase 4 — Planner + Research Agent
LETZTE ÄNDERUNG: 2026-08-25

> **Abweichung von der Arbeitsweise, auf Ansage:** es werden alle Phasen
> gebaut, nicht eine nach der anderen. Das widerspricht CLAUDE.md
> („Kein Vorgriff auf spätere Phasen") und der Verbotsliste in
> `docs/decisions.md`. **Keine Phase ist abgenommen** — jede DoD hängt an
> mindestens einer echten Modellantwort, und dafür fehlt der Key.

## Phasen

| # | Phase                     | Status   | DoD erfüllt am |
|---|---------------------------|----------|----------------|
| 1 | Walking Skeleton          | IN ARBEIT| –              |
| 2 | Tool-System               | IN ARBEIT| –              |
| 3 | Memory                    | IN ARBEIT| –              |
| 4 | Planner + Research Agent  | IN ARBEIT| –              |
| 5 | Permissions & Bestätigung | GESPERRT | –              |
| 6 | Hermes                    | GESPERRT | –              |
| 7 | Observability-Dashboard   | GESPERRT | –              |
| 8 | Satellite Agent           | GESPERRT | –              |
| 9 | Voice                     | GESPERRT | –              |
|10 | Härten & Verpacken        | GESPERRT | –              |

Status-Werte: GESPERRT / OFFEN / IN ARBEIT / FERTIG
Legende der DoD-Tabellen: ✓ erfüllt und ausgeführt · ◐ Mechanik steht und ist
getestet, die Abnahme braucht den Key · ✗ blockiert.

## Phase 1 — Walking Skeleton

| # | Kriterium | Stand |
|---|---|---|
| 1 | `python -m uvicorn main:app --reload` startet ohne Fehler | ✓ |
| 2 | `http://127.0.0.1:8000` zeigt das Chat-Interface | ✓ echter Browser |
| 3 | Antwort vom **echten** Modell | ✗ kein API-Key |
| 4 | Prozess neu starten → Verlauf ist noch da | ✓ Browser-Reload + Neustart |
| 5 | `llm_calls` mit **echten** Tokenzahlen | ◐ Zeile wird geschrieben, Zahlen vom Fake |
| 6 | Request ohne `X-Jarvis-Token` gibt 401 | ✓ live gegen den Server |
| 7 | `grep -ri "sk-" index.html` findet nichts | ✓ mit Gegenprobe |

## Phase 2 — Tool-System

| # | Kriterium | Stand |
|---|---|---|
| 1 | 17 % von 4380 → 744,6 mit `calculator`-Aufruf im Log | ◐ Rechner liefert 744.6, Aufruf wird protokolliert und angezeigt |
| 2 | Korrekte lokale Zeit über `clock` | ◐ `clock` stimmt; die Werkzeugwahl macht das Modell |
| 3 | Websuche mit Quellen-URLs in `ToolResult.sources` | ✗ kein `SEARCH_API_KEY`; Anfrage und Auswertung gegen MockTransport geprüft |
| 4 | Tool mit 40 s Laufzeit wird nach seinem Timeout abgebrochen | ✓ getestet |
| 5 | `pytest` grün, mindestens 6 Tests | ✓ 155 Tests, 39 davon zum Werkzeugsystem |
| 6 | Im UI aufklappbar: welche Tools mit welchen Argumenten liefen | ✓ headless gerendert |

Gebaut: `core/contracts.py` (Verträge ausgeführt statt nur beschrieben),
`core/tools/{registry,dispatch,validate,loop,builtin,search}.py`, Tabelle
`tool_calls`.

`calculator` kommt ohne `eval` aus: geprüft wird der AST, nicht der Text.
Abgelehnt werden `__import__(...)`, `open(...)`, Subscripts, Lambdas,
unbekannte Namen und `9**9**9` — je ein Test.

`web_search` spricht die Brave Search API. Endpunkt, Header
(`X-Subscription-Token`) und Antwortpfade
(`web.results[].{title,url,description}`) stammen aus der offiziellen Doku.

## Phase 3 — Memory

| # | Kriterium | Stand |
|---|---|---|
| 1 | Merk-dir-Satz erzeugt einen `facts`-Eintrag | ✓ über den echten Endpunkt, Modellzug geskriptet |
| 2 | Nach Neustart korrekte Antwort, Memory-Lookup im Log sichtbar | ◐ der Fakt landet nach dem Neustart nachweislich im Systemprompt; die Antwort selbst gibt das Modell |
| 3 | Nach dem Löschen halluziniert das Modell die Antwort nicht | ✓ nach dem Löschen steht nichts mehr im Kontext — geprüft |
| 4 | `task_log` hat nach drei Tasks drei Zeilen | ✓ |
| 5 | Widersprechender Fakt wird als Konflikt angezeigt, nicht stumm überschrieben | ✓ beide Stände bleiben, Verweis + Anzeige im UI |

Gebaut: `core/memory.py`, Tabellen `facts` und `task_log`, FTS5-Indizes über
`facts` und `messages` (per Trigger aktuell gehalten), Werkzeuge `remember`
(LOCAL) und `recall` (READ), Endpunkte `GET/POST/PATCH/DELETE /api/memory` und
`GET /api/tasks`, Gedächtnis-Ansicht im UI mit Bearbeiten, Löschen und
Konfliktauflösung.

**Grenze der Konflikterkennung, ehrlich benannt:** eine Stichwortsuche kann
keinen inhaltlichen Widerspruch erkennen. `finde_konflikt` meldet
*Verdachtsfälle* — gleiche Kategorie, mindestens ein gemeinsames Inhaltswort —
und überschreibt nie selbst. Aufgelöst wird von Hand. Lieber einmal zu viel
gefragt als still das Falsche behalten.

**Keine Embeddings.** FTS5 mit `unicode61 remove_diacritics 2`. Ein Vektorindex
kommt, wenn eine Messung zeigt, dass das nicht reicht — nicht auf Verdacht.

## Phase 4 — Planner + Research Agent

| # | Kriterium | Stand |
|---|---|---|
| 1 | Grundsteuer-Frage erzeugt einen Plan, Schritt für Schritt sichtbar | ✓ Plan über `GET /api/tasks/{id}`, im UI mit Live-Status; echte Modellzüge geskriptet |
| 2 | Jede Faktenbehauptung hat eine anklickbare Quelle | ◐ Quellen werden gesammelt und unter die Antwort gehängt; dass das Modell sie *im Text* zitiert, ist eine Bitte im Prompt |
| 3 | Falsche URL → Retry sichtbar, dann sauberes Scheitern, kein Endlos-Loop | ✓ genau `max_attempts` Versuche, dann `FAILED` mit Begründung |
| 4 | „Wie spät ist es?" ergibt einen Plan mit **einem** Schritt | ✓ |
| 5 | `max_steps=2` → `aborted_budget` mit Teilergebnis | ✓ |

Gebaut: `core/planner.py`, `core/agents.py`, `core/verify.py`, `core/runner.py`,
Tabellen `tasks` und `steps`, Werkzeug `fetch_url`, Endpunkte
`POST /api/tasks`, `GET /api/tasks`, `GET /api/tasks/{id}`,
`POST /api/tasks/{id}/cancel`.

**Verifikation ist Code, kein Modellaufruf.** Ein Test liest den Quelltext von
`core/verify.py` und schlägt an, wenn dort je ein Provider auftaucht — sonst
wäre es wieder dasselbe Modell, das sich selbst benotet.

**Kostenfolge, die man kennen muss:** ein Chat-Zug geht jetzt durch Planner,
Schritt und Zusammenfassung — drei bis vier Modellaufrufe statt einem. Bei
`claude-opus-5` ist das echtes Geld. Der Planner ist darauf getrimmt, einfache
Ziele in genau einem Schritt zu erledigen, aber die zwei Zusatzaufrufe bleiben.

## Offene Blocker

- [ ] LLM-API-Key besorgen, als `LLM_API_KEY` in `.env` eintragen
- [ ] `LLM_PROVIDER=anthropic` und `LLM_MODEL` (Modell-ID aus der Anbieter-Doku)
- [ ] `LLM_PRICE_IN_PER_MTOK` / `LLM_PRICE_OUT_PER_MTOK` in EUR
- [ ] `JARVIS_TOKEN` würfeln und eintragen
- [ ] `SEARCH_API_KEY` von api-dashboard.search.brave.com (für Phase 2 DoD 3)
- [ ] Danach `/dod` je Phase laufen lassen

## Bekannte Abweichungen vom Plan

| Abweichung | Begründung |
|---|---|
| Alle Phasen statt einer | Ausdrückliche Ansage des Nutzers. Widerspricht CLAUDE.md und `decisions.md`; hier festgehalten, nicht stillschweigend gemacht. |
| `GET /api/messages` und `GET /api/health` sind im Auftrag nicht genannt | Ohne sie kann die Oberfläche DoD 4 aus Phase 1 nicht zeigen. |
| `pytest` schon in Phase 1, obwohl 0.3 sie ab Phase 2 verlangt | CLAUDE.md schreibt `FakeLLMProvider` vor und dass Tests ausschließlich dagegen laufen. |
| `scripts/smoke.py` zusätzlich | CLAUDE.md nennt `python -m scripts.smoke` unter Befehle. |
| App startet degradiert statt abzustürzen, wenn Key oder Modell fehlen | Ein Startabbruch mit Stacktrace bringt den Nutzer nie an die Stelle, die erklärt, was fehlt. |
| `JARVIS_TOKEN` wird beim Ausliefern von `/` in die Seite eingesetzt | Sonst kann die Oberfläche die eigene API nicht aufrufen. Der LLM-Key kommt dort nie hin. |
| Leerer `JARVIS_TOKEN` wird gewürfelt statt akzeptiert | Ein leerer Vergleichswert ließe jeden Request ohne Header durch. |
| `docs/contracts.md` aus dem Master-Prompt wiederhergestellt | Die Datei im Setup-Zip war nach 67 Bytes abgeschnitten. |
| `prompt_hash` in `llm_calls`, obwohl PHASE-01 die Spalten abschließend nennt | 0.6 verlangt ihn. Auf Rückfrage bestätigt. |
| `ChatResponse` trägt zusätzlich `tool_calls` | Phase 2 DoD 6 verlangt die Anzeige je Antwort; ohne das Feld müsste die Oberfläche nach jedem Zug den ganzen Verlauf neu holen. |
| `facts` hat eine Spalte `conflicts_with`, die im Auftrag nicht steht | Ohne sie wäre der Konflikt aus DoD 5 nach dem Neuladen verschwunden. |
| Chat-Agent auf `max_permission = LOCAL` angehoben (war READ) | `remember` schreibt lokal. EXTERNAL und SENSITIVE bleiben zu. |
| `Step.note`, `Task.result`, `Task.abort_reason` ergänzt | Rein additiv, mit Default, nichts umbenannt. Ohne `note` steht im UI `FAILED` ohne Grund; ohne `abort_reason` sagt ein Task nur „aborted_budget" und nicht, welche Grenze riss (0.5 verlangt die Benennung). Gemeldet statt danebengebaut. |
| Der Plan wird **nicht** auf `budget.max_steps` gekürzt | Sonst könnte `max_steps` nie greifen und der Nutzer sähe nie, dass sein Ziel größer war als das Budget. Der Plan darf zu groß sein; das Budget stoppt ihn während der Ausführung, mit Teilergebnis. |
| `max_steps` zählt gelaufene, nicht geplante Schritte | Sonst reißt die Grenze, bevor ein Schritt lief — und es gäbe nie ein Teilergebnis. |
| `GET /api/tasks` aus Phase 3 heißt jetzt `GET /api/task-log` | Phase 4 belegt `/api/tasks` mit der Task-Struktur. Der episodische Log ist etwas anderes. |

## Entscheidungslog

| Datum | Entscheidung | Grund |
|-------|--------------|-------|
| 2026-08-25 | Kein `anthropic`-SDK, httpx direkt gegen die Messages-API | 0.3 legt httpx fest. Ein SDK wäre eine Stack-Änderung. |
| 2026-08-25 | `temperature`, `top_p`, `top_k`, `thinking.budget_tokens` werden nicht gesendet | Auf den aktuellen Opus-Modellen ist jedes davon ein 400. |
| 2026-08-25 | Kosten sind `0.0`, solange keine Preise in `.env` stehen | Eine geschätzte Kostenzahl wäre schlimmer als gar keine. |
| 2026-08-25 | Kein Konversations-Browser, ein linearer Verlauf | Das Schema aus PHASE-01 kennt genau eine Tabelle `messages`. |
| 2026-08-25 | Fehlgeschlagene Modellaufrufe kommen auch in `llm_calls` | Sonst fällt eine Retry-Schleife, die Geld verbrennt, erst auf der Rechnung auf. |
| 2026-08-25 | Brave Search als Suchanbieter | Doku nachgeschlagen, Endpunkt und Header verifiziert. Ein Wechsel ist ein neuer `Tool`, kein Umbau. |
| 2026-08-25 | Chat-Agent läuft mit `max_permission = READ` | Er darf lesen und rechnen, aber nichts schreiben und nichts nach außen schicken. Höher zu gehen ist eine bewusste Entscheidung. |
