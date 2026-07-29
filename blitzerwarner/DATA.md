# Datenlage

Quelle: **OpenStreetMap**, © OpenStreetMap-Mitwirkende, lizenziert unter
**ODbL 1.0**. Abgefragt über die Overpass-API, pro Bundesland.

Diese Datei sagt, was in den Daten steckt und was nicht. Sie ist die Grundlage
für die Entscheidung, ob das Produkt überhaupt Sinn ergibt — und für die
ehrliche Store-Beschreibung später.

**OSM-Datenstand: 29.07.2026.** Zahlen aus `npm run verify-dataset`.

## Deutschland gesamt

| | |
|---|---|
| Anlagen nach Deduplizierung | **6073** |
| OSM-Rohtreffer davor | 10232 |
| Gitterzellen belegt | 2517 |
| mit Tempolimit | 5148 (84,8 %) |
| mit Fahrtrichtung | 1553 (25,6 %) |
| Rotlicht / kombiniert | 596 |
| Dateigrösse | 430 KB |

## Pro Bundesland

Alle Zahlen nach Deduplizierung.

| Code | Bundesland | Anlagen | roh | /1000 km² | Richtung | maxspeed |
|---|---|---:|---:|---:|---:|---:|
| DE-BW | Baden-Württemberg | 1727 | 3020 | 48,3 | 16 % | 83 % |
| DE-NW | Nordrhein-Westfalen | 1109 | 1722 | 32,5 | 37 % | 88 % |
| DE-HE | Hessen | 983 | 1673 | 46,6 | 25 % | 92 % |
| DE-NI | Niedersachsen | 715 | 1165 | 15,0 | 28 % | 81 % |
| DE-SN | Sachsen | 313 | 641 | 17,0 | 38 % | 90 % |
| DE-BB | Brandenburg | 274 | 431 | 9,2 | 21 % | 87 % |
| DE-BY | Bayern | 167 | 247 | 2,4 | 30 % | 57 % |
| DE-MV | Mecklenburg-Vorpommern | 152 | 227 | 6,5 | 19 % | 88 % |
| DE-RP | Rheinland-Pfalz | 108 | 166 | 5,4 | 20 % | 79 % |
| DE-TH | Thüringen | 107 | 198 | 6,6 | 34 % | 92 % |
| DE-SH | Schleswig-Holstein | 95 | 172 | 6,0 | 35 % | 75 % |
| DE-BE | Berlin | 79 | 136 | 88,7 | 33 % | 91 % |
| DE-HB | Bremen | 66 | 103 | 157,1 | 21 % | 32 % |
| DE-ST | Sachsen-Anhalt | 65 | 122 | 3,2 | 26 % | 89 % |
| DE-SL | Saarland | 63 | 121 | 24,5 | 16 % | 79 % |
| DE-HH | Hamburg | 52 | 88 | 68,9 | 29 % | 88 % |

Die Summe der Gebietszahlen (6075) liegt zwei über der Gesamtzahl: zwei
Anlagen direkt auf einer Landesgrenze werden global noch einmal
zusammengefasst.

### Die regionalen Unterschiede sind gewaltig

Baden-Württemberg hat **48,3 Anlagen pro 1000 km², Bayern 2,4** — Faktor 20
zwischen den beiden grössten Flächenländern. Baden-Württemberg allein stellt
28 % aller Einträge in Deutschland.

Der Verdacht lag nahe, dass die Gebietsauswahl für Bayern kaputt ist.
Gegengeprüft mit `npx tsx scripts/crosscheck-region.ts DE-BY`: die Abfrage
über `ISO3166-2` und die unabhängig formulierte Abfrage über
`name` + `admin_level=4` liefern beide exakt **328** Rohtreffer. Die
Gebietsauswahl stimmt also — die Zahl ist echt.

Was sie bedeutet, lässt sich aus den Daten allein **nicht** entscheiden. Zwei
Erklärungen sind möglich und schliessen sich nicht aus: Bayern setzt stärker
auf mobile Messungen und hat real weniger stationäre Anlagen, und/oder die
OSM-Erfassung ist dort deutlich lückenhafter. Welcher Anteil auf welche
Ursache entfällt, klärt nur ein Abgleich mit einer unabhängigen Quelle —
siehe unten.

**Praktische Konsequenz:** In Bayern ist die App nach heutigem Datenstand
kaum brauchbar. Das gehört in die Store-Beschreibung, nicht ins Kleingedruckte.

## Was die Daten abdecken

**Nur stationäre Anlagen.** Mobile Messstellen sind in OSM nicht erfasst und
können es auch nicht sein — sie stehen heute hier und morgen dort. Die App
warnt davor nicht.

Erfasst werden zwei OSM-Objekttypen:

- `node[highway=speed_camera]` — die eigentliche Kamera
- `relation[type=enforcement]` — die Messanlage als Ganzes, mit
  `enforcement=maxspeed`, `average_speed` oder `traffic_signals`

