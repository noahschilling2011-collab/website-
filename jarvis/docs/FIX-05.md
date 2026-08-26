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
