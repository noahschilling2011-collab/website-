# STATUS

> Einzige Wahrheit über den Projektstand. Claude Code liest diese Datei zuerst
> und aktualisiert sie am Ende jeder Phase. Von Hand korrigieren ist erlaubt.

AKTUELL: Phase 2 — Tool-System
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
| 3 | Memory                    | GESPERRT | –              |
| 4 | Planner + Research Agent  | GESPERRT | –              |
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
