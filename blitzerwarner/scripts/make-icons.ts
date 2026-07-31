#!/usr/bin/env node
/**
 * App-Icon und Startbild erzeugen.
 *
 *   npx tsx scripts/make-icons.ts
 *
 * WARUM ERZEUGT UND NICHT GEMALT
 *
 * Aus demselben Grund wie die Landesumrisse und die Replay-Tracks: Was von
 * Hand entsteht, lässt sich nicht nachvollziehen und nicht reproduzieren.
 * Hier steht, warum das Zeichen so aussieht, und ein erneuter Lauf liefert
 * exakt dieselben Dateien.
 *
 * Ohne zusätzliche Abhängigkeit. Ein PNG ist zlib plus vier Blöcke mit
 * CRC — das ist überschaubarer als eine Bildbibliothek im Projekt, die nur
 * für drei Dateien da wäre.
 *
 * DAS ZEICHEN
 *
 * Ein gefüllter Punkt und drei Bögen, die sich ihm von links nähern. Der
 * Punkt ist die feste Anlage — der Name der App ist "Static", und genau
 * darum geht es: stationäre Messstellen, keine mobilen. Die Bögen sind die
 * Annäherung; sie werden nach aussen blasser, weil die Warnung mit der
 * Entfernung unsicherer wird.
 *
 * Bewusst abstrakt. Eine gezeichnete Kamera oder ein Blitzsymbol wäre auf
 * 40 Pixel nicht mehr lesbar, und es sähe aus wie das Zeichen von jemand
 * anderem.
 *
 * Farben aus app.json: Schwarz als Hintergrund, #FF3B30 als Warnfarbe.
 */
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HIER = dirname(fileURLToPath(import.meta.url));
const ZIEL = join(HIER, '..', 'app', 'assets');

/** Warnfarbe, identisch mit primaryColor in app.json. */
const ROT: [number, number, number] = [0xff, 0x3b, 0x30];
/** Hintergrund, identisch mit backgroundColor in app.json. */
const SCHWARZ: [number, number, number] = [0x00, 0x00, 0x00];

/**
 * Kantenglättung durch Überabtastung.
 *
 * Jeder Bildpunkt wird 4x4-fach abgetastet und gemittelt. Ohne das sind die
 * Bögen bei 1024 Pixeln sichtbar treppig, und ein treppiges Icon fällt im
 * Store sofort auf.
 */
const ABTASTUNG = 4;

// --- PNG ------------------------------------------------------------------

const CRC_TABELLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(daten: Uint8Array): number {
  let c = 0xffffffff;
  for (const b of daten) c = CRC_TABELLE[(c ^ b) & 0xff]! ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function block(typ: string, inhalt: Uint8Array): Uint8Array {
  const name = Buffer.from(typ, 'ascii');
  const koerper = Buffer.concat([name, Buffer.from(inhalt)]);
  const kopf = Buffer.alloc(4);
  kopf.writeUInt32BE(inhalt.length, 0);
  const pruef = Buffer.alloc(4);
  pruef.writeUInt32BE(crc32(koerper), 0);
  return Buffer.concat([kopf, koerper, pruef]);
}

/**
 * RGBA-Puffer als PNG schreiben.
 *
 * Filtertyp 0 (keiner) für jede Zeile. Ein besserer Filter spart bei diesen
 * flächigen Motiven kaum etwas und macht den Code doppelt so lang.
 */
function alsPng(breite: number, hoehe: number, rgba: Uint8Array): Buffer {
  const roh = Buffer.alloc(hoehe * (1 + breite * 4));
  for (let y = 0; y < hoehe; y++) {
    const ziel = y * (1 + breite * 4);
    roh[ziel] = 0;
    Buffer.from(rgba.buffer, rgba.byteOffset + y * breite * 4, breite * 4).copy(roh, ziel + 1);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(breite, 0);
  ihdr.writeUInt32BE(hoehe, 4);
  ihdr[8] = 8;   // 8 Bit je Kanal
  ihdr[9] = 6;   // RGBA
  ihdr[10] = 0;  // Deflate
  ihdr[11] = 0;  // Standardfilter
  ihdr[12] = 0;  // kein Interlace

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    block('IHDR', ihdr),
    block('IDAT', deflateSync(roh, { level: 9 })),
    block('IEND', new Uint8Array(0)),
  ]);
}

// --- Zeichnen -------------------------------------------------------------

type Deckung = (x: number, y: number) => number;

/** Gefüllter Kreis um (mx, my). */
function kreis(mx: number, my: number, r: number): Deckung {
  return (x, y) => ((x - mx) ** 2 + (y - my) ** 2 <= r * r ? 1 : 0);
}

/**
 * Bogen: Ringausschnitt um (mx, my), begrenzt auf einen Winkelbereich.
 *
 * Der Winkel wird von der positiven x-Achse gegen den Uhrzeigersinn gemessen.
 * `oeffnung` ist die halbe Breite des Ausschnitts — der Bogen reicht also von
 * `richtung - oeffnung` bis `richtung + oeffnung`.
 */