Enforcement-Relationen mit anderen Werten (`toll`, `maxheight`, `maxweight`,
`access`, `oneway`) werden verworfen — das sind keine Blitzer.

## Deduplizierung

Sehr viele Anlagen sind in OSM **doppelt** erfasst: einmal als Kamera-Node und
einmal als Enforcement-Relation für dieselbe Anlage. Zusammengefasst wird alles
innerhalb von 30 m, sofern die Richtungsangaben sich nicht widersprechen.
Bundesweit fallen dadurch 10232 Rohtreffer auf 6073 Anlagen — **41 % der
Rohzahl sind Dubletten**.

Das ist der Grund für den grossen Unterschied zwischen Rohtreffern und
Endergebnis. Die Rohzahl zu berichten wäre irreführend — sie zählt Anlagen
doppelt.

Beim Zusammenfassen gilt eine bewusst vorsichtige Regel für die Fahrtrichtung:
Eine bekannte Richtung wird nur dann übernommen, wenn das Paar aus einem Node
**und** einer Relation besteht, also sicher dieselbe Anlage beschreibt. Bei
zwei Nodes am selben Ort könnte es sich um zwei getrennte Kameras je
Fahrtrichtung handeln — dort bleibt die Richtung `null`, und die App warnt
richtungsunabhängig. Ein Fehlalarm ist ärgerlich, eine ausbleibende Warnung
macht das Produkt kaputt.

## Bekannte Schwächen

1. **Die Abdeckung ist lückenhaft und regional sehr unterschiedlich.** OSM wird
   ehrenamtlich gepflegt; wo niemand Blitzer einträgt, stehen keine drin. Der
   Faktor 20 zwischen Baden-Württemberg und Bayern (siehe oben) ist das
   deutlichste Beispiel. Die Datenqualität ist nachweislich schlechter als bei
   kommerziellen Anbietern.
2. **Die Fahrtrichtung fehlt bei 74 % der Einträge.** Nur 1553 von 6073
   Anlagen tragen eine verwertbare Richtung. Schritt (e) des Warnalgorithmus
   — Kameras der Gegenrichtung aussortieren — greift damit bei drei von vier
   Kameras überhaupt nicht. Die gesamte Last liegt auf dem Peilungsfilter
   (Schritt d), der nur die Richtung vom Fahrzeug zur Kamera kennt. Auf
   Parallelstraßen und bei Gegenfahrbahnen führt das zu Fehlalarmen. Der
   Replay-Test in Phase 3 muss deshalb vor allem den Fall „Kamera auf der
   Gegenfahrbahn **ohne** Richtungsangabe" abdecken, nicht den bequemen Fall
   mit Richtung.
3. **Kein Aktualitätsnachweis.** Ein abgebauter Blitzer verschwindet erst aus
   den Daten, wenn ihn jemand in OSM löscht. Die Daten enthalten also
   potenziell Anlagen, die es nicht mehr gibt, und es fehlen neu aufgestellte.
4. **`maxspeed` ist nicht immer die für den Blitzer geltende Grenze.** Bei
   Abschnittskontrollen und richtungsabhängigen Limits kann die Ansage eine
   falsche Zahl nennen. Im Zweifel lieber ohne Tempoangabe ansagen.
   Auffällig: Bremen hat nur bei 32 % der Anlagen ein Tempolimit, Bayern bei
   57 %, der Rest liegt bei 75–92 %. In diesen beiden Ländern wird die Ansage
   also oft ohne Tempoangabe auskommen müssen.

## Trefferquote gegen bekannte Standorte

**Noch nicht gemessen.**

Die Zahlen oben sagen nur, wie viel in OSM *drinsteht* — nicht, wie viel von
dem, was real existiert, auch erfasst ist. Das ist die eigentlich
entscheidende Zahl, und sie lässt sich nur gegen eine unabhängige Quelle
bestimmen.

Vorgehen: `scripts/reference-locations.json` mit mindestens 10 bekannten
Standorten füllen (Pressemeldungen, Mitteilungen von Städten, eigene
Beobachtung — **nicht** aus OSM und nicht aus dem gebauten Datensatz, sonst
misst der Test sich selbst), dann `npm run verify-dataset`. Ein Eintrag gilt
als Treffer, wenn der Datensatz innerhalb von 150 m eine Kamera kennt.

Das Ergebnis gehört hierher, auch und gerade wenn es schlecht ausfällt.

## Aktualisierung

Die Daten sind eine Momentaufnahme. `npm run build-dataset -- --no-cache`
erzeugt einen neuen Stand. Der OSM-Zeitstempel (`timestamp_osm_base`) wird im
Datensatz mitgeführt und gehört sichtbar in den Einstellungs-Screen der App:
„Stand der Daten: TT.MM.JJJJ, Quelle: OpenStreetMap, ODbL".
