# CarPlay

Kurzfassung: **Der Ton läuft über CarPlay, ohne dass etwas zu tun ist. Eine
CarPlay-Bedienoberfläche für die Blitzerwarnung wird es nicht geben** — nicht
weil es zu aufwendig wäre, sondern weil zwei Gründe dagegen stehen, von denen
der erste nicht verhandelbar ist.

## 1. Der rechtliche Grund

CarPlay bringt die App auf den **eingebauten Bildschirm des Fahrzeugs**. Dieser
Bildschirm ist der Arbeitsplatz des Fahrers; ihn zu bedienen ist der Zweck von
CarPlay, kein Nebeneffekt.

§ 23 Abs. 1c StVO richtet sich an den Fahrzeugführer: Er darf kein Gerät
betreiben oder betriebsbereit mitführen, das dafür bestimmt ist,
Verkehrsüberwachungsmaßnahmen anzuzeigen. Das OLG Karlsruhe hat mit Beschluss
vom 07.02.2023, Az. 2 ORbs 35 Ss 9/23, entschieden, dass eine
Ordnungswidrigkeit des Fahrers selbst dann vorliegt, wenn der **Beifahrer** die
App bedient und der Fahrer sich die Warnung zunutze macht.

Wenn schon die Bedienung durch den Beifahrer dem Fahrer zugerechnet wird, dann
ist eine Anzeige im Armaturenbrett der eindeutigere Fall, nicht der mildere.
Die gesamte Konstruktion dieses Projekts — Länder-Gate, Beifahrer-Szenario,
abgeschaltete Warnung in DE/AT/CH — existiert, um genau das zu vermeiden. Eine
CarPlay-Warnoberfläche würde sie aufheben.

**Konsequenz im Code:** Eine erkannte CarPlay-Verbindung **verschärft** das
Gate, sie lockert es nicht. Siehe `deutetAufFahrerbedienung()` in
`app/src/audio/route.ts`. Ein Bluetooth-Headset im Motorradhelm sagt über die
Bedienung dagegen nichts aus und wird nicht so behandelt.

Das ist keine Rechtsberatung. Vor einer Veröffentlichung muss das jemand mit
einschlägiger Qualifikation prüfen.

## 2. Der Entitlement-Grund

CarPlay-Apps brauchen ein Entitlement, das Apple einzeln vergibt und an
**genau eine Kategorie** bindet. Die Kategorien sind (Stand CarPlay Developer
Guide, Juni 2026): Audio, Kommunikation, Navigation, EV-Laden, Parken,
Essensbestellung, Tanken, Driving Task.

Ein Blitzerwarner passt in keine davon:

- **Navigation** wäre am nächsten, verlangt aber eine vollwertige
  Turn-by-turn-Navigation. Die steht unter Nicht-Ziele (Spec § 12) und wäre ein
  komplett anderes Produkt.
- **Driving Task** ist für fahrzeugbezogene Aufgaben gedacht, nicht für die
  Anzeige von Verkehrsüberwachung.
- **Audio** meint Medienwiedergabe, nicht Warntöne einer Fremd-App.

Ein Antrag müsste die App als etwas beschreiben, das sie nicht ist. Damit ist
das keine Frage der Wartezeit, sondern eine Frage, die man nicht stellen sollte.

## 3. Was ohne Entitlement schon funktioniert

**Die Sprachansage und der Warnton laufen über CarPlay** — ohne Entitlement,
ohne nativen Code, ohne Antrag. Sobald das iPhone per CarPlay verbunden ist,
ist die Autoanlage das aktive Ausgabegerät, und die Audio-Session der App
spielt dorthin. Das ist der eigentliche Nutzen: Die App ist audio-first, das
Display ist während 95 % der Nutzung aus.

Voraussetzung ist die richtige Audio-Session, und die steht
(`app/src/audio/player.ts`):

- `staysActiveInBackground: true` — ohne das schweigt die App bei
  ausgeschaltetem Display, also in genau dem Zustand, für den sie gebaut ist.
- `interruptionModeIOS: DuckOthers` — Musik wird geduckt, nicht gestoppt.
- `playsInSilentModeIOS: true` — der Stummschalter des Telefons darf eine
  Warnung nicht unterdrücken.

Was CarPlay zusätzlich brächte, wäre eine visuelle Anzeige. Bei dieser App ist
das der am wenigsten wertvolle Teil.

## 4. Was noch fehlt: Routen-Erkennung

`app/src/audio/route.ts` enthält die **Entscheidungslogik** für Audio-Routen —
welche Lautstärke, ob die Aufwach-Pause vor der Sprachansage nötig ist, ob ein
Routenwechsel angesagt werden muss. Diese Logik ist rein und getestet
(`app/tests/route.test.ts`).

Was fehlt, ist das **Erkennen** der Route. Expo legt
`AVAudioSession.currentRoute` nicht offen. Dafür braucht es ein kleines
natives Modul, das die Schnittstelle `RouteErkenner` erfüllt:

```ts
interface RouteErkenner {
  aktuelleRoute(): Route;
  beiWechsel(hoerer: (neu: Route) => void): () => void;
}
```

Bis dahin liefert `KEINE_ERKENNUNG` den Wert `'unbekannt'`, und die App
verhält sich konservativ: Aufwach-Pause immer, mittlere Lautstärke, keine
Wechselansagen. Das ist bewusst so — eine vorgetäuschte Erkennung wäre
schlimmer als keine.

Auf iOS liefert `AVAudioSession.currentRoute.outputs[].portType` die nötige
Information; `.carAudio` steht für CarPlay, `.bluetoothA2DP` und
`.bluetoothHFP` für Bluetooth, `.headphones` für Kabel, `.builtInSpeaker` für
den Telefonlautsprecher. Die Benachrichtigung heißt
`AVAudioSession.routeChangeNotification`.

## 5. Wenn du CarPlay trotzdem verfolgen willst

Der technische Weg wäre, für die Vollständigkeit:

1. CarPlay-Entitlement bei Apple beantragen (Kategorie festlegen, Begründung
   einreichen, Wartezeit Tage bis Wochen).
2. `react-native-carplay` einbinden. Für Expo gibt es Config-Plugins; die
   Variante `@g4rb4g3/react-native-carplay` ist auf Expo SDK 53 und die neue
   Architektur aktualisiert. Ein Development Build ist ohnehin nötig, weil
   Hintergrund-Location nicht in Expo Go läuft.
3. Die Oberfläche mit `CPTemplate`-Bausteinen bauen — freies Layout gibt es
   nicht, nur Apples Vorlagen.

Schritt 1 ist der, an dem es scheitert, und Abschnitt 1 dieses Dokuments ist
der Grund, warum das kein Verlust ist.

**Ein legitimer Teil bleibt übrig:** Der Fahrtbericht nach der Fahrt (Spec
§ 10.4) ist reine Selbstreflexion ohne Warnfunktion — Dauer,
Durchschnittsgeschwindigkeit, Höchstgeschwindigkeit. Das ist der einzige
Teil der App, den ein Fahrer legal nutzen darf, und ein Kandidat für eine
CarPlay-Anzeige, falls das Projekt jemals ein Entitlement bekommt. Für einen
Antrag reicht es allein aber nicht.

## Quellen

- [CarPlay Developer Guide, Juni 2026 (Apple)](https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf)
- [react-native-carplay](https://react-native-carplay.netlify.app/)
- [@g4rb4g3/react-native-carplay (Expo SDK 53, neue Architektur)](https://www.npmjs.com/package/@g4rb4g3/react-native-carplay)
