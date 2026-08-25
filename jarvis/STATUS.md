# STATUS

> Einzige Wahrheit über den Projektstand. Claude Code liest diese Datei zuerst
> und aktualisiert sie am Ende jeder Phase. Von Hand korrigieren ist erlaubt.

AKTUELL: Phase 9 — Voice
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
| 5 | Permissions & Bestätigung | IN ARBEIT| –              |
| 6 | Hermes                    | IN ARBEIT| –              |
| 7 | Observability-Dashboard   | IN ARBEIT| –              |
| 8 | Satellite Agent           | IN ARBEIT| –              |
| 9 | Voice                     | IN ARBEIT| –              |
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

## Phase 5 — Permissions & Bestätigung

| # | Kriterium | Stand |
|---|---|---|
| 1 | Test-Tool `send_email` (EXTERNAL, schreibt nur in eine Datei) löst eine Rückfrage aus | ✓ über den echten Endpunkt |
| 2 | Die Rückfrage zeigt Empfänger, Betreff und Text vor dem Senden | ✓ |
| 3 | Ohne Bestätigung passiert nichts — die Datei ist leer | ✓ die Datei entsteht gar nicht erst |
| 4 | Ein Agent mit `max_permission = READ` kann `send_email` nicht aufrufen | ✓ auch mit dem Tool in seiner Liste |
| 5 | Audit-Log enthält jede bestätigte Aktion mit Zeitstempel | ✓ inklusive Ablehnungen und Timeouts |

Gebaut: Bestätigungs-Haken im Dispatcher, `vorschau()` je Werkzeug,
`POST /api/tasks/{id}/confirm`, `GET /api/audit`, Tabelle `audit_log`,
Werkzeug `send_email`, Rückfrage-Dialog im UI.

**Unveränderlich heißt hier wirklich unveränderlich:** zwei SQLite-Trigger
lehnen `UPDATE` und `DELETE` auf `audit_log` ab. Ein Test versucht beides und
erwartet den Fehler.

**`max_permission` steht jetzt auf EXTERNAL** (vorher LOCAL). Bis Phase 4 gab
es keinen Schutz — ein Werkzeug mit Außenwirkung wäre einfach gelaufen. Seit
Phase 5 ist alles ab EXTERNAL bestätigungspflichtig (die Registry lässt gar
nichts anderes zu), und der Mensch sieht vorher genau, was passieren würde.
SENSITIVE bleibt zu.

**Timeout:** eine unbeantwortete Rückfrage läuft nach 10 Minuten ab. Danach
gilt der Task als `cancelled` — nicht als bestätigt.

## Phase 6 — Hermes

| # | Kriterium | Stand |
|---|---|---|
| 1 | Referenz-Task läuft durch und liefert eine Empfehlung mit Begründung | ◐ läuft mit geskripteten Modellzügen durch; die Empfehlung selbst formuliert das Modell |
| 2 | Jeder Preis hat eine Quelle mit Abrufdatum; Preis ohne Quelle → Schritt fehlgeschlagen | ✓ als Regel in `core/verify.py`, Abrufdatum unter der Antwort |
| 3 | Task-Baum im UI sichtbar (Hermes → Research → Tool-Calls) | ✓ Unteraufträge persistiert, im UI aufklappbar, rekursiv |
| 4 | Gesamtkosten und Gesamttokens am Ende | ✓ inklusive dem, was Unteraufträge verbraucht haben |
| 5 | Aus Tiefe 2 wird kein weiterer Agent gerufen — abgelehnt und geloggt | ✓ |
| 6 | Der Task bleibt unter dem Default-Budget | ◐ mit Fake-Zügen ja; mit echten Modellaufrufen ungeprüft |

Gebaut: `core/delegation.py` mit dem Werkzeug `ask_agent`, Agent `hermes`,
Persistenz der Unteraufträge über `parent_task_id`, Baumansicht im UI.

**Ein Unterauftrag bekommt kein eigenes Budget.** Er zählt aufs selbe —
sonst wäre `max_cost_eur` eine Zahl ohne Bedeutung.

