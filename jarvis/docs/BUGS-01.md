# BEFUNDE 01 — Fehlersuche vom 25.08.2026

Acht Sucher mit verschiedenen Brillen, danach je ein Skeptiker, der **jeden** Fund
reproduzieren musste. Wer den Fehler nicht mit einem ausgeführten Befehl vorführen
konnte, dessen Fund ist rausgeflogen.

```
30 bestätigt   ·   12 verworfen   ·   ~18 eigenständige Defekte
```

Zwei Prüfer sind am Sitzungslimit gescheitert (Brillen `vertraege` und `frontend`) —
deren Funde stehen unten **nicht** drin, weil sie nicht gegengeprüft sind.

**Stand der Reparatur** (der Befund selbst bleibt unverändert stehen — er ist das Protokoll
vom 25.08., kein Aufgabenzettel, den man umschreibt):

| Fund | Stand | Commit |
|---|---|---|
| 3 · Nicht-ASCII-Token → 500 | behoben | `f1d5e22` |
| 6 · Hostname aus Modellparameter | behoben | `f1d5e22` |
| 7 · Keine SSRF-Sperre | behoben | `f1d5e22` |
| 12 · `pruefe()` ohne Inhaltsprüfung | behoben | `5a21934` (FIX-02) |
| 13 · Kartenzahl sinkt ohne Nachrücken | behoben | `5a21934` (FIX-02) |
| 23 · jede Chat-Nachricht ab der 21. scheitert | behoben | `core/llm.py`, `api/routes.py` |
| 22 · `fts_query` wirft nicht-deutsche Wörter weg | behoben | `core/memory.py` |
| 19 · `EventBus` wirft das neue Ereignis weg | behoben | `api/events.py` |
| 16 · `/api/chat` ohne Budget | behoben | `api/routes.py` |
| 11 · 500 bei Nicht-Objekt-JSON | war mit FIX-02 Schritt 1 schon weg, Tests vorhanden | `tests/test_weltlage.py` |
| 10 · misslungener Lauf 60 min im Cache | war mit FIX-02 Schritt 1 schon weg, Test vorhanden | `tests/test_weltlage.py` |
| 15 · `can_call_agents` ungeprüft | behoben | `core/delegation.py` (Rufer im Kontext) + `core/agents.py` |
| 14 · Rechner-Bombe | behoben, **Mechanismus im Bericht falsch** — siehe unten | `core/tools/builtin.py` (Deckel für jedes Zwischenergebnis) |
| 5 · Weltlage nicht in `llm_calls` | war mit FIX-02 Schritt 2 schon weg, jetzt durch einen Test festgehalten | `tests/test_weltlage.py` |
| 4 · Budget nur zwischen Schritten | behoben | `core/tools/loop.py`, `core/agents.py`, `core/runner.py`, `core/contracts.py` |
| 2 · Restore macht sich selbst rückgängig | behoben | `scripts/backup.py` (Sicherheitskopie über die Backup-API) |
| 1 · Abbrechen-Knopf | behoben | `api/tasks.py` (Wecker für die Rückfrage) + `core/runner.py` (Prüfung *nach* jedem Schritt) |
| alle übrigen | offen | — |

---

## HOCH

### 1. Der Abbrechen-Knopf bricht nicht ab

`api/tasks.py:196` · `core/runner.py:198` · **von vier Suchern unabhängig gefunden**

Drei Ausprägungen desselben Defekts:

**a) Bei offener Rückfrage.** Der Task hängt in `await asyncio.wait_for(zukunft, 600)`.
`cancel` setzt nur `eintrag.abbruch` — niemand weckt die Future.

```
Rueckfrage offen: send_email | status: running
POST /cancel -> {'status': 'cancelling'}
6.1 s nach dem Abbruch:  status = running, confirmation offen = True
POST /confirm nach dem Abbruch -> 200 {'approved': True}
   Endstatus = done
   outbox existiert = True
   outbox-Inhalt: {"to": "chef@firma.de", "subject": "Krankmeldung", ...}
```

Im Browser nachgestellt: nach dem Klick auf „abbrechen" bleibt die Rückfrage sichtbar,
der Knopf „Ausführen" bleibt aktiv — und wer ihn drückt, verschickt die Mail.

**b) Beim letzten (meist einzigen) Schritt.** `budget_verletzung` und die Abbruchprüfung
liegen *zwischen* den Schritten.

```
POST /cancel -> {'status': 'cancelling'}
Endstatus: done | abort_reason: None
Modellaufrufe NACH dem Abbruch: 3 (also 2 weitere)
```

