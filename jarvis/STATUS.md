# STATUS

> Einzige Wahrheit über den Projektstand. Claude Code liest diese Datei zuerst
> und aktualisiert sie am Ende jeder Phase. Von Hand korrigieren ist erlaubt.

AKTUELL: Phase 1 — Walking Skeleton
LETZTE ÄNDERUNG: 2026-08-25 — Code steht, DoD 3 und 5 blockiert (kein API-Key)

## Phasen

| # | Phase                     | Status   | DoD erfüllt am |
|---|---------------------------|----------|----------------|
| 1 | Walking Skeleton          | IN ARBEIT| –              |
| 2 | Tool-System               | GESPERRT | –              |
| 3 | Memory                    | GESPERRT | –              |
| 4 | Planner + Research Agent  | GESPERRT | –              |
| 5 | Permissions & Bestätigung | GESPERRT | –              |
| 6 | Hermes                    | GESPERRT | –              |
| 7 | Observability-Dashboard   | GESPERRT | –              |
| 8 | Satellite Agent           | GESPERRT | –              |
| 9 | Voice                     | GESPERRT | –              |
|10 | Härten & Verpacken        | GESPERRT | –              |

Status-Werte: GESPERRT / OFFEN / IN ARBEIT / FERTIG
Eine Phase geht nur von GESPERRT auf OFFEN, wenn die vorherige FERTIG ist.

## Phase 1 — DoD-Stand

| # | Kriterium | Stand |
|---|---|---|
| 1 | `python -m uvicorn main:app --reload` startet ohne Fehler | ✓ ausgeführt |
| 2 | `http://127.0.0.1:8000` zeigt das Chat-Interface | ✓ echter Browser |
| 3 | "Hallo, wer bist du?" → Antwort vom **echten** Modell | ✗ **kein API-Key** |
| 4 | Prozess neu starten → Verlauf ist noch da | ✓ Browser-Reload + Neustart |
| 5 | `llm_calls` hat nach dem ersten Chat eine Zeile mit **echten** Tokenzahlen | ✗ Zeile wird geschrieben und ist getestet, die Zahlen stammen aber vom Fake |
| 6 | Request ohne `X-Jarvis-Token` gibt 401 | ✓ live gegen den Server |
| 7 | `grep -ri "sk-" index.html` findet nichts | ✓ mit Gegenprobe |

**Phase 1 ist damit nicht abgenommen.** 3 und 5 hängen an einem Ding: dem Key.

## Offene Blocker

- [ ] LLM-API-Key besorgen und als `LLM_API_KEY` in `.env` eintragen
- [ ] `LLM_PROVIDER=anthropic` und `LLM_MODEL` (Modell-ID aus der Anbieter-Doku) setzen
- [ ] Preise pro 1M Token in EUR eintragen (`LLM_PRICE_IN_PER_MTOK`, `LLM_PRICE_OUT_PER_MTOK`)
- [ ] `JARVIS_TOKEN` würfeln und eintragen — sonst wird er bei jedem Start neu erzeugt
- [ ] Danach `/dod` laufen lassen: erst dann steht Phase 1 auf FERTIG

## Bekannte Abweichungen vom Plan

| Abweichung | Begründung |
|---|---|
| `GET /api/messages` und `GET /api/health` sind im Auftrag nicht genannt | Ohne sie kann die Oberfläche DoD 4 nicht zeigen — der Verlauf muss nach einem Neustart irgendwie in den Browser kommen. |
| `pytest`-Suite schon in Phase 1, obwohl 0.3 sie erst ab Phase 2 verlangt | CLAUDE.md schreibt `FakeLLMProvider` vor und dass Tests ausschließlich dagegen laufen. Die Suite kostet nichts und sperrt echtes Netz in der Testsitzung hart. |
| `scripts/smoke.py` gibt es zusätzlich | CLAUDE.md nennt `python -m scripts.smoke` unter „Befehle". |
| App startet degradiert statt abzustürzen, wenn Key oder Modell fehlen | Ein Startabbruch mit Stacktrace bringt den Nutzer nie an die Stelle, die erklärt, was fehlt. `/api/health` nennt den Grund, `/api/chat` gibt 503. |
| `JARVIS_TOKEN` wird beim Ausliefern von `/` in die Seite eingesetzt | Sonst kann die Oberfläche die eigene API nicht aufrufen. Eine fremde Seite kann die Antwort von 127.0.0.1 wegen CORS nicht lesen. Der **LLM**-Key kommt dort nie hin. |
| Leerer `JARVIS_TOKEN` wird beim Start gewürfelt statt akzeptiert | Ein leerer Vergleichswert würde jeden Request ohne Header durchlassen — genau das Loch, das 0.4.4 schließen soll. |
| `docs/contracts.md` wurde aus `docs/MASTER-PROMPT-v2.md` wiederhergestellt | Die Datei im Setup-Zip war nach 67 Bytes abgeschnitten (Split-Skript an einem Backtick abgebrochen). |
| `llm_calls` hat **keinen** `prompt_hash`, obwohl 0.6 ihn in der Log-Liste nennt | PHASE-01 nennt die Spalten abschließend. Erst melden, dann ändern — **Rückfrage offen.** |

## Entscheidungslog

| Datum | Entscheidung | Grund |
|-------|--------------|-------|
| 2026-08-25 | Kein `anthropic`-SDK, httpx direkt gegen die Messages-API | 0.3 legt httpx fest. Ein SDK wäre eine Stack-Änderung. |
| 2026-08-25 | `temperature`, `top_p`, `top_k`, `thinking.budget_tokens` werden nicht gesendet | Auf den aktuellen Opus-Modellen ist jedes davon ein 400. Ein Test hält es fest. |
| 2026-08-25 | Kosten sind `0.0`, solange keine Preise in `.env` stehen | Eine geschätzte Kostenzahl wäre schlimmer als gar keine. |
| 2026-08-25 | Kein Konversations-Browser, ein linearer Verlauf | Das Schema aus PHASE-01 kennt genau eine Tabelle `messages`. Mehrere Konversationen stehen in keiner Phase. |
| 2026-08-25 | Fehlgeschlagene Modellaufrufe werden auch in `llm_calls` geschrieben | Sonst fällt eine Retry-Schleife, die Geld verbrennt, erst auf der Rechnung auf. |
