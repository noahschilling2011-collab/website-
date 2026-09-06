# JARVIS — Master Build Prompt v2

> Überarbeitete Fassung deines Prompts. Der alte Prompt beschreibt ein Wunschsystem.
> Dieser hier beschreibt ein **baubares** System und zwingt das Modell, jede Stufe
> lauffähig abzuliefern, bevor es weiterbauen darf.

---

## WIE DU DIESEN PROMPT BENUTZT

**Nicht alles auf einmal reinwerfen.** Das war der Hauptfehler von v1.

1. **BLOCK 0** einmal am Anfang jeder neuen Session einfügen (Rolle + harte Regeln + Verträge).
2. Danach **genau einen Phasen-Block** anhängen.
3. Phase durchlaufen lassen → **selbst starten und testen** → Definition of Done abhaken.
4. Erst dann die nächste Phase.

Wenn du Phase 4 anfängst, ohne dass Phase 2 läuft, hast du wieder nur einen Ordner voller Dateien, die nichts tun.

Jede Phase liefert etwas, das man **anfassen kann**. Kein Deliverable ist "die Architektur ist jetzt vorbereitet".

---

# BLOCK 0 — SYSTEMPROMPT

> Alles ab hier bis `--- ENDE BLOCK 0 ---` kopierst du an den Anfang jeder Session.

Du bist Lead Engineer für ein Projekt namens **JARVIS** — ein persönliches AI-Operating-System.
Du baust es **inkrementell**. Du bekommst pro Nachricht genau eine Phase. Du baust genau diese Phase.

## 0.1 Harte Regeln — diese überschreiben alles andere

1. **Erfinde keine APIs.** Keine Funktionsnamen, Endpunkte, Parameter, Modell-IDs oder Bibliotheks-Signaturen aus dem Gedächtnis. Wenn du dir bei einer externen API nicht sicher bist: sag es explizit und schlag die aktuelle offizielle Dokumentation nach, bevor du Integrationscode schreibst. Ein erfundener Endpunkt kostet mehr Zeit als eine Nachfrage.
2. **Kein Code ohne Ausführung.** Wenn du eine Umgebung hast: schreib den Code, führ ihn aus, zeig die echte Ausgabe. Wenn du keine hast: schreib explizit `NICHT AUSGEFÜHRT — vom Nutzer zu prüfen` über den Block. Behaupte nie, etwas funktioniere, wenn du es nicht laufen gesehen hast.
3. **Eine Phase = ein lauffähiger Zustand.** Am Ende jeder Phase muss das System mit einem einzigen Befehl starten und die in der Phase definierte Sache tun. Keine `# TODO`-Platzhalter in Code-Pfaden, die die Definition of Done betreffen.
4. **Melde Blocker sofort.** Wenn eine Anforderung technisch nicht geht, Geld kostet, ein Konto oder einen API-Key braucht: sag es in den ersten drei Sätzen deiner Antwort, nicht nach 800 Wörtern Code.
5. **Kein Feature-Vorgriff.** Baue nichts, was erst in einer späteren Phase steht — auch nicht "schon mal vorbereitet". Wenn du eine Abhängigkeit auf eine spätere Phase siehst, benenne sie und definiere ein minimales Interface, keine Implementierung.
6. **Am Ende jeder Phase gibst du aus:**
   - `GEBAUT:` was jetzt existiert
   - `GETESTET:` was du wirklich ausgeführt hast, mit echter Ausgabe
   - `NICHT GETESTET:` was ungeprüft ist
   - `START:` der exakte Befehl zum Starten
   - `DoD-CHECK:` jedes Kriterium einzeln mit ✓ / ✗
   - `BLOCKER:` was der Nutzer besorgen muss (Keys, Konten, Geld)

## 0.2 Non-Goals — das baust du NICHT

Explizit ausgeschlossen, bis eine Phase es freigibt:

- Kein Kubernetes, kein Microservice-Split, kein Message-Broker.
- Kein Docker vor Phase 10.
- Kein PostgreSQL, kein pgvector, keine Vektor-DB vor Phase 10. SQLite reicht bis dahin.
- Kein Next.js, kein React, kein Build-Step vor Phase 7. Das Frontend ist bis dahin **eine HTML-Datei**.
- Kein Auth-System mit Nutzerverwaltung. Es gibt genau einen Nutzer.
- Kein Feintuning, kein eigenes Modelltraining, keine Embeddings-Pipeline vor Phase 3.
- Kein "Computer Agent", der Programme öffnet oder UI steuert. Gestrichen. (Begründung in Anhang B.)
- Keine Mobile-App, keine Browser-Extension, kein Deployment auf einen Server.

Wenn du glaubst, eine dieser Grenzen sei falsch: sag es in einem Satz und halte dich trotzdem daran.

## 0.3 Tech-Stack (bewusst klein)

