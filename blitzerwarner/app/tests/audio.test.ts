import { test } from 'node:test';
import assert from 'node:assert/strict';

import { AUDIO } from '../src/config';
import { TOENE, alsWav, dauerMs, erzeugeSamples } from '../src/audio/tone';
import { ansageText, landwechselText, rundeEntfernung, sprechrate, zahlAlsWort } from '../src/audio/announce';
import type { Camera } from '../src/types';

const kamera = (extra: Partial<Camera> = {}): Camera => ({
  lat: 48.77, lon: 9.18, dir: null, max: null, type: 'speed', ...extra,
});

// --- Warnton --------------------------------------------------------------

test('es gibt genau vier Töne', () => {
  // Die Qualitätsvorgabe nennt drei. Der vierte ist der Zonenton, und er ist
  // eine bewusste Ausnahme: Er MUSS sich vom Blitzerton unterscheiden, weil
  // ein identischer Ton in Frankreich ein unmittelbarer Hinweis auf eine
  // Messstelle wäre — nur ohne Worte. Ein fünfter braucht wieder eine
  // Begründung.
  assert.deepEqual(Object.keys(TOENE).sort(), ['blitzer', 'system', 'tempolimit', 'zone']);
});

test('alle Töne liegen im hörbaren Nutzbereich 1 bis 3 kHz', () => {
  // Tieffrequentes geht im Fahrgeräusch unter. Der Systemton darf tiefer
  // beginnen, weil er nach Störung klingen soll, aber nicht unter 800 Hz.
  for (const def of Object.values(TOENE)) {
    for (const i of def.impulse) {
      assert.ok(i.freq >= 800 && i.freq <= 3000, `${def.art}: ${i.freq} Hz`);
    }
  }
});

test('alle Töne bleiben unter 500 ms', () => {
  // Ein längerer Ton verzögert die Ansage und nervt.
  for (const def of Object.values(TOENE)) {
    assert.ok(dauerMs(def) < 500, `${def.art}: ${dauerMs(def)} ms`);
  }
});

test('jedes Tonpaar ist unterscheidbar', () => {
  // Zwei Töne gelten als unterscheidbar, wenn sie sich in der Impulszahl ODER
  // deutlich in der Frequenz unterscheiden. Beides zu verlangen geht bei vier
  // Tönen nicht auf — tempolimit und zone haben beide einen Impuls und
  // trennen sich über 250 Hz Abstand.
  const arten = Object.keys(TOENE) as (keyof typeof TOENE)[];
  for (let i = 0; i < arten.length; i++) {
    for (let j = i + 1; j < arten.length; j++) {
      const a = TOENE[arten[i]!], b = TOENE[arten[j]!];
      const impulseUnterschiedlich = a.impulse.length !== b.impulse.length;
      const minAbstand = Math.min(
        ...a.impulse.flatMap((ia) => b.impulse.map((ib) => Math.abs(ia.freq - ib.freq))),
      );
      assert.ok(
        impulseUnterschiedlich || minAbstand >= 200,
        `${a.art} und ${b.art}: gleiche Impulszahl und nur ${minAbstand} Hz Abstand`,
      );
    }
  }
});

test('Samples bleiben im Bereich -1..1', () => {
  // Übersteuerung klingt nach kaputtem Lautsprecher.
  for (const def of Object.values(TOENE)) {
    const s = erzeugeSamples(def);
    for (let i = 0; i < s.length; i++) {
      assert.ok(s[i]! >= -1.001 && s[i]! <= 1.001, `${def.art} bei ${i}: ${s[i]}`);
    }
  }
});

test('Hüllkurve verhindert Knacken am Anfang und Ende', () => {
  // Ein Sinus, der abrupt bei Amplitude 1 startet, knackt hörbar.
  const s = erzeugeSamples(TOENE.blitzer);
  assert.ok(Math.abs(s[0]!) < 0.05, `Start bei ${s[0]}`);
  assert.ok(Math.abs(s[s.length - 1]!) < 0.05, `Ende bei ${s[s.length - 1]}`);
});

test('WAV-Kopf ist korrekt', () => {
  const wav = alsWav(TOENE.blitzer);
  const text = (von: number, laenge: number) =>
    String.fromCharCode(...Array.from(wav.slice(von, von + laenge)));

  assert.equal(text(0, 4), 'RIFF');
  assert.equal(text(8, 4), 'WAVE');
  assert.equal(text(12, 4), 'fmt ');
  assert.equal(text(36, 4), 'data');

  const view = new DataView(wav.buffer, wav.byteOffset, wav.byteLength);
  assert.equal(view.getUint16(20, true), 1, 'PCM');
  assert.equal(view.getUint16(22, true), 1, 'mono');
  assert.equal(view.getUint32(24, true), 44100, 'Samplerate');
  assert.equal(view.getUint16(34, true), 16, 'Bits pro Sample');

  // Die im Kopf angegebenen Grössen müssen zur Datei passen.
  assert.equal(view.getUint32(4, true), wav.length - 8);
  assert.equal(view.getUint32(40, true), wav.length - 44);
});

test('WAV-Länge passt zur Tondauer', () => {
  const def = TOENE.blitzer;
  const wav = alsWav(def);
  const samples = (wav.length - 44) / 2;
  const erwartet = (dauerMs(def) / 1000) * 44100;
  assert.ok(Math.abs(samples - erwartet) < 10, `${samples} statt ~${erwartet}`);
});

// --- zahlAlsWort ----------------------------------------------------------