**Der Delegationskontext hängt an einem `ContextVar`**, nicht an einem
Modulglobal: mehrere Tasks können gleichzeitig laufen.

## Phase 7 — Observability-Dashboard

| # | Kriterium | Stand |
|---|---|---|
| 1 | Live sehen, was läuft — SSE, kein Polling im Sekundentakt | ✓ `GET /api/events`, gegen einen echten uvicorn geprüft |
| 2 | Alten Task öffnen, jeden Schritt inkl. Prompt und Antwort nachlesen | ✓ |
| 3 | Kostenanzeige stimmt mit der Summe aus `llm_calls` überein | ✓ nachgerechnet, nicht geschätzt |
| 4 | Laufender Task per Knopf abbrechen, stoppt tatsächlich | ✓ endet in `cancelled` mit übersprungenen Schritten |

Gebaut: `api/events.py` (Ereignisbus + SSE), `GET /api/stats`,
`GET /api/tool-calls`, `Step.prompt`, vier Ansichten im UI (Chat, Aufträge,
Werkzeuge, Kosten) — weiterhin ohne Build-Step.

**Ein Fund, der über den Test hinausgeht:** seit Phase 4 schrieb der Task-Pfad
nichts mehr in `llm_calls`. Nur der alte Chat-Pfad tat das. Jede Kostenanzeige
wäre zu niedrig gewesen — und DoD 5 aus Phase 1 war für Aufträge still
zurückgefallen. Jetzt wird jeder Modellzug protokolliert, auch der des
Planners.

**Zweiter Fund:** die Rückfrage aus Phase 5 wurde sichtbar, bevor der Schritt
in der Datenbank auf `needs_confirmation` stand. Ein Client sah kurz eine
offene Frage zu einem Schritt, der laut Datenbank noch lief. Der Test war
deshalb sporadisch rot — etwa jeder zwölfte Lauf.

**SSE braucht einen echten Server.** Starlettes TestClient puffert den Strom
und blockiert beim Verlassen des Kontexts. Die Stromtests starten deshalb
einen uvicorn im Thread; die Netzsperre der Testsitzung lässt dafür genau
`127.0.0.1` durch und sonst nichts.

## Phase 8 — Satellite Agent

| # | Kriterium | Stand |
|---|---|---|
| 1 | Bild mit Aufnahmedatum, Sensor, m/px und Wolkenanteil | ✗ **kein `CDSE_CLIENT_ID`/`CDSE_CLIENT_SECRET`**. Katalogsuche und Steckbrief sind gegen `httpx.MockTransport` geprüft; ein echtes Bild wurde nie geholt. Ein **Geocoder ist nicht gebaut** — die Werkzeuge nehmen eine Bounding Box, keinen Ortsnamen |
| 2 | Kein Bild unter dem Schwellwert → JARVIS sagt das, statt ein wolkiges zu liefern | ✓ |
| 3 | Vergleich zweier Zeitpunkte mit Differenzdarstellung | ◐ die **numerische** Differenz (NDVI, Fläche in Hektar) ist gebaut und getestet; die Bilder nebeneinander brauchen die Rendering-Schnittstelle und damit Zugangsdaten |

Gebaut: `core/satellite/{contracts,analysis,policy,cdse}.py`, Werkzeuge
`satellite_search` und `satellite_compare`, Agent `satellite` (READ).

**Die Auflösungsgrenze ist Code, keine Bitte.** `beurteilbar()` lehnt Aussagen
über Objekte unter dem Dreifachen der Bodenauflösung ab; `grenzsatz()` erzeugt
die Pflichtzeile `GRENZE`. Bei 10 m/px sind das 30 m — ein Einfamilienhaus ist
damit ein Pixel und nicht beurteilbar.

**Vergleichbarkeit vor Rechnung.** Liegen zwei Aufnahmen mehr als zwei Monate
im Jahreslauf auseinander, wird der Vergleich abgelehnt: was man dann sieht,
ist die Jahreszeit. Der Jahreswechsel wird korrekt gerechnet (Dezember und
Januar sind einen Monat auseinander, nicht elf).

