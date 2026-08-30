# Was Noah tun muss — jeder Punkt genau

> Stand 30.08.2026. Jede Zahl hier ist gerechnet oder gemessen, nicht
> geschätzt. Wo etwas ungeprüft ist, steht es dabei.

Vier Punkte, nach Wirkung sortiert. **Nichts davon eilt.** Wenn du nur eines
machst: Punkt 1.

---

## 1. Die Messung — die einzige offene Frage, die ich allein nicht klären kann

### Worum es geht

Ich habe die 18 Werkzeugbeschreibungen von **4.601 auf 9.736 Zeichen**
verdoppelt (nach der Methode aus Microsofts EasyTool: einheitliches Format,
jedes Verwechslungspaar nennt das andere Werkzeug beim Namen). Diese Texte
gehen bei **jedem einzelnen Modellaufruf** mit — rund **1.150 → 2.434 Token**
zusätzlich, jedes Mal.

Ob das die Werkzeugwahl wirklich besser macht, ist bis heute **eine
Behauptung**. Die Messstrecke steht, beide Textstände sind archiviert, aber
ohne echtes Modell ist sie nie gelaufen. Du hast einen Groq-Key, ich nicht.

### ⚠️ Zuerst: das passt nicht so, wie ich es dir zuerst gesagt habe

Ich hatte dir `--laeufe 3` vorgeschlagen. **Das sprengt dein Tageskontingent.**
Nachgerechnet:

| Lauf | Token | Groq-Gratis-Limit: 200.000/Tag |
|---|---|---|
| `--laeufe 3 --texte nachher` | ~250.700 | ❌ passt allein schon nicht |
| beide Sätze mit `--laeufe 3` | ~385.900 | ❌ fast das Doppelte |
| **beide Sätze mit `--laeufe 1`** | **~128.600** | ✅ passt an einem Tag |

Die Rechnung: 30 Fälle × (Systemprompt + Auftrag + Antwort). Beim alten
Textsatz sind das ~1.502 Token je Aufruf, beim neuen ~2.786.

### Die zwei Befehle

```
cd C:\Users\Noah\JARVIS
python -m scripts.plantest --laeufe 1 --texte alt
python -m scripts.plantest --laeufe 1 --texte nachher
```

**Genau in dieser Reihenfolge, mit `--laeufe 1`.** Nicht 3.

### Was passieren wird

- **Es dauert.** Groq erlaubt 8.000 Token/Minute; bei ~2.786 Token je Aufruf
  sind das **knapp drei Aufrufe pro Minute**. 30 Fälle brauchen also grob
  **10–15 Minuten je Befehl**. Das ist normal, nicht kaputt.
- **Du wirst rote Zeilen sehen.** Bei jedem Fall steht, welche Werkzeuge
  erwartet und welche vorhergesagt wurden. Rot heißt „daneben" — genau das
  ist die Messung.
- **Ein Ratenlimit (429) kann den Lauf abbrechen.** Der Provider wiederholt
  zweimal und beachtet `Retry-After`; reicht das nicht, bricht es ab. **Das
  ist nicht schlimm:** seit heute bleiben bereits gefahrene Läufe erhalten
  und landen im Verlauf. Vorher wären sie samt verbrauchtem Kontingent weg
  gewesen — das war ein echter Fehler, den ich beim Nachrechnen gefunden und
  behoben habe.

### Was ich brauche

**Die letzten ~15 Zeilen jeder Ausgabe**, ab der Zeile, die so aussieht:

```
   node-F1 0.xxxx   edge-F1 0.xxxx   Leer 1.0000 (6/6)
```

Kopier einfach alles ab da bis zum Ende. Daraus werte ich aus, ob die
längeren Texte ihr Geld wert waren. **Wenn nicht, nehme ich sie zurück** —
das ist der Sinn der Messung, nicht ihre Bestätigung.

### Was du NICHT tun musst

Nichts vorher aufräumen, nichts löschen. Der Verlauf hängt an
(`tests/plandaten/verlauf.jsonl`), er überschreibt nichts.

---

## 2. Die zwei CDSE-Werte — Satellitenbilder und NDVI

**Vollständige Anleitung: `docs/BESCHAFFUNG.md`, Abschnitt 2.**

Kurz, weil der Punkt dort ausführlich steht:

- Kostenloses Konto auf `dataspace.copernicus.eu`, keine Kreditkarte.
- ⚠️ **Die Falle:** „OAuth clients" gibt es nur im **Sentinel-Hub**-Dashboard
  (`shapps.dataspace.copernicus.eu/dashboard/#/account/settings`), nicht im
  Copernicus Browser. Der Link „Dashboard" in der Fußzeile führt auf eine
  Infoseite — **das war der Grund, warum du es nicht gefunden hast**, und der
  Fehler stand in unserer eigenen `.env.example`.
- ⚠️ Beim Anlegen das Häkchen **„single-page application (SPA)" NICHT** setzen.
- ⚠️ Das Secret erscheint **genau einmal**. Sofort kopieren.

```
CDSE_CLIENT_ID=sh-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
CDSE_CLIENT_SECRET=...
```

**Was es freischaltet:** das Satellitenbild eines Ortes — und `satellite_compare`
(Vegetationsverlust in Hektar), denn NDVI kommt aus **demselben** Zugang.

**Was es NICHT braucht:** die Szenensuche und die Überflüge laufen schon
ohne. Nur das gerenderte Bild hängt daran.

**Dein Kontingent danach:** 10.000 Anfragen und 10.000 Processing Units pro
Monat. Ein Vergleich von 1 km × 1 km kostet rund 0,1 PU — du reizt das nicht
ansatzweise aus.

