import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  automatikErlaubtFuer,
  darfAutomatischSenden,
  naechsterZustand,
  wartetAufNutzerin,
  zeigeAutomatikAngebot,
} from './zustand';

test('Eine neue Mail erzeugt einen Entwurf, wenn nichts unklar ist', () => {
  const u = naechsterZustand('neu', { art: 'mail_eingegangen', braucht_rueckfrage: false });
  assert.equal(u.zustand, 'neu');
  assert.equal(u.wirkung, 'entwurf_erzeugen');
});

test('Bei unklarer Analyse wird kein Entwurf erzeugt', () => {
  // Geringes Vertrauen heisst nachfragen, nicht raten.
  const u = naechsterZustand('neu', { art: 'mail_eingegangen', braucht_rueckfrage: true });
  assert.equal(u.wirkung, undefined);
});

test('Ohne Freigabe wartet der Entwurf auf einen Klick', () => {
  const u = naechsterZustand('neu', { art: 'entwurf_bereit', darf_automatisch: false });
  assert.equal(u.zustand, 'warte_auf_mich');
  assert.equal(u.wirkung, undefined);
  assert.equal(wartetAufNutzerin(u.zustand), true);
});

test('Mit Freigabe geht der Entwurf direkt in die Haltezeit, nicht sofort raus', () => {
  // Auch die Automatik sendet nicht sofort: die 60 Sekunden gelten immer.
  const u = naechsterZustand('neu', { art: 'entwurf_bereit', darf_automatisch: true });
  assert.equal(u.zustand, 'gehalten');
  assert.equal(u.wirkung, 'in_ausgang_legen');
});

test('Senden fuehrt ueber die Haltezeit, nie direkt in den Versand', () => {
  const u = naechsterZustand('warte_auf_mich', { art: 'senden_ausgeloest' });
  assert.equal(u.zustand, 'gehalten');
  assert.equal(u.wirkung, 'in_ausgang_legen');
});

test('Abbruch waehrend der Haltezeit gibt den Vorgang zurueck an die Nutzerin', () => {
  const u = naechsterZustand('gehalten', { art: 'haltezeit_abgebrochen' });
  assert.equal(u.zustand, 'warte_auf_mich');
});

test('Abbruch ausserhalb der Haltezeit tut nichts', () => {
  assert.equal(
    naechsterZustand('warte_auf_andere', { art: 'haltezeit_abgebrochen' }).zustand,
    'warte_auf_andere',
  );
});

test('Nach dem Versand wird auf die Gegenseite gewartet', () => {
  assert.equal(naechsterZustand('gehalten', { art: 'versandt' }).zustand, 'warte_auf_andere');
});

test('Eine Zusage fuehrt zum Kalendereintrag, nicht direkt zu erledigt', () => {
  const u = naechsterZustand('warte_auf_andere', {
    art: 'antwort_eingegangen',
    ist_zusage: true,
  });
  assert.equal(u.wirkung, 'termin_eintragen');
});

test('Eine Absage oeffnet eine neue Runde', () => {
  const u = naechsterZustand('warte_auf_andere', {
    art: 'antwort_eingegangen',
    ist_zusage: false,
  });
  assert.equal(u.zustand, 'neu');
  assert.equal(u.wirkung, 'entwurf_erzeugen');
});

test('Ein Fristeintrag braucht keinen Klick und ist danach erledigt', () => {
  // Kalendereintraege sind umkehrbar und verlassen das System nicht.
  const u = naechsterZustand('neu', { art: 'frist_eingetragen' });
  assert.equal(u.zustand, 'erledigt');
  assert.equal(u.wirkung, undefined);
});

test('Erinnerungen greifen nur, solange auf die Gegenseite gewartet wird', () => {
  assert.equal(
    naechsterZustand('warte_auf_mich', { art: 'erinnerung_faellig', darf_automatisch: true })
      .zustand,
    'warte_auf_mich',
  );
  assert.equal(
    naechsterZustand('warte_auf_andere', { art: 'erinnerung_faellig', darf_automatisch: true })
      .zustand,
    'gehalten',
  );
});

test('Ein abgeschlossener Vorgang wird nur von einer neuen Mail geweckt', () => {
  assert.equal(naechsterZustand('erledigt', { art: 'senden_ausgeloest' }).zustand, 'erledigt');
  assert.equal(
    naechsterZustand('erledigt', { art: 'mail_eingegangen', braucht_rueckfrage: false }).zustand,
    'neu',
  );
});

test('Fehler landen oben auf dem Bildschirm', () => {
  const u = naechsterZustand('warte_auf_andere', { art: 'fehlgeschlagen' });
  assert.equal(u.zustand, 'fehler');
  assert.equal(wartetAufNutzerin(u.zustand), true);
});

// ---------------------------------------------------------------------------

test('Die Automatik wird erst nach drei bestaetigten Sendungen angeboten', () => {
  assert.equal(zeigeAutomatikAngebot({ bestaetigteSendungen: 0, automatisch: false }), false);
  assert.equal(zeigeAutomatikAngebot({ bestaetigteSendungen: 2, automatisch: false }), false);
  assert.equal(zeigeAutomatikAngebot({ bestaetigteSendungen: 3, automatisch: false }), true);
});

test('Angeboten ist nicht eingeschaltet', () => {
  // Drei Bestaetigungen erzeugen ein Angebot, keine Freigabe. Erst die
  // ausdrueckliche Zustimmung setzt automatisch auf true.
  const nachDrei = { bestaetigteSendungen: 3, automatisch: false };
  assert.equal(zeigeAutomatikAngebot(nachDrei), true);
  assert.equal(darfAutomatischSenden(nachDrei), false);

  const nachZustimmung = { bestaetigteSendungen: 3, automatisch: true };
  assert.equal(zeigeAutomatikAngebot(nachZustimmung), false);
  assert.equal(darfAutomatischSenden(nachZustimmung), true);
});

test('Ohne Regel gibt es keine Automatik', () => {
  assert.equal(darfAutomatischSenden(null), false);
  assert.equal(zeigeAutomatikAngebot(undefined), false);
});

test('Automatik gibt es nur beim Nachfassen', () => {
  // Ein falsches Nachfassen nervt. Ein falscher Termin kostet einen
  // Ausfalltermin — dafuer gibt es keine Automatik, nie.
  assert.equal(automatikErlaubtFuer('nachfassen'), true);
  assert.equal(automatikErlaubtFuer('termin'), false);
  assert.equal(automatikErlaubtFuer('frist'), false);
});