Bei einem Ein-Schritt-Plan — und der Planner ist ausdrücklich darauf getrimmt, einfache
Ziele in einem Schritt zu erledigen — ist der Knopf damit wirkungslos.

### 2. `scripts.backup einspielen` meldet Erfolg und macht den Restore rückgängig

`scripts/backup.py:90-97` · **zwei Funde derselben Ursache**

Die Sicherheitskopie vor dem Restore enthält nicht, was im `-wal` steht — und
unmittelbar danach wird genau diese `-wal`-Datei nicht mit beiseitegelegt. Der
Rückgabewert ist 0, der eingespielte Stand ist weg.

Das ist besonders bitter, weil `scripts/backup.py` genau dafür gebaut wurde: **„Ein
Restore, der das Vorherige unwiederbringlich löscht, ist eine Falle."**

### 3. Nicht-ASCII im Token-Header → HTTP 500 statt 401

`api/security.py:33` · **von drei Suchern gefunden**

`secrets.compare_digest` wirft bei einem `str` mit Nicht-ASCII-Zeichen. Folge:
Ein `JARVIS_TOKEN` mit Umlaut in der `.env` legt **jeden** Request lahm — der Nutzer
bekommt bei jedem Aufruf 500 und keinen Hinweis, woran es liegt.

### 4. Das Budget wird nur zwischen Schritten geprüft

`core/runner.py:209`

`budget_verletzung()` läuft ausschließlich in der Schleife über `task.steps`. Innerhalb
eines Schritts sind `max_tokens`, `max_cost_eur`, `max_tool_calls` und `max_seconds`
beliebig überschreitbar — und der Task endet auf `done` statt `aborted_budget`.

Ein Ein-Schritt-Plan hat damit praktisch kein Budget. Das widerspricht
`docs/contracts.md` 0.5 direkt.

### 5. Weltlage-Modellaufrufe landen nie in `llm_calls`

`api/weltlage.py:234` · **von vier Suchern gefunden**

```
3 Weltlage-Auftraege gestellt (3 echte Modellaufrufe).
llm_calls in der Datenbank : {'calls': 0, 'cost_eur': 0.0}
Zaehler der Weltlage-Seite : {'abfragen': 3, 'kosten_eur': 0, 'modellaufrufe': 0}
/api/stats total           : {'calls': 0, 'cost_eur': 0.0}
nach einem normalen Task   : {'calls': 3, ...}   <- der Task-Pfad schreibt korrekt
```

