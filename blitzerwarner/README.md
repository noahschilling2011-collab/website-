# Blitzerwarner (Arbeitstitel "Static")

Offline-Warner für **stationäre** Blitzer. Kein Backend, kein Account, keine
Werbung, keine Netzwerk-Requests zur Laufzeit.

**Diese App warnt nicht vor mobilen Messstellen.** Das ist keine Lücke, die
später geschlossen wird — es ist eine Produktentscheidung. Mobile Blitzer
brauchen eine Crowd-Datenbank, und die lässt sich ohne Nutzerbasis nicht
aufbauen. Wer davor gewarnt werden will, ist mit Blitzer.de PRO besser bedient.

Gewonnen wird stattdessen auf vier Achsen: **Akku, Datenschutz,
Offline-Fähigkeit, Einfachheit.** Auf Datenqualität verliert das Projekt gegen
kommerzielle Anbieter — siehe [DATA.md](DATA.md), dort steht ehrlich, was drin
ist und was fehlt.

## Rechtlicher Hinweis

§ 23 Abs. 1c StVO verbietet dem Fahrzeugführer den Betrieb und das
betriebsbereite Mitführen von Geräten, die Verkehrsüberwachungsmaßnahmen
anzeigen. Verstoß: 75 € und 1 Punkt (BKat Nr. 247). Nach OLG Karlsruhe,
Beschl. v. 07.02.2023, Az. 2 ORbs 35 Ss 9/23, liegt eine Ordnungswidrigkeit des
Fahrers auch dann vor, wenn der **Beifahrer** die App bedient, sofern der Fahrer
das billigt und sich die Warnung zunutze macht.

Die App zeigt beim ersten Start einen bestätigungspflichtigen Rechtshinweis und
blendet in DE/AT/CH einen dauerhaften, nicht abschaltbaren Banner ein.

Das ist keine Rechtsberatung. Vor einer Store-Veröffentlichung muss das jemand
mit einschlägiger Qualifikation prüfen.

## Stand

| Phase | Inhalt | Status |
|---|---|---|
| 1 | Datenpipeline | gebaut. 5053 Anlagen für Deutschland; Trefferquote gegen unabhängige Quellen offen — siehe DATA.md |
| 2 | Background-Tracking | gebaut, **auf dem Gerät nicht abgenommen**. Messbar mit dem Fahrtenschreiber, siehe unten |
| 3 | Warnlogik + Replay-Test | gebaut. 9 Fixture-Tracks, `npm run replay:all` |
| 4 | UI + Ansage | gebaut, **auf dem Gerät nicht abgenommen** |
| 5 | Akku unter 3 %/h | **nicht gemessen**. Messbar mit dem Fahrtenschreiber |
| 6 | Tempolimit-Datensatz | nicht gebaut. Nur das Mengengerüst gemessen (`scripts/count-speedlimits.ts`) |
| 7 | Map-Matching | nicht gebaut |
| 8 | Meldefunktion | nicht gebaut, und ohne Backend auch nicht vorgesehen |
| 9 | Store-Vorbereitung | offen |
| A | Europa-Datensatz | Mengengerüst gemessen (124 Gebiete), Ausbau offen |
| B | Länder-Gate | gebaut. Umrisse generiert, Grenz-Hysterese am Messtrack nachgezogen |
| C | Zonenmodus Frankreich | gebaut und im Hintergrund-Task verdrahtet |

**Was heisst "auf dem Gerät nicht abgenommen":** Der Code läuft und ist
getestet, aber drei Dinge lassen sich nur im Auto messen — 20 Minuten
lückenloses Tracking bei ausgeschaltetem Display, der Akkuverbrauch, und der
Vergleich gegen den Fahrzeugtacho. Dafür gibt es jetzt eine Instrumentierung.

### Eine Testfahrt, alle drei Messwerte

1. In der App: **Einstellungen → Diagnose → Fahrt aufzeichnen** einschalten.
   Standardmässig aus — hier entsteht als einzigem Ort der App eine
   vollständige Bewegungsspur. Sie bleibt im Arbeitsspeicher und wird beim
   Ausschalten gelöscht.
