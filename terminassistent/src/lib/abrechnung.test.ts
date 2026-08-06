import assert from 'node:assert/strict';
import { test } from 'node:test';
import { FREIE_VORGAENGE, pruefeSchranke, zeigeHinweis } from './abrechnung';

test('Die ersten fuenf Vorgaenge sind frei', () => {
  for (let n = 0; n < FREIE_VORGAENGE; n++) {
    const schranke = pruefeSchranke({ abgeschlosseneVorgaenge: n, zahlendSeit: null });
    assert.equal(schranke.erlaubt, true, `bei ${n} abgeschlossenen Vorgaengen`);
    assert.equal(schranke.verbleibend, FREIE_VORGAENGE - n);
  }
});

test('Der sechste Vorgang ist der Moment der Bezahlaufforderung', () => {
  // Nicht frueher: erst wenn der Nutzen fuenfmal nachweisbar war.
  const schranke = pruefeSchranke({ abgeschlosseneVorgaenge: 5, zahlendSeit: null });
  assert.equal(schranke.erlaubt, false);
  assert.equal(schranke.verbleibend, 0);
  assert.match(schranke.grund ?? '', /kostenlos/);
});

test('Wer zahlt, hat keine Grenze', () => {
  const schranke = pruefeSchranke({
    abgeschlosseneVorgaenge: 900,
    zahlendSeit: new Date('2026-01-01'),
  });
  assert.equal(schranke.erlaubt, true);
  assert.equal(schranke.verbleibend, Number.POSITIVE_INFINITY);
});

test('Ein ueberzaehlter Stand sperrt trotzdem nur, statt negativ zu werden', () => {
  // Kann durch gleichzeitige Vorgaenge entstehen; darf keine kaputte
  // Anzeige wie "-2 verbleibend" erzeugen.
  const schranke = pruefeSchranke({ abgeschlosseneVorgaenge: 7, zahlendSeit: null });
  assert.equal(schranke.erlaubt, false);
  assert.equal(schranke.verbleibend, 0);
});

test('Der Hinweis kommt spaet, nicht beim ersten Ergebnis', () => {
  assert.equal(zeigeHinweis({ abgeschlosseneVorgaenge: 0, zahlendSeit: null }), null);
  assert.equal(zeigeHinweis({ abgeschlosseneVorgaenge: 2, zahlendSeit: null }), null);
  assert.match(
    zeigeHinweis({ abgeschlosseneVorgaenge: 3, zahlendSeit: null }) ?? '',
    /Noch 2 kostenlose/,
  );
  assert.match(
    zeigeHinweis({ abgeschlosseneVorgaenge: 4, zahlendSeit: null }) ?? '',
    /Noch ein kostenloser/,
  );
  assert.match(
    zeigeHinweis({ abgeschlosseneVorgaenge: 5, zahlendSeit: null }) ?? '',
    /aufgebraucht/,
  );
});

test('Zahlende sehen keinen Hinweis', () => {
  assert.equal(
    zeigeHinweis({ abgeschlosseneVorgaenge: 4, zahlendSeit: new Date() }),
    null,
  );
});
