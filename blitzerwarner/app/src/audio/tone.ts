/**
 * Warntöne, selbst erzeugt.
 *
 * Bewusst nicht aus einer Sound-Bibliothek: Der Frequenzbereich ist eine
 * fachliche Entscheidung, keine Geschmacksfrage. Motoren- und Fahrtgeräusch
 * im Auto ist tieffrequent — ein tiefer Warnton geht darin unter. Genutzt
 * wird deshalb 1 bis 3 kHz, derselbe Bereich, in dem auch Autohersteller
 * ihre Warntöne legen.
 *
 * Die Erzeugung ist eine reine Funktion über Zahlen und damit testbar, ohne
 * dass ein Audiogerät im Spiel ist.
 */

/**
 * Die Töne der App. Die Qualitätsvorgabe nennt drei; der Zonenton ist eine
 * begründete Ausnahme (siehe unten). Ein fünfter braucht wieder eine.
 */
export type TonArt = 'blitzer' | 'tempolimit' | 'system' | 'zone';

export type Impuls = {
  /** Grundfrequenz in Hz. */
  freq: number;
  /** Dauer in ms. */
  dauerMs: number;
  /** Pause danach in ms. */
  pauseMs: number;
};

export type TonDefinition = {
  art: TonArt;
  impulse: Impuls[];
  /** Beschreibung, damit der Ton nicht versehentlich verändert wird. */
  zweck: string;
};

const SAMPLE_RATE = 44_100;

/**
 * Die Töne.
 *
 * Sie müssen sich am Ohr unterscheiden, nicht auf dem Papier. Zwei Töne
 * gelten als unterscheidbar, wenn sie sich in der IMPULSZAHL oder deutlich
 * in der FREQUENZ unterscheiden — der Rhythmus ist auch bei lauter Fahrt
 * erkennbar, eine Verschiebung um wenige hundert Hertz nicht. Ein Test prüft
 * jedes Paar.
 */
export const TOENE: Record<TonArt, TonDefinition> = {
  blitzer: {
    art: 'blitzer',
    // Zwei Impulse, aufsteigend — das ist der Ton, der zählt.
    impulse: [
      { freq: 1600, dauerMs: 90, pauseMs: 60 },
      { freq: 2200, dauerMs: 110, pauseMs: 0 },
    ],
    zweck: 'Blitzerwarnung. Weckt zusätzlich die Bluetooth-Verbindung vor der Ansage.',
  },
  tempolimit: {
    art: 'tempolimit',
    // Ein einzelner, kürzerer Impuls. Bewusst unauffälliger als die
    // Blitzerwarnung, damit der Nutzer nicht abstumpft.
    impulse: [{ freq: 1200, dauerMs: 120, pauseMs: 0 }],
    zweck: 'Tempolimit überschritten. Kein Sprachhinweis, sonst stumpft der Nutzer ab.',
  },
  zone: {
    art: 'zone',
    // Ein einzelner, weicher, tiefer liegender Impuls. Er muss sich HÖRBAR
    // vom Blitzerton unterscheiden — ein Fahrer soll aus dem Klang nicht
    // schliessen können, dass es dieselbe Sache ist. Das ist Teil der
    // französischen Auflage, nicht Geschmack: Ein identischer Ton wäre ein
    // unmittelbarer Hinweis auf eine Messstelle, nur ohne Worte.
    impulse: [{ freq: 950, dauerMs: 220, pauseMs: 0 }],
    zweck: 'Eintritt in einen Gefahrenbereich (Zonenmodus, Frankreich).',
  },
  system: {
    art: 'system',
    // Drei Impulse, absteigend — klingt nach Störung, nicht nach Warnung.
    // Gesamtdauer 460 ms — die Vorgabe "unter 500 ms" gilt auch hier, weil
    // dem Systemton eine Ansage folgt ("Warnung inaktiv").
    impulse: [
      { freq: 1400, dauerMs: 90, pauseMs: 60 },
      { freq: 1100, dauerMs: 90, pauseMs: 60 },
      { freq: 800, dauerMs: 160, pauseMs: 0 },
    ],
    zweck: 'Systemwarnung, vor allem der Watchdog ("Warnung inaktiv").',
  },
};