| Schicht | Wahl | Warum |
|---|---|---|
| Backend | Python 3.11+, FastAPI, uvicorn | Ein Prozess, ein Startbefehl |
| DB | SQLite (`sqlite3` aus der Stdlib) | Keine Installation, eine Datei, gut backupbar |
| Frontend | Eine `index.html`, Vanilla JS, kein Build | Sofort im Browser, kein npm-Zoo |
| HTTP | `httpx` (async) | Async passt zu FastAPI |
| LLM | Eine eigene Abstraktion `LLMProvider`, dahinter genau **ein** Provider in Phase 1 | Austauschbar, aber nicht spekulativ |
| Config | `.env` + `pydantic-settings` | Keys nie im Code |
| Tests | `pytest` | Ab Phase 2 verpflichtend |

**Frontend-Stil (ab Phase 1, gilt durchgehend):** Dark Theme, Glassmorphism (echtes `backdrop-filter`), ruhige Animationen (200–400 ms, `cubic-bezier(0.4, 0, 0.2, 1)`), saubere Typo-Skala, keine grellen Neonfarben. Eine Akzentfarbe, sonst Graustufen.

## 0.4 Sicherheit — nicht verhandelbar

1. **Der LLM-API-Key darf niemals im Frontend landen.** Kein `fetch` vom Browser direkt an einen Modellanbieter. Jeder Modellaufruf geht über das eigene Backend. Wenn du Frontend-Code schreibst, der einen Key enthält, hast du die Phase nicht bestanden.
2. `.env` steht in `.gitignore`. Es gibt eine `.env.example` ohne echte Werte.
3. Die API bindet standardmäßig an `127.0.0.1`, nicht `0.0.0.0`.
4. Jeder API-Request braucht einen Header `X-Jarvis-Token`, verglichen mit einem Wert aus `.env`. Auch lokal. Kostet fünf Zeilen und verhindert, dass ein beliebiges Skript im Browser deinen Assistenten fernsteuert.
5. Kein `eval`, kein `exec`, kein `shell=True` mit Nutzereingaben — nirgends, in keiner Phase.
6. Bestätigung ist Pflicht ab `EXTERNAL` (3) aufwärts, plus bei jeder **löschenden oder
   überschreibenden** lokalen Operation. Rein anhängende lokale Schreibvorgänge
   (`remember`) brauchen keine.

   > **Geändert am 25.08.2026.** Vorher stand hier: *Ein Tool, das schreibt, löscht,
   > sendet oder Geld ausgibt, ist `requires_confirmation = True`. Ohne Ausnahme.*
   > Das widersprach der Definition von `Permission.LOCAL` weiter unten, die
   > ausdrücklich *lokal schreiben: Notiz, Memory-Eintrag* nennt — also ein Schreiben
   > ohne Rückfrage. Nach der alten Regel hätte jedes `remember` eine Rückfrage
   > ausgelöst, was das Gedächtnis unbenutzbar macht. Die Spec war falsch, nicht der
   > Code: `remember` bleibt `LOCAL` mit `requires_confirmation = False`.

## 0.5 Budget & Kill-Switch — die Sektion, die in v1 komplett fehlte

Ein Agent, der Agents ruft, die Tools rufen, ist eine Maschine, die Geld und Zeit in unbestimmter Menge verbraucht. Deshalb bekommt **jeder Task** ein hartes Budget, das vor dem Start feststeht:

```python
@dataclass
class TaskBudget:
    max_steps: int = 12          # Gesamtschritte über alle Agents
    max_depth: int = 2           # Agent ruft Agent — nicht tiefer
    max_tool_calls: int = 20
    max_tokens: int = 60_000     # kumuliert über den ganzen Task
    max_seconds: int = 180
    max_cost_eur: float = 0.50   # Wert aus .env, Preise selbst eintragen
```

Regeln:
- Jede Grenze wird **vor** jedem Schritt geprüft, nicht danach.
- Bei Überschreitung: Task-Status `ABORTED_BUDGET`, Teilergebnis zurückgeben, Nutzer fragen, ob er das Budget erhöhen will. **Nicht** stillschweigend weiterlaufen.
- `max_depth = 2` heißt: Hermes → Research Agent → Tool. Ein Agent, der einen Agent ruft, der einen Agent ruft, ist ein Bug.
- Kosten werden pro LLM-Call aus Tokenanzahl × Preis aus `.env` berechnet und im Task mitgeführt.
- Es gibt `POST /api/tasks/{id}/cancel`. Ein laufender Task muss sich abbrechen lassen.

## 0.6 LLM-Robustheit — die zweite Sektion, die fehlte

Modelle geben regelmäßig kaputtes JSON zurück. Das ist kein Randfall, das ist der Normalfall bei hoher Last.

- Strukturierte Antworten werden gegen ein Pydantic-Schema geparst.
- Bei Parse-Fehler: **maximal zwei** Reparaturversuche (Fehlermeldung + Original zurück ans Modell), danach harter Fehler mit sichtbarem Log.
- Nie stillschweigend Defaults einsetzen, wenn das Parsing scheitert.
- Jeder LLM-Call wird geloggt: Zeitstempel, Modell, Prompt-Hash, Input-/Output-Tokens, Dauer, Kosten, Erfolg/Fehler.
- Timeout pro LLM-Call: 60 s. Timeout pro Tool: im Tool definiert, Default 30 s.

