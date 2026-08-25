# Phase 1 — Fundament

## Ziel

Ein Satz geht vom Browser ins Backend, von dort an ein echtes Modell und
zurück — und steht nach einem Neuladen der Seite immer noch da. Mehr nicht.
Keine Tools, keine Aufgaben, keine Agenten, kein Streaming.

Das ist wenig, aber es ist die Achse, an der alles Spätere hängt: Konfiguration,
Datenbank, Provider-Abstraktion, HTTP-Schicht, Oberfläche, Testaufbau. Wenn
eines davon wackelt, wackelt jede weitere Phase mit.

## Was gebaut wird

**Konfiguration** (`core/config.py`) — `pydantic-settings`, liest `.env`.
Provider, Modell, `max_tokens`, Effort, DB-Pfad, Systemprompt. Der API-Key
kommt aus der Umgebung und wird nirgends geloggt.

**Datenbank** (`core/db.py`, `core/schema.sql`) — SQLite aus der Stdlib.
Zwei Tabellen: `conversations`, `messages`. Fremdschlüssel an, WAL an,
Löschen kaskadiert. Kein ORM.

**Provider** (`core/llm.py`) — ein `LLMProvider`-Protokoll mit genau einer
Methode `complete()`. Zwei Implementierungen:

- `FakeLLMProvider` — deterministisch, ohne Netz. Wogegen Tests laufen.
- `AnthropicProvider` — `httpx` gegen `POST /v1/messages`. Wiederholt bei
  429/500/529 mit wachsender Wartezeit, übersetzt 401/403/404/400 in
  verständliche Fehler.

**HTTP** (`api/`) — `/api/health`, Konversationen anlegen/auflisten/lesen/
löschen, `/api/chat`. Ein Fehler des Providers wird zu einem 502 mit Klartext,
nie zu einem Stacktrace im Browser.

**Oberfläche** (`web/index.html`) — eine Datei, Vanilla JS, kein Build.
Dunkel, Glas, eine Akzentfarbe. Seitenleiste mit Konversationen, Chatfenster,
Eingabe.

**Tests** (`tests/`) — laufen ausschließlich gegen `FakeLLMProvider`. Echte
Netzwerkverbindungen sind in der Testsitzung gesperrt, nicht bloß unterlassen.

**Rauchtest** (`scripts/smoke.py`) — fährt die App gegen eine temporäre
Datenbank hoch und geht den ganzen Weg einmal durch.

## Warum kein Streaming

Streaming ist Phase 2. Es zieht Abbruchlogik, Teil-Persistenz und einen
zweiten Fehlerpfad nach sich. Beides gleichzeitig zu bauen heißt, keines von
beidem sauber zu bauen.

## Definition of Done

Jeder Punkt ist prüfbar. „Sieht gut aus" zählt nicht.

1. `pytest -q` ist grün und macht dabei **keinen** echten Modellaufruf.
   Nachweisbar dadurch, dass echte Netzwerkverbindungen in der Testsitzung
   eine Exception werfen.
2. `python -m scripts.smoke` läuft mit `FakeLLMProvider` durch und gibt
   Health, angelegte Konversation, Antwort und Verlauf aus.
3. `uvicorn main:app --reload` startet, `GET /` liefert die Oberfläche.
4. `GET /api/health` meldet Provider, Modell und erreichbare Datenbank.
5. Eine Nachricht über die Oberfläche erzeugt genau zwei Zeilen in `messages`
   (Nutzer, Assistent) und eine `conversation`, falls noch keine bestand.
6. Nach Neuladen der Seite ist die Konversation samt Verlauf noch da.
7. `AnthropicProvider` schickt Header und Body exakt in der dokumentierten
   Form — geprüft gegen einen `httpx.MockTransport`, nicht gegen die echte API.
   Insbesondere: kein `temperature`, kein `budget_tokens` (beide sind auf
   Opus 5 ein 400).
8. Ein fehlender API-Key führt zu einer klaren Fehlermeldung, nicht zu einem
   Absturz.
9. Der API-Key taucht in keiner Antwort, keinem Log und keiner Fehlermeldung
   auf.
10. `web/index.html` lädt nichts aus dem Netz und rendert ohne
    JavaScript-Fehler in 360, 768 und 1440 Pixel Breite.

## Nicht in dieser Phase

Streaming · Tools · Tasks · Agenten · Gedächtnis/Suche · Kostenanzeige ·
Nutzerverwaltung · Docker · irgendein Build-Step.