/** Gesamtdauer eines Tons in ms. */
export function dauerMs(def: TonDefinition): number {
  return def.impulse.reduce((n, i) => n + i.dauerMs + i.pauseMs, 0);
}

/**
 * Hüllkurve gegen Knacken.
 *
 * Ein Sinus, der abrupt bei Amplitude 1 beginnt, erzeugt einen hörbaren
 * Knack — ein Sprung im Signal ist breitbandig. Deshalb wird über wenige
 * Millisekunden ein- und ausgeblendet.
 */
function huellkurve(position: number, laenge: number, rampenLaenge: number): number {
  if (position < rampenLaenge) return position / rampenLaenge;
  const vonHinten = laenge - position;
  if (vonHinten < rampenLaenge) return vonHinten / rampenLaenge;
  return 1;
}

/** Die Samples eines Tons als Float im Bereich -1..1. */
export function erzeugeSamples(def: TonDefinition, sampleRate = SAMPLE_RATE): Float32Array {
  const gesamtSamples = Math.round((dauerMs(def) / 1000) * sampleRate);
  const samples = new Float32Array(gesamtSamples);
  const rampe = Math.round(0.004 * sampleRate); // 4 ms

  let offset = 0;
  for (const impuls of def.impulse) {
    const n = Math.round((impuls.dauerMs / 1000) * sampleRate);
    for (let i = 0; i < n && offset + i < gesamtSamples; i++) {
      const t = i / sampleRate;
      const grund = Math.sin(2 * Math.PI * impuls.freq * t);
      // Eine leise Oktave darüber macht den Ton durchdringender, ohne ihn
      // schrill zu machen.
      const oberton = 0.25 * Math.sin(2 * Math.PI * impuls.freq * 2 * t);
      samples[offset + i] = (grund + oberton) / 1.25 * huellkurve(i, n, rampe);
    }
    offset += n + Math.round((impuls.pauseMs / 1000) * sampleRate);
  }

  return samples;
}

/**
 * WAV-Datei als Bytes (PCM, 16 bit, mono).
 *
 * WAV statt AAC, weil die Dateien sehr kurz sind (unter 500 ms, also wenige
 * Dutzend Kilobyte) und ein unkomprimiertes Format ohne Decoder-Latenz
 * abspielt. Bei einem Warnton zählt der Anfang.
 */
export function alsWav(def: TonDefinition, sampleRate = SAMPLE_RATE): Uint8Array {
  const samples = erzeugeSamples(def, sampleRate);
  const datenBytes = samples.length * 2;
  const puffer = new ArrayBuffer(44 + datenBytes);
  const view = new DataView(puffer);

  const schreibeText = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i++) view.setUint8(offset + i, text.charCodeAt(i));
  };

  schreibeText(0, 'RIFF');
  view.setUint32(4, 36 + datenBytes, true);
  schreibeText(8, 'WAVE');
  schreibeText(12, 'fmt ');
  view.setUint32(16, 16, true);        // Grösse des fmt-Blocks
  view.setUint16(20, 1, true);         // PCM
  view.setUint16(22, 1, true);         // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); // Bytes pro Sekunde
  view.setUint16(32, 2, true);         // Bytes pro Frame
  view.setUint16(34, 16, true);        // Bits pro Sample
  schreibeText(36, 'data');
  view.setUint32(40, datenBytes, true);

  for (let i = 0; i < samples.length; i++) {
    // Auf -1..1 begrenzen, bevor skaliert wird — sonst kippt der Wert um.
    const s = Math.max(-1, Math.min(1, samples[i]!));
    view.setInt16(44 + i * 2, Math.round(s * 32767), true);
  }

  return new Uint8Array(puffer);
}

/** WAV als base64, wie es expo-av als Datenquelle annimmt. */
export function alsBase64(def: TonDefinition, sampleRate = SAMPLE_RATE): string {
  const bytes = alsWav(def, sampleRate);
  let binaer = '';
  for (let i = 0; i < bytes.length; i++) binaer += String.fromCharCode(bytes[i]!);
  // btoa existiert in Hermes und in Node ab 16.
  return typeof btoa === 'function'
    ? btoa(binaer)
    : Buffer.from(bytes).toString('base64');
}