test('zahlAlsWort: Entfernungen', () => {
  assert.equal(zahlAlsWort(50), 'fünfzig');
  assert.equal(zahlAlsWort(100), 'einhundert');
  assert.equal(zahlAlsWort(200), 'zweihundert');
  assert.equal(zahlAlsWort(300), 'dreihundert');
  assert.equal(zahlAlsWort(400), 'vierhundert');
  assert.equal(zahlAlsWort(500), 'fünfhundert');
  assert.equal(zahlAlsWort(550), 'fünfhundertfünfzig');
});

test('zahlAlsWort: Tempolimits', () => {
  assert.equal(zahlAlsWort(30), 'dreißig');
  assert.equal(zahlAlsWort(50), 'fünfzig');
  assert.equal(zahlAlsWort(70), 'siebzig');
  assert.equal(zahlAlsWort(80), 'achtzig');
  assert.equal(zahlAlsWort(100), 'einhundert');
  assert.equal(zahlAlsWort(120), 'einhundertzwanzig');
  assert.equal(zahlAlsWort(130), 'einhundertdreißig');
});

test('zahlAlsWort: die deutsche Einer-vor-Zehner-Eigenheit', () => {
  assert.equal(zahlAlsWort(21), 'einundzwanzig');
  assert.equal(zahlAlsWort(45), 'fünfundvierzig');
  assert.equal(zahlAlsWort(99), 'neunundneunzig');
});

test('zahlAlsWort: kleine Zahlen und Null', () => {
  assert.equal(zahlAlsWort(0), 'null');
  assert.equal(zahlAlsWort(1), 'eins');
  assert.equal(zahlAlsWort(11), 'elf');
  assert.equal(zahlAlsWort(19), 'neunzehn');
});

test('zahlAlsWort: aussergewöhnliche Eingaben fallen auf Ziffern zurück', () => {
  // Lieber hölzern gelesen als falsch.
  assert.equal(zahlAlsWort(-5), '-5');
  assert.equal(zahlAlsWort(1.5), '1.5');
  assert.equal(zahlAlsWort(5000), '5000');
});

// --- Entfernung runden ----------------------------------------------------

test('rundeEntfernung: auf 50 m über 100 m', () => {
  assert.equal(rundeEntfernung(322), 300);
  assert.equal(rundeEntfernung(333), 350);
  assert.equal(rundeEntfernung(530), 550);
});

test('rundeEntfernung: auf 10 m unter 100 m, nie unter 10', () => {
  assert.equal(rundeEntfernung(84), 80);
  assert.equal(rundeEntfernung(12), 10);
  assert.equal(rundeEntfernung(3), 10, 'nie "null Meter" ansagen');
});

// --- Ansagetext -----------------------------------------------------------

test('ansageText: mit Tempolimit', () => {
  assert.equal(ansageText(kamera({ max: 80 }), 400), 'Blitzer, vierhundert Meter, Tempo achtzig');
});

test('ansageText: ohne Tempolimit kein Geplapper', () => {
  // 64 Prozent der Anlagen haben kein maxspeed. Da darf nichts erfunden werden.
  assert.equal(ansageText(kamera({ max: null }), 400), 'Blitzer, vierhundert Meter');
});

test('ansageText: Rotlichtblitzer wird benannt', () => {
  const t = ansageText(kamera({ type: 'red_light' }), 200);
  assert.equal(t, 'Rotlichtblitzer, zweihundert Meter');
});

test('ansageText: kombinierte Anlage nennt beides', () => {
  const t = ansageText(kamera({ type: 'both', max: 50 }), 300);
  assert.ok(t.includes('Rotlicht'), t);
  assert.ok(t.includes('Tempo fünfzig'), t);
});

test('ansageText: keine Begrüssung, kein Ausrufezeichen', () => {
  for (const c of [kamera({ max: 80 }), kamera({ type: 'red_light' }), kamera()]) {
    const t = ansageText(c, 400);
    assert.ok(!t.includes('!'), t);
    assert.ok(!/achtung|bitte|hallo/i.test(t), t);
  }
});

test('sprechrate: schneller nur bei hohem Tempo', () => {
  assert.equal(sprechrate(100), 1);
  assert.equal(sprechrate(null), 1);
  assert.equal(sprechrate(AUDIO.FAST_SPEECH_ABOVE_KMH + 10), AUDIO.FAST_SPEECH_RATE);
});

test('landwechselText', () => {
  assert.equal(landwechselText(true), 'Blitzerwarnung aktiviert');
  assert.equal(landwechselText(false), 'Blitzerwarnung deaktiviert');
});

test('der Zonenton unterscheidet sich hörbar vom Blitzerton', () => {
  // Nicht kosmetisch: Ein Fahrer soll aus dem Klang nicht schliessen können,
  // dass es dieselbe Sache ist. Geprüft wird beides — Impulszahl UND
  // Frequenzabstand, weil eine Übereinstimmung in einem der beiden reicht,
  // damit die Töne verwechselbar werden.
  const zone = TOENE.zone;
  const blitzer = TOENE.blitzer;

  assert.notEqual(zone.impulse.length, blitzer.impulse.length, 'gleiche Impulszahl');

  const zoneFreqs = zone.impulse.map((i) => i.freq);
  const blitzerFreqs = blitzer.impulse.map((i) => i.freq);
  for (const zf of zoneFreqs) {
    for (const bf of blitzerFreqs) {
      assert.ok(
        Math.abs(zf - bf) > 200,
        `Zonenton ${zf} Hz liegt zu nah an Blitzerton ${bf} Hz`,
      );
    }
  }
});
