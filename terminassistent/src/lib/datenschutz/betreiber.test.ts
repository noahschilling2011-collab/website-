import assert from 'node:assert/strict';
import { test } from 'node:test';
import { betreiber, betreiberVollstaendig, datenschutzGeprueft } from './betreiber';

function ohne(): void {
  delete process.env.BETREIBER_NAME;
  delete process.env.BETREIBER_ANSCHRIFT;
  delete process.env.BETREIBER_EMAIL;
  delete process.env.DATENSCHUTZ_GEPRUEFT;
}

test('Fehlende Betreiberangaben sind sichtbar, nicht still leer', () => {
  ohne();
  assert.match(betreiber.name, /nicht eingetragen/);
  assert.equal(betreiberVollstaendig(), false);
});

test('Der Warnkasten braucht BEIDES: Angaben und ausdrueckliche Bestaetigung', () => {
  ohne();
  assert.equal(datenschutzGeprueft(), false);

  process.env.BETREIBER_NAME = 'Katrin Weber';
  process.env.BETREIBER_ANSCHRIFT = 'Musterweg 1, 12345 Musterstadt';
  process.env.BETREIBER_EMAIL = 'katrin@praxis.test';
  assert.equal(
    datenschutzGeprueft(),
    false,
    'die Adresse auszufuellen ist keine anwaltliche Pruefung',
  );

  process.env.DATENSCHUTZ_GEPRUEFT = 'ja';
  assert.equal(datenschutzGeprueft(), true);

  // Nur genau "ja" zaehlt — sonst schaltete ein beliebiger gesetzter Wert
  // den Hinweis versehentlich ab.
  process.env.DATENSCHUTZ_GEPRUEFT = 'nein';
  assert.equal(datenschutzGeprueft(), false);
  process.env.DATENSCHUTZ_GEPRUEFT = 'true';
  assert.equal(datenschutzGeprueft(), false);

  ohne();
});
