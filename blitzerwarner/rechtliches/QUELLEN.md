# Quellen und Referenzen

**Static** — Offline-Warner für stationäre Blitzer

Stand: 2026-08-01

Woher die Daten und die Angaben in dieser App stammen.

> Diese Datei wird aus `app/src/rechtstexte.ts` erzeugt.
> Änderungen gehören dorthin, sonst sind sie beim nächsten Lauf weg.

## Standorte der Messstellen

OpenStreetMap, © OpenStreetMap-Mitwirkende, Open Database License (ODbL) 1.0 — https://opendatacommons.org/licenses/odbl/1-0/

Abgefragt über die Overpass-API. Berücksichtigt werden highway=speed_camera sowie Enforcement-Relationen; bei letzteren wird die als "device" verknüpfte Anlage verwendet und nicht der Mittelpunkt der Relation, der im Extremfall über einen Kilometer daneben liegt.

Stand und Umfang des mitgelieferten Datensatzes stehen in der App unter "Datenquelle".

## Landesgrenzen für die Länder-Erkennung

Natural Earth, Admin 0 Countries, Massstab 1:10 Mio. — Public Domain, https://www.naturalearthdata.com/

Bewusst NICHT OpenStreetMap: Die Umrisse wären sonst eine abgeleitete Datenbank im Sinne der ODbL, und das Länder-Gate hinge damit an einer Lizenz mit Weitergabepflicht.

Die Linien sind vereinfacht — an Landgrenzen auf 200 m, an Küsten auf 500 m. Der Schwellwert, ab dem die App nach einem Grenzübertritt umschaltet, ist daraus abgeleitet und beträgt das Doppelte der Grenztoleranz.

## Rechtslage in den einzelnen Ländern

ADAC, Juristische Zentrale: Übersicht Radarwarner und Blitzer-Apps im Ausland, Stand 5/2025, ausdrücklich ohne Gewähr.

Wo diese Quelle sich mit anderen Angaben widerspricht, ist das im Projekt als "strittig" vermerkt und der Widerspruch benannt statt aufgelöst. Wo sie keine Aussage zur Funktion gespeicherter Standorte trifft, gilt die Lage als ungeklärt — und dort warnt die App nicht.

## Zitierte Normen und Entscheidungen

Deutschland: § 23 Abs. 1c StVO; Nummer 247 des Bussgeldkatalogs (75 Euro, ein Punkt). OLG Karlsruhe, Beschluss vom 07.02.2023, Az. 2 ORbs 35 Ss 9/23 — die Ordnungswidrigkeit des Fahrers liegt auch vor, wenn der Beifahrer bedient und der Fahrer sich die Warnung zunutze macht.

Österreich: § 98a KFG.

Schweiz: Art. 57b SVG.

Frankreich: Regelung seit dem 03.01.2012 — zulässig ist nur der Hinweis auf einen Gefahrenbereich mit Mindestlänge (300 m innerorts, 2000 m Landstrasse, 4000 m Autobahn), nicht der Hinweis auf eine einzelne Messstelle.

Alle Angaben sind Zusammenfassungen und ersetzen den Gesetzestext nicht.

## Berechnungen

Tacho-Abweichung: UNECE-Regelung Nr. 39. Die Anzeige eines Fahrzeugtachos darf nie weniger als die tatsächliche Geschwindigkeit zeigen und höchstens 0,1 × v + 4 km/h darüber liegen. Die Angabe erscheint nur im Erklärtext, sie löst nichts aus.

Nacht-Erkennung für die Bildschirmhelligkeit: NOAA-Sonnenstandsalgorithmus in der üblichen vereinfachten Form. Als Nacht gilt ein Sonnenstand unter −6 Grad, also das Ende der bürgerlichen Dämmerung.

Entfernungen: Haversine-Formel auf einer Kugel mit 6 371 km Radius. Der Fehler gegenüber einem Ellipsoid liegt bei den hier vorkommenden Entfernungen unter einem halben Prozent.

## Was NICHT als Quelle dient

Keine Community-Meldungen. Keine kommerziellen Blitzerdatenbanken. Keine mobilen Messstellen. Kein Abgleich mit einem Server — es gibt keinen.

---

Keine Rechtsberatung. Diese Texte beschreiben nach bestem Wissen, was die
App tut. Ob die Formulierungen den Anforderungen genügen, muss vor einer
Veröffentlichung jemand mit einschlägiger Qualifikation prüfen.
