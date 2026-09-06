# FIX-05 — Globus reparieren und einbauen

Auftrag von Noah, 26.08.2026. Ablage hier, Stand in `STATUS.md`.

## Der Auftrag in einem Satz

Der Globus aus Phase 11 ist im Kern kaputt — nicht langsam, sondern
**unbedienbar**. Reparieren in `weltlage.html`, und **erst danach** als
fünften Tab in `index.html`, ohne dass die Chat-Ansicht träger wird.

## Was ausdrücklich NICHT gebaut wird

**Obsidian ist gebaut** (`core/vault.py`, `core/vault_index.py`,
`scripts/migrate_vault.py`, Setting `vault_pfad`). Es fehlt eine Zeile in
`.env` — Schritt D, sonst nichts.

**Sprache ist gebaut** (`BrowserVoice()` in `index.html`, Push-to-Talk,
DE/EN, `SPRACHSTIL`). Phase 9 steht nur auf `◐`, weil Headless-Chromium
kein Mikrofon hat. Es fehlt eine **Abnahme**, kein Feature — Schritt C.

## Die Befunde, hier nachgerechnet

Alle sieben aus dem Auftrag wurden gegen die Datei vom 26.08.2026
nachgeprüft. **Alle sieben stimmen**, und die Zeilennummern des Auftrags
passen noch.

### B1 — Vier Länder haben ihre Klickmarke im Meer

`mittelpunkt()` (Zeile 461) mittelt alle Punkte aller Ringe arithmetisch
in lon/lat. Zwei Fehler zugleich: Überseegebiete zählen gleich stark wie
das Festland, und über der Datumsgrenze mitteln sich +178° und −178° zu 0°.

Mit genau der Formel aus Zeile 463 nachgerechnet:

```
FJI Fiji            lon=   88.88  lat= -17.01   -> Indischer Ozean
USA United States   lon= -121.39  lat=  45.02   -> Pazifik vor Oregon
NOR Norway          lon=   18.60  lat=  71.74   -> Barentssee
FRA France          lon=  -10.71  lat=  35.40   -> Atlantik vor Portugal
DEU Germany         lon=   10.69  lat=  51.04   -> stimmt
```

Die Zahlen decken sich auf die Nachkommastelle mit denen im Auftrag.
**Frankreich ist nicht anklickbar.**

### B2 — Der Globus lässt sich nicht drehen

```
canvas.addEventListener  -> nur Zeile 535, 'click'
pointerdown 0   pointermove 0   pointerup 0   wheel 0   touchstart 0
OrbitControls 0
```

Die abgewandte Halbkugel erreicht man nur, indem man dort ein Land
anklickt, das man nicht sehen kann. *Kleine Ergänzung zum Auftrag:* seit
dem 26.08. gibt es die Ortssuche, die per `fliegeZu()` hinfliegt — der
Globus ist also nicht *völlig* tot, aber drehen kann man ihn nicht.

### B3 — Klicks gehen durch die Erde hindurch

Zeile 541: `zeiger.intersectObject(zustand.marken)` — nur die Marken, die
Erdkugel ist nicht im Raycast.

### B4 — 60 Bilder pro Sekunde für ein Standbild

Zeile 605: `renderer.render(szene, kamera)` steht **außerhalb** des
`if (ziel)`-Blocks und läuft in jedem Frame.

### B5 — Three.js sind 2,0 MB

```
static/vendor/three.core.js     1409 kB
static/vendor/three.module.js    634 kB
```

`three.module.js` importiert `./three.core.js` in Zeile 6 und 7.

### B6 — Unvereinbare Layouts

`weltlage.html` legt `#globus`, Kopf, Karten und Statusleiste auf
`position:fixed` (Zeilen 29, 34, 55, 114, 138). `index.html` hat einen
eigenen Header, vier Tabs und eine Composer-Leiste.

### B7 — Drei Länder ohne ISO-Code

177 Geometrien, davon 3 ohne Eintrag in `iso3166.json`:
**N. Cyprus, Somaliland, Kosovo**.

## Three.js-Namen, gegen `static/vendor/` geprüft

Nicht aus dem Gedächtnis, sondern gegrept:

```
worldToLocal( vector ) {
intersectObject( object, recursive = true, intersects = [] ) {
```

Treffer tragen `.point` und `.distance`.

## Reihenfolge

```
A (weltlage.html reparieren)  ->  A6 abnehmen  ->  STOPP, berichten
B (in index.html einbauen)    ->  B6 abnehmen  ->  STOPP, berichten
C (Sprach-Abnahmeanleitung)   ->  an Noah
D (Vault einschalten)         ->  nur mit Pfad von Noah
```

---

## Schritt B — was beim Bauen dazukam

Zwei Dinge standen nicht im Auftrag und mussten trotzdem entschieden werden.
Beide sind gemessen, nicht vermutet.

### Namenskollisionen zwischen den beiden Oberflächen

`index.html` und der Globus benutzen zum Teil dieselben Namen. Nachgezählt:
31 Globus-Klassen gegen 99 aus `index.html`, 24 Globus-ids gegen alle ids
der Seite.

| Art | Name | Wo es kracht |
|-----|------|--------------|
| id | `btn-mic` | Die Sprachtaste des Chats (`index.html:842`) und die des Globus. Zwei gleiche ids in einem Dokument sind ungültig, und `getElementById` trifft dann die falsche. |
| Klasse | `karte` | `index.html:450` gibt ihr Innen- und Außenabstand, der Globus-Stil nicht. |
| Klasse | `status` | `index.html:129` schiebt sie mit `margin-left:auto` nach rechts; im Globus ist sie eine volle Leiste. |

Gelöst: die Mikrofontaste des Globus heißt jetzt `btn-globus-mic`, der ganze
Globus-Stil liegt unter `.globus-wurzel`, und die drei Eigenschaften, die
`index.html` an `karte` und `status` setzt und der Globus bisher nicht,
stehen im Globus-Stil ausdrücklich drin. `el()` sucht außerdem nur noch im
eigenen Behälter.

### Die Leertaste

Der Globus hört auf die Leertaste (Push-to-Talk). Der Handler hing an
`window` und prüfte nur `ev.target === document.body`. Im eigenen Tab ist
das harmlos. Als eingebauter Tab ist das Fenster der ganze Chat — die
Leertaste hätte im Chatfeld die Ländersuche gestartet. Jetzt zwei Schranken:
nur solange die Weltansicht läuft, und nie aus einem Eingabefeld heraus.

### Mutationen — was die Tests wirklich messen

Sechs Mutationen, je eine Zeile weg, die der Auftrag verlangt.

| # | Mutation | Ergebnis |
|---|----------|----------|
| M1 | `pausiere()` beim Tabwechsel weg | **getötet** |
| M2 | zweites Öffnen holt die Datei neu | überlebt |
| M3 | `resize()` in `weiter()` weg | überlebt |
| M4 | Leertaste ohne `aktiv`-Schranke | **getötet** |
| M5 | Three.js schon beim Start holen | **getötet** |
| M6 | Globus-Karten ohne die zwei Gegenzeilen | überlebt |

Die drei Überlebenden sind **doppelt abgesichert**, nicht ungeprüft. Nimmt
man jeweils beide Sicherungen weg, fällt der Test sofort:

| # | Beide Sicherungen weg | Ergebnis |
|---|-----------------------|----------|
| M2b | Wache weg **und** Cache-Buster am Import | **getötet** |
| M3b | `resize()` weg **und** `ResizeObserver` weg | **getötet** |
| M6b | Gegenzeilen weg **und** der Stern-Reset weg | **getötet** |

Drei Befunde daraus, die im Auftrag anders vermutet waren:

1. **Der `IntersectionObserver` reagiert in diesem Chromium sehr wohl auf
   `display:none`.** Der Auftrag sagt „verlass dich nicht darauf" — richtig,
   aber der Grund ist nicht, dass er schweigt. Er meldet, `sichtbar` wird
   false und `schleife()` steigt sofort aus. Der Zähler der gezeichneten
   Bilder steht damit auch ohne `pausiere()` still. Was **nicht** stillsteht,
   ist die Schleife selbst: `setAnimationLoop` ruft weiter in jedem Frame
   auf. Deshalb gibt es jetzt zwei Zähler, `window.__globusBilder` und
   `window.__globusSchleife`, und M1 stirbt am zweiten.
