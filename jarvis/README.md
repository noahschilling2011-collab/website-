# JARVIS

Persönliches AI-Operating-System. Läuft lokal, spricht Deutsch, gehört dir.
Kein Account, kein Deployment, keine Nutzerverwaltung — JARVIS hört auf
`127.0.0.1` und redet mit genau einem Menschen.

Der Projektstand steht in [STATUS.md](STATUS.md). **Dort zuerst schauen.**

## Installation

```bash
pip install -r requirements.txt
```

## Start

```bash
python -m uvicorn main:app --reload
```

Dann <http://127.0.0.1:8000> öffnen.

Ohne weitere Einrichtung läuft der **FakeLLMProvider**: deterministische
Antworten, kein Netz, keine Kosten.

Die Oberfläche läuft damit, und Aufträge laufen durch — der Fake liefert dem
Planner einen Plan mit genau **einem** Schritt, dessen Beschreibung das Ziel
ist. Aber **es wird kein Werkzeug ausgeführt**: der Fake schlägt nie einen
Werkzeugaufruf vor. Rechner, Websuche, Gedächtnis und Bestätigungsdialog
brauchen einen echten Provider mit Key — und der kostet Geld.

---

## Vor dem ersten echten Modellaufruf

```bash
cp .env.example .env
```

| Variable | Woher |
|---|---|
| `JARVIS_TOKEN` | `python -c "import secrets;print(secrets.token_urlsafe(32))"` |
| `LLM_PROVIDER` | `groq` (kostenlos) oder `anthropic` (kostet Geld). Siehe `.env.example` für den Unterschied |
| `LLM_API_KEY` | Konto beim Anbieter, Key aus der Console |
| `LLM_MODEL` | Modell-ID **aus der Doku des Anbieters**, nicht raten |
| `LLM_PRICE_IN_PER_MTOK`, `LLM_PRICE_OUT_PER_MTOK` | Preisseite des Anbieters, je 1 Mio. Token. **Die Felder heißen EUR, Anthropic rechnet in USD** — entweder umrechnen oder jedes „EUR“ in JARVIS als USD lesen. Ein Wechselkurs wird nirgends geholt. |
| `SEARCH_API_KEY` | <https://api-dashboard.search.brave.com> — für die Websuche |
| `CDSE_CLIENT_ID`, `CDSE_CLIENT_SECRET` | <https://dataspace.copernicus.eu> — für Satellitendaten |

**Ab dann kostet jeder Aufruf Geld.** Ein Auftrag geht durch Planner, Schritte
und Zusammenfassung — das sind drei bis vier Modellaufrufe, nicht einer.
Setz `BUDGET_MAX_COST_EUR` bewusst.

Bleiben die Preisfelder leer, steht in `llm_calls.cost_eur` eine `0.0` — keine
geschätzte Zahl. Eine erfundene Kostenrechnung wäre schlimmer als gar keine.

## Zugangsschutz

Jeder `/api/`-Request braucht den Header `X-Jarvis-Token`. Auch lokal. Die
Oberfläche bekommt den Token beim Ausliefern von `/` eingesetzt; der
**LLM-Key** verlässt das Backend nie.

Steht kein `JARVIS_TOKEN` in der `.env`, würfelt JARVIS beim Start einen und
schreibt ihn ins Log. Der Schutz ist damit nie aus — der Token ändert sich
aber bei jedem Neustart.

## Prüfen

```bash
pytest -q                       # ohne Netz, ohne Kosten
python -m scripts.smoke         # End-zu-End gegen den Fake-Anbieter
python -m scripts.smoke --real  # dasselbe mit echtem Modell — kostet Geld
```

`pytest` kann keinen echten Modellaufruf machen: `tests/conftest.py` sperrt
die httpx-Transportschicht für die ganze Testsitzung und lässt nur
`127.0.0.1` durch (für die SSE-Tests gegen einen echten uvicorn).
`tests/test_no_network.py` prüft, dass die Sperre hält.

## Betrieb

```bash
python -m scripts.backup sichern              # Backup nach data/backup-<zeit>.db
python -m scripts.backup pruefen datei.db     # Integrität und Zeilenzahlen
python -m scripts.backup einspielen datei.db  # Restore, legt die alte DB beiseite
python -m scripts.migrate                     # Datenbank einer älteren Phase nachziehen
python -m scripts.measure                     # misst, ob SQLite noch reicht
```