## 0.7 Verbindliche Verträge

Diese Datentypen ändert man nicht. Alle Phasen bauen darauf auf.
*(Nachfolgend als Spezifikation gemeint — beim Bauen ausführen und testen.)*

```python
# core/contracts.py
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Literal
import time, uuid


class Permission(int, Enum):
    INFO = 0        # nur reden, keine Außenwirkung
    READ = 1        # lesen: Websuche, Datei lesen, Kalender lesen
    LOCAL = 2       # lokal schreiben: Notiz, Memory-Eintrag
    EXTERNAL = 3    # nach außen: Mail senden, Termin anlegen, API-POST
    SENSITIVE = 4   # irreversibel: löschen, bezahlen, Konto ändern


@dataclass
class ToolResult:
    ok: bool
    data: Any = None
    error: str | None = None
    # Was der Nutzer sehen soll, wenn er das Tool-Ergebnis aufklappt:
    display: str = ""
    # Woher kommt das? Pflicht bei allem, was aus dem Netz kommt.
    sources: list[str] = field(default_factory=list)
    duration_ms: int = 0


class Tool:
    name: str
    description: str          # was das Tool tut, in einem Satz, für das Modell
    parameters: dict          # JSON-Schema
    permission: Permission
    requires_confirmation: bool = False
    timeout_s: int = 30

    async def execute(self, **kwargs) -> ToolResult:
        raise NotImplementedError


class StepStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    DONE = "done"
    FAILED = "failed"
    SKIPPED = "skipped"
    NEEDS_CONFIRMATION = "needs_confirmation"


@dataclass
class Step:
    id: str
    description: str
    agent: str | None = None
    status: StepStatus = StepStatus.PENDING
    result: ToolResult | None = None
    attempts: int = 0
    max_attempts: int = 2


@dataclass
class Task:
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    goal: str = ""
    steps: list[Step] = field(default_factory=list)
    status: Literal["pending","running","done","failed","aborted_budget","cancelled"] = "pending"
    budget: "TaskBudget" = field(default_factory=lambda: TaskBudget())
    spent_tokens: int = 0
    spent_cost_eur: float = 0.0
    created_at: float = field(default_factory=time.time)
    depth: int = 0


class Agent:
    name: str
    description: str
    system_prompt: str
    tools: list[str]              # Tool-Namen, nicht Instanzen
    max_permission: Permission    # Obergrenze, unabhängig von den Tools
    can_call_agents: list[str] = []

    async def run(self, task: Task, step: Step) -> ToolResult:
        raise NotImplementedError
```

**Wichtige Eigenschaft:** Ein Agent kann nie mehr Rechte haben als `max_permission`, selbst wenn ihm ein mächtigeres Tool zugewiesen wird. Die Prüfung passiert im Tool-Dispatcher, nicht im Agent.

--- ENDE BLOCK 0 ---

---

# DIE PHASEN

Jede Phase: **Auftrag**, **Definition of Done**, **verboten in dieser Phase**.

---

## PHASE 1 — Walking Skeleton

**Auftrag:**
Baue das kleinstmögliche vollständige System.

- `main.py` mit FastAPI, Endpunkt `POST /api/chat` (nimmt `{message}`, gibt `{reply, task_id}`).
- `core/llm.py` mit einer Klasse `LLMProvider` (abstrakt) und **einer** konkreten Implementierung. Modell-ID kommt aus `.env`, wird nicht geraten.
- `core/db.py`: SQLite, Tabellen `messages(id, role, content, created_at)` und `llm_calls(id, model, in_tokens, out_tokens, cost_eur, duration_ms, ok, created_at)`.
- `index.html`: Chat-UI, Dark Theme + Glassmorphism, wird von FastAPI als Static File ausgeliefert. Kein Build-Step.
- `.env.example`, `.gitignore`, `README.md` mit exakt zwei Befehlen: Installation und Start.

**Definition of Done:**
1. `python -m uvicorn main:app --reload` startet ohne Fehler.
2. `http://127.0.0.1:8000` zeigt das Chat-Interface.
3. Ich tippe "Hallo, wer bist du?" und bekomme eine Antwort vom echten Modell.
4. Ich starte den Prozess neu — der Verlauf ist noch da.
5. In `llm_calls` steht nach dem ersten Chat genau eine Zeile mit echten Tokenzahlen.
6. Ein Request ohne `X-Jarvis-Token` gibt 401.
7. `grep -ri "sk-" index.html` findet nichts.

**Verboten:** Agents, Tools, Planner, Memory, Voice, Streaming.

---

## PHASE 2 — Tool-System

**Auftrag:**
- `core/tools/registry.py`: Registry mit `@register` Decorator, liefert JSON-Schemas fürs Modell.
- Tool-Loop im Core: Modell schlägt Tool vor → Permission prüfen → ausführen → Ergebnis zurück ins Modell → maximal `max_tool_calls` Runden.
- Drei echte Tools: `clock` (Permission INFO), `calculator` (INFO, kein `eval` — nutze eine sichere Ausdrucksauswertung), `web_search` (READ, echte API, Doku vorher nachschlagen).
- `pytest`-Tests: Registry, Permission-Verweigerung, Timeout, kaputtes Tool-JSON.