---

## 3. Der Auftragstext für Abschnitt 8 (MÄRKTE) — harter Blocker

**Er liegt nicht im Repo.** In `docs/FIX-06.md` steht nur der Name in der
Kopfzeile: *„5 Design-System → 6 COMMAND CENTER → 7 WELT-NETZ → 8 MÄRKTE"*.
Du hattest ihn im Chat geschickt; der Chat ist weg, die Datei hat ihn nie
gesehen.

**Ich rate ihn nicht.** Ohne den Text weiß ich nicht: Aktien? Indizes?
Währungen? Rohstoffe? Krypto? Welche Ansicht, welche Zonen, welche Zusagen?

**Schick ihn einfach nochmal.** Dann baue ich — die Anbieterlandschaft ist
schon recherchiert und steht in `docs/BESCHAFFUNG.md` §4, inklusive der zwei
Anbieter, die man ausdrücklich **nicht** nehmen sollte:

- **Twelve Data (Gratis)** — genau unser Fall ist ausgeschlossen: *„The data
  cannot be displayed to users."* Anzeigen kostet 79 USD/Monat.
- **Yahoo / yfinance** — der bequemste Weg zu DAX-Daten und der einzige
  geprüfte, dessen AGB die Nutzung dem Wortlaut nach **auch privat** nicht
  deckt.

---

## 4. Drei Zeilen in deiner `.env`

### `JARVIS_TOKEN` — fehlt bei dir

Aus deinem Startlog vom 27.08.2026. Ohne die Zeile würfelt JARVIS bei
**jedem Start** einen neuen — dein Browser-Tab ist danach abgemeldet.

```
JARVIS_TOKEN=<ein langer Zufallswert, egal welcher>
```

Nimm irgendwas Langes, es ist nur dein eigener Zugang.

### `DATEI_WURZELN` — ohne das tun zwei Werkzeuge nichts

Die Ordner, die JARVIS **lesen** darf. Mehr nicht — nie schreiben, nie
löschen.

```
DATEI_WURZELN=C:\Users\Noah\Documents;C:\Users\Noah\JARVIS-Vault
```

Unter Windows ist das Trennzeichen ein **Semikolon**. Ordner, die es nicht
gibt, fallen still weg — ein Tippfehler öffnet also nichts Unerwartetes.

Ohne die Zeile sagen `datei_suchen` und `datei_lesen` ehrlich *„nicht
eingerichtet"* statt *„nichts gefunden"*. Der Unterschied ist Absicht.

### `KALENDER_QUELLE` — Pfad oder Abo-Adresse

```
KALENDER_QUELLE=C:\Users\Noah\Downloads\kalender.ics
```
oder
```
KALENDER_QUELLE=https://calendar.google.com/calendar/ical/.../basic.ics
```

⚠️ **Diese URL *ist* das Geheimnis** — wer sie hat, sieht deinen Kalender.
Sie gehört in die `.env` und **nirgendwo sonst hin**, auch nicht in einen
Chat. JARVIS folgt bei dieser Adresse deshalb auch keinen Weiterleitungen.

Ohne die Zeile sagt `kalender` *„nicht eingerichtet"* und liefert **keine
leere Terminliste** — der Unterschied zwischen „du hast frei" und „ich weiß
es nicht".

---

## Zwei Entscheidungen, wenn du magst

Beides ohne Eile, beides kann ich nicht für dich entscheiden.

### `MAX_KARTEN` von 5 auf 4?

Noahs Bewegtbild-Vorlage zeigt **vier** Meldungskarten, der Code kappt bei
**fünf**. Aber: die 5 ist eine **Zusage aus FIX-02 Abschnitt 5** und steht an
zwei Stellen — im Backend (`api/weltlage.py:39`), das bis `MAX_KARTEN × 2`
Kandidaten prüft und erst danach kappt, und im Frontend, das sie nur
spiegelt.

Vorn allein auf 4 zu gehen hieße: eine bereits geholte, geprüfte und
angereicherte Meldung wegwerfen. **Wenn 4, dann an beiden Stellen und mit
geänderter Zusage.** Deine Entscheidung.

### Welcher TIFF-Leser für NDVI?

`satellite_compare` bekommt seine NDVI-Werte als **FLOAT32-GeoTIFF** von
Sentinel Hub. Die Auswertehälfte steht schon — `core/satellite/analysis.py`
rechnet aus veränderten Pixeln bereits Hektar. Es fehlt nur: GeoTIFF →
`list[float]`.

- **`Pillow`** — steht seit gestern ohnehin in `requirements.txt` (die Tests
  brauchen es) und liest 32-Bit-Float-TIFF im Modus `F`. **Keine neue
  Abhängigkeit.** Mein Vorschlag.
- **`rasterio` / GDAL** — der Standardweg für Geodaten, aber eine
  **Stack-Änderung** nach `CLAUDE.md` und ein schwerer Brocken.

⚠️ **Ungeprüft:** dass Pillow dieses konkrete TIFF sauber liest, habe ich
**nicht** getestet — dafür bräuchte ich einen echten Abruf, also deine
Zugangsdaten. Ich würde es zuerst mit Pillow versuchen und erst wechseln,
wenn es scheitert.

---

## Was ich in der Zwischenzeit machen kann

Alles außer Punkt 3. Ohne die vier Punkte oben kann ich weiter aufräumen,
prüfen und absichern — aber **nichts Neues belegen**. Ab da wäre es
Behauptung, und genau das tut dieses Projekt nicht.
