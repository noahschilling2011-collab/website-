# WISSENSQUELLEN FÜR JARVIS

> Stand der Recherche: 25.08.2026. Was unten als **geprüft** markiert ist, wurde
> nachgeschlagen. Der Rest ist **ungeprüft** und vor dem Bauen zu verifizieren.

---

## 0. Die Korrektur vorweg

„Damit er nicht dumm bleibt und immer dazulernt" vermischt drei Dinge, die technisch
nichts miteinander zu tun haben:

| Was du meinst | Was es technisch ist | Geht das? |
|---|---|---|
| Er soll mehr wissen | **Nachschlagen** — Wissensquelle abfragen | ja, kostenlos |
| Er soll sich merken, was ich sage | **Memory** — Phase 3, SQLite | ja, schon gebaut |
| Er soll klüger werden | **Training** — Modellgewichte ändern | nein |

Das Modell lernt aus euren Gesprächen **nichts**. Es hat nach 1.000 Unterhaltungen
exakt dieselben Gewichte wie nach der ersten. Was sich ändert, ist nur, was JARVIS
in seine Prompts hineinschreibt.

**Und der eigentliche Gewinn einer Wissensquelle ist nicht, dass er mehr weiß —
sondern dass seine Antworten prüfbar werden.** Ein Modell, das Wikipedia zitiert,
kann man widerlegen. Ein Modell, das aus dem Gedächtnis erzählt, nicht. Das ist
derselbe Unterschied wie bei „5 Flugzeuge, 3 mehr als sonst".

---

## 1. Die Empfehlung: lokal + live, zwei getrennte Tools

### `wiki_lokal` — Kiwix ZIM auf deiner Platte **← hier anfangen**

Wikipedia als komprimierte Datei, die du einmal herunterlädst. `kiwix-serve` stellt
sie über HTTP bereit, JARVIS fragt `localhost` ab.

**Warum das die beste Antwort auf deine Frage ist:** kein Schlüssel, keine Kosten,
kein Ratenlimit, keine Netzabhängigkeit, deterministisch. Du kannst hundertmal pro
Minute abfragen und niemand sperrt dich.

Kiwix produziert jede Wikipedia in drei Varianten: `mini` enthält nur die Einleitung
jedes Artikels plus Infobox und spart rund 95 % Platz gegenüber der Vollversion,
`nopic` enthält vollständige Artikel ohne Bilder und ist etwa 75 % kleiner.
Die vollständige Wikipedia-ZIM liegt bei etwa 100 GB.

**Nimm `mini`.** Für ein Nachschlage-Tool willst du genau das, was `mini` liefert:
Einleitung plus Infobox. Den Volltext eines Artikels willst du gar nicht im Prompt
haben — der frisst dein Tokenbudget. Zum Größenvergleich: die englische `all_mini`
lag bei 11,7 GB, während `all_nopic` für Englisch bei rund 56 GB liegt.
Die deutschen Größen stehen im Katalog — **nachsehen, nicht raten**.

Bezug: `library.kiwix.org` (Oberfläche) oder `download.kiwix.org/zim/` (Dateiliste).

Einschränkung, die du kennen musst: ZIM-Dateien lassen sich nicht inkrementell
aktualisieren. Es ist eine datierte Momentaufnahme. Für Stammwissen egal, für
Aktuelles unbrauchbar — deshalb das zweite Tool.

### `wiki_live` — Wikimedia-API für alles nach dem Snapshot-Datum

**Geprüft, und hier hat sich 2026 etwas geändert:**

API-Ratenlimits werden 2026 ausgerollt, um den Anteil unauthentifizierter
automatisierter Anfragen zu senken. Anfragen ohne Zugangstoken sind auf 500 Anfragen
pro Stunde und IP begrenzt, mit persönlichem API-Token auf 5.000 pro Stunde.

Also: **kostenloses Token holen und benutzen.** Dazu Pflicht: ein aussagekräftiger
`User-Agent` mit Kontaktangabe, etwa
`CoolBot/0.0 (https://example.org/coolbot/; coolbot@example.org)`, höchstens drei
gleichzeitige Anfragen und `Retry-After` bei 429 respektieren.

Ohne konformen User-Agent fällst du in die niedrigste Limitklasse.

**Falle:** Die Core API wird ab Juli 2026 schrittweise abgekündigt; Ersatzrouten
stehen noch nicht fest, und Nutzer sollen mit der Migration warten, bis die neuen
Endpunkte in der zweiten Jahreshälfte 2026 angekündigt werden.
Bau also jetzt **nicht** auf der Core API auf. Vorher die aktuelle Doku prüfen,
welcher Endpunkt gerade der richtige ist.

### `wikidata` — für Fakten statt Fließtext