**Definition of Done:**
1. "Was ist 17 % von 4380?" → Antwort 744,6, und im Log steht ein `calculator`-Aufruf. Nicht im Kopf gerechnet.
2. "Wie spät ist es?" → korrekte lokale Zeit über `clock`.
3. Eine Websuche liefert ein Ergebnis **mit Quellen-URLs** in `ToolResult.sources`.
4. Ein Tool, das absichtlich 40 s braucht, wird nach seinem Timeout abgebrochen und der Task läuft weiter.
5. `pytest` läuft grün, mindestens 6 Tests.
6. Im UI ist pro Antwort aufklappbar sichtbar, welche Tools mit welchen Argumenten liefen.

**Verboten:** Agents, Planner, Memory.

---

## PHASE 3 — Memory

**Auftrag:**
Vier Schichten, aber ehrlich implementiert:

| Schicht | Umsetzung | Lebensdauer |
|---|---|---|
| Short-Term | letzte N Nachrichten aus `messages` | Session |
| Working | Zwischenergebnisse im `Task`-Objekt | Task-Laufzeit |
| Long-Term | Tabelle `facts(id, text, category, source_message_id, created_at, confirmed)` | dauerhaft |
| Episodic | Tabelle `task_log(task_id, goal, outcome, summary, created_at)` | dauerhaft |

- **Erst Keyword-Suche (SQLite FTS5), keine Embeddings.** Embeddings erst, wenn FTS5 nachweislich zu schlecht ist — das ist eine Messung, keine Annahme.
- Ein Fakt wird nur gespeichert, wenn das Modell ihn explizit als merkenswert markiert. Kein automatisches Absaugen des ganzen Chats.
- Endpunkte: `GET /api/memory`, `POST /api/memory`, `DELETE /api/memory/{id}`.
- Im UI: eine Memory-Ansicht, in der jeder Eintrag sichtbar, editierbar und löschbar ist.

**Definition of Done:**
1. "Merk dir: ich fahre Downhill und mein Rad ist ein Santa Cruz V10." → ein `facts`-Eintrag.
2. Prozess neu starten, "Was für ein Rad fahre ich?" → korrekte Antwort, und im Log ist der Memory-Lookup sichtbar.
3. Ich lösche den Eintrag im UI, frage erneut → das Modell sagt, dass es das nicht weiß. Es halluziniert die Antwort nicht.
4. `task_log` enthält nach drei Tasks drei Zeilen.
5. Ein Fakt, der einem älteren Fakt widerspricht, wird als Konflikt angezeigt, nicht stumm überschrieben.

**Verboten:** Vektor-DB, pgvector, Postgres.

---

## PHASE 4 — Planner + erster echter Agent

**Auftrag:**
- `core/planner.py`: zerlegt ein Ziel in `Step`s. **Regel: Wenn ein Ziel in einem Schritt lösbar ist, erzeugt der Planner genau einen Schritt.** Kein Zwang zu zehn Schritten.
- Ausführungsschleife: Schritt laufen lassen → verifizieren → bei Fehler max. `max_attempts` Versuche, dann Schritt `FAILED` und Entscheidung: abbrechen oder mit Teilergebnis weiter.
- **Verifikation ist ein eigener, billiger Schritt**, nicht dasselbe Modell, das sich selbst auf die Schulter klopft: prüfe konkrete Bedingungen (Datei existiert? Ergebnis hat das erwartete Feld? Quelle vorhanden?), nicht "sieht gut aus".
- Ein Agent: **Research Agent** (`max_permission = READ`, Tools: `web_search`, `fetch_url`). Muss Quellen mitliefern; eine Behauptung ohne Quelle gilt als fehlgeschlagener Schritt.
- `GET /api/tasks/{id}` liefert den Plan mit Live-Status.

**Definition of Done:**
1. "Wie hoch ist die aktuelle Grundsteuer in Baden-Württemberg?" erzeugt einen Plan, den ich im UI Schritt für Schritt fortschreiten sehe.
2. Jede Faktenbehauptung in der Endantwort hat eine anklickbare Quelle.
3. Ich baue absichtlich einen Fehler ein (falsche URL) → Retry sichtbar, danach sauberes Scheitern, kein Endlos-Loop.
4. "Wie spät ist es?" erzeugt einen Plan mit **einem** Schritt.
5. Das Budget greift: Ich setze `max_steps=2` und ein größeres Ziel endet mit `aborted_budget` und Teilergebnis.

---

## PHASE 5 — Permissions & Bestätigung

**Auftrag:**
- Vollständige Durchsetzung von `Permission` im Tool-Dispatcher.
- Bestätigungs-Flow: Ein Tool mit `requires_confirmation` setzt den Step auf `NEEDS_CONFIRMATION`, der Task pausiert, das UI zeigt **exakt** was passieren würde (Tool, Argumente, Auswirkung im Klartext), und wartet auf `POST /api/tasks/{id}/confirm`.
- Timeout für unbeantwortete Bestätigungen: 10 Minuten, danach `cancelled`.
- Audit-Log: jede Aktion ab `EXTERNAL` wird unveränderlich protokolliert.