**Beobachtungsanfragen werden abgelehnt, bevor ein Modell läuft.** Eine
Ablehnung, die von der Tagesform eines Modells abhängt, ist keine Regel. Die
Stichwortprüfung ist die erste Verteidigungslinie und ausdrücklich nicht
perfekt — die zweite ist der Systemprompt, die dritte die Auflösung selbst.

**CDSE-Endpunkte** stammen aus der offiziellen Doku (Token-Endpunkt,
OData-Katalog, Attribut `cloudCover`, Raum- und Zeitfilter). **UNSICHER:** die
Token-Doku zeigt `grant_type=password`; die `.env.example` sieht einen
Service-Account vor. Beide Wege sind implementiert, der Service-Account-Weg
ist vor dem ersten echten Aufruf zu bestätigen.

**Gefiltert wird serverseitig** — erst 200 Szenen holen und lokal filtern wäre
bei Kontingenten die falsche Reihenfolge.

## Phase 9 — Voice

| # | Kriterium | Stand |
|---|---|---|
| 1 | Taste halten, sprechen, loslassen → Transkript im Chat, Task startet | ✗ **nicht ausgeführt** — Headless-Chromium hat kein Mikrofon |
| 2 | Antwort wird vorgelesen und lässt sich abbrechen | ✗ **nicht ausgeführt** — keine Sprachsynthese im Testbrowser |
| 3 | Antwort im Sprachmodus kürzer als im Textmodus, vom Systemprompt erzwungen | ✓ backendseitig geprüft |
| 4 | Deutsch und Englisch funktionieren beide | ◐ Umschaltung gebaut und im Quelltext geprüft, nicht gesprochen getestet |

Gebaut: `SPRACHSTIL` (höchstens drei Sätze, keine Aufzählungen, keine URLs im
Fließtext), `voice`-Flag an `POST /api/tasks`, `VoiceProvider`-Abstraktion im
UI über die Web Speech API, Push-to-Talk-Knopf, Sprachumschaltung DE/EN.

**Im Sprachmodus hängt keine Quellenliste unter der Antwort** — vorgelesene
URLs sind unbrauchbar. Im Textmodus bleibt sie.

**Kein Wake Word, kein Streaming-STT** — beides ist in dieser Phase
ausdrücklich verboten. `continuous = false` und `interimResults = false` sind
die zwei Zeilen, die das sicherstellen; ein Test prüft sie.

**Was ich nicht testen konnte:** Spracherkennung und Sprachausgabe laufen im
Browser. Headless-Chromium hat weder Mikrofon noch Sprachsynthese. DoD 1, 2
und 4 brauchen einen echten Browser mit Mikrofon — das musst du selbst
ausprobieren.

## Offene Blocker

- [ ] LLM-API-Key besorgen, als `LLM_API_KEY` in `.env` eintragen
- [ ] `LLM_PROVIDER=anthropic` und `LLM_MODEL` (Modell-ID aus der Anbieter-Doku)
- [ ] `LLM_PRICE_IN_PER_MTOK` / `LLM_PRICE_OUT_PER_MTOK` in EUR
- [ ] `JARVIS_TOKEN` würfeln und eintragen
- [ ] `SEARCH_API_KEY` von api-dashboard.search.brave.com (für Phase 2 DoD 3)
- [ ] `CDSE_CLIENT_ID` / `CDSE_CLIENT_SECRET` von dataspace.copernicus.eu (Phase 8)
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
| Der Endzustand eines Tasks wird zuletzt geschrieben, nicht vom Runner | Sonst meldet `GET /api/tasks/{id}` `done`, bevor die Antwort im Verlauf steht — ein Client, der sofort nachlädt, sieht sie nicht. Preis: stirbt der Prozess genau dazwischen, steht der Task dauerhaft auf `running`. Das ist ehrlicher als ein `done` ohne Ergebnis. |
| `max_permission` von LOCAL auf EXTERNAL angehoben | Erst mit dem Bestätigungs-Flow aus Phase 5 gibt es einen Schutz, der das trägt. SENSITIVE bleibt zu. |

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