Strukturierte Daten per SPARQL: Einwohnerzahlen, Gründungsdaten, Koordinaten,
Zugehörigkeiten. Gut, wenn du eine *Zahl* brauchst und keinen Absatz.
Der Wikidata-SPARQL-Endpunkt erlaubt 60 Sekunden pro Abfrage und fünf gleichzeitige
Abfragen pro IP.

---

## 2. Weitere kostenlose Quellen — **ungeprüft, vor Nutzung verifizieren**

Diese wurden nicht nachgeschlagen. Kandidatenliste, keine Fakten.

| Quelle | wofür | vor Nutzung prüfen |
|---|---|---|
| OpenAlex | wissenschaftliche Arbeiten, Zitationen | Schlüsselpflicht, „polite pool" per Mail |
| Crossref | DOIs, Metadaten von Publikationen | Ratenlimits, Mail-Parameter |
| arXiv API | Preprints Physik/Informatik/Mathe | Abfragefrequenz |
| Open Library | Bücher, ISBN, Autoren | Limits |
| GDELT | weltweite Nachrichtenereignisse als Datensatz | Umfang, Lizenz |
| World Bank / Eurostat / Destatis | amtliche Statistik | Schlüssel? Format? |
| Nominatim (OSM) | Ortsnamen → Koordinaten | strenge Nutzungsrichtlinie, eigener Betrieb besser |
| Open-Meteo | Wetter | Schlüsselpflicht |
| PubMed / Europe PMC | Medizin | Limits |

**Regel:** Bevor eine dieser Quellen in ein Tool wandert, öffnet der Coding Agent die
offizielle Doku und schreibt in die Datei, welchen Endpunkt er dort gesehen hat.
Keine Endpunkte aus dem Gedächtnis.

---

## 3. Tool-Vertrag

```python
@register
class WikiLokal(Tool):
    name = "wiki_lokal"
    description = ("Schlaegt einen Begriff in der lokalen Wikipedia-Kopie nach. "
                   "Zuerst hier suchen, bevor eine Netzquelle bemueht wird.")
    permission = Permission.READ
    timeout_s = 5

    async def execute(self, begriff: str) -> ToolResult:
        # kiwix-serve laeuft auf http://127.0.0.1:8080
        # Rueckgabe MUSS enthalten: text, artikel_titel, zim_datei, snapshot_datum
        # snapshot_datum ist Pflicht -> das Modell muss wissen, wie alt das Wissen ist
        ...
```

Zwei Pflichtfelder, die den Unterschied machen:

- **`snapshot_datum`** wandert in den Prompt. Das Modell muss wissen, dass es aus einem
  Stand von z. B. März 2026 antwortet, und das in der Antwort sagen.
- **`sources`** enthält den Artikeltitel. Auch bei lokaler Quelle. Eine Antwort ohne
  Herkunft ist eine Behauptung.

**Reihenfolge im Research Agent:** `wiki_lokal` → bei Treffer fertig.
Kein Treffer oder Frage betrifft etwas nach dem Snapshot-Datum → `wiki_live` →
erst dann `web_search`. Von billig nach teuer, nicht umgekehrt.

---

## 4. Was „dazulernen" in JARVIS ehrlich heißen kann

Drei Dinge, alle billig, keines davon Training:

1. **Nachschlage-Cache.** Tabelle `lookups(begriff, text, quelle, snapshot, geholt_am)`.
   Dieselbe Frage zweimal kostet einmal. Nebeneffekt: Antworten werden konsistent,
   weil sie aus derselben gespeicherten Quelle kommen.
2. **Fakten aus Gesprächen** — das ist Phase 3 und existiert schon. Was *du* sagst,
   nicht was das Modell weiß.
3. **Häufigkeitsauswertung.** Was du oft nachschlägst, schlägt JARVIS vor als
   dauerhaften Eintrag: *„Du hast dreimal nach X gefragt — soll ich das merken?"*

Das ist die ehrliche Obergrenze. Alles, was darüber hinaus nach „er wird klüger"
klingt, ist entweder Memory unter anderem Namen oder Marketing.

---

## 5. Definition of Done, falls du das als Phase baust

1. `kiwix-serve` läuft lokal, `curl` gegen `127.0.0.1:8080` liefert einen Artikel.
2. „Was ist ein Sonnensynchroner Orbit?" wird nachweislich über `wiki_lokal`
   beantwortet — im Tool-Log sichtbar, **kein** `web_search`-Aufruf.
3. Die Antwort nennt den Artikeltitel und das Snapshot-Datum.
4. Eine Frage zu einem Ereignis nach dem Snapshot-Datum geht nachweislich auf
   `wiki_live` über, statt aus dem veralteten Stand zu antworten.
5. `wiki_live` sendet einen konformen User-Agent mit Kontakt. Im Request-Log geprüft.
6. Zweite identische Anfrage trifft den Cache, null neue Netzabfragen.
7. Ohne Netz beantwortet JARVIS Stammwissensfragen weiterhin — Test mit gekappter
   Verbindung.