`post_weltlage` ruft `provider.complete()` direkt auf und schreibt nie `db.log_llm_call`.
**Das ist die Ursache für `heute 0,0000 €` im Screenshot** — nicht ein Demo-Pfad.
Phase-11-DoD 8 („stimmt mit `llm_calls` überein") ist damit zwar wahr, aber leer.

### 6. `wiki_live` baut den Hostnamen aus einem Modellparameter

`core/tools/wissen_tools.py:257`

**Höher eingestuft als vom Prüfer.** Ich habe es selbst nachgestellt:

```
sprache='de'         -> host='de.wikipedia.org'    auth=ja
sprache='evil.com/'  -> host='evil.com'            auth=ja  <-- TOKEN AN FREMDEN HOST
sprache='de/../..'   -> host='de'                  auth=ja  <-- TOKEN AN FREMDEN HOST
sprache='//evil.com' -> host=''                    auth=ja  <-- TOKEN AN FREMDEN HOST
```

`sprache` kommt direkt aus dem Modell. Ein vergifteter Suchtreffer genügt, damit JARVIS
seinen `WIKI_API_TOKEN` samt `Authorization`-Header an einen fremden Server schickt.

### 7. `fetch_url` hat keine SSRF-Sperre

`core/tools/search.py` · selbst nachgestellt

```
fetch_url auf http://127.0.0.1:PORT/admin : ok=True
   Inhalt im Ergebnis: True   ("hunter2" landet im Modellkontext)
```

Eine vom Modell gelieferte URL kann alles lesen, was der Server erreicht — auch
`localhost` und das eigene Netz. Der Inhalt geht anschließend in den Prompt.

---

## MITTEL

### 8. Gedächtnis-Panel und Modell sehen mit Vault verschiedene Daten

`core/tools/memory_tools.py` gegen `api/routes.py` · selbst nachgestellt

```
1. Das Modell merkt sich etwas (Werkzeug remember)
   Gedaechtnis-Panel zeigt: 0 Fakten -> []
2. Der Mensch traegt im Panel etwas ein
   recall findet es: Nichts zu 'Schwaebisch' im Vault.
3. Zeilen in facts: 1 | Notizen im Vault-Index: 1
```

Mit gesetztem `VAULT_PFAD` zerfällt das Gedächtnis in zwei Hälften, die einander nicht
sehen. `MIGRATION-VAULT.md` Schritt 5 hat den Lesepfad des **Werkzeugs** umgestellt,
die API-Endpunkte aber nicht.

### 9. Die Konflikterkennung aus Phase 3 verschwindet mit dem Vault

`core/tools/memory_tools.py` · selbst nachgestellt

```
Ohne Vault:  Widerspruch gemeldet: True
             "ACHTUNG: das widerspricht moeglicherweise #1: Mein Rad ist ein Santa Cruz"
Mit Vault:   Widerspruch gemeldet: False
```

Phase-3-DoD 5 verlangt, dass ein widersprechender Fakt **angezeigt** und nicht stumm
danebengelegt wird. Mit Vault stehen beide gleichberechtigt im Kontext des Modells.

Ursache: `remember` vergibt jedes Mal eine neue `id`, also gibt es weder Dedup noch
Konfliktprüfung — und der Konfliktschutz `bekannt_bis` wird vom einzigen produktiven
Aufrufer nie übergeben.

### 10. Ein misslungener Weltlage-Auftrag wird 60 Minuten lang ausgeliefert

`api/weltlage.py:250`

Scheitert die Recherche, landet das leere Ergebnis im Cache — und wird danach eine
Stunde lang als „Ergebnis" zurückgegeben, statt es erneut zu versuchen.

### 11. `POST /api/weltlage/{land}` → 500 bei ungewöhnlichem Modell-JSON

`api/weltlage.py:244`

Liefert das Modell gültiges JSON, das kein Objekt ist (eine Liste), wirft die Route 500
statt es zu verwerfen.

### 12. `pruefe()` prüft `schlagzeile` und `kurz` nicht

`core/weltlage.py`

Eine Meldung mit leerer Schlagzeile und leerem Text besteht den Vertrag und wird als
Karte ausgeliefert.

### 13. Die Kartenzahl sinkt unter fünf, ohne nachzurücken

`api/weltlage.py` · selbst nachgestellt

```
8 Kandidaten -> 5 gekappt -> nach dem Bild: 4 Karten, verworfen: ['Bild ohne Herkunft']
Es gab noch 3 gueltige Kandidaten, die nicht nachruecken.
```

Gekappt wird **vor** dem Bildholen, gesiebt **danach**.

### 14. Rechner-Bombe friert den Server ein

`core/tools/builtin.py:128`

`(10**15)**1000` liegt exakt auf der Grenze (`1000` ist nicht `> 1000`), wird zugelassen,
und `rechne()` läuft synchron im asyncio-Loop. Die 30-Sekunden-Werkzeugschranke greift
nicht, weil `asyncio.wait_for` eine synchrone Funktion nicht unterbrechen kann.

> **Korrektur beim Reparieren, 26.08.** Der genannte Ausdruck friert nichts ein — er
> rechnet in 0,2 ms. Zwei getrennte Defekte stecken dahinter, beide nachgemessen:
>
> 1. `(10**15)**1000` ergibt 15001 Stellen. Python weigert sich ab 4300 Stellen,
>    daraus einen String zu machen. Der `ValueError` entsteht erst beim Formatieren
>    der Antwort — **nach** dem `try`-Block in `execute` — und flog unbehandelt heraus.
>    Beim Nutzer kam der Python-Interna-Text über `sys.set_int_max_str_digits` an.
> 2. Das Einfrieren ist echt, kommt aber von einer **Multiplikationskette**: die
>    Potenzgrenze deckelt nur `**`, nicht `*`.
>
>    ```
>    n= 50  Ausdruck   847 Zeichen   0.540 s
>    n=100  Ausdruck  1697 Zeichen   2.163 s
>    n=200  Ausdruck  3397 Zeichen   8.514 s
>    n=400  Ausdruck  6797 Zeichen  34.555 s
>    ```
>
>    Der Satz über `asyncio.wait_for` stimmt dabei: `rechne()` läuft synchron im
>    Event-Loop, 34 s lang antwortet der ganze Server nicht.
>
> Behoben mit einem Deckel für **jedes** Zwischenergebnis, nicht nur für Potenzen.
> Er liegt da, wo Python selbst aufhört. Danach: 3,2 ms statt 34,6 s.
>
> Offen und **nicht** repariert: ein sehr langer Ausdruck (ab ~2000 Faktoren) läuft
> beim Parsen in einen `RecursionError`. Der wird vom Dispatcher aufgefangen, dauert
> 23 ms und reisst nichts um — aber die Meldung an den Nutzer ist nichtssagend.

### 15. `can_call_agents` wird nirgends geprüft

`core/delegation.py:101`

`hermes` (`max_permission=LOCAL`, Liste `['research','satellite']`) erreicht über
`ask_agent` auch sich selbst und `jarvis`.

### 16. `POST /api/chat` hat kein Budget

`api/routes.py:174`

Nur die Zahl der Werkzeugrunden ist begrenzt — keine Token-, Kosten- oder Zeitschranke.

### 17. `migrate.py` lässt den Volltextindex leer

`scripts/migrate.py:55`

Eine Datenbank aus Phase 1 bekommt beim Nachziehen die FTS-Tabellen, aber der Index über
die **bestehenden** Nachrichten bleibt leer — die alte Historie ist danach für `recall`
unsichtbar, und der Reparaturbefehl `rebuild` ist selbst kaputt.

### 18. Nach der Vault-Migration fehlen der neuen `facts`-Tabelle die FTS-Trigger

`scripts/migrate_vault.py:100`

`ALTER TABLE facts RENAME TO facts_alt` nimmt die Trigger mit; `CREATE TRIGGER IF NOT
EXISTS` legt sie nicht neu an.

### 19. `EventBus` wirft bei vollem Puffer das **neue** Ereignis weg

`api/events.py:53`

Entgegen dem eigenen Docstring („drops oldest"). Folge: die Oberfläche bleibt auf
„Plan läuft" stehen, weil das `final`-Ereignis fehlt — und sie pollt bewusst nicht mehr.

### 20. Der Vault-Beobachter startet einen OS-Thread je geänderter Datei

`core/vault_index.py:190`

```
N= 2600  indexiert= 2600  FEHLEND=  0
N= 3000  indexiert= 2944  FEHLEND= 56   'database is locked'-Ausnahmen=56
```

Bei einem git-Checkout oder Obsidian-Sync mit ~3000 Notizen verlieren einige Dutzend
still den Index. Dazu: die Timer-Tabelle wächst unbegrenzt (50 Dateien → 50 Timer, auch
nach dem Feuern).

### 21. Eine nicht-UTF-8-Datei im Vault legt `remember` lahm

`core/vault.py:257`

### 22. `memory.fts_query` wirft jedes nicht-deutsche Wort weg

`core/memory.py:42`

`recall` findet Fakten mit z. B. kyrillischen oder französischen Wörtern nicht.

### 23. Jede 21. Nachricht an `/api/chat` scheitert am echten Anbieter

`api/routes.py:106`

Nach 40 Nachrichten beginnt das Verlaufsfenster mit `assistant` — die Anthropic-API
verlangt `user` als erste Nachricht. Mit dem Fake fällt das nicht auf.

---

## Was der Skeptiker verworfen hat (12)

Darunter: `/api/health` meldet fest `phase=2` (falsch, aber von einem Test festgenagelt
und ohne Wirkung), `DELETE /api/memory/<20-stellige-Zahl>` gibt 500 (auf keinem Weg
erreichbar), `WELT` bestellt sechs Meldungen und zeigt fünf (die Anzeigeregel ist
ausdrücklich so gewollt), `EventBus`-Überlauf über eine echte Verbindung (nur mit
künstlich blockiertem Event-Loop erreichbar).

Und einer von mir selbst: **Doppelklick auf „Senden" startet zwei Aufträge** — das war
ein Messartefakt von Playwrights Auto-Warten. Ohne Auto-Warten:

```
POST /api/tasks: 1 | offene Stroeme: 1 | Eingabe gesperrt: True
```

---

## Was gehalten hat

- **Der Rechner-AST** gegen neun Angriffe (`__import__`, `__subclasses__`, Lambdas,
  `open`, `globals`) — alle abgewiesen. Nur die Potenz-Grenze ist zu weit (Fund 14).
- **`audit_log`** ist wirklich unveränderlich: `UPDATE` und `DELETE` werden abgelehnt.
- **Die Kostenrechnung nach Abbruch** stimmt exakt: Task-Token == `llm_calls` == `/api/stats`.
- **Kein `eval`, kein `exec`, kein `shell=True`** im Produktivcode.
