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

### Geprüft: Es gibt keine weiteren Blitzer unter anderen Tags

Blitzer werden in OSM nicht einheitlich getaggt, also lag die Frage nahe, ob
unter anderen Schlüsseln noch Anlagen liegen, die die Pipeline übersieht.
Erhoben mit `explore-tagging.ts`, bewertet mit `assess-candidates.ts`
(Baden-Württemberg, Abgleich gegen den gebauten Datensatz, Radius 30 m):

| Variante | Treffer | davon neu | Ergebnis |
|---|---:|---:|---|
| `node[enforcement]` | 11 | 0 | Zusatztag auf bekannten Kameras |
| `node[speed_camera]` | 60 | 0 | Zusatztag auf bekannten Kameras |
| `node[surveillance:type=ALPR]` | 57 | 57 | **keine Blitzer**, siehe unten |
| `node[man_made=surveillance][surveillance:zone=traffic]` | 424 | 419 | **keine Blitzer**, siehe unten |
| `way[highway=speed_camera]` | 0 | — | existiert nicht |
| `node[man_made=surveillance][enforcement]` | 0 | — | existiert nicht |
| `node[device=speed_camera]` | 0 | — | existiert nicht |

**Ergebnis: keine einzige zusätzliche Anlage.** Die beiden bestehenden
Selektoren erfassen alles, was in OSM als Blitzer erfasst ist.

Die ersten beiden Varianten sind Zusatz-Tags: Jeder einzelne Treffer liegt
innerhalb von 30 m einer bereits bekannten Kamera.

Die beiden grossen Töpfe sehen nur nach Ausbeute aus. Was tatsächlich
dahintersteckt, zeigen die Tags der neuen Kandidaten:

- **ALPR** (Kennzeichenerfassung) ist überwiegend Parkhaus-Infrastruktur —
  30 von 57 tragen `surveillance:zone=parking`, dazu Betreiber wie
  „Parkdepot GmbH" und Objekte wie „Parkhaus Lohgerbe". Der Rest ist
  Fahrzeiterfassung der Stadt Stuttgart zur Reisezeitmessung
  (`note=Fahrzeiterfassung (B27-Weinsteige)`). Kennzeichen lesen heisst
  nicht Geschwindigkeit messen, und keine dieser Anlagen verschickt Bussgelder.
- **`surveillance:zone=traffic`** ist Verkehrsbeobachtung. Grösster Betreiber
  ist die Strassenverkehrszentrale Baden-Württemberg (65 Objekte), dazu die
  Autobahn GmbH und Städte. 73 sind schwenkbar (`camera:type=panning`), 68
  Dome-Kameras — Bauformen, die für eine Geschwindigkeitsmessung technisch
  nicht taugen. Unter den Beispielen findet sich eine
  „Haltestellenüberwachung Europaplatz". Kein einziges Objekt trägt ein
  `enforcement`-Tag.

