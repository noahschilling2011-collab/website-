# Datenlage

Quelle: **OpenStreetMap**, © OpenStreetMap-Mitwirkende, lizenziert unter
**ODbL 1.0**. Abgefragt über die Overpass-API, pro Bundesland.

Diese Datei sagt, was in den Daten steckt und was nicht. Sie ist die Grundlage
für die Entscheidung, ob das Produkt überhaupt Sinn ergibt — und für die
ehrliche Store-Beschreibung später.

<!-- ZAHLEN: eingetragen aus `npm run verify-dataset`, Stand siehe unten. -->

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
   ehrenamtlich gepflegt; wo niemand Blitzer einträgt, stehen keine drin. Die
   Datenqualität ist nachweislich schlechter als bei kommerziellen Anbietern.
2. **Die Fahrtrichtung fehlt bei der grossen Mehrheit der Einträge.** Ohne sie
   kann der Richtungsfilter nur über die Peilung vom Fahrzeug zur Kamera
   arbeiten, nicht über die Blickrichtung der Kamera. Auf Parallelstraßen und
   bei Gegenfahrbahnen führt das zu Fehlalarmen.
3. **Kein Aktualitätsnachweis.** Ein abgebauter Blitzer verschwindet erst aus
   den Daten, wenn ihn jemand in OSM löscht. Die Daten enthalten also
   potenziell Anlagen, die es nicht mehr gibt, und es fehlen neu aufgestellte.
4. **`maxspeed` ist nicht immer die für den Blitzer geltende Grenze.** Bei
   Abschnittskontrollen und richtungsabhängigen Limits kann die Ansage eine
   falsche Zahl nennen. Im Zweifel lieber ohne Tempoangabe ansagen.

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