2. **Der `ResizeObserver` fängt die Größenänderung im Hintergrund ab.**
   `weiter()` misst trotzdem neu — der Auftrag will sich ausdrücklich nicht
   auf den Observer verlassen, und M3b zeigt, dass ohne beide nichts bleibt.
3. **Ein zweiter Netzabruf ist gar nicht möglich**, solange die Import-URL
   dieselbe ist: die Modul-Landkarte des Browsers liefert das Modul aus dem
   Speicher. Die Wache `if (globusModul)` verhindert nicht den Abruf, sondern
   den zweiten `starte()`-Lauf. Dass B6 Kriterium 2 trotzdem etwas prüft,
   zeigt M5 (erste Hälfte) und M2b (zweite Hälfte).

### Was `web-selfcheck` sagt

Gegen den **laufenden** Server, nicht gegen die Datei — sonst steht dort
`__JARVIS_TOKEN__` und jeder Fetch läuft ins Leere.

| Ansicht | Fehler | Warnungen |
|---------|--------|-----------|
| `/weltlage` | **0** | 2 (leeres `<img>` im versteckten Ortspanel, kein `<h1>`) |
| `/` Chat | 3 | 0 |
| `/` Welt-Tab | 3 | 1 (dasselbe leere `<img>`) |

Die drei Fehler sind **dreimal derselbe**: Kontrast 1,69:1 auf dem aktiven
Tab (`.tab[aria-selected="true"]`, Akzent auf `--accent-soft`) bei 360, 768
und 1440 px. Er ist **nicht** neu — derselbe Lauf gegen die Fassung vor
FIX-05 meldet ihn wortgleich. Die Prüfung rechnet die halbtransparente
Akzentfläche gegen Weiß, weil sie den Farbverlauf des `body` nicht auflösen
kann. Angefasst wurde er nicht: das ist eine Frage an `index.html`, nicht an
diesen Auftrag.

Der 404 auf `/favicon.ico` in `weltlage.html` **wurde** angefasst — eine
Zeile, dasselbe eingebettete Favicon wie in `index.html`, mit demselben
Kommentar. Er war der einzige Fehler in der A6-Prüfung, und damit fiel auch
die Favicon-Ausnahme im Test wieder weg.

---

## Schritt B — zwei Fehler, die eine Gegenprüfung fand

Nach der Abnahme B6 lief ein zweiter Durchgang über den Diff: vier
unabhängige Blickwinkel (Korrektheit, Sicherheit, Lag, Tests), danach jeder
Befund von Skeptikern zu widerlegen versucht. Zwei Befunde haben das
überlebt, beide echt, beide reproduziert und behoben.

### 1. Das Rennen beim Laden — **hoch**

Wer auf „Welt" klickt und **noch während der 2,0 MB** zurück auf „Chat"
geht, hatte den Renderloop danach dauerhaft im Chat laufen.

Ursache: `globusModul` wurde erst gesetzt, wenn `starte()` aufgelöst hatte —
also nach dem Import **und** den beiden Geometrie-Abrufen. Die Pause-Zeile in
`zeigeAnsicht()` prüfte aber genau darauf (`&& globusModul`). Die
Zeichenschleife und das `aktiv`-Flag laufen dagegen schon im synchronen Teil
von `starte()` an.

Ohne Drosselung ist das Fenster zu schmal, um es zu treffen — deshalb war es
in der Abnahme nicht aufgefallen. Bei 250 kB/s, Rückklick nach 2,5 s:

```
NORMAL gedrosselt: Schleife +0   in 2 s, Leertaste geschluckt=False
RENNEN gedrosselt: Schleife +114 in 2 s, Leertaste geschluckt=True
```

Zwei Folgen: genau der Zähler, den Mutation M1 tötet, lief weiter — und der
Leertasten-Handler blieb scharf, also hätte die Leertaste im Chatfeld das
Mikrofon des Globus geöffnet. Das ist die Falle aus dem Abschnitt oben, nur
über einen Weg, den die `aktiv`-Schranke nicht abdeckte.