2. Akkustand notieren, fahren (mindestens 20 Minuten, für die Akkufrage besser
   eine Stunde), Akkustand notieren.
3. **Info → Fahrtprotokoll teilen** — CSV an sich selbst schicken.
4. Die beiden Akkuwerte in die vorbereiteten Zeilen im Kopf der Datei
   eintragen.
5. `npm run analyze-drive -- fahrt.csv`

Das Skript gibt Fixanzahl, jede Lücke über der Schwelle mit Dauer und
Zeitpunkt, den Zeitanteil je Akku-Strategie und je Warnmodus, die Anzahl
Warnungen sowie mittlere und maximale Genauigkeit aus — und rechnet den
Akkuverbrauch gegen das 3-%/h-Ziel.

**Automatische Akkuerfassung:** absichtlich nicht gebaut. Die dafür nötige
Abhängigkeit wäre `expo-battery`; die für Expo SDK 52 vorgesehene Version ist
`~9.0.1` (aus `bundledNativeModules.json` von `expo@52.0.0`, nicht geraten).
Sie ist hier nicht aufgenommen worden, weil ein natives Modul ohne Gerätebau
nicht prüfbar ist und der manuelle Weg die Frage genauso beantwortet. Wer sie
später hinzunimmt, hat die Versionsfrage damit schon geklärt.

## Datenpipeline

```bash
npm install
npm run build-dataset                        # Deutschland, alle Bundesländer
npm run build-dataset -- --regions DE-BW     # ein Bundesland nachziehen
npm run build-dataset -- --countries DE,AT,CH
npm run build-dataset -- --no-cache          # Overpass frisch abfragen
npm run verify-dataset                       # Integrität, Abdeckung, Stichprobe
npm test                                     # Unit-Tests, kein Netz nötig
```

Die Pipeline läuft **vor** dem App-Build und erzeugt
`assets/data/cameras.json`: ein einziges JSON, gruppiert in ein Gitter von
0,05° × 0,05°. Das ist der komplette räumliche Index — keine Datenbank, kein
SQLite, kein R-Tree. Der Datensatz passt in den RAM und wird beim App-Start
einmal geparst.

Overpass-Antworten werden in `.overpass-cache/` zwischengespeichert. Ein
erneuter Lauf belastet die API nicht noch einmal; `--no-cache` erzwingt eine
frische Abfrage.

### Werkzeuge

- `scripts/build-dataset.ts` — Abfrage, Normalisierung, Dedupe, Gitter
- `scripts/verify-dataset.ts` — Prüfung des Ergebnisses (Phase-1-DoD)
- `scripts/analyze-raw.ts` — seziert die Rohantwort eines Gebiets, beantwortet
  „warum sind das so viele/wenige?"
- `scripts/reference-locations.json` — bekannte Standorte für die Stichprobe,
  von Hand zu füllen

## Nicht-Ziele

Keine Community-Meldungen, kein Melde-Button, kein Backend. Keine Navigation,
keine Routenplanung. Keine Kartenansicht in Phase 1–4. Keine mobilen Blitzer.
Kein Account, kein Login, kein Analytics-SDK, kein Crashlytics. Kein Abo.

## Lizenz und Attribution

Die Blitzerdaten stammen aus **OpenStreetMap**, © OpenStreetMap-Mitwirkende,
lizenziert unter der **Open Database License (ODbL) 1.0**.

Der erzeugte Datensatz ist eine abgeleitete Datenbank im Sinne der ODbL. Damit
greift Share-Alike: Wird der Datensatz veröffentlicht oder mit der App
verteilt, muss er unter ODbL stehen und die Attribution in der App sichtbar
sein. Das ist vor einer Veröffentlichung im Detail zu prüfen — die Auslegung
von Share-Alike bei „Produced Works" ist nicht trivial.

Der Code in diesem Verzeichnis steht unter MIT.
