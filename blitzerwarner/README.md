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

**Das Verbot richtet sich an den Fahrzeugführer, nicht an die App.** Eine
solche App zu bauen, anzubieten oder zu installieren ist nicht untersagt —
untersagt ist dem Fahrer das Betreiben während der Fahrt. Die Warnung läuft
deshalb auch in Deutschland, Österreich und der Schweiz; die Entscheidung
darüber liegt beim Fahrer.

Die App zeigt beim ersten Start einen bestätigungspflichtigen Rechtshinweis und
blendet in DE, AT, CH und FR einen dauerhaften, nicht abschaltbaren Banner mit
der jeweiligen Norm und der konkreten Folge ein. Die drei Länder sind nicht
gleich teuer: Deutschland 75 € und 1 Punkt; Österreich im ungünstigen Fall bis
10.000 € und Geräteeinzug (Rechtslage strittig); die Schweiz untersagt schon
das Mitführen und kann das Gerät einziehen.

**Wo die Rechtslage ungeklärt ist, warnt die App nicht.** Und in Frankreich
trifft die Auflage die App selbst, nicht nur den Fahrer — dort läuft
ausschließlich der Zonenmodus ohne Entfernungsangabe.

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

### Die App aufs Telefon bringen

**Expo Go funktioniert nicht.** Die App braucht `expo-task-manager` und
Hintergrund-Standort; beides kann Expo Go nicht. Es muss ein eigener Build
sein — ein Development Build oder ein Preview-Build über EAS.

```bash
cd app
npm install
npx eas-cli@latest login          # kostenloses Expo-Konto
npx eas-cli@latest init           # schreibt extra.eas.projectId in app.json
```

**Android** — kostenlos, kein Android Studio nötig:

```bash
npx eas-cli@latest build --profile preview --platform android
```

Das `preview`-Profil ist in `eas.json` auf `"buildType": "apk"` gesetzt.
Ohne das käme ein `.aab` heraus, das sich auf dem Telefon nicht antippen
lässt. Der fertige Build wird als Link und QR-Code angeboten.

**iPhone** — hier steht eine Hürde, die nicht am Projekt liegt:

Ein iOS-Build, der auf einem physischen Gerät läuft, verlangt eine
**bezahlte Apple-Developer-Mitgliedschaft (99 USD pro Mitgliedsjahr,
developer.apple.com/support/compare-memberships)**. Das gilt für EAS-Builds
und für TestFlight gleichermaßen.

```bash
npx eas-cli@latest device:create   # iPhone registrieren (UDID per QR)
npx eas-cli@latest build --profile development --platform ios
```