function bogen(
  mx: number, my: number, r: number, dicke: number,
  richtungGrad: number, oeffnungGrad: number,
): Deckung {
  const innen = r - dicke / 2;
  const aussen = r + dicke / 2;
  const richtung = (richtungGrad * Math.PI) / 180;
  const oeffnung = (oeffnungGrad * Math.PI) / 180;
  return (x, y) => {
    const dx = x - mx;
    const dy = y - my;
    const d = Math.hypot(dx, dy);
    if (d < innen || d > aussen) return 0;
    // Kürzester Winkelabstand zur Sollrichtung.
    let w = Math.atan2(dy, dx) - richtung;
    while (w > Math.PI) w -= 2 * Math.PI;
    while (w < -Math.PI) w += 2 * Math.PI;
    return Math.abs(w) <= oeffnung ? 1 : 0;
  };
}

type Ebene = { form: Deckung; farbe: [number, number, number]; alpha: number };

/**
 * Der Aufbau des Zeichens, in Einheiten seiner eigenen Grundgrösse.
 *
 * Alles hier ist relativ. Wie gross und wo es landet, rechnet `zeichen()`
 * daraus aus — der erste Versuch hatte beides geraten, und das Zeichen sass
 * sichtbar links der Mitte und füllte die Kachel nur zur Hälfte.
 */
const PUNKT_R = 0.085;
const BOGEN_DICKE = 0.045;
const BOGEN_RADIEN = [0.19, 0.30, 0.41] as const;
const BOGEN_ALPHA = [0.9, 0.6, 0.32] as const;
/** Halbe Öffnung der Bögen in Grad, gemessen von der Richtung nach links. */
const BOGEN_OEFFNUNG = 52;

/**
 * Die Ausdehnung des Zeichens, aus seinem Aufbau gerechnet statt gemessen.
 *
 * Der äusserste Bogen bestimmt drei der vier Ränder; nach rechts reicht nur
 * der Punkt. Senkrecht zählt der Sinus der Öffnung, weil der Bogen dort
 * endet — nicht der volle Radius.
 */
const AUSSEN = BOGEN_RADIEN[BOGEN_RADIEN.length - 1]! + BOGEN_DICKE / 2;
const RAHMEN = {
  links: -AUSSEN,
  rechts: PUNKT_R,
  hoch: -AUSSEN * Math.sin((BOGEN_OEFFNUNG * Math.PI) / 180),
} as const;
const BREITE = RAHMEN.rechts - RAHMEN.links;
const HOEHE = -2 * RAHMEN.hoch;
/** Diagonale, für die Sicherheitszone des Android-Vordergrunds. */
const DIAGONALE = Math.hypot(BREITE, HOEHE);

/**
 * Das Zeichen aufbauen.
 *
 * `fuellung` ist der Anteil der Bildkante, den die längere Seite des Zeichens
 * einnehmen soll. Der Punkt wird so gesetzt, dass der GERECHNETE Rahmen
 * mittig sitzt — und nicht der Punkt selbst, denn der liegt am rechten Rand
 * des Zeichens und nicht in seiner Mitte.
 */
function zeichen(kante: number, fuellung: number): Ebene[] {
  const e = (fuellung * kante) / Math.max(BREITE, HOEHE);
  // Waagerechte Mitte des Rahmens, vom Punkt aus gemessen.
  const versatz = ((RAHMEN.links + RAHMEN.rechts) / 2) * e;
  const mx = kante / 2 - versatz;
  const my = kante / 2;

  return [
    // Die feste Anlage.
    { form: kreis(mx, my, e * PUNKT_R), farbe: ROT, alpha: 1 },
    // Drei Bögen, nach aussen blasser: Je weiter weg, desto unsicherer.
    ...BOGEN_RADIEN.map((r, i) => ({
      form: bogen(mx, my, e * r, e * BOGEN_DICKE, 180, BOGEN_OEFFNUNG),
      farbe: ROT,
      alpha: BOGEN_ALPHA[i]!,
    })),
  ];
}

/**
 * Ein Bild rastern.
 *
 * `hintergrund` null lässt die Fläche durchsichtig — das braucht der
 * Android-Vordergrund, dem das System seine eigene Hintergrundfarbe
 * unterlegt.
 */
