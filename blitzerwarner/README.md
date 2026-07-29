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
| 1 | Datenpipeline | Datensatz gebaut, Trefferquote noch offen — siehe DATA.md |
| 2 | Background-Tracking | offen |
| 3 | Warnlogik + Replay-Test | offen |
| 4 | UI + Ansage | offen |
| 5 | Store-Vorbereitung | offen |

Es existiert noch **keine** React-Native-App. Zuerst musste feststehen, ob
überhaupt genug Daten da sind, damit das Produkt Sinn ergibt.

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