Behoben: `globusModul` wird **sofort nach dem Import** gesetzt, ein eigenes
Flag `globusGewollt` sagt, was der Nutzer sehen will, und es wird auch dann
gesetzt, wenn das Modul noch lädt. Nach dem Fix beide Fälle `+0` und
`geschluckt=False`.

### 2. Karten, die im Hintergrund ankommen — **mittel**

`zeichneKarten()` schneidet mit `getBoundingClientRect()` zu. In einer
Ansicht mit `display:none` sind alle Maße null, die Abbruchbedingung ist
sofort wahr, es wird nichts weggenommen. Wer ein Land anklickt, in den Chat
wechselt und zurückkommt, sah gequetschte Karten mit abgeschnittenem Text
statt einer Karte weniger. Gemessen bei 1280×620:

```
ohne Nachholen: 5 Karten, kein Hinweis
mit  Nachholen: 1 Karte,  "4 weitere Meldungen passen nicht ins Bild."
```

Beachte: **nichts ragt über den Rand.** Die Spalte ist eine Flexbox mit
`overflow:hidden` — sie quetscht, statt hinauszuschieben. Ein Test, der auf
Überstand prüft, sieht den Fehler nicht; erst Anzahl und Hinweis zeigen ihn.

Behoben: das Zuschneiden ist eine eigene Funktion `schneideKarten()`, die
`weiter()` nachholt. Sie steigt bei einer Fläche von 0×0 ausdrücklich aus,
statt eine Entscheidung auf unmessbaren Werten zu treffen.

### Zwei weitere Mutationen

| # | Mutation | Ergebnis |
|---|----------|----------|
| M7 | den Zustand vor dem Fix wiederherstellen | **getötet** — „120 Schleifendurchlaeufe im Chat" |
| M8 | `kartenNachholen` aus `weiter()` entfernen | **getötet** — „5 Karten - es wurde nichts zugeschnitten" |

### Drei Lücken in den Tests, die derselbe Durchgang fand

Der vierte Blickwinkel war „taugen die Tests?" — und fand drei Stellen, an
denen die Abnahme weniger belegte, als sie behauptete:

1. **Der Leertasten-Test war einseitig.** `test_die_leertaste_im_chat_...`
   prüft eine *Abwesenheit* — er wäre auch grün, wenn man den Handler
   ersatzlos löschte. Dazu gibt es jetzt die Gegenprobe
   `test_in_der_weltansicht_gehoert_die_leertaste_dem_globus`: in der
   Weltansicht **muss** sie greifen, im Eingabefeld der Ortssuche **nicht**.
2. **Der Token war im Tab unabgedeckt.** `#land` zeigt „France" schon,
   bevor die Antwort da ist — `ladeLand()` schreibt den Namen sofort hin.
   Der Test prüfte also nur, dass die Anfrage rausgeht, nicht dass sie
   ankommt. Im Tab wandert der Token einen anderen Weg als auf der eigenen
   Seite (`starte(ziel, TOKEN)` statt Platzhalter im Modul); ein Fehler
   dabei ergäbe 401. Jetzt wird die **Antwort** geprüft.
3. **Keine JS-Fehler-Sammlung im Tab.** `tests/test_globus.py` sammelt
   `pageerror` und Konsolenfehler, `test_globus_tab.py` tat es nicht — dabei
   ist der Tab eine andere Umgebung: fremdes CSS, fremde ids, ein
   dynamischer Import. Ergänzt als `test_der_tab_laedt_ohne_javascript_fehler`,
   über beide Ansichten und einen Hin- und Rückwechsel.

| # | Mutation | Ergebnis |
|---|----------|----------|
| M9 | Leertasten-Handler ersatzlos weg | **getötet** — „der Globus nimmt die Leertaste nicht mehr an" |
| M10 | falscher Token an `starte()` | **getötet** — „Token kam nicht an: … 401" |

Zwei weitere Hinweise waren berechtigt und betrafen nur die Docstrings: der
B-5-Test und der `.karte`-Test versprachen mehr, als sie messen (M3 und M6
überleben einzeln). Beide Docstrings sagen das jetzt selbst.