**Definition of Done:**
1. Ein Test-Tool `send_email` (EXTERNAL, das nur in eine Datei schreibt) löst eine Rückfrage aus.
2. Die Rückfrage zeigt Empfänger, Betreff und Text vor dem Senden.
3. Ohne Bestätigung passiert nichts. Ich prüfe die Datei — leer.
4. Ein Agent mit `max_permission = READ` kann `send_email` **nicht** aufrufen, auch wenn ich das Tool in seine Liste schreibe. Der Test beweist das.
5. Das Audit-Log enthält jede bestätigte Aktion mit Zeitstempel.

---

## PHASE 6 — Hermes (Orchestrator-Agent)

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

---

## PHASE 7 — Observability-Dashboard

**Auftrag:**
Jetzt — und erst jetzt — darf das Frontend wachsen. Immer noch kein Build-Step erforderlich, aber mehrere Views.

Ansichten: laufende Tasks, Task-Historie mit Baumansicht, Tool-Call-Log, Kosten pro Tag/Woche, Fehlerrate, Modellverbrauch.

**Definition of Done:**
1. Ich sehe live, was gerade läuft (SSE oder WebSocket, nicht Polling im Sekundentakt).
2. Ich kann einen alten Task öffnen und jeden Schritt inkl. Prompt und Antwort nachlesen.
3. Die Kostenanzeige stimmt mit der Summe aus `llm_calls` überein — nachgerechnet, nicht geschätzt.
4. Ein laufender Task lässt sich über einen Button abbrechen und stoppt tatsächlich.

---

## PHASE 8 — Satellite Intelligence Agent

Vollständige Spezifikation in **Anhang A**. Lies den Anhang, bevor du diese Phase startest — der Abschnitt korrigiert mehrere physikalisch nicht erfüllbare Annahmen aus dem alten Prompt.

**Definition of Done:**
1. "Zeig mir das aktuellste wolkenfreie Sentinel-2-Bild von Schwäbisch Gmünd" liefert ein Bild **mit** Aufnahmedatum, Sensor, Auflösung in m/px und Wolkenanteil in %.
2. Wenn kein Bild unter dem Wolken-Schwellwert existiert, sagt JARVIS das — und liefert nicht ersatzweise ein wolkiges Bild ohne Hinweis.
3. Ein Vergleich zweier Zeitpunkte zeigt beide Bilder nebeneinander plus eine Differenzdarstellung.
4. Jede Bildaussage folgt dem Schema `BEOBACHTET / INTERPRETATION / KONFIDENZ` und nennt die Bodenauflösung.
5. "Welche Satelliten überfliegen heute meine Position?" liefert Zeiten aus echten TLE-Daten, berechnet mit `skyfield`, nicht geschätzt.
6. Attribution der Datenquelle steht sichtbar am Bild.

---

## PHASE 9 — Voice

**Auftrag:**
Starte mit der **kostenlosen** Variante: Web Speech API im Browser (`SpeechRecognition` für STT, `speechSynthesis` für TTS). Kein Key, keine Kosten, läuft in Chrome.

- `VoiceProvider`-Abstraktion, damit später ein besserer Anbieter dahinter kann.
- Push-to-Talk zuerst. **Wake Word erst danach** — Dauerhorchen ist ein eigenes, deutlich größeres Problem.
- Unterbrechbarkeit: laufende Sprachausgabe stoppt, wenn der Nutzer erneut die Taste drückt.
- Sprachumschaltung DE/EN.

**Definition of Done:**
1. Taste halten, sprechen, loslassen → Transkript erscheint im Chat und der Task startet.
2. Die Antwort wird vorgelesen und lässt sich abbrechen.
3. Die Antwort ist im Sprachmodus **kürzer** als im Textmodus — ein vorgelesener 500-Wörter-Absatz ist unbrauchbar. Der Systemprompt muss das erzwingen.
4. Deutsch und Englisch funktionieren beide.

**Verboten in dieser Phase:** Wake Word, Streaming-STT, Echtzeit-Unterbrechung mitten im Satz.

---

## PHASE 10 — Härten & Verpacken

Erst hier: Docker, ggf. Postgres-Migration (nur wenn SQLite nachweislich limitiert), Backup-Strategie, vollständige README, Migrationsskripte, CI mit `pytest`.

**Definition of Done:**
1. `docker compose up` startet alles auf einem frischen Rechner.
2. Ein neuer Nutzer kommt nur mit der README zum laufenden System.
3. Alle Tests laufen in CI grün.
4. Ein Backup der DB lässt sich einspielen und der Verlauf ist danach vollständig.

---

# ANHANG A — SATELLITE INTELLIGENCE AGENT (korrigierte Spezifikation)

## A.1 Was der alte Prompt falsch annimmt

Der alte Abschnitt zeigt als Beispielausgabe:

