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
| Anlagen nach Deduplizierung | **5053** |
| OSM-Rohtreffer davor | 14102 |
| Gitterzellen belegt | 2502 |
| mit Tempolimit | 4398 (87,0 %) |
| mit Fahrtrichtung | 1816 (35,9 %) |
| Rotlicht / kombiniert | 641 |
| Dateigrösse | 362 KB |

## Pro Bundesland

Alle Zahlen nach Deduplizierung.

| Code | Bundesland | Anlagen | roh | /1000 km² | Richtung | maxspeed |
|---|---|---:|---:|---:|---:|---:|
| DE-BW | Baden-Württemberg | 1509 | 4044 | 42,2 | 21 % | 86 % |
| DE-NW | Nordrhein-Westfalen | 926 | 2414 | 27,1 | 46 % | 90 % |
| DE-HE | Hessen | 835 | 2297 | 39,5 | 36 % | 94 % |
| DE-NI | Niedersachsen | 549 | 1689 | 11,5 | 42 % | 86 % |
| DE-SN | Sachsen | 282 | 888 | 15,3 | 56 % | 88 % |
| DE-BB | Brandenburg | 219 | 592 | 7,4 | 30 % | 89 % |
| DE-BY | Bayern | 132 | 320 | 1,9 | 43 % | 60 % |
| DE-MV | Mecklenburg-Vorpommern | 104 | 313 | 4,5 | 34 % | 92 % |
| DE-RP | Rheinland-Pfalz | 86 | 229 | 4,3 | 29 % | 85 % |
| DE-SH | Schleswig-Holstein | 80 | 235 | 5,1 | 54 % | 81 % |
| DE-TH | Thüringen | 78 | 272 | 4,8 | 55 % | 94 % |
| DE-BE | Berlin | 56 | 195 | 62,9 | 68 % | 96 % |
| DE-SL | Saarland | 54 | 162 | 21,0 | 22 % | 78 % |
| DE-HB | Bremen | 52 | 150 | 123,8 | 33 % | 35 % |
| DE-ST | Sachsen-Anhalt | 52 | 183 | 2,5 | 44 % | 87 % |
| DE-HH | Hamburg | 41 | 119 | 54,3 | 41 % | 88 % |

Die Summe der Gebietszahlen (5055) liegt zwei über der Gesamtzahl: zwei
Anlagen direkt auf einer Landesgrenze werden global noch einmal
zusammengefasst.

### Warum die Zahl gegenüber dem ersten Build gesunken ist

Der erste Build lieferte 6073 Anlagen, dieser 5053. Die Differenz ist kein
Datenverlust, sondern die Korrektur der Kamerapositionen: Vorher standen die
über 30 m versetzten Relations-Einträge als zusätzlicher Geisterblitzer neben
der echten Anlage. Jetzt sitzen sie auf dem tatsächlichen Kamera-Node,
fallen mit ihr zusammen und werden zusammengefasst.

Zwei Kennzahlen belegen, dass es eine Verbesserung und keine Verschlechterung
ist:

- Die **Fahrtrichtung** ist von 25,6 % auf 35,9 % gestiegen. Die Relationen
  erben jetzt die Tags ihres Kamera-Nodes, und dort steht die Richtung.
- Das **Tempolimit** ist von 84,8 % auf 87,0 % gestiegen, aus demselben Grund.

Wären beim Zusammenfassen echte Anlagen verlorengegangen, müssten diese
Quoten fallen statt steigen.

### Die regionalen Unterschiede sind gewaltig

Baden-Württemberg hat **42,2 Anlagen pro 1000 km², Bayern 1,9** — Faktor 22
zwischen den beiden grössten Flächenländern. Baden-Württemberg allein stellt
30 % aller Einträge in Deutschland.

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

### Warum der Relations-Mittelpunkt nicht der Kamerastandort ist

Naheliegend wäre, für eine Enforcement-Relation den von Overpass gelieferten
Mittelpunkt (`out center`) zu nehmen. Das ist falsch: Der Mittelpunkt ist der
Schwerpunkt **aller** Mitglieder, also inklusive der überwachten
Straßenabschnitte (`from`, `to`, `force`). Er liegt damit systematisch neben
der Kamera.

Nachgemessen an Baden-Württemberg — Abstand zwischen Relations-Mittelpunkt
und dem tatsächlichen `device`-Node, 1454 vergleichbare Relationen:

| Abstand | Anzahl |
|---|---:|
| ≤ 10 m | 638 |
| 10–30 m | 549 |
| 30–100 m | 237 |
| 100–300 m | 25 |
| 1394 m | 1 |

Median 12 m, p90 44 m, p99 118 m.

Die ersten beiden Zeilen sind harmlos — was innerhalb von 30 m liegt, fasst
der Dedupe ohnehin mit der echten Kamera zusammen. **Die 263 Relationen
darüber sind das Problem:** Sie werden nicht zusammengefasst und landen als
zusätzlicher, falsch positionierter Eintrag im Datensatz, während die echte
Kamera separat daneben steht. Das erzeugt Warnungen an Stellen, an denen
nichts steht — und in der Nähe einer echten Anlage ist das besonders
tückisch, weil es wie ein plausibler Treffer aussieht.

Die Pipeline löst deshalb die `device`-Mitglieder der Relation auf und
verwendet deren Koordinaten. Der Mittelpunkt bleibt nur als Notbehelf für
Relationen ohne verwertbaren device-Node (in BW 24 von 1478).

Nebeneffekt, der ebenfalls stimmt: Eine Abschnittskontrolle mit Kameras an
beiden Enden ergibt jetzt **zwei** Einträge an den richtigen Stellen statt
einem in der Streckenmitte, wo keine Kamera steht.

## Deduplizierung

Sehr viele Anlagen sind in OSM **doppelt** erfasst: einmal als Kamera-Node und
einmal als Enforcement-Relation für dieselbe Anlage. Zusammengefasst wird alles
innerhalb von 30 m, sofern die Richtungsangaben sich nicht widersprechen.
Bundesweit fallen dadurch 14102 Rohtreffer auf 5053 Anlagen — **64 % der
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
   Faktor 22 zwischen Baden-Württemberg und Bayern (siehe oben) ist das
   deutlichste Beispiel. Die Datenqualität ist nachweislich schlechter als bei
   kommerziellen Anbietern.
2. **Die Fahrtrichtung fehlt bei 64 % der Einträge.** Nur 1816 von 5053
   Anlagen tragen eine verwertbare Richtung. Schritt (e) des Warnalgorithmus
   — Kameras der Gegenrichtung aussortieren — greift damit bei zwei von drei
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
   Auffällig: Bremen hat nur bei 35 % der Anlagen ein Tempolimit, Bayern bei
   60 %, der Rest liegt bei 78–96 %. In diesen beiden Ländern wird die Ansage
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
