/**
 * Das Länder-Gate. Der Test, der über Bussgeld oder nicht entscheidet.
 *
 * Die wichtigste Prüfung hier ist die Invariante aus B.1:
 * `status !== 'belegt'` erzwingt `modus: 'aus'`. Ein Land, dessen Rechtslage
 * nicht belegt ist, warnt nicht.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { LAENDER_GATE, type LandCode } from '../src/config';
import { landHinweis, warnmodus, warnungErlaubt } from '../src/core/country';

const EINTRAEGE = Object.entries(LAENDER_GATE.LAENDER) as [LandCode, typeof LAENDER_GATE.LAENDER[LandCode]][];

test('DIE INVARIANTE: nur belegte Rechtslage darf warnen', () => {
  for (const [code, e] of EINTRAEGE) {
    if (e.status !== 'belegt') {
      assert.equal(
        e.modus, 'aus',
        `${code} hat status '${e.status}' und modus '${e.modus}' — nicht belegt heisst nicht warnen`,
      );
    }
  }
});

test('warnmodus() setzt die Invariante durch, auch gegen die Tabelle', () => {
  // Nicht bloss in der Tabelle vorausgesetzt, sondern in der Funktion
  // erzwungen: Ein neuer Eintrag mit vergessenem modus 'aus' darf nicht
  // durchrutschen.
  for (const [code, e] of EINTRAEGE) {
    const modus = warnmodus(code);
    if (e.status !== 'belegt') assert.equal(modus, 'aus', code);
    else assert.equal(modus, e.modus, code);
  }
});

test('jeder Eintrag hat eine Begründung und einen Hinweistext', () => {
  for (const [code, e] of EINTRAEGE) {
    assert.ok(e.grund.length > 10, `${code}: grund zu kurz`);
    assert.ok(e.hinweis.length > 20, `${code}: hinweis zu kurz`);
  }
});

test('Quelle und Stand sind angegeben', () => {
  assert.match(LAENDER_GATE.QUELLE, /ADAC/);
  assert.match(LAENDER_GATE.QUELLE, /ohne Gewähr/);
  assert.match(LAENDER_GATE.STAND, /^\d{4}-\d{2}$/);
});

test('unbekanntes Land warnt nicht', () => {
  // Der sichere Standard. Der eine Fehler kostet eine Funktion, der andere
  // ein Bussgeld.
  assert.equal(LAENDER_GATE.FALLBACK_WARNUNG_ERLAUBT, false);
  assert.equal(warnmodus(null), 'aus');
  assert.equal(warnungErlaubt(null), false);
  assert.equal(landHinweis(null), null);
});

test('Deutschland, Schweiz und Österreich warnen nicht', () => {
  for (const code of ['DE', 'CH', 'AT'] as const) {
    assert.equal(warnmodus(code), 'aus', code);
    assert.equal(warnungErlaubt(code), false, code);
    assert.equal(LAENDER_GATE.LAENDER[code].hinweisBanner, true, `${code} braucht den Banner`);
  }
});

test('Österreich ist als strittig geführt, nicht als belegt', () => {
  // Die Quellen widersprechen sich: bisheriger Projekteintrag sagt verboten,
  // der ADAC beschreibt POI-Warner als erlaubt. Das aufzulösen braucht den
  // Gesetzestext. Bis dahin sichtbar offen halten statt entscheiden.
  const at = LAENDER_GATE.LAENDER.AT;
  assert.equal(at.status, 'strittig');
  assert.equal(at.modus, 'aus');
  assert.match(at.grund, /WIDERSPRUCH/);
  assert.match(at.grund, /98a KFG/);
  assert.match(at.grund, /ADAC/);
  // Der Hinweis darf nicht behaupten, es sei verboten — nur, dass es unklar ist.
  assert.match(at.hinweis, /nicht geklärt|widersprechen/);
});

test('Frankreich läuft im Zonenmodus, nicht mit Punktwarnung', () => {
  // Der teuerste Fehler im Projekt, gemessen in Euro: bis 1500 Euro und
  // Einziehung des Geräts. Punktwarnung ist dort seit 03.01.2012 verboten.
  const fr = LAENDER_GATE.LAENDER.FR;
  assert.equal(fr.status, 'belegt');
  assert.equal(fr.modus, 'zone');
  assert.equal(warnmodus('FR'), 'zone');
  assert.equal(warnungErlaubt('FR'), true, 'gewarnt wird schon, nur anders');
  assert.match(fr.grund, /2012/);
  assert.match(fr.grund, /Gefahrenzonen|Gefahrenzone/);
});

test('kein Land warnt punktgenau, ohne dass die Quelle es hergibt', () => {
  const punktLaender = EINTRAEGE.filter(([, e]) => e.modus === 'punkt').map(([c]) => c);
  // Genau die acht Länder, für die die Quelle die POI-Funktion ausdrücklich
  // erlaubt. Wächst diese Liste, muss jemand die Quelle nachgelesen haben.
  assert.deepEqual(
    [...punktLaender].sort(),
    ['BE', 'CZ', 'ES', 'FI', 'LU', 'NL', 'PT', 'RS'],
  );
  for (const code of punktLaender) {
    assert.equal(LAENDER_GATE.LAENDER[code].status, 'belegt', code);
  }
});

test('Länder mit Widerspruch benennen ihn, statt ihn aufzulösen', () => {
  for (const code of ['HR', 'RO', 'HU'] as const) {
    const e = LAENDER_GATE.LAENDER[code];
    assert.equal(e.status, 'unklar', code);
    assert.match(e.grund, /WIDERSPRÜCHLICH/, code);
  }
});

test('kein Hinweistext behauptet ein Verbot, wo nur Unklarheit besteht', () => {
  // Der Unterschied zählt: Die App soll nicht behaupten, was sie nicht weiss.
  for (const [code, e] of EINTRAEGE) {
    if (e.status !== 'unklar') continue;
    assert.match(
      e.hinweis, /nicht belegt/,
      `${code}: unklare Rechtslage muss als "nicht belegt" beschrieben werden`,
    );
    assert.ok(
      !/ist verboten|untersagt/.test(e.hinweis),
      `${code}: Hinweis behauptet ein Verbot, obwohl die Lage nur unklar ist`,
    );
  }
});

test('Zonenmodus gibt es nur, wo er auch begründet ist', () => {
  const zonen = EINTRAEGE.filter(([, e]) => e.modus === 'zone').map(([c]) => c);
  assert.deepEqual(zonen, ['FR'], 'Zonenmodus derzeit nur für Frankreich');
});