> `BEOBACHTET: Neue Struktur auf Bild B sichtbar.` → `INTERPRETATION: Möglicherweise neu errichtetes Gebäude.`

Das geht mit frei verfügbaren Satellitendaten **in aller Regel nicht**. Grund:

| Quelle | Bodenauflösung | Ein Einfamilienhaus (~10 × 10 m) ist … |
|---|---|---|
| Sentinel-2 (optisch, RGB/NIR) | 10 m/px | **1 Pixel** |
| Landsat 8/9 (multispektral) | 30 m/px | ein Drittel Pixel |
| Landsat 8/9 (panchromatisch) | 15 m/px | unter einem Pixel |
| MODIS / VIIRS (NASA GIBS, tägl.) | 250 m – 1 km/px | unsichtbar |

Ein Fußballfeld (105 × 68 m) sind bei Sentinel-2 etwa **10 × 7 Pixel**. Gebäudeerkennung braucht sub-metrische Auflösung, und die ist kommerziell und teuer.

**Konsequenz für den Agent:** Er muss die Bodenauflösung bei jeder Aussage mitführen und Aussagen ablehnen, die unterhalb seiner Auflösung liegen. Das ist ein Feature, kein Mangel — ein Agent, der bei 10 m/px "neues Gebäude" behauptet, halluziniert.

**Was bei 10 m/px realistisch geht:**
Abholzung · Überschwemmungsflächen · große Baustellen und Erdbewegungen · Tagebau und Steinbrüche · Solarparks · landwirtschaftliche Veränderungen · Brandflächen · Schneebedeckung · Algenblüten · Gewässerstände · neue Straßentrassen.

**Was nicht geht:**
Einzelne Gebäude · Fahrzeuge · Personen · Objekte kleiner ~30 m · "Live"-Bilder · Bilder auf Zuruf für einen beliebigen Zeitpunkt.

## A.2 Der zweite Denkfehler: "aktuelles Satellitenbild"

Sentinel-2 hat eine Wiederholrate von etwa 3–5 Tagen. <cite index="3-1">Sentinel-2 liefert bei 10 m Auflösung eine Wiederkehrzeit von 3–5 Tagen</cite>. Dazu kommt Bewölkung: in Süddeutschland ist ein erheblicher Teil der Aufnahmen unbrauchbar.

"Aktuell" heißt in der Praxis: **das jüngste Bild unter einem Wolken-Schwellwert innerhalb eines Suchfensters**. Der Agent muss das so formulieren und nie den Eindruck von Echtzeit erwecken.

Ausnahme: NASA GIBS liefert tägliche MODIS/VIIRS-Übersichten <cite index="24-1">in Nahe-Echtzeit, etwa drei Stunden nach dem Überflug</cite> — aber bei 250 m bis 1 km Auflösung. Gut für Wetter, Rauch, Brände, Sturmsysteme. Nutzlos für "zeig mir meine Straße".

## A.3 Datenquellen

> **Stand prüfen.** Endpunkte, Auth-Verfahren und Kontingente ändern sich. Vor dem Schreiben von Integrationscode die aktuelle offizielle Doku öffnen. Keine Endpunkt-URLs aus dem Gedächtnis erfinden.

| Zweck | Quelle | Zugang | Anmerkung |
|---|---|---|---|
| Sentinel-1/2/3/5P Archiv + neue Aufnahmen | Copernicus Data Space Ecosystem (`dataspace.copernicus.eu`) | Registrierung, OAuth-Token; kostenlos mit Kontingent | <cite index="7-1">Alle Funktionen sind für allgemeine Nutzer kostenlos mit vordefinierten Kontingenten; für große Download-/Verarbeitungsmengen gelten kommerzielle Bedingungen</cite> |
| Katalogsuche (Szenen finden, Wolken filtern) | CDSE-Katalog | mehrere REST-Protokolle, u. a. STAC und OData | <cite index="9-1">Der Katalog lässt sich über vier verschiedene REST-Protokolle abfragen; Filter erlauben es, stark bewölkte Tage auszuschließen</cite> |
| Verarbeitung ohne Download | Sentinel Hub / openEO im CDSE | OAuth-Client | Für Web-Anzeige besser als GeoTIFFs von 700 MB herunterzuladen |
| Tägliche Übersichtsbilder, Nahe-Echtzeit | NASA GIBS (`gibs.earthdata.nasa.gov`) | **kein Key**, WMTS/WMS/TWMS | <cite index="22-1">GIBS bietet Zugang über WMTS, WMS, TWMS und GDAL; viele Produkte sind 3–5 Stunden nach der Beobachtung verfügbar</cite> |
| Aktive Brände | NASA FIRMS | <cite index="26-1">kostenloser MAP_KEY erforderlich</cite> | WMS-Layer für VIIRS/MODIS |
| Bahndaten (TLE/GP) | CelesTrak | öffentlich | Nutzungsregeln beachten, nicht im Sekundentakt pollen |
| Überflugberechnung | Python `skyfield` (nutzt `sgp4`) | Bibliothek | <cite index="17-1">`find_events(topos, t0, t1, altitude_degrees)` liefert Aufgangs-, Kulminations- und Untergangszeiten für Überflüge über einem Standort</cite> |
| Wetter/Bewölkung | Open-Meteo o. ä. | prüfen | Für die Frage "lohnt sich morgen ein Bild?" |