function male(
  breite: number, hoehe: number,
  ebenen: Ebene[],
  hintergrund: [number, number, number] | null,
): Uint8Array {
  const rgba = new Uint8Array(breite * hoehe * 4);
  const schritt = 1 / ABTASTUNG;

  for (let y = 0; y < hoehe; y++) {
    for (let x = 0; x < breite; x++) {
      let r = hintergrund?.[0] ?? 0;
      let g = hintergrund?.[1] ?? 0;
      let b = hintergrund?.[2] ?? 0;
      let a = hintergrund === null ? 0 : 1;

      for (const ebene of ebenen) {
        // Überabtastung: Anteil der Teilpunkte, die in der Form liegen.
        let treffer = 0;
        for (let sy = 0; sy < ABTASTUNG; sy++) {
          for (let sx = 0; sx < ABTASTUNG; sx++) {
            treffer += ebene.form(x + (sx + 0.5) * schritt, y + (sy + 0.5) * schritt);
          }
        }
        const deckung = (treffer / (ABTASTUNG * ABTASTUNG)) * ebene.alpha;
        if (deckung === 0) continue;

        // Über den bisherigen Stand legen (source-over, vorab unmultipliziert).
        const neuA = deckung + a * (1 - deckung);
        r = (ebene.farbe[0] * deckung + r * a * (1 - deckung)) / neuA;
        g = (ebene.farbe[1] * deckung + g * a * (1 - deckung)) / neuA;
        b = (ebene.farbe[2] * deckung + b * a * (1 - deckung)) / neuA;
        a = neuA;
      }

      const i = (y * breite + x) * 4;
      rgba[i] = Math.round(r);
      rgba[i + 1] = Math.round(g);
      rgba[i + 2] = Math.round(b);
      rgba[i + 3] = Math.round(a * 255);
    }
  }
  return rgba;
}

// --- Hauptlauf ------------------------------------------------------------

mkdirSync(ZIEL, { recursive: true });

/**
 * Die drei Dateien, die app.json braucht.
 *
 * Die Skalen sind verschieden, und zwar aus einem Grund je Datei:
 *
 *  icon             0.62 — füllt die Kachel gut aus. iOS rundet die Ecken
 *                   selbst, es darf also bis fast an den Rand gehen.
 *  adaptive-icon    0.42 — Android beschneidet den Vordergrund je nach
 *                   Gerätemaske. Sicher ist nur der mittlere Kreis mit
 *                   66 Prozent Durchmesser; alles darüber kann abgeschnitten
 *                   werden. Der äusserste Bogen liegt bei 0.41 * 0.42 * 2
 *                   = 34 Prozent der Kante vom Mittelpunkt aus und damit
 *                   klar innerhalb.
 *  splash-icon      0.34 — das Startbild zeigt das Zeichen klein und ruhig.
 *                   Ein bildschirmfüllendes Logo beim Start wirkt wie eine
 *                   Werbeeinblendung.
 */
/**
 * Wie viel der Bildkante der Android-Vordergrund einnehmen darf.
 *
 * Android beschneidet ihn je nach Gerätemaske — rund, quadratisch, Squircle.
 * Sicher ist nur der mittlere Kreis mit 66 Prozent Durchmesser. Massgeblich
 * ist deshalb die DIAGONALE des Zeichens und nicht seine längere Seite: Ein
 * Rechteck, dessen Höhe in den Kreis passt, ragt über Eck trotzdem heraus.
 *
 * 0,62 statt 0,66 lässt etwas Luft; genau auf der Kante zu liegen sieht auf
 * einem runden Gerät gedrängt aus.
 */
const ANDROID_SICHER = 0.62;

const DATEIEN = [
  /*
   * iOS rundet die Ecken selbst und beschneidet nicht weiter. Das Zeichen
   * darf deshalb gross sein — 0,74 füllt die Kachel, ohne den Rand zu
   * berühren.
   */
  { name: 'icon.png', kante: 1024, fuellung: 0.74, hintergrund: SCHWARZ },
  /*
   * Aus der Sicherheitszone gerechnet, nicht geschätzt: Damit die Diagonale
   * in den 62-Prozent-Kreis passt, darf die längere Seite nur
   * ANDROID_SICHER * längereSeite / Diagonale einnehmen.
   */
  {
    name: 'adaptive-icon.png',
    kante: 1024,
    fuellung: (ANDROID_SICHER * Math.max(BREITE, HOEHE)) / DIAGONALE,
    hintergrund: null,
  },
  /*
   * Das Startbild zeigt das Zeichen klein und ruhig. Ein bildschirmfüllendes
   * Logo beim Start wirkt wie eine Werbeeinblendung.
   */
  { name: 'splash-icon.png', kante: 1024, fuellung: 0.34, hintergrund: null },
] as const;

console.log(
  `Zeichen: Rahmen ${BREITE.toFixed(3)} x ${HOEHE.toFixed(3)}, ` +
  `Diagonale ${DIAGONALE.toFixed(3)} (Einheiten der Grundgrösse)\n`,
);

for (const d of DATEIEN) {
  const rgba = male(d.kante, d.kante, zeichen(d.kante, d.fuellung), d.hintergrund);
  const png = alsPng(d.kante, d.kante, rgba);
  writeFileSync(join(ZIEL, d.name), png);
  const e = (d.fuellung * d.kante) / Math.max(BREITE, HOEHE);
  console.log(
    `${d.name.padEnd(20)} ${d.kante}x${d.kante}  ` +
    `${(png.length / 1024).toFixed(0).padStart(4)} KB  ` +
    `Füllung ${(d.fuellung * 100).toFixed(0).padStart(2)} %  ` +
    `Diagonale ${((DIAGONALE * e) / d.kante * 100).toFixed(0).padStart(2)} %  ` +
    `${d.hintergrund === null ? 'transparent' : 'schwarz'}`,
  );
}

console.log(`\n${DATEIEN.length} Dateien in ${ZIEL}`);