Gesichert wird über SQLites Backup-API, nicht mit `cp`: bei eingeschaltetem
WAL liegen die letzten Schreibvorgänge in `-wal`, und eine kopierte `.db`
allein ist unvollständig.

### Docker

```bash
cp .env.example .env    # Werte eintragen
docker compose up
```

Das Port-Mapping veröffentlicht bewusst nur an `127.0.0.1`. **Ungeprüft:** in
der Umgebung, in der diese Dateien entstanden sind, war kein Docker-Daemon
erreichbar.

## Aufbau

```
main.py              Einstiegspunkt
index.html           die gesamte Oberfläche, ohne Build-Step
core/
  config.py          .env, Preise, Budgets
  contracts.py       Tool · ToolResult · Permission · Step · Task · TaskBudget · Agent
  db.py              SQLite: messages, llm_calls, tool_calls, facts, task_log,
                     tasks, steps, audit_log
  llm.py             LLMProvider (abstrakt) · FakeLLMProvider · AnthropicProvider
  memory.py          FTS5-Suche, Fakten, Konflikte, episodisches Log
  planner.py         zerlegt ein Ziel in Schritte
  verify.py          prüft einen Schritt — Code, kein Modell
  runner.py          führt Schritte aus, hält das Budget ein
  agents.py          hermes · research · satellite · jarvis
  delegation.py      ask_agent, Tiefengrenze
  tools/             Registry, Dispatcher, Werkzeuge
  satellite/         Szenen, Auflösungsgrenze, Change Detection, CDSE
api/                 Endpunkte, Zugangsschutz, Ereignisstrom
scripts/             smoke · backup · migrate · measure · healthcheck
docs/                Verträge, Phasenaufträge, Entscheidungen
```

## Warum SQLite und nicht Postgres

Gemessen, nicht angenommen — `python -m scripts.measure` mit 20.000
Nachrichten und 5.000 Fakten:

| Abfrage | Median | p95 |
|---|---|---|
| FTS5 über `facts` | 4,1 ms | 4,8 ms |
| FTS5 über `messages` | 20,0 ms | 21,4 ms |
| Kontextblock (Suche + Format) | 4,0 ms | 4,4 ms |

Ein Modellaufruf dauert das Tausendfache. Postgres oder pgvector würden hier
nichts lösen, was kaputt wäre. Die Messung gehört wiederholt, wenn die
Datenmenge deutlich wächst.

## Mitarbeiten

[CLAUDE.md](CLAUDE.md) enthält die Regeln, [STATUS.md](STATUS.md) den Stand,
[docs/phases/](docs/phases/) die Aufträge. Bearbeitet wird immer nur die als
`AKTUELL` markierte Phase.

---

## Weltlage — der Globus

`http://127.0.0.1:8000/weltlage` — eigene Vollbildseite, kein Build-Step.
Three.js und die Ländergrenzen liegen unter `static/vendor/` mit fester Version,
nicht am CDN: die Seite läuft damit auch ohne Netz.

Ein Klick auf ein Land lädt **einen** Auftrag. Der zweite Klick innerhalb von
60 Minuten kostet nichts — die Statusleiste zeigt Abfragen, Cache-Treffer,
Cache-Quote, verworfene Meldungen und die Tageskosten aus `llm_calls`.

**Ohne `SEARCH_API_KEY` findet der Weltlage-Agent keine echten Meldungen.**
Der Globus, der Cache und die Zähler laufen trotzdem.

## Endpunkte ohne Oberfläche — „nur API, kein UI"

Diese Endpunkte sind absichtlich nur über die API erreichbar. Die Oberfläche
ruft sie nicht auf. Das ist kein toter Code, das ist Absicht — ein Audit, das
„wird nirgends aufgerufen" meldet, hat hier recht und trotzdem unrecht.

| Endpunkt | wofür | Beispiel |
|---|---|---|
| `GET /api/audit` | jede bestätigte, abgelehnte oder abgelaufene Aktion ab EXTERNAL, unveränderlich | `curl -H "X-Jarvis-Token: $JARVIS_TOKEN" 127.0.0.1:8000/api/audit` |
| `GET /api/task-log` | eine Zeile je Auftrag: Ziel, Ausgang, Zusammenfassung | `curl -H "X-Jarvis-Token: $JARVIS_TOKEN" 127.0.0.1:8000/api/task-log` |

`tests/test_routen_haben_einen_nutzer.py` hält diese Liste aktuell: ein neuer
Endpunkt muss entweder in `index.html` vorkommen oder dort ausdrücklich als
„nur API" eingetragen sein.