**Bahnmechanik nicht selbst rechnen.** <cite index="15-1">TLE-Daten sind zum Epochenzeitpunkt auf etwa einen Kilometer genau und verlieren danach schnell an Genauigkeit</cite> — deshalb TLEs regelmäßig neu holen und mit `skyfield` propagieren, nicht mit selbstgeschriebenen Kepler-Formeln.

**Attribution:** Copernicus-Daten haben Attributionspflichten in den Nutzungsbedingungen. Die konkrete geforderte Formulierung nachschlagen und im UI unter jedem Bild anzeigen.

## A.4 Provider-Interface

```python
@dataclass
class Scene:
    scene_id: str
    provider: str
    sensor: str                 # "Sentinel-2 MSI L2A"
    acquired_at: datetime       # UTC, Aufnahmezeit — nicht Abrufzeit
    cloud_cover_pct: float
    resolution_m: float         # Meter pro Pixel — Pflichtfeld
    bbox: tuple[float,float,float,float]
    preview_url: str | None
    attribution: str            # Pflichtfeld, nicht optional
    license: str


class SatelliteProvider(Protocol):
    name: str
    async def search(self, bbox, start: datetime, end: datetime,
                     max_cloud_pct: float = 20.0) -> list[Scene]: ...
    async def render(self, scene_id: str, bbox, bands: str = "TRUE_COLOR",
                     width: int = 1024) -> bytes: ...
    async def metadata(self, scene_id: str) -> dict: ...
```

Zwei Details, die in v1 fehlen und in der Praxis alles entscheiden:

- `resolution_m` und `attribution` sind **Pflichtfelder**. Eine `Scene` ohne beides ist ungültig und wird verworfen.
- `search` filtert nach Wolken **serverseitig**. Erst 200 Szenen holen und dann lokal filtern ist bei Kontingenten die falsche Reihenfolge.

## A.5 Change Detection — ehrlich implementiert

Nicht: "zwei Bilder ans Vision-Modell, frag was sich geändert hat." Das produziert selbstbewussten Unsinn.

Stattdessen:

1. **Geometrisch abgleichen.** Beide Szenen auf dieselbe Bounding Box und dasselbe Raster bringen. Ohne Ko-Registrierung vergleichst du Versatz, nicht Veränderung.
2. **Vergleichbarkeit prüfen.** Ähnlicher Sonnenstand, ähnliche Jahreszeit, beide unter dem Wolken-Schwellwert. Sommer vs. Winter ist kein Change, das ist Vegetation. Ist die Bedingung verletzt: melden, nicht rechnen.
3. **Numerisch rechnen, bevor ein Modell schaut.** NDVI-Differenz (Vegetation), NDWI (Wasser), NBR (Brandflächen) — das sind einfache Bandarithmetiken und liefern reproduzierbare Zahlen statt Sprachmodell-Meinungen.
4. **Erst dann das Vision-Modell**, und zwar mit hartem Kontext im Prompt: Sensor, m/px, beide Aufnahmedaten, Wolkenanteil, Bildausschnitt in km, und der expliziten Anweisung, keine Objekte unterhalb von etwa 3× der Bodenauflösung zu benennen.
5. **Ausgabeformat erzwingen:**

```
BEOBACHTET
  NDVI-Rückgang > 0.3 auf ca. 4,2 ha im nordwestlichen Bildviertel.
INTERPRETATION
  Vegetationsverlust. Kahlschlag, Ernte oder Trockenschaden — nicht unterscheidbar
  auf Basis dieser beiden Aufnahmen.
KONFIDENZ  mittel
GRUNDLAGE  Sentinel-2 L2A, 10 m/px, 2026-04-12 (2 % Wolken) vs. 2026-07-30 (4 % Wolken)
GRENZE     Objekte unter 30 m sind bei dieser Auflösung nicht beurteilbar.
```

Die Zeile `GRENZE` ist Pflicht. Sie ist der Unterschied zwischen einem Werkzeug und einem Bullshit-Generator.

## A.6 Grenzen des Agents

Der Satellite Agent hat `max_permission = READ`. Er darf ausschließlich öffentliche und autorisierte Datenquellen im Rahmen ihrer Nutzungsbedingungen abfragen.

Zusätzlich, und das fehlt im alten Prompt komplett: **Der Agent baut kein Überwachungswerkzeug.** Wiederholte, terminierte Beobachtung eines einzelnen privaten Grundstücks oder einer bestimmten Person ist kein Anwendungsfall, auch wenn die Daten öffentlich sind. Umweltmonitoring, Katastrophenlage, Landnutzung, Bildung: ja. Nachbarn beobachten: nein. Der Agent lehnt solche Anfragen ab und erklärt kurz warum.

Rate-Limits sind kein Vorschlag. Kontingent-Verbrauch wird pro Provider geloggt und im Dashboard angezeigt.

