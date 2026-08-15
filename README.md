# Static — Offline-Warner für stationäre Blitzer

> Dieses Repo enthält zwei unabhängige Projekte: **Static** in `blitzerwarner/`
> (dieses README) und **CASHOUT**, ein Roblox-Spiel, in [`cashout/`](cashout/README.md).

Warnt per Sprachansage und Ton vor **stationären** Blitzern. Läuft im
Hintergrund bei ausgeschaltetem Display. Kein Backend, kein Account, keine
Werbung, **keine Netzwerk-Requests zur Laufzeit**.

**Diese App warnt nicht vor mobilen Messstellen.** Das ist eine
Produktentscheidung, keine Lücke: Mobile Blitzer brauchen eine
Crowd-Datenbank, und die lässt sich ohne Nutzerbasis nicht aufbauen.

Gewonnen wird auf vier Achsen: Akku, Datenschutz, Offline-Fähigkeit,
Einfachheit. Auf Datenqualität verliert das Projekt gegen kommerzielle
Anbieter — was drin ist und was fehlt, steht offen in
[blitzerwarner/DATA.md](blitzerwarner/DATA.md).

## Rechtlicher Hinweis

§ 23 Abs. 1c StVO verbietet dem Fahrzeugführer Betrieb und betriebsbereites
Mitführen von Geräten, die Verkehrsüberwachungsmaßnahmen anzeigen. Verstoß:
75 € und 1 Punkt (BKat Nr. 247). Nach OLG Karlsruhe, Beschl. v. 07.02.2023,
Az. 2 ORbs 35 Ss 9/23, liegt eine Ordnungswidrigkeit des Fahrers auch dann
vor, wenn der **Beifahrer** die App bedient und der Fahrer sich die Warnung
zunutze macht.

Die App schaltet die Warnfunktion in Deutschland, Österreich und der Schweiz
daher automatisch ab und zeigt dort einen nicht abschaltbaren Hinweis. Tacho
und Tempolimit-Anzeige laufen weiter.

Das ist keine Rechtsberatung. Vor einer Store-Veröffentlichung muss das jemand
mit einschlägiger Qualifikation prüfen.

## Aufbau

```
blitzerwarner/
├── scripts/            Datenpipeline (Node, läuft VOR dem App-Build)
│   ├── build-dataset.ts        OSM abfragen, normalisieren, deduplizieren, kacheln
│   ├── verify-dataset.ts       Integrität, Abdeckung, Stichprobe
│   ├── count-speedlimits.ts    Mengengerüst für den Tempolimit-Datensatz
│   ├── explore-tagging.ts      welche OSM-Taggings es überhaupt gibt
│   ├── assess-candidates.ts    bringt eine Tagging-Variante echte Blitzer?
│   └── crosscheck-region.ts    auffällige Gebietszahl gegenprüfen
├── assets/data/        der gebaute Datensatz (cameras.json)
├── app/                Expo-App (React Native, TypeScript)
│   ├── src/config.ts           JEDE Zahl der App, jede mit Begründung
│   ├── src/core/               Geometrie, Warnlogik, Tacho, Länder-Gate, Daten
│   ├── src/audio/              Warnton, Ansagetexte, Wiedergabe, Audio-Routen
│   ├── src/location/           Background-Task, Akku-Strategie, Watchdog
│   ├── src/replay/             Replay-Harness — GPX rein, Warnungen raus
│   ├── src/ui/                 vier Screens
│   ├── fixtures/               Referenz-Tracks mit Erwartungen
│   └── tests/                  165 Tests, kein Netz, kein Gerät nötig
├── DATA.md             Datenlage, ehrlich
└── CARPLAY.md          warum es keine CarPlay-Oberfläche gibt
```

## Loslegen

```bash
# Datenpipeline
cd blitzerwarner
npm install
npm run build-dataset                        # alle 16 Bundesländer
npm run verify-dataset                       # prüfen
npm test                                     # Unit-Tests

# App
cd app
npm install
npm test                                     # 165 Tests
npm run replay:all                           # Replay-Suite (Phase-3-DoD)
npx expo run:android                         # braucht Development Build
```

Hintergrund-Location läuft **nicht** in Expo Go. Es braucht einen Development
Build (`eas build --profile development`).

## Stand

| Phase | Inhalt | Status |
|---|---|---|
| 1 | Datenpipeline | 5053 Anlagen, Trefferquote offen (braucht Referenzdaten) |
| 2 | Background-Tracking | Code steht, Gerätetest offen |
| 3 | Warnlogik + Replay-Test | **fertig**, 5 Tracks grün |
| 4 | UI + Ansage | Code steht, Gerätetest offen |
| 5 | Tacho | Code steht, Vergleichsprotokoll offen |
| 6 | Tempolimit-Datensatz | Mengengerüst gemessen, Build offen |
| 7 | Map-Matching | offen |
| 8 | Meldefunktion (OSM-Notes) | offen |
| 9 | Store-Vorbereitung | offen |

Was ohne echtes Gerät nicht abschließbar ist: 20 Minuten lückenloses Tracking
bei ausgeschaltetem Display, Akkumessung gegen das Ziel von unter 3 %/h, und
das Vergleichsprotokoll gegen den Auto-Tacho.

## Lizenz und Attribution

Blitzerdaten aus **OpenStreetMap**, © OpenStreetMap-Mitwirkende, lizenziert
unter der **Open Database License (ODbL) 1.0**. Der erzeugte Datensatz ist eine
abgeleitete Datenbank; Share-Alike ist vor einer Veröffentlichung im Detail zu
prüfen. Die Attribution ist in der App sichtbar.

Code: MIT.