Zusätzlich als Kontrollgruppe gezählt: **168 `highway=speed_display`** in
Baden-Württemberg. Das sind Dialog-Displays („Sie fahren 47"), die nichts
ahnden. Sie stehen exemplarisch für die Falle: Eine breit gefasste Abfrage
hätte den Datensatz um mehrere hundert Einträge „wachsen" lassen und die App
dabei schlechter gemacht — jeder Fehlalarm entwertet auch die richtigen
Warnungen.

Diese Erhebung gilt für Baden-Württemberg und den Datenstand unten. Bei
einem späteren Update lohnt sich eine Wiederholung, weil sich
Tagging-Konventionen in OSM ändern.

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

## Tempolimit-Datensatz (Spec 4b, Phase 6)

Zweiter, völlig anders dimensionierter Datensatz: `maxspeed` auf
Strassensegmenten, für das Map-Matching. Die Spec befürchtet, dass ein
Bundesland allein dreistellige MB ergibt, und sieht dann eine Reduktion auf
`motorway + trunk + primary + secondary` vor.

**Mengengerüst Baden-Württemberg** (`npx tsx scripts/count-speedlimits.ts DE-BW`),
gezählt sind Wege mit gesetztem `maxspeed` und deren Stützpunkte:

| Klasse | Wege | Stützpunkte | Punkte/Weg |
|---|---:|---:|---:|
| motorway | 5 657 | 29 994 | 5,3 |
| trunk | 5 613 | 24 484 | 4,4 |
| primary | 28 874 | 118 198 | 4,1 |
| secondary | 58 094 | 329 289 | 5,7 |
| tertiary | 51 538 | 334 332 | 6,5 |
| unclassified | 18 557 | 143 230 | 7,7 |
| residential | 185 484 | 1 131 998 | 6,1 |
| **Summe** | **353 817** | **2 111 525** | 6,0 |
| davon reduziert | 98 238 | 501 965 | 5,1 |

Nicht die Wegzahl bestimmt die Dateigrösse, sondern die Stützpunktzahl —
ein Weg kann zwei Punkte haben oder zweihundert.

**Überschlag im Rohformat** (2 × Float32 pro Punkt, 4 Byte Kopf pro Weg,
ohne Vereinfachung, ohne Kachel-Overhead):

- voller Satz: **17,5 MB**
- reduziert: **4,2 MB**

**Ergebnis: Die Reduktion ist nicht nötig.** 17,5 MB für ein Bundesland
liegen weit unter der dreistelligen Grenze, ab der die Spec zurückrudern
wollte — und das ist der Wert *vor* Douglas-Peucker. Die App kann also auch
in der Stadt ein Tempolimit anzeigen, nicht nur auf Autobahn und Landstrasse.

Hochgerechnet auf Deutschland (Baden-Württemberg ist rund ein Zehntel der
Fläche, bei überdurchschnittlicher Strassendichte) liegt der volle Satz in
der Grössenordnung 150–250 MB. Als App-Bundle unmöglich, als
Nachlade-Datensatz pro Bundesland genau das, was Spec 4b vorsieht.

**Was dieser Überschlag noch nicht enthält** — und warum die Phase-6-DoD zu
Recht eine gemessene Zahl verlangt:

1. Douglas-Peucker entfernt Punkte auf geraden Abschnitten. Wie viel, hängt
   am Strassenverlauf; auf Autobahnen viel, in Wohngebieten wenig.
2. Kachelung nach dem 0,05-Grad-Gitter zerschneidet Wege an Kachelgrenzen.
   Jeder Schnitt kostet einen zusätzlichen Stützpunkt und einen weiteren
   Wegkopf. Bei einer Autobahn, die zwanzig Kacheln durchquert, ist das
   spürbar.
3. Pro Kachel kommt ein Dateikopf dazu, und der Dateisystem-Overhead bei
   mehreren tausend kleinen Dateien ist nicht null.

Punkt 2 ist der, der den Überschlag am ehesten sprengt. Gemessen wird beim
Build.

## Frankreich und der Zonenmodus (Phase C)

**4012 Anlagen**, aus 11708 OSM-Rohtreffern, OSM-Stand 30.07.2026, 298 KB.
Mit Fahrtrichtung 39,6 %, mit Tempolimit 83,9 %, Rotlicht oder kombiniert 693.

In Frankreich darf die App nicht punktgenau warnen. Seit dem 03.01.2012 ist
der deutliche und unmittelbare Hinweis auf eine Messstelle verboten; erlaubt
ist nur der allgemeine Hinweis auf einen Gefahrenbereich mit Mindestlänge —
300 m innerorts, 2000 m auf Land- und Nebenstrassen, 4000 m auf Autobahnen.
Verstoss: bis 1500 Euro, Einziehung des Geräts.

`scripts/build-zones.ts` erzeugt daraus `cameras.FR.zones.json`:

| | |
|---|---|
| Anlagen | 4012 |
| Zonen | **2579** (1433 zusammengefasst) |
| kleinster Radius | 150 m |
| grösster Radius | 5998 m |
| Dateigrösse | 101 KB |

Die Zonendatei enthält **ausschliesslich Mittelpunkt und Radius**. Nicht die
Zahl der enthaltenen Anlagen, nicht ihre Koordinaten, nicht ihren Typ, nicht
ihr Tempolimit. Aus einer Zone mit einer einzigen Anlage liesse sich sonst
deren Position zurückrechnen, und der Radius wäre Dekoration. Ein Test
durchsucht den Rohtext der Datei nach solchen Feldern.

### Die Annahme: Strassentyp aus maxspeed

Der Zonenradius hängt am Strassentyp, und den kennt der Datensatz nicht. Er
trägt nur `maxspeed`. Abgeleitet wird:

| maxspeed | angenommener Typ | Radius |
|---|---|---:|
| ≤ 50 | innerorts | 150 m |
| 60–90 | Landstrasse | 1000 m |
| ≥ 100 | Autobahn | 2000 m |
| unbekannt | Autobahn | 2000 m |

**Das ist eine Annahme, keine Messung.** Sie irrt sich bei einer innerorts
gelegenen Schnellstrasse mit Tempo 70 und bei einer Landstrasse mit Tempo 50.
Bei unbekanntem Tempolimit gilt bewusst die längste Zone — in Frankreich
betrifft das 644 der 4012 Anlagen. Im Zweifel die unschärfere Zone, weil eine
zu kurze Zone der rechtlich problematische Fall ist und eine zu lange nur der
unpräzise.

**Der saubere Weg** wäre der `highway`-Tag der zugehörigen Strasse. Der steht
heute nicht im Datensatz, weil die Pipeline nur die Kamera-Objekte holt und
nicht die Strassen, auf denen sie stehen. Das nachzuziehen hiesse, für jede
Anlage die nächstgelegene Strasse zu bestimmen — machbar zur Build-Zeit, aber
eine eigene Aufgabe. Offener Punkt.

### Was beim Bauen aufgefallen ist

Das Zusammenfassen überlappender Zonen kaskadierte: Werden A und B zu einer
grösseren Zone, überlappt die anschliessend C, wird grösser, überlappt D. An
Deutschland gemessen entstand so eine Zone mit **85 km Radius**. Die Regelung
erlaubt das Zusammenfassen zwei dicht aufeinanderfolgender Zonen, nicht eine
Kette durch halb Europa — und als Hinweis wäre eine 85-km-Zone wertlos.
Obergrenze jetzt 6000 m, das Anderthalbfache der längsten Mindestlänge.

## Offene Rechtsfragen

Diese Liste ist Teil des Datenstands, nicht Beiwerk: Über das Länder-Gate
entscheidet sich, ob die App in einem Land scharf ist. Ein Eintrag hier
bedeutet, dass die Warnung dort abgeschaltet bleibt, bis jemand mit
einschlägiger Qualifikation die Frage klärt.

Grundlage der Tabelle in `app/src/config.ts`: ADAC, Juristische Zentrale,
Übersicht Radarwarner und Blitzer-Apps im Ausland, Stand 5/2025, ausdrücklich
ohne Gewähr.

### 1. Österreich — POI-Warner oder Radardetektor?

**Status im Gate: `strittig`, Warnung aus.**

Der bisherige Eintrag im Projekt lautete `§ 98a KFG`, Warnung verboten.

Die Quelle beschreibt Österreich anders: Verboten seien Radarwarngeräte, mit
denen Verkehrsüberwachungseinrichtungen **beeinflusst oder gestört** werden
können. GPS-Geräte mit POI-Warner als Ankündigungsfunktion seien dagegen
erlaubt. Strafrahmen bis 10.000 Euro, Einziehung des Geräts.

Das ist genau die Unterscheidung, die dem Gate bis jetzt fehlte: **aktiver
Radardetektor** gegen **Datenbank-Warner**. Static ist Letzteres — er misst
nichts, stört nichts, sondern vergleicht eine GPS-Position mit einer Liste.

Eine der beiden Aussagen ist falsch. Das aufzulösen braucht den Gesetzestext
des KFG in geltender Fassung und jemand, der ihn lesen kann. Bis dahin bleibt
Österreich auf `aus` — nicht weil das die richtige Antwort wäre, sondern weil
es die sichere ist.

### 2. Kroatien, Rumänien, Ungarn — widersprüchliche Quelle

**Status im Gate: `unklar`, Warnung aus.**

Die Quelle nennt für diese drei Länder weder ein Mitführ- noch ein
Benutzungsverbot, die Anmerkung nennt aber Radarwarner beziehungsweise
Störsender als verboten. Das ist zu widersprüchlich, um als belegt zu gelten.
Der Widerspruch steht am Eintrag und wird dort ausdrücklich **nicht**
aufgelöst.

### 3. Fünfzehn Länder ohne Aussage zur POI-Funktion

**Status im Gate: `unklar`, Warnung aus.**

Bulgarien, Dänemark, Griechenland, Italien, Kroatien, Lettland, Litauen,
Norwegen, Polen, Rumänien, Schweden, Slowakei, Slowenien, Türkei, Ungarn.

Die Quelle nennt jeweils ein Benutzungsverbot, sagt aber nichts dazu, ob es
den Datenbank-Warner einschliesst. Solange das offen ist, warnt die App dort
nicht.

Der Hinweistext in der App sagt in diesen Fällen ausdrücklich, dass die
Rechtslage **nicht belegt** ist — nicht, dass sie verboten sei. Das ist ein
Unterschied, und die App soll nicht behaupten, was sie nicht weiss. Ein Test
prüft das.

### 4. Länder ganz ohne Eintrag

Irland, Grossbritannien, Estland, Island, Malta, Zypern, Albanien, Bosnien,
Nordmazedonien, Montenegro, Kosovo, Moldau, Ukraine, Liechtenstein, Andorra,
Monaco, San Marino kommen in der Quelle nicht vor und haben deshalb
absichtlich keinen Eintrag. Damit greift der Standard: keine Warnung. Ein
fehlender Eintrag ist eine Aussage — wir wissen es nicht.

### Wo punktgenau gewarnt wird

Nur dort, wo die Quelle die POI-Funktion ausdrücklich erlaubt: Belgien,
Finnland, Luxemburg, Niederlande, Portugal, Serbien, Spanien, Tschechien.
Frankreich warnt im Zonenmodus. Alle anderen Länder warnen nicht.

Ein Test hält diese Liste fest. Wächst sie, muss jemand die Quelle
nachgelesen haben.

## Wann die App den Grenzübertritt merkt (Phase B.4)

Die Gate-Tabelle sagt, **was** in einem Land erlaubt ist. Sie sagt nicht,
**wann** die App merkt, dass es soweit ist. Das entscheidet die Hysterese in
`app/src/core/country.ts`, und der Wert dafür war bis B.4 ein Behelf.

### Gemessen, nicht geschätzt

Messtrack: `app/fixtures/grenze-kehl-strasbourg.gpx` — Europabrücke von Kehl
nach Strasbourg, 381 Punkte, 13,9 m/s, ein Fix je etwa 14 m. Die Stelle ist
ausgesucht, nicht bequem: Die Grenze verläuft dort im Rhein, quer zur
Fahrtrichtung, Deutschland verbietet die Warnung, Frankreich erlaubt sie in
Zonenform. Ein Fehler in beide Richtungen hat Folgen.

Gemessen wurde, wie weit hinter der Grenze der Moduswechsel `aus -> zone`
greift:

| `MINDESTABSTAND_GRENZE_M` | Wechsel liegt hinter der Grenze |
|---|---|
| 3000 m (alter Wert) | 2988 m |
| 2000 m | 1988 m |
| 1000 m | 987 m |
| 600 m | 598 m |
| **400 m (neu)** | **389 m** |
| 300 m | 292 m |

Die Spec fordert 0 bis 500 m hinter der Grenze. Der alte Wert lag um Faktor
sechs daneben — er schaltete die Zonenwarnung erst mitten in Strasbourg frei.
Er stammte aus der Zeit der handeingetragenen Umrisse, deren Fehler unbekannt
war.

### Warum 400 m und nicht 500 m

Der neue Wert ist **abgeleitet, nicht gewählt**: das Doppelte von
`TOLERANZ_GRENZE_M` (200 m), der Vereinfachungstoleranz der generierten
Umrisse an Landgrenzen.

- **Untergrenze.** Ein Schwellwert unterhalb des Vereinfachungsfehlers prüft
  gegen den eigenen Fehler und damit nichts. Liegt die generierte Linie um die
  volle Toleranz nach Osten verschoben, dann liegt die tatsächliche Grenze
  200 m westlich von ihr — ein Wechsel 200 m hinter der Linie wäre ein Wechsel
  genau *auf* der Grenze. Erst 400 m stellen sicher, dass die Position auch im
  schlechtesten Fall der Vereinfachung im neuen Land liegt.
- **Obergrenze.** 500 m ist das geforderte Fenster. Ein Schwellwert genau dort
  hätte keine Luft mehr für den Fixabstand (14 m) und die fünf bestätigenden
  Fixes (70 m).

Der Wert ist im Code an `TOLERANZ_GRENZE_M` gekoppelt. Wird die Toleranz im
Generator geändert, wandert der Schwellwert mit, und `tests/grenze.test.ts`
schlägt an, falls das Fenster dabei reisst.

### Was die Messung nebenbei gefunden hat

**Der Grenzübertritt nach Frankreich wurde nicht angesagt.** Der
Hintergrund-Task verglich `darfPunktWarnen`, ein Ja/Nein. Beim Wechsel von
`aus` auf `zone` bleibt dieser Wert in beiden Fällen `false` — der Wechsel
fiel also stillschweigend aus. Gemessen: ein Moduswechsel, null Ansagen. Der
Task vergleicht jetzt den Modus.

**Die Ansage hätte in Frankreich ein verbotenes Wort enthalten.**
`landwechselText` lautete in beiden Richtungen „Blitzerwarnung aktiviert /
deaktiviert". „Blitzer" steht auf `VERBOTENE_ZONENWOERTER` — es beim Übertritt
nach Frankreich zu sagen, benennt die Gefahr. Jetzt pro Modus ein eigener
Text: „Blitzerwarnung aktiviert" nur im Punktmodus, „Hinweise aktiviert" im
Zonenmodus, „Warnung deaktiviert" beim Abschalten. Der Ausschalttext ist
absichtlich neutral, weil er beim Verlassen Frankreichs gesprochen wird und
damit unter Umständen noch auf französischem Gebiet.

**Der Replay meldete grün, ohne zu prüfen.** Der Grenztrack hat keine Kameras.
`npm run replay:all` schickte ihn durch die Punktlogik, fand null Warnungen,
erwartete null und meldete „OK" — ein grünes Ergebnis für eine Prüfung, die
nicht stattgefunden hat. Die Fixture-Erwartung hat jetzt ein Feld
`landwechsel`, und die CLI führt für solche Tracks die Landeslogik aus und
nennt die gemessene Zahl:

```
grenze-kehl-strasbourg
  Modus:             Landeserkennung (Grenzübertritt)
  Moduswechsel:      zone  (erwartet zone)  OK
    Fix  99: aus -> zone, 389 m hinter der Datengrenze
  Gründe:
    bestaetigt           353x
    grenznah             24x
    wartet_bestaetigung  4x
```

Die Gründe belegen, dass die richtige Bremse greift: 24 Fixes wurden wegen
Grenznähe gehalten, nur 4 vom Fixzähler. Bremste allein der Zähler, käme der
Wechsel schon 70 m hinter der Grenze — innerhalb des Vereinfachungsfehlers und
damit möglicherweise davor.

### Was weiter offen ist

Die Umrisse sind gegen **Natural Earth** gemessen, nicht gegen die
tatsächliche Grenze. `scripts/reference-locations.json` ist bewusst leer, und
eine unabhängige Grenzreferenz gibt es im Projekt nicht. Der Abstand von 389 m
ist also ein Abstand zur *Datengrenze*; wie weit die von der tatsächlichen
Grenze abweicht, ist durch die Vereinfachungstoleranz nach oben abgeschätzt,
aber nicht gemessen. Genau deshalb ist der Schwellwert das Doppelte der
Toleranz und nicht das Einfache.

**Der Zonenmodus ist im Hintergrund-Task noch nicht verdrahtet.** `core/zone.ts`
und der Replay decken ihn ab, aber `location/task.ts` gibt in Frankreich noch
keine Zonenansage aus — es wird dort also angesagt, dass Hinweise aktiv sind,
und danach kommt keiner. Das Laden der Zonendatei hängt am
länderweisen Datensatzformat (Phase A.4) und ist dort vermerkt. Bis dahin
bleibt es bei „gar nicht warnen", der sicheren Richtung.

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
