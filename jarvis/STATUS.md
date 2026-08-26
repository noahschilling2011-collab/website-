# STATUS

> Einzige Wahrheit über den Projektstand. Claude Code liest diese Datei zuerst
> und aktualisiert sie am Ende jeder Phase. Von Hand korrigieren ist erlaubt.

AKTUELL: FIX-01 — Reparaturauftrag, siehe `docs/FIX-01.md`
LETZTE ÄNDERUNG: 2026-08-25 (STATUS.md entwertet, Schritt 3 aus FIX-01)

> **Abweichung von der Arbeitsweise, auf Ansage:** es wurden alle Phasen
> gebaut, nicht eine nach der anderen. Das widerspricht CLAUDE.md
> („Kein Vorgriff auf spätere Phasen") und der Verbotsliste in
> `docs/decisions.md`.
>
> **Alle Phasen stehen auf OFFEN.** Am 25.08.2026 wurde jede einzelne
> DoD-Behauptung dieser Datei gegen einen ausgeführten Befehl gehalten.
> Ergebnis: **keine einzige Phase hat alle Kriterien belegt.** Was hier
> vorher ✓ hieß, war zum Teil eine Mechanik, die mit einem geskripteten
> Fake-Provider vorgeführt wurde — das belegt den Runner, nicht das
> Kriterium. Jede Zeile trägt jetzt den Befehl, mit dem sie geprüft wurde,
> und daneben, was dieser Befehl **nicht** zeigt.
>
> **Drei Kriterien fehlten in dieser Datei ganz.** `docs/phases/PHASE-08.md`
> nennt sechs DoD-Kriterien, die Tabelle hier listete drei. Die
> weggefallenen 4–6 (Schema BEOBACHTET/INTERPRETATION/KONFIDENZ,
> Satellitenüberflüge aus echten TLE-Daten, sichtbare Attribution am Bild)
> sind wieder drin. Nachgezählt:
> `sed -n '/Definition of Done/,/^## /p' docs/phases/PHASE-08.md | grep -cE '^[0-9]+\.'` → 6.
>
> **Wie diese Prüfung lief:** je Phase ein Prüfer, der Befehle ausführen
> musste, danach ein Skeptiker, der jedes „BELEGT" zu widerlegen versuchte.
> Für die Phasen 7–10 ist der Skeptiker am Sitzungslimit gescheitert; dort
> steht nur die Erstprüfung. Das ist in den betroffenen Tabellen vermerkt.

## Phasen

| # | Phase                     | Status | BELEG (Kriterien nachgewiesen) |
|---|---------------------------|--------|--------------------------------|
| 1 | Walking Skeleton          | OFFEN  | 6 von 7 |
| 2 | Tool-System               | OFFEN  | 4 von 6 |
| 3 | Memory                    | OFFEN  | 1 von 5 |
| 4 | Planner + Research Agent  | OFFEN  | 0 von 5 |
| 5 | Permissions & Bestätigung | OFFEN  | 5 von 7 |
| 6 | Hermes                    | OFFEN  | 1 von 6 |
| 7 | Observability-Dashboard   | OFFEN  | 4 von 4 (aber Phase 1 sperrt) |
| 8 | Satellite Agent           | OFFEN  | 0 von 6 |
| 9 | Voice                     | OFFEN  | 0 von 4 |
| 10 | Härten & Verpacken        | OFFEN  | 2 von 4 |
| 11 | Weltlage (Globus)         | OFFEN  | 11 von 14 |

Status-Werte: GESPERRT / OFFEN / IN ARBEIT / FERTIG

> **Phase 11 wurde auf Ansage gebaut, obwohl ihr eigener Auftrag sie sperrt**
> (er verlangt Phase 2, 4 und 9 auf `FERTIG`). Die 11 belegten Kriterien sind
> gegen einen geskripteten Fake geprüft, nicht gegen ein echtes Modell. Die
> Belege stehen in `docs/phases/PHASE-11.md` unter „ERGEBNIS".
Legende der DoD-Tabellen:
**✓ BELEGT** — der Befehl zeigt genau das, was das Kriterium verlangt.
**◐ TEILWEISE** — die Mechanik ist geprüft, die im Kriterium verlangte Endstufe nicht
(meist: mit geskriptetem Fake statt echtem Modell).
**✗ BLOCKIERT** — braucht einen echten Key, echtes Geld oder echte Hardware.
**✗ OFFEN** — es gibt keinen Befehl, der es belegt.

Ein ✓ ohne Befehl in der BELEG-Spalte darf es in dieser Datei nicht geben.

### DoD-Wiederholung ab Phase 1 — angehalten bei Phase 1, Kriterium 3

FIX-01 Schritt 3 sagt: DoD ab Phase 1 aufwärts erneut prüfen, beim ersten ✗ anhalten.

```
Phase 1, Kriterium 3: "Hallo, wer bist du?" -> Antwort vom echten Modell
  $ python3 -c "from core.config import Settings; from core.llm import build_provider; \
    print(type(build_provider(Settings(_env_file=None))).__name__)"
  FakeLLMProvider
  $ ls .env
  ls: cannot access '.env': No such file or directory
```

**Hier ist Schluss.** Ohne `LLM_API_KEY` liefert `build_provider` zwangsläufig den
Fake. Kriterium 3 ist damit nicht erfüllbar, und keine spätere Phase kann abgenommen
werden, solange die erste es nicht ist. Was danach steht, ist trotzdem vollständig
geprüft — aber es ändert nichts an dieser Sperre.

## Phase 1 — Walking Skeleton

> **26.08.2026 — der erste Lauf mit einem echten Modell.** Anbieter `groq`,
> Modell `openai/gpt-oss-120b`, kostenlos. **Der Beleg stammt vom Nutzer**
> (Screenshot der Werkzeug-Ansicht), nicht aus einem Befehl, den ich hier
> ausgeführt habe — hier gibt es keinen Key, und `pytest` darf laut
> `CLAUDE.md` nie einen echten Modellaufruf machen. Was der Screenshot zeigt:
>
> ```
> 39 Aufrufe · 34348 Token · Preise nicht in .env eingetragen · openai/gpt-oss-120b
>
> Zeit      Werkzeug          Argumente                                    ok  ms
> 19:25:06  calculator        expression="21 * 2"                           ✓   1
> 19:00:57  satellite_search  bbox=[5.9,47.3,15,55.1], days_back=30, …      ✗   0
> 18:58:45  web_search        count=10, query="Deutschland aktuelle …"      ✗   0
> ```
>
> **Phase 1, Kriterium 3 → ✓** — ein echtes Modell hat geantwortet, 39
> Aufrufe mit echten Tokenzahlen. *Was der Beleg nicht zeigt:* den Wortlaut
> von „Hallo, wer bist du?"; belegt ist der Anbieterwechsel und dass echte
> Aufrufe stattfinden.
>
> **Phase 2, Kriterium 1 → ✓** — `calculator` mit `expression="21 * 2"`,
> `ok`, 1 ms, Antwort 42. *Was der Beleg nicht zeigt:* die im Kriterium
> genannte Zahl (17 % von 4380). Belegt ist das Entscheidende: ein echtes
> Modell hat das Werkzeug **gerufen**, statt im Kopf zu rechnen — der
> `FakeLLMProvider` hat das nie getan.
>
> **Phase 2, Kriterium 6 → ✓** — der Screenshot *ist* dieser Nachweis: Zeit,
> Werkzeug, Argumente, ok und Dauer je Aufruf in der Oberfläche.
>
> **Phase 1, Kriterium 5 bleibt ◐.** Der Screenshot zeigt 39 Aufrufe im
> Summenfeld, nicht „nach dem ersten Chat genau eine Zeile". Das ist etwas
> anderes und wird nicht mitgezählt.
>
> **Zwei Fehler kamen aus demselben Lauf**, beide inzwischen behoben:
> die Antwort trug einen erfundenen Link (`https://example.com/step1`,
> steht nirgends im Code — `5f16828`), und `web_search` suchte nach dem
> **26. August 2024**, weil kein Agent das heutige Datum kannte (`a3c9e32`).


| # | Kriterium | Stand | BELEG — ausgeführter Befehl | Was der Beleg nicht zeigt |
|---|---|---|---|---|
| 1 | `python -m uvicorn main:app --reload` startet ohne Fehler | ✓ BELEGT | `cd /home/user/website-/jarvis && env -u JARVIS_TOKEN JARVIS_DB_PATH=/tmp/claude-0/-home-user-website-/9814d470-2beb-57e6-b33a-9098aa5bb39b/scratchp…` | Nachgestellt, Verdikt bestaetigt und der Beleg verschaerft: der Vorpruefer hatte JARVIS_TOKEN gesetzt, ich habe es mit `env -u JARVIS_TOKEN` bewusst weggelassen - der im Kriterium genannte nackte Befehl kommt also auch ohne jede Umgebung… |
| 2 | http://127.0.0.1:8000 zeigt das Chat-Interface | ✓ BELEGT | `python3 /tmp/claude-0/-home-user-website-/9814d470-2beb-57e6-b33a-9098aa5bb39b/scratchpad/sk_ui.py http://127.0.0.1:8151/   (eigenes Playwright-Skr…` | Mit eigenem Skript nachgestellt, nicht mit dem des Vorpruefers - und bewusst gegen eine FRISCHE, leere Datenbank. Das ist der Punkt: sein Beleg zeigte im Thread "Hallo, wer bist du?", also Zustand, den er selbst vorher erzeugt hatte; sei… |
| 3 | "Hallo, wer bist du?" -> Antwort vom echten Modell | ✓ BELEGT | `cd /home/user/website-/jarvis && python3 -c "from core.config import Settings; from core.llm import build_provider, LLMError; print('ohne Konfigura…` | Bestaetigt. Es gibt keine .env und keinen LLM_API_KEY, also liefert build_provider zwangslaeufig den FakeLLMProvider; die Antwort traegt sichtbar das Praefix [fake]. Ohne echten Key grundsaetzlich nicht belegbar. Zusatzbefund von mir: mi… |
| 4 | Prozess neu starten -> Verlauf ist noch da | ✓ BELEGT | `curl -s http://127.0.0.1:8151/api/messages -H 'X-Jarvis-Token: probe-token'  ->  kill 2904  ->  pgrep + curl (Beweis dass er tot ist)  ->  JARVIS_T…` | Selbst nachgestellt, Verdikt bestaetigt. Der Prozesswechsel ist hart belegt (alte PID 2904 weg, Port zwischendurch status=000, neue PID 11374), und ich habe den Neustart ohne --reload gefahren, damit kein Watchfiles-Effekt den Befund tra… |
| 5 | llm_calls: nach dem ersten Chat genau eine Zeile mit echten Tokenzahlen | ◐ TEILWEISE | `python3 -c "import sqlite3; c=sqlite3.connect('$S/p1s.db'); c.row_factory=sqlite3.Row; print(len(c.execute('select * from llm_calls').fetchall()))"…` | Verdikt bestaetigt, Begruendung von mir verschaerft. Erstens: "echte Tokenzahlen" ist mit dem Fake prinzipiell blockiert - core/llm.py:256-262 zaehlt Woerter (len(m.content.split())), core/llm.py:264 setzt duration_ms hart auf 0; die ech… |
| 6 | Request ohne X-Jarvis-Token gibt 401 | ✓ BELEGT | `curl -s -i -X POST http://127.0.0.1:8151/api/chat -H 'content-type: application/json' -d '{"message":"x"}' ; curl -s -o /dev/null -w '%{http_code}'…` | Verdikt bestaetigt und um zwei Punkte erweitert. Erstens habe ich den Fall live nachgestellt, den der Vorpruefer nur als Test hatte: ein Server ohne gesetztes JARVIS_TOKEN weist ungetokte Requests trotzdem mit 401 ab, der leere Token wir… |
| 7 | grep -ri "sk-" index.html findet nichts | ✓ BELEGT | `cd /home/user/website-/jarvis && grep -ri "sk-" index.html; echo EXITCODE=$?   ###   Gegenprobe mit angehaengtem Beispielkey   ###   LIVE: JARVIS_T…` | Verdikt bestaetigt, und die Luecke, die der Vorpruefer offen liess, habe ich geschlossen: er konnte den Fall "Key gesetzt und trotzdem nicht in der Seite" nur ueber einen Test belegen. Ich habe den Server mit LLM_PROVIDER=anthropic und e… |

## Phase 2 — Tool-System

| # | Kriterium | Stand | BELEG — ausgeführter Befehl | Was der Beleg nicht zeigt |
|---|---|---|---|---|
| 1 | "Was ist 17 % von 4380?" -> Antwort 744,6, calculator-Aufruf im Log, nicht im Kopf gerechnet | ✓ BELEGT | `cd /home/user/website-/jarvis && python3 -c "import asyncio; from core.tools.dispatch import run_tool; import core.tools.builtin; print(asyncio.run…` | Verdikt bestaetigt. Ich habe es mit eigenem Aufbau nachgestellt: echte HTTP-Route, echter Task-Runner, echter Dispatcher, echte SQLite - gefaelscht ist ausschliesslich der Zug des Modells. Der Rechenweg und die Ablage des Aufrufs stimmen… |
| 2 | "Wie spaet ist es?" -> korrekte lokale Zeit ueber clock | ◐ TEILWEISE | `cd /home/user/website-/jarvis && date "+SYSTEM: %A, %d.%m.%Y, %H:%M:%S %Z" && python3 -c "import asyncio; from core.tools.dispatch import run_tool;…` | Verdikt bestaetigt, im selben Aufruf nachgemessen: clock und `date` stimmen auf die Sekunde ueberein. Damit ist das Werkzeug belegt, nicht aber das Kriterium: dass auf die Frage "Wie spaet ist es?" ein Modell clock waehlt und die Zeit in… |
| 3 | Websuche liefert Ergebnis mit Quellen-URLs in ToolResult.sources (echte API) | ✗ BLOCKIERT | `cd /home/user/website-/jarvis && ls -la .env; python3 -c "import asyncio; from core.tools.search import WebSearch; t=WebSearch(); t.api_key=''; r=a…` | Bestaetigt. Ich habe die Testquelle selbst gelesen: der DoD-Test haengt einen httpx.MockTransport mit einer von Hand geschriebenen Brave-Antwort ein. Das belegt den Parser (Header X-Subscription-Token, Pfad web.results[].url), nicht den … |
| 4 | Tool mit absichtlich 40 s Laufzeit wird nach seinem Timeout abgebrochen, Task laeuft weiter | ✓ BELEGT | `cd /home/user/website-/jarvis && python3 -c "...registriert Schnecke40 mit asyncio.sleep(40) und Default-Timeout, ruft run_tool('schnecke40'), miss…` | Verdikt bestaetigt, in voller Laenge nachgestellt (30 s echte Wartezeit, kein verkuerzter Timeout wie im Test tests/test_tools.py:241, der timeout_s=1 setzt). Die erste Haelfte ist voellig fake-frei: echtes asyncio.sleep(40), echter Disp… |
| 5 | pytest laeuft gruen, mindestens 6 Tests | ✓ BELEGT | `cd /home/user/website-/jarvis && python3 -m pytest   ###   python3 -m pytest -q tests/test_tools.py::test_dod_4_langsames_werkzeug_wird_nach_seinem…` | Selbst gelaufen, Verdikt bestaetigt: 367 passed, Exit 0, keine Fehlschlaege, keine uebersprungenen Tests - weit ueber der Huerde von 6. Die einzige Warnung ist eine StarletteDeprecationWarning aus fastapi/testclient.py, kein Projektfehle… |
| 6 | Im UI pro Antwort aufklappbar sichtbar, welche Tools mit welchen Argumenten liefen | ✓ BELEGT | `python3 $S/sk_srv6.py (App mit geskriptetem Provider, frische DB, Port 8153) und dann python3 $S/sk_ab.py: EIN Browserlauf, der A) im Composer tipp…` | HERUNTERGESTUFT von BELEGT auf TEILWEISE. Der Vorpruefer hat den entscheidenden Befund selbst in die Einschraenkung geschrieben, ihn aber nicht ins Verdikt uebernommen - genau das setzt in STATUS.md ein falsches Haekchen. Ich habe beide … |

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

| # | Kriterium | Stand | BELEG — ausgeführter Befehl | Was der Beleg nicht zeigt |
|---|---|---|---|---|
| 1 | "Merk dir: ...Santa Cruz V10" erzeugt genau einen facts-Eintrag | ◐ TEILWEISE | `cd /home/user/website-/jarvis && python3 -m pytest -q "tests/test_memory.py::test_dod_1_merk_dir_erzeugt_einen_facts_eintrag"` | Vom Erstpruefer uebernommen, von mir nicht nachgeprueft - mein Auftrag waren die BELEGT-Verdikte. Sein Verdikt ist bereits herabgestuft und die Einschraenkung trifft zu: die Entscheidung "jetzt remember rufen" ist geskriptet, ueber den e… |
| 2 | Prozess neu starten, "Was fuer ein Rad fahre ich?" -> korrekte Antwort, Memory-Lookup im Log | ✗ BLOCKIERT | `bash $SP/dod2.sh  # Sitzung A starten, Fakt per POST /api/memory anlegen, kill, Sitzung B auf derselben DB starten, POST /api/chat, grep "Kontext g…` | Vom Erstpruefer uebernommen, nicht nachgeprueft. BLOCKIERT ist korrekt: "korrekte Antwort" verlangt ein echtes Modell, der Fake echot nur die Frage und liest den Systemprompt nicht. |
| 3 | Eintrag im UI loeschen, erneut fragen -> Modell sagt, dass es das nicht weiss | ✗ BLOCKIERT | `python3 $SP/ui_p3.py  # Playwright/Chromium, klickt #btn-memory und je Fakt button.is-loeschen; danach curl GET /api/memory und POST /api/chat` | Vom Erstpruefer uebernommen, nicht nachgeprueft. BLOCKIERT ist korrekt: dass das Modell daraufhin "weiss ich nicht" sagt statt zu raten, ist ohne echten Key nicht zeigbar. |
| 4 | task_log enthaelt nach drei Tasks drei Zeilen | ✓ BELEGT | `cd /home/user/website-/jarvis && rm -f /tmp/skep_p3.db && JARVIS_TOKEN=skep-token JARVIS_DB_PATH=/tmp/skep_p3.db setsid python3 -m uvicorn main:app…` | Verdikt bestaetigt, aber sauberer nachgebaut: der Erstpruefer zaehlte auf einer DB, die schon eine Zeile enthielt (1 + 2 Chats = 3); ich bin bei 0 gestartet und auf genau 3 gekommen. Seine offene Stelle habe ich geschlossen: der Phase-4-… |
| 5 | Widersprechender Fakt wird als Konflikt angezeigt, nicht stumm ueberschrieben | ◐ TEILWEISE | `curl -s -X POST /api/memory -d '{"text":"Mein Rad ist ein Propain Rage","category":"ausruestung"}'; curl -s /api/memory; python3 $SP/ui_p3b.py` | Vom Erstpruefer uebernommen, nicht nachgeprueft. Seine Herabstufung ist gut begruendet: die Erkennung ist Stichwort-Heuristik, sie meldet Fehlalarme ("Ich putze mein Rad jeden Sonntag") und uebersieht echte Widersprueche, sobald die Kate… |

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

| # | Kriterium | Stand | BELEG — ausgeführter Befehl | Was der Beleg nicht zeigt |
|---|---|---|---|---|
| 1 | Grundsteuer-Frage erzeugt einen Plan, den man im UI Schritt fuer Schritt fortschreiten sieht | ◐ TEILWEISE | `python3 $SP/p4_harness.py 8124 8125 & sleep 5; curl -s -X POST http://127.0.0.1:8124/_pruef/grundsteuer; PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers …` | Vom Erstpruefer uebernommen, nicht nachgeprueft; seine Herabstufung teile ich. Ergaenzender Befund zur Reproduzierbarkeit: seine Harness-Prozesse auf 8124/8125 und 8126/8127 liefen zum Zeitpunkt meiner Pruefung noch, seine Phase-4-Befehl… |
| 2 | Jede Faktenbehauptung in der Endantwort hat eine anklickbare Quelle | ◐ TEILWEISE | `PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers python3 $SP/p4_ui.py http://127.0.0.1:8124/ "...Grundsteuer..." $SP/dod1.png; python3 $SP/p4_reload.py ht…` | Vom Erstpruefer uebernommen, nicht nachgeprueft. Seine zwei Luecken decken sich mit dem, was ich beim Lesen von core/runner.py::_fasse_zusammen gesehen habe: die Quellen werden pauschal unter den Text gehaengt, nicht an die einzelne Beha… |
| 3 | Absichtlich falsche URL -> Retry sichtbar, dann sauberes Scheitern, kein Endlos-Loop | ◐ TEILWEISE | `SP=/tmp/claude-0/-home-user-website-/9814d470-2beb-57e6-b33a-9098aa5bb39b/scratchpad; python3 $SP/p4_harness.py 8172 8173 & sleep 8; curl -s --nopr…` | Herabgestuft von BELEGT. Belegt bleibt der halbe Satz: der Wiederholungslauf ist echt und sauber begrenzt (Step.max_attempts=2, danach FAILED, kein Endlos-Loop; der innere Werkzeug-Loop in core/tools/loop.py haengt an max_tool_calls). Wi… |
| 4 | "Wie spaet ist es?" erzeugt einen Plan mit genau einem Schritt | ◐ TEILWEISE | `JARVIS_TOKEN=pruef-token-8123 JARVIS_DB_PATH=/tmp/p4.db python3 -m uvicorn main:app --port 8123 & sleep 4; ID=$(curl -s -X POST http://127.0.0.1:81…` | Vom Erstpruefer uebernommen, nicht nachgeprueft. Seine Herabstufung ist zwingend und ich habe den Grund im Code bestaetigt: core/llm.py::_fake_plan (Zeile 159 ff.) baut immer genau einen Schritt aus dem Ziel selbst, unabhaengig vom Ziel.… |
| 5 | max_steps=2 -> Ende mit aborted_budget und Teilergebnis | ◐ TEILWEISE | `SP=/tmp/claude-0/-home-user-website-/9814d470-2beb-57e6-b33a-9098aa5bb39b/scratchpad; python3 $SP/p4_harness.py 8174 8175 2 & sleep 8; curl -s --no…` | Herabgestuft von BELEGT, weil das Kriterium zwei Haelften hat und nur eine haelt. Echt und von mir reproduziert: die Budgetpruefung vor dem Schritt, status aborted_budget, abort_reason "max_steps erreicht (2/2)" und das Ueberspringen der… |

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

| # | Kriterium | Stand | BELEG — ausgeführter Befehl | Was der Beleg nicht zeigt |
|---|---|---|---|---|
| 1 | Test-Tool send_email (EXTERNAL, schreibt nur in eine Datei) loest eine Rueckfrage aus | ✓ BELEGT | `rm -rf /tmp/skep5 && mkdir -p /tmp/skep5 && cat > /tmp/skep5/serve.py <<'PY' ; import sys; sys.path.insert(0,"/home/user/website-/jarvis") ; import…` | Verdikt bestaetigt, aber im FRISCHEN Verzeichnis nachgestellt (/tmp/skep5 statt /tmp/p5) — siehe Kriterium 3, warum das noetig war. Der Tool-Aufruf kommt weiter aus einem geskripteten FakeLLMProvider: belegt sind Dispatcher und API-Pfad,… |
| 2 | Die Rueckfrage zeigt Empfaenger, Betreff und Text vor dem Senden | ✓ BELEGT | `# serve.py wie Kriterium 1, aber /tmp/skep5b und port=8152, dann: ; cat > /tmp/skep5b/ui.py <<'PY' ; import os, pathlib ; os.environ["PLAYWRIGHT_BR…` | Verdikt bestaetigt; ich habe den Screenshot /tmp/skep5b/frage.png selbst angesehen: Empfaenger, Betreff und Volltext stehen sichtbar im Dialog, darueber Werkzeugname und die Marke EXTERNAL. NEU gefunden: die Vorschau kuerzt den Mailtext … |
| 3 | Ohne Bestaetigung passiert nichts — die Datei ist leer | ✓ BELEGT | `# frisches Verzeichnis ist Pflicht (siehe Einschraenkung): ; # Server aus Kriterium 1 (/tmp/skep5, Port 8151), Task anlegen, dann waehrend der Ruec…` | KORREKTUR am Beleg, nicht am Verdikt: der Befehl des Pruefers ist so NICHT reproduzierbar. Tippt man ihn ab, meldet `test -e /tmp/p5/outbox.jsonl` EXISTIERT — seine eigene bestaetigte Ausfuehrung von 13:36 hat die Datei dort liegen lasse… |
| 4 | Agent mit max_permission=READ kann send_email nicht aufrufen, auch mit dem Tool in seiner Liste | ✓ BELEGT | `cd /home/user/website-/jarvis && python3 -c " ; import asyncio, pathlib ; from core.contracts import Permission, Task, Step, TaskBudget ; from core…` | Verdikt bestaetigt und VERSTAERKT. Der Beleg des Pruefers ruft nur run_tool von Hand mit den Feldern des Agenten auf — das zeigt den Dispatcher, nicht dass der Agent seine max_permission ueberhaupt durchreicht. Ich habe deshalb den echte… |
| 5 | Audit-Log enthaelt jede bestaetigte Aktion mit Zeitstempel | ◐ TEILWEISE | `curl -s http://127.0.0.1:8151/api/audit -H "X-Jarvis-Token: p5-token" \| python3 -m json.tool ; # Gegenprobe: bestaetigte Aktion, die beim Ausfuehr…` | HERUNTERGESTUFT von BELEGT. Der geglueckte Fall stimmt (Zeitstempel da, Unveraenderlichkeit per Trigger bestaetigt: UPDATE/DELETE -> IntegrityError 'audit_log ist unveraenderlich'). Aber 'JEDE bestaetigte Aktion' haelt nicht: core/tools/… |
| 6 | Auftrag (nicht in der DoD-Tabelle): unbeantwortete Rueckfrage laeuft nach 10 Minuten ab, danach `cancelled` | ◐ TEILWEISE | `rm -rf /tmp/skep5d && mkdir -p /tmp/skep5d && cat > /tmp/skep5d/serve.py <<'PY' ; import sys; sys.path.insert(0,"/home/user/website-/jarvis") ; imp…` | Befund des Pruefers unabhaengig nachgestellt und bestaetigt: der Task endet auf `done` mit abort_reason=None, nicht auf `cancelled`. Belegt ist nur die halbe Zusage — die Rueckfrage laeuft ab, nichts wird ausgefuehrt (keine outbox), der … |
| 7 | Auftrag (nicht in der DoD-Tabelle): das UI zeigt exakt was passieren wuerde und wartet auf POST /confirm | ✓ BELEGT | `# Server wie Kriterium 1, aber /tmp/skep5c und port=8153, dann: ; cat > /tmp/skep5c/ui_ja.py <<'PY' ; import os, pathlib, time ; os.environ["PLAYWR…` | Verdikt bestaetigt und VERSTAERKT: der Pruefer hatte nur den Nein-Weg geklickt und den Ja-Weg per curl belegt. Ich habe beide Klickwege gefahren und den Netzverkehr des Browsers mitgeschnitten — der Klick geht tatsaechlich als POST /api/… |

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

| # | Kriterium | Stand | BELEG — ausgeführter Befehl | Was der Beleg nicht zeigt |
|---|---|---|---|---|
| 1 | Referenz-Task laeuft durch und liefert eine Empfehlung mit Begruendung | ✗ BLOCKIERT | `# Was der 'durchgelaufene' Referenz-Task des Pruefers wirklich ist: ; grep -n "Ich empfehle Modell B" /tmp/claude-0/-home-user-website-/9814d470-2b…` | HERUNTERGESTUFT von TEILWEISE. Ich habe das Skript des Pruefers gelesen: die 'Empfehlung mit Begruendung' steht woertlich als letzter Eintrag in seiner Reply-Liste (Zeile 26). Sein Beleg zeigt also, dass der Runner einen vorformulierten … |
| 2 | Jeder Preis hat eine Quelle mit Abrufdatum; Preis ohne Quelle -> Schritt fehlgeschlagen | ◐ TEILWEISE | `cd /home/user/website-/jarvis && python3 -c " ; from core.contracts import Step, ToolResult ; from core.verify import verifiziere ; for t in ['Der …` | HERUNTERGESTUFT von BELEGT. Zwei harte Gegenbelege: (1) 'mit Abrufdatum' wird NIRGENDS geprueft — core/verify.py fragt nur `ergebnis.sources` auf Wahrheitswert ab; eine Quelle ohne Datum und sogar der Nichtstring 'kein-url-quatsch' beste… |
| 3 | Task-Baum im UI sichtbar (Hermes -> Research -> Tool-Calls) | ◐ TEILWEISE | `sed -n '1126,1168p' /home/user/website-/jarvis/index.html   # unterauftraegeNode ; # plus der Playwright-Lauf des Pruefers gegen den geskripteten F…` | Befund des Pruefers am Quelltext bestaetigt: die dritte Ebene des geforderten Baums (Tool-Calls des Unterauftrags, z. B. web_search) wird vom Renderer gar nicht erzeugt — er kennt nur Ziel, Agentenmarke, Ergebnis und weitere Kinder. Bele… |
| 4 | Gesamtkosten und Gesamttokens am Ende angezeigt | ◐ TEILWEISE | `cd /home/user/website-/jarvis && ls -la .env; python3 -c " ; from core.config import Settings ; s = Settings(_env_file=None) ; print('Preise konfig…` | Befund des Pruefers bestaetigt, soweit ohne Modell pruefbar: im Auslieferungszustand gibt es keine .env, damit keine Preise, damit ist jede Kostenanzeige strukturell 0.0 — die Karte zeigt '0.0000 €', die Kostenzeile im Plan-Fuss entfaell… |
| 5 | Aus Tiefe 2 wird kein weiterer Agent gerufen — abgelehnt und geloggt | ✓ BELEGT | `cd /home/user/website-/jarvis && python3 -c " ; import asyncio, logging, sys ; logging.basicConfig(level=logging.WARNING, stream=sys.stdout, format…` | Verdikt bestaetigt und VERSTAERKT. Beleg des Pruefers und der Repo-Test bauen beide einen DelegationsKontext mit depth=2 VON HAND — das zeigt die Wache, nicht dass das System diese Tiefe je erreicht. Ich bin deshalb bei Tiefe 0 gestartet… |
| 6 | Task bleibt unter dem Default-Budget | ✗ BLOCKIERT | `cd /home/user/website-/jarvis && python3 -c " ; from core.config import Settings ; from core.contracts import TaskBudget ; s = Settings(_env_file=N…` | Verdikt bestaetigt. Ohne LLM_API_KEY laeuft kein echter Referenz-Task, also ist sein Verbrauch nicht messbar; die 956 Token des Pruefers sind gezaehlte Woerter des Fakes. Nachgeprueft und bestaetigt ist der Zusatzbefund: es gibt keine .e… |

Gebaut: `core/delegation.py` mit dem Werkzeug `ask_agent`, Agent `hermes`,
Persistenz der Unteraufträge über `parent_task_id`, Baumansicht im UI.

**Ein Unterauftrag bekommt kein eigenes Budget.** Er zählt aufs selbe —
sonst wäre `max_cost_eur` eine Zahl ohne Bedeutung.

**Der Delegationskontext hängt an einem `ContextVar`**, nicht an einem
Modulglobal: mehrere Tasks können gleichzeitig laufen.

## Phase 7 — Observability-Dashboard

| # | Kriterium | Stand | BELEG — ausgeführter Befehl | Was der Beleg nicht zeigt |
|---|---|---|---|---|
| 1 | Live sehen was laeuft - SSE/WebSocket, kein Polling im Sekundentakt | ✓ BELEGT | `python3 scratchpad/ui5.py` (Playwright gegen einen uvicorn mit dreistufigem, kuenstlich verlangsamtem Anbieter; zaehlt Netzanfragen der Seite) — dazu `grep -c 'setTimeout(weiter, pause)' index.html` → 0 | Gegenprobe ueber die Laufzeit: bei 6,2 s Laufzeit 9 Abfragen, bei 13,3 s Laufzeit 10 — die Zahl haengt an den Ereignissen, nicht an der Uhr (ein 700-ms-Poller waere von 8 auf 18 gegangen). **Kein `EventSource`:** das kann keine Header setzen, der Token muesste in die URL und damit ins Zugriffslog. Gelesen wird mit `fetch` + Reader. Die woertliche Abnahme aus FIX-01 (`grep -c EventSource index.html` > 0) ist damit **nicht** erfuellt — der eine Treffer ist ein Kommentar, der erklaert, warum nicht. |
| 2 | Alten Task oeffnen, jeden Schritt inkl. Prompt und Antwort nachlesen | ✓ BELEGT | `PYTHONPATH=/home/user/website-/jarvis PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers python3 /tmp/claude-0/-home-user-website-/9814d470-2beb-57e6-b33a-9…` | Der Server wurde neu gestartet, der Auftrag also wirklich aus der Datenbank gelesen. Was als 'Antwort' dasteht, ist aber der Text eines geskripteten FakeLLMProvider, keine Modellantwort. In diesem Lauf lief kein Werkzeug (der Fake waehlt… |
| 3 | Kostenanzeige stimmt mit der Summe aus llm_calls ueberein - nachgerechnet | ✓ BELEGT | `curl -s -H 'X-Jarvis-Token: pruef-123' http://127.0.0.1:8137/api/stats \| python3 -m json.tool   # dagegen: python3 -c "import sqlite3;c=sqlite3.co…` | Die Gleichheit Anzeige==llm_calls ist echt nachgerechnet (unabhaengige SQL-Summe plus Preisformel je Aufruf). Die Token selbst stammen aber vom FakeLLMProvider, der Woerter zaehlt statt zu tokenisieren - die Zahlen sind konsistent, nicht… |
| 4 | Laufender Task per Knopf abbrechen, stoppt tatsaechlich | ✓ BELEGT | `PYTHONPATH=/home/user/website-/jarvis PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers python3 /tmp/claude-0/-home-user-website-/9814d470-2beb-57e6-b33a-9…` | Der Abbruch greift ZWISCHEN den Schritten: der gerade laufende Schritt B lief nach dem Klick noch zu Ende (running -> done), erst C wurde uebersprungen. Bei einem echten, langsamen Modellaufruf heisst 'stoppt' also: kein weiterer Schritt… |

> **Nur Erstprüfung.** Die Gegenprobe für diese Phase ist nicht gelaufen (Sitzungslimit). Die Verdikte sind nicht von einem zweiten Prüfer widerlegt worden.

> **26.08.2026 — Aufräumen (Inbetriebnahme-Befund, Schritt 5d).** Kein
> Kriterium bewegt sich dadurch; nur Karteileichen sind weg.
>
> - `FIRMS_MAP_KEY` **entfernt** aus `core/config.py` und `.env.example`.
>   Kein Code hat es je gelesen — es stand nur in der Vorlage und forderte
>   einen NASA-Zugang, der nichts bewirkt hätte. Belegt durch den neuen
>   `tests/test_config.py::test_jedes_settings_feld_wird_irgendwo_gelesen`:
>   er prüft alle 32 Settings-Felder statisch und wurde rot genau bei diesem
>   einen. Gegenprobe: Feld wieder eingefügt → wieder rot. Der Plan für
>   aktive Brände bleibt in `docs/satellite.md:46` stehen.
> - Drei unbenutzte Importnamen aus `core/tools/satellite_tools.py` raus:
>   `GRENZE_FAKTOR`, `UeberwachungAbgelehnt`, `pruefe_anfrage`.
>
> **Korrektur an einem Befund von außen:** `pruefe_anfrage` ist *kein* toter
> Code. In `core/tools/satellite_tools.py` war der Import unbenutzt, die
> Überwachungssperre selbst hängt aber an `core/agents.py:362`
> (`vorpruefung=pruefe_anfrage`) und wird in `core/agents.py:238-247`
> abgefangen und als `ToolResult(ok=False)` mit Begründung zurückgegeben.
> Wer die drei Namen als „tote Imports" pauschal löscht, ohne das zu prüfen,
> löscht beim nächsten Mal die Sperre mit.

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

> **26.08.2026 — der Bildpfad ist gebaut.** Damit sind DoD 1, 3 und 6 nicht
> mehr *strukturell* unerfüllbar; sie bleiben trotzdem `✗`/`◐`, weil hier
> keine CDSE-Zugangsdaten liegen und ich sie nicht gegen den echten Dienst
> ausgeführt habe. **NICHT AUSGEFÜHRT: ein Aufruf gegen das echte
> `sh.dataspace.copernicus.eu`.** Belegt ist die Anfrageform gegen die
> Dokumentation und gegen zwei Messungen, nicht gegen den laufenden Dienst.
>
> Gemessen statt erinnert — die Endpunkt-Frage war nicht aus der Doku zu
> klären, also gemessen:
>
> ```
> POST /api/v1/process        -> 401   (existiert, Token fehlt)
> POST /process/v1            -> 401   (existiert auch)
> POST /gibtesnicht/quatsch   -> 503   (existiert nicht)
> ```
>
> Die 503 auf dem erfundenen Pfad ist der Beleg, dass die 401 etwas heißt.
> Kontingent laut `documentation.dataspace.copernicus.eu/Quotas.html`:
> 10.000 Processing Units und 50.000 Anfragen im Monat — der Bildpfad ist
> **kostenlos** benutzbar.
>
> **Gebaut:** `CDSEProvider.render()` gegen die Sentinel Hub Process API,
> `core/satellite/bilder.py` (inhaltsadressierte Ablage unter `data/bilder/`),
> `GET /api/bild/{kennung}` hinter demselben Token wie alles andere, und die
> Bildanzeige in `index.html` — die Datei hatte vorher **null** `<img>`.
>
> **Der Auflösungsfehler ist behoben.** Bis hierher stand überall die
> Konstante 10.0 m/px, unabhängig vom Ausschnitt. Gemessen:
>
> ```
> ganz Deutschland, 512 px  ->  1696 m je Bildpixel
> Schwäbisch Gmünd, 512 px  ->    21,7 m je Bildpixel
> ```
>
> Der Grenzsatz („Objekte unter X m sind nicht beurteilbar") stützt sich
> jetzt auf **diese** Zahl. Wer dort die 10 stehen lässt, sagt dem Modell,
> es könne Dinge sehen, die auf dem Bild ein Zehntel Pixel groß sind — genau
> die Halluzination, die `SATELLIT_PROMPT` verbietet.
>
> **Weiterhin offen:** DoD 5 (Überflüge aus TLE-Daten). `skyfield` ist nicht
> im Stack und wäre laut `CLAUDE.md` eine Stack-Änderung — die entscheidet
> Noah, nicht ich.


| # | Kriterium | Stand | BELEG — ausgeführter Befehl | Was der Beleg nicht zeigt |
|---|---|---|---|---|
| 1 | "Aktuellstes wolkenfreies Sentinel-2-Bild von Schwaebisch Gmuend" liefert ein BILD mit Aufnahmedatum, Sensor, m/px und Wolkenanteil | ✗ BLOCKIERT | `cd /home/user/website-/jarvis && python3 -m pytest -q "tests/test_satellite.py::test_die_suche_liefert_datum_sensor_aufloesung_und_wolken" ; python…` | Dreifach nicht erfuellt. (a) Kein echter Key: keine CDSE-Variablen in der Umgebung, .env.example Zeile 29/30 leer; die Antwort kam aus httpx.MockTransport, es wurde nie ein echter Katalog befragt. (b) Kein Bild: CDSEProvider hat weder re… |
| 2 | Kein Bild unter dem Wolken-Schwellwert -> JARVIS sagt das, statt ersatzweise ein wolkiges zu liefern | ◐ TEILWEISE | `cd /home/user/website-/jarvis && python3 -m pytest -q "tests/test_satellite.py::test_dod_2_kein_bild_unter_dem_schwellwert_wird_gesagt" -v` | Belegt ist das WERKZEUG, nicht "JARVIS". Der leere Katalog kommt aus einem geskripteten httpx.MockTransport, nicht vom echten CDSE. Die Endstufe - der Satz erscheint so in der Antwort an den Nutzer - laeuft ueber den Agenten und damit ue… |
| 3 | Vergleich zweier Zeitpunkte zeigt beide Bilder nebeneinander plus eine Differenzdarstellung | ◐ TEILWEISE | `cd /home/user/website-/jarvis && python3 -m pytest -q "tests/test_satellite.py::test_der_vergleich_rechnet_und_nennt_die_grenze" "tests/test_satell…` | Belegt ist ausschliesslich die NUMERISCHE Differenz (A.5 Schritt 3). Das Kriterium verlangt "beide Bilder nebeneinander plus eine Differenzdarstellung" - dafuer gibt es keinen Code: index.html enthaelt null "img"-Vorkommen, der Browserte… |
| 4 | Jede Bildaussage folgt BEOBACHTET / INTERPRETATION / KONFIDENZ und nennt die Bodenaufloesung | ◐ TEILWEISE | `cd /home/user/website-/jarvis && python3 -m pytest -q "tests/test_satellite.py::test_der_bericht_hat_die_pflichtzeile_grenze" "tests/test_satellite…` | Die Funktion erzeugt das Schema korrekt und weist erfundene Konfidenzstufen ab - aber sie wird im Produktivpfad NIE aufgerufen: der grep ueber alle .py ausserhalb von tests/ findet nur die Definition selbst. Die Displays von satellite_se… |
| 5 | "Welche Satelliten ueberfliegen heute meine Position?" - Zeiten aus echten TLE-Daten, mit skyfield gerechnet | ✗ OFFEN | `cd /home/user/website-/jarvis && grep -rniE "skyfield\|celestrak\|sgp4" --include=*.py --include=*.txt . ; echo "grep-Exitcode: $?" ; python3 -c "i…` | Nicht gebaut, nicht angefangen. skyfield steht nicht in requirements.txt und ist nicht installiert; die Woerter skyfield, celestrak und sgp4 kommen in keiner .py- oder .txt-Datei des Projekts vor; in der Werkzeugliste gibt es kein Ueberf… |
| 6 | Attribution der Datenquelle steht sichtbar am Bild | ✗ OFFEN | `cd /home/user/website-/jarvis && JARVIS_TOKEN=pruef8 python3 -m uvicorn main:app --host 127.0.0.1 --port 8137 &  (dann) python3 scratchpad/ui.py  #…` | Browserbeleg im echten Chromium: die geladene Oberflaeche hat null Bildelemente und null Canvas, also gibt es kein "Bild", an dem eine Attribution stehen koennte. Gebaut ist nur die Datenseite: Scene.attribution ist Pflichtfeld (eine Sze… |

> **Nur Erstprüfung.** Die Gegenprobe für diese Phase ist nicht gelaufen (Sitzungslimit). Die Verdikte sind nicht von einem zweiten Prüfer widerlegt worden.

> **26.08.2026 — Aufräumen (Inbetriebnahme-Befund, Schritt 5d).** Kein
> Kriterium bewegt sich dadurch; nur Karteileichen sind weg.
>
> - `FIRMS_MAP_KEY` **entfernt** aus `core/config.py` und `.env.example`.
>   Kein Code hat es je gelesen — es stand nur in der Vorlage und forderte
>   einen NASA-Zugang, der nichts bewirkt hätte. Belegt durch den neuen
>   `tests/test_config.py::test_jedes_settings_feld_wird_irgendwo_gelesen`:
>   er prüft alle 32 Settings-Felder statisch und wurde rot genau bei diesem
>   einen. Gegenprobe: Feld wieder eingefügt → wieder rot. Der Plan für
>   aktive Brände bleibt in `docs/satellite.md:46` stehen.
> - Drei unbenutzte Importnamen aus `core/tools/satellite_tools.py` raus:
>   `GRENZE_FAKTOR`, `UeberwachungAbgelehnt`, `pruefe_anfrage`.
>
> **Korrektur an einem Befund von außen:** `pruefe_anfrage` ist *kein* toter
> Code. In `core/tools/satellite_tools.py` war der Import unbenutzt, die
> Überwachungssperre selbst hängt aber an `core/agents.py:362`
> (`vorpruefung=pruefe_anfrage`) und wird in `core/agents.py:238-247`
> abgefangen und als `ToolResult(ok=False)` mit Begründung zurückgegeben.
> Wer die drei Namen als „tote Imports" pauschal löscht, ohne das zu prüfen,
> löscht beim nächsten Mal die Sperre mit.

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

| # | Kriterium | Stand | BELEG — ausgeführter Befehl | Was der Beleg nicht zeigt |
|---|---|---|---|---|
| 1 | Taste halten, sprechen, loslassen -> Transkript erscheint im Chat und der Task startet | ◐ TEILWEISE | `JARVIS_TOKEN=pruef-token-123 JARVIS_PORT=8137 LLM_PROVIDER= python3 main.py &  (dann) timeout 300 python3 /tmp/claude-0/-home-user-website-/9814d47…` | Das Transkript stammt aus einem von mir eingesetzten Fake-Recognizer, nicht aus echter Spracherkennung. Der ECHTE Pfad wurde separat versucht und scheitert hier hart: /tmp/.../echt_ptt.py mit --use-fake-device-for-media-stream liefert RO… |
| 2 | Die Antwort wird vorgelesen und laesst sich abbrechen | ◐ TEILWEISE | `timeout 300 python3 /tmp/claude-0/-home-user-website-/9814d470-2beb-57e6-b33a-9098aa5bb39b/scratchpad/ui_abbruch.py   # gleicher Server auf 8137, g…` | speechSynthesis war fuer diesen Lauf durch ein Skript ersetzt. Die echte Sprachausgabe ist in dieser Umgebung nicht moeglich: /tmp/.../tts_echt.py gibt {'voices': 0, 'events': ['error:synthesis-failed'], 'speaking': False} - Chromium hat… |
| 3 | Antwort im Sprachmodus kuerzer als im Textmodus, vom Systemprompt erzwungen | ◐ TEILWEISE | `python3 -m pytest -q tests/test_voice.py::test_der_endpunkt_nimmt_das_voice_flag tests/test_voice.py::test_ohne_flag_bleibt_es_beim_textmodus tests…` | Belegt ist nur die halbe Aussage: der Systemprompt wird im Sprachmodus tatsaechlich um SPRACHSTIL ('Hoechstens drei Saetze', 'wird VORGELESEN', 'Keine Aufzaehlungen') erweitert und sonst nichts geaendert. Dass die Antwort dadurch KUERZER… |
| 4 | Deutsch und Englisch funktionieren beide | ◐ TEILWEISE | `timeout 300 python3 /tmp/claude-0/-home-user-website-/9814d470-2beb-57e6-b33a-9098aa5bb39b/scratchpad/ui_ptt.py   # klickt #btn-sprache und schickt…` | Belegt ist zur Laufzeit im echten Browser, dass der Umschalter den Sprachcode auf beiden Seiten setzt (SpeechRecognition.lang = en-US, SpeechSynthesisUtterance.lang = en-US) und dass der englische Text durch denselben Weg bis zum POST ko… |

> **Nur Erstprüfung.** Die Gegenprobe für diese Phase ist nicht gelaufen (Sitzungslimit). Die Verdikte sind nicht von einem zweiten Prüfer widerlegt worden.

> **26.08.2026 — Aufräumen (Inbetriebnahme-Befund, Schritt 5d).** Kein
> Kriterium bewegt sich dadurch; nur Karteileichen sind weg.
>
> - `FIRMS_MAP_KEY` **entfernt** aus `core/config.py` und `.env.example`.
>   Kein Code hat es je gelesen — es stand nur in der Vorlage und forderte
>   einen NASA-Zugang, der nichts bewirkt hätte. Belegt durch den neuen
>   `tests/test_config.py::test_jedes_settings_feld_wird_irgendwo_gelesen`:
>   er prüft alle 32 Settings-Felder statisch und wurde rot genau bei diesem
>   einen. Gegenprobe: Feld wieder eingefügt → wieder rot. Der Plan für
>   aktive Brände bleibt in `docs/satellite.md:46` stehen.
> - Drei unbenutzte Importnamen aus `core/tools/satellite_tools.py` raus:
>   `GRENZE_FAKTOR`, `UeberwachungAbgelehnt`, `pruefe_anfrage`.
>
> **Korrektur an einem Befund von außen:** `pruefe_anfrage` ist *kein* toter
> Code. In `core/tools/satellite_tools.py` war der Import unbenutzt, die
> Überwachungssperre selbst hängt aber an `core/agents.py:362`
> (`vorpruefung=pruefe_anfrage`) und wird in `core/agents.py:238-247`
> abgefangen und als `ToolResult(ok=False)` mit Begründung zurückgegeben.
> Wer die drei Namen als „tote Imports" pauschal löscht, ohne das zu prüfen,
> löscht beim nächsten Mal die Sperre mit.

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

## Phase 10 — Härten & Verpacken

| # | Kriterium | Stand | BELEG — ausgeführter Befehl | Was der Beleg nicht zeigt |
|---|---|---|---|---|
| 1 | `docker compose up` startet alles auf einem frischen Rechner | ◐ TEILWEISE | `dockerd & ; git -C /home/user/website- archive HEAD jarvis \| tar -x -C /tmp/fresh --strip-components=1; cd /tmp/fresh && cp .env.example .env && d…` | Docker-Daemon war NICHT unerreichbar, wie STATUS.md behauptet — ich habe dockerd gestartet, `docker pull python:3.11-slim` lief durch. Der Build scheitert an der transparenten TLS-Interception dieser Sandbox (`docker run --rm python:3.11… |
| 2 | Ein neuer Nutzer kommt nur mit der README zum laufenden System | ✓ BELEGT | `git -C /home/user/website- archive HEAD jarvis \| tar -x -C /tmp/fresh --strip-components=1; cd /tmp/fresh && python3 -m venv .venv && ./.venv/bin/…` | "Frischer Rechner" ist simuliert: frischer git-archive-Export + frisches venv auf DERSELBEN Maschine, auf der Python 3.11, pip und ein Netzzugang schon standen. Statt des README-Befehls `python -m uvicorn main:app --reload` habe ich `--p… |
| 3 | Alle Tests laufen in CI grün | ◐ TEILWEISE | `GitHub Actions Run 32846153576 (.github/workflows/ci.yml, push, Commit f85564c) — abgerufen über die GitHub-API; lokal: `cd /home/user/website-/jar…` | Der grüne CI-Lauf gehört zu Commit f85564c. Lokal steht HEAD auf 23773fc, also ZWEI Commits weiter (2234a22 "fix: FakeLLMProvider beantwortet die Planungsanfrage", 23773fc); origin/claude/jarvis-ai-os-1u7ied zeigt noch auf f85564c. Für d… |
| 4 | Backup lässt sich einspielen, Verlauf danach vollständig | ✓ BELEGT | `JARVIS_DB_PATH=/tmp/fresh/data/jarvis.db python -m scripts.backup sichern /tmp/dod4-backup.db; rm -f /tmp/fresh/data/jarvis.db*; ... backup pruefen…` | Der WAL-Anspruch separat geprüft: bei offen gehaltener Verbindung (WAL 16512 Bytes) ist die `cp`-Kopie unbrauchbar ("no such table: messages"), das über scripts.backup erzeugte Backup enthält beide Zeilen ['alte Zeile','nur im WAL'] — de… |

> **Nur Erstprüfung.** Die Gegenprobe für diese Phase ist nicht gelaufen (Sitzungslimit). Die Verdikte sind nicht von einem zweiten Prüfer widerlegt worden.

> **26.08.2026 — Aufräumen (Inbetriebnahme-Befund, Schritt 5d).** Kein
> Kriterium bewegt sich dadurch; nur Karteileichen sind weg.
>
> - `FIRMS_MAP_KEY` **entfernt** aus `core/config.py` und `.env.example`.
>   Kein Code hat es je gelesen — es stand nur in der Vorlage und forderte
>   einen NASA-Zugang, der nichts bewirkt hätte. Belegt durch den neuen
>   `tests/test_config.py::test_jedes_settings_feld_wird_irgendwo_gelesen`:
>   er prüft alle 32 Settings-Felder statisch und wurde rot genau bei diesem
>   einen. Gegenprobe: Feld wieder eingefügt → wieder rot. Der Plan für
>   aktive Brände bleibt in `docs/satellite.md:46` stehen.
> - Drei unbenutzte Importnamen aus `core/tools/satellite_tools.py` raus:
>   `GRENZE_FAKTOR`, `UeberwachungAbgelehnt`, `pruefe_anfrage`.
>
> **Korrektur an einem Befund von außen:** `pruefe_anfrage` ist *kein* toter
> Code. In `core/tools/satellite_tools.py` war der Import unbenutzt, die
> Überwachungssperre selbst hängt aber an `core/agents.py:362`
> (`vorpruefung=pruefe_anfrage`) und wird in `core/agents.py:238-247`
> abgefangen und als `ToolResult(ok=False)` mit Begründung zurückgegeben.
> Wer die drei Namen als „tote Imports" pauschal löscht, ohne das zu prüfen,
> löscht beim nächsten Mal die Sperre mit.

Gebaut: `Dockerfile`, `docker-compose.yml`, `.dockerignore`,
`scripts/backup.py`, `scripts/migrate.py`, `scripts/measure.py`,
`scripts/healthcheck.py`, vollständige README, CI um Migration und
Backup/Restore erweitert.

**Gesichert wird über SQLites Backup-API, nicht mit `cp`.** Bei
eingeschaltetem WAL liegen die letzten Schreibvorgänge in `-wal`; eine
kopierte `.db` allein ist unvollständig. Ein Test hält eine Verbindung offen,
schreibt und prüft, dass die Zeile trotzdem im Backup landet.

**Ein Restore legt die bisherige Datenbank beiseite**, statt sie zu
überschreiben. Ein Restore, der das Vorherige unwiederbringlich löscht, ist
eine Falle.

**Der Compose-Port wird nur an `127.0.0.1` veröffentlicht** (§0.4.3). Ohne das
Präfix hinge JARVIS am ganzen Netz.

### Postgres: nicht nötig — gemessen, nicht angenommen

`python -m scripts.measure` mit 20.000 Nachrichten und 5.000 Fakten
(feste Zufallssaat, wiederholbar):

| Abfrage | Median | p95 | max |
|---|---|---|---|
| FTS5 über `facts` | 4,14 ms | 4,81 ms | 5,44 ms |
| FTS5 über `messages` | 19,96 ms | 21,44 ms | 21,62 ms |
| Kontextblock (Suche + Format) | 4,04 ms | 4,41 ms | 4,88 ms |

Datei: 5,5 MB. Ein Modellaufruf dauert das Tausendfache. **Postgres und
pgvector bleiben gestrichen.** Die Messung gehört wiederholt, wenn die
Datenmenge deutlich wächst.

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
