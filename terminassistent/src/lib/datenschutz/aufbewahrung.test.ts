import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  FRISTEN,
  kontoStand,
  protokollLoeschreif,
  protokollWortlautReif,
  tokenLoeschreif,
  verbindungLoeschreif,
  vorgangLoeschreif,
} from './aufbewahrung';

const JETZT = new Date('2026-08-06T12:00:00Z');
const vorTagen = (tage: number) => new Date(JETZT.getTime() - tage * 86_400_000);
const inTagen = (tage: number) => new Date(JETZT.getTime() + tage * 86_400_000);

test('Ein eingeloester Anmelde-Token verschwindet am Tag danach', () => {
  assert.equal(
    tokenLoeschreif({ gueltigBis: vorTagen(3), eingeloestAm: vorTagen(2) }, JETZT),
    true,
  );
  assert.equal(
    tokenLoeschreif({ gueltigBis: inTagen(1), eingeloestAm: null }, JETZT),
    false,
    'ein gueltiger Token bleibt',
  );
  assert.equal(
    tokenLoeschreif({ gueltigBis: vorTagen(2), eingeloestAm: null }, JETZT),
    true,
    'abgelaufen zaehlt wie eingeloest',
  );
});

test('Ein abgeschlossener Vorgang verschwindet nach der Frist', () => {
  const alt = { zustand: 'erledigt', geaendertAm: vorTagen(120), faelligAm: null };
  assert.equal(vorgangLoeschreif(alt, JETZT), true);

  assert.equal(
    vorgangLoeschreif({ ...alt, geaendertAm: vorTagen(10) }, JETZT),
    false,
    'frisch abgeschlossen bleibt',
  );
  assert.equal(
    vorgangLoeschreif({ ...alt, zustand: 'warte_auf_andere' }, JETZT),
    false,
    'was noch laeuft, wird nicht geloescht',
  );
});

test('Ein Vorgang mit einer Frist in der Zukunft bleibt, egal wie alt er ist', () => {
  // Eine Verordnung kann ein Jahr im Voraus eingetragen sein. Verschwindet
  // der Vorgang, kann die Nutzerin nicht mehr nachsehen, woher der Termin
  // in ihrem Kalender kommt.
  assert.equal(
    vorgangLoeschreif(
      { zustand: 'erledigt', geaendertAm: vorTagen(300), faelligAm: inTagen(30) },
      JETZT,
    ),
    false,
  );
  // Ist die Frist vorbei, greift die normale Regel wieder.
  assert.equal(
    vorgangLoeschreif(
      { zustand: 'erledigt', geaendertAm: vorTagen(300), faelligAm: vorTagen(30) },
      JETZT,
    ),
    true,
  );
});

test('Das Protokoll verliert erst den Wortlaut, dann den Eintrag', () => {
  const mittelalt = { zeitpunkt: vorTagen(100), details: 'Sehr geehrte Frau Berger, ...' };
  assert.equal(protokollWortlautReif(mittelalt, JETZT), true);
  assert.equal(protokollLoeschreif(mittelalt, JETZT), false, 'der Eintrag bleibt noch');

  const sehrAlt = { zeitpunkt: vorTagen(200), details: null };
  assert.equal(protokollLoeschreif(sehrAlt, JETZT), true);

  // Ohne Wortlaut gibt es nichts mehr zu entfernen — sonst schriebe der
  // Takt dieselbe Zeile jede Minute erneut.
  assert.equal(protokollWortlautReif({ zeitpunkt: vorTagen(200), details: null }, JETZT), false);

  assert.ok(
    FRISTEN.protokollWortlautTage < FRISTEN.protokollTage,
    'sonst waere die erste Stufe wirkungslos',
  );
});

test('Eine widerrufene Verbindung verschwindet, eine bestehende nie', () => {
  assert.equal(verbindungLoeschreif({ widerrufenAm: vorTagen(40) }, JETZT), true);
  assert.equal(verbindungLoeschreif({ widerrufenAm: vorTagen(5) }, JETZT), false);
  assert.equal(verbindungLoeschreif({ widerrufenAm: null }, JETZT), false);
});

test('Ruhende Konten werden erst gewarnt, dann geloescht — zahlende nie', () => {
  const frei = { zahlendSeit: null };
  assert.equal(kontoStand(frei, vorTagen(10), JETZT), 'aktiv');
  assert.equal(kontoStand(frei, vorTagen(710), JETZT), 'vorwarnen');
  assert.equal(kontoStand(frei, vorTagen(800), JETZT), 'loeschreif');

  // Ein Konto unter der Hand zu loeschen, fuer das jemand zahlt, waere ein
  // Fehler mit Ansage.
  assert.equal(kontoStand({ zahlendSeit: vorTagen(900) }, vorTagen(800), JETZT), 'aktiv');

  assert.ok(
    FRISTEN.kontoVorwarnungTage < FRISTEN.kontoRuhendTage,
    'die Vorwarnung muss vor der Loeschung liegen',
  );
});