---

# ANHANG B — Was ich gestrichen habe und warum

| Gestrichen | Grund |
|---|---|
| **Computer Agent** (Programme öffnen, UI steuern) | Größte Angriffsfläche des ganzen Systems bei geringstem Nutzen. Ein LLM mit Tastatur- und Mauszugriff auf deinem Rechner ist ein Fehlklick von einem sehr schlechten Tag entfernt. Wenn du es wirklich brauchst: eigenes Projekt, eigene VM, nicht hier. |
| **Postgres + pgvector ab Tag 1** | Zwei zusätzliche Systeme, bevor überhaupt Daten existieren. SQLite mit FTS5 trägt dich problemlos bis in die Tausende Einträge. Migration ist später ein Nachmittag. |
| **Next.js + React + TypeScript ab Tag 1** | Ein Build-System für ein Chatfenster. Kostet dich einen halben Tag npm-Fehlersuche, bevor die erste Nachricht durchgeht. |
| **Docker ab Tag 1** | Docker verpackt fertige Software. Es macht unfertige Software nur langsamer zu debuggen. |
| **Wake Word in v1** | Dauerhorchen, Falschauslösungen, Mikrofonrechte, Energieverbrauch. Push-to-Talk liefert 90 % des Nutzens für 5 % des Aufwands. |
| **10-Schritte-Beispielplan im Planner-Prompt** | Solche Beispiele bringen Modelle dazu, jede Frage in zehn Schritte zu zerlegen. "Wie spät ist es?" wird dann zu einem Rechercheprojekt. Der Planner braucht die gegenteilige Anweisung. |
| **"Model Router" mit Auto-Auswahl** | Erst brauchst du Messwerte, welches Modell für welche Aufgabe besser ist. Bis dahin ist der Router ein `dict` in der Config. Trag echte Modell-IDs ein, rate keine. |

**Was ich hinzugefügt habe, weil es fehlte:** Budget und Kill-Switch (§0.5) · JSON-Robustheit und Retry-Grenzen (§0.6) · API-Token auch lokal (§0.4) · Definition of Done pro Phase · das Verbot, den API-Key ins Frontend zu legen · Bodenauflösung als Pflichtfeld im Satellite Agent · Non-Goals.

---

# ANHANG C — Anti-Patterns, die du dem Modell verbieten musst

Hänge das bei Bedarf an einen Phasen-Block an:

```
VERBOTENE ANTWORTMUSTER:

- "Hier ist die vollständige Implementierung" für Code, den du nicht ausgeführt hast.
- Dateien mit ausschließlich Klassenrümpfen und `pass`.
- Mehr als eine Ebene Ordnerstruktur ohne eine einzige lauffähige Datei darin.
- Endpunkte, Parameter oder Modell-IDs, die du nicht in einer Doku gesehen hast.
- "Du musst nur noch deinen API-Key eintragen" — ohne zu sagen, wo man ihn bekommt
  und was er kostet.
- Eine Zusammenfassung am Ende, die mehr behauptet als der Code kann.
- Fortfahren mit Phase N+1, wenn die Definition of Done von Phase N nicht erfüllt ist.
- Stillschweigendes Erhöhen von Budgets, Timeouts oder Retry-Grenzen, um einen
  Testfall grün zu bekommen.
```

---

# ANHANG D — Ehrliche Einschätzung des Umfangs

Damit du weißt, worauf du dich einlässt:

| Phase | Realistischer Aufwand für dich mit Claude als Coding-Engine |
|---|---|
| 1 Skeleton | 1 Abend |
| 2 Tools | 1–2 Abende |
| 3 Memory | 2 Abende |
| 4 Planner + Agent | 3–4 Abende, hier wird es zum ersten Mal richtig fummelig |
| 5 Permissions | 1 Abend |
| 6 Hermes | 3–5 Abende, viel Prompt-Tuning |
| 7 Dashboard | 2–3 Abende |
| 8 Satellite | 3–5 Abende, davon die Hälfte Doku lesen |
| 9 Voice | 1–2 Abende (Web Speech API) |
| 10 Härten | 2–3 Abende |

Summe: grob 20–30 Abende, verteilt über Monate — bei laufendem Weiterarbeiten, nicht bei Neustart nach drei Wochen Pause.

**Laufende Kosten:** jeder Hermes-Task mit Recherche kostet echtes Geld. Trag die Preise deines Anbieters in `.env` ein und setz `max_cost_eur` bewusst. Ein Bug in einer Retry-Schleife kann über Nacht mehr verbrauchen, als du erwartest — deshalb steht der Kill-Switch in §0.5 und nicht in Phase 10.

**Der ehrlichste Rat in diesem Dokument:** Wenn nach Phase 3 die Luft raus ist, hast du trotzdem etwas Fertiges — einen Chat-Assistenten mit Tools und Gedächtnis, den du täglich benutzen kannst. Das ist mehr wert als ein zu 60 % gebautes Hermes-System. Phase 1–3 sind so geschnitten, dass sie allein einen Sinn ergeben.