Ohne bezahlte Mitgliedschaft bleibt nur der Weg über **Xcode auf einem Mac**
mit einem kostenlosen Apple Account („Personal Team"). Apple erlaubt das
ausdrücklich — „test your apps on devices" —, begrenzt es aber:
Provisioning-Profile laufen **7 Tage nach Ausstellung** ab, danach muss die
App neu gebaut und neu installiert werden; höchstens 3 Testgeräte und 10 App
IDs, jeweils ebenfalls 7 Tage gültig.

Praktisch heißt das: Android zum Ausprobieren, iPhone erst wenn die App
dauerhaft laufen soll.

### Was geprüft ist, bevor die App auf ein Gerät kommt

| Ebene | Prüfung | Wie |
|---|---|---|
| Logik | 385 Tests | `npm run test:logik` |
| Warnverhalten | 11 Fixture-Tracks | `npm run replay:all` |
| Ende zu Ende | echte Anlage aus dem Datensatz, echte Umrisse, echtes Gate bis zum Ansagetext | `tests/kaltstart.test.ts` |
| Oberfläche | alle vier Screens rendern, keine React-Warnung | `npm run test:render` |
| Gestaltung | Vierer-Raster, keine nackte Masszahl im Screen, jeder Token hat einen Leser, jede Fläche zeigt gedrückt und abgeschaltet | `tests/theme.test.ts` |
| Auslieferung | kein Netzwerk-Aufruf, kein Schlüssel, keine sendende Bibliothek im Quelltext | `tests/auslieferung.test.ts` |
| Paket | Bundle baut (721 Module in der Entwicklung, 613 ausgeliefert), Berechtigungen, Icons | `npx expo start`, `tests/berechtigungen.test.ts`, `tests/assets.test.ts` |
| Bündel | keine Source Maps, Datensatz eingebettet, Grösse | `npm run check-bundle` (baut wirklich, ~40 s) |

Der Ende-zu-Ende-Test sucht eine real erfasste Anlage bei Stuttgart, rechnet
eine Anfahrt darauf und lässt sie durch dieselbe Kette laufen wie der
Hintergrund-Task — Landeserkennung, Gate, Entscheidung, Ansage. Ergebnis:

```
Datensatz: 5053 Anlagen, Stand 2026-07-29
Anlage:    48.60411, 9.097 — Tempo 50
Fix 0:     Land null (wartet_bestaetigung), Modus aus
Fix 5:     Land DE (bestaetigt), Modus punkt
Warnung:   327 m vor der Anlage
           "Blitzer, dreihundertfünfzig Meter, Tempo fünfzig"
```

**Was das nicht abdeckt:** alles Native. Ob `expo-location` bei
ausgeschaltetem Display Positionen liefert, ob ein Ton über Bluetooth hörbar
wird, wie viel Akku das kostet — das zeigt nur eine Fahrt. Dafür gibt es den
Fahrtenschreiber.

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

**Hinter einem Proxy:** `NODE_USE_ENV_PROXY=1` davorsetzen. Node's `fetch()`
beachtet `HTTPS_PROXY` nicht von sich aus — anders als curl und anders als
praktisch jede andere HTTP-Bibliothek. Ohne die Variable antwortet jede
Abfrage mit `HTTP 503: upstream connect error … Connection refused`, und das
liest sich wie ein überlasteter Overpass-Server. Es ist keiner, und der
Unterschied ist wichtig: Bei Auslastung wartet man ab, hier wartet man ewig.
Das Skript prüft es beim Start und bricht mit der richtigen Zeile ab, statt
124 Gebiete gegen eine Wand zu fahren.

### Werkzeuge

- `scripts/build-dataset.ts` — Abfrage, Normalisierung, Dedupe, Gitter
- `scripts/verify-dataset.ts` — Prüfung des Ergebnisses (Phase-1-DoD)
- `scripts/analyze-raw.ts` — seziert die Rohantwort eines Gebiets, beantwortet
  „warum sind das so viele/wenige?"
- `scripts/reference-locations.json` — bekannte Standorte für die Stichprobe,
  von Hand zu füllen
- `scripts/check-bundle.ts` — baut das ausgelieferte JS-Bündel für beide
  Plattformen und misst nach: Source Maps, eingebetteter Datensatz, Grösse.
  Gehört vor eine Auslieferung, nicht in `npm test` — es baut wirklich.
  Gemessen am 2026-08-01: 4,04 MB (iOS) / 4,05 MB (Android), 613 / 612 Module,
  keine `.map`. Gegenprobe mit `expo export --source-maps`: 6,42 MB Source Map,
  die Prüfung greift.

## Datensatz Europa (Phase A.2) — offen, und warum

Das Mengengerüst steht (siehe DATA.md): 124 Gebiete, geschätzt 29.475 Anlagen,
rund 2 MB, und die Ein-Datei-Architektur trägt das nachweislich. Der eigentliche
Bau ist damit nur noch ein Lauf:

```bash
npm run build-dataset -- --countries EU --out assets/data/cameras.eu.json
```

**Er ist bisher nicht durchgelaufen.** Ein Versuch brach nach fünf Anläufen für
das erste Bundesland ab — Overpass antwortete über alle vier Spiegel abwechselnd
mit HTTP 429, 502 und 504. Das ist kein Fehler im Skript, sondern Auslastung auf
der Gegenseite.

Der Lauf wurde deshalb abgebrochen und nicht durchgedrückt. Overpass ist
gespendete Rechenzeit; 124 Geometrie-Abfragen gegen einen überlasteten Dienst zu
wiederholen, bis einer davon durchkommt, ist genau das, was man dort nicht tun
soll. Zu einem ruhigeren Zeitpunkt — nachts, europäische Zeit — ist der Lauf
unproblematisch, und der Cache unter `.overpass-cache/` hält bereits geholte
Gebiete fest, sodass ein Abbruch nichts kostet.

## Rechtliches

Vier Dokumente unter `rechtliches/`, erzeugt aus `app/src/rechtstexte.ts`:

| Datei | Stand |
|---|---|
| `NUTZUNGSBEDINGUNGEN.md` | fertig |
| `QUELLEN.md` | fertig |
| `DATENSCHUTZ.md` | **Verantwortlicher fehlt** |
| `IMPRESSUM.md` | **Name und Anschrift fehlen** |

Sie stehen ausserdem vollständig **in** der App, unter Info → Rechtliches und
Einstellungen → Recht und Lizenz. Nicht verlinkt, sondern eingebaut: Die App
stellt keine Netzwerkverbindung her, ein Link auf eine Website wäre
ausgerechnet in der Datenschutzerklärung der einzige Ort, an dem sie den
Nutzer ins Netz schickt — und im Funkloch unlesbar.

**Eine Quelle, zwei Fassungen.** Die Texte stehen in `app/src/rechtstexte.ts`;
`npm run make-legal-docs` erzeugt daraus die Markdown-Dateien für die Adresse,
die Apple und Google bei der Einreichung verlangen. Von Hand gepflegt liefen
die beiden Fassungen auseinander, und von zwei Datenschutzerklärungen ist
mindestens eine falsch. `tests/rechtstexte.test.ts` vergleicht sie bei jedem
Testlauf.

**Was noch fehlt, kann nur der Betreiber liefern:** Name und ladungsfähige
Anschrift. Beides ist mit `[AUSZUFÜLLEN]` markiert, der Generator meldet es
beim Lauf, ein Test hält fest, dass die Markierung nicht stillschweigend
verschwindet, und die App zeigt die betroffenen Dokumente in der Übersicht
als „unvollständig".

**Meine Daten** (Info → Rechtliches): Ausgeben als Text — Einstellungen,
Fehlerprotokoll und, falls eingeschaltet, das Fahrtprotokoll. Und alles
löschen. Ein Konto zum Löschen gibt es nicht, es wurde nie eines angelegt.

## Berechtigungen

Auf **Android** hat die App im ausgelieferten Build (`preview`, `production`)
**keine Internet-Berechtigung**. Das Versprechen „keine Netzwerk-Requests zur
Laufzeit" ist dort nicht behauptet, sondern nachprüfbar — in den
App-Informationen des Systems.

Auf **iOS** gibt es diesen Beweis nicht: Das System kennt keine
Internet-Berechtigung, jede App darf ins Netz, und es ist folglich auch nichts
nachzusehen. Die Zusage ruht dort auf dem Quelltext, und der wird geprüft —
`app/tests/auslieferung.test.ts` sucht in jeder Datei unter `app/src/` nach
`fetch`, `XMLHttpRequest`, `WebSocket`, `sendBeacon`, `EventSource`, `axios`,
`node:http` und `expo-updates`, und in `package.json` nach Analyse-,
Absturzmelder- und Werbepaketen. Die einzige Stelle, die überhaupt eine
Adresse anfasst, ist der Lizenzlink im Info-Screen: `Linking.openURL` übergibt
sie an den Browser, die App verbindet sich nicht selbst. Auch das steht
namentlich im Test, damit eine zweite Stelle auffällt.

Diese Unterscheidung stand vorher nirgends — in der App nicht, in der
Datenschutzerklärung nicht und hier nicht. Auf einem iPhone hätte die
Datenschutzerklärung behauptet, die Berechtigung sei entzogen und in den
Systemeinstellungen nachprüfbar. Beide Hälften falsch, auf genau der
Plattform, für die zuerst gebaut wird.

Ebenfalls entzogen: Mikrofon (`RECORD_AUDIO`), Gerätespeicher
(`READ_/WRITE_EXTERNAL_STORAGE`), Standortdaten aus fremden Fotos
(`ACCESS_MEDIA_LOCATION`) und das Debug-Overlay (`SYSTEM_ALERT_WINDOW`). Alle
fünf kamen ungefragt aus Abhängigkeiten ins Manifest — `expo-av` bringt das
Mikrofon mit, weil dieselbe Bibliothek auch aufnehmen kann, und React Native
setzt `INTERNET` grundsätzlich.

Was bleibt, ist das Minimum:

| Berechtigung | Wofür |
|---|---|
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | Position mit dem Datensatz vergleichen |
| `ACCESS_BACKGROUND_LOCATION` | warnen, wenn das Display aus ist |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` | Android beendet den Task sonst |
| `POST_NOTIFICATIONS` | die Pflicht-Notification des Vordergrunddienstes |
| `MODIFY_AUDIO_SETTINGS` | Musik leiser stellen statt stoppen |
| `WAKE_LOCK`, `VIBRATE` | Ansage und Vibration |

Der Entwicklungsbuild behält `INTERNET` und `SYSTEM_ALERT_WINDOW` — ohne sie
erreicht der Dev-Client den Metro-Server nicht. Die Unterscheidung nach
Build-Profil steht in `app/app.config.js`, geprüft von
`app/tests/berechtigungen.test.ts`.

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
